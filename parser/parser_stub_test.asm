; Rex Parser Implementation
; written in x86-64 NASM assembly

%include "include/rex_defs.inc"
%include "include/rex_ir.inc"

section .data
    current_token   dd 0

    ; Error messages
    err_syntax      db "Syntax Error: Unexpected token", 0
    err_dup_decl    db "Compile Error: Duplicate variable declaration in same scope", 0
    err_undef       db "Compile Error: Undefined variable", 0
    err_uninit      db "Compile Error: Variable read before initialization", 0
    err_type_mismatch db "Compile Error: Type mismatch", 0
    err_sigil_req   db "Compile Error: Mutation requires ':' sigil before variable name", 0
    err_newline_req db "Syntax Error: Expected newline or EOF at end of statement", 0
    ; Bug 5 fix: distinct message for symbol-table-full (was reusing err_dup_decl)
    err_sym_full    db "Compile Error: Symbol table full (too many variables)", 0
    err_unknown_method db "Compile Error: Unknown method for this type", 0

    ; Method name strings (used by parse_postfix dispatch)
    str_abs           db "abs", 0
    str_min           db "min", 0
    str_max           db "max", 0
    str_clamp         db "clamp", 0
    str_signum        db "signum", 0
    str_is_zero       db "is_zero", 0
    str_is_positive   db "is_positive", 0
    str_is_negative   db "is_negative", 0
    str_is_even       db "is_even", 0
    str_is_odd        db "is_odd", 0
    str_popcount      db "popcount", 0
    str_leading_zeros db "leading_zeros", 0
    str_trailing_zeros db "trailing_zeros", 0
    str_bit_len       db "bit_len", 0
    str_swap_bytes    db "swap_bytes", 0
    str_rotate_left   db "rotate_left", 0
    str_rotate_right  db "rotate_right", 0
    str_ceil          db "ceil", 0
    str_floor         db "floor", 0
    str_round         db "round", 0
    str_trunc         db "trunc", 0
    str_fract         db "fract", 0
    str_sqrt          db "sqrt", 0
    str_recip         db "recip", 0
    str_is_true       db "is_true", 0
    str_is_false      db "is_false", 0
    str_is_neutral    db "is_neutral", 0
    str_is_decided    db "is_decided", 0
    str_flip          db "flip", 0
    str_to_int        db "to_int", 0
    str_and_m         db "and", 0
    str_or_m          db "or", 0
    str_is_alpha      db "is_alpha", 0
    str_is_digit_s    db "is_digit", 0
    str_is_alnum      db "is_alnum", 0
    str_is_whitespace db "is_whitespace", 0
    str_is_upper      db "is_upper", 0
    str_is_lower      db "is_lower", 0
    str_is_punct      db "is_punct", 0
    str_is_printable  db "is_printable", 0
    str_is_ascii      db "is_ascii", 0
    str_to_upper      db "to_upper", 0
    str_to_lower      db "to_lower", 0
    str_to_byte       db "to_byte", 0
    str_to_char       db "to_char", 0
    str_to_digit      db "to_digit", 0
    str_swap_nibbles  db "swap_nibbles", 0
    str_is_nan        db "is_nan", 0
    str_is_infinite   db "is_infinite", 0
    str_is_finite     db "is_finite", 0
    float_pp_one      dq 0x3FF0000000000000

section .bss
    ; For storing name string buffers during parsing
    ident_buf       resb 32
    ident_len       resq 1
    ; For storing method name during parse_postfix
    method_buf      resb 32
    method_len      resq 1

section .text
    global parse_program
    
    extern next_token
    extern get_error_loc
    extern tok_type
    extern tok_str_ptr
    extern tok_str_len
    extern tok_ival
    extern tok_fval

    extern sym_add
    extern sym_lookup
    extern sym_get_type
    extern sym_is_init
    extern sym_set_init
    extern sym_set_mutable
    extern sym_get_offset

    extern alloc_vreg
    extern emit_ir

; Advance to the next token
advance:
    push rax
    call next_token
    mov eax, [tok_type]
    mov [current_token], eax
    pop rax
    ret

; Expect a token type, otherwise error
expect:
    cmp [current_token], edi
    jne .error
    call advance
    ret
.error:
    mov rdi, err_syntax
    jmp compile_error

; Main entry point
parse_program:
    ; Initialize lexer first
    call advance
    
.loop:
    mov eax, [current_token]
    cmp eax, TOK_EOF
    je .done
    
    ; Skip newlines at top level
    cmp eax, TOK_NEWLINE
    je .skip_newline
    
    call parse_stmt
    
    ; Statement must end with newline or EOF
    mov eax, [current_token]
    cmp eax, TOK_NEWLINE
    je .consume_newline
    cmp eax, TOK_EOF
    je .loop
    
    ; If not newline or EOF, it's an error
    mov rdi, err_newline_req
    jmp compile_error

.consume_newline:
    call advance
    jmp .loop
    
.skip_newline:
    call advance
    jmp .loop

.done:
    ; Emit halt
    mov rdi, IR_HALT
    xor rsi, rsi
    xor rdx, rdx
    xor rcx, rcx
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir
    ret

; Parse Statement
parse_stmt:
    mov eax, [current_token]
    cmp eax, TOK_TYPE
    je .explicit_decl
    
    cmp eax, TOK_COLON
    je .mutation
    
    cmp eax, TOK_IDENT
    je .ident_stmt
    
    cmp eax, TOK_OUTPUT
    je .output_stmt
    
    cmp eax, TOK_CONST
    je .const_decl
    
    cmp eax, TOK_STRUCT
    je .struct_decl
    
    cmp eax, TOK_ENUM
    je .enum_decl
    
    ; Unknown statement
    mov rdi, err_syntax
    jmp compile_error

.const_decl:
    call advance ; consume const
    mov eax, [current_token]
    cmp eax, TOK_IDENT
    jne .expected_ident
    
    call save_ident
    call advance
    
    mov edi, TOK_ASSIGN
    call expect
    
    call parse_expr
    mov r12, rdx ; type
    
    push rax
    mov rdi, ident_buf
    mov rsi, [ident_len]
    call determine_scope
    mov rcx, rax
    mov rdx, r12
    mov rdi, ident_buf
    mov rsi, [ident_len]
    call sym_add
    cmp rax, -2
    je .dup_error
    cmp rax, -1
    je .full_error
    
    mov r14, rax
    
    ; Emit store
    mov rdi, r14
    call sym_get_offset
    mov r9, rax
    
    pop rcx
    mov rdi, IR_STORE_VAR
    mov rsi, r12
    xor rdx, rdx
    xor r8, r8
    xor r10, r10
    call emit_ir
    
    mov rdi, r14
    mov rsi, 1
    call sym_set_init
    
    ; do NOT set mutable
    ret

.struct_decl:
    call advance ; consume struct
    mov eax, [current_token]
    cmp eax, TOK_IDENT
    jne .expected_ident
    
    call save_ident
    call advance ; consume IDENT
    
    push rbx
    push r12
    push r13
    push r14
    push r15
    
    mov rdi, TYPE_COMPLEX
    xor rsi, rsi ; size = 0 initially
    mov rdx, ident_buf
    mov rcx, [ident_len]
    xor r8, r8
    extern type_reg_add
    call type_reg_add ; returns type_id in rax
    mov r12, rax ; r12 = struct_type_id
    
    mov edi, TOK_COLON
    call expect
    mov edi, TOK_NEWLINE
    call expect
    mov edi, TOK_INDENT
    call expect
    
    xor r13, r13 ; r13 = accumulated size

