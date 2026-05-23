; lexer.asm - Lexical Analyzer for Rex
; Tokenizes source code and handles indentation levels

%include "src/include/common.inc"
%include "src/include/tokens.inc"

section .data
    ; Table of keywords and their token types
    kw_prot    db "prot", 0
    kw_return  db "return", 0
    kw_if      db "if", 0
    kw_else    db "else", 0
    kw_for     db "for", 0
    kw_in      db "in", 0
    kw_use     db "use", 0
    kw_mm      db "mm", 0
    kw_gc      db "gc", 0
    kw_output  db "output", 0
    kw_int     db "int", 0
    kw_float   db "float", 0
    kw_str     db "str", 0
    kw_dict    db "dict", 0
    kw_tup     db "tup", 0
    kw_set     db "set", 0
    kw_complex db "complex", 0
    kw_none    db "None", 0
    kw_true    db "true", 0
    kw_false   db "false", 0
    kw_unknown db "unknown", 0

    ; Keyword table for easy lookup
    ; [pointer, token_type]
    keyword_table:
        dq kw_prot, TOK_PROT
        dq kw_return, TOK_RETURN
        dq kw_if, TOK_IF
        dq kw_else, TOK_ELSE
        dq kw_for, TOK_FOR
        dq kw_in, TOK_IN
        dq kw_use, TOK_USE
        dq kw_mm, TOK_MM
        dq kw_gc, TOK_GC
        dq kw_output, TOK_OUTPUT
        dq kw_int, TOK_INT
        dq kw_float, TOK_FLOAT
        dq kw_str, TOK_STR
        dq kw_dict, TOK_DICT
        dq kw_tup, TOK_TUP
        dq kw_set, TOK_SET
        dq kw_complex, TOK_COMPLEX
        dq kw_none, TOK_NONE
        dq kw_true, TOK_TRUE
        dq kw_false, TOK_FALSE
        dq kw_unknown, TOK_UNKNOWN
        dq 0, 0

section .bss
    indent_stack resq 64    ; Stack to keep track of indentation levels
    indent_ptr   resq 1     ; Current pointer in indent_stack

    src_ptr      resq 1     ; Pointer to current char in source
    src_end      resq 1     ; Pointer to end of source

    line_num     resq 1     ; Current line number for error reporting

    tok_value    resb 256   ; Buffer for current token string value
    tok_val_len  resq 1

    at_line_start resb 1    ; Flag: are we at the start of a line?
    pending_dedents resq 1  ; Count of dedent tokens to emit

section .text
    global rex_lex_init
    global rex_lex_next

; Initialize the lexer
rex_lex_init:
    mov [src_ptr], rdi
    add rsi, rdi
    mov [src_end], rsi
    mov qword [line_num], 1
    mov byte [at_line_start], 1
    mov qword [pending_dedents], 0

    ; Initialize indent stack
    mov qword [indent_stack], 0 ; Base level 0
    lea rax, [indent_stack + 8]
    mov [indent_ptr], rax
    ret

; Get next token
rex_lex_next:
    push rbx
    push rcx
    push rsi
    push rdi

    ; Check for pending dedents first
    mov rax, [pending_dedents]
    test rax, rax
    jz .no_pending_dedents
    dec qword [pending_dedents]
    sub qword [indent_ptr], 8
    mov rax, TOK_DEDENT
    jmp .done

.no_pending_dedents:
.start:
    mov rsi, [src_ptr]
    cmp rsi, [src_end]
    jae .eof

    ; Handle indentation at start of line
    cmp byte [at_line_start], 0
    jz .skip_whitespace

    call handle_indentation
    test rax, rax
    jnz .done ; Return INDENT or DEDENT if emitted

.skip_whitespace:
    mov rsi, [src_ptr]
    cmp rsi, [src_end]
    jae .eof

    mov al, [rsi]

    cmp al, ' '
    je .inc_src_skip
    cmp al, 9
    je .inc_src_skip

    ; Handle comments
    cmp al, '/'
    jne .check_newline
    cmp byte [rsi + 1], '/'
    jne .check_newline
