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
    str_arr     db "arr", 0
    str_null    db "null", 0
    str_output  db "output", 0
    str_prot    db "prot", 0
    str_return  db "return", 0
    str_true    db "true", 0
    str_false   db "false", 0
    str_neutral db "neutral", 0
    str_and     db "and", 0
    str_or      db "or", 0
    str_not     db "not", 0
    ; Control flow keywords
    str_if      db "if", 0
    str_elif    db "elif", 0
    str_else    db "else", 0
    str_for     db "for", 0
    str_while   db "while", 0
    str_each    db "each", 0
    str_repeat  db "repeat", 0
    str_in      db "in", 0
    str_step    db "step", 0
    str_stop    db "stop", 0
    str_skip    db "skip", 0
    str_pass    db "pass", 0
    str_is      db "is", 0
    str_switch  db "switch", 0
    str_raise   db "raise", 0
    str_swap    db "swap", 0
    str_len     db "len", 0
    str_scope   db "scope", 0
    str_assert  db "assert", 0

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
    line_start_idx  resq 1
    
    tok_type        resd 1
    tok_str_ptr     resq 1
    tok_str_len     resq 1
    tok_ival        resq 1
    tok_fval        resq 1
    
    pending_dedents resd 1
    at_line_start   resb 1

    ; String translation pool: each lexed string literal is appended here
    ; with escape sequences resolved.  tok_str_ptr is set to the pool slice.
    ; Using a pool (rather than a single buffer) ensures that multiple string
    ; literals in one source file all retain valid pointers through codegen.
    tok_str_pool     resb SRC_FILE_MAX  ; translation arena (≤ source size)
    tok_str_pool_idx resq 1             ; next free byte offset in pool

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
    mov qword [line_start_idx], 0
    mov dword [pending_dedents], 0
    mov byte [at_line_start], 1
    
    ; Reset indentation stack to just containing 0
    mov dword [indent_stack], 0
    mov dword [indent_stack_len], 1
    ; Reset string translation pool
    mov qword [tok_str_pool_idx], 0
    ret

; Helper to peek next character without advancing
; Returns rax = char, or -1 if EOF
peek_char:
    mov rsi, [src_ptr]
    mov rdi, [src_idx]
    cmp rdi, [src_len]
    jae .eof
    movzx rax, byte [rsi + rdi]
    ret
.eof:
    or rax, -1
    ret

; Helper to read current character and advance
; Returns rax = char, or -1 if EOF
read_char:
    mov rsi, [src_ptr]
    mov rdi, [src_idx]
    cmp rdi, [src_len]
    jae .eof
    movzx rax, byte [rsi + rdi]
    inc qword [src_idx]
    ret
.eof:
    or rax, -1
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
    cmp rax, -1
    je .done
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
    mov rdx, [src_idx]
    sub rdx, [line_start_idx]
    inc rdx
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
    call read_char            ; consume CR
    mov rax, [src_idx]
    mov [line_start_idx], rax
    inc qword [line_num]      ; count CR as line ending
    ; Check if followed by LF (CR+LF)
    call peek_char
    cmp rax, 10
    jne .no_lf
    call read_char            ; consume LF after CR (already counted)
    mov rax, [src_idx]
    mov [line_start_idx], rax
    jmp .lf_done
.no_cr:
    call peek_char
    cmp rax, 10
    jne .no_lf
    call read_char            ; consume lone LF
    mov rax, [src_idx]
    mov [line_start_idx], rax
    inc qword [line_num]
.no_lf:
.lf_done:
    ; If at EOF after consuming empty lines, return TOK_EOF (or pending dedents)
    ; Otherwise retry for the next non-empty line
    call peek_char
    test rax, rax
    js .eof
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
    cmp eax, 32
    jae .indent_overflow
    mov [indent_stack + eax * 4], r8d
    inc dword [indent_stack_len]
    mov dword [tok_type], TOK_INDENT
    ret

.indent_overflow:
    mov dword [tok_type], TOK_ERROR
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
    ; Set TOK_ERROR for indentation mismatch
    mov dword [tok_type], TOK_ERROR
    ret

.skip_indent_logic:
    call skip_spaces
    
    ; Check EOF
    call peek_char
    test rax, rax
    js .eof
    
    ; Save token start pointer
    mov rsi, [src_ptr]
    mov rdi, [src_idx]
    lea r11, [rsi + rdi]
    mov [tok_str_ptr], r11
    
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
    cmp rax, '<'
    je .lt
    cmp rax, '>'
    je .gt
    cmp rax, '!'
    je .bang
    cmp rax, '~'
    je .tilde

    ; Unknown token character — return TOK_ERROR
    mov dword [tok_type], TOK_ERROR
    ret

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
    mov rax, [src_idx]
    mov [line_start_idx], rax
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
    cmp rax, '='
    je .slash_eq
    ; Otherwise it's TOK_SLASH
    mov dword [tok_type], TOK_SLASH
    mov qword [tok_str_len], 1
    ret
