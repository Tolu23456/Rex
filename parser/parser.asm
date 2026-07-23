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
    err_immutable   db "Compile Error: Cannot mutate an immutable variable", 0
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
    ; Seq method names
    str_push          db "push", 0
    str_len_m         db "len", 0
    str_get_m         db "get", 0
    str_pop           db "pop", 0
    str_insert        db "insert", 0
    str_remove        db "remove", 0
    str_first         db "first", 0
    str_last          db "last", 0
    str_contains      db "contains", 0
    str_index_of      db "index_of", 0
    str_count_of      db "count_of", 0
    str_copy          db "copy", 0
    str_reverse       db "reverse", 0
    str_sum_m         db "sum", 0
    str_min_m         db "min", 0
    str_max_m         db "max", 0
    str_slice         db "slice", 0
    str_clear_m       db "clear", 0
    str_reserve_m     db "reserve", 0
    str_cap_m         db "cap", 0
    str_is_empty_m    db "is_empty", 0
    float_pp_one      dq 0x3FF0000000000000

    ; scope() built-in string constants
    str_scope_global  db "global", 0
    str_scope_local   db "local", 0
    str_scope_block   db "block", 0

    ; For loop hidden variable name
    str_for_end       db "_for_end", 0

    ; Block nesting depth for SCOPE_LOCAL tracking
    ; depth 0 = global scope, depth > 0 = inside a block (SCOPE_LOCAL)
    block_nesting     dd 0
    ; Saved sym_count at block entry for block-scope cleanup
    block_sym_save    times 32 dd 0  ; up to 32 nesting levels

section .bss
    ; For storing name string buffers during parsing
    ident_buf       resb 32
    ident_len       resq 1
    ; For storing method name during parse_postfix
    method_buf      resb 32
    method_len      resq 1
    ; Label counter for control flow
    label_counter   resd 1
    ; Vreg to struct type_id mapping (for field access)
    vreg_type_map   resd 65536

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
    extern sym_is_mutable
    extern sym_get_offset
    extern sym_get_scope
    extern sym_set_private
    extern sym_count
    extern sym_remove_block_scope

    extern alloc_vreg
    extern emit_ir
    extern type_name_buf

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
    mov dword [label_counter], 0
    
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
    ; Allow keywords/statements to start next statement without newline
    ; (e.g., after if/elif/else blocks)
    cmp eax, TOK_TYPE
    je .loop
    cmp eax, TOK_IDENT
    je .loop
    cmp eax, TOK_OUTPUT
    je .loop
    cmp eax, TOK_CONST
    je .loop
    cmp eax, TOK_STRUCT
    je .loop
    cmp eax, TOK_ENUM
    je .loop
    cmp eax, TOK_IF
    je .loop
    cmp eax, TOK_FOR
    je .loop
    cmp eax, TOK_WHILE
    je .loop
    cmp eax, TOK_EACH
    je .loop
    cmp eax, TOK_REPEAT
    je .loop
    cmp eax, TOK_RETURN
    je .loop
    cmp eax, TOK_PASS
    je .loop
    cmp eax, TOK_STOP
    je .loop
    cmp eax, TOK_SKIP
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
    
    cmp eax, TOK_IF
    je .if_stmt
    
    cmp eax, TOK_FOR
    je .for_stmt
    
    cmp eax, TOK_WHILE
    je .while_stmt
    
    cmp eax, TOK_EACH
    je .each_stmt
    
    cmp eax, TOK_REPEAT
    je .repeat_stmt
    
    cmp eax, TOK_RETURN
    je .return_stmt
    
    cmp eax, TOK_PASS
    je .pass_stmt
    
    cmp eax, TOK_STOP
    je .stop_stmt
    
    cmp eax, TOK_SKIP
    je .skip_stmt
    
    ; Unknown statement — try as expression statement
    call parse_expr
    ret

.const_decl:
    call advance ; consume const
    mov eax, [current_token]
    cmp eax, TOK_IDENT
    jne expected_ident
    
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
    je dup_error
    cmp rax, -1
    je full_error
    
    mov r14, rax

    ; Check for _ prefix (but not __) → mark as private
    cmp qword [ident_len], 1
    jl .const_not_private
    cmp byte [ident_buf], '_'
    jne .const_not_private
    cmp qword [ident_len], 2
    jl .const_is_private
    cmp byte [ident_buf + 1], '_'
    je .const_not_private
.const_is_private:
    mov rdi, r14
    mov rsi, 1
    call sym_set_private
.const_not_private:
    
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
    jne expected_ident
    
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
    push rsi
    push rdx
    mov rcx, rdx
    lea rdi, [type_name_buf]
    cmp rcx, TYPE_NAME_BUF_SIZE - 1
    jle .field_name_ok
    mov rcx, TYPE_NAME_BUF_SIZE - 1
.field_name_ok:
    test rcx, rcx
    jz .field_name_done
    xor r8, r8
.field_name_copy:
    movzx rax, byte [rsi + r8]
    mov [rdi + r8], al
    inc r8
    cmp r8, rcx
    jl .field_name_copy
.field_name_done:
    mov byte [rdi + rcx], 0
    mov r8, rcx ; save length
    pop rdx
    pop rsi
    call advance ; consume IDENT
    
    mov edi, TOK_NEWLINE
    call expect
    
    ; Add field
    mov rdi, r12 ; struct_type_id
    lea rsi, [type_name_buf] ; field_name_ptr (stable copy)
    mov rdx, r8 ; field_name_len
    mov rcx, r14 ; field_type_id
    mov r8, r13 ; field_offset
    extern type_struct_add_field
    extern type_struct_find_field
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

    ; Check for _ prefix → mark as private
    cmp qword [ident_len], 1
    jl .enum_not_private
    cmp byte [ident_buf], '_'
    jne .enum_not_private
    cmp qword [ident_len], 2
    jl .enum_is_private
    cmp byte [ident_buf + 1], '_'
    je .enum_not_private
.enum_is_private:
    mov rdi, r13
    mov rsi, 1
    call sym_set_private
.enum_not_private:
    
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

; ============ If/Elsif/Else ============
.if_stmt:
    call advance ; consume 'if'
    call parse_expr ; condition → rax=vreg, rdx=type
    mov r12, rax ; condition vreg

    mov edi, TOK_COLON
    call expect ; consume ':'

    ; Generate end label (shared by all branches)
    call gen_label
    push rax ; save end_label on stack

    ; Generate else label
    call gen_label
    mov r14, rax ; r14 = else_label

    ; Emit JCC to else_label if condition != true (COND_NE)
    ; The JCC codegen already does CMP reg, 1 before the jump
    mov rdi, r14       ; target label
    mov rsi, COND_NE   ; condition code
    mov rcx, r12       ; condition vreg to test
    call emit_jcc

    ; Parse then body
    call parse_block

    ; Emit JMP to end_label (skip else branches)
    mov rdi, [rsp] ; end_label from stack
    call emit_jmp

    ; Check for elif/else
.if_chain:
    mov eax, [current_token]
    cmp eax, TOK_ELIF
    je .elif_branch
    cmp eax, TOK_ELSE
    je .else_branch
    ; No else — emit else_label and end_label
    mov rdi, r14
    call emit_label
    pop rdi ; end_label
    call emit_label
    ret

