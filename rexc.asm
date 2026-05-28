; -----------------------------------------------------------------------------
; Rex V5.0 - Unified High-Stability Compiler
; Consolidated Source for pure x86_64 Direct ELF Generation
; -----------------------------------------------------------------------------

default rel

; --- CONSTANTS ---
TOK_EOF       equ 0
TOK_NEWLINE   equ 1
TOK_IDENT     equ 4
TOK_INT_LIT   equ 5
TOK_TYPE_INT  equ 6
TOK_ASSIGN    equ 7
TOK_OUTPUT    equ 9
TOK_TYPE_FLOAT equ 22
TOK_FLOAT_LIT  equ 23
TOK_PLUS      equ 32
TOK_MINUS     equ 33
TOK_STAR      equ 34
TOK_SLASH     equ 35
TOK_LPAREN    equ 36
TOK_RPAREN    equ 37
TOK_LBRACE    equ 38
TOK_RBRACE    equ 39
TOK_COLON     equ 40
TOK_COMMA     equ 41
TOK_TYPE_DICT equ 42
TOK_LBRACK    equ 43
TOK_RBRACK    equ 44

TYPE_INT      equ 1
TYPE_FLOAT    equ 2
TYPE_DICT     equ 7

VAR_MAX        equ 128
VAR_STORAGE_BASE equ 0x440000
LOAD_BASE      equ 0x400000
HEADERS_SIZE   equ 120

RT_TOTAL_SIZE  equ 8448
RT_PRI_OFFSET  equ 125
RT_PRF_OFFSET  equ 1405
RT_PRQ_OFFSET  equ 7549
RT_DICT_NEW    equ 7550
RT_DICT_SET    equ 7577
RT_DICT_GET    equ 7626

section .data
    elf_hdr:
        db 0x7F, 'E', 'L', 'F', 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0
        dw 2, 0x3E
        dd 1
        dq LOAD_BASE + HEADERS_SIZE
        dq 64, 0
        dd 0
        dw 64, 56, 1, 0, 0, 0
    prog_hdr:
        dd 1, 7
        dq 0, LOAD_BASE, LOAD_BASE
        dq 0x80000, 0x80000, 0x1000

    out_name_str: db "output", 0
    rt_blob: incbin "runtime.bin"

section .bss
    src_buf: resb 65536
    src_len: resq 1
    out_buf: resb 131072
    out_idx: resq 1
    lex_pos: resq 1
    tok_typ: resb 1
    tok_iv:  resq 1
    tok_id:  resb 64
    var_tab: resb 64 * 128
    var_cnt: resq 1
    sav_nam: resb 64
    cur_typ: resb 1

section .text
global _start

_start:
    mov rax, [rsp]
    cmp rax, 2
    jl .exit
    mov rdi, [rsp+16]
    mov rax, 2
    xor rsi, rsi
    syscall
    test rax, rax
    js .exit
    mov rdi, rax
    mov rax, 0
    lea rsi, [src_buf]
    mov rdx, 65536
    syscall
    mov [src_len], rax
    mov rax, 3
    syscall
    
    call codegen_headers
    call codegen_init
    mov qword [lex_pos], 0
    call lexer_next
    
.parse_loop:
    movzx eax, byte [tok_typ]
    cmp al, TOK_EOF
    je .done
    cmp al, TOK_NEWLINE
    je .skip
    call parse_stmt
    jmp .parse_loop
.skip:
    call lexer_next
    jmp .parse_loop
.done:
    call codegen_finish
    mov rax, 87
    lea rdi, [out_name_str]
    syscall
    mov rax, 2
    lea rdi, [out_name_str]
    mov rsi, 0x41
    mov rdx, 493
    syscall
    mov rdi, rax
    mov rax, 1
    lea rsi, [out_buf]
    mov rdx, [out_idx]
    syscall
.exit:
    mov rax, 60
    xor rdi, rdi
    syscall

; --- LEXER ---
lexer_next:
.r:
    lea rdi, [src_buf]
    mov rcx, [lex_pos]
.sl:
    cmp rcx, [src_len]
    jge .ee
    movzx eax, byte [rdi+rcx]
    cmp al, ' '
    je .sn
    cmp al, 10
    je .enl
    jmp .st
.sn:
    inc rcx
    jmp .sl
