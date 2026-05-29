; -----------------------------------------------------------------------------
; Rex V5.0 Parser
; Recursive descent parser for the Rex language.
; Handles statement parsing, variable management, and protocol tracking.
; Also contains the full expression parser with operator precedence.
; -----------------------------------------------------------------------------

default rel

%include "include/rex_defs.inc"

global parse_stmt

; Externs from Lexer
extern lexer_init
extern lexer_next
extern tok_type
extern tok_int
extern tok_ident

; Externs from Codegen
extern codegen_output_const
extern codegen_output_typed
extern codegen_patch_jump
extern codegen_save_chain_base
extern codegen_emit_jmp_end
extern codegen_patch_chain_end
extern codegen_begin_protos
extern codegen_end_protos
extern codegen_emit_for_start
extern codegen_emit_for_end
extern codegen_emit_while_start
extern codegen_emit_while_end
extern codegen_emit_break
extern codegen_patch_breaks
extern codegen_emit_ret
extern codegen_emit_mov_eax_imm32
extern codegen_emit_call_prot
extern codegen_emit_assign_var
extern codegen_emit_cmp_var_jne
extern codegen_emit_unknown_bool
extern codegen_emit_mm_switch
extern codegen_emit_float_op
extern codegen_emit_complex_op
extern codegen_output_float_const
extern out_idx

; Externs for expression emission (raw byte emitters from codegen)
extern emit_b
extern emit_d
extern emit_q
extern get_var_va
extern codegen_output_rax_int
extern codegen_output_rax_float
extern codegen_output_rax_bool
extern codegen_output_rax_str
extern codegen_emit_store_rax_var
extern codegen_emit_cmp_rax_rbx_jcc

section .bss
    var_table:       resb VAR_ENTRY_SIZE * VAR_MAX
    var_count:       resq 1
    proto_table:     resb 48 * 32
    proto_count:     resq 1
    prot_body_depth: resq 1
    saved_name:      resb 64
    cur_type:        resb 1         ; type of last evaluated expression

section .data
    err_id:    db "error: expected identifier", 10
    err_id_l   equ $ - err_id

section .text

; -----------------------------------------------------------------------------
; strcpy — copy null-terminated string; RDI=dest, RSI=src
; -----------------------------------------------------------------------------
strcpy:
    push rbp
    mov rbp, rsp
    push rsi
    push rdi
