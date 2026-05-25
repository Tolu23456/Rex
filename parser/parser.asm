; parser.asm - Recursive descent parsing subsystem
;
; Tracks variable declarations and enforces Rex V4.0 mutability rules:
;   int x          →  mutable, uninitialized
;   int x = 42     →  immutable constant  (error on subsequent :x = ...)
;   :x = 10        →  assignment to mutable var only
;   output x       →  print variable value via codegen_output_const
;
; Exports:
;   parse_stmt    — parse one statement; on entry tok_type already holds the
;                   first token of the statement; on return tok_type holds the
;                   first token of the NEXT statement (or TOK_NEWLINE/EOF).

global parse_stmt

extern lexer_next
extern tok_type
extern tok_int
extern tok_ident
extern codegen_output_const
extern codegen_emit_cmp_jne
extern codegen_patch_jump
extern codegen_save_chain_base
extern codegen_emit_jmp_end
extern codegen_patch_chain_end
extern codegen_output_loop_var
extern codegen_begin_protos
extern codegen_end_protos
extern codegen_emit_for_start
extern codegen_emit_for_end
extern codegen_emit_while_start
extern codegen_emit_while_end
extern codegen_save_break_base
extern codegen_emit_break
extern codegen_patch_breaks
extern codegen_emit_ret
extern codegen_emit_mov_eax_imm32
extern codegen_emit_call_prot
extern out_idx

%include "rex_defs.inc"

; ─── BSS ────────────────────────────────────────────────────────────────────
section .bss
    var_table:        resb VAR_ENTRY_SIZE * VAR_MAX  ; variable table
    var_count:        resq 1                          ; number of declared variables
    saved_name:       resb 64                         ; temp: save ident across lexer calls
    saved_is_loop_var: resb 1                         ; is_loop_var flag preserved across lexer calls

    ; Protocol table: 32 entries × 40 bytes (32-byte name + 8-byte buffer offset)
    proto_table:      resb 40 * 32
    proto_count:      resq 1    ; number of registered protocols
    prot_body_depth:  resq 1    ; >0 when parsing inside a prot body (guards codegen_end_protos)

; ─── DATA (error messages) ───────────────────────────────────────────────────
section .data
    err_const_reassign:  db "error: reassignment to immutable variable", 10
    err_const_reassign_len equ $ - err_const_reassign
    err_undef_var:       db "error: undefined variable", 10
    err_undef_var_len    equ $ - err_undef_var
    err_uninit_var:      db "error: use of uninitialized variable", 10
    err_uninit_var_len   equ $ - err_uninit_var
    err_expect_ident:    db "error: expected identifier", 10
    err_expect_ident_len equ $ - err_expect_ident
    err_expect_int:      db "error: expected integer literal", 10
    err_expect_int_len   equ $ - err_expect_int
    err_expect_assign:   db "error: expected '='", 10
    err_expect_assign_len equ $ - err_expect_assign
    err_expect_eqeq:     db "error: expected '=='", 10
    err_expect_eqeq_len  equ $ - err_expect_eqeq
    err_expect_in:       db "error: expected 'in'", 10
    err_expect_in_len    equ $ - err_expect_in
    err_expect_dotdot:   db "error: expected '..'", 10
    err_expect_dotdot_len equ $ - err_expect_dotdot
    err_undef_prot:      db "error: undefined protocol", 10
    err_undef_prot_len   equ $ - err_undef_prot

; ─── TEXT ────────────────────────────────────────────────────────────────────
section .text

; ── fatal_error ──────────────────────────────────────────────────────────────
; Write error message to stderr and exit with code 1.
; rsi = message ptr, rdx = length
fatal_error:
    mov  rax, 1             ; sys_write
    mov  rdi, 2             ; fd = stderr
    syscall
    mov  rax, 60            ; sys_exit
    mov  rdi, 1
    syscall

; ── strcpy_local ─────────────────────────────────────────────────────────────
; Copy null-terminated string from rsi → rdi.  Clobbers rax.
strcpy_local:
.loop:
    movzx eax, byte [rsi]
    mov  [rdi], al
    inc  rsi
    inc  rdi
    test al, al
    jnz  .loop
    ret

; ── var_find ─────────────────────────────────────────────────────────────────
; Find variable by name.
; rdi = pointer to null-terminated name
; Returns: rax = index (0-based) if found, -1 if not found
; Preserves: rbx, rcx, rdx, rsi, rdi, r8–r15
var_find:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    xor  rcx, rcx                       ; i = 0
.find_loop:
    cmp  rcx, [rel var_count]
    jge  .not_found

    ; address of var_table[i].name
    mov  rax, rcx
    imul rax, VAR_ENTRY_SIZE
    lea  rsi, [rel var_table]
    add  rsi, rax                       ; rsi = entry base (name is at offset 0)

    ; inline string compare: [rsi] vs [rdi]
    push rsi
    push rdi
    push rcx