.enl:
    inc rcx
    mov [lex_pos], rcx
    jmp .r
.st:
    mov [lex_pos], rcx
    movzx eax, byte [rdi+rcx]
    cmp al, '0'
    jl .csp
    cmp al, '9'
    jle .pin
    cmp al, 'a'
    jl .pid
    cmp al, 'z'
    jle .pid
.csp:
    inc qword [lex_pos]
    cmp al, '='
    je .eas
    cmp al, '+'
    je .epl
    cmp al, '-'
    je .emi
    cmp al, '*'
    je .emu
    cmp al, '/'
    je .edi
    cmp al, '('
    je .elp
    cmp al, ')'
    je .erp
    cmp al, '{'
    je .elb
    cmp al, '}'
    je .erb
    cmp al, ':'
    je .eco
    cmp al, ','
    je .ecm
    cmp al, '['
    je .elbk
    cmp al, ']'
    je .erbk
    jmp .r
.eas: mov byte [tok_typ], TOK_ASSIGN
    ret
.epl: mov byte [tok_typ], TOK_PLUS
    ret
.emi: mov byte [tok_typ], TOK_MINUS
    ret
.emu: mov byte [tok_typ], TOK_STAR
    ret
.edi: mov byte [tok_typ], TOK_SLASH
    ret
.elp: mov byte [tok_typ], TOK_LPAREN
    ret
.erp: mov byte [tok_typ], TOK_RPAREN
    ret
.elb: mov byte [tok_typ], TOK_LBRACE
    ret
.erb: mov byte [tok_typ], TOK_RBRACE
    ret
.eco: mov byte [tok_typ], TOK_COLON
    ret
.ecm: mov byte [tok_typ], TOK_COMMA
    ret
.elbk: mov byte [tok_typ], TOK_LBRACK
    ret
.erbk: mov byte [tok_typ], TOK_RBRACK
    ret
.pid:
    xor rbx, rbx
    lea rsi, [tok_id]
.idl:
    movzx eax, byte [rdi+rcx]
    mov [rsi+rbx], al
    inc rbx
    inc rcx
    cmp rcx, [src_len]
    jge .idd
    movzx eax, byte [rdi+rcx]
    cmp al, 'a'
    jl .idd
    cmp al, 'z'
    jle .idl
.idd:
    mov byte [rsi+rbx], 0
    mov [lex_pos], rcx
    call lexer_classify
    ret
.pin:
    xor rbx, rbx
.inl:
    cmp rcx, [src_len]
    jge .ind
    movzx eax, byte [rdi+rcx]
    cmp al, '.'
    je .cfl
    cmp al, '0'
    jl .ind
    cmp al, '9'
    jg .ind
    sub al, '0'
    imul rbx, rbx, 10
    movzx rax, al
    add rbx, rax
    inc rcx
    jmp .inl
.cfl:
    inc rcx
    cvtsi2sd xmm0, rbx
    movsd xmm1, [rel .ten]
    movsd xmm2, xmm1
.fll:
    cmp rcx, [src_len]
    jge .fld
    movzx eax, byte [rdi+rcx]
    cmp al, '0'
    jl .fld
    cmp al, '9'
    jg .fld
    sub al, '0'
    cvtsi2sd xmm3, rax
    divsd xmm3, xmm1
    addsd xmm0, xmm3
    mulsd xmm1, xmm2
    inc rcx
    jmp .fll
.fld:
    mov [lex_pos], rcx
    movq [tok_iv], xmm0
    mov byte [tok_typ], TOK_FLOAT_LIT
    ret
.ind:
    mov [lex_pos], rcx
    mov [tok_iv], rbx
    mov byte [tok_typ], TOK_INT_LIT
    ret
.ee:
    mov byte [tok_typ], TOK_EOF
    ret
.ten: dq 10.0

lexer_classify:
    lea rsi, [tok_id]
    mov eax, [rsi]
    cmp eax, 0x00746e69
    je .ki
    cmp eax, 0x616f6c66
    je .kf
    cmp eax, 0x74636964
    je .kd
    cmp eax, 0x7074756F
    je .ko
    mov byte [tok_typ], TOK_IDENT
    ret
.ki: mov byte [tok_typ], TOK_TYPE_INT
    ret
.kf: mov byte [tok_typ], TOK_TYPE_FLOAT
    ret