.elif_branch:
    ; Emit JMP to end_label (skip remaining branches)
    mov rdi, [rsp] ; end_label from stack
    call emit_jmp

    ; Emit else_label (this elif's entry point)
    mov rdi, r14
    call emit_label

    call advance ; consume 'elif'
    call parse_expr ; elif condition
    mov r12, rax

    mov edi, TOK_COLON
    call expect

    ; Generate next else label
    call gen_label
    mov r14, rax

    ; JCC to next else if condition false
    ; The JCC codegen already does CMP reg, 1 before the jump
    mov rdi, r14
    mov rsi, COND_NE
    mov rcx, r12
    call emit_jcc

    ; Parse elif body
    call parse_block
    jmp .if_chain

.else_branch:
    ; Emit JMP to end_label
    mov rdi, [rsp]
    call emit_jmp

    ; Emit else_label
    mov rdi, r14
    call emit_label

    call advance ; consume 'else'
    mov edi, TOK_COLON
    call expect

    ; Parse else body
    call parse_block

    ; Emit end_label
    pop rdi ; end_label
    call emit_label
    ret

; ============ For Loop ============
.for_stmt:
    call advance ; consume 'for'

    ; Save loop variable name
    mov eax, [current_token]
    cmp eax, TOK_IDENT
    jne expected_ident
    call save_ident
    call advance ; consume IDENT

    mov edi, TOK_IN
    call expect ; consume 'in'

    ; Parse start expression
    call parse_expr
    push rax ; start vreg

    ; Expect '..'
    mov eax, [current_token]
    cmp eax, TOK_DOTDOT
    jne .for_syntax_err
    call advance ; consume '..'

    ; Parse end expression
    call parse_expr
    mov r13, rax ; end vreg

    ; Store end value into a hidden variable __for_end
    ; so the register allocator sees fresh vregs each iteration
    ; (avoids end vreg spanning the entire loop body)
    push r13
    lea rdi, [str_for_end]
    mov rsi, 9 ; len("_for_end")
    mov rdx, TYPE_INT
    call determine_scope
    mov rcx, rax
    mov rdx, TYPE_INT
    lea rdi, [str_for_end]
    mov rsi, 9
    call sym_add
    mov r14, rax ; end symbol index
    mov rdi, r14
    mov rsi, 1
    call sym_set_mutable
    mov rdi, r14
    mov rsi, 1
    call sym_set_init
    pop r13 ; end vreg

    ; Store end value to __for_end variable
    mov rdi, r14
    call sym_get_offset
    mov r9, rax
    mov rcx, r13 ; end vreg
    mov rdi, IR_STORE_VAR
    mov rsi, TYPE_INT
    xor rdx, rdx
    xor r8, r8
    xor r10, r10
    call emit_ir

    mov edi, TOK_COLON
    call expect

    ; Declare loop variable as mutable int
    push r14 ; save end symbol index
    mov rdi, ident_buf
    mov rsi, [ident_len]
    mov rdx, TYPE_INT
    call determine_scope
    mov rcx, rax
    mov rdx, TYPE_INT
    mov rdi, ident_buf
    mov rsi, [ident_len]
    call sym_add
    mov r15, rax ; loop symbol index

    ; Check for _ prefix → mark as private
    cmp qword [ident_len], 1
    jl .for_not_private
    cmp byte [ident_buf], '_'
    jne .for_not_private
    cmp qword [ident_len], 2
    jl .for_is_private
    cmp byte [ident_buf + 1], '_'
    je .for_not_private
.for_is_private:
    mov rdi, r15
    mov rsi, 1
    call sym_set_private
.for_not_private:

    mov rdi, r15
    mov rsi, 1
    call sym_set_mutable
    mov rdi, r15
    mov rsi, 1
    call sym_set_init
    pop r14 ; restore end symbol index

    ; Store start value to loop variable
    pop rcx ; start vreg
    push r14 ; save end symbol index
    mov rdi, r15
    call sym_get_offset
    mov r9, rax
    mov rdi, IR_STORE_VAR
    mov rsi, TYPE_INT
    xor rdx, rdx
    xor r8, r8
    xor r10, r10
    call emit_ir
    pop r14

    ; Generate labels
    call gen_label
    push rax ; loop_start
    call gen_label
    push rax ; loop_end

    ; Emit loop_start label
    mov rdi, [rsp + 8]
    call emit_label

    ; Load loop variable (fresh vreg each iteration)
    call alloc_vreg
    mov rbx, rax
    mov rdi, r15
    call sym_get_offset
    mov r9, rax
    mov rdi, IR_LOAD_VAR
    mov rsi, TYPE_INT
    mov rdx, rbx
    xor rcx, rcx
    xor r8, r8
    xor r10, r10
    call emit_ir

    ; Load end value from __for_end (fresh vreg each iteration)
    push rbx ; save loop var vreg
    call alloc_vreg
    mov r12, rax
    mov rdi, r14
    call sym_get_offset
    mov r9, rax
    mov rdi, IR_LOAD_VAR
    mov rsi, TYPE_INT
    mov rdx, r12
    xor rcx, rcx
    xor r8, r8
    xor r10, r10
    call emit_ir
    pop rbx ; restore loop var vreg

    ; Compare: loop_var < end
    call alloc_vreg
    push rax
    mov rdi, IR_CMP_BOOL
    mov rsi, TYPE_BOOL
    mov rdx, [rsp]
    mov rcx, rbx ; loop var vreg
    mov r8, r12  ; end value vreg
    xor r9, r9
    mov r10, COND_LT
    call emit_ir

    ; JCC to loop_end if NOT (loop_var < end)
    mov rdi, [rsp + 8] ; loop_end
    mov rsi, COND_NE
    pop rcx ; cmp result vreg
    call emit_jcc

    ; Parse loop body
    call parse_block

    ; Increment: i = i + 1
    call alloc_vreg
    mov rbx, rax
    mov rdi, r15
    call sym_get_offset
    mov r9, rax
    mov rdi, IR_LOAD_VAR
    mov rsi, TYPE_INT
    mov rdx, rbx
    xor rcx, rcx
    xor r8, r8
    xor r10, r10
    call emit_ir

    call alloc_vreg
    push rax
    mov rdi, IR_LOAD_IMM
    mov rsi, TYPE_INT
    mov rdx, [rsp]
    xor rcx, rcx
    xor r8, r8
    mov r9, 1
    xor r10, r10
    call emit_ir

    call alloc_vreg
    push rax
    mov rdi, IR_ADD
    mov rsi, TYPE_INT
    mov rdx, [rsp]
    mov rcx, rbx
    mov r8, [rsp + 8]
    xor r9, r9
    xor r10, r10
    call emit_ir

    mov rdi, r15
    call sym_get_offset
    mov r9, rax
    pop rcx
    add rsp, 8
    mov rdi, IR_STORE_VAR
    mov rsi, TYPE_INT
    xor rdx, rdx
    xor r8, r8
    xor r10, r10
    call emit_ir

    ; JMP back to loop_start
    mov rdi, [rsp + 8]
    call emit_jmp

    ; Emit loop_end label
    pop rdi
    pop rax
    call emit_label
    ret

.for_syntax_err:
    mov rdi, err_syntax
    jmp compile_error

; ============ While Loop ============
.while_stmt:
    call advance ; consume 'while'

    ; Generate loop start and end labels
    call gen_label
    push rax ; loop_start on stack
    call gen_label
    push rax ; loop_end on stack

    ; Emit loop_start label
    mov rdi, [rsp + 8] ; loop_start
    call emit_label

    ; Parse condition
    call parse_expr
    mov r12, rax ; condition vreg

    mov edi, TOK_COLON
    call expect

    ; JCC to loop_end if condition false
    ; The JCC codegen already does CMP reg, 1 before the jump
    mov rdi, [rsp] ; loop_end (top of stack)
    mov rsi, COND_NE
    mov rcx, r12
    call emit_jcc

    ; Parse loop body
    call parse_block

    ; JMP back to loop_start
    mov rdi, [rsp + 8]
    call emit_jmp

    ; Emit loop_end label
    pop rdi ; loop_end
    pop rax ; loop_start (discard)
    call emit_label
    ret

; ============ Each Loop ============
.each_stmt:
    call advance ; consume 'each'
    mov edi, TOK_IDENT
    call expect ; element variable
    mov edi, TOK_IN
    call expect
    call parse_expr ; collection expression
    mov edi, TOK_COLON
    call expect
    call .skip_block
    ret

; ============ Repeat Loop ============
.repeat_stmt:
    call advance ; consume 'repeat'
    call parse_expr ; count expression
    mov edi, TOK_COLON
    call expect
    call .skip_block
    ret

; ============ Return ============
.return_stmt:
    call advance ; consume 'return'
    mov eax, [current_token]
    cmp eax, TOK_NEWLINE
    je .return_void
    cmp eax, TOK_EOF
    je .return_void
    call parse_expr ; return value in rax
    ; Emit IR_RET with return value vreg
    push rax
    mov rdi, IR_RET
    xor rsi, rsi        ; type = void (return type)
    xor rdx, rdx        ; dst = 0 (void)
    mov rcx, rax        ; src1 = return value vreg
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir
    pop rax
    ret
.return_void:
    ; Emit IR_RET with no return value
    mov rdi, IR_RET
    xor rsi, rsi
    xor rdx, rdx
    xor rcx, rcx
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir
    ret

; ============ Pass ============
.pass_stmt:
    call advance ; consume 'pass'
    ret

; ============ Stop ============
.stop_stmt:
    call advance ; consume 'stop'
    ret

; ============ Skip ============
.skip_stmt:
    call advance ; consume 'skip'
    ret

; Helper: skip an indented block (consume until DEDENT)
.skip_block:
    mov eax, [current_token]
    cmp eax, TOK_INDENT
    jne .skip_single
    call advance ; consume INDENT
.skip_loop:
    mov eax, [current_token]
    cmp eax, TOK_DEDENT
    je .skip_done
    cmp eax, TOK_EOF
    je .skip_done
    call parse_stmt
    jmp .skip_loop
.skip_done:
    call advance ; consume DEDENT
.skip_single:
    ret

.explicit_decl:
    ; explicit_decl: type_expr [ "[" type_expr "]" ] <IDENT> [ "=" expr ]
    mov r12, [tok_ival] ; Save type ID
    call advance ; consume TYPE
    
    mov eax, [current_token]
    cmp eax, TOK_LBRACKET
    jne .no_size_suffix
    ; Check if this is a parameterized type (seq[T], dict[T], tup[T...])
    cmp r12, TYPE_SEQ
    je .param_type
    cmp r12, TYPE_DICT
    je .param_type
    cmp r12, TYPE_TUP
    je .param_type
    ; bool and byte do not accept size parameters (§4.1)
    cmp r12, TYPE_BOOL
    je .no_size_suffix
    cmp r12, TYPE_BYTE
    je .no_size_suffix
    call advance ; consume '['
    ; Parse and record the size (for now, skip tokens until ']')
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
    jmp .no_size_suffix

.param_type:
    ; Parameterized type: seq[T], dict[T], arr[T, N], tup[T...]
    call advance ; consume '['
    ; Parse the element type
    mov eax, [current_token]
    cmp eax, TOK_TYPE
    jne .param_type_err
    mov r13, [tok_ival] ; element type ID
    call advance ; consume element type
    ; Check if this is arr[T, N] — needs a second parameter
    cmp r12, TYPE_ARR
    jne .param_type_close
    ; Parse comma and size
    mov edi, TOK_COMMA
    call expect ; consume ','
    mov eax, [current_token]
    cmp eax, TOK_INT_LIT
    jne .param_type_err
    mov r14, [tok_ival] ; array size
    call advance ; consume size
.param_type_close:
    mov edi, TOK_RBRACKET
    call expect ; consume ']'
    ; Register a new type with the element type as aux_data
    ; For arr, also store the size
    jmp .no_size_suffix

.param_type_err:
    mov rdi, err_syntax
    jmp compile_error
    
.no_size_suffix:
    xor r13, r13 ; r13 = is_mutable (0 by default)
    mov eax, [current_token]
    cmp eax, TOK_IDENT
    jne expected_ident
    
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
    je dup_error
    cmp rax, -1
    je full_error

    mov r14, rax ; Save symbol index

    ; Check for _ prefix (but not __) → mark as private
    cmp qword [ident_len], 1
    jl .not_private
    cmp byte [ident_buf], '_'
    jne .not_private
    ; Check it's not __ prefix (block scope)
    cmp qword [ident_len], 2
    jl .is_private_name
    cmp byte [ident_buf + 1], '_'
    je .not_private ; __ is block scope, not private
.is_private_name:
    mov rdi, r14
    mov rsi, 1
    call sym_set_private
.not_private:
    
    ; Declarations are always immutable. Mutability is set retroactively
    ; when `:name =` appears later in the scope (design.md §3.1).
    ; r13 is always 0 here; no need to set mutable.

    ; Check if there is an initializer
    mov eax, [current_token]
    cmp eax, TOK_ASSIGN
    jne .no_initializer
    
    call advance ; consume '='

    ; Check if this is a seq initializer: seq[T] nums = [1, 2, 3]
    cmp r12, TYPE_SEQ
    jne .not_seq_init
    mov eax, [current_token]
    cmp eax, TOK_LBRACKET
    jne .not_seq_init
    ; This is a seq initializer
    call .parse_seq_initializer
    jmp .type_ok

.not_seq_init:
    ; Check if this is an arr initializer: arr[T, N] a = [1, 2, 3]
    cmp r12, TYPE_ARR
    jne .not_arr_init
    mov eax, [current_token]
    cmp eax, TOK_LBRACKET
    jne .not_arr_init
    call .parse_arr_initializer
    jmp .type_ok

.not_arr_init:
    ; Check if this is a dict initializer: dict[T] d = [:]
    cmp r12, TYPE_DICT
    jne .not_dict_init
    mov eax, [current_token]
    cmp eax, TOK_LBRACKET
    jne .not_dict_init
    ; Check for [:] pattern
    call advance ; consume '['
    mov eax, [current_token]
    cmp eax, TOK_COLON
    jne .dict_init_err
    call advance ; consume ':'
    mov edi, TOK_RBRACKET
    call expect ; consume ']'
    ; Emit IR_DICT_NEW with capacity 16
    call alloc_vreg
    mov r15, rax
    mov rdi, IR_DICT_NEW
    mov rsi, TYPE_DICT
    mov rdx, r15       ; dst = dict vreg
    xor rcx, rcx       ; src1 = 0
    xor r8, r8         ; src2 = 0
    mov r9, DICT_INITIAL_CAPACITY  ; imm = initial capacity
    xor r10, r10
    call emit_ir
    mov rax, r15
    mov rdx, TYPE_DICT
    jmp .type_ok

.dict_init_err:
    mov rdi, err_syntax
    jmp compile_error

.not_dict_init:
    call parse_expr ; rax = vreg, rdx = type
    
    ; Type check
    cmp rdx, r12
    je .type_ok
    cmp r12, TYPE_BYTE
    jne type_error
    cmp rdx, TYPE_STR
    je type_error ; byte from str not yet supported (need single-char detection)
    cmp rdx, TYPE_CHAR
    je .type_ok
    cmp rdx, TYPE_INT
    je .type_ok
    jmp type_error

; Helper: parse seq initializer [1, 2, 3]
; Returns: rax = seq vreg, rdx = TYPE_SEQ
.parse_seq_initializer:
    push r12
    push r13
    push r14
    push r15

    call advance ; consume '['

    ; Emit IR_SEQ_NEW with capacity 8, element size 8
    call alloc_vreg
    mov r15, rax       ; r15 = seq vreg (callee-saved, preserved across loop)
    mov rdi, IR_SEQ_NEW
    mov rsi, TYPE_SEQ
    mov rdx, r15       ; dst = seq vreg
    xor rcx, rcx       ; src1 = 0
    xor r8, r8         ; src2 = 0
    mov r9, 8          ; imm = initial capacity
    mov r10, 8         ; aux = element size
    call emit_ir

.seq_init_loop:
    mov eax, [current_token]
    cmp eax, TOK_RBRACKET
    je .seq_init_end
    cmp eax, TOK_EOF
    je .seq_init_end

    ; Parse element value
    call parse_expr    ; rax = elem vreg
    mov r14, rax       ; save elem vreg

    ; Emit IR_SEQ_PUSH
    mov rdi, IR_SEQ_PUSH
    mov rsi, TYPE_INT  ; element type
    xor rdx, rdx       ; dst = 0 (void)
    mov rcx, r15       ; src1 = seq vreg
    mov r8, r14        ; src2 = elem vreg
    mov r9, SEQ_ELEMENT_SIZE  ; imm = element size
    xor r10, r10
    call emit_ir

    ; Check for comma
    mov eax, [current_token]
    cmp eax, TOK_COMMA
    jne .seq_init_end
    call advance ; consume comma
    jmp .seq_init_loop

.seq_init_end:
    mov edi, TOK_RBRACKET
    call expect ; consume ']'

    mov rax, r15       ; return seq vreg
    mov rdx, TYPE_SEQ

    pop r15
    pop r14
    pop r13
    pop r12
    ret

.parse_arr_initializer:
    ; Parse arr[T, N] initializer: [v1, v2, ..., vN]
    ; r14 = array size (from param_type parsing)
    ; r13 = element type (from param_type parsing)
    push r12
    push r13
    push r14
    push r15

    ; r14 already has the array size from param_type
    ; We need to get it from the type registration
    ; For now, use a fixed element size of 8
    call advance ; consume '['

    ; Calculate total size: N * elem_size
    mov rax, r14
    imul rax, SEQ_ELEMENT_SIZE
    mov r12, rax        ; r12 = total size in bytes

    ; Emit IR_ARR_NEW
    call alloc_vreg
    mov r15, rax        ; r15 = array vreg
    mov rdi, IR_ARR_NEW
    mov rsi, TYPE_ARR
    mov rdx, r15        ; dst
    xor rcx, rcx        ; src1 = 0
    xor r8, r8          ; src2 = 0
    mov r9, r12         ; imm = total size
    mov r10, SEQ_ELEMENT_SIZE  ; aux = element size
    call emit_ir

    xor r13, r13        ; r13 = element index

.arr_init_loop:
    mov eax, [current_token]
    cmp eax, TOK_RBRACKET
    je .arr_init_end
    cmp eax, TOK_EOF
    je .arr_init_end

    ; Parse element value
    call parse_expr
    push rax            ; save elem vreg

    ; Emit IR_ARR_STORE: arr[index] = value
    ; We need the index as a constant. Emit IR_LOAD_IMM for the index.
    call alloc_vreg
    mov rbx, rax        ; rbx = index vreg
    mov rdi, IR_LOAD_IMM
    mov rsi, TYPE_INT
    mov rdx, rbx
    xor rcx, rcx
    xor r8, r8
    mov r9, r13         ; imm = element index
    xor r10, r10
    call emit_ir

    ; Now emit IR_ARR_STORE
    ; IR record: src1=arr_vreg, src2=index_vreg, aux=elem_size|(value_vreg<<16)
    pop rax             ; recover elem vreg
    shl eax, 16
    or eax, SEQ_ELEMENT_SIZE
    mov rdi, IR_ARR_STORE
    mov rsi, TYPE_ARR
    xor rdx, rdx        ; dst = 0 (void)
    mov rcx, r15        ; src1 = arr vreg
    mov r8, rbx         ; src2 = index vreg
    mov r9, 0           ; imm = 0
    mov r10, rax        ; aux = elem_size | (value_vreg << 16)
    call emit_ir

    ; Check for comma
    mov eax, [current_token]
    cmp eax, TOK_COMMA
    jne .arr_init_end
    call advance ; consume comma
    inc r13
    jmp .arr_init_loop

.arr_init_end:
    mov edi, TOK_RBRACKET
    call expect ; consume ']'

    mov rax, r15        ; return arr vreg
    mov rdx, TYPE_ARR

    pop r15
    pop r14
    pop r13
    pop r12
    ret

.byte_from_str:
    ; byte from str: dereference the string pointer to get the first byte
    ; The IR_LOAD_STR already loaded the string pointer into a vreg (in rax).
    ; Emit IR_LOAD_DEREF_BYTE to load byte at [ptr + 0].
    push rax
    mov rbx, rax        ; save string pointer vreg
    mov rdi, IR_LOAD_DEREF_BYTE
    mov rsi, TYPE_BYTE
    mov rdx, rbx        ; dst = reuse the same vreg (overwrite pointer with byte)
    mov rcx, rbx        ; src1 = pointer vreg
    xor r8, r8          ; imm = 0 (offset)
    xor r9, r9
    xor r10, r10
    call emit_ir
    pop rax
    jmp .type_ok
.type_ok:
    
    ; Emit IR_STORE_VAR
    push rax
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

.mutation:
    ; mutation: ":" <IDENT> "=" expr  OR  ":" <IDENT> "." method "(" args ")"
    call advance ; consume ':'
    mov eax, [current_token]
    cmp eax, TOK_IDENT
    jne expected_ident
    
    ; Lookup variable
    mov rdi, [tok_str_ptr]
    mov rsi, [tok_str_len]
    call sym_lookup
    cmp rax, -1
    je .undef_error
    
    mov r14, rax ; Save symbol index
    ; Per design.md §3.1: writing `:name =` makes the variable mutable.
    ; Mark it mutable now (retroactive mutability).
    mov rdi, r14
    mov rsi, 1
    call sym_set_mutable
    call advance ; consume IDENT

    ; Check if this is a method call: :name.method(...)
    mov eax, [current_token]
    cmp eax, TOK_DOT
    je .mutation_method

    ; Check if this is a bracket index: :name[i] = v
    cmp eax, TOK_LBRACKET
    je .mutation_bracket

    ; Check for compound assignment operators: +=, -=, *=, /=, %=, &=, |=, ^=, <<=, >>=
    cmp eax, TOK_PLUS_EQ
    je .compound_assign
    cmp eax, TOK_MINUS_EQ
    je .compound_assign
    cmp eax, TOK_STAR_EQ
    je .compound_assign
    cmp eax, TOK_SLASH_EQ
    je .compound_assign
    cmp eax, TOK_MOD_EQ
    je .compound_assign
    cmp eax, TOK_AND_EQ
    je .compound_assign
    cmp eax, TOK_OR_EQ
    je .compound_assign
    cmp eax, TOK_XOR_EQ
    je .compound_assign
    cmp eax, TOK_LSHIFT_EQ
    je .compound_assign
    cmp eax, TOK_RSHIFT_EQ
    je .compound_assign

    ; Otherwise, expect assignment: :name = expr
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
    jne type_error
    cmp rdx, TYPE_STR
    je .mut_type_ok
    cmp rdx, TYPE_CHAR
    je .mut_type_ok
    cmp rdx, TYPE_INT
    je .mut_type_ok
    jmp type_error
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

.compound_assign:
    ; Compound assignment: :name op= expr
    ; Desugars to: :name = name op expr
    ; r14 = symbol index, current_token = compound op

    ; Save compound operator token
    mov r12d, [current_token]
    call advance ; consume compound operator

    ; Load current variable value into a vreg
    call alloc_vreg
    mov r13, rax ; dst vreg for load

    mov rdi, r14
    call sym_get_offset
    mov r9, rax ; imm = offset

    mov rdi, r14
    call sym_get_type
    push rax ; save type for later

    mov rdi, IR_LOAD_VAR
    mov rsi, rax ; type
    mov rdx, r13 ; dst vreg
    xor rcx, rcx
    xor r8, r8
    xor r10, r10
    call emit_ir

    ; Parse RHS expression
    call parse_expr ; rax = rhs vreg, rdx = rhs type
    mov r15, rax ; rhs vreg

    ; Emit binary operation: dst = old_value op rhs
    call alloc_vreg
    push rax ; save result vreg

    ; Map compound operator to IR opcode
    cmp r12d, TOK_PLUS_EQ
    je .compound_add
    cmp r12d, TOK_MINUS_EQ
    je .compound_sub
    cmp r12d, TOK_STAR_EQ
    je .compound_mul
    cmp r12d, TOK_SLASH_EQ
    je .compound_div
    cmp r12d, TOK_MOD_EQ
    je .compound_mod
    cmp r12d, TOK_AND_EQ
    je .compound_and
    cmp r12d, TOK_OR_EQ
    je .compound_or
    cmp r12d, TOK_XOR_EQ
    je .compound_xor
    cmp r12d, TOK_LSHIFT_EQ
    je .compound_lshift
    cmp r12d, TOK_RSHIFT_EQ
    je .compound_rshift
    jmp .compound_unknown

.compound_add:
    mov rdi, IR_ADD
    jmp .compound_emit
.compound_sub:
    mov rdi, IR_SUB
    jmp .compound_emit
.compound_mul:
    mov rdi, IR_MUL
    jmp .compound_emit
.compound_div:
    mov rdi, IR_DIV
    jmp .compound_emit
.compound_mod:
    mov rdi, IR_MOD
    jmp .compound_emit
.compound_and:
    mov rdi, IR_AND
    jmp .compound_emit
.compound_or:
    mov rdi, IR_OR
    jmp .compound_emit
.compound_xor:
    mov rdi, IR_XOR
    jmp .compound_emit
.compound_lshift:
    mov rdi, IR_SHL
    jmp .compound_emit
.compound_rshift:
    mov rdi, IR_SHR
    jmp .compound_emit

.compound_emit:
    ; rdi = IR opcode
    pop rdx ; result vreg
    add rsp, 8 ; discard saved type (not needed for IR)
    mov rsi, TYPE_INT ; arithmetic is int-typed
    mov rcx, r13 ; src1 = old value vreg
    mov r8, r15 ; src2 = rhs vreg
    xor r9, r9
    xor r10, r10
    push rdx ; save result vreg
    call emit_ir

    ; Store result back to variable
    mov rdi, r14
    call sym_get_type
    mov r12, rax ; type

    mov rdi, r14
    call sym_get_offset
    mov r9, rax ; offset

    pop rcx ; result vreg
    mov rdi, IR_STORE_VAR
    mov rsi, r12
    xor rdx, rdx
    xor r8, r8
    xor r10, r10
    call emit_ir

    ; Mark as initialized
    mov rdi, r14
    mov rsi, 1
    call sym_set_init
    ret

.compound_unknown:
    add rsp, 16 ; clean up stack
    mov rdi, err_syntax
    jmp compile_error

.mutation_method:
    ; :name.method(args) — load variable, then dispatch method
    ; First, load the variable to get its vreg
    push rbx
    push r12
    push r13
    push r14
    push r15

    call alloc_vreg
    mov r15, rax ; save vreg

    mov rdi, r14 ; sym_idx is in r14
    push r14 ; save sym_idx
    call sym_get_offset
    mov r9, rax ; imm = offset

    mov rdi, [rsp] ; sym_idx
    call sym_get_type
    mov r13, rax ; type
    mov r12, r15 ; vreg

    mov rdi, IR_LOAD_VAR
    mov rsi, r13
    mov rdx, r12
    xor rcx, rcx
    xor r8, r8
    xor r10, r10
    call emit_ir

    pop r14 ; restore sym_idx (not needed further, but clean stack)

    ; Now parse the .method() chain
    ; r12 = vreg, r13 = type
.mut_method_loop:
    mov eax, [current_token]
    cmp eax, TOK_DOT
    jne .mut_method_done

    call advance ; consume '.'

    mov eax, [current_token]
    cmp eax, TOK_IDENT
    je .mut_method_name_ok
    cmp eax, TOK_LEN
    je .mut_method_name_ok
    jmp .mut_method_type_err

.mut_method_name_ok:
    ; Copy method name into method_buf
    mov rsi, [tok_str_ptr]
    mov rcx, [tok_str_len]
    cmp rcx, 31
    jle .mut_mlen_ok
    mov rcx, 31
.mut_mlen_ok:
    mov [method_len], rcx
    lea rdi, [method_buf]
    push rcx
    test rcx, rcx
    jz .mut_mcopy_done
.mut_mcopy:
    movzx rax, byte [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jnz .mut_mcopy
.mut_mcopy_done:
    pop rcx
    lea rdi, [method_buf]
    add rdi, rcx
    mov byte [rdi], 0

    call advance ; consume method name

    mov edi, TOK_LPAREN
    call expect ; consume '('

    ; Dispatch by type
    cmp r13, TYPE_SEQ
    je .mut_seq_dispatch
    jmp .mut_method_type_err

.mut_seq_dispatch:
    lea rdi, [str_push]
    call ident_is
    test rax, rax
    jnz .mut_seq_push
    lea rdi, [str_len_m]
    call ident_is
    test rax, rax
    jnz .mut_seq_len
    lea rdi, [str_get_m]
    call ident_is
    test rax, rax
    jnz .mut_seq_get
    lea rdi, [str_pop]
    call ident_is
    test rax, rax
    jnz .mut_seq_pop
    lea rdi, [str_insert]
    call ident_is
    test rax, rax
    jnz .mut_seq_insert
    lea rdi, [str_remove]
    call ident_is
    test rax, rax
    jnz .mut_seq_remove
    lea rdi, [str_reverse]
    call ident_is
    test rax, rax
    jnz .mut_seq_reverse
    lea rdi, [str_clear_m]
    call ident_is
    test rax, rax
    jnz .mut_seq_clear
    lea rdi, [str_reserve_m]
    call ident_is
    test rax, rax
    jnz .mut_seq_reserve
    jmp .mut_method_unknown_err

.mut_seq_push:
    call parse_expr ; parse value to push
    mov r14, rax    ; value vreg
    mov edi, TOK_RPAREN
    call expect ; consume ')'
    ; Emit IR_SEQ_PUSH
    mov rdi, IR_SEQ_PUSH
    mov rsi, TYPE_INT
    xor rdx, rdx       ; dst = 0 (void)
    mov rcx, r12       ; src1 = seq vreg
    mov r8, r14        ; src2 = value vreg
    mov r9, SEQ_ELEMENT_SIZE  ; imm = element size
    xor r10, r10
    call emit_ir
    jmp .mut_method_loop

.mut_seq_len:
    mov edi, TOK_RPAREN
    call expect ; consume ')'
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_SEQ_LEN
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r12    ; src1 = seq vreg
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_INT
    jmp .mut_method_loop

.mut_seq_get:
    call parse_expr ; parse index
    mov r14, rax    ; index vreg
    mov edi, TOK_RPAREN
    call expect ; consume ')'
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_SEQ_LOAD
    mov rsi, TYPE_INT
    mov rdx, rbx      ; dst
    mov rcx, r12      ; src1 = seq vreg
    mov r8, r14       ; src2 = index vreg
    mov r9, SEQ_ELEMENT_SIZE  ; element size
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_INT
    jmp .mut_method_loop

.mut_seq_pop:
    ; .pop() — emit IR_SEQ_POP
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_SEQ_POP
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r12
    xor r8, r8
    mov r9, 8
    xor r10, r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_INT
    jmp .mut_method_loop

.mut_seq_insert:
    ; .insert(index, value) — emit IR_SEQ_INSERT
    call parse_expr ; parse the index
    mov r14, rax    ; index vreg
    mov edi, TOK_COMMA
    call expect ; consume ','
    call parse_expr ; parse the value
    mov r15, rax    ; value vreg
    mov edi, TOK_RPAREN
    call expect ; consume ')'
    ; Emit IR_SEQ_INSERT
    mov rdi, IR_SEQ_INSERT
    mov rsi, TYPE_INT
    xor rdx, rdx       ; dst = 0 (void)
    mov rcx, r12       ; src1 = seq vreg
    mov r8, r14        ; src2 = index vreg
    mov r9, SEQ_ELEMENT_SIZE  ; imm = element size
    mov r10, r15       ; aux = value vreg
    call emit_ir
    jmp .mut_method_loop

.mut_seq_remove:
    ; .remove(index) — emit IR_SEQ_REMOVE
    call parse_expr ; parse the index
    mov r14, rax    ; index vreg
    mov edi, TOK_RPAREN
    call expect ; consume ')'
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_SEQ_REMOVE
    mov rsi, TYPE_INT
    mov rdx, rbx       ; dst
    mov rcx, r12       ; src1 = seq vreg
    mov r8, r14        ; src2 = index vreg
    mov r9, SEQ_ELEMENT_SIZE  ; imm = element size
    xor r10, r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_INT
    jmp .mut_method_loop

.mut_seq_reverse:
    ; .reverse() — void, mutates in place
    mov edi, TOK_RPAREN
    call expect
    mov rdi, IR_SEQ_REVERSE
    xor rsi, rsi
    xor rdx, rdx
    mov rcx, r12        ; seq vreg
    xor r8, r8
    mov r9, SEQ_ELEMENT_SIZE  ; element size
    xor r10, r10
    call emit_ir
    jmp .mut_method_loop

.mut_seq_clear:
    ; .clear() — void
    mov edi, TOK_RPAREN
    call expect
    mov rdi, IR_SEQ_CLEAR
    xor rsi, rsi
    xor rdx, rdx
    mov rcx, r12
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir
    jmp .mut_method_loop

.mut_seq_reserve:
    ; .reserve(n) — void
    call parse_expr
    mov r14, rax
    mov edi, TOK_RPAREN
    call expect
    mov rdi, IR_SEQ_RESERVE
    xor rsi, rsi
    xor rdx, rdx
    mov rcx, r12
    mov r8, r14
    xor r9, r9
    xor r10, r10
    call emit_ir
    jmp .mut_method_loop

.mut_method_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.mut_method_type_err:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rdi, err_type_mismatch
    jmp compile_error

.mut_method_unknown_err:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rdi, err_unknown_method
    jmp compile_error

.mutation_bracket:
    ; :name[index] = value — seq bracket write
    push r12
    push r13
    push r14
    push r15

    ; Load variable into vreg
    call alloc_vreg
    mov r15, rax

    mov rdi, r14
    push r14
    call sym_get_offset
    mov r9, rax

    mov rdi, [rsp]
    call sym_get_type
    mov r13, rax
    mov r12, r15

    mov rdi, IR_LOAD_VAR
    mov rsi, r13
    mov rdx, r12
    xor rcx, rcx
    xor r8, r8
    xor r10, r10
    call emit_ir

    pop r14

    ; Consume '['
    mov edi, TOK_LBRACKET
    call expect

    ; Parse index expression
    call parse_expr
    mov r14, rax

    ; Consume ']'
    mov edi, TOK_RBRACKET
    call expect

    ; Consume '='
    mov edi, TOK_ASSIGN
    call expect

    ; Parse value expression
    push r14
    call parse_expr
    mov r15, rax
    pop r14

    ; Emit IR_SEQ_STORE or IR_DICT_STORE based on type
    cmp r13, TYPE_DICT
    je .mutation_bracket_dict
    mov rdi, IR_SEQ_STORE
    mov rsi, TYPE_INT
    xor rdx, rdx
    mov rcx, r12
    mov r8, r14
    mov r9, 8
    mov r10, r15
    call emit_ir
    jmp .mutation_bracket_done

.mutation_bracket_dict:
    mov rdi, IR_DICT_STORE
    mov rsi, TYPE_INT
    xor rdx, rdx
    mov rcx, r12       ; dict vreg
    mov r8, r14        ; key vreg
    xor r9, r9
    mov r10, r15       ; value vreg
    call emit_ir

.mutation_bracket_done:
    pop r15
    pop r14
    pop r13
    pop r12
    ret

.undef_error:
    mov rdi, err_undef
    jmp compile_error

.mutation_not_allowed:
    mov rdi, err_immutable
    jmp compile_error

.ident_stmt:
    ; Could be type-inferred declaration: x = 5
    ; or illegal reassignment without ':': x = 5 (when x exists)
    mov rdi, [tok_str_ptr]
    mov rsi, [tok_str_len]
    call sym_lookup
    cmp rax, -1
    je .inferred_decl
    
    ; Variable exists. Check if it's mutable (from a prior :name = site).
    mov r14, rax ; Save symbol index
    mov rdi, r14
    call sym_is_mutable
    test rax, rax
    jz .immutable_reassign ; immutable → error

    ; Variable is mutable — treat as reassignment (same as .mutation but no ':' needed)
    call advance ; consume IDENT

    ; Check for compound assignment operators
    mov eax, [current_token]
    cmp eax, TOK_PLUS_EQ
    je .ident_compound
    cmp eax, TOK_MINUS_EQ
    je .ident_compound
    cmp eax, TOK_STAR_EQ
    je .ident_compound
    cmp eax, TOK_SLASH_EQ
    je .ident_compound
    cmp eax, TOK_MOD_EQ
    je .ident_compound
    cmp eax, TOK_AND_EQ
    je .ident_compound
    cmp eax, TOK_OR_EQ
    je .ident_compound
    cmp eax, TOK_XOR_EQ
    je .ident_compound
    cmp eax, TOK_LSHIFT_EQ
    je .ident_compound
    cmp eax, TOK_RSHIFT_EQ
    je .ident_compound

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
    je .ident_reassign_type_ok
    jmp type_error
.ident_reassign_type_ok:
    ; Emit IR_STORE_VAR
    mov rdi, r14
    call sym_get_offset
    mov r9, rax ; imm = offset
    pop rcx ; src1 vreg
    mov rdi, IR_STORE_VAR
    mov rsi, rdx ; type
    xor rdx, rdx
    xor r8, r8
    xor r10, r10
    call emit_ir
    ret

.immutable_reassign:
    mov rdi, err_sigil_req
    jmp compile_error

.ident_compound:
    ; Compound assignment for mutable variable without ':' prefix
    ; r14 = symbol index, current_token = compound op
    ; Same logic as .compound_assign but skips the ':' consumption

    ; Save compound operator token
    mov r12d, [current_token]
    call advance ; consume compound operator

    ; Load current variable value into a vreg
    call alloc_vreg
    mov r13, rax ; dst vreg for load

    mov rdi, r14
    call sym_get_offset
    mov r9, rax ; imm = offset

    mov rdi, r14
    call sym_get_type
    push rax ; save type

    mov rdi, IR_LOAD_VAR
    mov rsi, rax ; type
    mov rdx, r13 ; dst vreg
    xor rcx, rcx
    xor r8, r8
    xor r10, r10
    call emit_ir

    ; Parse RHS expression
    call parse_expr ; rax = rhs vreg, rdx = rhs type
    mov r15, rax ; rhs vreg

    ; Emit binary operation
    call alloc_vreg
    push rax ; save result vreg

    ; Map compound operator to IR opcode
    cmp r12d, TOK_PLUS_EQ
    je .ident_compound_add
    cmp r12d, TOK_MINUS_EQ
    je .ident_compound_sub
    cmp r12d, TOK_STAR_EQ
    je .ident_compound_mul
    cmp r12d, TOK_SLASH_EQ
    je .ident_compound_div
    cmp r12d, TOK_MOD_EQ
    je .ident_compound_mod
    cmp r12d, TOK_AND_EQ
    je .ident_compound_and
    cmp r12d, TOK_OR_EQ
    je .ident_compound_or
    cmp r12d, TOK_XOR_EQ
    je .ident_compound_xor
    cmp r12d, TOK_LSHIFT_EQ
    je .ident_compound_lshift
    cmp r12d, TOK_RSHIFT_EQ
    je .ident_compound_rshift
    jmp .compound_unknown

.ident_compound_add:
    mov rdi, IR_ADD
    jmp .ident_compound_emit
.ident_compound_sub:
    mov rdi, IR_SUB
    jmp .ident_compound_emit
.ident_compound_mul:
    mov rdi, IR_MUL
    jmp .ident_compound_emit
.ident_compound_div:
    mov rdi, IR_DIV
    jmp .ident_compound_emit
.ident_compound_mod:
    mov rdi, IR_MOD
    jmp .ident_compound_emit
.ident_compound_and:
    mov rdi, IR_AND
    jmp .ident_compound_emit
.ident_compound_or:
    mov rdi, IR_OR
    jmp .ident_compound_emit
.ident_compound_xor:
    mov rdi, IR_XOR
    jmp .ident_compound_emit
.ident_compound_lshift:
    mov rdi, IR_SHL
    jmp .ident_compound_emit
.ident_compound_rshift:
    mov rdi, IR_SHR
    jmp .ident_compound_emit

.ident_compound_emit:
    pop rdx ; result vreg
    add rsp, 8 ; discard saved type
    mov rsi, TYPE_INT
    mov rcx, r13 ; src1 = old value
    mov r8, r15 ; src2 = rhs
    xor r9, r9
    xor r10, r10
    push rdx
    call emit_ir

    ; Store result back
    mov rdi, r14
    call sym_get_type
    mov r12, rax
    mov rdi, r14
    call sym_get_offset
    mov r9, rax
    pop rcx ; result vreg
    mov rdi, IR_STORE_VAR
    mov rsi, r12
    xor rdx, rdx
    xor r8, r8
    xor r10, r10
    call emit_ir
    ret

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

    ; Check for _ prefix → mark as private
    cmp qword [ident_len], 1
    jl .inferred_not_private
    cmp byte [ident_buf], '_'
    jne .inferred_not_private
    cmp qword [ident_len], 2
    jl .inferred_is_private
    cmp byte [ident_buf + 1], '_'
    je .inferred_not_private
.inferred_is_private:
    mov rdi, r14
    mov rsi, 1
    call sym_set_private
.inferred_not_private:

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
    ; output_stmt: output "(" expr ["," expr]* ")"
    push r13     ; Preserve r13
    
    call advance ; consume output
    mov edi, TOK_LPAREN
    call expect ; consume '('
    
    ; Parse first argument
    call parse_expr ; rax = vreg, rdx = type
    mov r12, rdx ; Save type
    push rax     ; save expr vreg on stack

    ; Check if next token is comma (multi-arg) or rparen (single arg)
    mov eax, [current_token]
    cmp eax, TOK_COMMA
    je .multi_arg
    cmp eax, TOK_RPAREN
    je .single_arg

    ; Could be precision for float: "," integer_literal
    ; For now, treat as error
    jmp .single_arg

.single_arg:
    ; Single argument output
    mov edi, TOK_RPAREN
    call expect ; consume ')'
    pop rcx ; restore src1 vreg
    
    cmp r12, TYPE_INT
    je .single_out_int
    cmp r12, TYPE_FLOAT
    je .single_out_float
    cmp r12, TYPE_BOOL
    je .single_out_bool
    cmp r12, TYPE_STR
    je .single_out_str
    cmp r12, TYPE_CHAR
    je .single_out_char
    cmp r12, TYPE_BYTE
    je .single_out_int
    mov rdi, err_type_mismatch
    jmp compile_error

.single_out_int:
    mov rdi, IR_OUT_INT
    xor r9, r9
    jmp .single_emit_out
.single_out_float:
    mov rdi, IR_OUT_FLOAT
    xor r9, r9
    jmp .single_emit_out
.single_out_bool:
    mov rdi, IR_OUT_BOOL
    xor r9, r9
    jmp .single_emit_out
.single_out_str:
    mov rdi, IR_OUT_STR
    xor r9, r9
    jmp .single_emit_out
.single_out_char:
    mov rdi, IR_OUT_CHAR
    xor r9, r9
.single_emit_out:
    mov rsi, r12
    xor rdx, rdx
    xor r8, r8
    xor r10, r10
    call emit_ir
    pop r13
    ret

.multi_arg:
    ; We have multiple arguments. Emit the first one, then loop.
    pop rcx ; restore first arg vreg
    call .emit_output_for_type ; emit output for first arg

.arg_loop:
    ; Check if current token is comma
    mov eax, [current_token]
    cmp eax, TOK_COMMA
    jne .multi_arg_done
    call advance ; consume comma

    ; Emit space separator
    call .emit_space

    ; Parse next argument
    call parse_expr
    mov r12, rdx ; save type
    push rax     ; save vreg
    pop rcx      ; vreg
    call .emit_output_for_type
    jmp .arg_loop

.multi_arg_done:
    mov edi, TOK_RPAREN
    call expect ; consume ')'
    ; Emit newline
    call .emit_newline
    pop r13
    ret

; Helper: emit output IR for value in rcx, type in r12
.emit_output_for_type:
    cmp r12, TYPE_INT
    je .out_int
    cmp r12, TYPE_FLOAT
    je .out_float_no_prec
    cmp r12, TYPE_BOOL
    je .out_bool
    cmp r12, TYPE_STR
    je .out_str
    cmp r12, TYPE_CHAR
    je .out_char
    cmp r12, TYPE_BYTE
    je .out_int
    ret

; Helper: emit a space character output
.emit_space:
    ; Load space character (32) into a vreg
    call alloc_vreg
    push rax
    mov rdi, IR_LOAD_IMM
    mov rsi, TYPE_CHAR
    mov rdx, [rsp]
    xor rcx, rcx
    xor r8, r8
    mov r9, 32 ; space
    xor r10, r10
    call emit_ir
    ; Emit output for the space
    pop rcx
    mov rdi, IR_OUT_CHAR
    mov rsi, TYPE_CHAR
    xor rdx, rdx
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir
    ret

; Helper: emit a newline character output
.emit_newline:
    call alloc_vreg
    push rax
    mov rdi, IR_LOAD_IMM
    mov rsi, TYPE_CHAR
    mov rdx, [rsp]
    xor rcx, rcx
    xor r8, r8
    mov r9, 10 ; newline
    xor r10, r10
    call emit_ir
    pop rcx
    mov rdi, IR_OUT_CHAR
    mov rsi, TYPE_CHAR
    xor rdx, rdx
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir
    ret

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
.out_float_no_prec:
    xor r13, r13
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
    ret

; Parse Expression
parse_expr:
    jmp parse_comparison

parse_comparison:
    ; Comparison operators: == != < > <= >= (lowest precedence)
    ; Supports chained comparisons: a < b < c means (a < b) and (b < c)
    push rbx
    push r12
    push r13
    push r14
    push r15
    call parse_null_coalesce
    mov r12, rax
    mov r13, rdx
.loop:
    mov eax, [current_token]
    cmp eax, TOK_EQ
    je .do_cmp
    cmp eax, TOK_NE
    je .do_cmp
    cmp eax, TOK_LT
    je .do_cmp
    cmp eax, TOK_GT
    je .do_cmp
    cmp eax, TOK_LE
    je .do_cmp
    cmp eax, TOK_GE
    je .do_cmp
    jmp .done
.do_cmp:
    ; Save operator token type
    mov r14, rax
    call advance
    push r12
    call parse_null_coalesce
    mov r15, rax
    pop r12
    push r12
    push r15
    call alloc_vreg
    mov rbx, rax
    pop r15
    pop r12
    ; Emit IR_CMP_BOOL
    mov rdi, IR_CMP_BOOL
    mov rsi, TYPE_BOOL
    mov rdx, rbx
    mov rcx, r12
    mov r8, r15
    ; Map token to condition code
    ; Tokens: EQ=50, NE=51, LT=52, GT=53, LE=54, GE=55
    ; Conds:  EQ=0,  NE=1,  LT=2,  LE=3,  GT=4,  GE=5
    cmp r14, TOK_EQ
    je .cond_eq
    cmp r14, TOK_NE
    je .cond_ne
    cmp r14, TOK_LT
    je .cond_lt
    cmp r14, TOK_GT
    je .cond_gt
    cmp r14, TOK_LE
    je .cond_le
    cmp r14, TOK_GE
    je .cond_ge
    jmp .cond_done
.cond_eq:
    xor r10, r10       ; COND_EQ = 0
    jmp .cond_done
.cond_ne:
    mov r10, 1         ; COND_NE = 1
    jmp .cond_done
.cond_lt:
    mov r10, 2         ; COND_LT = 2
    jmp .cond_done
.cond_gt:
    mov r10, 4         ; COND_GT = 4
    jmp .cond_done
.cond_le:
    mov r10, 3         ; COND_LE = 3
    jmp .cond_done
.cond_ge:
    mov r10, 5         ; COND_GE = 5
.cond_done:
    xor r9, r9
    call emit_ir

    ; Check for chained comparison: another comparison op follows?
    ; If so, we need to AND this result with the next comparison.
    ; The right operand (r15) becomes the left operand of the next comparison.
    mov eax, [current_token]
    cmp eax, TOK_EQ
    je .chain
    cmp eax, TOK_NE
    je .chain
    cmp eax, TOK_LT
    je .chain
    cmp eax, TOK_GT
    je .chain
    cmp eax, TOK_LE
    je .chain
    cmp eax, TOK_GE
    je .chain
    ; No chain — single comparison, result is in rbx
    mov r12, rbx
    mov r13, TYPE_BOOL
    jmp .done

.chain:
    ; Chained comparison: rbx = (prev_left op prev_right), need (prev_right op next_right)
    ; Save current comparison result
    mov r12, rbx           ; r12 = result of first comparison
    ; prev_right (r15) becomes the new left operand
    push r12               ; save first result
    push r15               ; save new left operand

    ; Parse next comparison: r15 (prev_right) op next_operand
    mov r14, rax           ; save operator token
    call advance
    call parse_null_coalesce ; rax = next right operand
    mov r15, rax

    ; Emit second comparison: (prev_right) op (next_right)
    call alloc_vreg
    mov rbx, rax
    pop rcx                ; rcx = prev_right (left operand for second cmp)
    push rbx               ; save second result vreg
    mov rdi, IR_CMP_BOOL
    mov rsi, TYPE_BOOL
    mov rdx, rbx           ; dst
    ; rcx = left (prev_right)
    mov r8, r15            ; right (next_right)
    ; Map token to condition code
    cmp r14, TOK_EQ
    je .chain_cond_eq
    cmp r14, TOK_NE
    je .chain_cond_ne
    cmp r14, TOK_LT
    je .chain_cond_lt
    cmp r14, TOK_GT
    je .chain_cond_gt
    cmp r14, TOK_LE
    je .chain_cond_le
    cmp r14, TOK_GE
    je .chain_cond_ge
    jmp .chain_cond_done
.chain_cond_eq:
    xor r10, r10
    jmp .chain_cond_done
.chain_cond_ne:
    mov r10, 1
    jmp .chain_cond_done
.chain_cond_lt:
    mov r10, 2
    jmp .chain_cond_done
.chain_cond_gt:
    mov r10, 4
    jmp .chain_cond_done
.chain_cond_le:
    mov r10, 3
    jmp .chain_cond_done
.chain_cond_ge:
    mov r10, 5
.chain_cond_done:
    xor r9, r9
    call emit_ir

    ; AND the two comparison results
    call alloc_vreg
    mov rbx, rax           ; dst for AND
    pop r8                 ; r8 = second comparison result
    pop rcx                ; rcx = first comparison result
    push rbx               ; save AND result
    mov rdi, IR_BOOL_AND
    mov rsi, TYPE_BOOL
    mov rdx, rbx           ; dst
    ; rcx = first, r8 = second
    xor r9, r9
    xor r10, r10
    call emit_ir

    pop r12                ; r12 = AND result (new left for further chains)
    mov r13, TYPE_BOOL
    jmp .loop              ; check for more chained comparisons

.done:
    mov rax, r12
    mov rdx, r13
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

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
    mov r14, IR_NULL_COALESCE
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
    cmp r13, TYPE_BOOL
    jne .bool_type_err
    cmp rdx, TYPE_BOOL
    jne .bool_type_err
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
.bool_type_err:
    mov rdi, err_type_mismatch
    jmp compile_error

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
    cmp r13, TYPE_BOOL
    jne .bool_and_type_err
    cmp rdx, TYPE_BOOL
    jne .bool_and_type_err
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
.bool_and_type_err:
    mov rdi, err_type_mismatch
    jmp compile_error

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
    cmp r13, TYPE_STR
    je .str_concat
    mov r14, IR_ADD
    jmp .consume
.str_concat:
    mov r14, IR_STR_CONCAT
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
    cmp eax, TOK_TYPE
    je .type_cast
    cmp eax, TOK_MINUS
    je .unary_minus
    cmp eax, TOK_TILDE
    je .unary_tilde
    cmp eax, TOK_SCOPE
    je .scope_builtin
    cmp eax, TOK_LEN
    je .len_builtin
    cmp eax, TOK_LBRACKET
    je .array_literal
    
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
    ; Store type_id in vreg_type_map for struct field access
    push rax
    push rdx
    mov [vreg_type_map + rax * 4], edx
    pop rdx
    pop rax
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

; Unary minus: -expr
.unary_minus:
    call advance ; consume '-'
    call parse_postfix ; parse the operand
    push rax
    push rdx
    call alloc_vreg
    mov rbx, rax
    pop rdx  ; operand type
    pop rcx  ; operand vreg
    ; For int: emit IR_NEG; for float: negate via XOR with sign bit
    cmp rdx, TYPE_FLOAT
    je .unary_minus_float
    mov rdi, IR_NEG
    mov rsi, TYPE_INT
    mov rdx, rbx
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir
    mov rax, rbx
    mov rdx, TYPE_INT
    ret
.unary_minus_float:
    ; float negation: XOR sign bit via integer trick
    ; For now, emit 0.0 - operand
    ; Load 0.0 as float immediate
    push rcx ; save operand vreg
    call alloc_vreg
    push rax ; vreg for 0.0
    mov rdi, IR_LOAD_FIMM
    mov rsi, TYPE_FLOAT
    mov rdx, [rsp]
    xor rcx, rcx
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir
    ; result = 0.0 - operand
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_SUB
    mov rsi, TYPE_FLOAT
    mov rdx, rbx
    mov rcx, [rsp] ; 0.0 vreg
    mov r8, [rsp+8] ; operand vreg
    xor r9, r9
    xor r10, r10
    call emit_ir
    add rsp, 16
    mov rax, rbx
    mov rdx, TYPE_FLOAT
    ret

; Unary bitwise NOT: ~expr
.unary_tilde:
    call advance ; consume '~'
    call parse_postfix
    push rax
    push rdx
    call alloc_vreg
    mov rbx, rax
    pop rdx  ; operand type
    pop rcx  ; operand vreg
    ; NOT dst, src: mov dst, src; then not dst
    ; For simplicity, XOR with -1
    push rcx ; save operand vreg
    push rbx ; save dst vreg
    ; Load -1 as immediate
    call alloc_vreg
    push rax
    mov rdi, IR_LOAD_IMM
    mov rsi, TYPE_INT
    mov rdx, [rsp]
    xor rcx, rcx
    xor r8, r8
    mov r9, -1
    xor r10, r10
    call emit_ir
    ; result = operand XOR -1
    mov rdi, IR_XOR
    mov rsi, TYPE_INT
    mov rdx, [rsp+8] ; dst vreg
    mov rcx, [rsp+16] ; operand vreg
    mov r8, [rsp] ; -1 vreg
    xor r9, r9
    xor r10, r10
    call emit_ir
    add rsp, 24
    pop rbx ; restore dst
    mov rax, rbx
    mov rdx, TYPE_INT
    ret

; scope() built-in: returns scope of variable as str
.scope_builtin:
    call advance ; consume 'scope'
    mov edi, TOK_LPAREN
    call expect ; consume '('
    mov eax, [current_token]
    cmp eax, TOK_IDENT
    jne expected_ident
    ; Look up the variable
    mov rdi, [tok_str_ptr]
    mov rsi, [tok_str_len]
    call sym_lookup
    cmp rax, -1
    je .undef_error_scope
    mov r14, rax ; save symbol index
    call advance ; consume IDENT
    mov edi, TOK_RPAREN
    call expect ; consume ')'
    ; Get scope of the variable
    mov rdi, r14
    call sym_get_scope ; rax = SCOPE_GLOBAL/SCOPE_LOCAL/SCOPE_BLOCK
    ; Set up string pointer and length based on scope
    cmp rax, SCOPE_BLOCK
    je .scope_block
    cmp rax, SCOPE_LOCAL
    je .scope_local
    ; SCOPE_GLOBAL
    mov r14, str_scope_global
    mov r15, 6 ; len("global")
    jmp .scope_emit
.scope_local:
    mov r14, str_scope_local
    mov r15, 5 ; len("local")
    jmp .scope_emit
.scope_block:
    mov r14, str_scope_block
    mov r15, 5 ; len("block")
.scope_emit:
    call alloc_vreg
    push rax ; dst vreg
    mov rdi, IR_LOAD_STR
    mov rsi, TYPE_STR
    mov rdx, [rsp]   ; dst vreg
    xor rcx, rcx
    xor r8, r8
    mov r9, r14       ; str ptr (imm)
    mov r10, r15      ; str len (aux)
    call emit_ir
    pop rax ; dst vreg
    mov rdx, TYPE_STR
    ret
.undef_error_scope:
    mov rdi, err_undef
    jmp compile_error

; len() built-in: returns length of seq or str as int
.len_builtin:
    call advance ; consume 'len'
    mov edi, TOK_LPAREN
    call expect ; consume '('
    call parse_expr ; rax = arg vreg, rdx = arg type
    push rax ; save arg vreg
    push rdx ; save arg type
    mov edi, TOK_RPAREN
    call expect ; consume ')'
    pop rdx ; restore arg type
    pop rcx ; restore arg vreg (into rcx for src1)
    cmp rdx, TYPE_SEQ
    je .len_seq
    cmp rdx, TYPE_STR
    je .len_str
    cmp rdx, TYPE_DICT
    je .len_dict
    mov rdi, err_type_mismatch
    jmp compile_error
.len_seq:
    call alloc_vreg
    push rax
    mov rdi, IR_SEQ_LEN
    mov rsi, TYPE_INT
    mov rdx, [rsp] ; dst
    ; rcx already has seq vreg (src1)
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir
    pop rax
    mov rdx, TYPE_INT
    ret
.len_str:
    call alloc_vreg
    push rax
    mov rdi, IR_STR_LEN
    mov rsi, TYPE_INT
    mov rdx, [rsp] ; dst
    ; rcx already has str vreg (src1)
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir
    pop rax
    mov rdx, TYPE_INT
    ret
.len_dict:
    call alloc_vreg
    push rax
    mov rdi, IR_DICT_LEN
    mov rsi, TYPE_INT
    mov rdx, [rsp] ; dst
    ; rcx already has dict vreg (src1)
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir
    pop rax
    mov rdx, TYPE_INT
    ret

; Array literal: [expr, expr, ...]
; Stores values on the stack and returns count as int
.array_literal:
    call advance ; consume '['
    xor r12, r12 ; count = 0
.array_loop:
    mov eax, [current_token]
    cmp eax, TOK_RBRACKET
    je .array_done
    cmp eax, TOK_EOF
    je .array_done
    ; Parse the value
    call parse_expr
    ; Store the value on the stack (for now, just count)
    inc r12
    ; Check for comma
    mov eax, [current_token]
    cmp eax, TOK_COMMA
    jne .array_no_comma
    call advance ; consume comma
.array_no_comma:
    jmp .array_loop
.array_done:
    mov edi, TOK_RBRACKET
    call expect ; consume ']'
    ; Return the count as an integer literal
    call alloc_vreg
    push rax
    mov rdi, IR_LOAD_IMM
    mov rsi, TYPE_INT
    mov rdx, [rsp]
    xor rcx, rcx
    xor r8, r8
    mov r9, r12 ; count
    xor r10, r10
    call emit_ir
    pop rax
    mov rdx, TYPE_INT
    ret

; Type cast: type_name(expr)
.type_cast:
    mov r12, [tok_ival] ; target type ID
    call advance ; consume type keyword
    mov edi, TOK_LPAREN
    call expect ; consume '('
    call parse_expr ; rax = vreg, rdx = src_type
    mov r13, rdx ; save source type
    push rax ; save source vreg
    mov edi, TOK_RPAREN
    call expect ; consume ')'

    ; Determine cast IR opcode based on (src_type, dst_type)
    ; int(x): float->int, str->int, char->int, byte->int, bool->int
    ; float(x): int->float, str->float
    ; bool(x): int->bool
    ; char(x): int->char, byte->char
    ; byte(x): int->char, char->byte
    ; str(x): int->str, float->str, bool->str, char->str, byte->str

    ; For now, handle the most common casts
    mov r14, IR_CAST_FTI ; default: float->int

    cmp r12, TYPE_INT
    je .cast_to_int
    cmp r12, TYPE_FLOAT
    je .cast_to_float
    cmp r12, TYPE_BOOL
    je .cast_to_bool
    cmp r12, TYPE_CHAR
    je .cast_to_char
    cmp r12, TYPE_BYTE
    je .cast_to_byte
    ; Unsupported cast target
    jmp .cast_done_emit

.cast_to_int:
    cmp r13, TYPE_FLOAT
    je .cast_use_fti
    cmp r13, TYPE_BOOL
    je .cast_use_bti
    cmp r13, TYPE_CHAR
    je .cast_use_cti
    cmp r13, TYPE_BYTE
    je .cast_use_bci
    ; int(x) where x is already int — no-op, just use the vreg
    jmp .cast_noop
.cast_use_fti:
    mov r14, IR_CAST_FTI
    jmp .cast_done_emit
.cast_use_bti:
    mov r14, IR_CAST_BTI
    jmp .cast_done_emit
.cast_use_cti:
    mov r14, IR_CAST_CTI
    jmp .cast_done_emit
.cast_use_bci:
    mov r14, IR_CAST_BCI
    jmp .cast_done_emit

.cast_to_float:
    cmp r13, TYPE_INT
    je .cast_use_itf
    ; float(x) where x is already float — no-op
    jmp .cast_noop
.cast_use_itf:
    mov r14, IR_CAST_ITF
    jmp .cast_done_emit

.cast_to_bool:
    cmp r13, TYPE_INT
    je .cast_use_itb
    ; bool(x) where x is already bool — no-op
    jmp .cast_noop
.cast_use_itb:
    ; int->bool: positive->true(1), zero->neutral(0), negative->false(-1)
    ; IR_SIGNUM produces exactly {-1, 0, 1} from {<0, =0, >0} — correct for
    ; Łukasiewicz ternary booleans.  IR_CAST_BTI was previously used here by
    ; mistake (it is the bool→int direction, documented as a no-op).
    mov r14, IR_SIGNUM
    jmp .cast_done_emit

.cast_to_char:
    cmp r13, TYPE_INT
    je .cast_use_cti2
    cmp r13, TYPE_BYTE
    je .cast_use_btc
    jmp .cast_noop
.cast_use_cti2:
    mov r14, IR_CAST_CTI
    jmp .cast_done_emit
.cast_use_btc:
    mov r14, IR_CAST_BTC
    jmp .cast_done_emit

.cast_to_byte:
    cmp r13, TYPE_INT
    je .cast_use_bci2
    cmp r13, TYPE_CHAR
    je .cast_use_ctb
    jmp .cast_noop
.cast_use_bci2:
    mov r14, IR_CAST_BCI
    jmp .cast_done_emit
.cast_use_ctb:
    mov r14, IR_CAST_CTB
    jmp .cast_done_emit

.cast_noop:
    ; No cast needed — return source vreg with target type
    pop rax ; source vreg
    mov rdx, r12 ; target type
    ret

.cast_done_emit:
    call alloc_vreg
    mov rbx, rax ; dst vreg
    pop rcx ; src vreg
    mov rdi, r14 ; cast opcode
    mov rsi, r12 ; dst type
    mov rdx, rbx ; dst vreg
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir
    mov rax, rbx
    mov rdx, r12 ; return target type
    ret


; Helper: generate unique label ID
; Returns rax = label ID (0, 1, 2, ...)
gen_label:
    mov eax, [label_counter]
    inc dword [label_counter]
    ret

; Helper: emit IR_LABEL with given label ID
; rdi = label ID
emit_label:
    push rdi
    call alloc_vreg ; dummy vreg (labels don't use it)
    mov rdx, rax    ; dst vreg
    pop r9           ; label ID → imm
    mov rdi, IR_LABEL
    xor rsi, rsi     ; no type
    xor rcx, rcx     ; no src1
    xor r8, r8       ; no src2
    xor r10, r10     ; no aux
    call emit_ir
    ret

; Helper: emit IR_JMP to given label ID
; rdi = target label ID
emit_jmp:
    push rdi
    call alloc_vreg
    mov rdx, rax
    pop r9           ; target label → imm
    mov rdi, IR_JMP
    xor rsi, rsi
    xor rcx, rcx
    xor r8, r8
    xor r10, r10
    call emit_ir
    ret

; Helper: emit IR_JCC with condition code to given label ID
; rdi = target label ID, rsi = condition code (COND_*), rcx = vreg to test
emit_jcc:
    push rdi
    push rsi
    push rcx
    call alloc_vreg
    mov rdx, rax     ; dst vreg (dummy)
    pop rcx           ; src1 = vreg to test
    pop r10           ; condition code → aux
    pop r9            ; target label → imm
    mov rdi, IR_JCC
    xor rsi, rsi      ; no type
    xor r8, r8        ; no src2
    call emit_ir
    ret

; Helper: parse an indented block (INDENT ... DEDENT)
; Calls parse_stmt for each statement in the block
; Expects the current token to be NEWLINE (after ':')
parse_block:
    ; Consume NEWLINE before INDENT (if present)
    mov eax, [current_token]
    cmp eax, TOK_NEWLINE
    jne .block_no_nl
    call advance
.block_no_nl:
    mov eax, [current_token]
    cmp eax, TOK_INDENT
    jne .block_single

    ; Save sym_count at block entry for block-scope cleanup
    mov eax, [block_nesting]
    cmp eax, 31
    jg .block_too_deep
    mov ecx, [sym_count]
    imul eax, eax, 4
    mov [block_sym_save + rax], ecx

    ; Increment block nesting depth
    inc dword [block_nesting]

    call advance ; consume INDENT
.block_loop:
    mov eax, [current_token]
    cmp eax, TOK_DEDENT
    je .block_done
    cmp eax, TOK_EOF
    je .block_done
    call parse_stmt
    ; Expect newline after each statement in block
    mov eax, [current_token]
    cmp eax, TOK_NEWLINE
    jne .block_skip_nl
    call advance
.block_skip_nl:
    jmp .block_loop
.block_done:
    call advance ; consume DEDENT

    ; Decrement block nesting depth
    dec dword [block_nesting]

    ; Clean up block-scoped (__-prefixed) variables
    mov eax, [block_nesting]
    imul eax, eax, 4
    mov edi, [block_sym_save + rax]
    call sym_remove_block_scope

.block_single:
    ret

.block_too_deep:
    mov rdi, err_syntax
    jmp compile_error

; Helper to determine scope
; rdi = name_ptr, rsi = name_len
; Returns rax = scope level
determine_scope:
    ; Check for __ prefix → SCOPE_BLOCK
    cmp rsi, 2
    jl .not_block
    cmp byte [rdi], '_'
    jne .not_block
    cmp byte [rdi + 1], '_'
    jne .not_block
    mov rax, SCOPE_BLOCK
    ret
.not_block:
    ; Check nesting depth: if inside a block → SCOPE_LOCAL
    cmp dword [block_nesting], 0
    jle .global
    mov rax, SCOPE_LOCAL
    ret
.global:
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
    .err_prefix db "Compile Error: "
    .err_prefix_len equ $ - .err_prefix
    .line_suffix db " at line "
    .line_suffix_len equ $ - .line_suffix

section .text

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
    mov r12, rax
    mov r13, rdx

.pp_loop:
    mov eax, [current_token]
    cmp eax, TOK_LBRACKET
    je .pp_bracket_index
    cmp eax, TOK_DOT
    jne .pp_done

    call advance              ; consume '.'

    mov eax, [current_token]
    cmp eax, TOK_IDENT
    je .pp_method_name
    cmp eax, TOK_LEN
    je .pp_method_name
    jmp .pp_syntax_err

.pp_method_name:

    ; Check if this is a struct field access
    cmp r13, TYPE_COMPLEX
    jne .pp_not_struct_field
    ; Look up struct type_id from vreg_type_map
    movzx eax, word [vreg_type_map + r12 * 4]
    test eax, eax
    jz .pp_not_struct_field
    ; Look up field by name
    mov rdi, rax            ; struct type_id
    mov rsi, [tok_str_ptr]  ; field name ptr
    mov rdx, [tok_str_len]  ; field name len
    call advance            ; consume field name
    push r12                ; save base vreg
    call type_struct_find_field
    cmp rax, -1
    je .pp_struct_miss
    ; rax = field offset, ecx = field type_id
    mov r13, rcx            ; r13 = field type
    push rax                ; save offset
    call alloc_vreg
    pop r9                  ; r9 = field offset
    mov rdx, rax            ; dst vreg
    pop rcx                 ; src1 = base vreg
    ; Emit IR_LOAD_VAR
    mov rdi, IR_LOAD_VAR
    mov rsi, r13            ; type
    xor r8, r8
    xor r10, r10
    push rdx                ; save result vreg
    call emit_ir
    pop r12                 ; r12 = result vreg
    jmp .pp_loop
.pp_struct_miss:
    pop r12                 ; restore base vreg
.pp_not_struct_field:

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
    cmp r13, TYPE_SEQ
    je .pp_seq_dispatch
    cmp r13, TYPE_DICT
    je .pp_dict_dispatch
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
    lea rdi, [str_rotate_right]
    call ident_is
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
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_CAST_BTI
    mov rsi, TYPE_BOOL
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
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
    lea rdi, [str_is_whitespace]
    call ident_is
    test rax,rax
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
    lea rdi, [str_is_printable]
    call ident_is
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
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_CAST_CTI
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

.pp_char_to_byte:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_CAST_CTB
    mov rsi, TYPE_CHAR
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
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
    lea rdi, [str_swap_nibbles]
    call ident_is
    test rax,rax
    jnz .pp_byte_swap_nib
    lea rdi, [str_leading_zeros]
    call ident_is
    test rax,rax
    jnz .pp_byte_clz8
    lea rdi, [str_trailing_zeros]
    call ident_is
    test rax,rax
    jnz .pp_byte_ctz
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
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_CAST_BCI
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

.pp_byte_to_char:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_CAST_BTC
    mov rsi, TYPE_BYTE
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
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

; ─────────── SEQ methods ───────────────────────────────
.pp_seq_dispatch:
    lea rdi, [str_push]
    call ident_is
    test rax,rax
    jnz .pp_seq_push
    lea rdi, [str_len_m]
    call ident_is
    test rax,rax
    jnz .pp_seq_len
    lea rdi, [str_get_m]
    call ident_is
    test rax,rax
    jnz .pp_seq_get
    lea rdi, [str_pop]
    call ident_is
    test rax,rax
    jnz .pp_seq_pop
    lea rdi, [str_insert]
    call ident_is
    test rax,rax
    jnz .pp_seq_insert
    lea rdi, [str_remove]
    call ident_is
    test rax,rax
    jnz .pp_seq_remove
    lea rdi, [str_first]
    call ident_is
    test rax,rax
    jnz .pp_seq_first
    lea rdi, [str_last]
    call ident_is
    test rax,rax
    jnz .pp_seq_last
    lea rdi, [str_contains]
    call ident_is
    test rax,rax
    jnz .pp_seq_contains
    lea rdi, [str_index_of]
    call ident_is
    test rax,rax
    jnz .pp_seq_index_of
    lea rdi, [str_count_of]
    call ident_is
    test rax,rax
    jnz .pp_seq_count_of
    lea rdi, [str_copy]
    call ident_is
    test rax,rax
    jnz .pp_seq_copy
    lea rdi, [str_reverse]
    call ident_is
    test rax,rax
    jnz .pp_seq_reverse
    lea rdi, [str_sum_m]
    call ident_is
    test rax,rax
    jnz .pp_seq_sum
    lea rdi, [str_min_m]
    call ident_is
    test rax,rax
    jnz .pp_seq_min
    lea rdi, [str_max_m]
    call ident_is
    test rax,rax
    jnz .pp_seq_max
    lea rdi, [str_slice]
    call ident_is
    test rax,rax
    jnz .pp_seq_slice
    lea rdi, [str_clear_m]
    call ident_is
    test rax,rax
    jnz .pp_seq_clear
    lea rdi, [str_reserve_m]
    call ident_is
    test rax,rax
    jnz .pp_seq_reserve
    lea rdi, [str_cap_m]
    call ident_is
    test rax,rax
    jnz .pp_seq_cap
    lea rdi, [str_is_empty_m]
    call ident_is
    test rax,rax
    jnz .pp_seq_is_empty
    jmp .pp_method_err

.pp_seq_push:
    ; .push(value) — emit IR_SEQ_PUSH
    call parse_expr ; parse the value to push
    mov r14, rax    ; value vreg
    mov edi, TOK_RPAREN
    call expect
    ; Emit IR_SEQ_PUSH: seq_push(seq, value)
    mov rdi, IR_SEQ_PUSH
    mov rsi, TYPE_INT
    xor rdx, rdx       ; dst = 0 (void)
    mov rcx, r12       ; src1 = seq vreg
    mov r8, r14        ; src2 = value vreg
    mov r9, SEQ_ELEMENT_SIZE  ; imm = element size
    xor r10, r10
    call emit_ir
    ; push returns void, keep seq vreg in r12
    jmp .pp_loop

.pp_seq_len:
    ; .len() — emit IR_SEQ_LEN
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_SEQ_LEN
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r12    ; src1 = seq vreg
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_INT
    jmp .pp_loop

.pp_seq_get:
    ; .get(index) — emit IR_SEQ_LOAD
    call parse_expr ; parse the index
    mov r14, rax    ; index vreg
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_SEQ_LOAD
    mov rsi, TYPE_INT ; element type (assume int for now)
    mov rdx, rbx      ; dst
    mov rcx, r12      ; src1 = seq vreg
    mov r8, r14       ; src2 = index vreg
    mov r9, SEQ_ELEMENT_SIZE  ; element size (8 for int)
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_INT
    jmp .pp_loop

.pp_seq_pop:
    ; .pop() — emit IR_SEQ_POP
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_SEQ_POP
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r12
    xor r8, r8
    mov r9, 8
    xor r10, r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_INT
    jmp .pp_loop

.pp_seq_insert:
    ; .insert(index, value) — emit IR_SEQ_INSERT
    call parse_expr ; parse the index
    mov r14, rax    ; index vreg
    mov edi, TOK_COMMA
    call expect ; consume ','
    call parse_expr ; parse the value
    mov r15, rax    ; value vreg
    mov edi, TOK_RPAREN
    call expect ; consume ')'
    ; Emit IR_SEQ_INSERT: seq.insert(index, value)
    mov rdi, IR_SEQ_INSERT
    mov rsi, TYPE_INT
    xor rdx, rdx       ; dst = 0 (void)
    mov rcx, r12       ; src1 = seq vreg
    mov r8, r14        ; src2 = index vreg
    mov r9, SEQ_ELEMENT_SIZE  ; imm = element size
    mov r10, r15       ; aux = value vreg
    call emit_ir
    jmp .pp_loop

.pp_seq_remove:
    ; .remove(index) — emit IR_SEQ_REMOVE
    call parse_expr ; parse the index
    mov r14, rax    ; index vreg
    mov edi, TOK_RPAREN
    call expect ; consume ')'
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_SEQ_REMOVE
    mov rsi, TYPE_INT
    mov rdx, rbx       ; dst
    mov rcx, r12       ; src1 = seq vreg
    mov r8, r14        ; src2 = index vreg
    mov r9, SEQ_ELEMENT_SIZE  ; imm = element size
    xor r10, r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_INT
    jmp .pp_loop

.pp_seq_first:
    ; .first() — emit IR_SEQ_LOAD with index 0
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax        ; dst vreg
    ; Load 0 as immediate for index
    push rbx
    call alloc_vreg
    mov r14, rax        ; index vreg = 0
    mov rdi, IR_LOAD_IMM
    mov rsi, TYPE_INT
    mov rdx, r14
    xor rcx, rcx
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir
    pop rbx
    ; emit IR_SEQ_LOAD: dst = seq[0]
    mov rdi, IR_SEQ_LOAD
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r12        ; src1 = seq
    mov r8, r14         ; src2 = index vreg
    mov r9, SEQ_ELEMENT_SIZE  ; element size
    xor r10, r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_INT
    jmp .pp_loop

.pp_seq_last:
    ; .last() — emit IR_SEQ_LOAD with index len-1
    mov edi, TOK_RPAREN
    call expect
    ; First get length
    call alloc_vreg
    push rax            ; save len vreg
    mov rdi, IR_SEQ_LEN
    mov rsi, TYPE_INT
    mov rdx, [rsp]
    mov rcx, r12
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir
    ; Subtract 1 from length
    call alloc_vreg
    push rax            ; save index vreg
    call alloc_vreg
    mov r14, rax        ; const 1 vreg
    mov rdi, IR_LOAD_IMM
    mov rsi, TYPE_INT
    mov rdx, r14
    xor rcx, rcx
    xor r8, r8
    mov r9, 1
    xor r10, r10
    call emit_ir
    ; index = len - 1
    mov rdi, IR_SUB
    mov rsi, TYPE_INT
    pop rdx             ; dst = index vreg
    pop rcx             ; src1 = len vreg
    mov r8, r14         ; src2 = 1
    xor r9, r9
    xor r10, r10
    push rdx            ; save index vreg
    call emit_ir
    ; Load seq[index]
    call alloc_vreg
    mov rbx, rax
    pop r8              ; index vreg
    mov rdi, IR_SEQ_LOAD
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r12
    mov r9, 8
    xor r10, r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_INT
    jmp .pp_loop

.pp_seq_contains:
    ; .contains(value) → bool
    call parse_expr     ; value vreg
    mov r14, rax
    mov edi, TOK_RPAREN
    call expect
    mov rdi, IR_SEQ_CONTAINS
    mov rsi, TYPE_BOOL
    call alloc_vreg
    mov rbx, rax
    mov rdx, rbx
    mov rcx, r12        ; seq
    mov r8, r14         ; value
    mov r9, SEQ_ELEMENT_SIZE  ; element size
    xor r10, r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_BOOL
    jmp .pp_loop

.pp_seq_index_of:
    ; .index_of(value) → int
    call parse_expr
    mov r14, rax
    mov edi, TOK_RPAREN
    call expect
    mov rdi, IR_SEQ_INDEX_OF
    mov rsi, TYPE_INT
    call alloc_vreg
    mov rbx, rax
    mov rdx, rbx
    mov rcx, r12
    mov r8, r14
    mov r9, 8
    xor r10, r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_INT
    jmp .pp_loop

.pp_seq_count_of:
    ; .count_of(value) → int
    call parse_expr
    mov r14, rax       ; save value vreg
    mov edi, TOK_RPAREN
    call expect
    ; Emit IR_SEQ_COUNT_OF: dst = count of value in seq
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_SEQ_COUNT_OF
    mov rsi, TYPE_INT
    mov rdx, rbx        ; dst
    mov rcx, r12        ; src1 = seq vreg
    mov r8, r14         ; src2 = value vreg
    mov r9, SEQ_ELEMENT_SIZE           ; imm = element size
    xor r10, r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_INT
    jmp .pp_loop

.pp_seq_copy:
    ; .copy() → seq[T]
    mov edi, TOK_RPAREN
    call expect
    mov rdi, IR_SEQ_COPY
    mov rsi, TYPE_SEQ
    call alloc_vreg
    mov rbx, rax
    mov rdx, rbx
    mov rcx, r12
    xor r8, r8
    mov r9, 8
    xor r10, r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_SEQ
    jmp .pp_loop

.pp_seq_reverse:
    ; .reverse() — void, mutates in place
    mov edi, TOK_RPAREN
    call expect
    mov rdi, IR_SEQ_REVERSE
    xor rsi, rsi
    xor rdx, rdx
    mov rcx, r12
    xor r8, r8
    mov r9, 8
    xor r10, r10
    call emit_ir
    jmp .pp_loop

.pp_seq_sum:
    ; .sum() → int/float
    mov edi, TOK_RPAREN
    call expect
    mov rdi, IR_SEQ_SUM
    mov rsi, TYPE_INT
    call alloc_vreg
    mov rbx, rax
    mov rdx, rbx
    mov rcx, r12
    xor r8, r8
    mov r9, 8
    xor r10, r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_INT
    jmp .pp_loop

.pp_seq_min:
    ; .min() → T
    mov edi, TOK_RPAREN
    call expect
    mov rdi, IR_SEQ_MIN
    mov rsi, TYPE_INT
    call alloc_vreg
    mov rbx, rax
    mov rdx, rbx
    mov rcx, r12
    xor r8, r8
    mov r9, 8
    xor r10, r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_INT
    jmp .pp_loop

.pp_seq_max:
    ; .max() → T
    mov edi, TOK_RPAREN
    call expect
    mov rdi, IR_SEQ_MAX
    mov rsi, TYPE_INT
    call alloc_vreg
    mov rbx, rax
    mov rdx, rbx
    mov rcx, r12
    xor r8, r8
    mov r9, 8
    xor r10, r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_INT
    jmp .pp_loop

.pp_seq_slice:
    ; .slice(lo, hi) → seq[T]
    call parse_expr     ; lo
    mov r14, rax
    mov edi, TOK_COMMA
    call expect
    call parse_expr     ; hi
    mov r15, rax
    mov edi, TOK_RPAREN
    call expect
    mov rdi, IR_SEQ_SLICE
    mov rsi, TYPE_SEQ
    call alloc_vreg
    mov rbx, rax
    mov rdx, rbx
    mov rcx, r12        ; seq
    mov r8, r14         ; lo
    ; Store hi in aux
    push r15
    pop r10
    mov r9, 8
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_SEQ
    jmp .pp_loop

.pp_seq_clear:
    ; .clear() — void
    mov edi, TOK_RPAREN
    call expect
    mov rdi, IR_SEQ_CLEAR
    xor rsi, rsi
    xor rdx, rdx
    mov rcx, r12
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir
    jmp .pp_loop

.pp_seq_reserve:
    ; .reserve(n) — void
    call parse_expr
    mov r14, rax
    mov edi, TOK_RPAREN
    call expect
    mov rdi, IR_SEQ_RESERVE
    xor rsi, rsi
    xor rdx, rdx
    mov rcx, r12
    mov r8, r14
    xor r9, r9
    xor r10, r10
    call emit_ir
    jmp .pp_loop

.pp_seq_cap:
    ; .cap() → int
    mov edi, TOK_RPAREN
    call expect
    mov rdi, IR_SEQ_CAP
    mov rsi, TYPE_INT
    call alloc_vreg
    mov rbx, rax
    mov rdx, rbx
    mov rcx, r12
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_INT
    jmp .pp_loop

.pp_seq_is_empty:
    ; .is_empty() → bool (len == 0)
    mov edi, TOK_RPAREN
    call expect
    ; Get length
    call alloc_vreg
    push rax
    mov rdi, IR_SEQ_LEN
    mov rsi, TYPE_INT
    mov rdx, [rsp]
    mov rcx, r12
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir
    ; Compare with 0
    call alloc_vreg
    mov rbx, rax
    pop rcx             ; len vreg
    mov rdi, IR_CMP_BOOL
    mov rsi, TYPE_BOOL
    mov rdx, rbx
    ; rcx = len vreg (src1)
    xor r8, r8          ; src2 = 0 (use imm)
    xor r9, r9          ; imm = 0
    mov r10, COND_EQ    ; len == 0
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_BOOL
    jmp .pp_loop
.pp_dict_dispatch:
    lea rdi, [str_len_m]
    call ident_is
    test rax,rax
    jnz .pp_dict_len
    jmp .pp_method_err

.pp_dict_len:
    ; .len() — emit IR_DICT_LEN
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_DICT_LEN
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r12    ; src1 = dict vreg
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_INT
    jmp .pp_loop

; ─────────── bracket index s[i] ───────────────────────
.pp_bracket_index:
    ; r12 = base vreg, r13 = base type
    push r12 ; save base vreg before parse_expr clobbers it
    call advance ; consume '['
    call parse_expr ; rax = index vreg, rdx = index type
    mov r14, rax ; save index vreg
    mov edi, TOK_RBRACKET
    call expect ; consume ']'
    pop rcx ; restore base vreg into rcx (src1)
    cmp r13, TYPE_SEQ
    je .pp_bracket_seq
    cmp r13, TYPE_DICT
    je .pp_bracket_dict
    cmp r13, TYPE_ARR
    je .pp_bracket_arr
    mov rdi, err_type_mismatch
    jmp compile_error
.pp_bracket_seq:
    call alloc_vreg
    push rax
    mov rdi, IR_SEQ_LOAD
    mov rsi, TYPE_INT
    mov rdx, [rsp] ; dst
    ; rcx = seq vreg (src1)
    mov r8, r14 ; index vreg (src2)
    mov r9, SEQ_ELEMENT_SIZE ; element size
    xor r10, r10
    call emit_ir
    pop r12 ; result vreg
    mov r13, TYPE_INT
    jmp .pp_loop
.pp_bracket_dict:
    call alloc_vreg
    push rax
    mov rdi, IR_DICT_LOAD
    mov rsi, TYPE_INT
    mov rdx, [rsp] ; dst
    ; rcx = dict vreg (src1)
    mov r8, r14 ; key vreg (src2)
    xor r9, r9
    xor r10, r10
    call emit_ir
    pop r12 ; result vreg
    mov r13, TYPE_INT
    jmp .pp_loop
.pp_bracket_arr:
    ; Array index access: dst = arr[index]
    call alloc_vreg
    push rax
    mov rdi, IR_ARR_LOAD
    mov rsi, TYPE_INT
    mov rdx, [rsp] ; dst
    ; rcx = arr vreg (src1)
    mov r8, r14 ; index vreg (src2)
    mov r9, 0   ; imm = 0
    mov r10, SEQ_ELEMENT_SIZE ; aux = element size
    call emit_ir
    pop r12 ; result vreg
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

; Global error handlers accessible from any function
expected_ident:
    mov rdi, err_syntax
    jmp compile_error

dup_error:
    mov rdi, err_dup_decl
    jmp compile_error

full_error:
    mov rdi, err_sym_full
    jmp compile_error

type_error:
    mov rdi, err_type_mismatch
    jmp compile_error
