; parser.asm - Recursive Descent Parser for Rex

%include "src/include/common.inc"
%include "src/include/tokens.inc"

section .data
    err_syntax db "Syntax Error: ", 0
    err_newline db 10, 0

section .bss
    curr_tok_type resq 1
    curr_tok_val  resq 1

section .text
    global rex_parse
    extern rex_lex_init
    extern rex_lex_next
    extern rex_codegen_init
    extern rex_emit_byte
    extern rex_finish

; Main parse function
; RDI = source buffer, RSI = length
rex_parse:
    call rex_lex_init
    call rex_codegen_init
    call advance

.parse_loop:
    mov rax, [curr_tok_type]
    cmp rax, TOK_EOF
    je .success
    cmp rax, TOK_NEWLINE
    je .skip_newline

    call parse_statement
    jmp .parse_loop

.skip_newline:
    call advance
    jmp .parse_loop

.success:
    ; Emit exit syscall at the end of output binary
    ; mov rax, 60 (exit)
    mov rdi, 0xB8480000003C
    ; Wait, let's emit bytes manually for clarity
    mov dil, 0x48 ; mov rax, 60
    call rex_emit_byte
    mov dil, 0xC7
    call rex_emit_byte
    mov dil, 0xC0
    call rex_emit_byte
    mov dil, 0x3C
    call rex_emit_byte
    mov dil, 0x00
    call rex_emit_byte
    mov dil, 0x00
    call rex_emit_byte
    mov dil, 0x00
    call rex_emit_byte

    ; xor rdi, rdi
    mov dil, 0x48
    call rex_emit_byte
    mov dil, 0x31
    call rex_emit_byte
    mov dil, 0xFF
    call rex_emit_byte

    ; syscall
    mov dil, 0x0F
    call rex_emit_byte
    mov dil, 0x05
    call rex_emit_byte

    call rex_finish
    xor rax, rax
    ret

; Advance to the next token
advance:
    call rex_lex_next
    mov [curr_tok_type], rax
    mov [curr_tok_val], rdx
    ret

; Parse a single statement
parse_statement:
    mov rax, [curr_tok_type]

    cmp rax, TOK_OUTPUT
    je parse_output

    cmp rax, TOK_COLON
    je parse_assignment

    cmp rax, TOK_PROT
    je parse_prot

    cmp rax, TOK_IF
    je parse_if

    cmp rax, TOK_FOR
    je parse_for

    cmp rax, TOK_USE
    je parse_use

    ; Variable declarations
    cmp rax, TOK_INT
    je parse_decl
    cmp rax, TOK_FLOAT
    je parse_decl
    cmp rax, TOK_STR
    je parse_decl

    ; Unknown statement
    call advance
    ret

; parse :age = 56
parse_assignment:
    call advance ; skip :
    ; expect IDENT
    call advance ; skip ident
    ; expect =
    call advance ; skip =
    ; expect expression
    call parse_expression
    ret

; parse output x
parse_output:
    call advance ; skip output
    call parse_expression

    ; Generate code to print the result (assumed to be in RAX)
    ; For now, assume it's an integer and generate a write syscall stub
    ; mov rdi, rax
    ; call rex_print_int (stub)
    ret

; parse prot name(args) -> type:
parse_prot:
    call advance ; skip prot
    call advance ; skip name
    ; expect (
    call advance ; skip (
    ; ... handle args ...
    ; expect )
    call advance ; skip )
    ; expect ->
    call advance ; skip ->
    call advance ; skip return type
    ; expect :
    call advance ; skip :
    ; expect INDENT
    cmp qword [curr_tok_type], TOK_INDENT
    jne .error
    call advance

    ; parse body until DEDENT
.body_loop:
    mov rax, [curr_tok_type]
    cmp rax, TOK_DEDENT
    je .body_done
    cmp rax, TOK_EOF
    je .error
    call parse_statement
    jmp .body_loop
.body_done:
    call advance ; skip DEDENT
    ret
.error:
    ; Handle error
    ret

parse_if:
    call advance ; skip if
    call parse_expression
    ; expect :
    call advance ; skip :
    ; expect INDENT
    call advance ; skip INDENT
    ; ... body ...
    ret

parse_for:
    call advance ; skip for
    ; expect :ident
    call advance ; skip :
    call advance ; skip ident
    ; expect in
    call advance ; skip in
    call parse_expression ; range
    ; expect :
    call advance ; skip :
    ; expect INDENT
    ret

parse_use:
    call advance ; skip use
    ; expect mm
    call advance
    call advance ; skip mm number
    ; expect gc
    call advance
    call advance ; skip gc number
    ; expect :
    call advance
    ; expect INDENT
    ret

parse_decl:
    call advance ; skip type
    call advance ; skip name
    ret

parse_expression:
    ; Basic expression parser (stub)
    call advance
    ret