.kd: mov byte [tok_typ], TOK_TYPE_DICT
    ret
.ko: mov byte [tok_typ], TOK_OUTPUT
    ret

; --- PARSER ---
parse_stmt:
    movzx eax, byte [tok_typ]
    cmp al, TOK_TYPE_INT
    je .pi
    cmp al, TOK_TYPE_FLOAT
    je .pf
    cmp al, TOK_TYPE_DICT
    je .pd
    cmp al, TOK_OUTPUT
    je .ou
    call lexer_next
    ret
.pi:
    call lexer_next
    lea rsi, [tok_id]
    lea rdi, [sav_nam]
    call strcpy
    call lexer_next
    call lexer_next
    call parse_expr
    lea rdi, [sav_nam]
    mov cl, TYPE_INT
    call var_add
    mov rdi, rax
    call emit_assign_rax
    ret
.pf:
    call lexer_next
    lea rsi, [tok_id]
    lea rdi, [sav_nam]
    call strcpy
    call lexer_next
    call lexer_next
    call parse_expr
    lea rdi, [sav_nam]
    mov cl, TYPE_FLOAT
    call var_add
    mov rdi, rax
    call emit_assign_rax
    ret
.pd:
    call lexer_next
    lea rsi, [tok_id]
    lea rdi, [sav_nam]
    call strcpy
    call lexer_next
    call lexer_next
    call parse_dict
    lea rdi, [sav_nam]
    mov cl, TYPE_DICT
    call var_add
    mov rdi, rax
    call emit_assign_rax
    ret
.ou:
    call lexer_next
    call parse_expr
    movzx eax, byte [cur_typ]
    cmp al, TYPE_FLOAT
    je .of
    call emit_output_rax_int
    ret
.of:
    call emit_output_rax_float
    ret

parse_dict:
    mov al, 0xE8
    call emit_b
    mov rax, LOAD_BASE + RT_DICT_NEW
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d
    call lexer_next
.l:
    movzx eax, byte [tok_typ]
    cmp al, TOK_RBRACE
    je .done
    mov al, 0x50
    call emit_b
    call parse_expr
    mov al, 0x50
    call emit_b
    call lexer_next
    call parse_expr
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC2
    call emit_b
    mov al, 0x5E
    call emit_b
    mov al, 0x5F
    call emit_b
    mov al, 0xE8
    call emit_b
    mov rax, LOAD_BASE + RT_DICT_SET
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d
    mov al, 0x50
    call emit_b
    movzx eax, byte [tok_typ]
    cmp al, TOK_COMMA
    jne .l
    call lexer_next
    jmp .l
.done:
    call lexer_next
    mov al, 0x58
    call emit_b
    mov byte [cur_typ], TYPE_DICT
    ret

parse_expr:
    call parse_term
.l:
    movzx eax, byte [tok_typ]
    cmp al, TOK_PLUS
    je .p
    cmp al, TOK_MINUS
    je .m
    ret
.p:
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
    mov al, 0x48
    call emit_b
    mov al, 0x01
    call emit_b
    mov al, 0xD8
    call emit_b
    jmp .l
.m:
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
    mov al, 0x48
    call emit_b
    mov al, 0x29
    call emit_b
    mov al, 0xD8
    call emit_b
    jmp .l

parse_term:
    call parse_factor
.l:
    movzx eax, byte [tok_typ]
    cmp al, TOK_STAR
    je .s
    ret
.s:
    call lexer_next
    mov al, 0x50
    call emit_b
    call parse_factor
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
    mov al, 0x0F
    call emit_b
    mov al, 0xAF
    call emit_b
    mov al, 0xC3
    call emit_b
    jmp .l

parse_factor:
    movzx eax, byte [tok_typ]
    cmp al, TOK_INT_LIT
    je .i
    cmp al, TOK_FLOAT_LIT
    je .f
    cmp al, TOK_IDENT
    je .id
    call lexer_next
    ret
.i:
    mov rax, [tok_iv]
    mov al, 0x48
    call emit_b
    mov al, 0xB8
    call emit_b
    call emit_q
    mov byte [cur_typ], TYPE_INT
    call lexer_next
    ret
