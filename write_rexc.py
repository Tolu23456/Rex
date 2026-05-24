import sys

asm = r"""; rexc.asm - The Rex Compiler
%include "common.inc"
%include "tokens.inc"

section .bss
    file_fd   resq 1
    file_buf  resb 1048576
    file_len  resq 1
    c_tok_t   resq 1
    c_tok_v   resq 1
    tok_v_str resb 256
    src_p     resq 1
    src_e     resq 1
    ln_num    resq 1
    at_ls     resb 1
    ind_stk   resq 128
    ind_ptr   resq 1
    pen_d     resq 1
    s_tbl     resb 65536
    s_cnt     resq 1
    st_off    resq 1
    c_buf     resb 1048576
    c_ptr     resq 1
    o_fd      resq 1
    rt_base   resq 1

section .data
    align 8
    e_hdr:
        db 0x7F, 'E', 'L', 'F', 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0
        dw 2, 62, 1, 0
        dq 0x400080
        dq 64, 0, 0
        dw 64, 56, 1, 0, 0, 0
    p_hdr:
        dd 1, 7
        dq 0, 0x400000, 0x400000, 0, 0, 0x1000

    usage_msg db "Usage: rexc <file.rex>", 10
    usage_len equ $ - usage_msg
    o_nm      db "output", 0

    kw_tbl:
        dq .s_prot, TOK_PROT
        dq .s_ret,  TOK_RETURN
        dq .s_if,   TOK_IF
        dq .s_else, TOK_ELSE
        dq .s_for,  TOK_FOR
        dq .s_in,   TOK_IN
        dq .s_out,  TOK_OUTPUT
        dq .s_int,  TOK_INT
        dq .s_unkn, TOK_UNKNOWN
        dq 0, 0
    .s_prot db "prot", 0
    .s_ret  db "return", 0
    .s_if   db "if", 0
    .s_else db "else", 0
    .s_for  db "for", 0
    .s_in   db "in", 0
    .s_out  db "output", 0
    .s_int  db "int", 0
    .s_unkn db "unknown", 0

section .text
    global _start
_start:
    pop rax
    cmp rax, 2
    jl .u
    pop rax
    pop rdi
    mov rax, SYS_OPEN
    xor rsi, rsi
    syscall
    test rax, rax
    js .err
    mov [file_fd], rax
    mov rdi, rax
    mov rax, SYS_READ
    mov rsi, file_buf
    mov rdx, 1048576
    syscall
    mov [file_len], rax
    mov rdi, file_buf
    mov rsi, [file_len]
    call rex_lex_init
    call rex_codegen_init
    call rex_parse
    mov rax, SYS_EXIT
    xor rdi, rdi
    syscall
.u:
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, usage_msg
    mov rdx, usage_len
    syscall
.err:
    mov rax, SYS_EXIT
    mov rdi, 1
    syscall

rex_lex_init:
    mov [src_p], rdi
    add rsi, rdi
    mov [src_e], rsi
    mov qword [ln_num], 1
    mov byte [at_ls], 1
    mov qword [pen_d], 0
    mov qword [ind_stk], 0
    lea rax, [ind_stk + 8]
    mov [ind_ptr], rax
    ret

rex_lex_next:
    mov rax, [pen_d]
    test rax, rax
    jz .no_p
    dec qword [pen_d]
    sub qword [ind_ptr], 8
    mov rax, TOK_DEDENT
    ret
.no_p:
    mov rsi, [src_p]
.skp:
    cmp rsi, [src_e]
    jae .eof
    cmp byte [at_ls], 0
    jz .nls
    call handle_indentation
    test rax, rax
    jnz .done
    mov rsi, [src_p]
.nls:
    cmp rsi, [src_e]
    jae .eof
    mov al, [rsi]
    cmp al, ' '
    je .inc
    cmp al, 9
    je .inc
    cmp al, '#'
    je .com
    cmp al, 10
    je .nl
    mov byte [at_ls], 0
    cmp al, ':'
    je .t_col
    cmp al, '='
    je .t_eq
    cmp al, '+'
    je .t_pls
    cmp al, '*'
    je .t_mul
    cmp al, '.'
    je .t_dot
    cmp al, '('
    je .t_lp
    cmp al, ')'
    je .t_rp
    cmp al, ','
    je .t_cm
    call is_alpha
    test rax, rax
    jnz .l_id
    call is_digit
    test rax, rax
    jnz .l_nm
    inc rsi
    mov [src_p], rsi
    jmp .no_p
.inc:
    inc rsi
    mov [src_p], rsi
    jmp .skp
.com:
    inc rsi
.cl:
    cmp rsi, [src_e]
    jae .eof
    cmp byte [rsi], 10
    je .nl
    inc rsi
    jmp .cl
.nl:
    inc rsi
    mov [src_p], rsi
    inc qword [ln_num]
    mov byte [at_ls], 1
    mov rax, TOK_NEWLINE
    ret
.t_col: inc rsi
    mov [src_p], rsi
    mov rax, TOK_COLON
    ret
.t_eq:
    inc rsi
    cmp byte [rsi], '='
    je .t_e2
    mov [src_p], rsi
    mov rax, TOK_ASSIGN
    ret
.t_e2:
    inc rsi
    mov [src_p], rsi
    mov rax, TOK_EQ
    ret
.t_pls: inc rsi
    mov [src_p], rsi
    mov rax, TOK_PLUS
    ret
.t_mul: inc rsi
    mov [src_p], rsi
    mov rax, TOK_MUL
    ret
.t_dot:
    inc rsi
    cmp byte [rsi], '.'
    je .t_d2
    mov [src_p], rsi
    mov rax, TOK_DOT
    ret
.t_d2:
    inc rsi
    mov [src_p], rsi
    mov rax, TOK_DOTDOT
    ret
.t_lp: inc rsi
    mov [src_p], rsi
    mov rax, TOK_LPAREN
    ret
.t_rp: inc rsi
    mov [src_p], rsi
    mov rax, TOK_RPAREN
    ret
.t_cm: inc rsi
    mov [src_p], rsi
    mov rax, TOK_COMMA
    ret
.l_id:
    xor rcx, rcx
.idl:
    mov al, [rsi]
    call is_alnum
    test rax, rax
    jz .idd
    mov [tok_v_str + rcx], al
    inc rcx
    inc rsi
    jmp .idl
.idd:
    mov [src_p], rsi
    mov byte [tok_v_str + rcx], 0
    mov rsi, kw_tbl
.kwl:
    mov rdi, [rsi]
    test rdi, rdi
    jz .nkw
    push rsi
    lea rsi, [tok_v_str]
    call rex_strcmp
    pop rsi
    test rax, rax
    jnz .ikw
    add rsi, 16
    jmp .kwl
.ikw:
    mov rax, [rsi + 8]
    ret
.nkw:
    mov rax, TOK_IDENT
    lea rdx, [tok_v_str]
    mov [c_tok_v], rdx
    ret
.l_nm:
    xor rbx, rbx
.nml:
    mov al, [rsi]
    call is_digit
    test rax, rax
    jz .nmd
    sub al, '0'
    movzx rax, al
    imul rbx, 10
    add rbx, rax
    inc rsi
    jmp .nml
.nmd:
    mov [src_p], rsi
    mov rax, TOK_LIT_INT
    mov [c_tok_v], rbx
    ret
.eof:
    mov rbx, [ind_ptr]
    sub rbx, ind_stk
    shr rbx, 3
    cmp rbx, 1
    jle .reof
    mov qword [pen_d], rbx
    sub qword [pen_d], 2
    sub qword [ind_ptr], 8
    mov rax, TOK_DEDENT
    ret
.reof:
    mov rax, TOK_EOF
    ret
.done: ret

handle_indentation:
    xor rcx, rcx
    mov rsi, [src_p]
.hi_l:
    cmp rsi, [src_e]
    jae .hi_d
    mov al, [rsi]
    cmp al, ' '
    je .hi_s
    cmp al, 9
    je .hi_t
    jmp .hi_d
.hi_s: inc rcx
    inc rsi
    jmp .hi_l
.hi_t: add rcx, 4
    inc rsi
    jmp .hi_l
.hi_d:
    mov [src_p], rsi
    mov rbx, [ind_ptr]
    mov rdx, [rbx - 8]
    cmp rcx, rdx
    je .hi_sm
    jg .hi_gt
    xor rax, rax
.hi_ded:
    sub rbx, 8
    mov rdx, [rbx - 8]
    inc rax
    cmp rcx, rdx
    je .hi_f
    jl .hi_ded
.hi_f:
    mov [ind_ptr], rbx
    mov [pen_d], rax
    dec qword [pen_d]
    mov rax, TOK_DEDENT
    ret
.hi_gt:
    mov [rbx], rcx
    add qword [ind_ptr], 8
    mov rax, TOK_INDENT
    ret
.hi_sm:
    xor rax, rax
    ret

is_alpha:
    mov al, [rsi]
    cmp al, 'a'
    jl .iau
    cmp al, 'z'
    jle .iay
.iau:
    cmp al, 'A'
    jl .ian
    cmp al, 'Z'
    jle .iay
.ian:
    cmp al, '_'
    je .iay
    xor rax, rax
    ret
.iay:
    mov rax, 1
    ret

is_digit:
    mov al, [rsi]
    cmp al, '0'
    jl .idn
    cmp al, '9'
    jle .idy
.idn:
    xor rax, rax
    ret
.idy:
    mov rax, 1
    ret

is_alnum:
    call is_alpha
    test rax, rax
    jnz .y
    call is_digit
.y: ret

rex_strcmp:
.scl:
    mov al, [rsi]
    mov bl, [rdi]
    cmp al, bl
    jne .scn
    test al, al
    jz .scy
    inc rsi
    inc rdi
    jmp .scl
.scn:
    xor rax, rax
    ret
.scy:
    mov rax, 1
    ret

rex_parse:
    mov qword [s_cnt], 0
    mov qword [st_off], 8

    mov rdi, 0xE9
    call rex_emit_byte
    mov rax, [c_ptr]
    push rax
    xor rdi, rdi
    call rex_emit_dq_low32

    mov rax, [c_ptr]
    add rax, 15
    and rax, ~15
    mov [c_ptr], rax
    mov [rt_base], rax

    lea rsi, [rt_start]
    mov rcx, rt_end - rt_start
.eml:
    push rsi
    push rcx
    lodsb
    movzx rdi, al
    call rex_emit_byte
    pop rcx
    pop rsi
    loop .eml

    pop rdi
    mov rax, [c_ptr]
    mov rsi, rax
    sub rsi, rdi
    sub rsi, 4
    mov [rdi], esi

    mov rdi, 0x55 ; push rbp
    call rex_emit_byte
    mov rdi, 0x48 \ call rex_emit_byte \ mov rdi, 0x89 \ call rex_emit_byte \ mov rdi, 0xE5 \ call rex_emit_byte

    mov rax, [rt_base]
    add rax, (rt_mem_init - rt_start)
    call emit_call_abs_to_rel

    call .adv
.pl:
    mov rax, [c_tok_t]
    cmp rax, TOK_EOF
    je .pd
    cmp rax, TOK_NEWLINE
    je .sn
    call p_stmt
    jmp .pl
.sn:
    call .adv
    jmp .pl
.pd:
    mov rdi, 0x48 \ call rex_emit_byte \ mov rdi, 0x89 \ call rex_emit_byte \ mov rdi, 0xEC \ call rex_emit_byte
    mov rdi, 0x5D \ call rex_emit_byte
    mov rdi, 60
    call rex_emit_mov_rax_imm
    xor rdi, rdi
    call rex_emit_mov_rdi_imm
    call rex_emit_syscall
    call rex_finish
    ret
.adv:
    call rex_lex_next
    mov [c_tok_t], rax
    ret

emit_call_abs_to_rel:
    mov rsi, rax
    mov rdi, 0xE8
    call rex_emit_byte
    mov rax, [c_ptr]
    add rax, 4
    sub rsi, rax
    mov rdi, rsi
    call rex_emit_dq_low32
    ret

p_stmt:
    mov rax, [c_tok_t]
    cmp rax, TOK_OUTPUT \ je p_out
    cmp rax, TOK_COLON \ je p_mut
    cmp rax, TOK_INT \ je p_decl
    cmp rax, TOK_IF \ je p_if
    cmp rax, TOK_FOR \ je p_for
    cmp rax, TOK_PROT \ je p_prot
    cmp rax, TOK_RETURN \ je p_ret
    call rex_parse.adv
    ret

p_decl:
    call rex_parse.adv
    mov rsi, [c_tok_v]
    call f_sym
    test rax, rax
    jnz .d
    mov rax, [s_cnt]
    imul rax, 64
    lea rbx, [s_tbl]
    add rbx, rax
    mov rsi, [c_tok_v]
    mov rdi, rbx
    mov rcx, 32
    rep movsb
    mov qword [rbx + 32], 0
    mov rdx, [st_off]
    mov [rbx + 40], rdx
    add qword [st_off], 8
    inc qword [s_cnt]
    mov rdi, 0x48 \ call rex_emit_byte \ mov rdi, 0x83 \ call rex_emit_byte \ mov rdi, 0xEC \ call rex_emit_byte \ mov rdi, 0x08 \ call rex_emit_byte
.d:
    call rex_parse.adv
    ret

p_mut:
    call rex_parse.adv
    mov rsi, [c_tok_v]
    call f_sym
    test rax, rax
    jz .er
    mov rbx, rax
    mov rax, [rbx + 40]
    push rax
    call rex_parse.adv
    call rex_parse.adv
    call p_exp
    pop rdx
    mov rdi, 0x48 \ call rex_emit_byte \ mov rdi, 0x89 \ call rex_emit_byte \ mov rdi, 0x45 \ call rex_emit_byte
    neg rdx
    mov rdi, rdx
    call rex_emit_byte
    ret
.er:
    call rex_parse.adv
    call rex_parse.adv
    call p_exp
    ret

p_out:
    call rex_parse.adv
    call p_exp
    mov rax, [rt_base]
    add rax, (rt_pri - rt_start)
    call .eca_p
    mov rax, [rt_base]
    add rax, (rt_prn - rt_start)
    call .eca_p
    ret
.eca_p:
    mov rsi, rax
    mov rdi, 0xE8
    call rex_emit_byte
    mov rax, [c_ptr]
    add rax, 4
    sub rsi, rax
    mov rdi, rsi
    call rex_emit_dq_low32
    ret

p_if:
    call rex_parse.adv
    call p_exp
    mov rdi, 0x48 \ call rex_emit_byte \ mov rdi, 0x85 \ call rex_emit_byte \ mov rdi, 0xC0 \ call rex_emit_byte
    mov rdi, 0x0F \ call rex_emit_byte \ mov rdi, 0x84 \ call rex_emit_byte
    mov rax, [c_ptr]
    push rax
    xor rdi, rdi
    call rex_emit_dq_low32
    call rex_parse.adv
    call rex_parse.adv
.l:
    mov rax, [c_tok_t]
    cmp rax, TOK_DEDENT \ je .d
    cmp rax, TOK_EOF    \ je .d
    call p_stmt
    jmp .l
.d:
    call rex_parse.adv
    pop rdi
    mov rax, [c_ptr]
    mov rsi, rax
    sub rsi, rdi
    sub rsi, 4
    mov [rdi], esi
    ret

p_for:
    call rex_parse.adv
    call rex_parse.adv
    mov rsi, [c_tok_v]
    call f_sym
    test rax, rax
    jz .er
    mov rbx, rax
    mov rax, [rbx + 40]
    push rax ; offset
    call rex_parse.adv ; id
    call rex_parse.adv ; in
    call p_exp
    pop rdx
    push rdx
    mov rdi, 0x48 \ call rex_emit_byte \ mov rdi, 0x89 \ call rex_emit_byte \ mov rdi, 0x45 \ call rex_emit_byte
    neg rdx \ mov rdi, rdx \ call rex_emit_byte
    call rex_parse.adv ; ..
    call p_exp
    mov rdi, 0x50 \ call rex_emit_byte ; push limit
    mov rbx, [c_ptr]
    push rbx ; head
    call rex_parse.adv
    call rex_parse.adv
.l:
    mov rax, [c_tok_t]
    cmp rax, TOK_DEDENT \ je .done
    cmp rax, TOK_EOF    \ je .done
    call p_stmt
    jmp .l
.done:
    call rex_parse.adv
    pop rbx ; Head
    pop rax ; Limit (dummy)
    pop rdx ; offset
    push rdx
    push rbx
    mov rdi, 0x48 \ call rex_emit_byte \ mov rdi, 0x8B \ call rex_emit_byte \ mov rdi, 0x45 \ call rex_emit_byte
    neg rdx \ mov rdi, rdx \ call rex_emit_byte
    mov rdi, 0x48 \ call rex_emit_byte \ mov rdi, 0x3B \ call rex_emit_byte \ mov rdi, 0x04 \ call rex_emit_byte \ mov rdi, 0x24 \ call rex_emit_byte
    mov rdi, 0x0F \ call rex_emit_byte \ mov rdi, 0x8D \ call rex_emit_byte
    mov rax, [c_ptr]
    push rax
    xor rdi, rdi
    call rex_emit_dq_low32
    pop rax \ pop rbx \ pop rdx \ push rdx \ push rbx \ push rax
    mov rdi, 0x48 \ call rex_emit_byte \ mov rdi, 0x83 \ call rex_emit_byte \ mov rdi, 0x45 \ call rex_emit_byte
    neg rdx \ mov rdi, rdx \ call rex_emit_byte \ mov rdi, 1 \ call rex_emit_byte
    mov rax, [c_ptr]
    mov rdi, 0xE9 \ call rex_emit_byte
    pop rax \ push rax \ sub rbx, rax \ sub rbx, 4 \ mov rdi, rbx \ call rex_emit_dq_low32
    pop rax \ pop rbx \ pop rdx
    mov rsi, [c_ptr]
    sub rsi, rax
    sub rsi, 4
    mov [rax], esi
    mov rdi, 0x58 \ call rex_emit_byte
    ret
.er:
    ret

p_prot:
    call rex_parse.adv
    mov rsi, [c_tok_v]
    mov rax, [s_cnt]
    imul rax, 64
    lea rbx, [s_tbl]
    add rbx, rax
    mov rsi, [c_tok_v]
    mov rdi, rbx
    mov rcx, 32
    rep movsb
    mov qword [rbx + 32], 1 ; type prot
    mov rax, [c_ptr]
    mov [rbx + 40], rax ; addr
    inc qword [s_cnt]
    mov rdi, 0xE9 \ call rex_emit_byte
    mov rax, [c_ptr]
    push rax
    xor rdi, rdi
    call rex_emit_dq_low32
    mov rbx, [st_off]
    push rbx
    mov qword [st_off], 8
    call rex_parse.adv ; id
    call rex_parse.adv ; (
    mov rdi, 0x55 \ call rex_emit_byte
    mov rdi, 0x48 \ call rex_emit_byte \ mov rdi, 0x89 \ call rex_emit_byte \ mov rdi, 0xE5 \ call rex_emit_byte
    xor r12, r12
.arg:
    mov rax, [c_tok_t]
    cmp rax, TOK_RPAREN \ je .body
    cmp rax, TOK_IDENT \ jne .next
    mov rsi, [c_tok_v]
    push r12
    call .ap
    pop r12
    call .sa
    inc r12
.next:
    call rex_parse.adv \ jmp .arg
.body:
    call rex_parse.adv \ call rex_parse.adv \ call rex_parse.adv
.l:
    mov rax, [c_tok_t]
    cmp rax, TOK_DEDENT \ je .done
    cmp rax, TOK_EOF    \ je .done
    call p_stmt \ jmp .l
.done:
    call rex_parse.adv
    mov rdi, 0x48 \ call rex_emit_byte \ mov rdi, 0x89 \ call rex_emit_byte \ mov rdi, 0xEC \ call rex_emit_byte
    mov rdi, 0x5D \ call rex_emit_byte \ mov rdi, 0xC3 \ call rex_emit_byte
    pop rax
    mov [st_off], rax
    pop rdi
    mov rax, [c_ptr]
    mov rsi, rax
    sub rsi, rdi
    sub rsi, 4
    mov [rdi], esi \ ret
.ap:
    mov rax, [s_cnt] \ imul rax, 64 \ lea rbx, [s_tbl] \ add rbx, rax
    mov rdi, rbx \ mov rcx, 32 \ rep movsb
    mov qword [rbx + 32], 0 \ mov rdx, [st_off] \ mov [rbx + 40], rdx
    add qword [st_off], 8 \ inc qword [s_cnt] \ ret
.sa:
    mov rdi, 0x48 \ call rex_emit_byte \ mov rdi, 0x83 \ call rex_emit_byte \ mov rdi, 0xEC \ call rex_emit_byte \ mov rdi, 0x08 \ call rex_emit_byte
    mov rdi, 0x48 \ call rex_emit_byte \ mov rdi, 0x89 \ call rex_emit_byte
    cmp r12, 0 \ je .r0
    cmp r12, 1 \ je .r1
    cmp r12, 2 \ je .r2
    mov rdi, 0xC1 \ jmp .r3
.r0: mov rdi, 0x7D \ jmp .r3
.r1: mov rdi, 0x75 \ jmp .r3
.r2: mov rdi, 0x55 \ jmp .r3
.r3: call rex_emit_byte \ neg rdx \ mov rdi, rdx \ call rex_emit_byte \ ret

p_ret:
    call rex_parse.adv \ call p_exp
    mov rdi, 0x48 \ call rex_emit_byte \ mov rdi, 0x89 \ call rex_emit_byte \ mov rdi, 0xEC \ call rex_emit_byte
    mov rdi, 0x5D \ call rex_emit_byte \ mov rdi, 0xC3 \ call rex_emit_byte \ ret

p_exp:
    call p_term
.l:
    mov rax, [c_tok_t]
    cmp rax, TOK_PLUS \ jne .d
    mov rdi, 0x50 \ call rex_emit_byte
    call rex_parse.adv
    call p_term
    mov rdi, 0x5B \ call rex_emit_byte
    mov rdi, 0x48 \ call rex_emit_byte \ mov rdi, 0x01 \ call rex_emit_byte \ mov rdi, 0xD8 \ call rex_emit_byte
    jmp .l
.d: ret

p_term:
    call p_fact
.l:
    mov rax, [c_tok_t]
    cmp rax, TOK_MUL \ jne .d
    mov rdi, 0x50 \ call rex_emit_byte
    call rex_parse.adv
    call p_fact
    mov rdi, 0x5B \ call rex_emit_byte
    mov rdi, 0x48 \ call rex_emit_byte \ mov rdi, 0x0F \ call rex_emit_byte \ mov rdi, 0xAF \ call rex_emit_byte \ mov rdi, 0xC3 \ call rex_emit_byte
    jmp .l
.d: ret

p_fact:
    mov rax, [c_tok_t]
    cmp rax, TOK_LIT_INT \ je .lit
    cmp rax, TOK_IDENT \ je .id
    cmp rax, TOK_UNKNOWN \ je .un
    ret
.lit:
    mov rdi, [c_tok_v] \ call rex_emit_mov_rax_imm \ call rex_parse.adv \ ret
.un:
    mov rax, [rt_base] \ add rax, (rt_un - rt_start) \ call p_out.eca_p \ call rex_parse.adv \ ret
.id:
    mov rsi, [c_tok_v] \ call f_sym
    test rax, rax \ jz .er
    mov rbx, rax \ mov rax, [rbx + 32] \ cmp rax, 1 \ je .call
    mov rax, [rbx + 40] \ mov rdi, 0x48 \ call rex_emit_byte
    mov rdi, 0x8B \ call rex_emit_byte \ mov rdi, 0x45 \ call rex_emit_byte
    neg rax \ mov rdi, rax \ call rex_emit_byte \ call rex_parse.adv \ ret
.call:
    mov rax, [rbx + 40] \ push rax \ call rex_parse.adv \ call rex_parse.adv \ xor r12, r12
.ca:
    mov rax, [c_tok_t] \ cmp rax, TOK_RPAREN \ je .ce
    push r12 \ call p_exp \ pop r12
    mov rdi, 0x48 \ call rex_emit_byte \ mov rdi, 0x89 \ call rex_emit_byte
    cmp r12, 0 \ je .c0
    cmp r12, 1 \ je .c1
    cmp r12, 2 \ je .c2
    mov rdi, 0xC1 \ jmp .c3
.c0: mov rdi, 0xC7 \ jmp .c3
.c1: mov rdi, 0xC6 \ jmp .c3
.c2: mov rdi, 0xC2 \ jmp .c3
.c3:
    call rex_emit_byte \ inc r12
    mov rax, [c_tok_t] \ cmp rax, TOK_COMMA \ jne .ca
    call rex_parse.adv \ jmp .ca
.ce:
    call rex_parse.adv \ pop rsi \ mov rdi, 0xE8 \ call rex_emit_byte
    mov rax, [c_ptr] \ add rax, 4 \ sub rsi, rax \ mov rdi, rsi \ call rex_emit_dq_low32 \ ret
.er: call rex_parse.adv \ ret

f_sym:
    mov rcx, [s_cnt] \ xor rdx, rdx
.l: test rcx, rcx \ jz .n \ mov rax, rdx \ imul rax, 64 \ lea rbx, [s_tbl] \ add rbx, rax
    push rsi \ push rbx \ push rcx \ push rdx \ mov rdi, rbx \ call rex_strcmp
    pop rdx \ pop rcx \ pop rbx \ pop rsi \ test rax, rax \ jnz .f \ inc rdx \ dec rcx \ jmp .l
.f: mov rax, rbx \ ret
.n: xor rax, rax \ ret

rex_codegen_init: lea rax, [c_buf] \ mov [c_ptr], rax \ ret
rex_emit_byte: mov rdx, [c_ptr] \ mov [rdx], dil \ inc qword [c_ptr] \ ret
rex_emit_dq_low32: mov rdx, [c_ptr] \ mov [rdx], edi \ add qword [c_ptr], 4 \ ret
rex_emit_dq: mov rdx, [c_ptr] \ mov [rdx], rdi \ add qword [c_ptr], 8 \ ret
rex_emit_mov_rax_imm: push rdi \ mov rdi, 0x48 \ call rex_emit_byte \ mov rdi, 0xB8 \ call rex_emit_byte \ pop rdi \ call rex_emit_dq \ ret
rex_emit_mov_rdi_imm: push rdi \ mov rdi, 0x48 \ call rex_emit_byte \ mov rdi, 0xBF \ call rex_emit_byte \ pop rdi \ call rex_emit_dq \ ret
rex_emit_syscall: mov rdi, 0x0F \ call rex_emit_byte \ mov rdi, 0x05 \ call rex_emit_byte \ ret
rex_finish:
    lea rax, [c_buf] \ mov rdx, [c_ptr] \ sub rdx, rax \ add rdx, 128 \ mov [p_hdr + 32], rdx \ mov [p_hdr + 40], rdx
    mov rax, SYS_OPEN \ mov rdi, o_nm \ mov rsi, 0x241 \ mov rdx, 0755o \ syscall \ mov [o_fd], rax
    mov rdi, rax \ mov rax, 1 \ mov rsi, e_hdr \ mov rdx, 64 \ syscall
    mov rdi, [o_fd] \ mov rax, 1 \ mov rsi, p_hdr \ mov rdx, 56 \ syscall
    mov rdi, [o_fd] \ mov rax, 1 \ push qword 0 \ mov rsi, rsp \ mov rdx, 8 \ syscall \ pop rax
    mov rdi, [o_fd] \ mov rax, 1 \ lea rsi, [c_buf] \ mov rdx, [c_ptr] \ sub rdx, rsi \ syscall
    mov rax, SYS_CLOSE \ mov rdi, [o_fd] \ syscall \ ret

rt_start:
rt_mem_init: mov rax, 9 \ xor rdi, rdi \ mov rsi, 0x1000000 \ mov rdx, 3 \ mov r10, 34 \ mov r8, -1 \ mov r9, 0 \ syscall \ ret
rt_pri:
    push rbp \ mov rbp, rsp \ sub rsp, 64 \ push rbx \ mov rbx, 10 \ lea rdi, [rbp - 1] \ mov byte [rdi], 0 \ test rax, rax \ jnz .l
    dec rdi \ mov byte [rdi], '0' \ jmp .p
.l: xor rdx, rdx \ div rbx \ add dl, '0' \ dec rdi \ mov [rdi], dl \ test rax, rax \ jnz .l
.p: mov rsi, rdi \ lea rdx, [rbp - 1] \ sub rdx, rsi \ mov rax, SYS_WRITE \ mov rdi, 1 \ syscall \ pop rbx \ mov rsp, rbp \ pop rbp \ ret
rt_prn:
    push rax \ push rdi \ push rsi \ push rdx \ mov rax, SYS_WRITE \ mov rdi, 1 \ push qword 10 \ mov rsi, rsp \ mov rdx, 1 \ syscall
    pop rax \ pop rdx \ pop rsi \ pop rdi \ pop rax \ ret
rt_un: rdtsc \ and rax, 1 \ ret
rt_end:
