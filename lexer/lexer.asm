; Rex Lexer Implementation
; written in x86-64 NASM assembly
;
; Bug fixes applied:
;   - check_empty_line now saves/restores RBX (Bug 4: ABI violation)
;   - .question handler removed redundant read_char (Bug 1: double-consume)

%include "include/rex_defs.inc"

section .data
    ; Indentation stack: up to 32 levels of nesting
    indent_stack       times 32 dd 0
    indent_stack_len   dd 1 ; contains 0 initially

    ; Keyword strings and their corresponding tokens/types
    str_int     db "int", 0
    str_float   db "float", 0
    str_bool    db "bool", 0
    str_str     db "str", 0
    str_char    db "char", 0
    str_byte    db "byte", 0
    str_const   db "const", 0
    str_type    db "type", 0
    str_struct  db "struct", 0
    str_enum    db "enum", 0
    str_tup     db "tup", 0
    str_seq     db "seq", 0
    str_dict    db "dict", 0
    str_null    db "null", 0
    str_output  db "output", 0
    str_true    db "true", 0
    str_false   db "false", 0
    str_neutral db "neutral", 0
    str_and     db "and", 0
    str_or      db "or", 0
    str_not     db "not", 0

section .bss
    global src_ptr
    global src_len
    global src_idx
    global line_num

    global tok_type
    global tok_str_ptr
    global tok_str_len
    global tok_ival
    global tok_fval

    global pending_dedents
    global at_line_start

    src_ptr         resq 1
    src_len         resq 1
    src_idx         resq 1
    line_num        resq 1
    
    tok_type        resd 1
    tok_str_ptr     resq 1
    tok_str_len     resq 1
    tok_ival        resq 1
    tok_fval        resq 1
    
    pending_dedents resd 1
    at_line_start   resb 1

section .text
    global lex_init
    global next_token
    global get_error_loc

; Initialize the lexer
; rdi = buffer_ptr, rsi = buffer_size
lex_init:
    mov [src_ptr], rdi
    mov [src_len], rsi
    mov qword [src_idx], 0
    mov qword [line_num], 1
    mov dword [pending_dedents], 0
    mov byte [at_line_start], 1
    
    ; Reset indentation stack to just containing 0
    mov dword [indent_stack], 0
    mov dword [indent_stack_len], 1
    ret

; Helper to peek next character without advancing
; Returns rax = char, or 0 if EOF
peek_char:
    mov rsi, [src_ptr]
    mov rdi, [src_idx]
    cmp rdi, [src_len]
    jae .eof
    movzx rax, byte [rsi + rdi]
    ret
.eof:
    xor rax, rax
    ret

; Helper to read current character and advance
; Returns rax = char, or 0 if EOF
read_char:
    mov rsi, [src_ptr]
    mov rdi, [src_idx]
    cmp rdi, [src_len]
    jae .eof
    movzx rax, byte [rsi + rdi]
    inc qword [src_idx]
    ret
.eof:
    xor rax, rax
    ret

; Check if the current line starting from src_idx is empty or a comment
; Returns rax = 1 if empty/comment, 0 otherwise
; BUG FIX (Bug 4): push/pop rbx so callers' RBX is preserved (SysV ABI)
check_empty_line:
    push rbx                    ; <-- FIX: save callee-saved RBX
    mov rsi, [src_ptr]
    mov rcx, [src_idx]
.loop:
    cmp rcx, [src_len]
    jae .empty
    movzx rax, byte [rsi + rcx]
    cmp al, ' '
    je .next
    cmp al, 9       ; tab
    je .next
    cmp al, 10      ; LF
    je .empty
    cmp al, 13      ; CR
    je .empty
    
    ; Check for comment '//'
    cmp al, '/'
    jne .not_empty
    mov rdx, rcx
    inc rdx
    cmp rdx, [src_len]
    jae .not_empty
    movzx rbx, byte [rsi + rdx]  ; rbx is now saved, safe to use
    cmp bl, '/'
    je .empty