.skip_comment:
    inc qword [src_ptr]
    mov rsi, [src_ptr]
    cmp rsi, [src_end]
    jae .eof
    cmp byte [rsi], 10
    je .handle_newline
    jmp .skip_comment

.check_newline:
    cmp al, 10
    je .handle_newline

    ; We found a non-whitespace character, so we are no longer at line start
    mov byte [at_line_start], 0

    ; Handle single char tokens
    cmp al, ':'
    je .lex_colon
    cmp al, '='
    je .lex_equals
    cmp al, '@'
    je .lex_at
    cmp al, '('
    je .lex_lparen
    cmp al, ')'
    je .lex_rparen
    cmp al, '['
    je .lex_lbrack
    cmp al, ']'
    je .lex_rbrack
    cmp al, '{'
    je .lex_lbrace
    cmp al, '}'
    je .lex_rbrace
    cmp al, ','
    je .lex_comma

    ; Handle arrows ->
    cmp al, '-'
    jne .check_ident
    cmp byte [rsi+1], '>'
    jne .lex_minus
    add qword [src_ptr], 2
    mov rax, TOK_ARROW
    jmp .done

.check_ident:
    call is_alpha
    test rax, rax
    jnz .lex_ident

    call is_digit
    test rax, rax
    jnz .lex_number

.unknown_char:
    inc qword [src_ptr]
    mov rax, -1
    jmp .done

.inc_src_skip:
    inc qword [src_ptr]
    jmp .skip_whitespace

.handle_newline:
    inc qword [src_ptr]
    inc qword [line_num]
    mov byte [at_line_start], 1
    mov rax, TOK_NEWLINE
    jmp .done

.lex_colon:
    inc qword [src_ptr]
    mov rax, TOK_COLON
    jmp .done

.lex_equals:
    inc qword [src_ptr]
    cmp byte [rsi+1], '='
    je .lex_eq_eq
    mov rax, TOK_ASSIGN
    jmp .done
.lex_eq_eq:
    inc qword [src_ptr]
    mov rax, TOK_EQ
    jmp .done

.lex_at:
    inc qword [src_ptr]
    mov rax, TOK_AT
    jmp .done

.lex_lparen:
    inc qword [src_ptr]
    mov rax, TOK_LPAREN
    jmp .done
.lex_rparen:
    inc qword [src_ptr]
    mov rax, TOK_RPAREN
    jmp .done
.lex_lbrack:
    inc qword [src_ptr]
    mov rax, TOK_LBRACK
    jmp .done
.lex_rbrack:
    inc qword [src_ptr]
    mov rax, TOK_RBRACK
    jmp .done
.lex_lbrace:
    inc qword [src_ptr]
    mov rax, TOK_LBRACE
    jmp .done
.lex_rbrace:
    inc qword [src_ptr]
    mov rax, TOK_RBRACE
    jmp .done
.lex_comma:
    inc qword [src_ptr]
    mov rax, TOK_COMMA
    jmp .done
.lex_minus:
    inc qword [src_ptr]
    mov rax, TOK_MINUS
    jmp .done

.lex_ident:
    xor rcx, rcx
.ident_loop:
    mov rsi, [src_ptr]
    cmp rsi, [src_end]
    jae .ident_end
    mov al, [rsi]
    call is_alnum_char
    test rax, rax
    jz .ident_end
    mov [tok_value + rcx], al
    inc rcx
    inc qword [src_ptr]
    jmp .ident_loop
.ident_end:
    mov [tok_val_len], rcx
    mov byte [tok_value + rcx], 0

    ; Check keyword table
    mov rsi, keyword_table
.kw_lookup:
    mov rdi, [rsi]
    test rdi, rdi
    jz .not_kw

    ; Compare strings
    push rsi
    lea rsi, [tok_value]
    call str_equal
    pop rsi
    test rax, rax
    jnz .is_kw

    add rsi, 16
    jmp .kw_lookup

.is_kw:
    mov rax, [rsi + 8]
    jmp .done

.not_kw:
    mov rax, TOK_IDENT
    lea rdx, [tok_value]
    jmp .done

.lex_number:
    xor rbx, rbx
