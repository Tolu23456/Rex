default rel
%include "include/rex_defs.inc"
global parse_stmt
extern lexer_init, lexer_next, tok_type, tok_int, tok_ident
extern codegen_output_const, codegen_output_typed, codegen_patch_jump, codegen_save_chain_base, codegen_emit_jmp_end, codegen_patch_chain_end
extern codegen_begin_protos, codegen_end_protos, codegen_emit_for_start, codegen_emit_for_end, codegen_emit_while_start, codegen_emit_while_end
extern codegen_emit_break, codegen_patch_breaks, codegen_emit_ret, codegen_emit_mov_eax_imm32, codegen_emit_call_prot, codegen_emit_assign_var, codegen_emit_cmp_var_jne, codegen_emit_unknown_bool
extern codegen_emit_mm_switch, codegen_emit_loop_base, out_idx
section .bss
var_table: resb VAR_ENTRY_SIZE * VAR_MAX
    var_count: resq 1
    proto_table: resb 40 * 32
    proto_count: resq 1
    prot_body_depth: resq 1
    saved_name: resb 64
section .data
err_id: db "error: expected identifier", 10
    err_id_l equ $ - err_id
section .text
strcpy: push rbp
    mov rbp, rsp
    push rsi
    push rdi
.l: movzx eax, byte [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .l
    pop rdi
    pop rsi
    leave
    ret
fatal: push rbp
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
var_find: push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rsi
    push rdi
    xor rcx, rcx
.l: cmp rcx, [var_count]
    jge .nf
    mov rax, rcx
    imul rax, VAR_ENTRY_SIZE
    lea rsi, [var_table]
    add rsi, rax
    mov rdi, [rbp-32]
.c: movzx eax, byte [rdi]
    movzx edx, byte [rsi]
    cmp al, dl
    jne .next
    test al, al
    jz .match
    inc rdi
    inc rsi
    jmp .c
.match: mov rax, rcx
    jmp .done
.next: inc rcx
    jmp .l
.nf: mov rax, -1
.done: pop rdi
    pop rsi
    pop rcx
    pop rbx
    leave
    ret
var_add: push rbp
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
.full: mov rax, -1
.done: pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
parse_stmt: push rbp
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
.s1: cmp al, TOK_TYPE_INT
    je .pi
    cmp al, TOK_TYPE_FLOAT
    je .pf
    cmp al, TOK_TYPE_BOOL
    je .pb
    cmp al, TOK_TYPE_STR
    je .ps
    cmp al, TOK_TYPE_COMPLEX
    je .pc
    cmp al, TOK_COLON
    je .assign
    cmp al, TOK_OUTPUT
    je .out
    cmp al, TOK_IF
    je .if
    cmp al, TOK_FOR
    je .for
    cmp al, TOK_WHILE
    je .while
    cmp al, TOK_PROT
    je .prot
    cmp al, TOK_RETURN
    je .ret
    cmp al, TOK_STOP
    je .stop
    cmp al, TOK_AT
    je .at
    cmp al, TOK_USE
    je .use
    call lexer_next
    jmp .done
.pf: mov r15b, TYPE_FLOAT
    jmp .pg
.pb: mov r15b, TYPE_BOOL
    jmp .pg
.ps: mov r15b, TYPE_STR
    jmp .pg
.pc: mov r15b, TYPE_COMPLEX
    jmp .pg
.pi: mov r15b, TYPE_INT
.pg: call lexer_next
    cmp byte [tok_type], TOK_IDENT
    jne .err
    lea rsi, [tok_ident]
    lea rdi, [saved_name]
    call strcpy
    call lexer_next
    cmp byte [tok_type], TOK_ASSIGN
    je .pinit
    lea rdi, [saved_name]
    xor rsi, rsi
    mov dl, 0
    mov cl, r15b
    call var_add
    jmp .done
.pinit: call lexer_next
    movzx eax, byte [tok_type]
    mov r11, [tok_int]
    cmp al, TOK_TRUE
    jne .nt
    mov r11, 1
    jmp .nu
.nt: cmp al, TOK_FALSE
    jne .nf
    mov r11, 0
    jmp .nu
.nf: cmp al, TOK_UNKNOWN
    jne .nu
.nu: lea rdi, [saved_name]
    mov rsi, r11
    mov dl, 1
    mov cl, r15b
    call var_add
    mov r14, rax
    mov rdi, r14
    movzx eax, byte [tok_type]
    cmp al, TOK_UNKNOWN
    je .gu
    mov rsi, r11
    call codegen_emit_assign_var
    jmp .gd
.gu: call codegen_emit_unknown_bool
.gd: call lexer_next
    jmp .done
.err: lea rsi, [err_id]
    mov rdx, err_id_l
    call fatal
.assign: call lexer_next
    cmp byte [tok_type], TOK_IDENT
    jne .done
    sub rsp, 64
    mov rdi, rsp
    lea rsi, [tok_ident]
    call strcpy
    call lexer_next
    call lexer_next
    mov r11, [tok_int]
    movzx eax, byte [tok_type]
    cmp al, TOK_TRUE
    jne .ant
    mov r11, 1
.ant: cmp al, TOK_FALSE
    jne .anf
    mov r11, 0
.anf: mov rdi, rsp
    call var_find
    cmp rax, -1
    je .eas
    mov r14, rax
    imul rax, rax, VAR_ENTRY_SIZE
    lea rcx, [var_table]
    add rcx, rax
    mov [rcx+32], r11
    mov rdi, r14
    movzx eax, byte [tok_type]
    cmp al, TOK_UNKNOWN
    je .agu
    mov rsi, r11
    call codegen_emit_assign_var
    jmp .ad
.agu: call codegen_emit_unknown_bool
.ad: call lexer_next
.eas: add rsp, 64
    jmp .done
.out: call lexer_next
    cmp byte [tok_type], TOK_INT_LIT
    je .ol
    cmp byte [tok_type], TOK_IDENT
    jne .done
    sub rsp, 64
    mov rdi, rsp
    lea rsi, [tok_ident]
    call strcpy
    mov rdi, rsp
    call var_find
    cmp rax, -1
    je .oer
    mov r14, rax
    imul rax, rax, VAR_ENTRY_SIZE
    lea rcx, [var_table]
    add rcx, rax
    mov rdi, r14
    movzx esi, byte [rcx+48]
    call codegen_output_typed
    call lexer_next
.oer: add rsp, 64
    jmp .done
.ol: mov rdi, [tok_int]
    call codegen_output_const
    call lexer_next
    jmp .done
.if: call codegen_save_chain_base
.ifn: call lexer_next
    sub rsp, 64
    mov rdi, rsp
    lea rsi, [tok_ident]
    call strcpy
    mov rdi, rsp
    call var_find
    cmp rax, -1
    je .ife
    mov r14, rax
    call lexer_next
    call lexer_next
    mov r11, [tok_int]
    movzx eax, byte [tok_type]
    cmp al, TOK_TRUE
    jne .ifnt
    mov r11, 1
.ifnt: cmp al, TOK_FALSE
    jne .ifnf
    mov r11, 0
.ifnf: mov rdi, r14
    mov rsi, r11
    call codegen_emit_cmp_var_jne
    add rsp, 64
    call lexer_next
    call lexer_next
    cmp byte [tok_type], TOK_NEWLINE
    jne .ifnn
    call lexer_next
.ifnn: cmp byte [tok_type], TOK_INDENT
    jne .ifb
    call lexer_next
    mov r13, 1
    jmp .ifbl
.ifb: xor r13, r13
.ifbl: movzx eax, byte [tok_type]
    cmp al, TOK_EOF
    je .ifen
    cmp al, TOK_DEDENT
    je .ifen
    call parse_stmt
    test r13, r13
    jnz .ifbl
.ifen: test r13, r13
    jz .ifad
    cmp byte [tok_type], TOK_DEDENT
    jne .ifad
    call lexer_next
.ifad: movzx eax, byte [tok_type]
    cmp al, TOK_ELIF
    je .elif
    cmp al, TOK_ELSE
    je .else
    call codegen_patch_jump
    call codegen_patch_chain_end
    jmp .done
.elif: call codegen_emit_jmp_end
    call codegen_patch_jump
    jmp .ifn
.else: call codegen_emit_jmp_end
    call codegen_patch_jump
    call lexer_next
    call lexer_next
    cmp byte [tok_type], TOK_NEWLINE
    jne .elnn
    call lexer_next
.elnn: cmp byte [tok_type], TOK_INDENT
    jne .elb
    call lexer_next
    mov r13, 1
    jmp .elbl
.elb: xor r13, r13
.elbl: movzx eax, byte [tok_type]
    cmp al, TOK_EOF
    je .elen
    cmp al, TOK_DEDENT
    je .elen
    call parse_stmt
    test r13, r13
    jnz .elbl
.elen: test r13, r13
    jz .eldo
    cmp byte [tok_type], TOK_DEDENT
    jne .eldo
    call lexer_next
.eldo: call codegen_patch_chain_end
    jmp .done
.ife: add rsp, 64
    jmp .done
.for: call lexer_next
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
.forl: movzx eax, byte [tok_type]
    cmp al, TOK_EOF
    je .ford
    cmp al, TOK_DEDENT
    je .ford
    call parse_stmt
    jmp .forl
.ford: cmp byte [tok_type], TOK_DEDENT
    jne .fornd
    call lexer_next
.fornd: mov rdi, r15
    mov rsi, r14
    call codegen_emit_for_end
    jmp .done
.while: call lexer_next
    mov r15, [out_idx]
    sub rsp, 64
    mov rdi, rsp
    lea rsi, [tok_ident]
    call strcpy
    mov rdi, rsp
    call var_find
    cmp rax, -1
    je .wer
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
call codegen_emit_loop_base
.whilel: movzx eax, byte [tok_type]
    cmp al, TOK_EOF
    je .whiled
    cmp al, TOK_DEDENT
    je .whiled
    call parse_stmt
    jmp .whilel
.whiled: cmp byte [tok_type], TOK_DEDENT
    jne .whilend
    call lexer_next
.whilend: mov rdi, r15
    call codegen_emit_while_end
    jmp .done
.wer: add rsp, 64
    jmp .done
.prot: inc qword [prot_body_depth]
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
.protl: movzx eax, byte [tok_type]
    cmp al, TOK_EOF
    je .protd
    cmp al, TOK_DEDENT
    je .protd
    call parse_stmt
    jmp .protl
.protd: cmp byte [tok_type], TOK_DEDENT
    jne .protnd
    call lexer_next
.protnd: call codegen_emit_ret
    dec qword [prot_body_depth]
    jmp .done
.ret: call lexer_next
    mov rdi, [tok_int]
    call codegen_emit_mov_eax_imm32
    call codegen_emit_ret
    call lexer_next
    jmp .done
.stop: call codegen_emit_break
    call lexer_next
    jmp .done
.at: call lexer_next
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
.use:
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
    call lexer_next
    cmp byte [tok_type], TOK_NEWLINE
    jne .un
    call lexer_next
.un: cmp byte [tok_type], TOK_INDENT
    jne .ub
    call lexer_next
    mov r13, 1
    jmp .ubl
.ub: xor r13, r13
.ubl: movzx eax, byte [tok_type]
    cmp al, TOK_EOF
    je .uen
    cmp al, TOK_DEDENT
    je .uen
    call parse_stmt
    test r13, r13
    jnz .ubl
.uen: test r13, r13
    jz .udo
    cmp byte [tok_type], TOK_DEDENT
    jne .udo
    call lexer_next
.udo: xor rdi, rdi
    call codegen_emit_mm_switch
    jmp .done
.done: pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
proto_find: push rbp
    mov rbp, rsp
    push r12
    push r13
    push rbx
    mov r12, rdi
    xor r13, r13
.l: cmp r13, [proto_count]
    jge .nf
    mov rax, r13
    imul rax, 40
    lea rbx, [proto_table]
    add rbx, rax
    mov rdi, rbx
    mov rsi, r12
    mov ecx, 32
.cl: movzx eax, byte [rdi]
    movzx edx, byte [rsi]
    cmp eax, edx
    jne .nm
    test eax, eax
    jz .m
    inc rdi
    inc rsi
    dec ecx
    jnz .cl
.m: mov rax, [rbx+32]
    jmp .done
.nm: inc r13
    jmp .l
.nf: mov rax, -1
.done: pop rbx
    pop r13
    pop r12
    leave
    ret