.not_empty:
    xor rax, rax
    pop rbx                     ; <-- FIX: restore before returning
    ret
.next:
    inc rcx
    jmp .loop
.empty:
    mov rax, 1
    pop rbx                     ; <-- FIX: restore before returning
    ret

; Skip whitespace (spaces and tabs only)
skip_spaces:
.loop:
    call peek_char
    cmp rax, ' '
    je .consume
    cmp rax, 9      ; tab
    je .consume
    ret
.consume:
    call read_char
    jmp .loop

; Skip single-line comment '//'
skip_comment:
.loop:
    call peek_char
    cmp rax, 0
    je .done
    cmp rax, 10     ; LF
    je .done
    cmp rax, 13     ; CR
    je .done
    call read_char
    jmp .loop
.done:
    ret

; Compare two strings
; rdi = null-terminated string, rsi = string buffer, rdx = len
; Returns rax = 1 if equal, 0 if not
strcmp_len:
    push rbx
    xor rcx, rcx
.loop:
    cmp rcx, rdx
    je .check_null
    movzx rax, byte [rdi + rcx]
    movzx rbx, byte [rsi + rcx]
    cmp al, bl
    jne .not_equal
    inc rcx
    jmp .loop
.check_null:
    movzx rax, byte [rdi + rcx]
    cmp al, 0
    jne .not_equal
    mov rax, 1
    pop rbx
    ret
.not_equal:
    xor rax, rax
    pop rbx
    ret

; Get current line number and column number for error reporting
; Returns: rax = line, rdx = column
get_error_loc:
    mov rax, [line_num]
    ; Simple approximation of column for now
    mov rdx, [src_idx]
    ret

; Main entry point to get next token
next_token:
    ; 1. Check pending dedents
    mov eax, [pending_dedents]
    test eax, eax
    jz .no_pending_dedents
    dec dword [pending_dedents]
    mov dword [tok_type], TOK_DEDENT
    ret

.no_pending_dedents:
    ; 2. Handle line start / indentation
    cmp byte [at_line_start], 1
    jne .skip_indent_logic
    
    ; Check if line is empty or comment
    call check_empty_line
    test rax, rax
    jz .process_indent
    
    ; If empty line, consume spaces and newline/comment and retry
    call skip_spaces
    call peek_char
    cmp rax, '/'
    jne .no_comment
    call skip_comment
.no_comment:
    call peek_char
    cmp rax, 13
    jne .no_cr
    call read_char
.no_cr:
    call peek_char
    cmp rax, 10
    jne .no_lf
    call read_char
    inc qword [line_num]
.no_lf:
    ; If at EOF after consuming empty lines, return TOK_EOF (or pending dedents)
    ; Otherwise retry for the next non-empty line
    call peek_char
    test rax, rax
    jz .eof
    jmp next_token

.process_indent:
    mov byte [at_line_start], 0
    
    ; Count space spaces/tabs (using r8 instead of r12)
    xor r8, r8 ; space count
.indent_loop:
    call peek_char
    cmp rax, ' '
    je .inc_space
    cmp rax, 9      ; tab
    je .inc_tab
    jmp .indent_done
.inc_space:
    inc r8
    call read_char
    jmp .indent_loop
.inc_tab:
    add r8, 4      ; Treat tab as 4 spaces
    call read_char
    jmp .indent_loop

.indent_done:
    ; Compare with top of stack
    mov eax, [indent_stack_len]
    dec eax
    mov ecx, [indent_stack + rax * 4] ; top value
    cmp r8d, ecx
    jg .indent_indent
    jl .indent_dedent
    jmp .skip_indent_logic ; equal, just proceed

.indent_indent:
    ; Push r8d to stack
    mov eax, [indent_stack_len]
    mov [indent_stack + eax * 4], r8d
    inc dword [indent_stack_len]
    mov dword [tok_type], TOK_INDENT
    ret

