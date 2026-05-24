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

%include "rex_defs.inc"

; ─── BSS ────────────────────────────────────────────────────────────────────
section .bss
    var_table:   resb VAR_ENTRY_SIZE * VAR_MAX  ; variable table
    var_count:   resq 1                          ; number of declared variables
    saved_name:  resb 64                         ; temp: save ident across lexer calls

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
    movzx eax, byte [rel tok_type]

    cmp  al, TOK_TYPE_INT
    je   .parse_decl

    cmp  al, TOK_COLON
    je   .parse_assign

    cmp  al, TOK_OUTPUT
    je   .parse_output

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

; ─── output x ────────────────────────────────────────────────────────────────
.parse_output:
    ; Current: TOK_OUTPUT
    call lexer_next
    movzx eax, byte [rel tok_type]
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

    ; Emit code: call rt_pri with the known value
    mov  rdi, [rcx + 32]
    call codegen_output_const

    call lexer_next         ; advance past identifier
    ret

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