.num_loop:
    mov rsi, [src_ptr]
    cmp rsi, [src_end]
    jae .num_end
    mov al, [rsi]
    call is_digit
    test rax, rax
    jz .num_end

    ; rbx = rbx * 10 + (al - '0')
    imul rbx, 10
    sub al, '0'
    movzx rax, al
    add rbx, rax
    inc qword [src_ptr]
    jmp .num_loop
.num_end:
    mov rax, TOK_LIT_INT
    mov rdx, rbx
    jmp .done

.eof:
    ; Emit remaining dedents if any
    mov rbx, [indent_ptr]
    sub rbx, indent_stack
    shr rbx, 3 ; rbx = number of levels on stack
    cmp rbx, 1
    jle .real_eof

    mov qword [pending_dedents], rbx
    sub qword [pending_dedents], 2
    sub qword [indent_ptr], 8
    mov rax, TOK_DEDENT
    jmp .done

.real_eof:
    mov rax, TOK_EOF
    jmp .done

.done:
    pop rdi
    pop rsi
    pop rcx
    pop rbx
    ret

; Helper to handle indentation
handle_indentation:
    xor rcx, rcx ; current indent level
    mov rsi, [src_ptr]
.h_loop:
    cmp rsi, [src_end]
    jae .h_end
    mov al, [rsi]
    cmp al, ' '
    je .h_space
    cmp al, 9 ; tab
    je .h_tab
    jmp .h_end
.h_space:
    inc rcx
    inc rsi
    jmp .h_loop
.h_tab:
    add rcx, 4 ; Tab = 4 spaces
    inc rsi
    jmp .h_loop
.h_end:
    mov [src_ptr], rsi

    ; Compare with top of stack
    mov rbx, [indent_ptr]
    mov rdx, [rbx - 8]

    cmp rcx, rdx
    je .h_same
    jg .h_indent

    ; Dedent - might need multiple
    xor rax, rax ; count
.h_dedent_loop:
    sub rbx, 8
    mov rdx, [rbx - 8]
    inc rax
    cmp rcx, rdx
    je .h_dedent_done
    jl .h_dedent_loop
    ; Error: inconsistent indentation
.h_dedent_done:
    mov [indent_ptr], rbx
    mov [pending_dedents], rax
    dec qword [pending_dedents]
    mov rax, TOK_DEDENT
    ret

.h_indent:
    mov [rbx], rcx
    add qword [indent_ptr], 8
    mov rax, TOK_INDENT
    ret

.h_same:
    xor rax, rax
    ret

; Helper: string equal (RSI, RDI)
str_equal:
    push rsi
    push rdi
.se_loop:
    mov al, [rsi]
    mov bl, [rdi]
    cmp al, bl
    jne .se_no
    test al, al
    jz .se_yes
    inc rsi
    inc rdi
    jmp .se_loop
.se_no:
    xor rax, rax
    jmp .se_done
.se_yes:
    mov rax, 1
.se_done:
    pop rdi
    pop rsi
    ret

is_alpha:
    mov rsi, [src_ptr]
    mov al, [rsi]
    cmp al, 'a'
    jl .upper
    cmp al, 'z'
    jle .yes
.upper:
    cmp al, 'A'
    jl .underscore
    cmp al, 'Z'
    jle .yes
.underscore:
    cmp al, '_'
    je .yes
    xor rax, rax
    ret
.yes:
    mov rax, 1
    ret

is_digit:
    mov rsi, [src_ptr]
    mov al, [rsi]
    cmp al, '0'
    jl .no
    cmp al, '9'
    jle .yes
.no:
    xor rax, rax
    ret
.yes:
    mov rax, 1
    ret

is_alnum_char:
    cmp al, 'a'
    jl .check_upper
    cmp al, 'z'
    jle .alnum_yes
.check_upper:
    cmp al, 'A'
    jl .check_digit
    cmp al, 'Z'
    jle .alnum_yes
.check_digit:
    cmp al, '0'
    jl .check_underscore
    cmp al, '9'
    jle .alnum_yes
.check_underscore:
    cmp al, '_'
    je .alnum_yes
    xor rax, rax
    ret
.alnum_yes:
    mov rax, 1
    ret
