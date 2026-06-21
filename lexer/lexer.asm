default rel
%include "include/rex_defs.inc"
global lexer_init, lexer_next, tok_type, tok_int, tok_ident, tok_line, tok_col
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
tok_line:      resq 1   ; current source line (1-indexed)
tok_col:       resq 1   ; current source column (0-indexed byte offset)
lex_line_start: resq 1  ; byte offset of the first byte of the current line
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
    mov qword [tok_line], 1
    mov qword [tok_col], 0
    mov qword [lex_line_start], 0
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
    mov [lex_line_start], rcx
    jmp .r
.ie:
    ; Indent tracking hit EOF — clear at_line_start flag and resume normal lexing.
    ; (All debug syscall output has been removed.)
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
    mov rax, [lex_line_start]
    sub rcx, rax
    mov [tok_col], rcx
    mov rcx, [lex_pos]
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
    cmp al, '#'
    je .ehash
    cmp al, '$'
    je .edollar
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
    mov rcx, [lex_pos]
    inc rcx
    cmp rcx, [lex_len]
    jge .eslash1
    movzx eax, byte [rdi+rcx]
    cmp al, '/'
    jne .eslash1
    ; // comment — skip bytes until newline or EOF
    inc rcx
.eslash_skip:
    cmp rcx, [lex_len]
    jge .eslash_eol
    movzx eax, byte [rdi+rcx]
    cmp al, 0x0A
    je .eslash_eol
    inc rcx
    jmp .eslash_skip
.eslash_eol:
    mov [lex_pos], rcx
    jmp .r
.eslash1:
    mov [lex_pos], rcx
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
    jne .pipe_arrow_chk
    inc rcx
    mov [lex_pos], rcx
    mov byte [tok_type], TOK_OR
    jmp .done
.pipe_arrow_chk:
    cmp al, '>'
    jne .pipe1
    inc rcx
    mov [lex_pos], rcx
    mov byte [tok_type], TOK_PIPE_ARROW
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
    cmp rbx, 63
    jge .strd
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
    mov rcx, [lex_pos]
    inc rcx
    cmp rcx, [lex_len]
    jge .epl1
    movzx eax, byte [rdi+rcx]
    cmp al, '+'
    jne .epl1
    inc rcx
    mov [lex_pos], rcx
    mov byte [tok_type], TOK_PLUSPLUS
    jmp .done
.epl1:
    mov [lex_pos], rcx
    mov byte [tok_type], TOK_PLUS
    jmp .done
.emi:
    mov rcx, [lex_pos]
    inc rcx
    cmp rcx, [lex_len]
    jge .emi1
    movzx eax, byte [rdi+rcx]
    cmp al, '-'
    jne .emi_arrow
    inc rcx
    mov [lex_pos], rcx
    mov byte [tok_type], TOK_MINUSMINUS
    jmp .done
.emi_arrow:
    cmp al, '>'
    jne .emi1
    inc rcx
    mov [lex_pos], rcx
    mov byte [tok_type], TOK_ARROW
    jmp .done
.emi1:
    mov [lex_pos], rcx
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
    inc qword [tok_line]        ; BUG-08 fix: increment line counter on each newline
    mov rax, [lex_pos]
    mov [lex_line_start], rax
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
    mov byte [tok_type], TOK_DOT
    jmp .done
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
    ; peek: if first char is '0' and next is 'b'/'B'/'x'/'X'/'o'/'O' → radix literal
    cmp rcx, [lex_len]
    jge .in_l
    movzx eax, byte [rdi+rcx]
    cmp al, '0'
    jne .in_l                  ; not '0' → normal decimal
    lea r9, [rcx+1]
    cmp r9, [lex_len]
    jge .in_l                  ; only one char, just '0'
    movzx eax, byte [rdi+rcx+1]
    cmp al, 'b'
    je .pin_bin
    cmp al, 'B'
    je .pin_bin
    cmp al, 'x'
    je .pin_hex
    cmp al, 'X'
    je .pin_hex
    cmp al, 'o'
    je .pin_oct
    cmp al, 'O'
    je .pin_oct
    jmp .in_l                  ; plain '0...' decimal
.pin_bin:
    add rcx, 2                 ; skip '0b'
