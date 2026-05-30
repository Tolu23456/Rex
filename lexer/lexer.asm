default rel
%include "include/rex_defs.inc"
global lexer_init, lexer_next, tok_type, tok_int, tok_ident
section .bss
lex_src:       resq 1
lex_len:       resq 1
lex_pos:       resq 1
at_line_start: resb 1
indent_stack:  resq 32
indent_depth:  resq 1
pending_dedents: resq 1
tok_type:      resb 1
tok_int:       resq 1
tok_ident:     resb 64
section .text
lexer_init:
    push rbp
    mov rbp, rsp
    mov [lex_src], rdi
    mov [lex_len], rsi
    mov qword [lex_pos], 0
    mov byte [at_line_start], 1
    mov qword [indent_depth], 0
    mov qword [pending_dedents], 0
    mov qword [indent_stack], 0
    leave
    ret

lexer_next:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
.r:
    cmp qword [pending_dedents], 0
    jle .n
    dec qword [pending_dedents]
    mov byte [tok_type], TOK_DEDENT
    jmp .done
.n:
    cmp byte [at_line_start], 0
    je .s
    mov rcx, [lex_pos]
    mov rdi, [lex_src]
    xor rbx, rbx
.cs:
    cmp rcx, [lex_len]
    jge .ie
    movzx eax, byte [rdi+rcx]
    cmp al, ' '
    jne .cd
    inc rbx
    inc rcx
    jmp .cs
.cd:
    cmp rcx, [lex_len]
    jge .ie
    movzx eax, byte [rdi+rcx]
    cmp al, 0x0A
    je .bl
    mov [lex_pos], rcx
    mov byte [at_line_start], 0
    mov rax, [indent_depth]
    lea rcx, [indent_stack]
    mov rdx, [rcx+rax*8]
    cmp rbx, rdx
    jg .mi
    jl .li
    jmp .s
.mi:
    inc qword [indent_depth]
    mov rax, [indent_depth]
    lea rcx, [indent_stack]
    mov [rcx+rax*8], rbx
    mov byte [tok_type], TOK_INDENT
    jmp .done
.li:
    cmp qword [indent_depth], 0
    jle .de
    mov rax, [indent_depth]
    lea rcx, [indent_stack]
    mov rdx, [rcx+rax*8]
    cmp rdx, rbx
    jle .de
    dec qword [indent_depth]
    inc qword [pending_dedents]
    jmp .li
.de:
    dec qword [pending_dedents]
    mov byte [tok_type], TOK_DEDENT
    jmp .done
.bl:
    inc rcx
    mov [lex_pos], rcx
    jmp .r
.ie:
    mov byte [at_line_start], 0
    mov [lex_pos], rcx
    jmp .r
.s:
    mov rcx, [lex_pos]
    mov rdi, [lex_src]
.sl:
    cmp rcx, [lex_len]
    jge .ee
    movzx eax, byte [rdi+rcx]
    cmp al, ' '
    je .sn
    cmp al, 0x09
    je .sn
    jmp .sd
.sn:
    inc rcx
    jmp .sl
.sd:
    mov [lex_pos], rcx
    cmp rcx, [lex_len]
    jge .ee
    movzx eax, byte [rdi+rcx]
    cmp al, 0x0A
    je .enl
    cmp al, '"'
    je .pstr
    cmp al, '['
    je .elb
    cmp al, ']'
    je .erb
    cmp al, '{'
    je .elc
    cmp al, '}'
    je .erc
    cmp al, ','
    je .ecm
    cmp al, '('
    je .elp
    cmp al, ')'
    je .erp
    cmp al, '*'
    je .estar
    cmp al, '/'
    je .eslash
    cmp al, '%'
    je .epct
    cmp al, '<'
    je .elt
    cmp al, '>'
    je .egt
    cmp al, '!'
    je .eexcl
    cmp al, '&'
    je .eamp
    cmp al, '|'
    je .epipe
    cmp al, '^'
    je .ecaret
    cmp al, '~'
    je .etilde
    cmp al, '_'
    je .pid
    cmp al, 'a'
    jl .cup
    cmp al, 'z'
    jle .pid
.cup:
    cmp al, 'A'
    jl .cdi
    cmp al, 'Z'
    jle .pid
.cdi:
    cmp al, '0'
    jl .csp
    cmp al, '9'
    jle .pin
