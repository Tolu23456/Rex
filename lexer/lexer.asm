; -----------------------------------------------------------------------------
; Rex V5.0 Lexer
; Responsible for tokenizing source input into discrete symbols.
; Follows System V AMD64 ABI and strict style mandates.
; -----------------------------------------------------------------------------

default rel

%include "include/rex_defs.inc"

global lexer_init
global lexer_next
global tok_type
global tok_int
global tok_ident

section .bss
    lex_src:         resq 1
    lex_len:         resq 1
    lex_pos:         resq 1
    at_line_start:   resb 1
    indent_stack:    resq 32
    indent_depth:    resq 1
    pending_dedents: resq 1
    tok_type:        resb 1
    tok_int:         resq 1
    tok_ident:       resb 64

section .text

; -----------------------------------------------------------------------------
; lexer_init
; Input: RDI = source pointer, RSI = source length
; -----------------------------------------------------------------------------
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

; -----------------------------------------------------------------------------
; lexer_next
; Output: RAX = token type (also stored in [tok_type])
; -----------------------------------------------------------------------------
lexer_next:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

.restart:
    cmp qword [pending_dedents], 0
    jle .no_pending_dedents
    dec qword [pending_dedents]
    mov byte [tok_type], TOK_DEDENT
    jmp .done

.no_pending_dedents:
    cmp byte [at_line_start], 0
    je .skip_whitespace
    mov rcx, [lex_pos]
    mov rdi, [lex_src]
    xor rbx, rbx

.count_spaces:
    cmp rcx, [lex_len]
    jge .handle_eof
    movzx eax, byte [rdi+rcx]
    cmp al, ' '
    jne .check_indent_change
    inc rbx
    inc rcx
    jmp .count_spaces

.check_indent_change:
    cmp rcx, [lex_len]
    jge .handle_eof
    movzx eax, byte [rdi+rcx]
    cmp al, 0x0A
    je .blank_line
    mov [lex_pos], rcx
    mov byte [at_line_start], 0
    mov rax, [indent_depth]
    lea rcx, [indent_stack]
    mov rdx, [rcx+rax*8]
    cmp rbx, rdx
    jg .more_indent
    jl .less_indent
    jmp .skip_whitespace

.more_indent:
    inc qword [indent_depth]
    mov rax, [indent_depth]
    lea rcx, [indent_stack]
    mov [rcx+rax*8], rbx
    mov byte [tok_type], TOK_INDENT
    jmp .done

.less_indent:
    cmp qword [indent_depth], 0
    jle .dedent_error
    mov rax, [indent_depth]
    lea rcx, [indent_stack]
    mov rdx, [rcx+rax*8]
    cmp rdx, rbx
    jle .dedent_error
    dec qword [indent_depth]
    inc qword [pending_dedents]
    jmp .less_indent

.dedent_error:
    dec qword [pending_dedents]
    mov byte [tok_type], TOK_DEDENT
    jmp .done

.blank_line:
    inc rcx
    mov [lex_pos], rcx
    jmp .restart

.handle_eof:
    mov byte [at_line_start], 0
    mov [lex_pos], rcx
    jmp .restart

.skip_whitespace:
    mov rcx, [lex_pos]
    mov rdi, [lex_src]

.skip_loop:
    cmp rcx, [lex_len]
    jge .emit_eof
    movzx eax, byte [rdi+rcx]
    cmp al, ' '
    je .skip_next
    cmp al, 0x09
    je .skip_next
    jmp .switch_token

.skip_next:
    inc rcx
    jmp .skip_loop

.switch_token:
    mov [lex_pos], rcx
    cmp rcx, [lex_len]
    jge .emit_eof
    movzx eax, byte [rdi+rcx]

    cmp al, 0x0A
    je .emit_newline
    cmp al, '"'
    je .parse_string
    cmp al, '['
    je .emit_lbrack
    cmp al, ']'
    je .emit_rbrack
    cmp al, '{'
    je .emit_lbrace
    cmp al, '}'
    je .emit_rbrace
    cmp al, ','
    je .emit_comma
    cmp al, '('
    je .emit_lparen
    cmp al, ')'
    je .emit_rparen
    cmp al, '_'
    je .parse_identifier
    cmp al, 'a'
    jl .check_uppercase
    cmp al, 'z'
    jle .parse_identifier