.bin_l:
    cmp rcx, [lex_len]
    jge .in_d
    movzx eax, byte [rdi+rcx]
    cmp al, '0'
    je .bin_0
    cmp al, '1'
    je .bin_1
    jmp .in_d
.bin_0:
    shl rbx, 1
    inc rcx
    jmp .bin_l
.bin_1:
    shl rbx, 1
    or rbx, 1
    inc rcx
    jmp .bin_l
.pin_hex:
    add rcx, 2                 ; skip '0x'
.hex_l:
    cmp rcx, [lex_len]
    jge .in_d
    movzx eax, byte [rdi+rcx]
    cmp al, '0'
    jl .hex_d
    cmp al, '9'
    jle .hex_digit
    cmp al, 'a'
    jl .hex_alpha_up
    cmp al, 'f'
    jle .hex_lower
    jmp .hex_d
.hex_alpha_up:
    cmp al, 'A'
    jl .hex_d
    cmp al, 'F'
    jg .hex_d
    sub al, 'A' - 10
    jmp .hex_acc
.hex_lower:
    sub al, 'a' - 10
    jmp .hex_acc
.hex_digit:
    sub al, '0'
.hex_acc:
    shl rbx, 4
    movzx rax, al
    or rbx, rax
    inc rcx
    jmp .hex_l
.hex_d:
    jmp .in_d
.pin_oct:
    add rcx, 2                 ; skip '0o'
.oct_l:
    cmp rcx, [lex_len]
    jge .in_d
    movzx eax, byte [rdi+rcx]
    cmp al, '0'
    jl .in_d
    cmp al, '7'
    jg .in_d
    sub al, '0'
    shl rbx, 3
    movzx rax, al
    or rbx, rax
    inc rcx
    jmp .oct_l
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
    ; peek: if next char is also '.', this is '..' range — emit integer, don't enter float mode
    lea rax, [rcx+1]
    cmp rax, [lex_len]
    jge .in_float_start
    cmp byte [rdi+rcx+1], '.'
    je .in_d
.in_float_start:
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
    ; --- scientific notation (exponent) parsing ---
    cmp rcx, [lex_len]
    jge .done
    movzx eax, byte [rdi+rcx]
    cmp al, 'e'
    je .p_exp
    cmp al, 'E'
    jne .done
.p_exp:
    inc rcx
    cmp rcx, [lex_len]
    jge .done
    mov r8, 0               ; sign: 0 = pos, 1 = neg
    movzx eax, byte [rdi+rcx]
    cmp al, '+'
    je .p_exp_plus
    cmp al, '-'
    jne .p_exp_val
    mov r8, 1
.p_exp_plus:
    inc rcx
.p_exp_val:
    xor rbx, rbx            ; exponent accumulator
    mov r9, 0               ; count digits
.p_exp_loop:
    cmp rcx, [lex_len]
    jge .p_exp_apply
    movzx eax, byte [rdi+rcx]
    cmp al, '0'
    jl .p_exp_apply
    cmp al, '9'
    jg .p_exp_apply
    sub al, '0'
    imul rbx, rbx, 10
    movzx rax, al
    add rbx, rax
    inc rcx
    inc r9
    jmp .p_exp_loop
.p_exp_apply:
    test r9, r9
    jz .done                ; no digits after 'e'
    mov [lex_pos], rcx
    movq xmm0, [tok_int]
    test rbx, rbx
    jz .done                ; e0 = 1.0, no change
    ; multiplier in xmm1
    mov rax, 10
    cvtsi2sd xmm1, rax
    cvtsi2sd xmm2, rax      ; base 10.0
.p_exp_pow_loop:
    dec rbx
    jz .p_exp_pow_done
    mulsd xmm1, xmm2
    jmp .p_exp_pow_loop
.p_exp_pow_done:
    test r8, r8
    jnz .p_exp_div
    mulsd xmm0, xmm1
    jmp .p_exp_store
.p_exp_div:
    divsd xmm0, xmm1
.p_exp_store:
    movq [tok_int], xmm0
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

; ── '$' dollar handler: TOK_DOLLAR (syscall intercept) ───────────────────────
.edollar:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_DOLLAR
    jmp .done

; ── #decorator handler (local to lexer_next) ─────────────────────────────────
; Reached when dispatch sees '#'. Reads the following identifier word.
; Supported decorators: memo, memo_reset, pure, total, hot, cold, safe, unsafe, inline
; On entry: rcx = position of '#', rdi = lex_src base.
.ehash:
    inc rcx                    ; skip '#'
    xor rbx, rbx              ; tok_ident index
.ehash_word:
    cmp rcx, [lex_len]
    jge .ehash_done
    movzx eax, byte [rdi+rcx]
    cmp al, 'a'
    jl .ehash_chk_upper
    cmp al, 'z'
    jle .ehash_store
.ehash_chk_upper:
    cmp al, 'A'
    jl .ehash_chk_us
    cmp al, 'Z'
    jle .ehash_store
.ehash_chk_us:
    cmp al, '_'
    jne .ehash_done
.ehash_store:
    cmp rbx, 63
    jge .ehash_done
    mov [tok_ident+rbx], al
    inc rbx
    inc rcx
    jmp .ehash_word
.ehash_done:
    mov byte [tok_ident+rbx], 0
    mov [lex_pos], rcx
    ; --- #memo ---
    cmp dword [tok_ident], 0x6F6D656D  ; "memo" LE
    jne .ehash_chk_mr
    cmp byte [tok_ident+4], 0
    jne .ehash_chk_mr
    mov byte [tok_type], TOK_MEMO
    jmp .done
.ehash_chk_mr:
    ; --- #memo_reset ---
    cmp dword [tok_ident], 0x6F6D656D
    jne .ehash_chk_pure
    cmp byte [tok_ident+4], '_'
    jne .ehash_chk_pure
    cmp byte [tok_ident+5], 'r'
    jne .ehash_chk_pure
    cmp byte [tok_ident+6], 'e'
    jne .ehash_chk_pure
    cmp byte [tok_ident+7], 's'
    jne .ehash_chk_pure
    cmp byte [tok_ident+8], 'e'
    jne .ehash_chk_pure
    cmp byte [tok_ident+9], 't'
    jne .ehash_chk_pure
    cmp byte [tok_ident+10], 0
    jne .ehash_chk_pure
    mov byte [tok_type], TOK_MEMO_RESET
    jmp .done
.ehash_chk_pure:
    ; --- #pure: p,u,r,e → 0x65727570, len=4 ---
    cmp dword [tok_ident], 0x65727570
    jne .ehash_chk_total
    cmp byte [tok_ident+4], 0
    jne .ehash_chk_total
    mov byte [tok_type], TOK_PURE
    jmp .done
.ehash_chk_total:
    ; --- #total: t,o,t,a,l → dword=0x6174six6F74 → t=74,o=6F,t=74,a=61 → 0x6174oT ---
    ; "tota" = 0x61746F74 LE, [4]='l', [5]=0
    cmp dword [tok_ident], 0x61746F74
    jne .ehash_chk_hot
    cmp byte [tok_ident+4], 'l'
    jne .ehash_chk_hot
    cmp byte [tok_ident+5], 0
    jne .ehash_chk_hot
    mov byte [tok_type], TOK_TOTAL
    jmp .done
.ehash_chk_hot:
    ; --- #hot: h,o,t → 0x00746F68 LE, len=3 ---
    cmp dword [tok_ident], 0x00746F68
    jne .ehash_chk_cold
    cmp byte [tok_ident+3], 0
    jne .ehash_chk_cold
    mov byte [tok_type], TOK_HOT
    jmp .done
.ehash_chk_cold:
    ; --- #cold: c,o,l,d → 0x646C6F63 LE, len=4, [4]=0 ---
    cmp dword [tok_ident], 0x646C6F63
    jne .ehash_chk_safe
    cmp byte [tok_ident+4], 0
    jne .ehash_chk_safe
    mov byte [tok_type], TOK_COLD
    jmp .done
.ehash_chk_safe:
    ; --- #safe: s,a,f,e → 0x65666173 LE, len=4, [4]=0 ---
    cmp dword [tok_ident], 0x65666173
    jne .ehash_chk_unsafe
    cmp byte [tok_ident+4], 0
    jne .ehash_chk_unsafe
    mov byte [tok_type], TOK_SAFE_KW
    jmp .done