.cmp_loop:
    movzx eax, byte [rdi]
    movzx edx, byte [rsi]
    cmp  al, dl
    jne  .cmp_ne
    test al, al
    jz   .cmp_eq
    inc  rdi
    inc  rsi
    jmp  .cmp_loop
.cmp_eq:
    pop  rcx
    pop  rdi
    pop  rsi
    ; Found
    mov  rax, rcx
    jmp  .find_done
.cmp_ne:
    pop  rcx
    pop  rdi
    pop  rsi
    inc  rcx
    jmp  .find_loop

.not_found:
    mov  rax, -1
.find_done:
    pop  rdi
    pop  rsi
    pop  rdx
    pop  rcx
    pop  rbx
    ret

; ── var_add ───────────────────────────────────────────────────────────────────
; Add a variable to the table.
; rdi = name ptr (null-terminated)
; rsi = initial value (qword)
; dl  = is_const (1 = immutable, 0 = mutable)
; dh  = is_initialized (1 = has value, 0 = uninitialized)
; Returns: rax = new index, or -1 if table full
var_add:
    push r12
    push r13
    push r14
    push rbx

    mov  r12, rdi           ; name ptr
    mov  r13, rsi           ; value
    movzx r14d, dl          ; is_const (is_initialized = is_const for new decls)

    mov  rbx, [rel var_count]
    cmp  rbx, VAR_MAX
    jge  .full

    ; Compute entry address: &var_table[var_count]
    mov  rax, rbx
    imul rax, VAR_ENTRY_SIZE
    lea  rdi, [rel var_table]
    add  rdi, rax           ; rdi = &entry

    ; Copy name (max 31 chars + null) into entry[0..31]
    mov  rsi, r12
    mov  ecx, 31
.copy_name:
    movzx eax, byte [rsi]
    mov  [rdi], al
    inc  rsi
    inc  rdi
    test al, al
    jz   .copy_done
    dec  ecx
    jnz  .copy_name
    mov  byte [rdi], 0      ; force null termination at byte 31
.copy_done:

    ; Re-derive entry base pointer for the remaining fields
    mov  rax, rbx
    imul rax, VAR_ENTRY_SIZE
    lea  rdi, [rel var_table]
    add  rdi, rax

    ; entry[32..39] = value
    mov  [rdi + 32], r13
    ; entry[40]     = is_const
    mov  byte [rdi + 40], r14b
    ; entry[41]     = is_initialized  (same as is_const for fresh declarations)
    mov  byte [rdi + 41], r14b

    inc  qword [rel var_count]
    mov  rax, rbx           ; return index

    pop  rbx
    pop  r14
    pop  r13
    pop  r12
    ret
.full:
    mov  rax, -1
    pop  rbx
    pop  r14
    pop  r13
    pop  r12
    ret

; ── parse_stmt ───────────────────────────────────────────────────────────────
; Called with tok_type already set to the first token of the statement.
; On return, tok_type holds the token immediately after the statement
; (typically TOK_NEWLINE, TOK_INDENT, TOK_DEDENT, or TOK_EOF).
parse_stmt:
    ; Read current token type first so we can guard on TOK_PROT below
    movzx eax, byte [rel tok_type]

    ; Patch the prot-skip jmp ONLY if this statement is NOT itself a prot definition
    ; and we are NOT inside a prot body.  Patching during a prot definition would
    ; redirect the jmp to mid-prot code instead of to the main program.
    cmp  al, TOK_PROT
    je   .stmt_skip_end_protos
    cmp  qword [rel prot_body_depth], 0
    jne  .stmt_skip_end_protos
    call codegen_end_protos
    movzx eax, byte [rel tok_type]   ; re-read: call may have clobbered eax
.stmt_skip_end_protos:

    cmp  al, TOK_TYPE_INT
    je   .parse_decl

    cmp  al, TOK_COLON
    je   .parse_assign

    cmp  al, TOK_OUTPUT
    je   .parse_output

    cmp  al, TOK_IF
    je   .parse_if

    cmp  al, TOK_FOR
    je   .parse_for

    cmp  al, TOK_WHILE
    je   .parse_while

    cmp  al, TOK_PROT
    je   .parse_prot

    cmp  al, TOK_RETURN
    je   .parse_return

    cmp  al, TOK_STOP
    je   .parse_stop

    cmp  al, TOK_AT
    je   .parse_at

    ; Unknown token at statement level — skip
    call lexer_next
    ret