.indent_dedent:
    ; Count how many dedents we need (using r9 instead of r13)
    xor r9, r9 ; dedent count
.dedent_loop:
    mov eax, [indent_stack_len]
    dec eax
    jz .dedent_error ; stack empty but we didn't match 0 (should never happen as bottom is 0)
    mov ecx, [indent_stack + rax * 4]
    cmp r8d, ecx
    je .dedent_match
    jg .dedent_error ; indentation error: mismatched level
    
    ; Pop stack
    dec dword [indent_stack_len]
    inc r9
    jmp .dedent_loop

.dedent_match:
    ; We need to emit r9 TOK_DEDENT tokens.
    ; Emit the first one now, save the rest in pending_dedents
    dec r9
    mov [pending_dedents], r9d
    mov dword [tok_type], TOK_DEDENT
    ret

.dedent_error:
    ; Set TOK_EOF or handle error
    mov dword [tok_type], TOK_EOF
    ret

.skip_indent_logic:
    call skip_spaces
    
    ; Check EOF
    call peek_char
    test rax, rax
    jz .eof
    
    ; Save token start pointer
    mov rsi, [src_ptr]
    mov rdi, [src_idx]
    lea rbx, [rsi + rdi]
    mov [tok_str_ptr], rbx
    
    ; Handle Newline
    cmp rax, 13
    je .newline
    cmp rax, 10
    je .newline
    
    ; Handle Comment
    cmp rax, '/'
    je .comment_or_slash

    ; Handle string literals
    cmp rax, '"'
    je .string

    ; Handle char literals
    cmp rax, 39
    je .char_literal

    ; Handle digits (integer or float)
    cmp rax, '0'
    jl .not_digit
    cmp rax, '9'
    jg .not_digit
    jmp .number

.not_digit:
    ; Handle Identifiers/Keywords
    cmp rax, 'a'
    jl .not_lower
    cmp rax, 'z'
    jle .identifier
.not_lower:
    cmp rax, 'A'
    jl .not_upper
    cmp rax, 'Z'
    jle .identifier
.not_upper:
    cmp rax, '_'
    je .identifier

    ; Handle individual operators
    call read_char
    cmp rax, ':'
    je .colon
    cmp rax, '='
    je .assign
    cmp rax, '+'
    je .plus
    cmp rax, '-'
    je .minus
    cmp rax, '*'
    je .star
    cmp rax, '('
    je .lparen
    cmp rax, ')'
    je .rparen
    cmp rax, '['
    je .lbracket
    cmp rax, ']'
    je .rbracket
    cmp rax, '{'
    je .lbrace
    cmp rax, '}'
    je .rbrace
    cmp rax, ','
    je .comma
    cmp rax, '.'
    je .dot
    cmp rax, '?'
    je .question
    cmp rax, '%'
    je .mod
    cmp rax, '&'
    je .and
    cmp rax, '|'
    je .or
    cmp rax, '^'
    je .xor

    ; Unknown token character, skip it or return EOF
    jmp next_token

.eof:
    ; Check if we need to emit remaining dedents to reach 0
    mov eax, [indent_stack_len]
    cmp eax, 1
    jbe .real_eof
    dec dword [indent_stack_len]
    mov dword [tok_type], TOK_DEDENT
    ret
.real_eof:
    mov dword [tok_type], TOK_EOF
    mov qword [tok_str_ptr], 0
    mov qword [tok_str_len], 0
    ret

.newline:
    call read_char
    cmp rax, 13
    jne .no_cr2
    call peek_char
    cmp rax, 10
    jne .no_cr2
    call read_char
.no_cr2:
    inc qword [line_num]
    mov byte [at_line_start], 1
    mov dword [tok_type], TOK_NEWLINE
    mov rsi, [src_idx]
    mov rdi, [tok_str_ptr]
    mov rdx, [src_ptr]
    add rdx, rsi
    sub rdx, rdi
    mov [tok_str_len], rdx
    ret

