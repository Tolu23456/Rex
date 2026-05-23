; parser.asm - Recursive Descent Parser for Rex

%include "include/common.inc"
%include "include/tokens.inc"

section .data
    err_syntax db "Syntax Error", 10, 0
    err_undef  db "Error: Undefined variable", 10, 0

section .bss
    curr_tok_type resq 1
    curr_tok_val  resq 1
    sym_table     resb 4000
    sym_count     resq 1
    stack_offset  resq 1

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
    extern rex_emit_jne
    extern rex_emit_je
    extern rex_emit_label
    extern rex_patch_jump
    extern rex_get_code_ptr
    extern rex_finish
    extern rex_print_int
    extern rex_print_newline
    extern rex_set_mm_gc
    extern rex_get_mm_gc
    extern rex_get_random_bool
    extern rex_semant_init
    extern rex_enter_scope
    extern rex_exit_scope
    extern rex_check_escape

rex_parse:
    call rex_lex_init
    call rex_codegen_init
    call rex_semant_init
    mov qword [sym_count], 0
    mov qword [stack_offset], 8
    mov rdi, 0x55
    call rex_emit_byte
    mov rdi, 0x48
    call rex_emit_byte
    mov rdi, 0x89
    call rex_emit_byte
    mov rdi, 0xE5
    call rex_emit_byte
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
    mov rdi, 0x48
    call rex_emit_byte
    mov rdi, 0x89
    call rex_emit_byte
    mov rdi, 0xEC
    call rex_emit_byte
    mov rdi, 0x5D
    call rex_emit_byte
    mov rdi, 60
    call rex_emit_mov_rax_imm
    mov rdi, 0x48
    call rex_emit_byte
    mov rdi, 0x31
    call rex_emit_byte
    mov rdi, 0xFF
    call rex_emit_byte
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
    cmp rax, TOK_INT
    je parse_decl
    cmp rax, TOK_IF
    je parse_if
    cmp rax, TOK_USE
    je parse_use
    call advance
    ret

parse_decl:
    call advance
    mov rsi, [curr_tok_val]
    call find_symbol
    test rax, rax
    jnz .done
    mov rax, [sym_count]
    imul rax, 40
    lea rbx, [sym_table + rax]
    mov rsi, [curr_tok_val]
    mov rdi, rbx
    mov rcx, 32
.copy:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jnz .copy
    mov rdx, [stack_offset]
    mov [rbx + 32], rdx
    add qword [stack_offset], 8
    inc qword [sym_count]
    mov rdi, 0x48
    call rex_emit_byte
    mov rdi, 0x83
    call rex_emit_byte
    mov rdi, 0xEC
    call rex_emit_byte
    mov rdi, 0x08
    call rex_emit_byte
.done:
    call advance
    ret

parse_assignment:
    call advance
    mov rsi, [curr_tok_val]
    call find_symbol
    push rax
    call advance
    call advance
    call parse_expression
    pop rdx
    mov rdi, 0x48
    call rex_emit_byte
    mov rdi, 0x89
    call rex_emit_byte
    mov rdi, 0x45
    call rex_emit_byte
    neg rdx
    mov rdi, rdx
    call rex_emit_byte
    ret

parse_if:
    call advance
    mov rax, [curr_tok_type]
    cmp rax, TOK_UNKNOWN
    je .unknown
    call parse_expression
    jmp .after_cond
.unknown:
    mov rdi, rex_get_random_bool
    call rex_emit_mov_rax_imm
    call rex_emit_call_rax
    call advance
.after_cond:
    mov rdi, 0x48
    call rex_emit_byte
    mov rdi, 0x85
    call rex_emit_byte
    mov rdi, 0xC0
    call rex_emit_byte
    mov rdi, 0x0F
    call rex_emit_byte
    mov rdi, 0x84
    call rex_emit_byte
    call rex_get_code_ptr
    mov r12, rax
    mov rdi, 0
    call rex_emit_byte
    call rex_emit_byte
    call rex_emit_byte
    call rex_emit_byte
    call advance
    call advance
    call rex_enter_scope
.loop:
    mov rax, [curr_tok_type]
    cmp rax, TOK_DEDENT
    je .block_done
    cmp rax, TOK_EOF
    je .block_done
    call parse_statement
    jmp .loop