.csp:
    cmp al, '='
    je .eas
    cmp al, ':'
    je .eco
    cmp al, '.'
    je .cdd
    cmp al, '@'
    je .eat
    cmp al, '+'
    je .epl
    cmp al, '-'
    je .emi
    inc qword [lex_pos]
    jmp .r
.elb:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_LBRACK
    jmp .done
.erb:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_RBRACK
    jmp .done
.elc:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_LBRACE
    jmp .done
.erc:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_RBRACE
    jmp .done
.ecm:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_COMMA
    jmp .done
.elp:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_LPAREN
    jmp .done
.erp:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_RPAREN
    jmp .done
.estar:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_STAR
    jmp .done
.eslash:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_SLASH
    jmp .done
.epct:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_PERCENT
    jmp .done
.eamp:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_AMP
    jmp .done
.ecaret:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_CARET
    jmp .done
.etilde:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_TILDE
    jmp .done
.elt:
    mov rcx, [lex_pos]
    inc rcx
    cmp rcx, [lex_len]
    jge .lt1
    movzx eax, byte [rdi+rcx]
    cmp al, '='
    jne .ltlt
    inc rcx
    mov [lex_pos], rcx
    mov byte [tok_type], TOK_LTE
    jmp .done
.ltlt:
    cmp al, '<'
    jne .lt1
    inc rcx
    mov [lex_pos], rcx
    mov byte [tok_type], TOK_LSHIFT
    jmp .done
.lt1:
    mov [lex_pos], rcx
    mov byte [tok_type], TOK_LT
    jmp .done
.egt:
    mov rcx, [lex_pos]
    inc rcx
    cmp rcx, [lex_len]
    jge .gt1
    movzx eax, byte [rdi+rcx]
    cmp al, '='
    jne .gtgt
    inc rcx
    mov [lex_pos], rcx
    mov byte [tok_type], TOK_GTE
    jmp .done
.gtgt:
    cmp al, '>'
    jne .gt1
    inc rcx
    mov [lex_pos], rcx
    mov byte [tok_type], TOK_RSHIFT
    jmp .done
.gt1:
    mov [lex_pos], rcx
    mov byte [tok_type], TOK_GT
    jmp .done
.eexcl:
    mov rcx, [lex_pos]
    inc rcx
    cmp rcx, [lex_len]
    jge .eskip
    movzx eax, byte [rdi+rcx]
    cmp al, '='
    jne .eskip
    inc rcx
    mov [lex_pos], rcx
    mov byte [tok_type], TOK_NEQ
    jmp .done
.eskip:
    inc qword [lex_pos]
    jmp .r
.epipe:
    mov rcx, [lex_pos]
    inc rcx
    cmp rcx, [lex_len]
    jge .pipe1
    movzx eax, byte [rdi+rcx]
    cmp al, '|'
    jne .pipe1
    inc rcx
    mov [lex_pos], rcx
    mov byte [tok_type], TOK_OR
    jmp .done
.pipe1:
    mov [lex_pos], rcx
    mov byte [tok_type], TOK_PIPE
    jmp .done
.pstr:
    inc qword [lex_pos]
    mov rcx, [lex_pos]
    mov rdi, [lex_src]
    lea rsi, [tok_ident]
    xor rbx, rbx
.strl:
    cmp rcx, [lex_len]
    jge .strd
    movzx eax, byte [rdi+rcx]
    cmp al, '"'
    je .strq
    mov [rsi+rbx], al
    inc rbx
    inc rcx
    jmp .strl
.strq:
    inc rcx
.strd:
    mov byte [rsi+rbx], 0
    mov [lex_pos], rcx
    mov byte [tok_type], TOK_STR_LIT
    jmp .done
.epl:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_PLUS
    jmp .done
.emi:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_MINUS
    jmp .done
.eat:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_AT
    jmp .done
.ee:
    mov byte [tok_type], TOK_EOF
    jmp .done
.enl:
    inc qword [lex_pos]
    mov byte [at_line_start], 1
    mov byte [tok_type], TOK_NEWLINE
    jmp .done
.eas:
    mov rcx, [lex_pos]
    inc rcx
    cmp rcx, [lex_len]
    jge .as
    movzx eax, byte [rdi+rcx]
    cmp al, '='
    jne .as
    inc rcx
    mov [lex_pos], rcx
    mov byte [tok_type], TOK_EQEQ
    jmp .done