; ─── int x [= value] ─────────────────────────────────────────────────────────
.parse_decl:
    ; Current: TOK_TYPE_INT  →  advance to identifier
    call lexer_next
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_IDENT
    jne  .err_expect_ident

    ; Save identifier name before next lexer_next overwrites tok_ident
    lea  rsi, [rel tok_ident]
    lea  rdi, [rel saved_name]
    call strcpy_local

    ; Advance: look for '=' (const) or end-of-statement (mutable)
    call lexer_next
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_ASSIGN
    je   .parse_const_decl

    ; ── Mutable declaration: int x  (no initializer) ─────────────────────────
    ; Register mutable, uninitialized variable
    lea  rdi, [rel saved_name]
    xor  rsi, rsi           ; value = 0
    mov  dl, 0              ; is_const = 0 (mutable, uninitialized)
    call var_add
    ; Current token is whatever came after the identifier (newline, EOF, …)
    ret

    ; ── Const declaration: int x = <value> ───────────────────────────────────
.parse_const_decl:
    call lexer_next
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_INT_LIT
    jne  .err_expect_int

    lea  rdi, [rel saved_name]
    mov  rsi, [rel tok_int]
    mov  dl, 1              ; is_const = 1 (initialized inline)
    call var_add

    call lexer_next         ; advance past the integer literal
    ret

; ─── :x = value ──────────────────────────────────────────────────────────────
.parse_assign:
    ; Current: TOK_COLON
    call lexer_next
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_IDENT
    jne  .err_expect_ident

    lea  rsi, [rel tok_ident]
    lea  rdi, [rel saved_name]
    call strcpy_local

    call lexer_next
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_ASSIGN
    jne  .err_expect_assign

    call lexer_next
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_INT_LIT
    jne  .err_expect_int

    ; Look up variable
    lea  rdi, [rel saved_name]
    call var_find
    cmp  rax, -1
    je   .err_undef_var

    ; Compute entry pointer
    push rax
    imul rax, VAR_ENTRY_SIZE
    lea  rcx, [rel var_table]
    add  rcx, rax           ; rcx = entry base

    ; Immutability check
    cmp  byte [rcx + 40], 1
    je   .err_const_reassign

    ; Update value and mark initialized
    mov  rax, [rel tok_int]
    mov  [rcx + 32], rax
    mov  byte [rcx + 41], 1

    pop  rax                ; discard saved index (already used rcx)
    call lexer_next         ; advance past integer literal
    ret

; ─── output <ident | int_lit> ────────────────────────────────────────────────
.parse_output:
    ; Current: TOK_OUTPUT
    call lexer_next
    movzx eax, byte [rel tok_type]

    ; Accept a bare integer literal: output 42
    cmp  al, TOK_INT_LIT
    je   .output_literal

    ; Otherwise must be an identifier: output x
    cmp  al, TOK_IDENT
    jne  .err_expect_ident

    lea  rdi, [rel tok_ident]
    call var_find
    cmp  rax, -1
    je   .err_undef_var

    ; Compute entry pointer
    imul rax, VAR_ENTRY_SIZE
    lea  rcx, [rel var_table]
    add  rcx, rax

    ; Check initialized
    cmp  byte [rcx + 41], 1
    jne  .err_uninit_var

    ; Check is_loop_var flag at byte[43] — loop counter already live in edi
    cmp  byte [rcx + 43], 1
    je   .output_loop_var

    ; Static variable: emit "mov edi, value; call rt_pri"
    mov  rdi, [rcx + 32]
    call codegen_output_const

    call lexer_next         ; advance past identifier
    ret

.output_loop_var:
    ; Loop variable: edi is already live; emit "push rdi; call rt_pri; pop rdi"
    call codegen_output_loop_var

    call lexer_next         ; advance past identifier
    ret

.output_literal:
    ; Emit code: call rt_pri with the literal value directly
    mov  rdi, [rel tok_int]
    call codegen_output_const
    call lexer_next         ; advance past integer literal
    ret