.comment_or_slash:
    call read_char ; consume '/'
    call peek_char
    cmp rax, '/'
    je .comment
    ; Otherwise it's TOK_SLASH
    mov dword [tok_type], TOK_SLASH
    mov qword [tok_str_len], 1
    ret
.comment:
    call skip_comment
    jmp next_token

.string:
    call read_char ; consume opening quote
    mov rsi, [src_ptr]
    mov rdi, [src_idx]
    lea rbx, [rsi + rdi]
    mov [tok_str_ptr], rbx ; store string content start pointer
    
    xor r8, r8 ; string length count (using r8 instead of r12)
.str_loop:
    call read_char
    test rax, rax
    jz .str_error
    cmp rax, '"'
    je .str_done
    cmp rax, 10
    je .str_newline
    inc r8
    jmp .str_loop
.str_newline:
    inc qword [line_num]
    inc r8
    jmp .str_loop
.str_done:
    mov [tok_str_len], r8
    mov dword [tok_type], TOK_STR_LIT
    ret
.str_error:
    mov dword [tok_type], TOK_EOF
    ret

.char_literal:
    call read_char ; consume opening quote
    mov rsi, [src_ptr]
    mov rdi, [src_idx]
    lea rbx, [rsi + rdi]
    mov [tok_str_ptr], rbx
    
    call read_char
    test rax, rax
    jz .str_error
    mov [tok_ival], rax ; store char ASCII/UTF-8 byte
    
    call read_char
    cmp rax, 39 ; closing quote
    jne .str_error
    
    mov qword [tok_str_len], 1
    mov dword [tok_type], TOK_CHAR_LIT
    ret

.number:
    ; Accumulate digits, support underscores, check if float
    xor r8, r8 ; whole part value (integer) (using r8 instead of r12)
    xor r9, r9 ; float flag (0 = int, 1 = float) (using r9 instead of r13)
    
    ; check hex / binary / octal prefix
    call peek_char
    cmp rax, '0'
    jne .num_loop
    mov rsi, [src_ptr]
    mov rdi, [src_idx]
    inc rdi
    cmp rdi, [src_len]
    jae .num_loop
    movzx rbx, byte [rsi + rdi]
    cmp bl, 'x'
    je .hex_start
    cmp bl, 'X'
    je .hex_start
    cmp bl, 'b'
    je .bin_start
    cmp bl, 'B'
    je .bin_start
    cmp bl, 'o'
    je .oct_start
    cmp bl, 'O'
    je .oct_start
    jmp .num_loop

.hex_start:
    call read_char ; consume 0
    call read_char ; consume x
.hex_loop:
    call peek_char
    cmp rax, '_'
    je .hex_under
    cmp rax, '0'
    jl .num_done
    cmp rax, '9'
    jle .hex_digit
    cmp rax, 'A'
    jl .num_done
    cmp rax, 'F'
    jle .hex_upper
    cmp rax, 'a'
    jl .num_done
    cmp rax, 'f'
    jle .hex_lower
    jmp .num_done

.hex_digit:
    call read_char
    sub rax, '0'
    shl r8, 4
    add r8, rax
    jmp .hex_loop
.hex_upper:
    call read_char
    sub rax, 'A'
    add rax, 10
    shl r8, 4
    add r8, rax
    jmp .hex_loop
.hex_lower:
    call read_char
    sub rax, 'a'
    add rax, 10
    shl r8, 4
    add r8, rax
    jmp .hex_loop
.hex_under:
    call read_char
    jmp .hex_loop

.bin_start:
    call read_char ; consume 0
    call read_char ; consume b
.bin_loop:
    call peek_char
    cmp rax, '_'
    je .bin_under
    cmp rax, '0'
    je .bin_zero
    cmp rax, '1'
    je .bin_one
    jmp .num_done