.f:
    mov rax, [tok_iv]
    mov al, 0x48
    call emit_b
    mov al, 0xB8
    call emit_b
    call emit_q
    mov byte [cur_typ], TYPE_FLOAT
    call lexer_next
    ret
.id:
    lea rdi, [tok_id]
    call var_find
    mov al, 0x48
    call emit_b
    mov al, 0xA1
    call emit_b
    shl rax, 6
    add rax, VAR_STORAGE_BASE
    call emit_q
    mov byte [cur_typ], TYPE_INT
    call lexer_next
    movzx eax, byte [tok_typ]
    cmp al, TOK_LBRACK
    jne .ret
    mov al, 0x50
    call emit_b
    call lexer_next
    call parse_expr
    call lexer_next
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC6
    call emit_b
    mov al, 0x5F
    call emit_b
    mov al, 0xE8
    call emit_b
    mov rax, LOAD_BASE + RT_DICT_GET
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d
    mov byte [cur_typ], TYPE_INT
.ret:
    ret

var_add:
    mov rbx, [var_cnt]
    mov rax, rbx
    shl rax, 6
    lea rdi, [var_tab]
    add rdi, rax
    push rdi
    lea rsi, [sav_nam]
    call strcpy
    pop rdi
    mov [rdi+32], cl
    mov rax, rbx
    inc qword [var_cnt]
    ret
var_find:
    xor rbx, rbx
.l:
    cmp rbx, [var_cnt]
    jge .nf
    mov rax, rbx
    shl rax, 6
    lea rsi, [var_tab]
    add rsi, rax
    lea rdi, [tok_id]
.c:
    movzx eax, byte [rdi]
    movzx edx, byte [rsi]
    cmp al, dl
    jne .n
    test al, al
    jz .m
    inc rdi
    inc rsi
    jmp .c
.m:
    mov rax, rbx
    ret
.n:
    inc rbx
    jmp .l
.nf:
    mov rax, -1
    ret
strcpy:
.l:
    movzx eax, byte [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .l
    ret

; --- CODEGEN ---
codegen_headers:
    mov qword [out_idx], 0
    lea rdi, [out_buf]
    lea rsi, [elf_hdr]
    mov rcx, 64
    rep movsb
    lea rsi, [prog_hdr]
    mov rcx, 56
    rep movsb
    mov qword [out_idx], 120
    ret
codegen_init:
    mov al, 0xE9
    call emit_b
    mov eax, RT_TOTAL_SIZE
    call emit_d
    lea rdi, [out_buf]
    add rdi, [out_idx]
    lea rsi, [rt_blob]
    mov rcx, RT_TOTAL_SIZE
    rep movsb
    add qword [out_idx], RT_TOTAL_SIZE
    ret
emit_b:
    push rbx
    mov rbx, [out_idx]
    lea rcx, [out_buf]
    mov [rcx+rbx], al
    inc qword [out_idx]
    pop rbx
    ret
emit_d:
    push rbx
    mov rbx, [out_idx]
    lea rcx, [out_buf]
    mov [rcx+rbx], eax
    add qword [out_idx], 4
    pop rbx
    ret
emit_q:
    push rbx
    mov rbx, [out_idx]
    lea rcx, [out_buf]
    mov [rcx+rbx], rax
    add qword [out_idx], 8
    pop rbx
    ret
codegen_finish:
    mov al, 0x48
    call emit_b
    mov al, 0xC7
    call emit_b
    mov al, 0xC0
    call emit_b
    mov eax, 60
    call emit_d
    mov al, 0x48
    call emit_b
    mov al, 0x31
    call emit_b
    mov al, 0xFF
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0x05
    call emit_b
    mov rax, [out_idx]
    lea rcx, [out_buf]
    mov [rcx+96], rax
    ret
emit_assign_rax:
    mov al, 0x48
    call emit_b
    mov al, 0xA3
    call emit_b
    mov rax, rdi
    shl rax, 6
    add rax, VAR_STORAGE_BASE
    call emit_q
    ret
emit_output_rax_int:
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC7
    call emit_b
    mov al, 0xE8
    call emit_b
    mov rax, LOAD_BASE + RT_PRI_OFFSET
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d
    ret
emit_output_rax_float:
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC7
    call emit_b
    mov al, 0xE8
    call emit_b
    mov rax, LOAD_BASE + RT_PRF_OFFSET
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d
    ret