.check_uppercase:
    cmp al, 'A'
    jl .check_digit
    cmp al, 'Z'
    jle .parse_identifier

.check_digit:
    cmp al, '0'
    jl .check_special
    cmp al, '9'
    jle .parse_numeric

.check_special:
    cmp al, '='
    je .handle_assign
    cmp al, ':'
    je .emit_colon
    cmp al, '.'
    je .check_dotdot
    cmp al, '@'
    je .emit_at
    cmp al, '+'
    je .emit_plus
    cmp al, '-'
    je .emit_minus
    cmp al, '*'
    je .emit_star
    cmp al, '/'
    je .handle_slash
    cmp al, '<'
    je .handle_lt
    cmp al, '>'
    je .handle_gt
    cmp al, '!'
    je .handle_bang
    cmp al, '&'
    je .emit_band
    cmp al, '|'
    je .emit_bor
    cmp al, '^'
    je .emit_bxor
    cmp al, '~'
    je .emit_bnot
    cmp al, '%'
    je .emit_mod
    inc qword [lex_pos]
    jmp .restart

; --- Single-character emitters ---
.emit_lbrack:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_LBRACK
    jmp .done

.emit_rbrack:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_RBRACK
    jmp .done

.emit_lbrace:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_LBRACE
    jmp .done

.emit_rbrace:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_RBRACE
    jmp .done

.emit_comma:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_COMMA
    jmp .done

.emit_lparen:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_LPAREN
    jmp .done

.emit_rparen:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_RPAREN
    jmp .done

.emit_plus:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_PLUS
    jmp .done

.emit_minus:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_MINUS
    jmp .done

.emit_star:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_STAR
    jmp .done

.emit_at:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_AT
    jmp .done

.emit_band:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_BAND
    jmp .done

.emit_bor:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_BOR
    jmp .done

.emit_bxor:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_BXOR
    jmp .done

.emit_bnot:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_BNOT
    jmp .done

.emit_mod:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_MOD
    jmp .done

; --- Multi-character operator handlers ---
; Handle '/' and '//' (line comment)
.handle_slash:
    mov rcx, [lex_pos]
    inc rcx
    cmp rcx, [lex_len]
    jge .emit_slash_single
    movzx eax, byte [rdi+rcx]
    cmp al, '/'
    je .skip_line_comment
.emit_slash_single:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_SLASH
    jmp .done

.skip_line_comment:
    inc rcx
.scl_loop:
    cmp rcx, [lex_len]
    jge .scl_eof
    movzx eax, byte [rdi+rcx]
    cmp al, 0x0A
    je .scl_eof
    inc rcx
    jmp .scl_loop
.scl_eof:
    mov [lex_pos], rcx
    jmp .restart

; Handle '<', '<=', '<<'
.handle_lt:
    mov rcx, [lex_pos]
    inc rcx
    cmp rcx, [lex_len]
    jge .emit_lt_single
    movzx eax, byte [rdi+rcx]
    cmp al, '='
    je .emit_lte
    cmp al, '<'
    je .emit_shl
.emit_lt_single:
    add qword [lex_pos], 1
    mov byte [tok_type], TOK_LT
    jmp .done
.emit_lte:
    add qword [lex_pos], 2
    mov byte [tok_type], TOK_LTE
    jmp .done
.emit_shl:
    add qword [lex_pos], 2
    mov byte [tok_type], TOK_SHL
    jmp .done