.struct_loop:
    mov eax, [current_token]
    cmp eax, TOK_DEDENT
    je .struct_done
    
    cmp eax, TOK_TYPE
    jne .struct_syntax_err
    
    mov r14, [tok_ival] ; field_type_id
    call advance ; consume TYPE
    
    mov eax, [current_token]
    cmp eax, TOK_IDENT
    jne .struct_syntax_err
    
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call advance ; consume IDENT
    
    mov edi, TOK_NEWLINE
    call expect
    
    ; Add field
    mov rdi, r12 ; struct_type_id
    mov rcx, r14 ; field_type_id
    mov r8, r13 ; field_offset
    extern type_struct_add_field
    call type_struct_add_field
    
    ; Add field size
    push rsi
    push rdx
    mov rdi, r14
    extern type_get_size
    call type_get_size
    add r13, rax
    pop rdx
    pop rsi
    
    jmp .struct_loop

.struct_done:
    call advance ; consume DEDENT
    
    ; Set struct size
    mov rdi, r12
    mov rsi, r13
    extern type_set_size
    call type_set_size
    
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.struct_syntax_err:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rdi, err_syntax
    jmp compile_error

.enum_decl:
    call advance ; consume enum
    mov edi, TOK_IDENT
    call expect
    mov edi, TOK_COLON
    call expect
    mov edi, TOK_NEWLINE
    call expect
    mov edi, TOK_INDENT
    call expect
    
    push rbx
    push r12
    push r13
    push r14
    push r15
    
    xor r14, r14 ; enum value

.enum_loop:
    mov eax, [current_token]
    cmp eax, TOK_DEDENT
    je .enum_done
    
    cmp eax, TOK_IDENT
    jne .enum_syntax_err
    
    call save_ident
    call advance
    
    mov eax, [current_token]
    cmp eax, TOK_ASSIGN
    jne .enum_emit
    
    call advance
    mov eax, [current_token]
    cmp eax, TOK_INT_LIT
    jne .enum_syntax_err
    mov r14, [tok_ival]
    call advance

.enum_emit:
    call alloc_vreg
    mov r12, rax
    
    push r12
    mov rdi, IR_LOAD_IMM
    mov rsi, TYPE_INT
    mov rdx, r12
    xor rcx, rcx
    xor r8, r8
    mov r9, r14
    xor r10, r10
    call emit_ir
    pop r12
    
    mov rdi, ident_buf
    mov rsi, [ident_len]
    call determine_scope
    mov rcx, rax
    mov rdx, TYPE_INT
    mov rdi, ident_buf
    mov rsi, [ident_len]
    call sym_add
    cmp rax, -2
    je .enum_dup_err
    cmp rax, -1
    je .enum_full_err
    mov r13, rax
    
    mov rdi, r13
    call sym_get_offset
    mov r9, rax
    
    mov rdi, IR_STORE_VAR
    mov rsi, TYPE_INT
    xor rdx, rdx
    mov rcx, r12
    xor r8, r8
    xor r10, r10
    call emit_ir
    
    mov rdi, r13
    mov rsi, 1
    call sym_set_init
    
    inc r14
    
    mov edi, TOK_NEWLINE
    call expect
    jmp .enum_loop

.enum_done:
    call advance ; consume DEDENT
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.enum_syntax_err:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rdi, err_syntax
    jmp compile_error

.enum_dup_err:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rdi, err_dup_decl
    jmp compile_error

.enum_full_err:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rdi, err_sym_full
    jmp compile_error

.explicit_decl:
    ; explicit_decl: type_expr [ "[" expr "]" ] [ ":" ] <IDENT> [ "=" expr ]
    mov r12, [tok_ival] ; Save type ID
    call advance ; consume TYPE
    
    mov eax, [current_token]
    cmp eax, TOK_LBRACKET
    jne .no_size_suffix
    call advance ; consume '['
    ; for now, we just skip the size expression
    ; ideally we'd call parse_expr, but we can just skip tokens until ']'
.skip_size_loop:
    mov eax, [current_token]
    cmp eax, TOK_RBRACKET
    je .size_done
    cmp eax, TOK_EOF
    je .size_done
    call advance
    jmp .skip_size_loop
.size_done:
    mov edi, TOK_RBRACKET
    call expect ; consume ']'
    
.no_size_suffix:
    xor r13, r13 ; r13 = is_mutable (0 by default)
    mov eax, [current_token]
    cmp eax, TOK_COLON
    jne .no_colon_sigil
    mov r13, 1
    call advance ; consume ':'
    
.no_colon_sigil:
    mov eax, [current_token]
    cmp eax, TOK_IDENT
    jne .expected_ident
    
    ; Save ident name and length
    call save_ident
    call advance ; consume IDENT
    
    ; Add to symbol table
    mov rdi, ident_buf
    mov rsi, [ident_len]
    mov rdx, r12 ; type
    call determine_scope
    mov rcx, rax ; scope
    mov rdx, r12 ; type
    mov rdi, ident_buf
    mov rsi, [ident_len]
    call sym_add
    cmp rax, -2
    je .dup_error
    cmp rax, -1
    je .full_error
    
    mov r14, rax ; Save symbol index
    
    ; Set mutability
    test r13, r13
    jz .not_mutable_yet
    mov rdi, r14
    mov rsi, 1
    call sym_set_mutable
.not_mutable_yet:

    ; Check if there is an initializer
    mov eax, [current_token]
    cmp eax, TOK_ASSIGN
    jne .no_initializer
    
    call advance ; consume '='
    call parse_expr ; rax = vreg, rdx = type
    
    ; Type check
    cmp rdx, r12
    je .type_ok
    cmp r12, TYPE_BYTE
    jne .type_error
    cmp rdx, TYPE_STR
    je .type_ok
    cmp rdx, TYPE_CHAR
    je .type_ok
    cmp rdx, TYPE_INT
    je .type_ok
    jmp .type_error
.type_ok:
    
    ; Emit IR_STORE_VAR
    push rax
    mov rdi, IR_STORE_VAR
    mov rsi, r12 ; type
    xor rdx, rdx ; no dst register (void)
    mov rcx, [rsp] ; src1 vreg
    xor r8, r8
    ; imm = variable offset
    mov rdi, r14
    call sym_get_offset
    mov r9, rax ; imm = variable offset
    mov rdi, IR_STORE_VAR
    mov rsi, r12
    xor rdx, rdx
    mov rcx, [rsp]
    xor r8, r8
    xor r10, r10
    call emit_ir
    pop rax
    
    ; Mark as initialized
    mov rdi, r14
    mov rsi, 1
    call sym_set_init
    ret

.no_initializer:
    ; Uninitialized variable is mutable by default (must be assigned later)
    mov rdi, r14
    mov rsi, 1
    call sym_set_mutable
    ret

.expected_ident:
    mov rdi, err_syntax
    jmp compile_error