.slash_eq:
    call read_char ; consume '='
    mov dword [tok_type], TOK_SLASH_EQ
    mov qword [tok_str_len], 2
    ret
.comment:
    call skip_comment
    jmp next_token

.string:
    ; Allocate a slice from the string translation pool.
    ; r11 = write base (pool_base + pool_idx); preserved across read_char calls
    ; because read_char only clobbers rax, rsi, rdi.
    call read_char ; consume opening '"'
    lea r11, [tok_str_pool]
    add r11, [tok_str_pool_idx]  ; r11 = &pool[pool_idx]
    mov [tok_str_ptr], r11       ; tok_str_ptr → this pool slice
    xor r8, r8                   ; length / write index
.str_loop:
    call read_char
    test rax, rax
    js .str_error          ; EOF inside string literal
    jz .str_error          ; embedded null byte not allowed
    cmp rax, '"'
    je .str_done
    cmp rax, '\'
    je .str_escape
    cmp rax, 10            ; bare LF inside string — store as LF byte
    je .str_newline
    mov [r11 + r8], al     ; store raw byte into pool
    inc r8
    jmp .str_loop

    ; -- Escape sequence handler --
    ; Reads the char after '\', translates it, writes one byte to pool.
    ; Exception: '\' + LF = line continuation (no output byte).
.str_escape:
    call read_char
    test rax, rax
    js .str_error
    cmp rax, 10            ; \<LF> = line continuation — no byte emitted
    je .str_escape_newline
    ; Translate common C-style escapes
    cmp rax, 'n'
    je .se_n
    cmp rax, 't'
    je .se_t
    cmp rax, 'r'
    je .se_r
    cmp rax, '0'
    je .se_0
    cmp rax, 'a'
    je .se_a
    cmp rax, 'b'
    je .se_b
    cmp rax, 'f'
    je .se_f
    cmp rax, 'v'
    je .se_v
    ; '\\', '\"', '\'' and unrecognised escapes: keep the literal char
    jmp .se_store
.se_n:  mov rax, 10  ; LF
    jmp .se_store
.se_t:  mov rax, 9   ; TAB
    jmp .se_store
.se_r:  mov rax, 13  ; CR
    jmp .se_store
.se_0:  xor rax, rax ; NUL
    jmp .se_store
.se_a:  mov rax, 7   ; BEL
    jmp .se_store
.se_b:  mov rax, 8   ; BS
    jmp .se_store
.se_f:  mov rax, 12  ; FF
    jmp .se_store
.se_v:  mov rax, 11  ; VT
.se_store:
    mov [r11 + r8], al
    inc r8
    jmp .str_loop

.str_escape_newline:            ; '\' + LF: line continuation
    mov rax, [src_idx]
    mov [line_start_idx], rax
    inc qword [line_num]
    ; No byte written — continue loop
    jmp .str_loop

.str_newline:                   ; bare LF inside string: store as LF
    mov rax, [src_idx]
    mov [line_start_idx], rax
    inc qword [line_num]
    mov byte [r11 + r8], 10
    inc r8
    jmp .str_loop

.str_done:
    mov [tok_str_len], r8
    ; Advance pool index so the next string gets a fresh slice
    add [tok_str_pool_idx], r8
    mov dword [tok_type], TOK_STR_LIT
    ret

.str_error:
    mov dword [tok_type], TOK_ERROR
    mov qword [tok_str_ptr], 0
    mov qword [tok_str_len], 0
    ret

.char_literal:
    call read_char ; consume opening quote
    mov rsi, [src_ptr]
    mov rdi, [src_idx]
    lea r11, [rsi + rdi]
    mov [tok_str_ptr], r11
    
    call read_char
    test rax, rax
    js .str_error
    ; Handle escape sequences in char literals
    cmp rax, '\'
    je .char_escape
    mov [tok_ival], rax ; store char ASCII/UTF-8 byte
    jmp .char_after