.block_done:
    call rex_exit_scope
    call advance
    mov rdi, r12
    call rex_emit_label
    mov rsi, rax
    call rex_patch_jump
    ret

parse_use:
    call advance
    call advance
    mov r13, [curr_tok_val]
    call advance
    call advance
    mov r14, [curr_tok_val]
    call advance
    call advance
    call advance
    call rex_enter_scope
    mov rdi, rex_get_mm_gc
    call rex_emit_mov_rax_imm
    call rex_emit_call_rax
    mov rdi, 0x50
    call rex_emit_byte
    mov rdi, r13
    call rex_emit_mov_rax_imm
    mov rdi, 0x48
    call rex_emit_byte
    mov rdi, 0x89
    call rex_emit_byte
    mov rdi, 0xC7
    call rex_emit_byte
    mov rdi, r14
    call rex_emit_mov_rax_imm
    mov rdi, 0x48
    call rex_emit_byte
    mov rdi, 0x89
    call rex_emit_byte
    mov rdi, 0xC6
    call rex_emit_byte
    mov rdi, rex_set_mm_gc
    call rex_emit_mov_rax_imm
    call rex_emit_call_rax
.loop:
    mov rax, [curr_tok_type]
    cmp rax, TOK_DEDENT
    je .done
    cmp rax, TOK_EOF
    je .done
    call parse_statement
    jmp .loop
.done:
    call rex_exit_scope
    call advance
    mov rdi, 0x5F
    call rex_emit_byte
    mov rdi, 0x48
    call rex_emit_byte
    mov rdi, 0x89
    call rex_emit_byte
    mov rdi, 0xFE
    call rex_emit_byte
    mov rdi, 0x48
    call rex_emit_byte
    mov rdi, 0xC1
    call rex_emit_byte
    mov rdi, 0xEE
    call rex_emit_byte
    mov rdi, 0x08
    call rex_emit_byte
    mov rdi, rex_set_mm_gc
    call rex_emit_mov_rax_imm
    call rex_emit_call_rax
    ret

find_symbol:
    mov rcx, [sym_count]
    xor rdx, rdx
.loop:
    test rcx, rcx
    jz .not_found
    mov rax, rdx
    imul rax, 40
    lea rbx, [sym_table + rax]
    push rsi
    push rbx
    push rcx
    push rdx
    mov rdi, rbx
    call str_equal
    pop rdx
    pop rcx
    pop rbx
    pop rsi
    test rax, rax
    jnz .found
    inc rdx
    dec rcx
    jmp .loop
.found:
    mov rax, [rbx + 32]
    ret
.not_found:
    xor rax, rax
    ret

str_equal:
.loop:
    mov al, [rsi]
    mov bl, [rdi]
    cmp al, bl
    jne .no
    test al, al
    jz .yes
    inc rsi
    inc rdi
    jmp .loop
.no:
    xor rax, rax
    ret
.yes:
    mov rax, 1
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

parse_expression:
    call parse_term
.loop:
    mov rax, [curr_tok_type]
    cmp rax, TOK_PLUS
    jne .done
    call rex_emit_push_rax
    call advance
    call parse_term
    call rex_emit_pop_rcx
    call rex_emit_add_rax_rcx
    jmp .loop
.done:
    ret

parse_term:
    call parse_factor
    ret

parse_factor:
    mov rax, [curr_tok_type]
    cmp rax, TOK_LIT_INT
    je .int
    cmp rax, TOK_IDENT
    je .ident
    cmp rax, TOK_LIT_CPX
    je .complex
    call advance
    ret
.int:
    mov rdi, [curr_tok_val]
    call rex_emit_mov_rax_imm
    call advance
    ret
.ident:
    mov rsi, [curr_tok_val]
    call find_symbol
    mov rdi, 0x48
    call rex_emit_byte
    mov rdi, 0x8B
    call rex_emit_byte
    mov rdi, 0x45
    call rex_emit_byte
    neg rax
    mov rdi, rax
    call rex_emit_byte
    call advance
    ret
.complex:
    mov rdi, [curr_tok_val]
    call rex_emit_mov_rax_imm
    call advance
    ret