.dup_error:
    mov rdi, err_dup_decl
    jmp compile_error
.full_error:
    ; Symbol table overflow (Bug 5 fix: was incorrectly using err_dup_decl)
    mov rdi, err_sym_full
    jmp compile_error
.type_error:
    mov rdi, err_type_mismatch
    jmp compile_error

.mutation:
    ; mutation: ":" <IDENT> "=" expr
    call advance ; consume ':'
    mov eax, [current_token]
    cmp eax, TOK_IDENT
    jne .expected_ident
    
    ; Lookup variable
    mov rdi, [tok_str_ptr]
    mov rsi, [tok_str_len]
    call sym_lookup
    cmp rax, -1
    je .undef_error
    
    mov r14, rax ; Save symbol index
    call advance ; consume IDENT
    
    mov edi, TOK_ASSIGN
    call expect ; consume '='
    
    call parse_expr ; rax = vreg, rdx = type
    
    ; Check type match
    mov rdi, r14
    push rax
    push rdx
    call sym_get_type
    pop rdx
    
    cmp rax, rdx
    je .mut_type_ok
    cmp rax, TYPE_BYTE
    jne .type_error
    cmp rdx, TYPE_STR
    je .mut_type_ok
    cmp rdx, TYPE_CHAR
    je .mut_type_ok
    cmp rdx, TYPE_INT
    je .mut_type_ok
    jmp .type_error
.mut_type_ok:
    
    ; Mark mutable and initialized
    mov rdi, r14
    mov rsi, 1
    call sym_set_mutable
    mov rdi, r14
    mov rsi, 1
    call sym_set_init
    
    ; Emit IR_STORE_VAR
    mov rdi, r14
    call sym_get_type
    mov r12, rax ; type
    
    mov rdi, r14
    call sym_get_offset
    mov r9, rax ; imm = offset
    
    pop rcx ; src1 vreg
    mov rdi, IR_STORE_VAR
    mov rsi, r12
    xor rdx, rdx
    xor r8, r8
    xor r10, r10
    call emit_ir
    ret

.undef_error:
    mov rdi, err_undef
    jmp compile_error

.ident_stmt:
    ; Could be type-inferred declaration: x = 5
    ; or illegal reassignment without ':': x = 5 (when x exists)
    mov rdi, [tok_str_ptr]
    mov rsi, [tok_str_len]
    call sym_lookup
    cmp rax, -1
    je .inferred_decl
    
    ; Variable exists, but we did not see ':'! This is a compile error.
    mov rdi, err_sigil_req
    jmp compile_error

.inferred_decl:
    ; Save identifier name and length
    call save_ident
    call advance ; consume IDENT
    
    mov edi, TOK_ASSIGN
    call expect ; consume '='
    
    call parse_expr ; rax = vreg, rdx = type
    mov r12, rdx ; Save type
    
    ; Add to symbol table
    push rax
    mov rdi, ident_buf
    mov rsi, [ident_len]
    call determine_scope
    mov rcx, rax ; scope
    mov rdx, r12 ; type
    mov rdi, ident_buf
    mov rsi, [ident_len]
    call sym_add
    mov r14, rax ; symbol index
    pop rcx ; src1 vreg
    
    ; Emit IR_STORE_VAR
    mov rdi, r14
    call sym_get_offset
    mov r9, rax ; imm = offset
    
    mov rdi, IR_STORE_VAR
    mov rsi, r12
    xor rdx, rdx
    xor r8, r8
    xor r10, r10
    call emit_ir
    
    ; Mark initialized
    mov rdi, r14
    mov rsi, 1
    call sym_set_init
    ret

.output_stmt:
    ; output_stmt: output "(" expr ["," integer_literal] ")"
    push r13     ; Preserve r13
    
    call advance ; consume output
    mov edi, TOK_LPAREN
    call expect ; consume '('
    
    call parse_expr ; rax = vreg, rdx = type
    mov r12, rdx ; Save type
    push rax     ; save expr vreg on stack

    ; Check if there is a comma
    xor r13, r13 ; Default precision immediate = 0 (means not specified)
    mov eax, [current_token]
    cmp eax, TOK_COMMA
    jne .no_precision

    ; Consume comma
    call advance
    
    ; Expect integer literal for precision
    mov eax, [current_token]
    cmp eax, TOK_INT_LIT
    jne .error_syntax_prec

    ; Save the integer literal value as precision
    mov r13, [tok_ival]
    call advance ; consume TOK_INT_LIT

.no_precision:
    mov edi, TOK_RPAREN
    call expect ; consume ')'
    pop rcx ; restore src1 vreg
    
    ; If type is not float, but precision is specified (r13 != 0), it's a type mismatch
    cmp r12, TYPE_FLOAT
    je .out_float
    test r13, r13
    jnz .error_prec_type_mismatch
    
    cmp r12, TYPE_INT
    je .out_int
    cmp r12, TYPE_BOOL
    je .out_bool
    cmp r12, TYPE_STR
    je .out_str
    cmp r12, TYPE_CHAR
    je .out_char
    cmp r12, TYPE_BYTE
    je .out_int    ; print byte as integer
    
    ; Fallback/error
    mov rdi, err_type_mismatch
    jmp compile_error

.error_syntax_prec:
    mov rdi, err_syntax
    jmp compile_error

.error_prec_type_mismatch:
    mov rdi, err_type_mismatch
    jmp compile_error

.out_char:
    mov rdi, IR_OUT_CHAR
    xor r9, r9
    jmp .emit_out
.out_int:
    mov rdi, IR_OUT_INT
    xor r9, r9
    jmp .emit_out
.out_float:
    mov rdi, IR_OUT_FLOAT
    mov r9, r13  ; Pass precision in r9 (imm)
    jmp .emit_out
.out_bool:
    mov rdi, IR_OUT_BOOL
    xor r9, r9
    jmp .emit_out
.out_str:
    mov rdi, IR_OUT_STR
    xor r9, r9
.emit_out:
    mov rsi, r12 ; type
    xor rdx, rdx ; no dst
    xor r8, r8
    ; r9 already contains the precision
    xor r10, r10
    call emit_ir
    
    pop r13      ; Restore r13
    ret

; Parse Expression
parse_expr:
    jmp parse_null_coalesce

parse_null_coalesce:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call parse_bool_or
    mov r12, rax
    mov r13, rdx
.loop:
    mov eax, [current_token]
    cmp eax, TOK_QQ
    jne .done
    mov r14, IR_OR
    call advance
    push r12
    call parse_bitwise_or
    mov r15, rax
    pop r12
    push r12
    push r15
    call alloc_vreg
    mov rbx, rax
    pop r15
    pop r12
    mov rdi, r14
    mov rsi, r13
    mov rdx, rbx
    mov rcx, r12
    mov r8, r15
    xor r9, r9
    xor r10, r10
    call emit_ir
    mov r12, rbx
    jmp .loop
.done:
    mov rax, r12
    mov rdx, r13
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ==========================================================
; Binary Operator Parser Macro Structure
; Since NASM macros for complex logic are tricky, we use explicit blocks.
; ==========================================================

; Parse Bool OR expression (lowest bool precedence: 'or' = max)
parse_bool_or:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call parse_bool_and
    mov r12, rax
    mov r13, rdx