.as:
    mov [lex_pos], rcx
    mov byte [tok_type], TOK_ASSIGN
    jmp .done
.eco:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_COLON
    jmp .done
.cdd:
    mov rcx, [lex_pos]
    inc rcx
    cmp rcx, [lex_len]
    jge .sch
    movzx eax, byte [rdi+rcx]
    cmp al, '.'
    jne .sch
    add qword [lex_pos], 2
    mov byte [tok_type], TOK_DOTDOT
    jmp .done
.sch:
    inc qword [lex_pos]
    jmp .r
.pid:
    mov rcx, [lex_pos]
    mov rdi, [lex_src]
    lea rsi, [tok_ident]
    xor rbx, rbx
.id_l:
    cmp rbx, 63
    jge .id_d
    cmp rcx, [lex_len]
    jge .id_d
    movzx eax, byte [rdi+rcx]
    cmp al, '_'
    je .id_c
    cmp al, 'a'
    jl .id_up
    cmp al, 'z'
    jle .id_c
.id_up:
    cmp al, 'A'
    jl .id_di
    cmp al, 'Z'
    jle .id_c
.id_di:
    cmp al, '0'
    jl .id_d
    cmp al, '9'
    jle .id_c
    jmp .id_d
.id_c:
    mov [rsi+rbx], al
    inc rbx
    inc rcx
    jmp .id_l
.id_d:
    mov byte [rsi+rbx], 0
    mov [lex_pos], rcx
    call lexer_classify
    jmp .done
.pin:
    mov rcx, [lex_pos]
    mov rdi, [lex_src]
    xor rbx, rbx
.in_l:
    cmp rcx, [lex_len]
    jge .in_d
    movzx eax, byte [rdi+rcx]
    cmp al, '0'
    jl .in_f
    cmp al, '9'
    jg .in_f
    sub al, '0'
    imul rbx, rbx, 10
    movzx rax, al
    add rbx, rax
    inc rcx
    jmp .in_l
.in_f:
    cmp al, '.'
    jne .in_c
    cvtsi2sd xmm0, rbx
    inc rcx
    mov r8, 10
    cvtsi2sd xmm2, r8
    movsd xmm1, xmm2
.fl_l:
    cmp rcx, [lex_len]
    jge .fl_d
    movzx eax, byte [rdi+rcx]
    cmp al, '0'
    jl .fl_d
    cmp al, '9'
    jg .fl_d
    sub al, '0'
    cvtsi2sd xmm3, rax
    divsd xmm3, xmm1
    addsd xmm0, xmm3
    mulsd xmm1, xmm2
    inc rcx
    jmp .fl_l
.fl_d:
    mov [lex_pos], rcx
    movq [tok_int], xmm0
    mov byte [tok_type], TOK_FLOAT_LIT
    jmp .done
.in_c:
    cmp al, 'j'
    jne .in_d
    inc rcx
    mov [lex_pos], rcx
    mov [tok_int], rbx
    mov byte [tok_type], TOK_COMPLEX_LIT
    jmp .done
.in_d:
    mov [lex_pos], rcx
    mov [tok_int], rbx
    mov byte [tok_type], TOK_INT_LIT
    jmp .done
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

lexer_classify:
    mov eax, dword [tok_ident]
    cmp eax, 0x6c6f6f62
    je .kb
    cmp eax, 0x616f6c66
    jne .nf
    cmp byte [tok_ident+4], 't'
    je .kf
.nf:
    cmp eax, 0x706d6f63
    jne .ncp
    cmp dword [tok_ident+4], 0x78656c
    je .kcp
.ncp:
    cmp eax, 0x00727473
    je .ks
    cmp eax, 0x65757274
    je .kt
    cmp eax, 0x736c6166
    jne .nfa
    cmp byte [tok_ident+4], 'e'
    je .kfa
.nfa:
    cmp eax, 0x6e6b6e75
    jne .nu
    cmp dword [tok_ident+4], 0x6e776f
    je .ku
.nu:
    cmp eax, 0x00746e69
    je .ki
    cmp eax, 0x00006669
    je .kif
    cmp eax, 0x00726f66
    je .kfo
    cmp eax, 0x00006e69
    je .kin
    cmp eax, 0x6C696877
    jne .nwh
    cmp byte [tok_ident+4], 'e'
    je .kwh