.ehash_chk_unsafe:
    ; --- #unsafe: u,n,s,a,f,e → dword=0x61736E75 [4]='f',[5]='e',[6]=0 ---
    cmp dword [tok_ident], 0x61736E75
    jne .ehash_chk_inline
    cmp byte [tok_ident+4], 'f'
    jne .ehash_chk_inline
    cmp byte [tok_ident+5], 'e'
    jne .ehash_chk_inline
    cmp byte [tok_ident+6], 0
    jne .ehash_chk_inline
    mov byte [tok_type], TOK_UNSAFE
    jmp .done
.ehash_chk_inline:
    ; --- #inline: i,n,l,i,n,e → dword=0x696C6E69 [4]='n',[5]='e',[6]=0 ---
    cmp dword [tok_ident], 0x696C6E69
    jne .ehash_skip_line
    cmp byte [tok_ident+4], 'n'
    jne .ehash_skip_line
    cmp byte [tok_ident+5], 'e'
    jne .ehash_skip_line
    cmp byte [tok_ident+6], 0
    jne .ehash_skip_line
    mov byte [tok_type], TOK_INLINE_KW
    jmp .done
.ehash_skip_line:
    mov rcx, [lex_pos]
.ehash_sl_loop:
    cmp rcx, [lex_len]
    jge .ehash_sl_done
    movzx eax, byte [rdi+rcx]
    inc rcx
    cmp al, 0x0A
    jne .ehash_sl_loop
.ehash_sl_done:
    mov [lex_pos], rcx
    jmp .r

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
    jne .nso
    cmp byte [tok_ident+4], 0
    je .kso
.nso:
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
    jne .npush
    cmp byte [tok_ident+4], 0
    je .kpush
.npush:
    cmp eax, 0x00706f70
    je .kpop
    cmp eax, 0x006e656c
    je .klen
    cmp eax, 0x70696b73
    jne .nskip
    cmp byte [tok_ident+4], 0
    je .kskip
.nskip:
    cmp eax, 0x73736170
    jne .npass
    cmp byte [tok_ident+4], 0
    je .kpass
.npass:
    cmp eax, 0x68636165
    jne .neach
    cmp byte [tok_ident+4], 0
    je .keach
.neach:
    cmp eax, 0x6e656877
    jne .nwhen
    cmp byte [tok_ident+4], 0
    je .kwhen
.nwhen:
    cmp eax, 0x65707974
    jne .ntype
    cmp dword [tok_ident+4], 0x666f
    je .ktof
.ntype:
    cmp eax, 0x006e6962
    je .kbin
    cmp eax, 0x70617773
    jne .nswap
    cmp byte [tok_ident+4], 0
    je .kswap
.nswap:
    cmp eax, 0x00736261
    jne .nabs
    cmp byte [tok_ident+3], 0
    je .kabs
.nabs:
    cmp eax, 0x00706163
    jne .ncap
    cmp byte [tok_ident+3], 0
    je .kcap
.ncap:
    ; "clock" → "cloc"=0x636F6C63 + 'k'=0x6B at [4], null at [5]
    cmp eax, 0x636F6C63
    jne .nclock
    cmp byte [tok_ident+4], 'k'
    jne .nclock
    cmp byte [tok_ident+5], 0
    jne .nclock
    jmp .kclock
.nclock:
    cmp eax, 0x00007369
    jne .nis
    cmp byte [tok_ident+2], 0
    je .kis
.nis:
    cmp eax, 0x70657473
    jne .nstep
    cmp byte [tok_ident+4], 0
    je .kstep