.bin_zero:
    call read_char
    shl r8, 1
    jmp .bin_loop
.bin_one:
    call read_char
    shl r8, 1
    or r8, 1
    jmp .bin_loop
.bin_under:
    call read_char
    jmp .bin_loop

.oct_start:
    call read_char ; consume 0
    call read_char ; consume o
.oct_loop:
    call peek_char
    cmp rax, '_'
    je .oct_under
    cmp rax, '0'
    jl .num_done
    cmp rax, '7'
    jg .num_done
    call read_char
    sub rax, '0'
    imul r8, 8
    add r8, rax
    jmp .oct_loop
.oct_under:
    call read_char
    jmp .oct_loop

.num_loop:
    call peek_char
    cmp rax, '_'
    je .num_underscore
    cmp rax, '.'
    je .num_dot
    cmp rax, '0'
    jl .num_done
    cmp rax, '9'
    jg .num_done
    
    ; Accumulate integer value
    call read_char
    sub rax, '0'
    imul r8, 10
    add r8, rax
    jmp .num_loop

.num_underscore:
    call read_char ; consume '_'
    jmp .num_loop

.num_dot:
    mov rsi, [src_ptr]
    mov rdi, [src_idx]
    inc rdi
    cmp rdi, [src_len]
    jae .num_done
    movzx rbx, byte [rsi + rdi]
    cmp bl, '.'
    je .num_done ; '..' range operator
    cmp bl, '0'
    jl .num_done
    cmp bl, '9'
    jg .num_done
    
    ; It is a float!
    call read_char ; consume '.'
    mov r9, 1
    
    cvtsi2sd xmm0, r8 ; xmm0 = whole part
    movq xmm1, qword [.float_ten] ; xmm1 = 10.0
    movq xmm2, qword [.float_one] ; xmm2 = 1.0
.frac_loop:
    call peek_char
    cmp rax, '_'
    je .frac_underscore
    cmp rax, '0'
    jl .frac_done
    cmp rax, '9'
    jg .frac_done
    
    call read_char
    sub rax, '0'
    cvtsi2sd xmm3, rax ; xmm3 = digit
    divsd xmm2, xmm1 ; xmm2 = place value (0.1, 0.01, ...)
    mulsd xmm3, xmm2
    addsd xmm0, xmm3
    jmp .frac_loop

.frac_underscore:
    call read_char
    jmp .frac_loop

.frac_sci:
    ; Scientific notation: e or E followed by optional +/- and digits
    call read_char ; consume 'e' or 'E'
    ; check sign
    xor r10, r10 ; r10 = exponent sign: 0 = positive, 1 = negative
    call peek_char
    cmp rax, '+'
    je .sci_plus
    cmp rax, '-'
    je .sci_minus
    jmp .sci_exp_digits
.sci_plus:
    call read_char
    jmp .sci_exp_digits
.sci_minus:
    call read_char
    mov r10, 1
.sci_exp_digits:
    xor r11, r11 ; r11 = exponent value
.sci_exp_loop:
    call peek_char
    cmp rax, '0'
    jl .sci_exp_done
    cmp rax, '9'
    jg .sci_exp_done
    call read_char
    sub rax, '0'
    imul r11, 10
    add r11, rax
    jmp .sci_exp_loop
.sci_exp_done:
    ; Apply exponent: multiply or divide by 10^r11
    test r10, r10
    jnz .sci_neg_exp
.sci_pos_exp:
    test r11, r11
    jz .sci_done
    mulsd xmm0, xmm1 ; multiply by 10.0
    dec r11
    jmp .sci_pos_exp
.sci_neg_exp:
    test r11, r11
    jz .sci_done
    divsd xmm0, xmm1 ; divide by 10.0
    dec r11
    jmp .sci_neg_exp
