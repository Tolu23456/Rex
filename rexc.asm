; #############################################################################
; # Rex Compiler - Final Verified Version
; #############################################################################

%include "common.inc"
%include "tokens.inc"

section .bss
    file_fd   resq 1
    file_buf  resb 1048576
    file_len  resq 1
    c_tok_t   resq 1
    c_tok_v   resq 1
    tok_v_str resb 4096
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
    o_fd      resq 1
    rt_base   resq 1
    patch_stack resq 128
    patch_depth resq 1
    c_buf     resb 1048576
    c_ptr     resq 1

section .data
    align 8
    e_hdr:
        db 0x7F, 'E', 'L', 'F', 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0
        dw 2                ; e_type
        dw 62               ; e_machine
        dd 1                ; e_version
        dq 0x400080         ; e_entry
        dq 64               ; e_phoff
        dq 0                ; e_shoff
        dd 0                ; e_flags
        dw 64               ; e_ehsize
        dw 56               ; e_phentsize
        dw 1                ; e_phnum
        dw 0, 0, 0
    p_hdr:
        dd 1                ; p_type
        dd 7                ; p_flags
        dq 0                ; p_offset
        dq 0x400000         ; p_vaddr
        dq 0x400000         ; p_paddr
        dq 0x100000         ; p_filesz
        dq 0x100000         ; p_memsz
        dq 0x1000           ; p_align

    usage_msg db "Usage: rexc <file.rex>", 10
    usage_len equ $ - usage_msg
    o_nm db "output", 0

    kw_s_out db "output", 0
    kw_s_int db "int", 0
    kw_s_if  db "if", 0
    kw_s_for db "for", 0
    kw_s_in  db "in", 0

    kw_tbl:
        dq kw_s_out, TOK_OUTPUT
        dq kw_s_int, TOK_INT
        dq kw_s_if, TOK_IF
        dq kw_s_for, TOK_FOR
        dq kw_s_in, TOK_IN
        dq 0, 0

section .text
    global _start
_start:
    pop rax
    cmp rax, 2
    jl .usage
    pop rax
    pop rdi
    mov rax, 2
    xor rsi, rsi
    syscall
    test rax, rax
    js .err
    mov [file_fd], rax
    mov rdi, rax
    xor rax, rax
    mov rsi, file_buf
    mov rdx, 1048576
    syscall
    mov [file_len], rax
    mov [src_p], rsi
    add rax, rsi
    mov [src_e], rax
    call rex_lex_init
    lea rax, [c_buf]
    mov [c_ptr], rax
    mov qword [patch_depth], 0
    call rex_parse
    mov rax, 60
    xor rdi, rdi
    syscall
.usage:
    mov rax, 1
    mov rdi, 1
    mov rsi, usage_msg
    mov rdx, usage_len
    syscall
.err:
    mov rax, 60
    mov rdi, 1
    syscall

rex_lex_init:
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
    jz .body
    dec qword [pen_d]
    sub qword [ind_ptr], 8
    mov rax, TOK_DEDENT
    ret
.body:
    mov rsi, [src_p]
.ws_loop:
    cmp rsi, [src_e]
    jae .return_eof
    cmp byte [at_ls], 0
    jz .char_check
    xor rcx, rcx
.indent_loop:
    cmp rsi, [src_e]
    jae .indent_done
    mov al, [rsi]
    cmp al, ' '
    je .is_space
    cmp al, 9
    je .is_tab
    jmp .indent_done
.is_space:
    inc rcx
    inc rsi
    jmp .indent_loop
.is_tab:
    add rcx, 4
    inc rsi
    jmp .indent_loop
.indent_done:
    mov [src_p], rsi
    mov rbx, [ind_ptr]
    mov rdx, [rbx-8]
    cmp rcx, rdx
    je .char_check
    jg .is_indent
    xor rax, rax
.dedent_scan:
    sub rbx, 8
    mov rdx, [rbx-8]
    inc rax
    cmp rcx, rdx
    je .dedent_found
    jl .dedent_scan
.dedent_found:
    mov [ind_ptr], rbx
    add qword [ind_ptr], 8
    mov [pen_d], rax
    dec qword [pen_d]
    mov rax, TOK_DEDENT
    ret
.is_indent:
    mov [rbx], rcx
    add qword [ind_ptr], 8
    mov rax, TOK_INDENT
    ret