.nwh:
    cmp eax, 0x00657375
    je .kuse
    cmp eax, 0x00006d6d
    je .kmm
    cmp eax, 0x00006367
    je .kgc
    cmp eax, 0x746F7270
    je .kpr
    cmp eax, 0x75746572
    jne .nr
    cmp byte [tok_ident+4], 'r'
    jne .nr
    cmp byte [tok_ident+5], 'n'
    je .kr
.nr:
    cmp eax, 0x706F7473
    je .kso
    cmp eax, 0x65736C65
    je .kel
    cmp eax, 0x66696C65
    je .kei
    cmp eax, 0x7074756F
    jne .nout
    cmp word [tok_ident+4], 0x7475
    je .kou
.nout:
    cmp eax, 0x00646e61
    je .kand
    cmp eax, 0x0000726f
    je .kor
    cmp eax, 0x00746f6e
    je .knot
    cmp eax, 0x00727265
    je .kerr
    cmp eax, 0x00716573
    je .kseq
    cmp eax, 0x68737570
    je .kpush
    cmp eax, 0x00706f70
    je .kpop
    cmp eax, 0x006e656c
    je .klen
    cmp eax, 0x70696b73
    je .kskip
    cmp eax, 0x73736170
    je .kpass
    cmp eax, 0x68636165
    je .keach
    cmp eax, 0x6e656877
    je .kwhen
    cmp eax, 0x65707974
    jne .ntype
    cmp dword [tok_ident+4], 0x666f
    je .ktof
.ntype:
    cmp eax, 0x006e6962
    je .kbin
.kid:
    mov byte [tok_type], TOK_IDENT
    ret
.ki:
    mov byte [tok_type], TOK_TYPE_INT
    ret
.kb:
    mov byte [tok_type], TOK_TYPE_BOOL
    ret
.kf:
    mov byte [tok_type], TOK_TYPE_FLOAT
    ret
.kcp:
    mov byte [tok_type], TOK_TYPE_COMPLEX
    ret
.ks:
    mov byte [tok_type], TOK_TYPE_STR
    ret
.kt:
    mov byte [tok_type], TOK_TRUE
    ret
.kfa:
    mov byte [tok_type], TOK_FALSE
    ret
.ku:
    mov byte [tok_type], TOK_UNKNOWN
    ret
.kif:
    mov byte [tok_type], TOK_IF
    ret
.kfo:
    mov byte [tok_type], TOK_FOR
    ret
.kin:
    mov byte [tok_type], TOK_IN
    ret
.kwh:
    mov byte [tok_type], TOK_WHILE
    ret
.kuse:
    mov byte [tok_type], TOK_USE
    ret
.kmm:
    mov byte [tok_type], TOK_MM
    ret
.kgc:
    mov byte [tok_type], TOK_GC
    ret
.kpr:
    mov byte [tok_type], TOK_PROT
    ret
.kr:
    mov byte [tok_type], TOK_RETURN
    ret
.kso:
    mov byte [tok_type], TOK_STOP
    ret
.kel:
    mov byte [tok_type], TOK_ELSE
    ret
.kei:
    mov byte [tok_type], TOK_ELIF
    ret
.kou:
    mov byte [tok_type], TOK_OUTPUT
    ret
.kand:
    mov byte [tok_type], TOK_AND
    ret
.kor:
    mov byte [tok_type], TOK_OR
    ret
.knot:
    mov byte [tok_type], TOK_NOT
    ret
.kerr:
    mov byte [tok_type], TOK_ERR
    ret
.kseq:
    mov byte [tok_type], TOK_TYPE_SEQ
    ret
.kpush:
    mov byte [tok_type], TOK_PUSH
    ret
.kpop:
    mov byte [tok_type], TOK_POP
    ret
.klen:
    mov byte [tok_type], TOK_LEN
    ret
.kskip:
    mov byte [tok_type], TOK_SKIP
    ret
.kpass:
    mov byte [tok_type], TOK_PASS
    ret
.keach:
    mov byte [tok_type], TOK_EACH
    ret
.kwhen:
    mov byte [tok_type], TOK_WHEN
    ret
.ktof:
    mov byte [tok_type], TOK_TYPEOF
    ret
.kbin:
    mov byte [tok_type], TOK_BIN
    ret