.l:
    movzx eax, byte [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .l
    pop rdi
    pop rsi
    leave
    ret

; -----------------------------------------------------------------------------
; fatal — write error to stderr and exit 1
; -----------------------------------------------------------------------------
fatal:
    push rbp
    mov rbp, rsp
    mov r9, rdx
    mov r8, rsi
    mov rax, 1
    mov rdi, 2
    mov rsi, r8
    mov rdx, r9
    syscall
    mov rax, 60
    mov rdi, 1
    syscall

; -----------------------------------------------------------------------------
; var_find — look up variable by name
; Input: RDI = name pointer
; Output: RAX = index, or -1 if not found
; -----------------------------------------------------------------------------
var_find:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rsi
    push rdi
    xor rcx, rcx
.l:
    cmp rcx, [var_count]
    jge .nf
    mov rax, rcx
    imul rax, VAR_ENTRY_SIZE
    lea rsi, [var_table]
    add rsi, rax
    mov rdi, [rbp-32]
.c:
    movzx eax, byte [rdi]
    movzx edx, byte [rsi]
    cmp al, dl
    jne .next
    test al, al
    jz .match
    inc rdi
    inc rsi
    jmp .c
.match:
    mov rax, rcx
    jmp .done
.next:
    inc rcx
    jmp .l
.nf:
    mov rax, -1
.done:
    pop rdi
    pop rsi
    pop rcx
    pop rbx
    leave
    ret

; -----------------------------------------------------------------------------
; var_add — add variable to symbol table
; RDI=name, RSI=val, DL=is_init, CL=type
; Returns RAX = index, or -1 if table full
; -----------------------------------------------------------------------------
var_add:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14b, dl
    mov r15b, cl
    mov rbx, [var_count]
    cmp rbx, VAR_MAX
    jge .full
    mov rax, rbx
    imul rax, VAR_ENTRY_SIZE
    lea rdi, [var_table]
    add rdi, rax
    push rdi
    mov ecx, VAR_ENTRY_SIZE / 4
    xor eax, eax
    cld
    rep stosd
    pop rdi
    mov rsi, r12
    call strcpy
    mov rax, rbx
    imul rax, VAR_ENTRY_SIZE
    lea rdi, [var_table]
    add rdi, rax
    mov [rdi+32], r13
    mov byte [rdi+40], r14b
    mov byte [rdi+48], r15b
    inc qword [var_count]
    mov rax, rbx
    jmp .done
.full:
    mov rax, -1
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

; -----------------------------------------------------------------------------
; parse_stmt — parse and codegen one statement
; -----------------------------------------------------------------------------
parse_stmt:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    movzx eax, byte [tok_type]

    cmp al, TOK_PROT
    je .s1
    cmp qword [prot_body_depth], 0
    jne .s1
    call codegen_end_protos
    movzx eax, byte [tok_type]

.s1:
    cmp al, TOK_TYPE_INT
    je .p_int
    cmp al, TOK_TYPE_FLOAT
    je .p_float
    cmp al, TOK_TYPE_BOOL
    je .p_bool
    cmp al, TOK_TYPE_STR
    je .p_str
    cmp al, TOK_TYPE_COMPLEX
    je .p_complex
    cmp al, TOK_TYPE_DICT
    je .p_dict
    cmp al, TOK_BIN
    je .p_bin
    cmp al, TOK_COLON
    je .assign
    cmp al, TOK_OUTPUT
    je .output
    cmp al, TOK_IF
    je .if
    cmp al, TOK_FOR
    je .for
    cmp al, TOK_WHILE
    je .while
    cmp al, TOK_PROT
    je .protocol
    cmp al, TOK_RETURN
    je .return
    cmp al, TOK_STOP
    je .stop
    cmp al, TOK_AT
    je .at_call
    cmp al, TOK_USE
    je .use_mm
    cmp al, TOK_ERR
    je .err_stmt
    cmp al, TOK_TYPE_SEQ
    je .seq_decl
    cmp al, TOK_PUSH
    je .push_stmt

    call lexer_next
    jmp .done

.p_float:   mov r15b, TYPE_FLOAT;   jmp .p_generic
.p_bool:    mov r15b, TYPE_BOOL;    jmp .p_generic
.p_str:     mov r15b, TYPE_STR;     jmp .p_generic
.p_complex: mov r15b, TYPE_COMPLEX; jmp .p_generic
.p_int:     mov r15b, TYPE_INT

.p_generic:
    call lexer_next
    cmp byte [tok_type], TOK_IDENT
    jne .id_error
    lea rsi, [tok_ident]
    lea rdi, [saved_name]
    call strcpy
    call lexer_next
    cmp byte [tok_type], TOK_ASSIGN
    je .parse_init
    lea rdi, [saved_name]
    xor rsi, rsi
    mov dl, 0
    mov cl, r15b
    call var_add
    jmp .done

.parse_init:
    call lexer_next
    movzx eax, byte [tok_type]
    cmp al, TOK_TRUE
    je .pi_true
    cmp al, TOK_FALSE
    je .pi_false
    cmp al, TOK_UNKNOWN
    je .pi_unknown

    ; General expression — parse and store at runtime
    lea rdi, [saved_name]
    xor rsi, rsi
    mov dl, 1
    mov cl, r15b
    call var_add
    cmp rax, -1
    je .done
    mov r14, rax
    call parse_expr
    mov rdi, r14
    call codegen_emit_store_rax_var
    jmp .done

.pi_true:
    lea rdi, [saved_name]
    mov rsi, 1
    mov dl, 1
    mov cl, r15b
    call var_add
    cmp rax, -1
    je .done
    mov r14, rax
    mov rdi, r14
    mov rsi, 1
    call codegen_emit_assign_var
    call lexer_next
    jmp .done

.pi_false:
    lea rdi, [saved_name]
    xor rsi, rsi
    mov dl, 1
    mov cl, r15b
    call var_add
    cmp rax, -1
    je .done
    mov r14, rax
    mov rdi, r14
    xor rsi, rsi
    call codegen_emit_assign_var
    call lexer_next
    jmp .done

.pi_unknown:
    lea rdi, [saved_name]
    xor rsi, rsi
    mov dl, 1
    mov cl, r15b
    call var_add
    cmp rax, -1
    je .done
    mov r14, rax
    mov rdi, r14
    call codegen_emit_unknown_bool
    call lexer_next
    jmp .done

.id_error:
    lea rsi, [err_id]
    mov rdx, err_id_l
    call fatal

; --- bin type declaration: bin10 name = val ---
.p_bin:
    call lexer_next
    cmp byte [tok_type], TOK_IDENT
    jne .id_error
    lea rsi, [tok_ident]
    lea rdi, [saved_name]
    call strcpy
    call lexer_next
    cmp byte [tok_type], TOK_ASSIGN
    jne .pb_no_init
    call lexer_next
    lea rdi, [saved_name]
    xor rsi, rsi
    mov dl, 1
    mov cl, TYPE_BIN
    call var_add
    cmp rax, -1
    je .done
    mov r14, rax
    call parse_expr
    mov rdi, r14
    call codegen_emit_store_rax_var
    jmp .done
.pb_no_init:
    lea rdi, [saved_name]
    xor rsi, rsi
    mov dl, 0
    mov cl, TYPE_BIN
    call var_add
    jmp .done

; --- dict type declaration: dict name = { ... } ---
.p_dict:
    call lexer_next
    cmp byte [tok_type], TOK_IDENT
    jne .id_error
    lea rsi, [tok_ident]
    lea rdi, [saved_name]
    call strcpy
    call lexer_next
    cmp byte [tok_type], TOK_ASSIGN
    jne .pd_no_init
    call lexer_next
    lea rdi, [saved_name]
    xor rsi, rsi
    mov dl, 1
    mov cl, TYPE_DICT
    call var_add
    cmp rax, -1
    je .done
    mov r14, rax
    call parse_dict_inline
    mov rdi, r14
    call codegen_emit_store_rax_var
    jmp .done
.pd_no_init:
    lea rdi, [saved_name]
    xor rsi, rsi
    mov dl, 0
    mov cl, TYPE_DICT
    call var_add
    jmp .done

; --- output expr ---
; Dispatches to the correct runtime printer based on cur_type.
.output:
    call lexer_next
    call parse_expr
    movzx eax, byte [cur_type]
    cmp al, TYPE_FLOAT
    je .out_float
    cmp al, TYPE_STR
    je .out_str
    cmp al, TYPE_BOOL
    je .out_bool
    cmp al, TYPE_BIN
    je .out_int      ; Backing its data directly down to standard registers/ints
.out_int:
    call codegen_output_rax_int
    jmp .done
.out_float:
    call codegen_output_rax_float
    jmp .done
.out_str:
    call codegen_output_rax_str
    jmp .done
.out_bool:
    call codegen_output_rax_bool
    jmp .done

; --- : name = expr (reassignment) ---
.assign:
    call lexer_next
    cmp byte [tok_type], TOK_IDENT
    jne .done
    sub rsp, 64
    mov rdi, rsp
    lea rsi, [tok_ident]
    call strcpy
    call lexer_next          ; skip dest ident
    call lexer_next          ; skip '='

    mov rdi, rsp
    call var_find
    cmp rax, -1
    je .asgn_err
    mov r14, rax

    movzx eax, byte [tok_type]
    cmp al, TOK_TRUE
    je .asgn_true
    cmp al, TOK_FALSE
    je .asgn_false
    cmp al, TOK_UNKNOWN
    je .asgn_unknown

    call parse_expr
    mov rdi, r14
    call codegen_emit_store_rax_var
    add rsp, 64
    jmp .done

.asgn_true:
    mov rdi, r14
    mov rsi, 1
    call codegen_emit_assign_var
    call lexer_next
    add rsp, 64
    jmp .done

.asgn_false:
    mov rdi, r14
    xor rsi, rsi
    call codegen_emit_assign_var
    call lexer_next
    add rsp, 64
    jmp .done

.asgn_unknown:
    mov rdi, r14
    call codegen_emit_unknown_bool
    call lexer_next
    add rsp, 64
    jmp .done

.asgn_err:
    add rsp, 64
    jmp .done

; --- if / elif / else ---
; Conditions support full expressions on both sides of any comparison op.
; Syntax: if expr op expr:
.if:
    call codegen_save_chain_base
.if_next:
    call lexer_next              ; advance past keyword; tok = first LHS token
    call parse_expr              ; LHS → rax at runtime; tok = comparison op
    ; emit: push rax (50)  — save LHS result
    mov al, 0x50
    call emit_b
    movzx r12d, byte [tok_type] ; save the comparison operator token
    call lexer_next              ; skip comparison op; tok = first RHS token
    call parse_expr              ; RHS → rax at runtime; tok = ':'
    ; emit: mov rbx,rax; pop rax  (left in rax, right in rbx)
    call emit_cmp_binop_setup
    ; emit cmp rax,rbx + inverted Jcc (pushes to patch stack)
    movzx rdi, r12b
    call codegen_emit_cmp_rax_rbx_jcc
    ; tok is now ':', advance past it
    call lexer_next              ; skip ':'; tok = newline or indent or stmt
    cmp byte [tok_type], TOK_NEWLINE
    jne .if_no_nl
    call lexer_next              ; skip newline
.if_no_nl:
    cmp byte [tok_type], TOK_INDENT
    jne .if_single
    call lexer_next              ; skip INDENT; tok = first stmt token
    mov r13, 1
    jmp .if_block_loop
.if_single:
    xor r13, r13
.if_block_loop:
    movzx eax, byte [tok_type]
    cmp al, TOK_EOF
    je .if_end_block
    cmp al, TOK_DEDENT
    je .if_end_block
    call parse_stmt
    test r13, r13
    jnz .if_block_loop
.if_end_block:
    test r13, r13
    jz .if_after_dedent
    cmp byte [tok_type], TOK_DEDENT
    jne .if_after_dedent
    call lexer_next
.if_after_dedent:
    movzx eax, byte [tok_type]
    cmp al, TOK_ELIF
    je .do_elif
    cmp al, TOK_ELSE
    je .do_else
    call codegen_patch_jump
    call codegen_patch_chain_end
    jmp .done
.do_elif:
    call codegen_emit_jmp_end
    call codegen_patch_jump
    jmp .if_next
.do_else:
    call codegen_emit_jmp_end
    call codegen_patch_jump
    call lexer_next
    call lexer_next
    cmp byte [tok_type], TOK_NEWLINE
    jne .el_nn
    call lexer_next
.el_nn:
    cmp byte [tok_type], TOK_INDENT
    jne .el_single
    call lexer_next
    mov r13, 1
    jmp .el_bl
.el_single:
    xor r13, r13
.el_bl:
    movzx eax, byte [tok_type]
    cmp al, TOK_EOF
    je .el_en
    cmp al, TOK_DEDENT
    je .el_en
    call parse_stmt
    test r13, r13
    jnz .el_bl
.el_en:
    test r13, r13
    jz .el_do
    cmp byte [tok_type], TOK_DEDENT
    jne .el_do
    call lexer_next
.el_do:
    call codegen_patch_chain_end
    jmp .done

; --- for loop ---
.for:
    call codegen_emit_while_start   ; save break base for stop (break) support
    call lexer_next
    call lexer_next
    sub rsp, 64
    mov rdi, rsp
    lea rsi, [tok_ident]
    call strcpy
    call lexer_next
    call lexer_next
    mov r12, [tok_int]
    call lexer_next
    call lexer_next
    mov r13, [tok_int]
    lea rsi, [rsp]
    lea rdi, [saved_name]
    call strcpy
    lea rdi, [saved_name]
    mov rsi, r12
    mov dl, 0
    mov cl, TYPE_INT
    call var_add
    mov r14, rax
    mov rdi, r14
    mov rsi, r12
    mov rdx, r13
    call codegen_emit_for_start
    mov r15, rax
    add rsp, 64
    call lexer_next
    call lexer_next
.for_loop:
    movzx eax, byte [tok_type]
    cmp al, TOK_EOF
    je .for_done
    cmp al, TOK_DEDENT
    je .for_done
    call parse_stmt
    jmp .for_loop
.for_done:
    cmp byte [tok_type], TOK_DEDENT
    jne .for_no_dedent
    call lexer_next
.for_no_dedent:
    mov rdi, r15
    mov rsi, r14
    call codegen_emit_for_end
    jmp .done

; --- while loop ---
; Conditions support full expressions on both sides of any comparison op.
; Syntax: while expr op expr:
.while:
    call codegen_emit_while_start   ; save break base for stop (break) support
    call lexer_next                 ; advance past 'while'; tok = first LHS token
    mov r15, [out_idx]             ; save loop-top offset for backward JMP
    call parse_expr                 ; LHS → rax at runtime; tok = comparison op
    ; emit: push rax (50)  — save LHS result
    mov al, 0x50
    call emit_b
    movzx r12d, byte [tok_type]    ; save comparison operator token
    call lexer_next                 ; skip comparison op; tok = first RHS token
    call parse_expr                 ; RHS → rax at runtime; tok = ':'
    call emit_cmp_binop_setup      ; emit: mov rbx,rax; pop rax
    movzx rdi, r12b
    call codegen_emit_cmp_rax_rbx_jcc  ; emit inverted Jcc → push to patch stack
    call lexer_next                 ; skip ':'; tok = newline or indent or stmt
    call lexer_next                 ; skip newline/indent first token
.while_l:
    movzx eax, byte [tok_type]
    cmp al, TOK_EOF
    je .while_d
    cmp al, TOK_DEDENT
    je .while_d
    call parse_stmt
    jmp .while_l
.while_d:
    cmp byte [tok_type], TOK_DEDENT
    jne .w_nd
    call lexer_next
.w_nd:
    mov rdi, r15
    call codegen_emit_while_end     ; emit JMP back + patch Jcc + patch breaks
    jmp .done

; --- protocol definition ---
; Syntax: prot name():  OR  prot name(a, b, c):
.protocol:
    inc qword [prot_body_depth]
    call codegen_begin_protos
    call lexer_next                 ; tok = protocol name
    mov rax, [proto_count]
    imul rax, 48                    ; 48-byte proto entries
    lea r13, [proto_table]
    add r13, rax
    lea rsi, [tok_ident]
    mov rdi, r13
    call strcpy
    mov rbx, [out_idx]
    mov [r13+32], rbx               ; store current code offset
    xor r12d, r12d                  ; r12 = param count
    inc qword [proto_count]
    call lexer_next                 ; tok = '(' or ':'
    cmp byte [tok_type], TOK_LPAREN
    jne .prot_no_params
    call lexer_next                 ; skip '(', tok = first param or ')'
.prot_param_loop:
    movzx eax, byte [tok_type]
    cmp al, TOK_RPAREN
    je .prot_params_done
    cmp al, TOK_IDENT
    jne .prot_params_done
    lea rdi, [tok_ident]
    mov cl, TYPE_INT
    call var_add                    ; rax = new var index
    cmp r12d, 5
    jge .prot_pi
    mov [r13+41+r12], al            ; store var index in proto entry
.prot_pi:
    inc r12d
    call lexer_next                 ; tok = ',' or ')'
    movzx eax, byte [tok_type]
    cmp al, TOK_COMMA
    jne .prot_params_done
    call lexer_next                 ; skip ','
    jmp .prot_param_loop
.prot_params_done:
    call lexer_next                 ; skip ')'
.prot_no_params:
    mov [r13+40], r12b              ; store param count in proto entry
    ; skip ':' and newline/indent before body
    call lexer_next                 ; skip ':'
    call lexer_next                 ; skip newline
    call lexer_next                 ; skip indent (first stmt token)
    ; Emit: mov [var_addr], reg  for each declared parameter
    xor r12d, r12d
.prot_store_params:
    movzx eax, byte [r13+40]
    cmp r12d, eax
    jge .prot_body
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    ; ModRM byte: rdi=0x3C, rsi=0x34, rdx=0x14, rcx=0x0C
    cmp r12d, 0
    je .psp_rdi
    cmp r12d, 1
    je .psp_rsi
    cmp r12d, 2
    je .psp_rdx
    mov al, 0x0C
    jmp .psp_modrm
.psp_rdi:
    mov al, 0x3C
    jmp .psp_modrm
.psp_rsi:
    mov al, 0x34
    jmp .psp_modrm
.psp_rdx:
    mov al, 0x14
.psp_modrm:
    call emit_b
    mov al, 0x25
    call emit_b
    movzx rdi, byte [r13+41+r12]
    call get_var_va
    call emit_d
    inc r12d
    jmp .prot_store_params
.prot_body:
.prot_loop:
    movzx eax, byte [tok_type]
    cmp al, TOK_EOF
    je .prot_done
    cmp al, TOK_DEDENT
    je .prot_done
    call parse_stmt
    jmp .prot_loop
.prot_done:
    cmp byte [tok_type], TOK_DEDENT
    jne .prot_nd
    call lexer_next
.prot_nd:
    call codegen_emit_ret
    dec qword [prot_body_depth]
    jmp .done

; --- return ---
; Supports full expressions: return expr  or  bare return (void).
.return:
    call lexer_next
    movzx eax, byte [tok_type]
    cmp al, TOK_NEWLINE
    je .ret_void
    cmp al, TOK_EOF
    je .ret_void
    cmp al, TOK_DEDENT
    je .ret_void
    call parse_expr                 ; evaluate return expression → rax at runtime
    jmp .ret_done
.ret_void:
.ret_done:
    call codegen_emit_ret
    jmp .done

; --- stop (break) ---
.stop:
    call codegen_emit_break
    call lexer_next
    jmp .done

; --- @protocol_call ---
; Syntax: @name()  OR  @name(expr1, expr2, ...)
.at_call:
    call lexer_next              ; skip '@', tok = protocol name
    lea rdi, [tok_ident]
    call proto_find              ; rax = protocol code offset, or -1
    cmp rax, -1
    je .ac_skip
    mov r12, rax                 ; save protocol offset
    call lexer_next              ; skip protocol name, tok = '('
    call emit_at_call_args       ; eval args + emit pushes/pops, advance past ')'
    mov rdi, r12
    call codegen_emit_call_prot
    jmp .done
.ac_skip:
    call lexer_next              ; skip protocol name
    call lexer_next              ; skip '('
    call lexer_next              ; skip ')'
    jmp .done

; --- use mm ... ---
; Supports: use mm pool gc <name>:  or  use mm arena gc <name>:
.use_mm:
    call lexer_next
    call lexer_next
    call lexer_next
    ; Full 4-byte comparison for "pool\0"
    cmp dword [tok_ident], 0x6c6f6f70   ; "pool" in little-endian
    jne .use_not_pool
    cmp byte [tok_ident+4], 0
    jne .use_not_pool
    mov edi, 1
    jmp .use_do_switch
.use_not_pool:
    xor edi, edi
.use_do_switch:
    call codegen_emit_mm_switch
    call lexer_next
    call lexer_next
    call lexer_next
    call lexer_next
    cmp byte [tok_type], TOK_NEWLINE
    jne .un
    call lexer_next
.un:
    cmp byte [tok_type], TOK_INDENT
    jne .ub
    call lexer_next
    mov r13, 1
    jmp .ubl
.ub:
    xor r13, r13
.ubl:
    movzx eax, byte [tok_type]
    cmp al, TOK_EOF
    je .uen
    cmp al, TOK_DEDENT
    je .uen
    call parse_stmt
    test r13, r13
    jnz .ubl
.uen:
    test r13, r13
    jz .udo
    cmp byte [tok_type], TOK_DEDENT
    jne .udo
    call lexer_next
.udo:
    xor rdi, rdi
    call codegen_emit_mm_switch
    jmp .done

; --- err "msg" ---
; Evaluates a string expression then calls rt_err (writes to stderr + newline).
.err_stmt:
    call lexer_next              ; skip 'err', tok = string expression
    call parse_expr              ; emit expr code → rax at runtime (string ptr)
    ; Emit: mov rdi, rax  (48 89 C7)
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC7
    call emit_b
    ; Emit: call rt_err  (E8 <rel32>)
    mov al, 0xE8
    call emit_b
    mov rax, LOAD_BASE + RT_ERR_OFFSET
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d
    jmp .done

; --- seq x ---
; Declares a dynamic sequence variable; allocates initial heap block via rt_alc.
; Block layout: [8-byte hidden len][8-byte cap][data: u64 * cap]
; ptr returned points to [8-byte cap].
.seq_decl:
    call lexer_next              ; skip 'seq', tok = var name
    lea rdi, [tok_ident]
    mov cl, TYPE_SEQ
    call var_add                 ; rax = var index
    cmp rax, -1
    je .done
    mov r15, rax                 ; r15 = var index
    ; Emit: mov rdi, 80  (48 C7 C7 50 00 00 00)  — 8 hdr + 8 cap + 8 slots * 8 bytes
    mov al, 0x48
    call emit_b
    mov al, 0xC7
    call emit_b
    mov al, 0xC7
    call emit_b
    mov al, 80
    call emit_b
    xor eax, eax
    call emit_b
    call emit_b
    call emit_b
    ; Emit: call rt_alc  (E8 <rel32>)
    mov al, 0xE8
    call emit_b
    mov rax, LOAD_BASE + RT_ALC_OFFSET
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d
    ; Emit: add rax, 8 — skip hidden length header
    mov al, 0x48
    call emit_b
    mov al, 0x83
    call emit_b
    mov al, 0xC0
    call emit_b
    mov al, 0x08
    call emit_b
    ; Emit: mov [var_addr], rax  (48 89 04 25 <addr>)
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    mov rdi, r15
    call get_var_va
    call emit_d
    ; Emit: mov qword [rax-8], 0  (48 C7 40 F8 00 00 00 00)  — initial len = 0
    mov al, 0x48
    call emit_b
    mov al, 0xC7
    call emit_b
    mov al, 0x40
    call emit_b
    mov al, 0xF8
    call emit_b
    xor eax, eax
    call emit_d
    ; Emit: mov qword [rax], 8  (48 C7 00 08 00 00 00)  — initial cap = 8
    mov al, 0x48
    call emit_b
    mov al, 0xC7
    call emit_b
    mov al, 0x00
    call emit_b
    mov al, 0x08
    call emit_b
    xor eax, eax
    call emit_b
    call emit_b
    call emit_b
    call lexer_next              ; advance past var name
    jmp .done

; --- push x val ---
; Appends a value to a sequence. val is any integer expression.
.push_stmt:
    call lexer_next              ; skip 'push', tok = seq var name
    lea rdi, [tok_ident]
    call var_find                ; rax = var index
    cmp rax, -1
    je .push_skip
    mov r15, rax                 ; r15 = seq var index
    call lexer_next              ; skip var name, tok = value expression
    call parse_expr              ; emit value expression → runtime rax
    ; Emit: push rax  (50)  — save value while we load seq ptr
    mov al, 0x50
    call emit_b
    ; Emit: mov rbx, [seq_var_addr]  (48 8B 1C 25 <addr>)  — load heap ptr
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x1C
    call emit_b
    mov al, 0x25
    call emit_b
    mov rdi, r15
    call get_var_va
    call emit_d
    ; Emit: mov rcx, [rbx-8]  (48 8B 4B F8)  — load current length from hidden header
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x4B
    call emit_b
    mov al, 0xF8
    call emit_b
    ; Emit: pop rax  (58)  — restore value
    mov al, 0x58
    call emit_b
    ; Emit: mov [rbx+rcx*8+8], rax  (48 89 44 CB 08)  — store at data[len]
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0x44
    call emit_b
    mov al, 0xCB
    call emit_b
    mov al, 0x08
    call emit_b
    ; Emit: inc qword [rbx-8]  (48 FF 43 F8)  — increment length
    mov al, 0x48
    call emit_b
    mov al, 0xFF
    call emit_b
    mov al, 0x43
    call emit_b
    mov al, 0xF8
    call emit_b
    jmp .done
.push_skip:
    call lexer_next              ; skip var name
    call lexer_next              ; skip value (one token)
    jmp .done

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

; -----------------------------------------------------------------------------
; proto_find — look up protocol by name; Input: RDI=name; Output: RAX=offset or -1
; -----------------------------------------------------------------------------
proto_find:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push rbx
    mov r12, rdi
    xor r13, r13
.l:
    cmp r13, [proto_count]
    jge .nf
    mov rax, r13
    imul rax, 48
    lea rbx, [proto_table]
    add rbx, rax
    mov rdi, rbx
    mov rsi, r12
    mov ecx, 32
.cl:
    movzx eax, byte [rdi]
    movzx edx, byte [rsi]
    cmp eax, edx
    jne .nm
    test eax, eax
    jz .m
    inc rdi
    inc rsi
    dec ecx
    jnz .cl
.m:
    mov rax, [rbx+32]
    jmp .done
.nm:
    inc r13
    jmp .l
.nf:
    mov rax, -1
.done:
    pop rbx
    pop r13
    pop r12
    leave
    ret

; =============================================================================
; Expression Parser — recursive descent with full operator precedence.
; All parse_* functions below:
;   - Emit x86-64 machine code into out_buffer via emit_b/emit_d/emit_q.
;   - Leave the runtime result in RAX.
;   - Set [cur_type] to the type of the last loaded atom (TYPE_INT, TYPE_FLOAT, etc.)
;   - Advance [tok_type] past all consumed tokens.
; =============================================================================

; --- Helper: emit_cmp_binop_setup ---
; Emits: mov rbx, rax (48 89 C3)  +  pop rax (58)  +  cmp rax, rbx (48 39 D8)
; Used before all comparison setXX instructions.
emit_cmp_binop_setup:
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC3
    call emit_b
    mov al, 0x58
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0x39
    call emit_b
    mov al, 0xD8
    call emit_b
    ret

; --- Helper: emit_movzx_rax_al ---
; Emits: movzx rax, al  (48 0F B6 C0)
emit_movzx_rax_al:
    mov al, 0x48
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0xB6
    call emit_b
    mov al, 0xC0
    call emit_b
    ret

; --- Helper: emit_at_call_args ---
; Entry: [tok_type] = TOK_LPAREN  ('(')
; Evaluates each argument expression, emitting "push rax" after each.
; Then emits pops in reverse order into SysV argument registers:
;   rdi (1st), rsi (2nd), rdx (3rd), rcx (4th).
; Advances tok past the closing ')'.
; Returns: rax = number of arguments evaluated.
emit_at_call_args:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    xor r13d, r13d              ; r13 = argument count
    call lexer_next             ; skip '(' → first arg or ')'
.eaa_loop:
    movzx eax, byte [tok_type]
    cmp al, TOK_RPAREN
    je .eaa_done
    cmp al, TOK_EOF
    je .eaa_done
    call parse_expr             ; emit arg expression → runtime rax
    mov al, 0x50                ; emit: push rax
    call emit_b
    inc r13d
    movzx eax, byte [tok_type]
    cmp al, TOK_COMMA
    jne .eaa_done
    call lexer_next             ; skip ','
    jmp .eaa_loop
.eaa_done:
    call lexer_next             ; skip ')'
    ; Emit pops in reverse: arg[n-1] → last reg, arg[0] → rdi
    ; Pop opcodes: rdi=0x5F, rsi=0x5E, rdx=0x5A, rcx=0x59
    mov rbx, r13
.eaa_pop_loop:
    dec rbx
    js .eaa_pop_done
    cmp rbx, 0
    je .eaa_rdi
    cmp rbx, 1
    je .eaa_rsi
    cmp rbx, 2
    je .eaa_rdx
    mov al, 0x59                ; pop rcx
    jmp .eaa_emit
.eaa_rdi:
    mov al, 0x5F
    jmp .eaa_emit
.eaa_rsi:
    mov al, 0x5E
    jmp .eaa_emit
.eaa_rdx:
    mov al, 0x5A
.eaa_emit:
    call emit_b
    jmp .eaa_pop_loop
.eaa_pop_done:
    mov rax, r13
    pop r13
    pop r12
    pop rbx
    leave
    ret

; --- parse_expr — top-level expression entry point ---
parse_expr:
    push rbp
    mov rbp, rsp
    call parse_comparison
    leave
    ret

; --- parse_comparison (Level 5): handles ==, !=, <, >, <=, >= ---
parse_comparison:
    push rbp
    mov rbp, rsp
    call parse_additive
.loop:
    movzx eax, byte [tok_type]
    cmp al, TOK_EQEQ
    je .peq
    cmp al, TOK_NEQ
    je .pne
    cmp al, TOK_LT
    je .plt
    cmp al, TOK_GT
    je .pgt
    cmp al, TOK_LTE
    je .ple
    cmp al, TOK_GTE
    je .pge
    leave
    ret
.peq:
    call lexer_next
    mov al, 0x50
    call emit_b
    call parse_additive
    call emit_cmp_binop_setup
    ; emit: sete al (0F 94 C0)
    mov al, 0x0F
    call emit_b
    mov al, 0x94
    call emit_b
    mov al, 0xC0
    call emit_b
    call emit_movzx_rax_al
    jmp .loop
.pne:
    call lexer_next
    mov al, 0x50
    call emit_b
    call parse_additive
    call emit_cmp_binop_setup
    ; emit: setne al (0F 95 C0)
    mov al, 0x0F
    call emit_b
    mov al, 0x95
    call emit_b
    mov al, 0xC0
    call emit_b
    call emit_movzx_rax_al
    jmp .loop
.plt:
    call lexer_next
    mov al, 0x50
    call emit_b
    call parse_additive
    call emit_cmp_binop_setup
    ; emit: setl al (0F 9C C0)
    mov al, 0x0F
    call emit_b
    mov al, 0x9C
    call emit_b
    mov al, 0xC0
    call emit_b
    call emit_movzx_rax_al
    jmp .loop
.pgt:
    call lexer_next
    mov al, 0x50
    call emit_b
    call parse_additive
    call emit_cmp_binop_setup
    ; emit: setg al (0F 9F C0)
    mov al, 0x0F
    call emit_b
    mov al, 0x9F
    call emit_b
    mov al, 0xC0
    call emit_b
    call emit_movzx_rax_al
    jmp .loop
.ple:
    call lexer_next
    mov al, 0x50
    call emit_b
    call parse_additive
    call emit_cmp_binop_setup
    ; emit: setle al (0F 9E C0)
    mov al, 0x0F
    call emit_b
    mov al, 0x9E
    call emit_b
    mov al, 0xC0
    call emit_b
    call emit_movzx_rax_al
    jmp .loop
.pge:
    call lexer_next
    mov al, 0x50
    call emit_b
    call parse_additive
    call emit_cmp_binop_setup
    ; emit: setge al (0F 9D C0)
    mov al, 0x0F
    call emit_b
    mov al, 0x9D
    call emit_b
    mov al, 0xC0
    call emit_b
    call emit_movzx_rax_al
    jmp .loop

; --- parse_additive (Level 4): handles +, -, &, |, ^ ---
parse_additive:
    push rbp
    mov rbp, rsp
    push r14                    ; r14 = saved LHS type for propagation
    call parse_multiplicative
.loop:
    movzx eax, byte [tok_type]
    cmp al, TOK_PLUS
    je .padd
    cmp al, TOK_MINUS
    je .psub
    cmp al, TOK_BAND
    je .pband
    cmp al, TOK_BOR
    je .pbor
    cmp al, TOK_BXOR
    je .pbxor
    pop r14
    leave
    ret
.padd:
    call lexer_next
    movzx r14d, byte [cur_type] ; save LHS type
    mov al, 0x50
    call emit_b
    call parse_multiplicative   ; RHS; sets cur_type to RHS type
    ; Type propagation: if either side was float, result is float
    cmp r14b, TYPE_FLOAT
    jne .padd_type_done
    mov byte [cur_type], TYPE_FLOAT
.padd_type_done:
    ; emit: mov rbx, rax (48 89 C3)
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC3
    call emit_b
    ; emit: pop rax (58)
    mov al, 0x58
    call emit_b
    ; emit: add rax, rbx (48 01 D8)
    mov al, 0x48
    call emit_b
    mov al, 0x01
    call emit_b
    mov al, 0xD8
    call emit_b
    jmp .loop
.psub:
    call lexer_next
    movzx r14d, byte [cur_type]
    mov al, 0x50
    call emit_b
    call parse_multiplicative
    cmp r14b, TYPE_FLOAT
    jne .psub_type_done
    mov byte [cur_type], TYPE_FLOAT
.psub_type_done:
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC3
    call emit_b
    mov al, 0x58
    call emit_b
    ; emit: sub rax, rbx (48 29 D8)
    mov al, 0x48
    call emit_b
    mov al, 0x29
    call emit_b
    mov al, 0xD8
    call emit_b
    jmp .loop
.pband:
    call lexer_next
    mov al, 0x50
    call emit_b
    call parse_multiplicative
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC3
    call emit_b
    mov al, 0x58
    call emit_b
    ; emit: and rax, rbx (48 21 D8)
    mov al, 0x48
    call emit_b
    mov al, 0x21
    call emit_b
    mov al, 0xD8
    call emit_b
    jmp .loop
.pbor:
    call lexer_next
    mov al, 0x50
    call emit_b
    call parse_multiplicative
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC3
    call emit_b
    mov al, 0x58
    call emit_b
    ; emit: or rax, rbx (48 09 D8)
    mov al, 0x48
    call emit_b
    mov al, 0x09
    call emit_b
    mov al, 0xD8
    call emit_b
    jmp .loop
.pbxor:
    call lexer_next
    mov al, 0x50
    call emit_b
    call parse_multiplicative
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC3
    call emit_b
    mov al, 0x58
    call emit_b
    ; emit: xor rax, rbx (48 31 D8)
    mov al, 0x48
    call emit_b
    mov al, 0x31
    call emit_b
    mov al, 0xD8
    call emit_b
    jmp .loop

; --- parse_multiplicative (Level 3): handles *, /, %, <<, >> ---
parse_multiplicative:
    push rbp
    mov rbp, rsp
    push r14                    ; r14 = saved LHS type for propagation
    call parse_unary
.loop:
    movzx eax, byte [tok_type]
    cmp al, TOK_STAR
    je .pmul
    cmp al, TOK_SLASH
    je .pdiv
    cmp al, TOK_MOD
    je .pmod
    cmp al, TOK_SHL
    je .pshl
    cmp al, TOK_SHR
    je .pshr
    pop r14
    leave
    ret
.pmul:
    call lexer_next
    movzx r14d, byte [cur_type]
    mov al, 0x50
    call emit_b
    call parse_unary
    cmp r14b, TYPE_FLOAT
    jne .pmul_type_done
    mov byte [cur_type], TYPE_FLOAT
.pmul_type_done:
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC3
    call emit_b
    mov al, 0x58
    call emit_b
    ; emit: imul rax, rbx (48 0F AF C3)
    mov al, 0x48
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0xAF
    call emit_b
    mov al, 0xC3
    call emit_b
    jmp .loop
.pdiv:
    call lexer_next
    movzx r14d, byte [cur_type]
    mov al, 0x50
    call emit_b
    call parse_unary
    cmp r14b, TYPE_FLOAT
    jne .pdiv_type_done
    mov byte [cur_type], TYPE_FLOAT
.pdiv_type_done:
    ; emit: mov rbx, rax; pop rax; cqo; idiv rbx
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC3
    call emit_b
    mov al, 0x58
    call emit_b
    ; emit: cqo (48 99)
    mov al, 0x48
    call emit_b
    mov al, 0x99
    call emit_b
    ; emit: idiv rbx (48 F7 FB)
    mov al, 0x48
    call emit_b
    mov al, 0xF7
    call emit_b
    mov al, 0xFB
    call emit_b
    jmp .loop
.pmod:
    call lexer_next
    movzx r14d, byte [cur_type]
    mov al, 0x50
    call emit_b
    call parse_unary
    ; mod result is always int
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC3
    call emit_b
    mov al, 0x58
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0x99
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0xF7
    call emit_b
    mov al, 0xFB
    call emit_b
    ; emit: mov rax, rdx (48 89 D0) — remainder in rdx after idiv
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xD0
    call emit_b
    jmp .loop
.pshl:
    call lexer_next
    mov al, 0x50
    call emit_b
    call parse_unary
    ; emit: mov rcx, rax (48 89 C1)
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC1
    call emit_b
    ; emit: pop rax (58)
    mov al, 0x58
    call emit_b
    ; emit: shl rax, cl (48 D3 E0)
    mov al, 0x48
    call emit_b
    mov al, 0xD3
    call emit_b
    mov al, 0xE0
    call emit_b
    jmp .loop
.pshr:
    call lexer_next
    mov al, 0x50
    call emit_b
    call parse_unary
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC1
    call emit_b
    mov al, 0x58
    call emit_b
    ; emit: shr rax, cl (48 D3 E8)
    mov al, 0x48
    call emit_b
    mov al, 0xD3
    call emit_b
    mov al, 0xE8
    call emit_b
    jmp .loop

; --- parse_unary: handles ~ and unary - ---
parse_unary:
    push rbp
    mov rbp, rsp
    movzx eax, byte [tok_type]
    cmp al, TOK_BNOT
    je .bitnot
    cmp al, TOK_MINUS
    je .negate
    call parse_factor
    leave
    ret
.bitnot:
    call lexer_next
    call parse_unary
    ; emit: not rax (48 F7 D0)
    mov al, 0x48
    call emit_b
    mov al, 0xF7
    call emit_b
    mov al, 0xD0
    call emit_b
    leave
    ret
.negate:
    call lexer_next
    call parse_unary
    ; emit: neg rax (48 F7 D8)
    mov al, 0x48
    call emit_b
    mov al, 0xF7
    call emit_b
    mov al, 0xD8
    call emit_b
    leave
    ret

; --- parse_factor: handles atoms (int lit, float lit, str lit, bool, ident, paren) ---
parse_factor:
    push rbp
    mov rbp, rsp
    push rbx
    movzx eax, byte [tok_type]
    cmp al, TOK_INT_LIT
    je .int_lit
    cmp al, TOK_FLOAT_LIT
    je .float_lit
    cmp al, TOK_STR_LIT
    je .str_lit
    cmp al, TOK_TRUE
    je .bool_true
    cmp al, TOK_FALSE
    je .bool_false
    cmp al, TOK_UNKNOWN
    je .bool_unknown
    cmp al, TOK_IDENT
    je .ident
    cmp al, TOK_LPAREN
    je .paren
    cmp al, TOK_AT
    je .at_in_expr
    cmp al, TOK_LEN
    je .len_in_expr
    cmp al, TOK_CAP
    je .cap_in_expr
    cmp al, TOK_POP
    je .pop_in_expr
    cmp al, TOK_TYPEOF
    je .typeof_in_expr
    cmp al, TOK_TYPE_INT
    je .cast_int
    cmp al, TOK_TYPE_FLOAT
    je .cast_float
    ; Default: emit zero, treat as int
    xor eax, eax
    mov byte [cur_type], TYPE_INT
    pop rbx
    leave
    ret

.int_lit:
    ; emit: mov rax, imm64  (48 B8 <8 bytes>)
    mov al, 0x48
    call emit_b
    mov al, 0xB8
    call emit_b
    mov rax, [tok_int]
    call emit_q
    mov byte [cur_type], TYPE_INT
    call lexer_next
    pop rbx
    leave
    ret

.float_lit:
    ; emit: mov rax, imm64  (float bits)
    mov al, 0x48
    call emit_b
    mov al, 0xB8
    call emit_b
    mov rax, [tok_int]
    call emit_q
    mov byte [cur_type], TYPE_FLOAT
    call lexer_next
    pop rbx
    leave
    ret

.ident:
    lea rdi, [tok_ident]
    call var_find
    cmp rax, -1
    je .ident_done

    mov rbx, rax                       ; rbx = var index

    ; Determine type from var_table[rbx].type (offset +48)
    mov rax, rbx
    imul rax, VAR_ENTRY_SIZE
    lea rcx, [var_table]
    add rcx, rax
    movzx eax, byte [rcx+48]
    mov [cur_type], al

    ; emit: mov rax, [addr32]  (48 8B 04 25 <addr32>)
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    mov rdi, rbx
    call get_var_va
    call emit_d

    call lexer_next

    ; Check for dict subscript access: dict[key]
    movzx eax, byte [tok_type]
    cmp al, TOK_LBRACK
    jne .ident_done

    ; emit: push rax  (50) — save dict ptr
    mov al, 0x50
    call emit_b

    call lexer_next                    ; skip '['
    call parse_expr                    ; key -> rax

    ; expect and skip ']'
    call lexer_next

    ; emit: mov rsi, rax  (48 89 C6) — key
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC6
    call emit_b
    ; emit: pop rdi  (5F) — dict ptr
    mov al, 0x5F
    call emit_b
    ; emit: call rt_dict_get  (E8 <rel32>)
    mov al, 0xE8
    call emit_b
    mov rax, LOAD_BASE + RT_DICT_GET_OFFSET
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d
    mov byte [cur_type], TYPE_INT

.ident_done:
    pop rbx
    leave
    ret

.paren:
    call lexer_next                    ; skip '('
    call parse_expr
    call lexer_next                    ; skip ')'
    pop rbx
    leave
    ret

; --- @name(args) as an expression atom ---
; Calls a protocol and leaves return value in rax.
.at_in_expr:
    push r12
    call lexer_next                    ; skip '@', tok = protocol name
    lea rdi, [tok_ident]
    call proto_find                    ; rax = protocol offset or -1
    cmp rax, -1
    je .at_in_skip
    mov r12, rax                       ; save protocol offset
    call lexer_next                    ; skip name, tok = '('
    call emit_at_call_args             ; eval args, push/pop, advance past ')'
    mov rdi, r12
    call codegen_emit_call_prot
    mov byte [cur_type], TYPE_INT
    pop r12
    pop rbx
    leave
    ret
.at_in_skip:
    call lexer_next                    ; skip name
    call lexer_next                    ; skip '('
    call lexer_next                    ; skip ')'
    mov byte [cur_type], TYPE_INT
    pop r12
    pop rbx
    leave
    ret

; --- cap(expr) — load metadata capacity header into rax ---
.cap_in_expr:
    call lexer_next                    ; skip 'cap'
    cmp byte [tok_type], TOK_LPAREN
    jne .cap_no_paren
    call lexer_next                    ; skip '('
    call parse_expr                    ; evaluate collection expr -> rax
    call lexer_next                    ; skip ')'
    jmp .cap_emit
.cap_no_paren:
    call parse_expr                    ; evaluate collection expr -> rax
.cap_emit:
    ; Emit: mov rax, [rax-16]  (48 8B 40 F0) — load 8-byte hidden capacity prefix
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x40
    call emit_b
    mov al, 0xF0
    call emit_b
    mov byte [cur_type], TYPE_INT
    pop rbx
    leave
    ret

; --- len(expr) — load metadata length header into rax ---
.len_in_expr:
    call lexer_next                    ; skip 'len'
    push r12
    movzx r12d, byte [tok_type]        ; check if we have a paren
    cmp r12b, TOK_LPAREN
    jne .len_no_p
    call lexer_next
.len_no_p:
    call parse_expr                    ; evaluate expr -> rax; cur_type set

    ; Compile-time reflection for scalar types
    movzx eax, byte [cur_type]
    cmp al, TYPE_INT
    je .len_scalar_8
    cmp al, TYPE_FLOAT
    je .len_scalar_8
    cmp al, TYPE_BOOL
    je .len_scalar_1
    cmp al, TYPE_COMPLEX
    je .len_scalar_16
    jmp .len_runtime

.len_scalar_8:
    ; emit: mov rax, 8
    mov al, 0x48
    call emit_b
    mov al, 0xC7
    call emit_b
    mov al, 0xC0
    call emit_b
    mov eax, 8
    call emit_d
    jmp .len_done

.len_scalar_1:
    ; emit: mov rax, 1
    mov al, 0x48
    call emit_b
    mov al, 0xC7
    call emit_b
    mov al, 0xC0
    call emit_b
    mov eax, 1
    call emit_d
    jmp .len_done

.len_scalar_16:
    ; emit: mov rax, 16
    mov al, 0x48
    call emit_b
    mov al, 0xC7
    call emit_b
    mov al, 0xC0
    call emit_b
    mov eax, 16
    call emit_d
    jmp .len_done

.len_runtime:
    ; collections: emit: mov rax, [rax-8]
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x40
    call emit_b
    mov al, 0xF8
    call emit_b

.len_done:
    cmp r12b, TOK_LPAREN
    jne .len_exit
    call lexer_next                    ; skip ')'
.len_exit:
    mov byte [cur_type], TYPE_INT
    pop r12
    pop rbx
    leave
    ret

; --- typeof expr — return integer code for the expression's type ---
.typeof_in_expr:
    call lexer_next                    ; skip 'typeof'
    call parse_expr                    ; evaluate expression
    movzx edi, byte [cur_type]         ; result of expression parsing
    ; emit: mov rax, imm32  (48 C7 C0 <4 bytes>)
    mov al, 0x48
    call emit_b
    mov al, 0xC7
    call emit_b
    mov al, 0xC0
    call emit_b
    mov eax, edi
    call emit_d
    mov byte [cur_type], TYPE_INT
    pop rbx
    leave
    ret

; --- int(float_expr) — SSE2 truncate float to int ---
.cast_int:
    call lexer_next                    ; skip 'int'
    call lexer_next                    ; skip '('
    call parse_expr                    ; evaluate expr -> rax (float bits)
    call lexer_next                    ; skip ')'
    ; emit: movq xmm0, rax  (66 48 0F 6E C0)
    mov al, 0x66
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0x6E
    call emit_b
    mov al, 0xC0
    call emit_b
    ; emit: cvttsd2si rax, xmm0 (F2 48 0F 2C C0)
    mov al, 0xF2
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0x2C
    call emit_b
    mov al, 0xC0
    call emit_b
    mov byte [cur_type], TYPE_INT
    pop rbx
    leave
    ret

; --- float(int_expr) — SSE2 convert int to float ---
.cast_float:
    call lexer_next                    ; skip 'float'
    call lexer_next                    ; skip '('
    call parse_expr                    ; evaluate expr -> rax (int)
    call lexer_next                    ; skip ')'
    ; emit: cvtsi2sd xmm0, rax (F2 48 0F 2A C0)
    mov al, 0xF2
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0x2A
    call emit_b
    mov al, 0xC0
    call emit_b
    ; emit: movq rax, xmm0 (66 48 0F 7E C0)
    mov al, 0x66
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0x7E
    call emit_b
    mov al, 0xC0
    call emit_b
    mov byte [cur_type], TYPE_FLOAT
    pop rbx
    leave
    ret

; --- pop seq_name — decrement length, return former last element in rax ---
.pop_in_expr:
    call lexer_next                    ; skip 'pop', tok = seq var name
    lea rdi, [tok_ident]
    call var_find                      ; rax = var index or -1
    cmp rax, -1
    je .pop_in_err
    push rax                           ; save var index
    ; Emit: mov rbx, [var_addr]  (48 8B 1C 25 <addr>)  — load seq heap ptr
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x1C
    call emit_b
    mov al, 0x25
    call emit_b
    pop rdi
    call get_var_va
    call emit_d
    ; Emit: dec qword [rbx-8]  (48 FF 4B F8)  — decrement length
    mov al, 0x48
    call emit_b
    mov al, 0xFF
    call emit_b
    mov al, 0x4B
    call emit_b
    mov al, 0xF8
    call emit_b
    ; Emit: mov rcx, [rbx-8]  (48 8B 4B F8)  — load new length (index of popped)
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x4B
    call emit_b
    mov al, 0xF8
    call emit_b
    ; Emit: mov rax, [rbx+rcx*8+8]  (48 8B 44 CB 08)  — load popped value
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x44
    call emit_b
    mov al, 0xCB
    call emit_b
    mov al, 0x08
    call emit_b
    mov byte [cur_type], TYPE_INT
    call lexer_next
    pop rbx
    leave
    ret
.pop_in_err:
    mov byte [cur_type], TYPE_INT
    call lexer_next
    pop rbx
    leave
    ret

; ---- bool literals ----

.bool_true:
    ; emit: mov rax, 1  (48 B8 01 00 00 00 00 00 00 00)
    mov al, 0x48
    call emit_b
    mov al, 0xB8
    call emit_b
    mov rax, 1
    call emit_q
    mov byte [cur_type], TYPE_BOOL
    call lexer_next
    pop rbx
    leave
    ret

.bool_false:
    ; emit: mov rax, 0
    mov al, 0x48
    call emit_b
    mov al, 0xB8
    call emit_b
    xor rax, rax
    call emit_q
    mov byte [cur_type], TYPE_BOOL
    call lexer_next
    pop rbx
    leave
    ret

.bool_unknown:
    ; emit: rdrand eax (0F C7 F0) — hardware random bit
    mov al, 0x0F
    call emit_b
    mov al, 0xC7
    call emit_b
    mov al, 0xF0
    call emit_b
    ; emit: and rax, 1  (48 83 E0 01)
    mov al, 0x48
    call emit_b
    mov al, 0x83
    call emit_b
    mov al, 0xE0
    call emit_b
    mov al, 0x01
    call emit_b
    mov byte [cur_type], TYPE_BOOL
    call lexer_next
    pop rbx
    leave
    ret

; ---- string literal ----
; Emits the string inline in the code stream with a JMP over it, then
; loads the string's virtual address into RAX.
; Layout:
;   JMP <past_null>    (E9 <rel32>)   5 bytes
;   <8-byte metadata header: length>  8 bytes
;   <string bytes>                    len+1 bytes (includes null terminator)
;   MOV rax, string_va (48 B8 <q>)   10 bytes
.str_lit:
    push r12
    push r13
    push r14
    mov r13, [out_idx]          ; position of the JMP instruction

    ; emit: E9 00 00 00 00  (JMP with placeholder)
    mov al, 0xE9
    call emit_b
    xor eax, eax
    call emit_d

    ; Compute length of tok_ident
    lea rbx, [tok_ident]
    xor r14, r14
.sl_len:
    cmp byte [rbx+r14], 0
    je .sl_len_done
    inc r14
    jmp .sl_len
.sl_len_done:

    ; emit: 8-byte length prefix
    mov rax, r14
    call emit_q

    mov r12, [out_idx]          ; string data starts here; VA = LOAD_BASE + r12

    ; emit: string bytes from tok_ident (null-terminated)
    lea rbx, [tok_ident]
.str_loop:
    movzx eax, byte [rbx]
    call emit_b
    inc rbx
    test al, al
    jnz .str_loop               ; null byte is emitted last (al == 0 exits after emit)

    ; Patch JMP: rel32 = out_idx - (r13 + 5)
    mov rax, [out_idx]
    sub rax, r13
    sub rax, 5
    lea rcx, [out_buffer]
    mov dword [rcx+r13+1], eax  ; +1 to skip the E9 opcode

    ; emit: mov rax, string_VA  (48 B8 <imm64>)
    mov al, 0x48
    call emit_b
    mov al, 0xB8
    call emit_b
    mov rax, r12
    add rax, LOAD_BASE
    call emit_q

    mov byte [cur_type], TYPE_STR
    call lexer_next
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

; --- parse_dict_inline: handles { key: val, ... } dict literals ---
; On entry: tok_type == TOK_LBRACE
; On exit: rax at runtime holds the dict ptr; [cur_type] = TYPE_DICT
parse_dict_inline:
    push rbp
    mov rbp, rsp

    ; emit: call rt_dict_new  (E8 <rel32>)
    mov al, 0xE8
    call emit_b
    mov rax, LOAD_BASE + RT_DICT_NEW_OFFSET
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d

    call lexer_next                    ; skip '{'

    ; emit: push rax  (50) — save dict ptr on runtime stack
    mov al, 0x50
    call emit_b

.dict_loop:
    movzx eax, byte [tok_type]
    cmp al, TOK_RBRACE
    je .dict_done
    cmp al, TOK_EOF
    je .dict_done

    ; Parse key expression -> rax
    call parse_expr

    ; emit: push rax  (50) — save key
    mov al, 0x50
    call emit_b

    ; Skip ':'
    call lexer_next

    ; Parse value expression -> rax
    call parse_expr

    ; emit: mov rdx, rax  (48 89 C2) — value
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC2
    call emit_b

    ; emit: pop rsi  (5E) — key
    mov al, 0x5E
    call emit_b

    ; emit: mov rdi, [rsp]  (48 8B 3C 24) — peek dict ptr without popping
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x3C
    call emit_b
    mov al, 0x24
    call emit_b

    ; emit: call rt_dict_set  (E8 <rel32>)
    mov al, 0xE8
    call emit_b
    mov rax, LOAD_BASE + RT_DICT_SET_OFFSET
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d

    ; If comma, consume it and continue
    movzx eax, byte [tok_type]
    cmp al, TOK_COMMA
    jne .dict_loop
    call lexer_next
    jmp .dict_loop

.dict_done:
    call lexer_next                    ; skip '}'

    ; emit: pop rax  (58) — restore dict ptr as function result
    mov al, 0x58
    call emit_b

    mov byte [cur_type], TYPE_DICT
    leave
    ret