.char_check:
    cmp rsi, [src_e]
    jae .return_eof
    mov al, [rsi]
    cmp al, ' '
    je .skip_char
    cmp al, 9
    je .skip_char
    cmp al, 10
    je .handle_newline
    cmp al, 13
    je .skip_char
    cmp al, '#'
    je .handle_comment
    mov byte [at_ls], 0
    cmp al, '"'
    je .handle_string
    cmp al, "'"
    je .handle_string
    cmp al, ':'
    je .handle_colon
    cmp al, '='
    je .handle_assign
    cmp al, '.'
    je .handle_dot
    call rex_is_alpha
    test rax, rax
    jnz .handle_ident
    call rex_is_digit
    test rax, rax
    jnz .handle_int
    inc rsi
    mov [src_p], rsi
    jmp .body
.skip_char:
    inc rsi
    mov [src_p], rsi
    jmp .ws_loop
.handle_newline:
    inc rsi
    mov [src_p], rsi
    inc qword [ln_num]
    mov byte [at_ls], 1
    mov rax, TOK_NEWLINE
    ret
.handle_comment:
    inc rsi
.comment_loop:
    cmp rsi, [src_e]
    jae .return_eof
    cmp byte [rsi], 10
    je .handle_newline
    inc rsi
    jmp .comment_loop
.handle_colon:
    inc rsi
    mov [src_p], rsi
    mov rax, TOK_COLON
    ret
.handle_assign:
    inc rsi
    mov [src_p], rsi
    mov rax, TOK_ASSIGN
    ret
.handle_dot:
    inc rsi
    cmp byte [rsi], '.'
    je .handle_dotdot
    mov [src_p], rsi
    mov rax, TOK_DOT
    ret
.handle_dotdot:
    inc rsi
    mov [src_p], rsi
    mov rax, TOK_DOTDOT
    ret
.handle_string:
    mov dl, [rsi]
    inc rsi
    xor rcx, rcx
.str_loop:
    cmp rsi, [src_e]
    jae .str_done
    mov al, [rsi]
    cmp al, dl
    je .str_quote
    mov [tok_v_str+rcx], al
    inc rcx
    inc rsi
    jmp .str_loop
.str_quote:
    inc rsi
.str_done:
    mov [src_p], rsi
    mov byte [tok_v_str+rcx], 0
    mov [c_tok_v], rcx
    mov rax, TOK_LIT_STR
    ret
.handle_ident:
    xor rcx, rcx
.ident_loop:
    mov al, [rsi]
    call rex_is_alnum
    test rax, rax
    jz .ident_done
    mov [tok_v_str+rcx], al
    inc rcx
    inc rsi
    jmp .ident_loop
.ident_done:
    mov [src_p], rsi
    mov byte [tok_v_str+rcx], 0
    mov rsi, kw_tbl
.kw_loop:
    mov rdi, [rsi]
    test rdi, rdi
    jz .ident_is_not_kw
    push rsi
    lea rsi, [tok_v_str]
    call rex_strcmp
    pop rsi
    test rax, rax
    jnz .ident_is_kw
    add rsi, 16
    jmp .kw_loop
.ident_is_kw:
    mov rax, [rsi+8]
    ret
.ident_is_not_kw:
    mov rax, TOK_IDENT
    lea rdx, [tok_v_str]
    mov [c_tok_v], rdx
    ret
.handle_int:
    xor rbx, rbx
.int_loop:
    mov al, [rsi]
    call rex_is_digit
    test rax, rax
    jz .int_done
    sub al, '0'
    movzx rax, al
    imul rbx, 10
    add rbx, rax
    inc rsi
    jmp .int_loop
.int_done:
    mov [src_p], rsi
    mov rax, TOK_LIT_INT
    mov [c_tok_v], rbx
    ret
.return_eof:
    mov rax, TOK_EOF
    ret

rex_get_va:
    mov rax, [c_ptr]
    lea rbx, [c_buf]
    sub rax, rbx
    add rax, 0x400080
    ret

rex_parse:
    mov qword [s_cnt], 0
    mov qword [st_off], 8
    mov rdi, 0xE9
    call rex_eb
    mov rax, [c_ptr]
    push rax
    xor rdi, rdi
    call rex_edq32
    call rex_get_va
    add rax, 15
    and rax, ~15
    mov rdx, rax
    lea rbx, [c_buf]
    sub rax, 0x400080
    add rax, rbx
    mov [c_ptr], rax
    mov [rt_base], rdx
    lea rsi, [rt_start]
    mov rcx, rt_end-rt_start