.loop:
    mov eax, [current_token]
    cmp eax, TOK_BOOL_OR
    jne .done
    call advance
    push r12
    call parse_bool_and
    mov r15, rax
    pop r12
    ; Both operands must be bool
    push r12
    push r15
    call alloc_vreg
    mov rbx, rax
    pop r15
    pop r12
    mov rdi, IR_BOOL_OR
    mov rsi, TYPE_BOOL
    mov rdx, rbx
    mov rcx, r12
    mov r8, r15
    xor r9, r9
    xor r10, r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_BOOL
    jmp .loop
.done:
    mov rax, r12
    mov rdx, r13
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Parse Bool AND expression ('and' = min)
parse_bool_and:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call parse_bitwise_or
    mov r12, rax
    mov r13, rdx
.loop:
    mov eax, [current_token]
    cmp eax, TOK_BOOL_AND
    jne .done
    call advance
    push r12
    call parse_bitwise_or
    mov r15, rax
    pop r12
    push r12
    push r15
    call alloc_vreg
    mov rbx, rax
    pop r15
    pop r12
    mov rdi, IR_BOOL_AND
    mov rsi, TYPE_BOOL
    mov rdx, rbx
    mov rcx, r12
    mov r8, r15
    xor r9, r9
    xor r10, r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_BOOL
    jmp .loop
.done:
    mov rax, r12
    mov rdx, r13
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

parse_bitwise_or:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call parse_bitwise_xor
    mov r12, rax
    mov r13, rdx
.loop:
    mov eax, [current_token]
    cmp eax, TOK_OR
    jne .done
    mov r14, IR_OR
    call advance
    push r12
    call parse_bitwise_xor
    mov r15, rax
    pop r12
    cmp rdx, r13
    jne .type_error
    push r12
    push r15
    call alloc_vreg
    mov rbx, rax
    pop r15
    pop r12
    mov rdi, r14
    mov rsi, r13
    mov rdx, rbx
    mov rcx, r12
    mov r8, r15
    xor r9, r9
    xor r10, r10
    call emit_ir
    mov r12, rbx
    jmp .loop
.type_error:
    mov rdi, err_type_mismatch
    jmp compile_error
.done:
    mov rax, r12
    mov rdx, r13
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

parse_bitwise_xor:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call parse_bitwise_and
    mov r12, rax
    mov r13, rdx
.loop:
    mov eax, [current_token]
    cmp eax, TOK_XOR
    jne .done
    mov r14, IR_XOR
    call advance
    push r12
    call parse_bitwise_and
    mov r15, rax
    pop r12
    cmp rdx, r13
    jne .type_error
    push r12
    push r15
    call alloc_vreg
    mov rbx, rax
    pop r15
    pop r12
    mov rdi, r14
    mov rsi, r13
    mov rdx, rbx
    mov rcx, r12
    mov r8, r15
    xor r9, r9
    xor r10, r10
    call emit_ir
    mov r12, rbx
    jmp .loop
.type_error:
    mov rdi, err_type_mismatch
    jmp compile_error
.done:
    mov rax, r12
    mov rdx, r13
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

parse_bitwise_and:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call parse_add
    mov r12, rax
    mov r13, rdx
.loop:
    mov eax, [current_token]
    cmp eax, TOK_AND
    jne .done
    mov r14, IR_AND
    call advance
    push r12
    call parse_add
    mov r15, rax
    pop r12
    cmp rdx, r13
    jne .type_error
    push r12
    push r15
    call alloc_vreg
    mov rbx, rax
    pop r15
    pop r12
    mov rdi, r14
    mov rsi, r13
    mov rdx, rbx
    mov rcx, r12
    mov r8, r15
    xor r9, r9
    xor r10, r10
    call emit_ir
    mov r12, rbx
    jmp .loop
.type_error:
    mov rdi, err_type_mismatch
    jmp compile_error
.done:
    mov rax, r12
    mov rdx, r13
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Parse Additive Expression
parse_add:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call parse_mult
    mov r12, rax
    mov r13, rdx
.loop:
    mov eax, [current_token]
    cmp eax, TOK_PLUS
    je .add
    cmp eax, TOK_MINUS
    je .sub
    jmp .done
.add:
    mov r14, IR_ADD
    jmp .consume
.sub:
    mov r14, IR_SUB
.consume:
    call advance
    push r12
    call parse_mult
    mov r15, rax
    pop r12
    cmp rdx, r13
    jne .type_error
    push r12
    push r15
    call alloc_vreg
    mov rbx, rax
    pop r15
    pop r12
    mov rdi, r14
    mov rsi, r13
    mov rdx, rbx
    mov rcx, r12
    mov r8, r15
    xor r9, r9
    xor r10, r10
    call emit_ir
    mov r12, rbx
    jmp .loop
.type_error:
    mov rdi, err_type_mismatch
    jmp compile_error
.done:
    mov rax, r12
    mov rdx, r13
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Parse Multiplicative Expression
parse_mult:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call parse_postfix
    mov r12, rax
    mov r13, rdx
.loop:
    mov eax, [current_token]
    cmp eax, TOK_STAR
    je .mul
    cmp eax, TOK_SLASH
    je .div
    cmp eax, TOK_MOD
    je .mod
    jmp .done
.mul:
    mov r14, IR_MUL
    jmp .consume
.div:
    mov r14, IR_DIV
    jmp .consume
.mod:
    mov r14, IR_MOD
.consume:
    call advance
    push r12
    call parse_postfix
    mov r15, rax
    pop r12
    cmp rdx, r13
    jne .type_error
    push r12
    push r15
    call alloc_vreg
    mov rbx, rax
    pop r15
    pop r12
    mov rdi, r14
    mov rsi, r13
    mov rdx, rbx
    mov rcx, r12
    mov r8, r15
    xor r9, r9
    xor r10, r10
    call emit_ir
    mov r12, rbx
    jmp .loop
.type_error:
    mov rdi, err_type_mismatch
    jmp compile_error
.done:
    mov rax, r12
    mov rdx, r13
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret


; Parse Term
parse_term:
    mov eax, [current_token]
    cmp eax, TOK_INT_LIT
    je .int_lit
    cmp eax, TOK_FLOAT_LIT
    je .float_lit
    cmp eax, TOK_BOOL_LIT
    je .bool_lit
    cmp eax, TOK_CHAR_LIT
    je .char_lit
    cmp eax, TOK_STR_LIT
    je .str_lit
    cmp eax, TOK_NULL
    je .null_lit
    cmp eax, TOK_IDENT
    je .ident
    cmp eax, TOK_LPAREN
    je .paren
    cmp eax, TOK_BOOL_NOT
    je .bool_not
    
    mov rdi, err_syntax
    jmp compile_error

.int_lit:
    push qword [tok_ival]
    call advance
    call alloc_vreg
    push rax
    
    mov rdi, IR_LOAD_IMM
    mov rsi, TYPE_INT
    mov rdx, [rsp]
    xor rcx, rcx
    xor r8, r8
    mov r9, [rsp + 8]
    xor r10, r10
    call emit_ir
    
    pop rax
    add rsp, 8
    mov rdx, TYPE_INT
    ret