; ─── if / elif* / else? ───────────────────────────────────────────────────────
;
; Handles the complete if-elif*-else? chain in one single-pass descent.
;
; Register contract (callee-saved within parse_if stack frame):
;   r12 = variable value (LHS of ==) for the current branch
;   r13 = literal value  (RHS of ==) for the current branch
;
; Codegen stack protocol:
;   jump_patch_stack  — one JNE placeholder per live conditional branch
;   end_jump_stack    — one JMP placeholder per taken branch (skip to chain end)
;   chain_base_stack  — end_jump_depth snapshot at chain entry for bulk-patch
.parse_if:
    push r12
    push r13

    ; Snapshot end_jump_depth so codegen_patch_chain_end patches only our jumps
    call codegen_save_chain_base

    ; Advance past TOK_IF → first token of condition (identifier)
    call lexer_next

; ═══════════════════════════════════════════════════════════════════════════════
; .branch_parse_cond — shared entry for both 'if' and each 'elif' condition.
;   On arrival: tok = condition identifier (TOK_IDENT)
; ═══════════════════════════════════════════════════════════════════════════════
.branch_parse_cond:
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_IDENT
    jne  .if_err_ident

    ; Resolve variable → r12 = compile-time LHS value
    lea  rdi, [rel tok_ident]
    call var_find
    cmp  rax, -1
    je   .if_err_undef

    imul rax, VAR_ENTRY_SIZE
    lea  rcx, [rel var_table]
    add  rcx, rax
    mov  r12, [rcx + 32]            ; r12 = variable value (LHS)
    ; Save is_loop_var flag (byte[43]) for passing in rdx to codegen_emit_cmp_jne
    movzx rax, byte [rcx + 43]
    mov  [rel saved_is_loop_var], al

    ; Expect '=='
    call lexer_next
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_EQEQ
    jne  .if_err_eqeq

    ; Expect integer literal (RHS)
    call lexer_next
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_INT_LIT
    jne  .if_err_int

    mov  r13, [rel tok_int]         ; r13 = comparison value (RHS)

    ; Consume ':' → newline → INDENT → prime first body token
    call lexer_next                 ; int_lit  →  ':'
    call lexer_next                 ; ':'      →  newline
    call lexer_next                 ; newline  →  INDENT
    call lexer_next                 ; INDENT   →  first body token

    ; Emit cmp+JNE with placeholder (placeholder pushed onto jump_patch_stack)
    ; rdx = is_loop_var (1 = skip "mov edi, val" since edi is already live)
    movzx rdx, byte [rel saved_is_loop_var]
    mov  rdi, r12
    mov  rsi, r13
    call codegen_emit_cmp_jne

    ; ── Branch body loop: parse statements until DEDENT or EOF ────────────────
.branch_body_loop:
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_EOF
    je   .branch_body_done
    cmp  al, TOK_DEDENT
    je   .branch_body_done
    cmp  al, TOK_NEWLINE
    je   .branch_body_skip
    cmp  al, TOK_INDENT
    je   .branch_body_skip
    call parse_stmt                 ; recursive — handles any nested statement
    jmp  .branch_body_loop
.branch_body_skip:
    call lexer_next
    jmp  .branch_body_loop

    ; ── Body done: advance past DEDENT → inspect what follows ─────────────────
.branch_body_done:
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_DEDENT
    jne  .branch_check_next
    call lexer_next                 ; consume DEDENT → first token of next line

.branch_check_next:
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_ELIF
    je   .branch_elif_entry
    cmp  al, TOK_ELSE
    je   .branch_else_entry

    ; ── No continuation: standalone if (or final elif) — end the chain ────────
    call codegen_patch_jump         ; back-fill last cond JNE  → chain exit (here)
    call codegen_patch_chain_end    ; back-fill all JMP-to-end → chain exit (here)
    pop  r13
    pop  r12
    ret

    ; ── elif <ident> == <int_lit>: ────────────────────────────────────────────
.branch_elif_entry:
    ; tok = TOK_ELIF
    ; Phase A: emit unconditional JMP over the rest of the chain
    call codegen_emit_jmp_end       ; E9 + placeholder → pushed onto end_jump_stack
    ; Phase B: back-fill the previous cond JNE → here (start of elif test code)
    call codegen_patch_jump
    ; Phase C: advance past TOK_ELIF → condition ident, then re-parse condition
    call lexer_next
    jmp  .branch_parse_cond         ; loops back through condition + body + check

    ; ── else: ─────────────────────────────────────────────────────────────────