.emit_rt_loop:
    lodsb
    movzx rdi, al
    push rsi
    push rcx
    call rex_eb
    pop rcx
    pop rsi
    loop .emit_rt_loop
    pop rdi
    call rex_get_va
    mov rsi, rax
    call rex_patch_at_ptr
    mov rdi, 0x55
    call rex_eb
    mov rdi, 0x48
    call rex_eb
    mov rdi, 0x89
    call rex_eb
    mov rdi, 0xE5
    call rex_eb
    call rex_adv
.parse_loop:
    mov rax, [c_tok_t]
    cmp rax, TOK_EOF
    je .parse_done
    cmp rax, TOK_NEWLINE
    je .skip_token
    cmp rax, TOK_INDENT
    je .skip_token
    cmp rax, TOK_DEDENT
    je .skip_token
    call rex_p_stmt
    jmp .parse_loop
.skip_token:
    call rex_adv
    jmp .parse_loop
.parse_done:
    mov rdi, 60
    call rex_emrax
    xor rdi, rdi
    call rex_emrdi
    mov rdi, 0x0F
    call rex_eb
    mov rdi, 0x05
    call rex_eb
    call rex_finish
    ret

rex_p_stmt:
    mov rax, [c_tok_t]
    cmp rax, TOK_OUTPUT
    je .stmt_out
    cmp rax, TOK_INT
    je .stmt_decl
    cmp rax, TOK_COLON
    je .stmt_mut
    cmp rax, TOK_IF
    je .stmt_if
    cmp rax, TOK_FOR
    je .stmt_for
    jmp rex_adv
.stmt_out:
    call rex_p_out
    ret
.stmt_decl:
    call rex_p_decl
    ret
.stmt_mut:
    call rex_p_mut
    ret
.stmt_if:
    call rex_p_if
    ret
.stmt_for:
    call rex_p_for
    ret

rex_p_decl:
    call rex_adv
    sub rsp, 64
    mov rsi, [c_tok_v]
    mov rdi, rsp
    call rex_strcpy
    call rex_adv
    mov rsi, rsp
    call f_sym
    test rax, rax
    jnz .decl_done
    mov rax, [s_cnt]
    imul rax, 64
    lea rbx, [s_tbl]
    add rbx, rax
    mov rsi, rsp
    mov rdi, rbx
    mov rcx, 32
    rep movsb
    mov qword [rbx+40], 0
    mov rdx, [st_off]
    mov [rbx+40], rdx
    add qword [st_off], 8
    inc qword [s_cnt]
    mov rdi, 0x48
    call rex_eb
    mov rdi, 0x83
    call rex_eb
    mov rdi, 0xEC
    call rex_eb
    mov rdi, 0x08
    call rex_eb
.decl_done:
    add rsp, 64
    ret

rex_p_mut:
    call rex_adv
    sub rsp, 64
    mov rsi, [c_tok_v]
    mov rdi, rsp
    call rex_strcpy
    call rex_adv
    call rex_adv
    call rex_p_exp
    mov rsi, rsp
    call f_sym
    test rax, rax
    jz .mut_done
    mov rbx, rax
    mov rdx, [rbx+40]
    mov rdi, 0x48
    call rex_eb
    mov rdi, 0x89
    call rex_eb
    mov rdi, 0x45
    call rex_eb
    neg rdx
    mov rdi, rdx
    call rex_eb
.mut_done:
    add rsp, 64
    ret

rex_p_out:
    call rex_adv
    call rex_p_exp
    mov rdi, (rt_pri - rt_start)
    call rex_eca_va
    ret

rex_p_exp:
    mov rax, [c_tok_t]
    cmp rax, TOK_LIT_INT
    je .exp_li
    cmp rax, TOK_IDENT
    je .exp_id
    ret
.exp_li:
    mov rdi, [c_tok_v]
    call rex_emrax
    call rex_adv
    ret
.exp_id:
    mov rsi, [c_tok_v]
    call f_sym
    test rax, rax
    jz .exp_id_err
    mov rbx, rax
    mov rdx, [rbx+40]
    mov rdi, 0x48
    call rex_eb
    mov rdi, 0x8B
    call rex_eb
    mov rdi, 0x45
    call rex_eb
    neg rdx
    mov rdi, rdx
    call rex_eb
.exp_id_err:
    call rex_adv
    ret