; Handle '>', '>=', '>>'
.handle_gt:
    mov rcx, [lex_pos]
    inc rcx
    cmp rcx, [lex_len]
    jge .emit_gt_single
    movzx eax, byte [rdi+rcx]
    cmp al, '='
    je .emit_gte
    cmp al, '>'
    je .emit_shr
.emit_gt_single:
    add qword [lex_pos], 1
    mov byte [tok_type], TOK_GT
    jmp .done
.emit_gte:
    add qword [lex_pos], 2
    mov byte [tok_type], TOK_GTE
    jmp .done
.emit_shr:
    add qword [lex_pos], 2
    mov byte [tok_type], TOK_SHR
    jmp .done

; Handle '!='
.handle_bang:
    mov rcx, [lex_pos]
    inc rcx
    cmp rcx, [lex_len]
    jge .skip_bang
    movzx eax, byte [rdi+rcx]
    cmp al, '='
    jne .skip_bang
    add qword [lex_pos], 2
    mov byte [tok_type], TOK_NEQ
    jmp .done
.skip_bang:
    inc qword [lex_pos]
    jmp .restart

; Handle '=' and '=='
.handle_assign:
    mov rcx, [lex_pos]
    inc rcx
    cmp rcx, [lex_len]
    jge .emit_assign
    movzx eax, byte [rdi+rcx]
    cmp al, '='
    jne .emit_assign
    inc rcx
    mov [lex_pos], rcx
    mov byte [tok_type], TOK_EQEQ
    jmp .done

.emit_assign:
    mov [lex_pos], rcx
    mov byte [tok_type], TOK_ASSIGN
    jmp .done

.emit_colon:
    inc qword [lex_pos]
    mov byte [tok_type], TOK_COLON
    jmp .done

.check_dotdot:
    mov rcx, [lex_pos]
    inc rcx
    cmp rcx, [lex_len]
    jge .skip_dot
    movzx eax, byte [rdi+rcx]
    cmp al, '.'
    jne .skip_dot
    add qword [lex_pos], 2
    mov byte [tok_type], TOK_DOTDOT
    jmp .done
.skip_dot:
    inc qword [lex_pos]
    jmp .restart

; --- String literal ---
.parse_string:
    inc qword [lex_pos]
    mov rcx, [lex_pos]
    mov rdi, [lex_src]
    lea rsi, [tok_ident]
    xor rbx, rbx

.string_loop:
    cmp rcx, [lex_len]
    jge .string_done
    movzx eax, byte [rdi+rcx]
    cmp al, '"'
    je .string_quote
    mov [rsi+rbx], al
    inc rbx
    inc rcx
    jmp .string_loop

.string_quote:
    inc rcx

.string_done:
    mov byte [rsi+rbx], 0
    mov [lex_pos], rcx
    mov byte [tok_type], TOK_STR_LIT
    jmp .done

; --- Identifier / keyword ---
.parse_identifier:
    mov rcx, [lex_pos]
    mov rdi, [lex_src]
    lea rsi, [tok_ident]
    xor rbx, rbx

.id_loop:
    cmp rbx, 63
    jge .id_done
    cmp rcx, [lex_len]
    jge .id_done
    movzx eax, byte [rdi+rcx]
    cmp al, '_'
    je .id_char
    cmp al, 'a'
    jl .id_upper
    cmp al, 'z'
    jle .id_char
.id_upper:
    cmp al, 'A'
    jl .id_digit
    cmp al, 'Z'
    jle .id_char
.id_digit:
    cmp al, '0'
    jl .id_done
    cmp al, '9'
    jle .id_char
    jmp .id_done
.id_char:
    mov [rsi+rbx], al
    inc rbx
    inc rcx
    jmp .id_loop
.id_done:
    mov byte [rsi+rbx], 0
    mov [lex_pos], rcx
    call lexer_classify
    jmp .done

; --- Numeric literal ---
.parse_numeric:
    mov rcx, [lex_pos]
    mov rdi, [lex_src]
    xor rbx, rbx