.nstep:
    ; "memo_reset": bare statement keyword kept; bare "memo" removed (use #memo).
    ; dword "memo" = 0x6F6D656D (LE). "memo_reset" has '_' at [4].
    cmp eax, 0x6F6D656D
    jne .nmemo
    cmp byte [tok_ident+4], 0
    je .nmemo          ; plain "memo" — not a keyword; fall to ident
    cmp byte [tok_ident+4], '_'
    jne .nmemo
    cmp byte [tok_ident+5], 'r'
    jne .nmemo
    cmp byte [tok_ident+6], 'e'
    jne .nmemo
    cmp byte [tok_ident+7], 's'
    jne .nmemo
    cmp byte [tok_ident+8], 'e'
    jne .nmemo
    cmp byte [tok_ident+9], 't'
    jne .nmemo
    cmp byte [tok_ident+10], 0
    jne .nmemo
    jmp .kmemo_reset
.nmemo:
    cmp eax, 0x656E6F4E
    jne .nkeyword
    cmp byte [tok_ident+4], 0
    je .knone
.nkeyword:
    ; "keyword": k,e,y,w,o,r,d  dword[0]=0x7779656B
    cmp eax, 0x7779656B
    jne .nas
    cmp byte [tok_ident+4], 'o'
    jne .nas
    cmp byte [tok_ident+5], 'r'
    jne .nas
    cmp byte [tok_ident+6], 'd'
    jne .nas
    cmp byte [tok_ident+7], 0
    jne .nas
    mov byte [tok_type], TOK_KEYWORD
    ret
.nas:
    ; "as": a,s  dword=0x00007361, byte[2]=0
    cmp eax, 0x00007361
    jne .nkw_rep
    cmp byte [tok_ident+2], 0
    jne .kid
    mov byte [tok_type], TOK_AS
    ret
.knone:
    mov byte [tok_type], TOK_NONE
    ret
.kstep:
    mov byte [tok_type], TOK_STEP
    ret
.nkw_rep:
    ; "repeat": r,e,p,e,a,t → dword=0x65706572, [4]='a',[5]='t',[6]=0
    cmp eax, 0x65706572
    jne .nkw_unr
    cmp byte [tok_ident+4], 'a'
    jne .kid
    cmp byte [tok_ident+5], 't'
    jne .kid
    cmp byte [tok_ident+6], 0
    jne .kid
    mov byte [tok_type], TOK_REPEAT
    ret
.nkw_unr:
    ; "unreachable": u,n,r,e → dword=0x65726E75, then a,c,h,a,b,l,e,\0
    cmp eax, 0x65726E75
    jne .nkw_asr
    cmp byte [tok_ident+4], 'a'
    jne .kid
    cmp byte [tok_ident+5], 'c'
    jne .kid
    cmp byte [tok_ident+6], 'h'
    jne .kid
    cmp byte [tok_ident+7], 'a'
    jne .kid
    cmp byte [tok_ident+8], 'b'
    jne .kid
    cmp byte [tok_ident+9], 'l'
    jne .kid
    cmp byte [tok_ident+10], 'e'
    jne .kid
    cmp byte [tok_ident+11], 0
    jne .kid
    mov byte [tok_type], TOK_UNREACHABLE
    ret
.nkw_asr:
    ; "assert": a,s,s,e,r,t → dword=0x65737361, [4]='r',[5]='t',[6]=0
    cmp eax, 0x65737361
    jne .nkw_const
    cmp byte [tok_ident+4], 'r'
    jne .nkw_const
    cmp byte [tok_ident+5], 't'
    jne .nkw_const
    cmp byte [tok_ident+6], 0
    jne .nkw_const
    mov byte [tok_type], TOK_ASSERT
    ret
.nkw_const:
    ; "const": c,o,n,s,t → dword=0x736E6F63, [4]='t',[5]=0
    cmp eax, 0x736E6F63
    jne .nkw_volatile
    cmp byte [tok_ident+4], 't'
    jne .nkw_volatile
    cmp byte [tok_ident+5], 0
    jne .nkw_volatile
    mov byte [tok_type], TOK_CONST
    ret
.nkw_volatile:
    ; "volatile": v,o,l,a,t,i,l,e → dword=0x616C6F76, [4]='t',[5]='i',[6]='l',[7]='e',[8]=0
    cmp eax, 0x616C6F76
    jne .nkw_set
    cmp byte [tok_ident+4], 't'
    jne .nkw_set
    cmp byte [tok_ident+5], 'i'
    jne .nkw_set
    cmp byte [tok_ident+6], 'l'
    jne .nkw_set
    cmp byte [tok_ident+7], 'e'
    jne .nkw_set
    cmp byte [tok_ident+8], 0
    jne .nkw_set
    mov byte [tok_type], TOK_VOLATILE
    ret
.nkw_set:
    ; "set": s,e,t → dword 3 bytes = 0x00746573, byte[3]=0
    cmp eax, 0x00746573
    jne .nkw_tup
    cmp byte [tok_ident+3], 0
    jne .nkw_tup
    mov byte [tok_type], TOK_TYPE_SET
    ret
.nkw_tup:
    ; "tup": t,u,p → 0x00707574, byte[3]=0
    cmp eax, 0x00707574
    jne .nkw_arr
    cmp byte [tok_ident+3], 0
    jne .nkw_arr
    mov byte [tok_type], TOK_TYPE_TUP
    ret
.nkw_arr:
    ; "arr": a,r,r → 0x00727261, byte[3]=0
    cmp eax, 0x00727261
    jne .nkw_fn
    cmp byte [tok_ident+3], 0
    jne .nkw_fn
    mov byte [tok_type], TOK_TYPE_ARR
    ret
.nkw_fn:
    ; "fn": f,n → 0x00006E66, byte[2]=0
    cmp eax, 0x00006E66
    jne .nkw_import
    cmp byte [tok_ident+2], 0
    jne .nkw_import
    mov byte [tok_type], TOK_FN
    ret
.nkw_import:
    ; "import": i,m,p,o,r,t → dword=0x6F706D69, [4]='r',[5]='t',[6]=0
    cmp eax, 0x6F706D69
    jne .nkw_from
    cmp byte [tok_ident+4], 'r'
    jne .nkw_from
    cmp byte [tok_ident+5], 't'
    jne .nkw_from
    cmp byte [tok_ident+6], 0
    jne .nkw_from
    mov byte [tok_type], TOK_IMPORT
    ret
.nkw_from:
    ; "from": f,r,o,m → 0x6D6F7266, [4]=0
    cmp eax, 0x6D6F7266
    jne .nkw_blast
    cmp byte [tok_ident+4], 0
    jne .nkw_blast
    mov byte [tok_type], TOK_FROM
    ret
.nkw_blast:
    ; "blast": b,l,a,s,t → dword=0x73616C62, [4]='t',[5]=0
    cmp eax, 0x73616C62
    jne .nkw_match
    cmp byte [tok_ident+4], 't'
    jne .nkw_match
    cmp byte [tok_ident+5], 0
    jne .nkw_match
    mov byte [tok_type], TOK_BLAST
    ret
.nkw_match:
    ; "match": m,a,t,c,h → dword=0x6374616D, [4]='h',[5]=0
    cmp eax, 0x6374616D
    jne .nkw_try
    cmp byte [tok_ident+4], 'h'
    jne .nkw_try
    cmp byte [tok_ident+5], 0
    jne .nkw_try
    mov byte [tok_type], TOK_MATCH
    ret
.nkw_try:
    ; "try": t,r,y → 0x00797274, byte[3]=0
    cmp eax, 0x00797274
    jne .nkw_except
    cmp byte [tok_ident+3], 0
    jne .nkw_except
    mov byte [tok_type], TOK_TRY
    ret
.nkw_except:
    ; "except": e,x,c,e,p,t → dword=0x65636578, [4]='p',[5]='t',[6]=0
    cmp eax, 0x65636578
    jne .nkw_finally
    cmp byte [tok_ident+4], 'p'
    jne .nkw_finally
    cmp byte [tok_ident+5], 't'
    jne .nkw_finally
    cmp byte [tok_ident+6], 0
    jne .nkw_finally
    mov byte [tok_type], TOK_EXCEPT
    ret
.nkw_finally:
    ; "finally": f,i,n,a,l,l,y → dword=0x616E6966, [4]='l',[5]='l',[6]='y',[7]=0
    cmp eax, 0x616E6966
    jne .nkw_ctx
    cmp byte [tok_ident+4], 'l'
    jne .nkw_ctx
    cmp byte [tok_ident+5], 'l'
    jne .nkw_ctx
    cmp byte [tok_ident+6], 'y'
    jne .nkw_ctx
    cmp byte [tok_ident+7], 0
    jne .nkw_ctx
    mov byte [tok_type], TOK_FINALLY
    ret
.nkw_ctx:
    ; "ctx": c,t,x → 0x00787463, byte[3]=0
    cmp eax, 0x00787463
    jne .nkw_show
    cmp byte [tok_ident+3], 0
    jne .nkw_show
    mov byte [tok_type], TOK_CTX
    ret
.nkw_show:
    ; "show": s,h,o,w → 0x776F6873, [4]=0
    cmp eax, 0x776F6873
    jne .nkw_warn
    cmp byte [tok_ident+4], 0
    jne .nkw_warn
    mov byte [tok_type], TOK_SHOW
    ret
.nkw_warn:
    ; "warn": w,a,r,n → 0x6E726177, [4]=0
    cmp eax, 0x6E726177
    jne .nkw_debug
    cmp byte [tok_ident+4], 0
    jne .nkw_debug
    mov byte [tok_type], TOK_WARN
    ret
.nkw_debug:
    ; "debug": d,e,b,u,g → dword=0x75626564, [4]='g',[5]=0
    cmp eax, 0x75626564
    jne .nkw_write
    cmp byte [tok_ident+4], 'g'
    jne .nkw_write
    cmp byte [tok_ident+5], 0
    jne .nkw_write
    mov byte [tok_type], TOK_DEBUG_KW
    ret
.nkw_write:
    ; "write": w,r,i,t,e → dword=0x74697277, [4]='e',[5]=0
    cmp eax, 0x74697277
    jne .nkw_flush
    cmp byte [tok_ident+4], 'e'
    jne .nkw_flush
    cmp byte [tok_ident+5], 0
    jne .nkw_flush
    mov byte [tok_type], TOK_WRITE
    ret
.nkw_flush:
    ; "flush": f,l,u,s,h → dword=0x73756C66, [4]='h',[5]=0
    cmp eax, 0x73756C66
    jne .nkw_input
    cmp byte [tok_ident+4], 'h'
    jne .nkw_input
    cmp byte [tok_ident+5], 0
    jne .nkw_input
    mov byte [tok_type], TOK_FLUSH
    ret
.nkw_input:
    ; "input": i,n,p,u,t → dword=0x7570 6E69 → bytes: 0x69,0x6E,0x70,0x75 → 0x75706E69, [4]='t',[5]=0
    cmp eax, 0x75706E69
    jne .nkw_flip
    cmp byte [tok_ident+4], 't'
    jne .nkw_flip
    cmp byte [tok_ident+5], 0
    jne .nkw_flip
    mov byte [tok_type], TOK_INPUT
    ret
.nkw_flip:
    ; "flip": f,l,i,p → 0x70696C66, [4]=0
    cmp eax, 0x70696C66
    jne .nkw_rand
    cmp byte [tok_ident+4], 0
    jne .nkw_rand
    mov byte [tok_type], TOK_FLIP
    ret
.nkw_rand:
    ; "rand": r,a,n,d → 0x646E6172, [4]=0
    cmp eax, 0x646E6172
    jne .nkw_fmt
    cmp byte [tok_ident+4], 0
    jne .nkw_fmt
    mov byte [tok_type], TOK_RAND
    ret
.nkw_fmt:
    ; "fmt": f,m,t → 0x00746D66, byte[3]=0
    cmp eax, 0x00746D66
    jne .nkw_str_at
    cmp byte [tok_ident+3], 0
    jne .nkw_str_at
    mov byte [tok_type], TOK_FMT
    ret
.nkw_str_at:
    ; "str_at": s,t,r,_ = LE 0x5F727473; [4]='a',[5]='t',[6]=0
    cmp eax, 0x5F727473
    jne .nkw_char_kw
    cmp byte [tok_ident+4], 'a'
    jne .nkw_char_kw
    cmp byte [tok_ident+5], 't'
    jne .nkw_char_kw
    cmp byte [tok_ident+6], 0
    jne .nkw_char_kw
    mov byte [tok_type], TOK_STR_AT
    ret
.nkw_char_kw:
    ; "char": c,h,a,r = LE 0x72616863; [4]=0
    cmp eax, 0x72616863
    jne .nkw_file
    cmp byte [tok_ident+4], 0
    jne .nkw_file
    mov byte [tok_type], TOK_CHAR_KW
    ret
.nkw_file:
    ; "file_*": f,i,l,e = LE 0x656C6966; [4]='_', dispatch on [5]
    cmp eax, 0x656C6966
    jne .nkw_exit_kw
    cmp byte [tok_ident+4], '_'
    jne .nkw_exit_kw
    cmp byte [tok_ident+5], 'o'
    je .nkw_file_open
    cmp byte [tok_ident+5], 'r'
    je .nkw_file_read
    cmp byte [tok_ident+5], 'w'
    je .nkw_file_write
    cmp byte [tok_ident+5], 'c'
    je .nkw_file_close
    jmp .nkw_exit_kw
.nkw_file_open:
    ; "file_open": [5]='o',[6]='p',[7]='e',[8]='n',[9]=0
    cmp byte [tok_ident+6], 'p'
    jne .nkw_exit_kw
    cmp byte [tok_ident+7], 'e'
    jne .nkw_exit_kw
    cmp byte [tok_ident+8], 'n'
    jne .nkw_exit_kw
    cmp byte [tok_ident+9], 0
    jne .nkw_exit_kw
    mov byte [tok_type], TOK_FILE_OPEN
    ret
.nkw_file_read:
    ; "file_read_all": ...[6]='e',[7]='a',[8]='d',[9]='_',[10]='a',[11]='l',[12]='l',[13]=0
    cmp byte [tok_ident+6], 'e'
    jne .nkw_exit_kw
    cmp byte [tok_ident+7], 'a'
    jne .nkw_exit_kw
    cmp byte [tok_ident+8], 'd'
    jne .nkw_exit_kw
    cmp byte [tok_ident+9], '_'
    jne .nkw_exit_kw
    cmp byte [tok_ident+10], 'a'
    jne .nkw_exit_kw
    cmp byte [tok_ident+11], 'l'
    jne .nkw_exit_kw
    cmp byte [tok_ident+12], 'l'
    jne .nkw_exit_kw
    cmp byte [tok_ident+13], 0
    jne .nkw_exit_kw
    mov byte [tok_type], TOK_FILE_READ
    ret
.nkw_file_write:
    ; "file_write": [5]='w',[6]='r',[7]='i',[8]='t',[9]='e',[10]=0
    cmp byte [tok_ident+6], 'r'
    jne .nkw_exit_kw
    cmp byte [tok_ident+7], 'i'
    jne .nkw_exit_kw
    cmp byte [tok_ident+8], 't'
    jne .nkw_exit_kw
    cmp byte [tok_ident+9], 'e'
    jne .nkw_exit_kw
    cmp byte [tok_ident+10], 0
    jne .nkw_exit_kw
    mov byte [tok_type], TOK_FILE_WRITE
    ret
.nkw_file_close:
    ; "file_close": [5]='c',[6]='l',[7]='o',[8]='s',[9]='e',[10]=0
    cmp byte [tok_ident+6], 'l'
    jne .nkw_exit_kw
    cmp byte [tok_ident+7], 'o'
    jne .nkw_exit_kw
    cmp byte [tok_ident+8], 's'
    jne .nkw_exit_kw
    cmp byte [tok_ident+9], 'e'
    jne .nkw_exit_kw
    cmp byte [tok_ident+10], 0
    jne .nkw_exit_kw
    mov byte [tok_type], TOK_FILE_CLOSE
    ret
.nkw_exit_kw:
    ; "exit": e,x,i,t = LE 0x74697865; [4]=0
    cmp eax, 0x74697865
    jne .nkw_alloc_kw
    cmp byte [tok_ident+4], 0
    jne .nkw_alloc_kw
    mov byte [tok_type], TOK_EXIT_KW
    ret
.nkw_alloc_kw:
    ; "alloc": a,l,l,o = LE 0x6F6C6C61; [4]='c',[5]=0
    cmp eax, 0x6F6C6C61
    jne .kid
    cmp byte [tok_ident+4], 'c'
    jne .kid
    cmp byte [tok_ident+5], 0
    jne .kid
    mov byte [tok_type], TOK_ALLOC_KW
    ret
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
.kswap:
    mov byte [tok_type], TOK_SWAP
    ret
.kabs:
    mov byte [tok_type], TOK_ABS
    ret
.kcap:
    mov byte [tok_type], TOK_CAP
    ret
.kclock:
    mov byte [tok_type], TOK_CLOCK
    ret
.kis:
    mov byte [tok_type], TOK_IS
    ret
.kmemo:
    mov byte [tok_type], TOK_MEMO
    ret
.kmemo_reset:
    mov byte [tok_type], TOK_MEMO_RESET
    ret

section .data
ldbg_ie_msg: db "IE id=",0
ldbg_sep:    db " pd=",0
ldbg_nl:     db 10,0