.char_escape:
    call read_char
    test rax, rax
    js .str_error
    ; Translate escape sequence — same table as string escapes
    cmp rax, 'n'
    je .ce_n
    cmp rax, 't'
    je .ce_t
    cmp rax, 'r'
    je .ce_r
    cmp rax, '0'
    je .ce_0
    cmp rax, 'a'
    je .ce_a
    cmp rax, 'b'
    je .ce_b
    cmp rax, 'f'
    je .ce_f
    cmp rax, 'v'
    je .ce_v
    ; '\\', '\'', '\"' and unrecognised: keep literal char
    jmp .ce_store
.ce_n:  mov rax, 10  ; LF
    jmp .ce_store
.ce_t:  mov rax, 9   ; TAB
    jmp .ce_store
.ce_r:  mov rax, 13  ; CR
    jmp .ce_store
.ce_0:  xor rax, rax ; NUL
    jmp .ce_store
.ce_a:  mov rax, 7   ; BEL
    jmp .ce_store
.ce_b:  mov rax, 8   ; BS
    jmp .ce_store
.ce_f:  mov rax, 12  ; FF
    jmp .ce_store
.ce_v:  mov rax, 11  ; VT
.ce_store:
    mov [tok_ival], rax
.char_after:
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
    movzx r11, byte [rsi + rdi]
    cmp r11b, 'x'
    je .hex_start
    cmp r11b, 'X'
    je .hex_start
    cmp r11b, 'b'
    je .bin_start
    cmp r11b, 'B'
    je .bin_start
    cmp r11b, 'o'
    je .oct_start
    cmp r11b, 'O'
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
    movzx r11, byte [rsi + rdi]
    cmp r11b, '.'
    je .num_done ; second dot — stop number parsing, dots lexed separately
    cmp r11b, '0'
    jl .num_done
    cmp r11b, '9'
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
    ; Check for scientific notation on plain integer (e.g. 1e4 → 10000.0)
    call peek_char
    cmp rax, 'e'
    je .int_to_sci
    cmp rax, 'E'
    je .int_to_sci
    mov [tok_ival], r8
    mov dword [tok_type], TOK_INT_LIT
    jmp .num_finish
.int_to_sci:
    ; Promote integer to float and enter scientific notation handler
    cvtsi2sd xmm0, r8
    movq xmm1, qword [.float_ten]

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
    mov qword [tok_ival], TYPE_SEQ
    ret
.not_seq:
    mov rdi, str_dict
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_dict
    mov dword [tok_type], TOK_TYPE
    mov qword [tok_ival], TYPE_DICT
    ret
.not_dict:
    mov rdi, str_arr
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_arr
    mov dword [tok_type], TOK_TYPE
    mov qword [tok_ival], TYPE_ARR
    ret
.not_arr:
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
    mov rdi, str_prot
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_prot
    mov dword [tok_type], TOK_PROT
    ret
.not_prot:
    mov rdi, str_return
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_return
    mov dword [tok_type], TOK_RETURN
    ret
.not_return:
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
    ; Control flow keywords
    mov rdi, str_if
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_if_kw
    mov dword [tok_type], TOK_IF
    ret
.not_if_kw:
    mov rdi, str_elif
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_elif_kw
    mov dword [tok_type], TOK_ELIF
    ret
.not_elif_kw:
    mov rdi, str_else
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_else_kw
    mov dword [tok_type], TOK_ELSE
    ret
.not_else_kw:
    mov rdi, str_for
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_for_kw
    mov dword [tok_type], TOK_FOR
    ret
.not_for_kw:
    mov rdi, str_while
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_while_kw
    mov dword [tok_type], TOK_WHILE
    ret
.not_while_kw:
    mov rdi, str_each
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_each_kw
    mov dword [tok_type], TOK_EACH
    ret
.not_each_kw:
    mov rdi, str_repeat
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_repeat_kw
    mov dword [tok_type], TOK_REPEAT
    ret
.not_repeat_kw:
    mov rdi, str_in
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_in_kw
    mov dword [tok_type], TOK_IN
    ret
.not_in_kw:
    mov rdi, str_step
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_step_kw
    mov dword [tok_type], TOK_STEP
    ret
.not_step_kw:
    mov rdi, str_stop
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_stop_kw
    mov dword [tok_type], TOK_STOP
    ret
.not_stop_kw:
    mov rdi, str_skip
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_skip_kw
    mov dword [tok_type], TOK_SKIP
    ret
.not_skip_kw:
    mov rdi, str_pass
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_pass_kw
    mov dword [tok_type], TOK_PASS
    ret