.int_loop:
    cmp rcx, [lex_len]
    jge .int_done
    movzx eax, byte [rdi+rcx]
    cmp al, '0'
    jl .check_float
    cmp al, '9'
    jg .check_float
    sub al, '0'
    imul rbx, rbx, 10
    movzx rax, al
    add rbx, rax
    inc rcx
    jmp .int_loop

.check_float:
    cmp al, '.'
    jne .check_complex
    cvtsi2sd xmm0, rbx
    inc rcx
    mov r8, 10
    cvtsi2sd xmm2, r8
    movsd xmm1, xmm2

.float_loop:
    cmp rcx, [lex_len]
    jge .float_done
    movzx eax, byte [rdi+rcx]
    cmp al, '0'
    jl .float_done
    cmp al, '9'
    jg .float_done
    sub al, '0'
    cvtsi2sd xmm3, rax
    divsd xmm3, xmm1
    addsd xmm0, xmm3
    mulsd xmm1, xmm2
    inc rcx
    jmp .float_loop

.float_done:
    mov [lex_pos], rcx
    movq [tok_int], xmm0
    mov byte [tok_type], TOK_FLOAT_LIT
    jmp .done

.check_complex:
    cmp al, 'j'
    jne .int_done
    inc rcx
    mov [lex_pos], rcx
    mov [tok_int], rbx
    mov byte [tok_type], TOK_COMPLEX_LIT
    jmp .done

.int_done:
    mov [lex_pos], rcx
    mov [tok_int], rbx
    mov byte [tok_type], TOK_INT_LIT
    jmp .done

.emit_eof:
    mov byte [tok_type], TOK_EOF
    xor eax, eax
    jmp .done

.emit_newline:
    inc qword [lex_pos]
    mov byte [at_line_start], 1
    mov byte [tok_type], TOK_NEWLINE
    jmp .done

.done:
    movzx eax, byte [tok_type]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

; -----------------------------------------------------------------------------
; lexer_classify — match identifier against keyword list
; -----------------------------------------------------------------------------
lexer_classify:
    mov eax, dword [tok_ident]

    cmp eax, 0x6c6f6f62           ; 'bool'
    je .is_bool
    cmp eax, 0x616f6c66           ; 'floa'
    jne .not_float
    cmp byte [tok_ident+4], 't'
    je .is_float
.not_float:
    cmp eax, 0x706d6f63           ; 'comp'
    jne .not_complex
    cmp dword [tok_ident+4], 0x78656c  ; 'lex'
    je .is_complex
.not_complex:
    cmp eax, 0x00727473           ; 'str'
    je .is_str
    cmp eax, 0x74636964           ; 'dict'
    jne .not_dict
    cmp byte [tok_ident+4], 0
    je .is_dict
.not_dict:
    cmp eax, 0x65757274           ; 'true'
    je .is_true
    cmp eax, 0x736c6166           ; 'fals'
    jne .not_false
    cmp byte [tok_ident+4], 'e'
    je .is_false
.not_false:
    cmp eax, 0x6e6b6e75           ; 'unkn'
    jne .not_unknown
    cmp dword [tok_ident+4], 0x6e776f   ; 'own'
    je .is_unknown
.not_unknown:
    cmp eax, 0x00746e69           ; 'int'
    je .is_int
    cmp eax, 0x00006669           ; 'if'
    je .is_if
    cmp eax, 0x00726f66           ; 'for'
    je .is_for
    cmp eax, 0x00006e69           ; 'in'
    je .is_in
    cmp eax, 0x6c696877           ; 'whil'
    jne .check_use
    cmp byte [tok_ident+4], 'e'
    je .is_while
.check_use:
    cmp eax, 0x00657375           ; 'use'
    je .is_use
    cmp eax, 0x00006d6d           ; 'mm'
    je .is_mm
    cmp eax, 0x00006367           ; 'gc'
    je .is_gc
    cmp eax, 0x746f7270           ; 'prot'
    je .is_prot
    cmp eax, 0x75746572           ; 'retu'
    jne .not_return
    cmp byte [tok_ident+4], 'r'
    jne .not_return
    cmp byte [tok_ident+5], 'n'
    je .is_return
