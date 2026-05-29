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
extern codegen_emit_store_rax_var

section .bss
    var_table:       resb VAR_ENTRY_SIZE * VAR_MAX
    var_count:       resq 1
    proto_table:     resb 40 * 32
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

; --- output expr ---
; Fixed: old code had double-cmp bug overwriting flags.
; New code uses parse_expr so all expression types work.
.output:
    call lexer_next
    call parse_expr
    movzx eax, byte [cur_type]
    cmp al, TYPE_FLOAT
    je .out_float
    call codegen_output_rax_int
    jmp .done
.out_float:
    call codegen_output_rax_float
    jmp .done

; --- if / elif / else ---
.if:
    call codegen_save_chain_base
.if_next:
    call lexer_next
    sub rsp, 64
    mov rdi, rsp
    lea rsi, [tok_ident]
    call strcpy
    mov rdi, rsp
    call var_find
    cmp rax, -1
    je .if_err
    mov r14, rax
    call lexer_next
    call lexer_next
    mov r11, [tok_int]
    movzx eax, byte [tok_type]
    cmp al, TOK_TRUE
    jne .if_nt
    mov r11, 1
.if_nt:
    cmp al, TOK_FALSE
    jne .if_nf
    mov r11, 0
.if_nf:
    mov rdi, r14
    mov rsi, r11
    call codegen_emit_cmp_var_jne
    add rsp, 64
    call lexer_next
    call lexer_next
    cmp byte [tok_type], TOK_NEWLINE
    jne .if_no_nl
    call lexer_next
.if_no_nl:
    cmp byte [tok_type], TOK_INDENT
    jne .if_single
    call lexer_next
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
.if_err:
    add rsp, 64
    jmp .done

; --- for loop ---
.for:
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
.while:
    call lexer_next
    mov r15, [out_idx]
    sub rsp, 64
    mov rdi, rsp
    lea rsi, [tok_ident]
    call strcpy
    mov rdi, rsp
    call var_find
    cmp rax, -1
    je .w_er
    mov r14, rax
    call lexer_next
    call lexer_next
    mov r11, [tok_int]
    mov rsi, r11
    mov rdi, r14
    call codegen_emit_cmp_var_jne
    add rsp, 64
    call lexer_next
    call lexer_next
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
    call codegen_emit_while_end
    jmp .done
.w_er:
    add rsp, 64
    jmp .done

; --- protocol definition ---
.protocol:
    inc qword [prot_body_depth]
    call codegen_begin_protos
    call lexer_next
    mov rax, [proto_count]
    imul rax, 40
    lea r13, [proto_table]
    add r13, rax
    lea rsi, [tok_ident]
    mov rdi, r13
    call strcpy
    mov rbx, [out_idx]
    mov [r13+32], rbx
    inc qword [proto_count]
    call lexer_next
    call lexer_next
    call lexer_next
    call lexer_next
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
.return:
    call lexer_next
    mov rdi, [tok_int]
    call codegen_emit_mov_eax_imm32
    call codegen_emit_ret
    call lexer_next
    jmp .done

; --- stop (break) ---
.stop:
    call codegen_emit_break
    call lexer_next
    jmp .done

; --- @protocol_call ---
.at_call:
    call lexer_next
    lea rdi, [tok_ident]
    call proto_find
    cmp rax, -1
    je .done
    mov rdi, rax
    call codegen_emit_call_prot
    call lexer_next
    call lexer_next
    call lexer_next
    jmp .done

; --- use mm ... ---
; Note: 'use mm pool gc mark_sweep:' — hardcoded pool check via first char 'p'
.use_mm:
    call lexer_next
    call lexer_next
    call lexer_next
    cmp byte [tok_ident], 'p'
    sete al
    movzx edi, al
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
    imul rax, 40
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

; --- parse_expr — top-level expression entry point ---
parse_expr:
    push rbp
    mov rbp, rsp
    call parse_bitor
    leave
    ret

; --- parse_bitor: handles | ---
parse_bitor:
    push rbp
    mov rbp, rsp
    call parse_bitxor
.loop:
    movzx eax, byte [tok_type]
    cmp al, TOK_BOR
    jne .done
    call lexer_next
    mov al, 0x50
    call emit_b
    call parse_bitxor
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
    ; emit: or rax, rbx (48 09 D8)
    mov al, 0x48
    call emit_b
    mov al, 0x09
    call emit_b
    mov al, 0xD8
    call emit_b
    jmp .loop
.done:
    leave
    ret

; --- parse_bitxor: handles ^ ---
parse_bitxor:
    push rbp
    mov rbp, rsp
    call parse_bitand
.loop:
    movzx eax, byte [tok_type]
    cmp al, TOK_BXOR
    jne .done
    call lexer_next
    mov al, 0x50
    call emit_b
    call parse_bitand
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
.done:
    leave
    ret

; --- parse_bitand: handles & ---
parse_bitand:
    push rbp
    mov rbp, rsp
    call parse_cmp
.loop:
    movzx eax, byte [tok_type]
    cmp al, TOK_BAND
    jne .done
    call lexer_next
    mov al, 0x50
    call emit_b
    call parse_cmp
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
.done:
    leave
    ret

; --- parse_cmp: handles ==, !=, <, >, <=, >= ---
parse_cmp:
    push rbp
    mov rbp, rsp
    call parse_shift
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
    call parse_shift
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
    call parse_shift
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
    call parse_shift
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
    call parse_shift
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
    call parse_shift
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
    call parse_shift
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

; --- parse_shift: handles <<, >> ---
parse_shift:
    push rbp
    mov rbp, rsp
    call parse_additive
.loop:
    movzx eax, byte [tok_type]
    cmp al, TOK_SHL
    je .pshl
    cmp al, TOK_SHR
    je .pshr
    leave
    ret
.pshl:
    call lexer_next
    mov al, 0x50
    call emit_b
    call parse_additive
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
    call parse_additive
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

; --- parse_additive: handles +, - ---
parse_additive:
    push rbp
    mov rbp, rsp
    call parse_term
.loop:
    movzx eax, byte [tok_type]
    cmp al, TOK_PLUS
    je .padd
    cmp al, TOK_MINUS
    je .psub
    leave
    ret
.padd:
    call lexer_next
    mov al, 0x50
    call emit_b
    call parse_term
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
    mov al, 0x50
    call emit_b
    call parse_term
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

; --- parse_term: handles *, /, % ---
parse_term:
    push rbp
    mov rbp, rsp
    call parse_unary
.loop:
    movzx eax, byte [tok_type]
    cmp al, TOK_STAR
    je .pmul
    cmp al, TOK_SLASH
    je .pdiv
    cmp al, TOK_MOD
    je .pmod
    leave
    ret
.pmul:
    call lexer_next
    mov al, 0x50
    call emit_b
    call parse_unary
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
    mov al, 0x50
    call emit_b
    call parse_unary
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
    mov al, 0x50
    call emit_b
    call parse_unary
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

; --- parse_factor: handles atoms (int lit, float lit, ident, paren) ---
parse_factor:
    push rbp
    mov rbp, rsp
    push rbx
    movzx eax, byte [tok_type]
    cmp al, TOK_INT_LIT
    je .int_lit
    cmp al, TOK_FLOAT_LIT
    je .float_lit
    cmp al, TOK_IDENT
    je .ident
    cmp al, TOK_LPAREN
    je .paren
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