.float_lit:
    push qword [tok_fval]
    call advance
    call alloc_vreg
    push rax
    
    mov rdi, IR_LOAD_FIMM
    mov rsi, TYPE_FLOAT
    mov rdx, [rsp]
    xor rcx, rcx
    xor r8, r8
    mov r9, [rsp + 8]
    xor r10, r10
    call emit_ir
    
    pop rax
    add rsp, 8
    mov rdx, TYPE_FLOAT
    ret

.bool_lit:
    push qword [tok_ival]
    call advance
    call alloc_vreg
    push rax
    
    mov rdi, IR_LOAD_BOOL
    mov rsi, TYPE_BOOL
    mov rdx, [rsp]
    xor rcx, rcx
    xor r8, r8
    mov r9, [rsp + 8]
    xor r10, r10
    call emit_ir
    
    pop rax
    add rsp, 8
    mov rdx, TYPE_BOOL
    ret

.char_lit:
    push qword [tok_ival]
    call advance
    call alloc_vreg
    push rax
    
    mov rdi, IR_LOAD_IMM
    mov rsi, TYPE_CHAR
    mov rdx, [rsp]
    xor rcx, rcx
    xor r8, r8
    mov r9, [rsp + 8]
    xor r10, r10
    call emit_ir
    
    pop rax
    add rsp, 8
    mov rdx, TYPE_CHAR
    ret

.str_lit:
    push qword [tok_str_len]
    push qword [tok_str_ptr]
    call advance
    call alloc_vreg
    push rax
    
    mov rdi, IR_LOAD_STR
    mov rsi, TYPE_STR
    mov rdx, [rsp]
    xor rcx, rcx
    xor r8, r8
    mov r9, [rsp + 8]
    mov r10, [rsp + 16]
    call emit_ir
    
    pop rax
    add rsp, 16
    mov rdx, TYPE_STR
    ret

.null_lit:
    call advance
    call alloc_vreg
    push rax
    
    mov rdi, IR_LOAD_IMM
    xor rsi, rsi
    mov rdx, [rsp]
    xor rcx, rcx
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir
    
    pop rax
    xor rdx, rdx
    ret

.ident:
    mov rdi, [tok_str_ptr]
    mov rsi, [tok_str_len]
    call sym_lookup
    cmp rax, -1
    je .undef_error
    
    push rax ; sym_idx
    call advance
    
    mov rdi, [rsp]
    call sym_is_init
    test rax, rax
    jz .uninit_error
    
    mov rdi, [rsp]
    call sym_get_type
    push rax ; type
    
    call alloc_vreg
    push rax ; vreg
    
    mov rdi, [rsp + 16] ; sym_idx
    call sym_get_offset
    mov r9, rax ; offset
    
    mov rdi, IR_LOAD_VAR
    mov rsi, [rsp + 8] ; type
    mov rdx, [rsp] ; dst
    xor rcx, rcx
    xor r8, r8
    xor r10, r10
    call emit_ir
    
    pop rax ; vreg
    pop rdx ; type
    add rsp, 8 ; clean up sym_idx
    ret

.undef_error:
    mov rdi, err_undef
    jmp compile_error
.uninit_error:
    add rsp, 8 ; clean up sym_idx
    mov rdi, err_uninit
    jmp compile_error

.paren:
    call advance ; consume '('
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect ; consume ')'
    pop rdx
    pop rax
    ret

.bool_not:
    call advance ; consume 'not'
    call parse_postfix ; parse the operand
    push rax
    push rdx
    call alloc_vreg
    mov rbx, rax
    pop rdx  ; operand type
    pop rcx  ; operand vreg
    mov rdi, IR_BOOL_NOT
    mov rsi, TYPE_BOOL
    mov rdx, rbx
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir
    mov rax, rbx
    mov rdx, TYPE_BOOL
    ret


; Helper to determine scope
; rdi = name_ptr, rsi = name_len
; Returns rax = scope level
determine_scope:
    cmp rsi, 2
    jl .not_block
    cmp byte [rdi], '_'
    jne .not_block
    cmp byte [rdi + 1], '_'
    jne .not_block
    mov rax, SCOPE_BLOCK
    ret
.not_block:
    mov rax, SCOPE_GLOBAL
    ret

; Helper to save identifier token
save_ident:
    mov rsi, [tok_str_ptr]
    mov rcx, [tok_str_len]
    cmp rcx, 31
    jle .ok
    mov rcx, 31
.ok:
    mov [ident_len], rcx
    xor rdi, rdi
.loop:
    cmp rdi, rcx
    je .done
    movzx rax, byte [rsi + rdi]
    mov [ident_buf + rdi], al
    inc rdi
    jmp .loop
.done:
    mov byte [ident_buf + rdi], 0
    ret

; Report a compile error and exit
; rdi = message string
compile_error:
    push rdi
    
    ; Print error prefix to stderr
    mov rax, 1
    mov rdi, 2
    mov rsi, .err_prefix
    mov rdx, .err_prefix_len
    syscall
    
    ; Print message
    pop rsi ; original message
    push rsi
    xor rdx, rdx
.len_loop:
    cmp byte [rsi + rdx], 0
    je .len_done
    inc rdx
    jmp .len_loop
.len_done:
    mov rax, 1
    mov rdi, 2
    syscall
    
    ; Print line details
    mov rax, 1
    mov rdi, 2
    mov rsi, .line_suffix
    mov rdx, .line_suffix_len
    syscall
    
    ; Print line number
    call get_error_loc ; rax = line
    ; Simple division to print integer line number
    mov rbx, 10
    push 10 ; newline at end
    mov rcx, 1 ; count of chars pushed
.div_loop:
    xor rdx, rdx
    div rbx
    add rdx, '0'
    push rdx
    inc rcx
    test rax, rax
    jnz .div_loop
    
.print_loop:
    dec rcx
    push rcx
    mov rax, 1
    mov rdi, 2
    lea rsi, [rsp + 8] ; print char pushed
    mov rdx, 1
    syscall
    pop rcx
    pop rax ; remove char from stack
    test rcx, rcx
    jnz .print_loop
    
    mov rax, 60
    mov rdi, 1 ; exit code 1
    syscall

section .rodata
    .err_prefix db "Compile Error: ", 0
    .err_prefix_len equ $ - .err_prefix
    .line_suffix db " at line ", 0
    .line_suffix_len equ $ - .line_suffix

; ======================================================
; ident_is: compare method_buf against null-terminated string in rdi
; Returns: rax=1 if match, rax=0 otherwise
; Preserves: rbx
; ======================================================
ident_is:
    push rbx
    mov rbx, rdi             ; rbx = expected string ptr
    ; Count expected string length
    xor rcx, rcx
.ii_count:
    cmp byte [rbx + rcx], 0
    je .ii_counted
    inc rcx
    jmp .ii_count
.ii_counted:
    cmp rcx, [method_len]
    jne .ii_no_match
    test rcx, rcx
    jz .ii_match
    lea rdi, [method_buf]
    mov rsi, rbx
.ii_cmp:
    movzx rax, byte [rdi]
    cmp al, byte [rsi]
    jne .ii_no_match
    inc rdi
    inc rsi
    dec rcx
    jnz .ii_cmp
.ii_match:
    mov rax, 1
    pop rbx
    ret
.ii_no_match:
    xor rax, rax
    pop rbx
    ret

; ======================================================
; parse_postfix: parse a term followed by optional .method() chains
; Returns: rax = vreg, rdx = type
; r12 = current vreg (accumulated through chain)
; r13 = current type
; ======================================================
parse_postfix:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call parse_term
    ; stub: no method dispatch, just return result
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; original parse_postfix body saved below (method dispatch)
parse_postfix_full:
    push rbx
    push r12
    push r13
    push r14
    push r15

    call parse_term
    mov r12, rax
    mov r13, rdx

.pp_loop:
    mov eax, [current_token]
    cmp eax, TOK_DOT
    jne .pp_done

    call advance              ; consume '.'

    mov eax, [current_token]
    cmp eax, TOK_IDENT
    jne .pp_syntax_err

    ; Copy method name into method_buf
    mov rsi, [tok_str_ptr]
    mov rcx, [tok_str_len]
    cmp rcx, 31
    jle .pp_mlen_ok
    mov rcx, 31
.pp_mlen_ok:
    mov [method_len], rcx
    lea rdi, [method_buf]
    push rcx
    test rcx, rcx
    jz .pp_mcopy_done
.pp_mcopy:
    movzx rax, byte [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jnz .pp_mcopy
.pp_mcopy_done:
    pop rcx
    lea rdi, [method_buf]
    add rdi, rcx
    mov byte [rdi], 0

    call advance              ; consume method name IDENT

    mov edi, TOK_LPAREN
    call expect               ; consume '('

    ; Dispatch by type
    cmp r13, TYPE_INT
    je .pp_int_dispatch
    cmp r13, TYPE_FLOAT
    je .pp_float_dispatch
    cmp r13, TYPE_BOOL
    je .pp_bool_dispatch
    cmp r13, TYPE_CHAR
    je .pp_char_dispatch
    cmp r13, TYPE_BYTE
    je .pp_byte_dispatch
    jmp .pp_type_err

; ─────────── INT methods ───────────────────────────────
.pp_int_dispatch:
    lea rdi, [str_abs]
    call ident_is
    test rax,rax
    jnz .pp_int_abs
    lea rdi, [str_min]
    call ident_is
    test rax,rax
    jnz .pp_int_min
    lea rdi, [str_max]
    call ident_is
    test rax,rax
    jnz .pp_int_max
    lea rdi, [str_clamp]
    call ident_is
    test rax,rax
    jnz .pp_int_clamp
    lea rdi, [str_signum]
    call ident_is
    test rax,rax
    jnz .pp_int_signum
    lea rdi, [str_is_zero]
    call ident_is
    test rax,rax
    jnz .pp_int_is_zero
    lea rdi, [str_is_positive]
    call ident_is
    test rax,rax
    jnz .pp_int_is_pos
    lea rdi, [str_is_negative]
    call ident_is
    test rax,rax
    jnz .pp_int_is_neg
    lea rdi, [str_is_even]
    call ident_is
    test rax,rax
    jnz .pp_int_is_even
    lea rdi, [str_is_odd]
    call ident_is
    test rax,rax
    jnz .pp_int_is_odd
    lea rdi, [str_popcount]
    call ident_is
    test rax,rax
    jnz .pp_int_popcount
    lea rdi, [str_leading_zeros]
    call ident_is
    test rax,rax
    jnz .pp_int_clz
    lea rdi, [str_trailing_zeros]
    call ident_is
    test rax,rax
    jnz .pp_int_ctz
    lea rdi, [str_bit_len]
    call ident_is
    test rax,rax
    jnz .pp_int_bit_len
    lea rdi, [str_swap_bytes]
    call ident_is
    test rax,rax
    jnz .pp_int_bswap
    lea rdi, [str_rotate_left]
    call ident_is
    test rax,rax
    jnz .pp_int_rol
    lea rdi, [str_rotate_right];call ident_is
    test rax,rax
    jnz .pp_int_ror
    jmp .pp_method_err

.pp_int_abs:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_ABS_INT
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

.pp_int_min:
    call parse_expr
    mov r14, rax
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_MIN_INT
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r12
    mov r8, r14
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

.pp_int_max:
    call parse_expr
    mov r14, rax
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_MAX_INT
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r12
    mov r8, r14
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

.pp_int_clamp:
    call parse_expr
    mov r14, rax   ; lo
    mov edi, TOK_COMMA
    call expect
    call parse_expr
    mov r15, rax   ; hi
    mov edi, TOK_RPAREN
    call expect
    ; temp = min(self, hi)
    call alloc_vreg
    push rax
    mov rdi, IR_MIN_INT
    mov rsi, TYPE_INT
    mov rdx, [rsp]
    mov rcx, r12
    mov r8, r15
    xor r9,r9
    xor r10,r10
    call emit_ir
    ; result = max(lo, temp)
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_MAX_INT
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r14
    mov r8, [rsp]
    xor r9,r9
    xor r10,r10
    call emit_ir
    add rsp, 8
    mov r12, rbx
    jmp .pp_loop

.pp_int_signum:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_SIGNUM
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

.pp_int_is_zero:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_CMP_BOOL
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    mov r10, COND_EQ
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_BOOL
    jmp .pp_loop

.pp_int_is_pos:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_CMP_BOOL
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    mov r10, COND_GT
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_BOOL
    jmp .pp_loop

.pp_int_is_neg:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_CMP_BOOL
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    mov r10, COND_LT
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_BOOL
    jmp .pp_loop

.pp_int_is_even:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_IS_EVEN
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_BOOL
    jmp .pp_loop

.pp_int_is_odd:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_IS_ODD
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_BOOL
    jmp .pp_loop

.pp_int_popcount:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_POPCOUNT
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_INT
    jmp .pp_loop

.pp_int_clz:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_CLZ
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_INT
    jmp .pp_loop

.pp_int_ctz:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_CTZ
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_INT
    jmp .pp_loop

.pp_int_bit_len:
    mov edi, TOK_RPAREN
    call expect
    ; clz_result = clz(self)
    call alloc_vreg
    push rax
    mov rdi, IR_CLZ
    mov rsi, TYPE_INT
    mov rdx, [rsp]
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    ; const64 = 64
    call alloc_vreg
    push rax
    mov rdi, IR_LOAD_IMM
    mov rsi, TYPE_INT
    mov rdx, [rsp]
    xor rcx,rcx
    xor r8,r8
    mov r9,64
    xor r10,r10
    call emit_ir
    ; result = 64 - clz_result
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_SUB
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, [rsp]
    mov r8, [rsp+8]
    xor r9,r9
    xor r10,r10
    call emit_ir
    add rsp, 16
    mov r12, rbx
    mov r13, TYPE_INT
    jmp .pp_loop

.pp_int_bswap:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_BSWAP
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

.pp_int_rol:
    call parse_expr
    mov r14, rax
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_ROL
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r12
    mov r8, r14
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

.pp_int_ror:
    call parse_expr
    mov r14, rax
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_ROR
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r12
    mov r8, r14
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

; ─────────── FLOAT methods ─────────────────────────────
.pp_float_dispatch:
    lea rdi, [str_abs]
    call ident_is
    test rax,rax
    jnz .pp_float_abs
    lea rdi, [str_min]
    call ident_is
    test rax,rax
    jnz .pp_float_min
    lea rdi, [str_max]
    call ident_is
    test rax,rax
    jnz .pp_float_max
    lea rdi, [str_clamp]
    call ident_is
    test rax,rax
    jnz .pp_float_clamp
    lea rdi, [str_ceil]
    call ident_is
    test rax,rax
    jnz .pp_float_ceil
    lea rdi, [str_floor]
    call ident_is
    test rax,rax
    jnz .pp_float_floor
    lea rdi, [str_round]
    call ident_is
    test rax,rax
    jnz .pp_float_round
    lea rdi, [str_trunc]
    call ident_is
    test rax,rax
    jnz .pp_float_trunc
    lea rdi, [str_fract]
    call ident_is
    test rax,rax
    jnz .pp_float_fract
    lea rdi, [str_sqrt]
    call ident_is
    test rax,rax
    jnz .pp_float_sqrt
    lea rdi, [str_recip]
    call ident_is
    test rax,rax
    jnz .pp_float_recip
    lea rdi, [str_is_zero]
    call ident_is
    test rax,rax
    jnz .pp_float_is_zero
    lea rdi, [str_is_positive]
    call ident_is
    test rax,rax
    jnz .pp_float_is_pos
    lea rdi, [str_is_negative]
    call ident_is
    test rax,rax
    jnz .pp_float_is_neg
    lea rdi, [str_is_nan]
    call ident_is
    test rax,rax
    jnz .pp_float_is_nan
    lea rdi, [str_is_infinite]
    call ident_is
    test rax,rax
    jnz .pp_float_is_inf
    lea rdi, [str_is_finite]
    call ident_is
    test rax,rax
    jnz .pp_float_is_finite
    jmp .pp_method_err

.pp_float_abs:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_ABS_FLOAT
    mov rsi, TYPE_FLOAT
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

.pp_float_min:
    call parse_expr
    mov r14, rax
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_MIN_FLOAT
    mov rsi, TYPE_FLOAT
    mov rdx, rbx
    mov rcx, r12
    mov r8, r14
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

.pp_float_max:
    call parse_expr
    mov r14, rax
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_MAX_FLOAT
    mov rsi, TYPE_FLOAT
    mov rdx, rbx
    mov rcx, r12
    mov r8, r14
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

.pp_float_clamp:
    call parse_expr
    mov r14, rax   ; lo
    mov edi, TOK_COMMA
    call expect
    call parse_expr
    mov r15, rax   ; hi
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    push rax
    mov rdi, IR_MIN_FLOAT
    mov rsi, TYPE_FLOAT
    mov rdx, [rsp]
    mov rcx, r12
    mov r8, r15
    xor r9,r9
    xor r10,r10
    call emit_ir
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_MAX_FLOAT
    mov rsi, TYPE_FLOAT
    mov rdx, rbx
    mov rcx, r14
    mov r8, [rsp]
    xor r9,r9
    xor r10,r10
    call emit_ir
    add rsp, 8
    mov r12, rbx
    jmp .pp_loop

.pp_float_ceil:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_CEIL
    mov rsi, TYPE_FLOAT
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_INT
    jmp .pp_loop

.pp_float_floor:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_FLOOR
    mov rsi, TYPE_FLOAT
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_INT
    jmp .pp_loop

.pp_float_round:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_ROUND
    mov rsi, TYPE_FLOAT
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_INT
    jmp .pp_loop

.pp_float_trunc:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_TRUNC_F
    mov rsi, TYPE_FLOAT
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

.pp_float_fract:
    mov edi, TOK_RPAREN
    call expect
    ; temp = trunc(self)
    call alloc_vreg
    push rax
    mov rdi, IR_TRUNC_F
    mov rsi, TYPE_FLOAT
    mov rdx, [rsp]
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    ; result = self - temp
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_SUB
    mov rsi, TYPE_FLOAT
    mov rdx, rbx
    mov rcx, r12
    mov r8, [rsp]
    xor r9,r9
    xor r10,r10
    call emit_ir
    add rsp, 8
    mov r12, rbx
    jmp .pp_loop

.pp_float_sqrt:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_SQRT
    mov rsi, TYPE_FLOAT
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

.pp_float_recip:
    mov edi, TOK_RPAREN
    call expect
    ; vreg_one = 1.0
    call alloc_vreg
    push rax
    mov rdi, IR_LOAD_FIMM
    mov rsi, TYPE_FLOAT
    mov rdx, [rsp]
    xor rcx,rcx
    xor r8,r8
    mov r9, [float_pp_one]
    xor r10,r10
    call emit_ir
    ; result = 1.0 / self
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_DIV
    mov rsi, TYPE_FLOAT
    mov rdx, rbx
    mov rcx, [rsp]
    mov r8, r12
    xor r9,r9
    xor r10,r10
    call emit_ir
    add rsp, 8
    mov r12, rbx
    jmp .pp_loop

.pp_float_is_zero:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_IS_ZERO_F
    mov rsi, TYPE_FLOAT
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_BOOL
    jmp .pp_loop

.pp_float_is_pos:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_IS_POS_F
    mov rsi, TYPE_FLOAT
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_BOOL
    jmp .pp_loop

.pp_float_is_neg:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_IS_NEG_F
    mov rsi, TYPE_FLOAT
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_BOOL
    jmp .pp_loop

.pp_float_is_nan:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_IS_NAN
    mov rsi, TYPE_FLOAT
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_BOOL
    jmp .pp_loop

.pp_float_is_inf:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_IS_INF
    mov rsi, TYPE_FLOAT
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_BOOL
    jmp .pp_loop

.pp_float_is_finite:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_IS_FINITE
    mov rsi, TYPE_FLOAT
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_BOOL
    jmp .pp_loop

; ─────────── BOOL methods ──────────────────────────────
.pp_bool_dispatch:
    lea rdi, [str_is_true]
    call ident_is
    test rax,rax
    jnz .pp_bool_is_true
    lea rdi, [str_is_false]
    call ident_is
    test rax,rax
    jnz .pp_bool_is_false
    lea rdi, [str_is_neutral]
    call ident_is
    test rax,rax
    jnz .pp_bool_is_neutral
    lea rdi, [str_is_decided]
    call ident_is
    test rax,rax
    jnz .pp_bool_is_decided
    lea rdi, [str_flip]
    call ident_is
    test rax,rax
    jnz .pp_bool_flip
    lea rdi, [str_to_int]
    call ident_is
    test rax,rax
    jnz .pp_bool_to_int
    lea rdi, [str_and_m]
    call ident_is
    test rax,rax
    jnz .pp_bool_and
    lea rdi, [str_or_m]
    call ident_is
    test rax,rax
    jnz .pp_bool_or
    jmp .pp_method_err

.pp_bool_is_true:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_CMP_BOOL
    mov rsi, TYPE_BOOL
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    mov r9,1
    mov r10,COND_EQ
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

.pp_bool_is_false:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_CMP_BOOL
    mov rsi, TYPE_BOOL
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    mov r9,-1
    mov r10,COND_EQ
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

.pp_bool_is_neutral:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_CMP_BOOL
    mov rsi, TYPE_BOOL
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    mov r10,COND_EQ
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

.pp_bool_is_decided:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_CMP_BOOL
    mov rsi, TYPE_BOOL
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    mov r10,COND_NE
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

.pp_bool_flip:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_BOOL_NOT
    mov rsi, TYPE_BOOL
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

.pp_bool_to_int:
    mov edi, TOK_RPAREN
    call expect
    mov r13, TYPE_INT
    jmp .pp_loop

.pp_bool_and:
    call parse_expr
    mov r14, rax
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_BOOL_AND
    mov rsi, TYPE_BOOL
    mov rdx, rbx
    mov rcx, r12
    mov r8, r14
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

.pp_bool_or:
    call parse_expr
    mov r14, rax
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_BOOL_OR
    mov rsi, TYPE_BOOL
    mov rdx, rbx
    mov rcx, r12
    mov r8, r14
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

; ─────────── CHAR methods ──────────────────────────────
.pp_char_dispatch:
    lea rdi, [str_is_alpha]
    call ident_is
    test rax,rax
    jnz .pp_char_is_alpha
    lea rdi, [str_is_digit_s]
    call ident_is
    test rax,rax
    jnz .pp_char_is_digit
    lea rdi, [str_is_alnum]
    call ident_is
    test rax,rax
    jnz .pp_char_is_alnum
    lea rdi, [str_is_whitespace];call ident_is;test rax,rax
    jnz .pp_char_is_space
    lea rdi, [str_is_upper]
    call ident_is
    test rax,rax
    jnz .pp_char_is_upper
    lea rdi, [str_is_lower]
    call ident_is
    test rax,rax
    jnz .pp_char_is_lower
    lea rdi, [str_is_punct]
    call ident_is
    test rax,rax
    jnz .pp_char_is_punct
    lea rdi, [str_is_printable];call ident_is
    test rax,rax
    jnz .pp_char_is_print
    lea rdi, [str_is_ascii]
    call ident_is
    test rax,rax
    jnz .pp_char_is_ascii
    lea rdi, [str_to_upper]
    call ident_is
    test rax,rax
    jnz .pp_char_to_upper
    lea rdi, [str_to_lower]
    call ident_is
    test rax,rax
    jnz .pp_char_to_lower
    lea rdi, [str_to_int]
    call ident_is
    test rax,rax
    jnz .pp_char_to_int
    lea rdi, [str_to_byte]
    call ident_is
    test rax,rax
    jnz .pp_char_to_byte
    lea rdi, [str_to_digit]
    call ident_is
    test rax,rax
    jnz .pp_char_to_digit
    jmp .pp_method_err

%macro pp_char_pred 2
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, %1
    mov rsi, TYPE_CHAR
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_BOOL
    jmp .pp_loop
%endmacro

.pp_char_is_alpha:  pp_char_pred IR_IS_ALPHA,  0
.pp_char_is_digit:  pp_char_pred IR_IS_DIGIT_C, 0
.pp_char_is_alnum:  pp_char_pred IR_IS_ALNUM,  0
.pp_char_is_space:  pp_char_pred IR_IS_SPACE,  0
.pp_char_is_upper:  pp_char_pred IR_IS_UPPER,  0
.pp_char_is_lower:  pp_char_pred IR_IS_LOWER_C,0
.pp_char_is_punct:  pp_char_pred IR_IS_PUNCT,  0
.pp_char_is_print:  pp_char_pred IR_IS_PRINT,  0

.pp_char_is_ascii:
    ; is_ascii: (c < 128) ≡ CMP_BOOL with COND_LT, imm=128
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_CMP_BOOL
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    mov r9,128
    mov r10,COND_LT
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_BOOL
    jmp .pp_loop

.pp_char_to_upper:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_TO_UPPER
    mov rsi, TYPE_CHAR
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

.pp_char_to_lower:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_TO_LOWER
    mov rsi, TYPE_CHAR
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

.pp_char_to_int:
    mov edi, TOK_RPAREN
    call expect
    mov r13, TYPE_INT
    jmp .pp_loop

.pp_char_to_byte:
    mov edi, TOK_RPAREN
    call expect
    mov r13, TYPE_BYTE
    jmp .pp_loop

.pp_char_to_digit:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_TO_DIGIT
    mov rsi, TYPE_CHAR
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_INT
    jmp .pp_loop

; ─────────── BYTE methods ──────────────────────────────
.pp_byte_dispatch:
    lea rdi, [str_popcount]
    call ident_is
    test rax,rax
    jnz .pp_byte_popcount
    lea rdi, [str_is_zero]
    call ident_is
    test rax,rax
    jnz .pp_byte_is_zero
    lea rdi, [str_is_even]
    call ident_is
    test rax,rax
    jnz .pp_byte_is_even
    lea rdi, [str_is_odd]
    call ident_is
    test rax,rax
    jnz .pp_byte_is_odd
    lea rdi, [str_is_ascii]
    call ident_is
    test rax,rax
    jnz .pp_byte_is_ascii
    lea rdi, [str_to_int]
    call ident_is
    test rax,rax
    jnz .pp_byte_to_int
    lea rdi, [str_to_char]
    call ident_is
    test rax,rax
    jnz .pp_byte_to_char
    lea rdi, [str_swap_nibbles];call ident_is
    test rax,rax
    jnz .pp_byte_swap_nib
    lea rdi, [str_leading_zeros];call ident_is;test rax,rax
    jnz .pp_byte_clz8
    lea rdi, [str_trailing_zeros];call ident_is;test rax,rax;jnz .pp_byte_ctz
    jmp .pp_method_err

.pp_byte_popcount:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_POPCOUNT
    mov rsi, TYPE_BYTE
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_INT
    jmp .pp_loop

.pp_byte_is_zero:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_CMP_BOOL
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    mov r10,COND_EQ
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_BOOL
    jmp .pp_loop

.pp_byte_is_even:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_IS_EVEN
    mov rsi, TYPE_BYTE
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_BOOL
    jmp .pp_loop

.pp_byte_is_odd:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_IS_ODD
    mov rsi, TYPE_BYTE
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_BOOL
    jmp .pp_loop

.pp_byte_is_ascii:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_CMP_BOOL
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    mov r9,128
    mov r10,COND_LT
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_BOOL
    jmp .pp_loop

.pp_byte_to_int:
    mov edi, TOK_RPAREN
    call expect
    mov r13, TYPE_INT
    jmp .pp_loop

.pp_byte_to_char:
    mov edi, TOK_RPAREN
    call expect
    mov r13, TYPE_CHAR
    jmp .pp_loop

.pp_byte_swap_nib:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_SWAP_NIB
    mov rsi, TYPE_BYTE
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

.pp_byte_clz8:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_CLZ8
    mov rsi, TYPE_BYTE
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_INT
    jmp .pp_loop

.pp_byte_ctz:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_CTZ
    mov rsi, TYPE_BYTE
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_INT
    jmp .pp_loop

; ─────────── shared exits ──────────────────────────────
.pp_done:
    mov rax, r12
    mov rdx, r13
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.pp_syntax_err:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rdi, err_syntax
    jmp compile_error

.pp_type_err:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rdi, err_type_mismatch
    jmp compile_error

.pp_method_err:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rdi, err_unknown_method
    jmp compile_error