.branch_else_entry:
    ; tok = TOK_ELSE
    ; Phase A: emit unconditional JMP over the else body
    call codegen_emit_jmp_end       ; E9 + placeholder → pushed onto end_jump_stack
    ; Phase B: back-fill the previous cond JNE → here (start of else body)
    call codegen_patch_jump
    ; Phase C: consume 'else' ':' → newline → INDENT → first body token
    call lexer_next                 ; TOK_ELSE  →  ':'
    call lexer_next                 ; ':'       →  newline
    call lexer_next                 ; newline   →  INDENT
    call lexer_next                 ; INDENT    →  first else body token

    ; ── Else body loop ────────────────────────────────────────────────────────
.else_body_loop:
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_EOF
    je   .else_body_done
    cmp  al, TOK_DEDENT
    je   .else_body_done
    cmp  al, TOK_NEWLINE
    je   .else_body_skip
    cmp  al, TOK_INDENT
    je   .else_body_skip
    call parse_stmt
    jmp  .else_body_loop
.else_body_skip:
    call lexer_next
    jmp  .else_body_loop

    ; ── Else done: patch ALL "jmp to chain end" → here ────────────────────────
.else_body_done:
    ; Phase D: back-fill every JMP-to-end placeholder emitted for this chain
    call codegen_patch_chain_end
    ; Advance past else body's DEDENT
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_DEDENT
    jne  .if_exit
    call lexer_next

.if_exit:
    pop  r13
    pop  r12
    ret

    ; ── Error paths (all terminate via fatal_error → sys_exit) ────────────────
.if_err_ident:
    pop  r13
    pop  r12
    lea  rsi, [rel err_expect_ident]
    mov  rdx, err_expect_ident_len
    call fatal_error

.if_err_undef:
    pop  r13
    pop  r12
    lea  rsi, [rel err_undef_var]
    mov  rdx, err_undef_var_len
    call fatal_error

.if_err_eqeq:
    pop  r13
    pop  r12
    lea  rsi, [rel err_expect_eqeq]
    mov  rdx, err_expect_eqeq_len
    call fatal_error

.if_err_int:
    pop  r13
    pop  r12
    lea  rsi, [rel err_expect_int]
    mov  rdx, err_expect_int_len
    call fatal_error

; ─── Error handlers ───────────────────────────────────────────────────────────
.err_const_reassign:
    pop  rax
    lea  rsi, [rel err_const_reassign]
    mov  rdx, err_const_reassign_len
    call fatal_error

.err_undef_var:
    lea  rsi, [rel err_undef_var]
    mov  rdx, err_undef_var_len
    call fatal_error

.err_uninit_var:
    lea  rsi, [rel err_uninit_var]
    mov  rdx, err_uninit_var_len
    call fatal_error

.err_expect_ident:
    lea  rsi, [rel err_expect_ident]
    mov  rdx, err_expect_ident_len
    call fatal_error

.err_expect_int:
    lea  rsi, [rel err_expect_int]
    mov  rdx, err_expect_int_len
    call fatal_error

.err_expect_assign:
    lea  rsi, [rel err_expect_assign]
    mov  rdx, err_expect_assign_len
    call fatal_error

; ═══════════════════════════════════════════════════════════════════════════════
; .parse_for — for :i in <start>..<end>:
;
; Token stream (after TOK_FOR is current):
;   TOK_FOR → TOK_COLON → TOK_IDENT(i) → TOK_IN → TOK_INT_LIT(start)
;   → TOK_DOTDOT → TOK_INT_LIT(end) → TOK_COLON → newline → INDENT → body → DEDENT
;
; Register contract:
;   r12 = loop_top (from codegen_emit_for_start)
;   r13 = start value
;   r14 = end value
;   rbx = var_table index of loop variable
; ═══════════════════════════════════════════════════════════════════════════════
.parse_for:
    push r12
    push r13
    push r14
    push rbx

    ; Advance: TOK_FOR → ':'
    call lexer_next
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_COLON
    jne  .for_err

    ; Advance: ':' → TOK_IDENT (loop variable name)
    call lexer_next
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_IDENT
    jne  .for_err

    ; Copy loop var name into saved_name buffer
    lea  rdi, [rel saved_name]
    lea  rsi, [rel tok_ident]
    mov  ecx, 32
.for_copy_name:
    movzx eax, byte [rsi]
    mov  [rdi], al
    inc  rsi
    inc  rdi
    test al, al
    jz   .for_name_done
    dec  ecx
    jnz  .for_copy_name
