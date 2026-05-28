; -----------------------------------------------------------------------------
; Rex V5.0 Parser
; Recursive descent parser for the Rex language.
; Handles statement parsing, variable management, and protocol tracking.
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
extern out_idx

section .bss
    var_table:       resb VAR_ENTRY_SIZE * VAR_MAX ; Symbol table for variables
    var_count:       resq 1                        ; Current variable count
    proto_table:     resb 40 * 32                  ; Symbol table for protocols
    proto_count:     resq 1                        ; Current protocol count
    prot_body_depth: resq 1                        ; Depth of nested protocol definitions
    saved_name:      resb 64                       ; Temporary buffer for identifiers

section .data
    err_id:    db "error: expected identifier", 10
    err_id_l   equ $ - err_id

section .text

; -----------------------------------------------------------------------------
; strcpy
; Utility: Copy null-terminated string.
; RDI: destination, RSI: source
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
; fatal
; Error reporting and termination.
; RDI: error string, RSI: length
; -----------------------------------------------------------------------------
fatal:
    push rbp
    mov rbp, rsp

    mov r9, rdx                 ; length
    mov r8, rsi                 ; string ptr

    mov rax, 1                  ; sys_write
    mov rdi, 2                  ; stderr
    mov rsi, r8
    mov rdx, r9
    syscall

    mov rax, 60                 ; sys_exit
    mov rdi, 1
    syscall

; -----------------------------------------------------------------------------
; var_find
; Finds a variable in the symbol table.
; Input: RDI = name pointer
; Output: RAX = index or -1
; -----------------------------------------------------------------------------
var_find:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rsi
    push rdi

    xor rcx, rcx                ; Loop index
.l:
    cmp rcx, [var_count]
    jge .nf

    mov rax, rcx
    imul rax, VAR_ENTRY_SIZE
    lea rsi, [var_table]
    add rsi, rax                ; Candidate pointer
    mov rdi, [rbp-32]           ; target pointer (RESET EACH LOOP)

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
; var_add
; Adds a variable to the symbol table.
; -----------------------------------------------------------------------------
var_add:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                ; name
    mov r13, rsi                ; val
    mov r14b, dl                ; is_init
    mov r15b, cl                ; type

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
; parse_stmt
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
    mov r11, [tok_int]

    cmp al, TOK_TRUE
    jne .check_false
    mov r11, 1
    jmp .do_add
.check_false:
    cmp al, TOK_FALSE
    jne .check_unknown
    mov r11, 0
    jmp .do_add
.check_unknown:
    cmp al, TOK_UNKNOWN
    jne .do_add

.do_add:
    lea rdi, [saved_name]
    mov rsi, r11
    mov dl, 1
    mov cl, r15b
    call var_add

    mov r14, rax
    mov rdi, r14
    movzx eax, byte [tok_type]
    cmp al, TOK_UNKNOWN
    je .emit_unknown

    mov rsi, r11
    call codegen_emit_assign_var
    jmp .after_init

.emit_unknown:
    call codegen_emit_unknown_bool

.after_init:
    call lexer_next
    jmp .done

.id_error:
    lea rsi, [err_id]
    mov rdx, err_id_l
    call fatal

.assign:
    call lexer_next
    cmp byte [tok_type], TOK_IDENT
    jne .done

    sub rsp, 64
    mov rdi, rsp
    lea rsi, [tok_ident]
    call strcpy

    call lexer_next             ; skip ident
    call lexer_next             ; skip '='

    movzx eax, byte [tok_type]
    cmp al, TOK_IDENT
    je .parse_expr

    mov r11, [tok_int]
    cmp al, TOK_TRUE
    jne .a_nt
    mov r11, 1
.a_nt:
    cmp al, TOK_FALSE
    jne .a_nf
    mov r11, 0
.a_nf:
    mov rdi, rsp
    call var_find
    cmp rax, -1
    je .e_as

    mov r14, rax
    imul rax, rax, VAR_ENTRY_SIZE
    lea rcx, [var_table]
    add rcx, rax
    mov [rcx+32], r11

    mov rdi, r14
    movzx eax, byte [tok_type]
    cmp al, TOK_UNKNOWN
    je .a_gu
    mov rsi, r11
    call codegen_emit_assign_var
    jmp .a_ad
.a_gu:
    call codegen_emit_unknown_bool
.a_ad:
    call lexer_next
    add rsp, 64
    jmp .done

.parse_expr:
    lea rdi, [tok_ident]
    call var_find
    mov r12, rax                ; src1 index

    call lexer_next             ; op
    movzx r13, byte [tok_type]

    call lexer_next             ; src2
    lea rdi, [tok_ident]
    call var_find
    mov r14, rax                ; src2 index

    mov rdi, rsp
    call var_find
    mov rbx, rax                ; dest index

    imul rax, rax, VAR_ENTRY_SIZE
    lea rcx, [var_table]
    add rcx, rax
    movzx edx, byte [rcx+48]    ; type

    xor rcx, rcx
    cmp r13b, TOK_PLUS
    je .op_emit
    inc rcx

.op_emit:
    cmp dl, TYPE_FLOAT
    je .emit_f
    cmp dl, TYPE_COMPLEX
    je .emit_c
.emit_f:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r14
    call codegen_emit_float_op
    jmp .expr_done
.emit_c:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r14
    call codegen_emit_complex_op

.expr_done:
    call lexer_next
    add rsp, 64
    jmp .done

.e_as:
    add rsp, 64
    jmp .done

.output:
    call lexer_next
    cmp byte [tok_type], TOK_INT_LIT
    cmp byte [tok_type], TOK_FLOAT_LIT
    je .o_float_lit
    je .o_lit
    cmp byte [tok_type], TOK_IDENT
    jne .done

    sub rsp, 64
    mov rdi, rsp
    lea rsi, [tok_ident]
    call strcpy
    mov rdi, rsp
    call var_find
    cmp rax, -1
    je .o_er

    mov r14, rax
    imul rax, rax, VAR_ENTRY_SIZE
    lea rcx, [var_table]
    add rcx, rax
    mov rdi, r14
    movzx esi, byte [rcx+48]
    call codegen_output_typed
    call lexer_next

.o_er:
    add rsp, 64
    jmp .done

.o_float_lit:
    mov rdi, [tok_int]
    extern codegen_output_float_const
    call codegen_output_float_const
    call lexer_next
    jmp .done
.o_lit:
    mov rdi, [tok_int]
    call codegen_output_const
    call lexer_next
    jmp .done

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

.return:
    call lexer_next
    mov rdi, [tok_int]
    call codegen_emit_mov_eax_imm32
    call codegen_emit_ret
    call lexer_next
    jmp .done

.stop:
    call codegen_emit_break
    call lexer_next
    jmp .done

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
; proto_find
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
    mov rsi, r12                 ; target
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