.not_pass_kw:
    mov rdi, str_is
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_is_kw
    ; Check for 'is not' (bounds-checked)
    mov rdi, [src_idx]
    add rdi, 4
    cmp rdi, [src_len]
    ja .is_single           ; not enough room for " not"
    mov rdi, [src_ptr]
    mov rsi, [src_idx]
    add rsi, rdi
    cmp byte [rsi], ' '
    jne .is_single
    cmp byte [rsi + 1], 'n'
    jne .is_single
    cmp byte [rsi + 2], 'o'
    jne .is_single
    cmp byte [rsi + 3], 't'
    jne .is_single
    ; Word-boundary check: the char at rsi+4 must NOT be an identifier char.
    ; Without this, 'is nothing' / 'is notify' / 'is not_x' would all match
    ; 'is not' and leave a stale suffix in the token stream.
    mov rdi, [src_idx]
    add rdi, 5                  ; index of char immediately after " not"
    cmp rdi, [src_len]
    jae .is_not_match           ; at/past EOF — word boundary is guaranteed
    movzx ecx, byte [rsi + 4]  ; peek at char after 'not'
    cmp cl, 'a'
    jl .is_not_wbc1
    cmp cl, 'z'
    jle .is_single              ; lowercase letter — not a boundary
.is_not_wbc1:
    cmp cl, 'A'
    jl .is_not_wbc2
    cmp cl, 'Z'
    jle .is_single              ; uppercase letter — not a boundary
.is_not_wbc2:
    cmp cl, '0'
    jl .is_not_wbc3
    cmp cl, '9'
    jle .is_single              ; digit — not a boundary
.is_not_wbc3:
    cmp cl, '_'
    je .is_single               ; underscore — not a boundary
.is_not_match:
    ; 'is not' — consume the space and 'not'
    add qword [src_idx], 4
    mov dword [tok_type], TOK_IS_NOT
    add qword [tok_str_len], 4
    ret
.is_single:
    mov dword [tok_type], TOK_IS
    ret
.not_is_kw:
    mov rdi, str_switch
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_switch_kw
    mov dword [tok_type], TOK_SWITCH
    ret
.not_switch_kw:
    mov rdi, str_raise
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_raise_kw
    mov dword [tok_type], TOK_RAISE
    ret
.not_raise_kw:
    mov rdi, str_swap
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_swap_kw
    mov dword [tok_type], TOK_SWAP
    ret
.not_swap_kw:
    mov rdi, str_len
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_len_kw
    mov dword [tok_type], TOK_LEN
    ret
.not_len_kw:
    mov rdi, str_scope
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_scope_kw
    mov dword [tok_type], TOK_SCOPE
    ret
.not_scope_kw:
    mov rdi, str_assert
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call strcmp_len
    test rax, rax
    jz .not_assert_kw
    mov dword [tok_type], TOK_ASSERT
    ret
.not_assert_kw:
    mov dword [tok_type], TOK_IDENT
    ret

; Operators definitions
.colon:
    mov dword [tok_type], TOK_COLON
    mov qword [tok_str_len], 1
    ret
.assign:
    ; '=' could be '==' (eq)
    call peek_char
    cmp rax, '='
    je .eq
    mov dword [tok_type], TOK_ASSIGN
    mov qword [tok_str_len], 1
    ret
.eq:
    call read_char ; consume second '='
    mov dword [tok_type], TOK_EQ
    mov qword [tok_str_len], 2
    ret
.plus:
    ; '+' could be '++' (plusplus) or '+=' (plus_eq)
    call peek_char
    cmp rax, '+'
    je .plusplus
    cmp rax, '='
    je .plus_eq
    mov dword [tok_type], TOK_PLUS
    mov qword [tok_str_len], 1
    ret
.plusplus:
    call read_char ; consume second '+'
    mov dword [tok_type], TOK_PLUSPLUS
    mov qword [tok_str_len], 2
    ret
.plus_eq:
    call read_char ; consume '='
    mov dword [tok_type], TOK_PLUS_EQ
    mov qword [tok_str_len], 2
    ret
.minus:
    ; '-' could be '--' (minusminus) or '->' (arrow) or '-=' (minus_eq)
    call peek_char
    cmp rax, '-'
    je .minusminus
    cmp rax, '>'
    je .arrow
    cmp rax, '='
    je .minus_eq
    mov dword [tok_type], TOK_MINUS
    mov qword [tok_str_len], 1
    ret
.minusminus:
    call read_char ; consume second '-'
    mov dword [tok_type], TOK_MINUSMINUS
    mov qword [tok_str_len], 2
    ret
.arrow:
    call read_char ; consume '>'
    mov dword [tok_type], TOK_ARROW
    mov qword [tok_str_len], 2
    ret
