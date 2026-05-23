; parser.asm - Recursive Descent Parser for Rex

%include "src/include/common.inc"
%include "src/include/tokens.inc"

section .data
    err_syntax db "Syntax Error", 10, 0

section .bss
    curr_tok_type resq 1
    curr_tok_val  resq 1

section .text
    global rex_parse
    extern rex_lex_init
    extern rex_lex_next
    extern rex_codegen_init
    extern rex_emit_byte
    extern rex_emit_dq
    extern rex_emit_mov_rax_imm
    extern rex_emit_push_rax
    extern rex_emit_pop_rax
    extern rex_emit_pop_rcx
    extern rex_emit_add_rax_rcx
    extern rex_emit_sub_rax_rcx
    extern rex_emit_mul_rcx
    extern rex_emit_syscall
    extern rex_emit_call_rax
    extern rex_emit_cmp_rax_rcx
    extern rex_emit_jmp
    extern rex_emit_je
    extern rex_finish

    extern rex_print_int
    extern rex_print_newline

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
    mov rdi, 60
    call rex_emit_mov_rax_imm
    mov dil, 0x48 \ call rex_emit_byte
    mov dil, 0x31 \ call rex_emit_byte
    mov dil, 0xFF \ call rex_emit_byte
    call rex_emit_syscall

    call rex_finish
    xor rax, rax
    ret

advance:
    call rex_lex_next
    mov [curr_tok_type], rax
    mov [curr_tok_val], rdx
    ret

parse_statement:
    mov rax, [curr_tok_type]
    cmp rax, TOK_OUTPUT
    je parse_output
    cmp rax, TOK_COLON
    je parse_assignment
    cmp rax, TOK_IF
    je parse_if
    cmp rax, TOK_FOR
    je parse_for
    cmp rax, TOK_PROT
    je parse_prot
    call advance
    ret

parse_output:
    call advance
    call parse_expression
    mov rdi, rex_print_int
    call rex_emit_mov_rax_imm
    call rex_emit_call_rax
    mov rdi, rex_print_newline
    call rex_emit_mov_rax_imm
    call rex_emit_call_rax
    ret

parse_assignment:
    call advance ; :
    ; handle variable storage logic (simplified for now)
    call advance
    call advance ; =
    call parse_expression
    ret

parse_if:
    call advance ; if
    call parse_expression
    call advance ; :
    call advance ; INDENT
.loop:
    mov rax, [curr_tok_type]
    cmp rax, TOK_DEDENT
    je .done
    call parse_statement
    jmp .loop
.done:
    call advance ; DEDENT
    ret

parse_for:
    call advance ; for
    call advance ; :
    call advance ; ident
    call advance ; in
    call parse_expression ; range
    call advance ; :
    call advance ; INDENT
.loop:
    mov rax, [curr_tok_type]
    cmp rax, TOK_DEDENT
    je .done
    call parse_statement
    jmp .loop
.done:
    call advance ; DEDENT
    ret

parse_prot:
    call advance ; prot
    call advance ; name
    call advance ; (
    call advance ; args
    call advance ; )
    call advance ; ->
    call advance ; type
    call advance ; :
    call advance ; INDENT
.loop:
    mov rax, [curr_tok_type]
    cmp rax, TOK_DEDENT
    je .done
    call parse_statement
    jmp .loop
.done:
    call advance ; DEDENT
    ret

parse_expression:
    call parse_term
.exp_loop:
    mov rax, [curr_tok_type]
    cmp rax, TOK_PLUS
    je .handle_plus
    cmp rax, TOK_MINUS
    je .handle_minus
    ret
.handle_plus:
    call rex_emit_push_rax
    call advance
    call parse_term
    call rex_emit_pop_rcx
    call rex_emit_add_rax_rcx
    jmp .exp_loop
.handle_minus:
    call rex_emit_push_rax
    call advance
    call parse_term
    call rex_emit_pop_rcx
    mov dil, 0x48 \ call rex_emit_byte
    mov dil, 0x29 \ call rex_emit_byte
    mov dil, 0xC1 \ call rex_emit_byte
    mov dil, 0x48 \ call rex_emit_byte
    mov dil, 0x89 \ call rex_emit_byte
    mov dil, 0xC8 \ call rex_emit_byte
    jmp .exp_loop

parse_term:
    call parse_factor
.term_loop:
    mov rax, [curr_tok_type]
    cmp rax, TOK_MUL
    je .handle_mul
    ret
.handle_mul:
    call rex_emit_push_rax
    call advance
    call parse_factor
    call rex_emit_pop_rcx
    call rex_emit_mul_rcx
    jmp .term_loop

parse_factor:
    mov rax, [curr_tok_type]
    cmp rax, TOK_LIT_INT
    je .handle_int
    call advance
    ret
.handle_int:
    mov rdi, [curr_tok_val]
    call rex_emit_mov_rax_imm
    call advance
    ret