.not_return:
    cmp eax, 0x706f7473           ; 'stop'
    je .is_stop
    cmp eax, 0x65736c65           ; 'else'
    je .is_else
    cmp eax, 0x66696c65           ; 'elif'
    je .is_elif
    cmp eax, 0x7074756f           ; 'outp'
    jne .check_new_kw
    cmp word [tok_ident+4], 0x7475  ; 'ut'
    je .is_output

.check_new_kw:
    ; --- Stage 4/5/7 keywords ---
    cmp eax, 0x00727265             ; 'err\0'
    je .is_err
    cmp eax, 0x00716573             ; 'seq\0'
    je .is_seq
    cmp eax, 0x68737570             ; 'push' (4 chars)
    jne .not_push
    cmp byte [tok_ident+4], 0
    je .is_push
.not_push:
    cmp eax, 0x00706F70             ; 'pop\0'
    je .is_pop
    cmp eax, 0x006E656C             ; 'len\0'
    je .is_len
    cmp eax, 0x65707974             ; 'type'
    jne .not_typeof
    cmp word [tok_ident+4], 0x666f  ; 'of'
    je .is_typeof
.not_typeof:
    mov eax, dword [tok_ident]
    and eax, 0x00ffffff
    cmp eax, 0x006e6962             ; 'bin'
    jne .default_id
    movzx eax, byte [tok_ident+3]
    test al, al
    jz .is_bin
    cmp al, '0'
    jl .default_id
    cmp al, '9'
    jle .is_bin

.default_id:
    mov byte [tok_type], TOK_IDENT
    ret

.is_int:     mov byte [tok_type], TOK_TYPE_INT
    ret
.is_bool:    mov byte [tok_type], TOK_TYPE_BOOL
    ret
.is_float:   mov byte [tok_type], TOK_TYPE_FLOAT
    ret
.is_complex: mov byte [tok_type], TOK_TYPE_COMPLEX
    ret
.is_str:     mov byte [tok_type], TOK_TYPE_STR
    ret
.is_dict:    mov byte [tok_type], TOK_TYPE_DICT
    ret
.is_true:    mov byte [tok_type], TOK_TRUE
    ret
.is_false:   mov byte [tok_type], TOK_FALSE
    ret
.is_unknown: mov byte [tok_type], TOK_UNKNOWN
    ret
.is_if:      mov byte [tok_type], TOK_IF
    ret
.is_for:     mov byte [tok_type], TOK_FOR
    ret
.is_in:      mov byte [tok_type], TOK_IN
    ret
.is_while:   mov byte [tok_type], TOK_WHILE
    ret
.is_use:     mov byte [tok_type], TOK_USE
    ret
.is_mm:      mov byte [tok_type], TOK_MM
    ret
.is_gc:      mov byte [tok_type], TOK_GC
    ret
.is_prot:    mov byte [tok_type], TOK_PROT
    ret
.is_return:  mov byte [tok_type], TOK_RETURN
    ret
.is_stop:    mov byte [tok_type], TOK_STOP
    ret
.is_else:    mov byte [tok_type], TOK_ELSE
    ret
.is_elif:    mov byte [tok_type], TOK_ELIF
    ret
.is_output:  mov byte [tok_type], TOK_OUTPUT
    ret
.is_err:     mov byte [tok_type], TOK_ERR
    ret
.is_seq:     mov byte [tok_type], TOK_TYPE_SEQ
    ret
.is_push:    mov byte [tok_type], TOK_PUSH
    ret
.is_pop:     mov byte [tok_type], TOK_POP
    ret
.is_len:     mov byte [tok_type], TOK_LEN
    ret
.is_typeof:  mov byte [tok_type], TOK_TYPEOF
    ret
.is_bin:     mov byte [tok_type], TOK_BIN
    ret