.sci_done:
    movq [tok_fval], xmm0
    mov dword [tok_type], TOK_FLOAT_LIT
    jmp .num_finish

.frac_done:
    ; Check for scientific notation after fractional part
    call peek_char
    cmp rax, 'e'
    je .frac_sci
    cmp rax, 'E'
    je .frac_sci
    movq [tok_fval], xmm0
    mov dword [tok_type], TOK_FLOAT_LIT
    jmp .num_finish

.num_done:
    test r9, r9
    jnz .num_finish
    ; Check for scientific notation on plain integer that becomes float (e.g. 1e4)
    ; For now just finalize as integer
    mov [tok_ival], r8
    mov dword [tok_type], TOK_INT_LIT

.num_finish:
    ; Calculate token string length
    mov rsi, [src_idx]
    mov rdi, [tok_str_ptr]
    mov rdx, [src_ptr]
    add rdx, rsi
    sub rdx, rdi
    mov [tok_str_len], rdx
    ret

section .rodata
    .float_ten dq 10.0
    .float_one dq 1.0

section .text
.identifier:
    ; Read identifier characters
.id_loop:
    call peek_char
    cmp rax, 'a'
    jl .id_not_lower
    cmp rax, 'z'
    jle .id_consume
.id_not_lower:
    cmp rax, 'A'
    jl .id_not_upper
    cmp rax, 'Z'
    jle .id_consume
.id_not_upper:
    cmp rax, '0'
    jl .id_not_digit
    cmp rax, '9'
    jle .id_consume
.id_not_digit:
    cmp rax, '_'
    je .id_consume
    jmp .id_done
.id_consume:
    call read_char
    jmp .id_loop

.id_done:
    ; Calculate token string length
    mov rsi, [src_idx]
    mov rdi, [tok_str_ptr]
    mov rdx, [src_ptr]
    add rdx, rsi
    sub rdx, rdi
    mov [tok_str_len], rdx
    
    ; Check if identifier is a keyword
    mov rdi, str_int
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_int
    mov dword [tok_type], TOK_TYPE
    mov qword [tok_ival], TYPE_INT
    ret
.not_int:
    mov rdi, str_float
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_float
    mov dword [tok_type], TOK_TYPE
    mov qword [tok_ival], TYPE_FLOAT
    ret
.not_float:
    mov rdi, str_bool
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_bool
    mov dword [tok_type], TOK_TYPE
    mov qword [tok_ival], TYPE_BOOL
    ret
.not_bool:
    mov rdi, str_str
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_str
    mov dword [tok_type], TOK_TYPE
    mov qword [tok_ival], TYPE_STR
    ret
.not_str:
    mov rdi, str_char
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_char
    mov dword [tok_type], TOK_TYPE
    mov qword [tok_ival], TYPE_CHAR
    ret
.not_char:
    mov rdi, str_byte
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_byte
    mov dword [tok_type], TOK_TYPE
    mov qword [tok_ival], TYPE_BYTE
    ret
.not_byte:
    mov rdi, str_const
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_const
    mov dword [tok_type], TOK_CONST
    ret
.not_const:
    mov rdi, str_type
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_type_kw
    mov dword [tok_type], TOK_TYPE_KW
    ret
.not_type_kw:
    mov rdi, str_struct
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_struct
    mov dword [tok_type], TOK_STRUCT
    ret
.not_struct:
    mov rdi, str_enum
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_enum
    mov dword [tok_type], TOK_ENUM
    ret
.not_enum:
    mov rdi, str_tup
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_tup
    mov dword [tok_type], TOK_TUP
    ret
.not_tup:
    mov rdi, str_seq
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_seq
    mov dword [tok_type], TOK_TYPE
    mov qword [tok_ival], 6 ; TYPE_SEQ
    ret
.not_seq:
    mov rdi, str_dict
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_dict
    mov dword [tok_type], TOK_TYPE
    mov qword [tok_ival], 7 ; TYPE_DICT
    ret