rex_p_if:
    call rex_adv
    call rex_p_exp
    mov rdi, 0x48
    call rex_eb
    mov rdi, 0x85
    call rex_eb
    mov rdi, 0xC0
    call rex_eb
    mov rdi, 0x0F
    call rex_eb
    mov rdi, 0x84
    call rex_eb
    mov rax, [c_ptr]
    call rex_patch_push
    xor rdi, rdi
    call rex_edq32
    call rex_adv
    call rex_adv
.if_body_loop:
    mov rax, [c_tok_t]
    cmp rax, TOK_DEDENT
    je .if_body_done
    cmp rax, TOK_EOF
    je .if_body_done
    cmp rax, TOK_NEWLINE
    je .if_body_skip
    call rex_p_stmt
    jmp .if_body_loop
.if_body_skip:
    call rex_adv
    jmp .if_body_loop
.if_body_done:
    call rex_adv
    call rex_patch_pop_and_patch
    ret

rex_p_for:
    call rex_adv
    sub rsp, 64
    mov rsi, [c_tok_v]
    mov rdi, rsp
    call rex_strcpy
    call rex_adv
    call rex_adv
    call rex_p_exp
    mov rsi, rsp
    call f_sym
    test rax, rax
    jz .for_err
    mov rbx, rax
    mov rdx, [rbx+40]
    push rdx
    mov rdi, 0x48
    call rex_eb
    mov rdi, 0x89
    call rex_eb
    mov rdi, 0x45
    call rex_eb
    neg rdx
    mov rdi, rdx
    call rex_eb
    call rex_adv
    call rex_p_exp
    mov rdi, 0x50
    call rex_eb
    call rex_get_va
    push rax
    call rex_adv
    call rex_adv
.for_body_loop:
    mov rax, [c_tok_t]
    cmp rax, TOK_DEDENT
    je .for_body_done
    cmp rax, TOK_EOF
    je .for_body_done
    cmp rax, TOK_NEWLINE
    je .for_body_skip
    call rex_p_stmt
    jmp .for_body_loop
.for_body_skip:
    call rex_adv
    jmp .for_body_loop
.for_body_done:
    call rex_adv
    pop rbx
    pop rdx
    mov rdi, 0x48
    call rex_eb
    mov rdi, 0x83
    call rex_eb
    mov rdi, 0x45
    call rex_eb
    neg rdx
    mov rdi, rdx
    call rex_eb
    mov rdi, 1
    call rex_eb
    mov rdi, 0x48
    call rex_eb
    mov rdi, 0x8B
    call rex_eb
    mov rdi, 0x45
    call rex_eb
    neg rdx
    mov rdi, rdx
    call rex_eb
    mov rdi, 0x48
    call rex_eb
    mov rdi, 0x3B
    call rex_eb
    mov rdi, 0x04
    call rex_eb
    mov rdi, 0x24
    call rex_eb
    mov rdi, 0x0F
    call rex_eb
    mov rdi, 0x8E
    call rex_eb
    call rex_get_va
    add rax, 4
    mov rcx, rbx
    sub rcx, rax
    mov rdi, rcx
    call rex_edq32
    mov rdi, 0x58
    call rex_eb
.for_err:
    add rsp, 64
    ret

rex_eb:
    mov rdx, [c_ptr]
    mov [rdx], dil
    inc qword [c_ptr]
    ret
rex_edq32:
    mov rdx, [c_ptr]
    mov [rdx], edi
    add qword [c_ptr], 4
    ret
rex_edq:
    mov rdx, [c_ptr]
    mov [rdx], rdi
    add qword [c_ptr], 8
    ret
rex_emrax:
    push rdi
    mov rdi, 0x48
    call rex_eb
    mov rdi, 0xB8
    call rex_eb
    pop rdi
    call rex_edq
    ret
rex_emrdi:
    push rdi
    mov rdi, 0x48
    call rex_eb
    mov rdi, 0xBF
    call rex_eb
    pop rdi
    call rex_edq
    ret
rex_eca_va:
    push rdi
    mov rdi, 0xE8
    call rex_eb
    call rex_get_va
    add rax, 4
    mov rdx, [rt_base]
    pop rdi
    add rdx, rdi
    sub rdx, rax
    mov rdi, rdx
    call rex_edq32
    ret
rex_patch_at_ptr:
    push rax
    push rbx
    push rdx
    mov rax, rdi
    lea rbx, [c_buf]
    sub rax, rbx
    add rax, 0x400080
    add rax, 4
    mov rbx, rsi
    sub rbx, rax
    mov [rdi], ebx
    pop rdx
    pop rbx
    pop rax
    ret