.for_name_done:

    ; Advance: TOK_IDENT → TOK_IN
    call lexer_next
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_IN
    jne  .for_err

    ; Advance: TOK_IN → TOK_INT_LIT (start value)
    call lexer_next
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_INT_LIT
    jne  .for_err
    mov  r13, [rel tok_int]         ; r13 = start

    ; Advance: int_lit → TOK_DOTDOT
    call lexer_next
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_DOTDOT
    jne  .for_err

    ; Advance: TOK_DOTDOT → TOK_INT_LIT (end value, exclusive upper bound)
    call lexer_next
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_INT_LIT
    jne  .for_err
    mov  r14, [rel tok_int]         ; r14 = end

    ; Advance: int_lit → ':' → newline → INDENT → first body token
    call lexer_next                 ; → ':'
    call lexer_next                 ; → newline
    call lexer_next                 ; → INDENT
    call lexer_next                 ; → first body token

    ; Register loop variable: mutable, initialised, is_loop_var = 1
    lea  rdi, [rel saved_name]
    mov  rsi, r13                   ; initial value = start
    mov  dl,  0                     ; is_const = 0 (mutable)
    mov  dh,  1                     ; is_initialized = 1
    call var_add
    mov  rbx, rax                   ; rbx = var index (returned by var_add)
    imul rax, VAR_ENTRY_SIZE
    lea  rcx, [rel var_table]
    add  rcx, rax
    mov  byte [rcx + 41], 1         ; is_initialized = 1 (var_add sets it from dl=0; fix here)
    mov  byte [rcx + 43], 1         ; is_loop_var = 1 (edi is live carrier of counter)

    ; Save break base + emit for-loop start code
    call codegen_save_break_base
    mov  rdi, r13                   ; start
    mov  rsi, r14                   ; end
    call codegen_emit_for_start
    mov  r12, rax                   ; r12 = loop_top (returned by codegen_emit_for_start)

    ; ── For body loop ────────────────────────────────────────────────────────
.for_body_loop:
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_EOF
    je   .for_body_done
    cmp  al, TOK_DEDENT
    je   .for_body_done
    cmp  al, TOK_NEWLINE
    je   .for_body_skip
    cmp  al, TOK_INDENT
    je   .for_body_skip
    call parse_stmt
    jmp  .for_body_loop
.for_body_skip:
    call lexer_next
    jmp  .for_body_loop
.for_body_done:
    ; Consume DEDENT if present
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_DEDENT
    jne  .for_after_dedent
    call lexer_next
.for_after_dedent:

    ; Emit: inc edi + backward jmp + patch jge + patch breaks
    mov  rdi, r12
    call codegen_emit_for_end

    ; Clear is_loop_var so variable is no longer treated as live-in-edi
    mov  rax, rbx
    imul rax, VAR_ENTRY_SIZE
    lea  rcx, [rel var_table]
    add  rcx, rax
    mov  byte [rcx + 43], 0

    pop  rbx
    pop  r14
    pop  r13
    pop  r12
    ret

.for_err:
    pop  rbx
    pop  r14
    pop  r13
    pop  r12
    lea  rsi, [rel err_expect_in]
    mov  rdx, err_expect_in_len
    call fatal_error

; ═══════════════════════════════════════════════════════════════════════════════
; .parse_while — while <ident> == <int_lit>:
;
; Token stream (after TOK_WHILE is current):
;   TOK_WHILE → TOK_IDENT → TOK_EQEQ → TOK_INT_LIT → TOK_COLON → newline → INDENT
;   → body → DEDENT
;
; Register contract:
;   r12 = loop_top (from codegen_emit_while_start)
;   r13 = variable value (LHS)
;   r14 = comparison literal (RHS)
; ═══════════════════════════════════════════════════════════════════════════════
.parse_while:
    push r12
    push r13
    push r14

    ; Advance: TOK_WHILE → TOK_IDENT (condition variable)
    call lexer_next
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_IDENT
    jne  .while_err

    ; Look up variable in var_table
    lea  rdi, [rel tok_ident]
    call var_find
    cmp  rax, -1
    je   .while_err

    imul rax, VAR_ENTRY_SIZE
    lea  rcx, [rel var_table]
    add  rcx, rax
    mov  r13, [rcx + 32]            ; r13 = variable value (LHS)
    movzx rax, byte [rcx + 43]
    mov  [rel saved_is_loop_var], al ; save is_loop_var for codegen

    ; Advance: TOK_IDENT → TOK_EQEQ
    call lexer_next
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_EQEQ
    jne  .while_err

    ; Advance: TOK_EQEQ → TOK_INT_LIT (comparison value)
    call lexer_next
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_INT_LIT
    jne  .while_err
    mov  r14, [rel tok_int]         ; r14 = comparison value (RHS)

    ; Advance: int_lit → ':' → newline → INDENT → first body token
    call lexer_next                 ; → ':'
    call lexer_next                 ; → newline
    call lexer_next                 ; → INDENT
    call lexer_next                 ; → first body token

    ; Save break base + emit while-loop start (records loop_top + emits cmp+jne)
    call codegen_save_break_base
    mov  rdi, r13
    mov  rsi, r14
    movzx rdx, byte [rel saved_is_loop_var]
    call codegen_emit_while_start
    mov  r12, rax                   ; r12 = loop_top

    ; ── While body loop ──────────────────────────────────────────────────────
.while_body_loop:
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_EOF
    je   .while_body_done
    cmp  al, TOK_DEDENT
    je   .while_body_done
    cmp  al, TOK_NEWLINE
    je   .while_body_skip
    cmp  al, TOK_INDENT
    je   .while_body_skip
    call parse_stmt
    jmp  .while_body_loop
.while_body_skip:
    call lexer_next
    jmp  .while_body_loop
.while_body_done:
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_DEDENT
    jne  .while_after_dedent
    call lexer_next
.while_after_dedent:

    ; Emit backward jmp + patch jne → after_loop + patch breaks
    mov  rdi, r12
    call codegen_emit_while_end

    pop  r14
    pop  r13
    pop  r12
    ret

.while_err:
    pop  r14
    pop  r13
    pop  r12
    lea  rsi, [rel err_expect_ident]
    mov  rdx, err_expect_ident_len
    call fatal_error

; ═══════════════════════════════════════════════════════════════════════════════
; .parse_prot — prot <name>():
;
; Token stream (after TOK_PROT is current; '(' and ')' are unknown chars → skipped):
;   TOK_PROT → TOK_IDENT(name) → TOK_COLON → newline → INDENT → body → DEDENT
;
; Protocol table entry: 40 bytes — [0..31]=name, [32..39]=code_offset (qword)
; ═══════════════════════════════════════════════════════════════════════════════
.parse_prot:
    push r12                        ; r12 = prot code start (out_idx snapshot)
    push r13                        ; r13 = proto_table entry ptr

    ; Mark that we are now parsing inside a prot body (suppresses codegen_end_protos)
    inc  qword [rel prot_body_depth]

    ; Emit the one-time jmp-over-protos placeholder (idempotent)
    call codegen_begin_protos

    ; Snapshot out_idx: this is where the prot's machine code will begin
    mov  r12, [rel out_idx]

    ; Advance: TOK_PROT → TOK_IDENT (protocol name)
    call lexer_next
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_IDENT
    jne  .prot_err

    ; Compute proto_table entry ptr for proto_count-th entry
    mov  rax, [rel proto_count]
    imul rax, 40
    lea  r13, [rel proto_table]
    add  r13, rax                   ; r13 = &proto_table[proto_count]

    ; Copy protocol name into entry[0..31]
    mov  rdi, r13
    lea  rsi, [rel tok_ident]
    mov  ecx, 32
.prot_copy_name:
    movzx eax, byte [rsi]
    mov  [rdi], al
    inc  rsi
    inc  rdi
    test al, al
    jz   .prot_name_done
    dec  ecx
    jnz  .prot_copy_name
.prot_name_done:

    ; Store code start offset into entry[32..39]
    mov  [r13 + 32], r12

    ; Increment proto_count
    inc  qword [rel proto_count]

    ; Advance past name (and skipped '(' ')') → TOK_COLON → newline → INDENT → body token
    call lexer_next                 ; → TOK_COLON  (parens are unknown, skipped by lexer)
    call lexer_next                 ; → newline
    call lexer_next                 ; → INDENT
    call lexer_next                 ; → first body token

    ; ── Prot body loop ───────────────────────────────────────────────────────
.prot_body_loop:
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_EOF
    je   .prot_body_done
    cmp  al, TOK_DEDENT
    je   .prot_body_done
    cmp  al, TOK_NEWLINE
    je   .prot_body_skip
    cmp  al, TOK_INDENT
    je   .prot_body_skip
    call parse_stmt
    jmp  .prot_body_loop
.prot_body_skip:
    call lexer_next
    jmp  .prot_body_loop
.prot_body_done:
    ; Consume DEDENT
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_DEDENT
    jne  .prot_after_dedent
    call lexer_next
.prot_after_dedent:

    ; Emit implicit ret (C3) to close the prot's machine code block
    call codegen_emit_ret

    ; Leave prot body scope
    dec  qword [rel prot_body_depth]

    pop  r13
    pop  r12
    ret