.not_dict:
    mov rdi, str_null
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_null
    mov dword [tok_type], TOK_NULL
    ret
.not_null:
    mov rdi, str_output
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_output
    mov dword [tok_type], TOK_OUTPUT
    ret
.not_output:
    mov rdi, str_true
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_true
    mov dword [tok_type], TOK_BOOL_LIT
    mov qword [tok_ival], 1
    ret
.not_true:
    mov rdi, str_false
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_false
    mov dword [tok_type], TOK_BOOL_LIT
    mov qword [tok_ival], -1
    ret
.not_false:
    mov rdi, str_neutral
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_neutral
    mov dword [tok_type], TOK_BOOL_LIT
    mov qword [tok_ival], 0
    ret
.not_neutral:
    mov rdi, str_and
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_and_kw
    mov dword [tok_type], TOK_BOOL_AND
    ret
.not_and_kw:
    mov rdi, str_or
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_or_kw
    mov dword [tok_type], TOK_BOOL_OR
    ret
.not_or_kw:
    mov rdi, str_not
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_not_kw
    mov dword [tok_type], TOK_BOOL_NOT
    ret
.not_not_kw:
    mov dword [tok_type], TOK_IDENT
    ret

; Operators definitions
.colon:
    mov dword [tok_type], TOK_COLON
    mov qword [tok_str_len], 1
    ret
.assign:
    mov dword [tok_type], TOK_ASSIGN
    mov qword [tok_str_len], 1
    ret
.plus:
    mov dword [tok_type], TOK_PLUS
    mov qword [tok_str_len], 1
    ret
.minus:
    mov dword [tok_type], TOK_MINUS
    mov qword [tok_str_len], 1
    ret
.star:
    mov dword [tok_type], TOK_STAR
    mov qword [tok_str_len], 1
    ret
.lparen:
    mov dword [tok_type], TOK_LPAREN
    mov qword [tok_str_len], 1
    ret
.rparen:
    mov dword [tok_type], TOK_RPAREN
    mov qword [tok_str_len], 1
    ret
.lbracket:
    mov dword [tok_type], TOK_LBRACKET
    mov qword [tok_str_len], 1
    ret
.rbracket:
    mov dword [tok_type], TOK_RBRACKET
    mov qword [tok_str_len], 1
    ret
.lbrace:
    mov dword [tok_type], TOK_LBRACE
    mov qword [tok_str_len], 1
    ret
.rbrace:
    mov dword [tok_type], TOK_RBRACE
    mov qword [tok_str_len], 1
    ret
.comma:
    mov dword [tok_type], TOK_COMMA
    mov qword [tok_str_len], 1
    ret
.dot:
    mov dword [tok_type], TOK_DOT
    mov qword [tok_str_len], 1
    ret

; BUG FIX (Bug 1): The '?' character was already consumed by the generic
; read_char at the operator dispatch block above.  The old code called
; read_char a second time, discarding the character that follows '?'.
; Fix: use peek_char / read_char only as needed for look-ahead.
.question:
    ; '?' already consumed above — just peek at the next character
    call peek_char
    cmp rax, '?'
    je .qq
    mov dword [tok_type], TOK_QUESTION
    mov qword [tok_str_len], 1
    ret
.qq:
    call read_char ; consume the second '?'
    mov dword [tok_type], TOK_QQ
    mov qword [tok_str_len], 2
    ret

.mod:
    mov dword [tok_type], TOK_MOD
    mov qword [tok_str_len], 1
    ret
.and:
    mov dword [tok_type], TOK_AND
    mov qword [tok_str_len], 1
    ret
.or:
    mov dword [tok_type], TOK_OR
    mov qword [tok_str_len], 1
    ret
.xor:
    mov dword [tok_type], TOK_XOR
    mov qword [tok_str_len], 1
    ret