.minus_eq:
    call read_char ; consume '='
    mov dword [tok_type], TOK_MINUS_EQ
    mov qword [tok_str_len], 2
    ret
.star:
    ; '*' could be '*=' (star_eq)
    call peek_char
    cmp rax, '='
    je .star_eq
    mov dword [tok_type], TOK_STAR
    mov qword [tok_str_len], 1
    ret
.star_eq:
    call read_char ; consume '='
    mov dword [tok_type], TOK_STAR_EQ
    mov qword [tok_str_len], 2
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
    ; '.' could be '..' (range)
    call peek_char
    cmp rax, '.'
    je .dotdot
    mov dword [tok_type], TOK_DOT
    mov qword [tok_str_len], 1
    ret
.dotdot:
    call read_char ; consume second '.'
    mov dword [tok_type], TOK_DOTDOT
    mov qword [tok_str_len], 2
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
    ; '%' could be '%=' (mod_eq)
    call peek_char
    cmp rax, '='
    je .mod_eq
    mov dword [tok_type], TOK_MOD
    mov qword [tok_str_len], 1
    ret
.mod_eq:
    call read_char ; consume '='
    mov dword [tok_type], TOK_MOD_EQ
    mov qword [tok_str_len], 2
    ret
.and:
    ; '&' could be '&=' (and_eq)
    call peek_char
    cmp rax, '='
    je .and_eq
    mov dword [tok_type], TOK_AND
    mov qword [tok_str_len], 1
    ret
.and_eq:
    call read_char ; consume '='
    mov dword [tok_type], TOK_AND_EQ
    mov qword [tok_str_len], 2
    ret
.or:
    ; '|' could be '|=' (or_eq)
    call peek_char
    cmp rax, '='
    je .or_eq
    mov dword [tok_type], TOK_OR
    mov qword [tok_str_len], 1
    ret
.or_eq:
    call read_char ; consume '='
    mov dword [tok_type], TOK_OR_EQ
    mov qword [tok_str_len], 2
    ret
.xor:
    ; '^' could be '^=' (xor_eq)
    call peek_char
    cmp rax, '='
    je .xor_eq
    mov dword [tok_type], TOK_XOR
    mov qword [tok_str_len], 1
    ret
.xor_eq:
    call read_char ; consume '='
    mov dword [tok_type], TOK_XOR_EQ
    mov qword [tok_str_len], 2
    ret

.lt:
    ; '<' could be '<=' (le) or '<<' (lshift)
    call peek_char
    cmp rax, '='
    je .le
    cmp rax, '<'
    je .lshift
    mov dword [tok_type], TOK_LT
    mov qword [tok_str_len], 1
    ret
.le:
    call read_char ; consume '='
    mov dword [tok_type], TOK_LE
    mov qword [tok_str_len], 2
    ret
.lshift:
    call read_char ; consume second '<'
    ; '<<' could be '<<=' (lshift_eq)
    call peek_char
    cmp rax, '='
    je .lshift_eq
    mov dword [tok_type], TOK_LSHIFT
    mov qword [tok_str_len], 2
    ret
.lshift_eq:
    call read_char ; consume '='
    mov dword [tok_type], TOK_LSHIFT_EQ
    mov qword [tok_str_len], 3
    ret

.gt:
    ; '>' could be '>=' (ge) or '>>' (rshift)
    call peek_char
    cmp rax, '='
    je .ge
    cmp rax, '>'
    je .rshift
    mov dword [tok_type], TOK_GT
    mov qword [tok_str_len], 1
    ret
.ge:
    call read_char ; consume '='
    mov dword [tok_type], TOK_GE
    mov qword [tok_str_len], 2
    ret
.rshift:
    call read_char ; consume second '>'
    ; '>>' could be '>>=' (rshift_eq)
    call peek_char
    cmp rax, '='
    je .rshift_eq
    mov dword [tok_type], TOK_RSHIFT
    mov qword [tok_str_len], 2
    ret
.rshift_eq:
    call read_char ; consume '='
    mov dword [tok_type], TOK_RSHIFT_EQ
    mov qword [tok_str_len], 3
    ret

.bang:
    ; '!' could be '!=' (ne)
    call peek_char
    cmp rax, '='
    je .ne
    mov dword [tok_type], TOK_ERROR ; bare '!' not valid
    mov qword [tok_str_len], 1
    ret
.ne:
    call read_char ; consume '='
    mov dword [tok_type], TOK_NE
    mov qword [tok_str_len], 2
    ret

.tilde:
    mov dword [tok_type], TOK_TILDE
    mov qword [tok_str_len], 1
    ret