.prot_err:
    dec  qword [rel prot_body_depth]
    pop  r13
    pop  r12
    lea  rsi, [rel err_expect_ident]
    mov  rdx, err_expect_ident_len
    call fatal_error

; ═══════════════════════════════════════════════════════════════════════════════
; .parse_return — return [<int_lit>]
;
; Emits: mov eax, value (if present) then ret.
; For the current implementation, return with a literal is supported.
; ═══════════════════════════════════════════════════════════════════════════════
.parse_return:
    ; Advance past TOK_RETURN → check next token
    call lexer_next
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_INT_LIT
    jne  .return_bare             ; bare return (no value)

    ; Emit: mov eax, value
    mov  rdi, [rel tok_int]
    call codegen_emit_mov_eax_imm32

    ; Advance past the literal
    call lexer_next

.return_bare:
    ; Emit: ret (C3)
    call codegen_emit_ret
    ret

; ═══════════════════════════════════════════════════════════════════════════════
; .parse_stop — stop  (break out of current loop)
;
; Emits an unconditional jmp placeholder that will be back-filled by
; codegen_patch_breaks when the enclosing loop ends.
; ═══════════════════════════════════════════════════════════════════════════════
.parse_stop:
    ; Emit: jmp 0 placeholder → pushed onto break_jump_stack
    call codegen_emit_break

    ; Advance past TOK_STOP
    call lexer_next
    ret

; ═══════════════════════════════════════════════════════════════════════════════
; .parse_at — @<name>()   (standalone protocol call, result discarded)
;
; Token stream (after TOK_AT is current; '(' and ')' are skipped by lexer):
;   TOK_AT → TOK_IDENT(name)   [then lexer skips '(' ')']
;
; Looks up the protocol in proto_table and emits a CALL instruction.
; ═══════════════════════════════════════════════════════════════════════════════
.parse_at:
    push r12                        ; r12 = prot buffer offset

    ; Advance: TOK_AT → TOK_IDENT (protocol name)
    call lexer_next
    movzx eax, byte [rel tok_type]
    cmp  al, TOK_IDENT
    jne  .at_err

    ; Look up protocol in proto_table
    lea  rdi, [rel tok_ident]
    call proto_find
    cmp  rax, -1
    je   .at_err_undef
    mov  r12, rax                   ; r12 = prot code offset in out_buffer

    ; Advance past the ident (and ignored '(' ')') → next statement token
    call lexer_next                 ; → should land on next meaningful token

    ; Emit: call <prot>  (E8 + rel32)
    mov  rdi, r12
    call codegen_emit_call_prot

    pop  r12
    ret

.at_err:
    pop  r12
    lea  rsi, [rel err_expect_ident]
    mov  rdx, err_expect_ident_len
    call fatal_error

.at_err_undef:
    pop  r12
    lea  rsi, [rel err_undef_prot]
    mov  rdx, err_undef_prot_len
    call fatal_error

; ═══════════════════════════════════════════════════════════════════════════════
; proto_find — search proto_table for a protocol name
;
; rdi = pointer to null-terminated name string (max 31 chars)
; Returns:
;   rax = buffer offset of prot's first instruction (from proto_table entry[32..39])
;   rax = -1 if not found
; ═══════════════════════════════════════════════════════════════════════════════
proto_find:
    push r12
    push r13
    push rbx

    mov  r12, rdi                   ; r12 = name to search for
    xor  r13, r13                   ; r13 = table index

.pf_loop:
    cmp  r13, [rel proto_count]
    jge  .pf_not_found

    ; Compute entry pointer: proto_table + r13 * 40
    mov  rax, r13
    imul rax, 40
    lea  rbx, [rel proto_table]
    add  rbx, rax                   ; rbx = &proto_table[r13]

    ; Compare name bytes until mismatch or null terminator
    mov  rdi, rbx
    mov  rsi, r12
    mov  ecx, 32
.pf_cmp_loop:
    movzx eax, byte [rdi]
    movzx edx, byte [rsi]
    cmp  eax, edx
    jne  .pf_no_match               ; byte mismatch → try next entry
    test eax, eax                   ; both bytes == 0 → end of name → match
    jz   .pf_match
    inc  rdi
    inc  rsi
    dec  ecx
    jnz  .pf_cmp_loop

.pf_match:
    ; Return buffer offset stored at entry[32..39]
    mov  rax, [rbx + 32]

    pop  rbx
    pop  r13
    pop  r12
    ret

.pf_no_match:
    inc  r13
    jmp  .pf_loop

.pf_not_found:
    mov  rax, -1

    pop  rbx
    pop  r13
    pop  r12
    ret