rex_patch_push:
    mov rbx, [patch_depth]
    lea rcx, [patch_stack]
    mov [rcx+rbx*8], rax
    inc qword [patch_depth]
    ret
rex_patch_pop_and_patch:
    dec qword [patch_depth]
    mov rbx, [patch_depth]
    lea rcx, [patch_stack]
    mov rdi, [rcx+rbx*8]
    call rex_get_va
    mov rsi, rax
    call rex_patch_at_ptr
    ret
rex_adv:
    call rex_lex_next
    mov [c_tok_t], rax
    ret
rex_is_alpha:
    mov al, [rsi]
    cmp al, 'a'
    jl .is_ia_u
    cmp al, 'z'
    jle .is_ia_y
.is_ia_u:
    cmp al, 'A'
    jl .is_ia_n
    cmp al, 'Z'
    jle .is_ia_y
.is_ia_n:
    cmp al, '_'
    je .is_ia_y
    xor rax, rax
    ret
.is_ia_y:
    mov rax, 1
    ret
rex_is_digit:
    mov al, [rsi]
    cmp al, '0'
    jl .is_id_n
    cmp al, '9'
    jle .is_id_y
.is_id_n:
    xor rax, rax
    ret
.is_id_y:
    mov rax, 1
    ret
rex_is_alnum:
    call rex_is_alpha
    test rax, rax
    jnz .is_aln_y
    call rex_is_digit
.is_aln_y:
    ret
rex_strcmp:
.strcmp_loop:
    mov al, [rsi]
    mov bl, [rdi]
    cmp al, bl
    jne .strcmp_ne
    test al, al
    jz .strcmp_eq
    inc rsi
    inc rdi
    jmp .strcmp_loop
.strcmp_ne:
    xor rax, rax
    ret
.strcmp_eq:
    mov rax, 1
    ret
rex_strcpy:
.strcpy_loop:
    lodsb
    stosb
    test al, al
    jnz .strcpy_loop
    ret
f_sym:
    mov rcx, [s_cnt]
    xor rdx, rdx
.fsym_loop:
    test rcx, rcx
    jz .fsym_none
    mov rax, rdx
    imul rax, 64
    lea rbx, [s_tbl]
    add rbx, rax
    push rsi
    push rbx
    push rcx
    push rdx
    mov rdi, rbx
    call rex_strcmp
    pop rdx
    pop rcx
    pop rbx
    pop rsi
    test rax, rax
    jnz .fsym_found
    inc rdx
    dec rcx
    jmp .fsym_loop
.fsym_found:
    mov rax, rbx
    ret
.fsym_none:
    xor rax, rax
    ret

rex_finish:
    lea rax, [c_buf]
    mov rdx, [c_ptr]
    sub rdx, rax
    add rdx, 128
    mov [p_hdr+32], rdx
    mov [p_hdr+40], rdx
    mov rax, 2
    mov rdi, o_nm
    mov rsi, 577
    mov rdx, 0755o
    syscall
    mov [o_fd], rax
    mov rdi, rax
    mov rax, 1
    mov rsi, e_hdr
    mov rdx, 64
    syscall
    mov rdi, [o_fd]
    mov rax, 1
    mov rsi, p_hdr
    mov rdx, 56
    syscall
    mov rdi, [o_fd]
    mov rax, 1
    xor rbx, rbx
    push rbx
    mov rsi, rsp
    mov rdx, 8
    syscall
    pop rbx
    mov rdi, [o_fd]
    mov rax, 1
    lea rsi, [c_buf]
    mov rdx, [c_ptr]
    lea rbx, [c_buf]
    sub rdx, rbx
    syscall
    mov rax, 3
    mov rdi, [o_fd]
    syscall
    ret

rt_start:
rt_pri:
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 64
    mov rbx, 10
    lea rcx, [rbp-1]
    mov byte [rcx], 10
    test rax, rax
    jnz .rtpri_nz
    dec rcx
    mov byte [rcx], '0'
    jmp .rtpri_pr
.rtpri_nz:
    xor rdx, rdx
    div rbx
    add dl, '0'
    dec rcx
    mov [rcx], dl
    test rax, rax
    jnz .rtpri_nz
.rtpri_pr:
    mov rsi, rcx
    mov rdx, rbp
    sub rdx, rcx
    mov rax, 1
    mov rdi, 1
    syscall
    add rsp, 64
    pop rbx
    pop rbp
    ret
rt_end:
