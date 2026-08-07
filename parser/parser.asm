; Rex Parser Implementation
; written in x86-64 NASM assembly

%include "include/rex_defs.inc"
%include "include/rex_ir.inc"

section .data
    global current_token
    current_token   dd 0

    ; Error messages
    err_syntax      db "Syntax Error: Unexpected token", 0
    err_dup_decl    db "Compile Error: Duplicate variable declaration in same scope", 0
    err_undef       db "Compile Error: Undefined variable", 0
    err_uninit      db "Compile Error: Variable read before initialization", 0
err_type_mismatch db "Compile Error: Type mismatch", 0
err_when_overflow db "Compile Error: Too many distinct `when` expressions (max 256)", 0
err_loop_ctl_outside db "Compile Error: `stop`/`skip` outside a loop", 0
err_loop_ctl_depth db "Compile Error: Loop control depth exceeds current nesting", 0
err_loop_nesting db "Compile Error: Loop nesting too deep (max 32)", 0
    err_sigil_req   db "Compile Error: Mutation requires ':' sigil before variable name", 0
    err_private_member db "Compile Error: Cannot access private member", 0
    err_unknown_module db "Compile Error: Unknown module", 0
    err_nested_module db "Compile Error: 'module' blocks cannot be nested", 0
    err_immutable   db "Compile Error: Cannot mutate an immutable variable", 0
    err_newline_req db "Syntax Error: Expected newline or EOF at end of statement", 0
    ; Bug 5 fix: distinct message for symbol-table-full (was reusing err_dup_decl)
    err_sym_full    db "Compile Error: Symbol table full (too many variables)", 0
    err_unknown_method_on db "Compile Error: Unknown method", 0
    err_unknown_field db "Compile Error: Unknown field", 0
    str_on_type       db " on type ", 0
    ; Type names for error messages
    str_t_int         db "int", 0
    str_t_float       db "float", 0
    str_t_bool        db "bool", 0
    str_t_struct      db "struct", 0
    str_t_str         db "str", 0
    str_t_seq         db "seq", 0
    str_t_dict        db "dict", 0
    str_t_char        db "char", 0
    str_t_byte        db "byte", 0
    str_t_file        db "file", 0
    str_t_tuple       db "tuple", 0
    str_t_value       db "value", 0
    err_unknown_proto db "Compile Error: Unknown protocol", 0
    err_proto_arg_count db "Compile Error: Wrong number of arguments to protocol", 0
    err_proto_multi db "Compile Error: Multi-return protocols must be assigned with ':a, :b ='", 0
    err_arity db "Compile Error: This protocol requires a different return arity", 0
    err_label_overflow db "Compile Error: Too many control-flow labels (program too complex)", 0
    str_assert_default db "AssertionError: assertion failed", 0
    str_assert_default_len equ $ - str_assert_default
    str_unreachable_default db "UnreachableError: reached unreachable code", 0

    str_unreachable_default_len equ $ - str_unreachable_default

    ; Method name strings (used by parse_postfix dispatch)
    str_abs           db "abs", 0
    str_min           db "min", 0
    str_max           db "max", 0
    str_clamp         db "clamp", 0
    str_signum        db "signum", 0
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
    ; Seq method names
    str_push          db "push", 0
    str_len_m         db "len", 0
    str_get_m         db "get", 0
    str_pop           db "pop", 0
    str_insert        db "insert", 0
    str_remove        db "remove", 0
    str_first         db "first", 0
    str_last          db "last", 0
    str_index         db "index", 0
    str_count         db "count", 0
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
    str_sin           db "sin", 0
    str_cos           db "cos", 0
    str_tan           db "tan", 0
    str_pow           db "pow", 0
    str_cbrt          db "cbrt", 0
    str_gcd           db "gcd", 0
    str_lcm           db "lcm", 0
    str_to_bin        db "to_bin", 0
    str_to_hex        db "to_hex", 0
    str_to_oct        db "to_oct", 0
    str_str_m         db "str", 0
    str_int_m         db "int", 0
    str_byte_m        db "byte", 0
    str_char_m        db "char", 0
    str_alpha         db "alpha", 0
    str_digit         db "digit", 0
    str_alnum_m       db "alnum", 0
    str_whitespace    db "whitespace", 0
    str_upper         db "upper", 0
    str_lower         db "lower", 0
    str_punct_m       db "punct", 0
    str_printable_m   db "printable", 0
    str_ascii_m       db "ascii", 0
    str_bit           db "bit", 0
    str_hex_m         db "hex", 0
    str_bin_m         db "bin", 0
    str_oct_m         db "oct", 0
    str_zero          db "zero", 0
    str_positive      db "positive", 0
    str_negative      db "negative", 0
    str_even          db "even", 0
    str_odd           db "odd", 0
    str_nan           db "nan", 0
    str_inf           db "inf", 0
    str_finite        db "finite", 0
    ; File method names (design.md §15.4)
    str_open          db "open", 0
    str_file_exists   db "file_exists", 0
    str_read          db "read", 0
    str_read_line     db "read_line", 0
    str_read_bytes    db "read_bytes", 0
    str_read_all_bytes db "read_all_bytes", 0
    str_lines_m       db "lines", 0
    str_write_m       db "write", 0
    str_writeln       db "writeln", 0
    str_write_bytes   db "write_bytes", 0
    str_seek          db "seek", 0
    str_seek_end      db "seek_end", 0
    str_pos           db "pos", 0
    str_size          db "size", 0
    str_is_eof        db "is_eof", 0
    str_flush         db "flush", 0
    str_close_m       db "close", 0
    str_path          db "path", 0
    str_mode_r        db "r", 0
    float_pp_one      dq 0x3FF0000000000000
    ; scope() built-in string constants
    str_scope_global  db "global", 0
    str_scope_local   db "local", 0
    str_scope_block   db "block", 0

    ; For loop hidden variable names
    str_for_end       db "_for_end", 0
    str_for_step      db "_for_step", 0

    ; Block nesting depth for SCOPE_LOCAL tracking
    ; depth 0 = global scope, depth > 0 = inside a block (SCOPE_LOCAL)
    block_nesting     dd 0
    ; Saved sym_count at block entry for block-scope cleanup
    block_sym_save    times 32 dd 0  ; up to 32 nesting levels

    ; Protocol body tracking
    proto_body_nesting dd 0      ; >0 while parsing a protocol body
    prot_sym_save     dd 0       ; sym_count before protocol params/body
    ; Call-site argument scratch (65 params max)
    call_arg_vregs    times 65 dw 0
    call_arg_types    times 65 dd 0
    call_result_hi    dd 0       ; hi return vreg of last protocol call (0 = none)
    ; Multi-target mutation targets
    mut_target_syms   times 65 dd 0

section .bss
    ; For storing name string buffers during parsing
    ident_buf       resb 32
    ident_len       resq 1
    ; For storing method name during parse_postfix
    method_buf      resb 32
    method_len      resq 1
    ; For building unique per-loop hidden variable names
    for_hidden_buf  resb 32
    ; 1 = for-loop used '..=' (inclusive range → COND_LE), 0 = '..' (COND_LT)
    for_inclusive   resb 1
    ; For saving the element variable name in each loops (parse_expr clobbers ident_buf)
    each_var_buf    resb 32
    each_var_len    resq 1
    ; Label counter for control flow
    label_counter   resd 1
    ; Vreg to struct type_id mapping (for field access)
    vreg_type_map   resd 65536
    ; Vreg to container element type (seq[T]/dict[T]/arr[T]) for bracket indexing
    vreg_elem_types resd 65536
    ; Element type parsed from seq[T]/dict[T]/arr[T,N] during a declaration
    pending_elem_type resd 1
    ; Struct construction scratch pool bump offset into the output's data
    ; segment (STRUCT_SCRATCH_BASE + offset is emitted as the LEA_VAR imm).
    struct_scratch_ptr resd 1
    ; output() argument buffers (max 256 args)
    out_arg_vregs   resw 256
    out_arg_types   resd 256
    ; `when` monitor dedup table (design §7.3): one monitor per unique expr text
    when_hash_table resq WHEN_MONITOR_MAX
    when_count      resd 1
    ; Loop context stack for stop/skip (design §8.5)
    loop_end_labels resq LOOP_MAX_DEPTH
    loop_skip_labels resq LOOP_MAX_DEPTH
    loop_depth      resd 1
    ; Scratch buffer for composing error messages (e.g. "Undefined variable 'name'")
    error_msg_buf   resb 192
    ; Scratch buffer for the caret line under the offending source line
    err_caret_buf   resb 132
    ; Number-print scratch buffer (digits written back-to-front)
    print_num_buf   resb 16

section .text
    global parse_program
    global compile_error
    
    extern next_token
    extern get_error_loc
    extern lexer_peek_token
    extern tok_type
    extern tok_str_ptr
    extern tok_str_len
    extern tok_ival
    extern tok_fval
    extern src_ptr
    extern src_idx
    extern src_len
    extern line_num
    extern line_start_idx

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
    extern sym_is_private
    extern sym_set_const
    extern sym_is_const
    extern sym_lookup_module
    extern sym_count
    extern sym_remove_block_scope
    extern sym_remove_after
    extern proto_lookup
    extern proto_lookup_module
    extern proto_resolve_call
    extern proto_get_private
    extern proto_get_param_count
    extern proto_get_ret_count
    extern proto_set_param_var_idx
    extern proto_get_ret_conc_type

    extern current_module
    extern current_sym_module
    extern module_lookup
    extern module_get_kind
    extern module_get_status
    extern module_import_add
    extern module_parse_depth
    extern parse_module_body

    extern alloc_vreg
    extern emit_ir
    extern type_name_buf
    extern type_lookup
    extern type_get_kind
    extern type_struct_field_at

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
    ; Struct construction scratch pool bump offset into the OUTPUT's data
    ; segment (STRUCT_SCRATCH_BASE). Absolute base + offset is emitted as the
    ; LEA_VAR imm, so constructions land in the running program's mapped bss
    ; instead of rexc's own buffer address.
    mov dword [struct_scratch_ptr], 0
    
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
    cmp eax, TOK_PROT
    je .loop
    cmp eax, TOK_AT
    je .loop
    cmp eax, TOK_COLON
    je .loop
    cmp eax, TOK_USE
    je .loop
    cmp eax, TOK_MODULE
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
    ; Emit halt — but only for the outermost file. File modules return their
    ; IR inline into the using file's stream at the first-`use` site, so a
    ; module-level halt would stop the program mid-parse.
    cmp dword [module_parse_depth], 0
    jne .done_no_halt
    mov rdi, IR_HALT
    xor rsi, rsi
    xor rdx, rdx
    xor rcx, rcx
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir
.done_no_halt:
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
    
    cmp eax, TOK_SWAP
    je .swap_stmt
    
    cmp eax, TOK_PLUSPLUS
    je .inc_dec_prefix
    cmp eax, TOK_MINUSMINUS
    je .inc_dec_prefix
    
    cmp eax, TOK_PROT
    je .prot_stmt
    
    cmp eax, TOK_SWITCH
    je .switch_stmt
    
    cmp eax, TOK_ASSERT
    je .assert_stmt
    
    cmp eax, TOK_UNREACHABLE
    je .unreachable_stmt
    
    cmp eax, TOK_WITH
    je .with_stmt
    
    cmp eax, TOK_USE
    je .use_stmt
    
    cmp eax, TOK_MODULE
    je .module_stmt
    
    ; Unknown statement — try as expression statement
    call parse_expr
    ret

; ============ Assert Statement ============
; assert(<expr>)                 → abort "AssertionError: assertion failed"
; assert(<expr>, "<msg>")        → abort "AssertionError: <msg>"
.assert_stmt:
    push r12
    push r13
    call advance ; consume 'assert'
    mov edi, TOK_LPAREN
    call expect
    call parse_expr ; rax = cond vreg, rdx = type
    mov r12, rax ; cond vreg
    ; Optional message: ',' <str literal>
    mov r13, 0 ; r13 = msg vreg (0 = none)
    mov eax, [current_token]
    cmp eax, TOK_COMMA
    jne .assert_no_msg
    call advance
    mov eax, [current_token]
    cmp eax, TOK_STR_LIT
    jne .assert_syntax_err
    ; Emit IR_LOAD_STR for the message
    push qword [tok_str_len]
    push qword [tok_str_ptr]
    call advance
    call alloc_vreg
    mov r13, rax ; msg vreg
    mov rdi, IR_LOAD_STR
    mov rsi, TYPE_STR
    mov rdx, r13
    xor rcx, rcx
    xor r8, r8
    mov r9, [rsp]
    mov r10, [rsp + 8]
    call emit_ir
    add rsp, 16
.assert_no_msg:
    mov edi, TOK_RPAREN
    call expect
    ; If no message, emit default string
    test r13, r13
    jnz .assert_msg_ready
    lea rdi, [str_assert_default]
    mov rsi, str_assert_default_len
    call .emit_load_str_len ; rax = msg vreg (str ptr)
    mov r13, rax
.assert_msg_ready:
    ; If cond != true, abort with message
    call gen_label
    push rax ; ok_label
    mov rdi, rax
    mov rsi, COND_EQ ; jump if cond == true
    mov rcx, r12
    call emit_jcc
    ; abort(msg)
    mov rdi, IR_ABORT
    xor rsi, rsi
    xor rdx, rdx
    mov rcx, r13
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir
    ; ok_label:
    pop rdi
    call emit_label
    pop r13
    pop r12
    ret
.assert_syntax_err:
    mov rdi, err_syntax
    jmp compile_error

; ============ Unreachable Statement ============
; unreachable() → abort "UnreachableError: reached unreachable code"
.unreachable_stmt:
    push r12
    call advance ; consume 'unreachable'
    mov edi, TOK_LPAREN
    call expect
    mov edi, TOK_RPAREN
    call expect
    ; Emit default message
    lea rdi, [str_unreachable_default]
    mov rsi, str_unreachable_default_len
    call .emit_load_str_len ; rax = msg vreg
    mov r12, rax
    ; abort(msg)
    mov rdi, IR_ABORT
    xor rsi, rsi
    xor rdx, rdx
    mov rcx, r12
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir
    pop r12
    ret

; Helper: emit IR_LOAD_STR for a constant string.
; rdi = string ptr, rsi = length. Returns rax = vreg (str ptr).
.emit_load_str_len:
    push rdi
    push rsi
    call alloc_vreg
    mov rdx, rax ; dst vreg
    mov rdi, IR_LOAD_STR
    mov rsi, TYPE_STR
    ; rdx = dst
    xor rcx, rcx
    xor r8, r8
    pop r10 ; length
    pop r9  ; string ptr
    call emit_ir
    mov rax, rdx ; return vreg (emit_ir clobbers rax)
    ret

; ============ Protocol Definition ============
; prot <IDENT> "(" params ")" ["->" return_type] ":" NEWLINE INDENT body DEDENT
.prot_stmt:
    call advance ; consume 'prot' → IDENT
    mov eax, [current_token]
    cmp eax, TOK_IDENT
    jne expected_ident

    ; Protocol was pre-registered by the prescan (same name + module)
    mov rdi, [tok_str_ptr]
    mov rsi, [tok_str_len]
    mov edx, [current_module]
    call proto_lookup_module
    cmp rax, -1
    je .prot_undef
    mov r14, rax ; proto_id

    ; Emit JMP over the body (so main code does not fall into it)
    call gen_label
    mov r15, rax ; end label
    mov rdi, r15
    call emit_jmp

    ; IR_PROTO_BEGIN(imm = proto_id)
    mov rdi, IR_PROTO_BEGIN
    xor rsi, rsi
    xor rdx, rdx
    xor rcx, rcx
    xor r8, r8
    mov r9, r14
    xor r10, r10
    call emit_ir

    ; Enter protocol body context: params/vars become SCOPE_LOCAL.
    ; (parse_block increments block_nesting itself when it enters the body.)
    inc dword [proto_body_nesting]
    mov eax, [sym_count]
    mov [prot_sym_save], eax

    ; Parse "(" params ")"
    call advance ; consume name → '('
    mov edi, TOK_LPAREN
    call expect ; consume '('

    xor r12d, r12d ; param index
.param_loop:
    mov eax, [current_token]
    cmp eax, TOK_RPAREN
    je .param_done
    ; param ::= type_expr IDENT
    mov eax, [current_token]
    cmp eax, TOK_TYPE
    jne .prot_syntax_err
    mov ebx, [tok_ival] ; type
    call advance ; consume type
    ; optional [T] / [T, N] suffix
    mov eax, [current_token]
    cmp eax, TOK_LBRACKET
    jne .param_no_suffix
.param_skip:
    call advance
    mov eax, [current_token]
    cmp eax, TOK_RBRACKET
    jne .param_skip
    call advance ; consume ']'
.param_no_suffix:
    mov eax, [current_token]
    cmp eax, TOK_IDENT
    jne expected_ident
    call save_ident
    call advance ; consume IDENT
    ; sym_add(name, len, type, SCOPE_LOCAL)
    mov rdi, ident_buf
    mov rsi, [ident_len]
    mov rdx, rbx
    mov rcx, SCOPE_LOCAL
    call sym_add
    cmp rax, -2
    je dup_error
    cmp rax, -1
    je full_error
    mov r13, rax ; sym index
    ; Params arrive initialised and mutable
    mov rdi, r13
    mov rsi, 1
    call sym_set_init
    mov rdi, r13
    mov rsi, 1
    call sym_set_mutable
    ; Record param var slot
    mov rdi, r13
    call sym_get_offset
    mov rbx, rax ; var abs offset
    mov rdi, r14 ; proto_id
    mov rsi, r12 ; arg index
    mov rdx, rbx ; var offset
    call proto_set_param_var_idx
    ; IR_SAVE_ARG(imm = arg index, aux = var offset)
    mov rdi, IR_SAVE_ARG
    xor rsi, rsi
    xor rdx, rdx
    xor rcx, rcx
    xor r8, r8
    mov r9, r12
    mov r10, rbx
    call emit_ir
    inc r12d
    ; ',' or ')'
    mov eax, [current_token]
    cmp eax, TOK_COMMA
    jne .param_loop
    call advance
    jmp .param_loop
.param_done:
    mov edi, TOK_RPAREN
    call expect ; consume ')'

    ; Optional return type: skip tokens until ':' (validated by prescan)
    mov eax, [current_token]
    cmp eax, TOK_ARROW
    jne .prot_no_ret
.prot_ret_skip:
    call advance
    mov eax, [current_token]
    cmp eax, TOK_COLON
    je .prot_no_ret
    cmp eax, TOK_EOF
    je .prot_syntax_err
    jmp .prot_ret_skip
.prot_no_ret:
    mov edi, TOK_COLON
    call expect ; consume ':'

    ; Parse the body
    call parse_block

    ; Fall-through return (void). Explicit `return` statements already
    ; emitted their own IR_RET inside the body.
    mov rdi, IR_RET
    xor rsi, rsi
    xor rdx, rdx
    xor rcx, rcx
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir

    ; End label (the JMP-over-body target)
    mov rdi, r15
    call emit_label

    ; Leave protocol body context: drop all body-local symbols so the
    ; next body reuses the same var slots (VAR_MAX is small).
    mov edi, [prot_sym_save]
    call sym_remove_after
    dec dword [proto_body_nesting]
    ret

.prot_undef:
    mov rdi, err_unknown_proto
    jmp compile_error
.prot_syntax_err:
    mov rdi, err_syntax
    jmp compile_error

; ============ Use Statement ============
; use <mod>            — star import
; use <mod> : <a>, <b> — selective import
; A file module's init statements are emitted inline into the IR here on its
; first `use` (once, in declaration order). Inline modules emit at their
; definition site instead.
.use_stmt:
    push rbx
    push r12
    push r13
    call advance ; consume 'use' → IDENT (module name)
    mov eax, [current_token]
    cmp eax, TOK_IDENT
    jne expected_ident
    ; Resolve the module (registered by the prescan).
    mov rdi, [tok_str_ptr]
    mov rsi, [tok_str_len]
    call module_lookup
    cmp rax, -1
    je .use_undef
    mov r12, rax ; module id
    call advance ; consume module name
    ; Optional ': import_list'
    mov eax, [current_token]
    cmp eax, TOK_COLON
    jne .use_no_imports
    call advance ; consume ':'
    mov eax, [current_token]
    cmp eax, TOK_STAR
    je .use_star
    jmp .use_import_item
.use_import_item:
    mov eax, [current_token]
    cmp eax, TOK_IDENT
    jne expected_ident
    ; Record the import into the current module.
    mov rdi, r12          ; target module
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    xor ecx, ecx          ; is_star = 0
    call module_import_add
    call advance ; consume import name
    mov eax, [current_token]
    cmp eax, TOK_COMMA
    jne .use_no_imports
    call advance
    jmp .use_import_item
.use_star:
    ; Star import: name ptr = 0, is_star = 1.
    mov rdi, r12
    xor esi, esi
    xor edx, edx
    mov ecx, 1
    call module_import_add
    call advance ; consume '*'
.use_no_imports:
    ; First `use` of a file module emits its init code here.
    mov rdi, r12
    call module_get_kind
    cmp rax, MOD_KIND_INLINE
    je .use_done
    mov rdi, r12
    call module_get_status
    cmp rax, MOD_ST_PARSED
    je .use_done
    mov rdi, r12
    call parse_module_body
.use_done:
    pop r13
    pop r12
    pop rbx
    ret
.use_undef:
    mov rdi, err_unknown_module
    jmp compile_error

; ============ Module Definition (inline) ============
; module <IDENT> ":" NEWLINE INDENT { top_level_item } DEDENT
.module_stmt:
    push rbx
    push r12
    call advance ; consume 'module' → IDENT
    mov eax, [current_token]
    cmp eax, TOK_IDENT
    jne expected_ident
    ; Resolve the inline module registered by the prescan.
    mov rdi, [tok_str_ptr]
    mov rsi, [tok_str_len]
    call module_lookup
    cmp rax, -1
    je .mod_stmt_undef
    mov r12, rax ; module id
    ; Only inline modules have a body in this file (a file module reached
    ; here means the name collides across a `use` and an inline block).
    mov rdi, r12
    call module_get_kind
    cmp rax, MOD_KIND_INLINE
    jne .mod_stmt_conflict
    ; Nested module blocks are illegal (grammar.md §10.3).
    cmp dword [module_parse_depth], 0
    jne .mod_stmt_nested
    call advance ; consume module name → ':'
    mov edi, TOK_COLON
    call expect
    ; Expect NEWLINE INDENT body DEDENT (not parse_block: its block_nesting
    ; increment would demote module globals to SCOPE_LOCAL).
    mov eax, [current_token]
    cmp eax, TOK_NEWLINE
    jne .mod_stmt_syntax
    call advance
    mov eax, [current_token]
    cmp eax, TOK_INDENT
    jne .mod_stmt_syntax
    call advance ; consume INDENT
    ; Switch context to the module for its body. Its init statements run
    ; inline here (once, at this position in the flat IR stream).
    mov eax, [current_module]
    push rax
    mov eax, [current_sym_module]
    push rax
    mov dword [current_module], r12d
    mov dword [current_sym_module], r12d
    inc dword [module_parse_depth]
.mod_body_loop:
    mov eax, [current_token]
    cmp eax, TOK_DEDENT
    je .mod_body_done
    cmp eax, TOK_EOF
    je .mod_body_done
    call parse_stmt
    mov eax, [current_token]
    cmp eax, TOK_NEWLINE
    jne .mod_body_loop
    call advance
    jmp .mod_body_loop
.mod_body_done:
    call advance ; consume DEDENT
    dec dword [module_parse_depth]
    pop rax
    mov [current_sym_module], eax
    pop rax
    mov [current_module], eax
    pop r12
    pop rbx
    ret
.mod_stmt_undef:
    mov rdi, err_unknown_module
    jmp compile_error
.mod_stmt_conflict:
    mov rdi, err_nested_module
    jmp compile_error
.mod_stmt_nested:
    mov rdi, err_nested_module
    jmp compile_error
.mod_stmt_syntax:
    mov rdi, err_syntax
    jmp compile_error

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
    
    ; Mark as constant — mutation via ':' is forbidden (design.md §4.17)
    mov rdi, r14
    mov rsi, 1
    call sym_set_const
    
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
    je .struct_type_token
    cmp eax, TOK_IDENT
    je .struct_ident_type
    jmp .struct_syntax_err

.struct_type_token:
    mov r14, [tok_ival] ; field_type_id
    call advance ; consume TYPE
    jmp .struct_field_name

.struct_ident_type:
    ; User-defined field type (e.g. a nested struct)
    mov rdi, [tok_str_ptr]
    mov rsi, [tok_str_len]
    call type_lookup
    cmp rax, -1
    je .struct_syntax_err
    mov r14, rax ; field_type_id
    call advance ; consume IDENT

.struct_field_name:
    mov eax, [current_token]
    cmp eax, TOK_IDENT
    jne .struct_syntax_err
    
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    push rsi
    push rdx
    ; Allocate a unique slot in type_name_buf for this field name
    ; (M8 fix: previously every field copied to offset 0, so all field
    ;  names shared one pointer and type_struct_find_field could only ever
    ;  match the LAST field declared.)
    extern type_name_idx
    mov r15d, [type_name_idx]   ; r15 = slot offset (type_name_idx is a dword)
    cmp r15d, TYPE_NAME_BUF_SIZE - 2
    jge .field_name_skip        ; no room — store field without a name copy
    mov rcx, rdx
    lea rax, [r15 + rcx + 1]
    cmp rax, TYPE_NAME_BUF_SIZE
    jbe .field_name_fits
    mov rcx, TYPE_NAME_BUF_SIZE - 1
    sub rcx, r15
    jbe .field_name_skip
.field_name_fits:
    lea rdi, [type_name_buf + r15]
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
    mov rbx, rcx ; save length (rbx survives advance/expect below)
    ; Advance type_name_idx by len + 1
    lea eax, [rcx + 1]
    add dword [type_name_idx], eax
    jmp .field_name_add
.field_name_skip:
    mov rbx, rdx ; save raw length; no stable name copy (buffer full)
.field_name_add:
    pop rdx
    pop rsi
    call advance ; consume IDENT
    
    mov edi, TOK_NEWLINE
    call expect
    
    ; Align field offset to 8 bytes (fields hold qwords/pointers)
    lea r13, [r13 + 7]
    and r13, -8

    ; Add field
    mov rdi, r12 ; struct_type_id
    lea rsi, [type_name_buf + r15] ; field_name_ptr (unique stable copy)
    mov rdx, rbx ; field_name_len
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
    push rax ; save else_label on stack (above end_label; parse_block
             ; clobbers r14, so both labels live on the stack)

    ; Emit JCC to else_label if condition != true (COND_NE)
    ; The JCC codegen already does CMP reg, 1 before the jump
    mov rdi, [rsp]     ; target label (else_label)
    mov rsi, COND_NE   ; condition code
    mov rcx, r12       ; condition vreg to test
    call emit_jcc

    ; Parse then body
    call parse_block

    ; Emit JMP to end_label (skip else branches)
    mov rdi, [rsp + 8] ; end_label from stack
    call emit_jmp

    ; Check for elif/else
.if_chain:
    mov eax, [current_token]
    cmp eax, TOK_NEWLINE
    jne .if_chain_cont
    call advance ; single-line bodies end with a NEWLINE before the next
                 ; elif/else keyword on the following line
    mov eax, [current_token]
.if_chain_cont:
    cmp eax, TOK_ELIF
    je .elif_branch
    cmp eax, TOK_ELSE
    je .else_branch
    ; No else — emit else_label and end_label
    pop rdi ; else_label
    call emit_label
    pop rdi ; end_label
    call emit_label
    ret

.elif_branch:
    ; Emit JMP to end_label (skip remaining branches)
    mov rdi, [rsp + 8] ; end_label from stack
    call emit_jmp

    ; Emit else_label (this elif's entry point)
    pop rdi ; else_label
    call emit_label

    call advance ; consume 'elif'
    call parse_expr ; elif condition
    mov r12, rax

    mov edi, TOK_COLON
    call expect

    ; Generate next else label
    call gen_label
    push rax ; save next else_label on stack

    ; JCC to next else if condition false
    ; The JCC codegen already does CMP reg, 1 before the jump
    mov rdi, [rsp]
    mov rsi, COND_NE
    mov rcx, r12
    call emit_jcc

    ; Parse elif body
    call parse_block
    jmp .if_chain

.else_branch:
    ; Emit JMP to end_label
    mov rdi, [rsp + 8]
    call emit_jmp

    ; Emit else_label
    pop rdi ; else_label
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

; ============ With Statement ============
; with open(path [, mode]) as <ident>:
;     <body>
; The handle is opened before the body and closed (IR_FILE_CLOSE) after it.
.with_stmt:
    call advance ; consume 'with'
    call parse_expr ; rax = handle vreg, rdx = type
    mov r15, rax ; save handle vreg across sym_add
    cmp rdx, TYPE_FILE
    jne .with_type_err

    mov edi, TOK_AS
    call expect ; consume 'as'
    mov eax, [current_token]
    cmp eax, TOK_IDENT
    jne expected_ident
    call save_ident
    call advance ; consume IDENT

    ; Add alias symbol: sym_add(name, len, TYPE_FILE, scope)
    mov rdi, ident_buf
    mov rsi, [ident_len]
    call determine_scope
    mov rcx, rax ; scope
    mov rdi, ident_buf
    mov rsi, [ident_len]
    mov rdx, TYPE_FILE
    call sym_add
    cmp rax, -2
    je dup_error
    cmp rax, -1
    je full_error
    mov r14, rax ; sym index

    ; Mark initialized and store the handle into the alias variable
    mov rdi, r14
    mov rsi, 1
    call sym_set_init
    mov rdi, r14
    call sym_get_offset
    mov r9, rax ; imm = var offset
    mov rdi, IR_STORE_VAR
    mov rsi, TYPE_FILE
    xor rdx, rdx
    mov rcx, r15 ; src1 = handle vreg
    xor r8, r8
    xor r10, r10
    call emit_ir

    mov edi, TOK_COLON
    call expect ; consume ':'

    ; Save handle vreg on the stack across parse_block (parse_block may
    ; clobber r15); restore it afterwards for the auto-close.
    push r15
    call parse_block
    pop r15

    ; Auto-close the file after the body
    mov rdi, IR_FILE_CLOSE
    mov rsi, TYPE_FILE
    xor rdx, rdx ; dst = 0 (void)
    mov rcx, r15 ; src1 = handle vreg
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir
    ret

.with_type_err:
    mov rdi, err_type_mismatch
    jmp compile_error

; ============ Switch Statement ============
; switch <expr>:
;     -> <pattern>[, <pattern>]*:
;         <case block>
;     _:
;         <default block>
; Patterns: value literals, variables/enum variants (Enum.variant or plain),
; and half-open ranges a..b (a <= subject < b).
.switch_stmt:
    call advance ; consume 'switch'

    ; Parse subject expression
    call parse_expr ; rax = subject vreg, rdx = subject type
    mov r12, rax ; subject vreg
    mov r13, rdx ; subject type

    mov edi, TOK_COLON
    call expect

    ; Consume NEWLINE + INDENT (switch body)
    mov eax, [current_token]
    cmp eax, TOK_NEWLINE
    jne .switch_syntax_err
    call advance
    mov eax, [current_token]
    cmp eax, TOK_INDENT
    jne .switch_syntax_err
    call advance

    ; end_label for jumping past all cases
    call gen_label
    push rax ; [rsp+24] = end_label

    ; r15 = next_label: entry for next case / default
    call gen_label
    mov r15, rax

    ; Keep switch state on the stack so case bodies (parse_block and the
    ; statements inside) cannot clobber it. Layout:
    ;   [rsp]    = default-seen flag (0 = none yet)
    ;   [rsp+8]  = subject vreg
    ;   [rsp+16] = subject type
    ;   [rsp+24] = end_label
    push r13 ; subject type
    push r12 ; subject vreg
    push 0   ; default-seen flag

.switch_case_loop:
    mov r14, [rsp] ; default flag (may have been clobbered by a case body)
    mov eax, [current_token]
    cmp eax, TOK_DEDENT
    je .switch_done
    cmp eax, TOK_ARROW
    je .switch_case
    cmp eax, TOK_IDENT
    jne .switch_syntax_err
    ; Could be '_' (default case)
    cmp qword [tok_str_len], 1
    jne .switch_syntax_err
    mov rcx, [tok_str_ptr]
    cmp byte [rcx], '_'
    jne .switch_syntax_err
    ; Default case (must be last)
    cmp r14, 1
    je .switch_syntax_err
    jmp .switch_default

.switch_case:
    ; No case lines may follow the default
    cmp r14, 1
    je .switch_syntax_err
    call advance ; consume '->'

    ; Emit next_label = this case's entry point. Placed BEFORE the
    ; conditions so the previous case's fall-through JCC lands on the
    ; condition evaluation (a non-match falls through to test this case).
    mov rdi, r15
    call emit_label

    ; Reload subject vreg/type (a previous case body may have clobbered them)
    mov r12, [rsp+8]  ; subject vreg
    mov r13, [rsp+16] ; subject type

    ; Build combined condition: OR of each pattern's match
    xor rbx, rbx ; rbx = combined cond vreg (0 = none yet)

.switch_pat_loop:
    ; Parse one pattern value
    call .parse_switch_pattern_value ; rax = vreg, rdx = type
    mov r8, rax ; pattern vreg
    mov r9, rdx ; pattern type

    ; Check for range: '..'
    mov eax, [current_token]
    cmp eax, TOK_DOTDOT
    je .switch_range

    ; Single-value match
    push rbx ; save combined
    mov rdi, r12 ; subject
    mov rsi, r8  ; pattern
    mov rdx, r9  ; pattern type
    mov rcx, r13 ; subject type
    call .emit_pattern_match ; rax = cond vreg
    pop rbx
    mov rcx, rax
    jmp .switch_or

.switch_range:
    push r8 ; save low vreg across advance + high-value parse
    push r9 ; save low pattern type across advance + high-value parse
    call advance ; consume '..'
    call .parse_switch_pattern_value ; rax = vreg (high), rdx = type
    mov r10, rax ; high vreg
    pop rcx ; pattern type (low type)
    pop r8  ; low vreg
    push rbx ; save combined
    mov rdi, r12 ; subject
    mov rsi, r8  ; low
    mov rdx, r10 ; high
    mov r8, r13  ; subject type
    call .emit_range_match ; rax = cond vreg
    pop rbx
    mov rcx, rax

.switch_or:
    test rbx, rbx
    jz .switch_or_first
    ; rbx = rbx OR rcx
    push rbx
    push rcx
    call alloc_vreg
    mov rdx, rax ; dst
    pop r8       ; second operand
    pop rcx      ; first operand
    push rdx
    mov rdi, IR_BOOL_OR
    mov rsi, TYPE_BOOL
    mov rdx, [rsp]
    xor r9, r9
    xor r10, r10
    call emit_ir
    pop rbx ; new combined cond
    jmp .switch_pat_next
.switch_or_first:
    mov rbx, rcx
.switch_pat_next:
    ; comma → another pattern
    mov eax, [current_token]
    cmp eax, TOK_COMMA
    jne .switch_pat_done
    call advance
    jmp .switch_pat_loop
.switch_pat_done:

    ; Expect ':'
    mov edi, TOK_COLON
    call expect

    ; Generate fall-through label for "not matched"
    push rbx
    call gen_label
    mov r10, rax
    pop rbx

    ; If not matched, jump to fall-through
    push rbx
    push r10
    mov rdi, r10
    mov rsi, COND_NE
    mov rcx, rbx
    call emit_jcc
    pop r10
    pop rbx

    ; Parse case block (may clobber r10/r12/r13/r14/r15)
    push r10 ; save fall-through label across parse_block
    call parse_block
    pop r10

    ; Jump past end
    mov r15, r10 ; next case entry = fall-through label
    mov rdi, [rsp+24] ; end_label
    call emit_jmp
    jmp .switch_case_loop

.switch_default:
    mov r14, 1
    mov [rsp], r14 ; persist default flag
    call advance ; consume '_'
    mov edi, TOK_COLON
    call expect
    ; Emit next_label = default entry
    mov rdi, r15
    call emit_label
    ; Parse default block
    call parse_block
    ; Jump past end
    mov rdi, [rsp+24] ; end_label
    call emit_jmp
    jmp .switch_done

.switch_done:
    call advance ; consume DEDENT
    mov r14, [rsp] ; default flag
    cmp r14, 1
    jne .switch_no_default
    jmp .switch_end_emit
.switch_no_default:
    ; No default — unmatched values fall through to end label
    mov rdi, r15
    call emit_label
.switch_end_emit:
    add rsp, 24 ; discard default flag, subject vreg, subject type
    pop rdi ; end_label
    call emit_label
    ret

.switch_syntax_err:
    mov rdi, err_syntax
    jmp compile_error

; Parse a single switch pattern value: literal, variable/enum variant,
; or negated numeric literal. Returns rax = vreg, rdx = type.
.parse_switch_pattern_value:
    mov eax, [current_token]
    cmp eax, TOK_MINUS
    je .neg_lit
    cmp eax, TOK_IDENT
    je .ident
    call parse_term
    ret
.neg_lit:
    call advance ; consume '-'
    mov eax, [current_token]
    cmp eax, TOK_INT_LIT
    jne .neg_not_int
    neg qword [tok_ival]
    jmp .lit_dispatch
.neg_not_int:
    cmp eax, TOK_FLOAT_LIT
    jne .pattern_err
    mov rax, [tok_fval]
    mov rdx, 0x8000000000000000
    xor rax, rdx
    mov [tok_fval], rax
.lit_dispatch:
    call parse_term
    ret
.ident:
    ; Save the identifier text; peek for '.' (Enum.variant)
    push qword [tok_str_ptr]
    push qword [tok_str_len]
    call advance
    mov eax, [current_token]
    cmp eax, TOK_DOT
    jne .ident_single
    ; Enum.variant — variant name follows the dot
    call advance ; consume '.'
    mov eax, [current_token]
    cmp eax, TOK_IDENT
    jne .pattern_err
    add rsp, 16 ; discard enum type name
    push qword [tok_str_len]
    push qword [tok_str_ptr]
.ident_single:
    ; stack: [rsp] = ptr, [rsp+8] = len ; current token is past the ident
    mov rax, [rsp]
    mov rbx, [rsp+8]
    mov [tok_str_ptr], rax
    mov [tok_str_len], rbx
    mov rdi, rax
    mov rsi, rbx
    call sym_lookup
    cmp rax, -1
    je .pattern_err
    mov r14, rax ; sym_idx
    push r14
    mov rdi, r14
    call sym_is_init
    test rax, rax
    jz .pattern_err
    mov rdi, r14
    call sym_get_type
    mov r15, rax ; type
    push r15
    mov rdi, r14
    call sym_get_offset
    mov r9, rax ; offset
    call alloc_vreg
    mov rbx, rax ; dst vreg
    mov rdi, IR_LOAD_VAR
    mov rsi, r15
    mov rdx, rbx
    xor rcx, rcx
    xor r8, r8
    xor r10, r10
    call emit_ir
    pop r15
    pop r14
    add rsp, 16 ; discard ptr + len
    mov rax, rbx
    mov rdx, r15
    ret
.pattern_err:
    mov rdi, err_syntax
    jmp compile_error

; Emit a match comparison: subject == pattern.
; rdi = subject vreg, rsi = pattern vreg, rdx = pattern type, rcx = subject type
; Returns rax = cond vreg (bool)
.emit_pattern_match:
    cmp rdx, rcx
    jne type_error
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi ; subject
    mov r13, rsi ; pattern
    mov r14, rdx ; type
    cmp rdx, TYPE_STR
    je .str_match
    cmp rdx, TYPE_FLOAT
    je .num_match
    jmp .int_match
.str_match:
    ; t = strcmp(subject, pattern); cond = (t == 0)
    call alloc_vreg
    mov r15, rax ; t vreg
    mov rdi, IR_STR_CMP
    mov rsi, TYPE_INT
    mov rdx, r15
    mov rcx, r12
    mov r8, r13
    xor r9, r9
    xor r10, r10
    call emit_ir
    call alloc_vreg
    mov rbx, rax ; cond vreg
    mov rdi, IR_CMP_BOOL
    mov rsi, TYPE_BOOL
    mov rdx, rbx
    mov rcx, r15
    xor r8, r8
    xor r9, r9
    xor r10, r10 ; COND_EQ
    call emit_ir
    mov rax, rbx
    jmp .done
.num_match:
    call alloc_vreg
    mov rbx, rax ; cond vreg
    mov rdi, IR_CMP_BOOL
    mov rsi, TYPE_FLOAT
    mov rdx, rbx
    mov rcx, r12
    mov r8, r13
    xor r9, r9
    xor r10, r10 ; COND_EQ
    call emit_ir
    mov rax, rbx
    jmp .done
.int_match:
    call alloc_vreg
    mov rbx, rax ; cond vreg
    mov rdi, IR_CMP_BOOL
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r12
    mov r8, r13
    xor r9, r9
    xor r10, r10 ; COND_EQ
    call emit_ir
    mov rax, rbx
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; Emit a range match: (subject >= low) and (subject < high)
; rdi = subject vreg, rsi = low vreg, rdx = high vreg,
; rcx = pattern type, r8 = subject type
; Returns rax = cond vreg (bool)
.emit_range_match:
    cmp rcx, r8
    jne type_error
    cmp rcx, TYPE_STR
    je type_error
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi ; subject
    mov r13, rsi ; low
    mov r14, rdx ; high
    mov r15, rcx ; type
    ; c1 = subject >= low (COND_GE = 5)
    call alloc_vreg
    mov rbx, rax ; c1
    mov rdi, IR_CMP_BOOL
    mov rsi, r15
    mov rdx, rbx
    mov rcx, r12
    mov r8, r13
    xor r9, r9
    mov r10, 5 ; COND_GE
    call emit_ir
    ; c2 = subject < high (COND_LT = 2)
    push rbx ; save c1
    call alloc_vreg
    mov rbx, rax ; c2
    mov rdi, IR_CMP_BOOL
    mov rsi, r15
    mov rdx, rbx
    mov rcx, r12
    mov r8, r14
    xor r9, r9
    mov r10, 2 ; COND_LT
    call emit_ir
    pop rcx ; c1
    push rbx ; c2
    ; cond = c1 and c2
    call alloc_vreg
    mov rdx, rax ; dst
    pop r8       ; c2
    mov rbx, rax ; dst
    mov rdi, IR_BOOL_AND
    mov rsi, TYPE_BOOL
    mov rdx, rbx
    ; rcx = c1, r8 = c2
    xor r9, r9
    xor r10, r10
    call emit_ir
    mov rax, rbx
    pop r15
    pop r14
    pop r13
    pop r12
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

    ; Expect '..' or '..=' (inclusive range)
    mov byte [for_inclusive], 0
    mov eax, [current_token]
    cmp eax, TOK_DOTDOT_EQ
    jne .check_excl
    mov byte [for_inclusive], 1
    jmp .range_consume
.check_excl:
    cmp eax, TOK_DOTDOT
    jne .for_syntax_err
.range_consume:
    call advance ; consume '..' or '..='

    ; Parse end expression
    call parse_expr
    mov r13, rax ; end vreg

    ; Store end value into a hidden variable __for_end
    ; so the register allocator sees fresh vregs each iteration
    ; (avoids end vreg spanning the entire loop body)
    push r13
    call build_for_hidden_name ; rdi = name ptr, rax = len
    mov rsi, rax
    mov rdx, TYPE_INT
    call determine_scope
    mov rcx, rax
    mov rdx, TYPE_INT
    call build_for_hidden_name ; rdi = name ptr, rax = len
    mov rsi, rax
    call sym_add
    cmp rax, 0
    jl .for_syntax_err ; hidden name must never collide
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

    ; Optional 'step <expr>' — store the step into a hidden __for_step variable
    ; so the increment reloads it each iteration (like __for_end). r13 holds the
    ; step symbol index (or -1 if no step was given) until the increment is emitted.
    mov r13, -1
    mov eax, [current_token]
    cmp eax, TOK_STEP
    jne .no_step
    call advance ; consume 'step'
    call parse_expr ; rax = step vreg
    push rax
    call gen_label ; unique name suffix
    call build_for_hidden_step_name ; rdi = name ptr, rax = len
    mov rsi, rax
    mov rdx, TYPE_INT
    call determine_scope
    mov rcx, rax
    mov rdx, TYPE_INT
    call build_for_hidden_step_name ; rdi = name ptr, rax = len
    mov rsi, rax
    call sym_add
    cmp rax, 0
    jl .for_syntax_err ; hidden name must never collide
    mov r13, rax ; step symbol index
    mov rdi, r13
    mov rsi, 1
    call sym_set_mutable
    mov rdi, r13
    mov rsi, 1
    call sym_set_init
    pop rax ; step vreg
    push rax ; keep step vreg while resolving the symbol offset
    mov rdi, r13
    call sym_get_offset
    mov r9, rax ; step var offset
    pop rcx ; step vreg (src1)
    mov rdi, IR_STORE_VAR
    mov rsi, TYPE_INT
    xor rdx, rdx
    xor r8, r8
    xor r10, r10
    call emit_ir
.no_step:

    mov edi, TOK_COLON
    call expect

    ; Declare loop variable as mutable int.
    ; If the name already exists in this scope (e.g. a previous loop used the
    ; same variable, or an `int i = 0` declaration), reuse the existing symbol
    ; instead of failing: the second loop simply re-initializes it.
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
    cmp rax, -2
    je .reuse_loop_var
    cmp rax, 0
    jl .for_syntax_err ; table full / other error
    jmp .loop_var_sym_done
.reuse_loop_var:
    mov rdi, ident_buf
    mov rsi, [ident_len]
    call sym_lookup
    cmp rax, -1
    je .for_syntax_err ; duplicate vanished; treat as error
.loop_var_sym_done:
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
    ; Third label = loop_else_entry (natural-exit target; design §8.6 else)
    call gen_label
    push rax
    ; Fourth label = loop_skip (target of `skip`; emitted before the increment)
    call gen_label
    push rax
    mov rdi, [rsp + 16] ; loop_end
    pop rsi             ; loop_skip
    call push_loop_context

    ; Emit loop_start label
    mov rdi, [rsp + 16]
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
    cmp byte [for_inclusive], 0
    je .cmp_cond_done
    mov r10, COND_LE ; '..=' → loop while loop_var <= end
.cmp_cond_done:
    call emit_ir

    ; JCC to loop_else_entry if NOT (loop_var < end)
    mov rdi, [rsp + 8] ; loop_else_entry
    mov rsi, COND_NE
    pop rcx ; cmp result vreg
    call emit_jcc

    ; Parse loop body (body statements may clobber r13/r14/r15 — preserve
    ; the loop-var, _for_end and _for_step symbol indices across the call)
    push r13
    push r14
    push r15
    call parse_block
    pop r15
    pop r14
    pop r13

    ; loop_skip label: `skip` lands here, before the increment step
    call emit_loop_skip_label

    ; Increment: i = i + 1 (or i + __for_step when step given)
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
    cmp r13, 0
    jl .inc_no_step
    ; Explicit step: ve = LOAD_VAR __for_step (fresh vreg each iteration)
    mov rdi, r13
    call sym_get_offset
    mov r9, rax
    mov rdi, IR_LOAD_VAR
    mov rsi, TYPE_INT
    mov rdx, [rsp]
    xor rcx, rcx
    xor r8, r8
    xor r10, r10
    call emit_ir
    jmp .inc_src_done
.inc_no_step:
    mov rdi, IR_LOAD_IMM
    mov rsi, TYPE_INT
    mov rdx, [rsp]
    xor rcx, rcx
    xor r8, r8
    mov r9, 1
    xor r10, r10
    call emit_ir
.inc_src_done:

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
    mov rdi, [rsp + 16]
    call emit_jmp

    ; Emit loop_end label (or else block + loop_end)
    call loop_else_chain
    add rsp, 24 ; drop loop_start/loop_end/loop_else_entry
    call pop_loop_context
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
    call gen_label
    push rax ; loop_else_entry on stack
    ; While has no increment section — `skip` re-checks the condition, so the
    ; skip target IS loop_start (design §8.5)
    push rax            ; temp: [temp][else_entry][loop_end][loop_start]
    mov rdi, [rsp + 16] ; loop_end
    mov rsi, [rsp + 24] ; loop_start
    pop rax             ; discard placeholder
    call push_loop_context

    ; Emit loop_start label
    mov rdi, [rsp + 16] ; loop_start
    call emit_label

    ; Parse condition
    call parse_expr
    mov r12, rax ; condition vreg

    mov edi, TOK_COLON
    call expect

    ; JCC to loop_else_entry if condition false
    ; The JCC codegen already does CMP reg, 1 before the jump
    mov rdi, [rsp] ; loop_else_entry (top of stack)
    mov rsi, COND_NE
    mov rcx, r12
    call emit_jcc

    ; Parse loop body
    call parse_block

    ; JMP back to loop_start
    mov rdi, [rsp + 16] ; loop_start
    call emit_jmp

    ; Emit loop_end label (or else block + loop_end)
    call loop_else_chain
    add rsp, 24 ; drop loop_start/loop_end/loop_else_entry
    call pop_loop_context
    ret

; ============ Each Loop ============
.each_stmt:
    call advance ; consume 'each'
    ; Element variable name
    mov eax, [current_token]
    cmp eax, TOK_IDENT
    jne expected_ident
    call save_ident
    ; Save element name into its own buffer — parse_expr below clobbers ident_buf
    mov rax, [ident_len]
    mov [each_var_len], rax
    xor rdi, rdi
.each_name_copy:
    cmp rdi, rax
    jae .each_name_done
    mov cl, [ident_buf + rdi]
    mov [each_var_buf + rdi], cl
    inc rdi
    jmp .each_name_copy
.each_name_done:
    mov byte [each_var_buf + rdi], 0
    call advance ; consume IDENT

    mov edi, TOK_IN
    call expect

    ; Parse collection expression
    call parse_expr ; rax = seq vreg, rdx = type
    cmp rdx, TYPE_SEQ
    jne .for_syntax_err
    push rax ; seq vreg on stack

    mov edi, TOK_COLON
    call expect

    ; Hidden seq variable (holds the seq pointer across the loop body)
    call build_for_hidden_name ; rdi = name ptr, rax = len
    mov rsi, rax
    mov rdx, TYPE_INT
    call determine_scope
    mov rcx, rax
    mov rdx, TYPE_INT
    call build_for_hidden_name ; rdi = name ptr, rax = len
    mov rsi, rax
    call sym_add
    cmp rax, 0
    jl .for_syntax_err
    mov r14, rax ; seq symbol index
    mov rdi, r14
    mov rsi, 1
    call sym_set_mutable
    mov rdi, r14
    mov rsi, 1
    call sym_set_init

    ; Store collection value into hidden seq variable
    mov rdi, r14
    call sym_get_offset
    mov r9, rax
    pop rcx ; seq vreg (src1)
    mov rdi, IR_STORE_VAR
    mov rsi, TYPE_SEQ
    xor rdx, rdx
    xor r8, r8
    xor r10, r10
    call emit_ir

    ; Hidden index variable (must use a distinct name — bump the counter first)
    call gen_label ; unique name suffix for the index variable
    push r14 ; save seq symbol index
    call build_for_hidden_name ; rdi = name ptr, rax = len
    mov rsi, rax
    mov rdx, TYPE_INT
    call determine_scope
    mov rcx, rax
    mov rdx, TYPE_INT
    call build_for_hidden_name ; rdi = name ptr, rax = len
    mov rsi, rax
    call sym_add
    cmp rax, 0
    jl .for_syntax_err
    mov r13, rax ; index symbol index
    mov rdi, r13
    mov rsi, 1
    call sym_set_mutable
    mov rdi, r13
    mov rsi, 1
    call sym_set_init
    pop r14 ; restore seq symbol index

    ; Store 0 into hidden index variable
    call alloc_vreg
    push rax
    mov rdi, IR_LOAD_IMM
    mov rsi, TYPE_INT
    mov rdx, [rsp]
    xor rcx, rcx
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir

    mov rdi, r13
    call sym_get_offset
    mov r9, rax
    pop rcx
    mov rdi, IR_STORE_VAR
    mov rsi, TYPE_INT
    xor rdx, rdx
    xor r8, r8
    xor r10, r10
    call emit_ir

    ; Declare element variable as mutable int.
    ; Reuse an existing symbol with the same name in this scope (same rule
    ; as `for` loop variables) instead of failing.
    push r14 ; save seq symbol index
    push r13 ; save index symbol index
    mov rdi, each_var_buf
    mov rsi, [each_var_len]
    mov rdx, TYPE_INT
    call determine_scope
    mov rcx, rax
    mov rdx, TYPE_INT
    mov rdi, each_var_buf
    mov rsi, [each_var_len]
    call sym_add
    cmp rax, -2
    je .each_reuse_var
    cmp rax, 0
    jl .for_syntax_err ; table full / other error
    jmp .each_var_sym_done
.each_reuse_var:
    mov rdi, each_var_buf
    mov rsi, [each_var_len]
    call sym_lookup
    cmp rax, -1
    je .for_syntax_err
.each_var_sym_done:
    mov r15, rax ; element symbol index

    ; Check for _ prefix → mark as private
    cmp qword [each_var_len], 1
    jl .each_not_private
    cmp byte [each_var_buf], '_'
    jne .each_not_private
    cmp qword [each_var_len], 2
    jl .each_is_private
    cmp byte [each_var_buf + 1], '_'
    je .each_not_private
.each_is_private:
    mov rdi, r15
    mov rsi, 1
    call sym_set_private
.each_not_private:

    mov rdi, r15
    mov rsi, 1
    call sym_set_mutable
    mov rdi, r15
    mov rsi, 1
    call sym_set_init
    pop r13 ; restore index symbol index
    pop r14 ; restore seq symbol index

    ; Generate loop labels
    call gen_label
    push rax ; loop_start
    call gen_label
    push rax ; loop_end
    call gen_label
    push rax ; loop_else_entry
    ; Fourth label = loop_skip (target of `skip`; emitted before index increment)
    call gen_label
    push rax
    mov rdi, [rsp + 16] ; loop_end
    pop rsi             ; loop_skip
    call push_loop_context

    ; Emit loop_start label
    mov rdi, [rsp + 16] ; loop_start
    call emit_label

    ; Load index (fresh vreg each iteration)
    call alloc_vreg
    mov rbx, rax
    mov rdi, r13
    call sym_get_offset
    mov r9, rax
    mov rdi, IR_LOAD_VAR
    mov rsi, TYPE_INT
    mov rdx, rbx
    xor rcx, rcx
    xor r8, r8
    xor r10, r10
    call emit_ir

    ; Load seq pointer (fresh vreg each iteration)
    call alloc_vreg
    mov r12, rax
    mov rdi, r14
    call sym_get_offset
    mov r9, rax
    mov rdi, IR_LOAD_VAR
    mov rsi, TYPE_SEQ
    mov rdx, r12
    xor rcx, rcx
    xor r8, r8
    xor r10, r10
    call emit_ir

    ; len = seq.len()
    call alloc_vreg
    push rax
    mov rdi, IR_SEQ_LEN
    mov rsi, TYPE_INT
    mov rdx, [rsp] ; dst
    mov rcx, r12 ; seq vreg
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir

    ; Compare: index < len
    call alloc_vreg
    push rax
    mov rdi, IR_CMP_BOOL
    mov rsi, TYPE_BOOL
    mov rdx, [rsp] ; dst
    mov rcx, rbx ; index vreg (src1)
    mov r8, [rsp + 8] ; len vreg (src2)
    xor r9, r9
    mov r10, COND_LT
    call emit_ir

    ; JCC to loop_else_entry if NOT (index < len)
    mov rdi, [rsp + 16] ; loop_else_entry
    mov rsi, COND_NE
    pop rcx ; cmp result vreg
    pop r12 ; len vreg (discard)
    call emit_jcc

    ; element = seq[index]
    call alloc_vreg
    mov rbx, rax ; index vreg
    mov rdi, r13
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
    mov r12, rax ; seq vreg
    mov rdi, r14
    call sym_get_offset
    mov r9, rax
    mov rdi, IR_LOAD_VAR
    mov rsi, TYPE_SEQ
    mov rdx, r12
    xor rcx, rcx
    xor r8, r8
    xor r10, r10
    call emit_ir

    call alloc_vreg
    push rax
    mov rdi, IR_SEQ_LOAD
    mov rsi, TYPE_INT
    mov rdx, [rsp] ; dst
    mov rcx, r12 ; seq vreg (src1)
    mov r8, rbx ; index vreg (src2)
    mov r9, SEQ_ELEMENT_SIZE
    xor r10, r10
    call emit_ir

    ; Store element value into element variable
    mov rdi, r15
    call sym_get_offset
    mov r9, rax
    pop rcx ; element vreg
    mov rdi, IR_STORE_VAR
    mov rsi, TYPE_INT
    xor rdx, rdx
    xor r8, r8
    xor r10, r10
    call emit_ir

    ; Parse loop body (body statements may clobber r13/r14/r15 — preserve
    ; the seq/index/element symbol indices across the call)
    push r13
    push r14
    push r15
    call parse_block
    pop r15
    pop r14
    pop r13

    ; loop_skip label: `skip` lands here, before the index increment
    call emit_loop_skip_label

    ; Increment: index = index + 1
    call alloc_vreg
    mov rbx, rax
    mov rdi, r13
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

    mov rdi, r13
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
    mov rdi, [rsp + 16]
    call emit_jmp

    ; Emit loop_end label (or else block + loop_end)
    call loop_else_chain
    add rsp, 24 ; drop loop_start/loop_end/loop_else_entry
    call pop_loop_context
    ret

; ============ Repeat Loop ============
.repeat_stmt:
    call advance ; consume 'repeat'
    call parse_expr ; count expression vreg in rax
    cmp rdx, TYPE_INT
    jne .for_syntax_err
    push rax ; count vreg on stack
    mov edi, TOK_COLON
    call expect

    ; Hidden counter variable (holds the remaining count across the loop body)
    call build_for_hidden_name ; rdi = name ptr, rax = len
    mov rsi, rax
    mov rdx, TYPE_INT
    call determine_scope
    mov rcx, rax
    mov rdx, TYPE_INT
    call build_for_hidden_name ; rdi = name ptr, rax = len
    mov rsi, rax
    call sym_add
    cmp rax, 0
    jl .for_syntax_err
    mov r14, rax ; counter symbol index
    mov rdi, r14
    mov rsi, 1
    call sym_set_mutable
    mov rdi, r14
    mov rsi, 1
    call sym_set_init

    ; Store count value into hidden counter variable
    mov rdi, r14
    call sym_get_offset
    mov r9, rax
    pop rcx ; count vreg (src1)
    mov rdi, IR_STORE_VAR
    mov rsi, TYPE_INT
    xor rdx, rdx
    xor r8, r8
    xor r10, r10
    call emit_ir

    ; Generate loop labels
    call gen_label
    push rax ; loop_start
    call gen_label
    push rax ; loop_end
    call gen_label
    push rax ; loop_else_entry
    ; Fourth label = loop_skip (target of `skip`; emitted before the decrement)
    call gen_label
    push rax
    mov rdi, [rsp + 16] ; loop_end
    pop rsi             ; loop_skip
    call push_loop_context

    ; Emit loop_start label
    mov rdi, [rsp + 16] ; loop_start
    call emit_label

    ; Load counter (fresh vreg each iteration)
    call alloc_vreg
    mov rbx, rax
    mov rdi, r14
    call sym_get_offset
    mov r9, rax
    mov rdi, IR_LOAD_VAR
    mov rsi, TYPE_INT
    mov rdx, rbx
    xor rcx, rcx
    xor r8, r8
    xor r10, r10
    call emit_ir

    ; Compare: counter > 0
    call alloc_vreg
    push rax
    mov rdi, IR_CMP_BOOL
    mov rsi, TYPE_BOOL
    mov rdx, [rsp] ; dst
    mov rcx, rbx ; counter vreg (src1)
    xor r8, r8 ; src2 = 0 (use imm)
    xor r9, r9 ; imm = 0
    mov r10, COND_GT
    call emit_ir

    ; JCC to loop_else_entry if NOT (counter > 0)
    mov rdi, [rsp + 8] ; loop_else_entry
    mov rsi, COND_NE
    pop rcx ; cmp result vreg
    call emit_jcc

    ; Parse loop body (body statements may clobber r14/r15 — preserve
    ; the counter symbol index across the call)
    push r14
    push r15
    call parse_block
    pop r15
    pop r14

    ; loop_skip label: `skip` lands here, before the decrement
    call emit_loop_skip_label

    ; Decrement: counter = counter - 1
    call alloc_vreg
    mov rbx, rax
    mov rdi, r14
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
    mov rdi, IR_SUB
    mov rsi, TYPE_INT
    mov rdx, [rsp]
    mov rcx, rbx
    mov r8, [rsp + 8]
    xor r9, r9
    xor r10, r10
    call emit_ir

    mov rdi, r14
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
    mov rdi, [rsp + 16]
    call emit_jmp

    ; Emit loop_end label (or else block + loop_end)
    call loop_else_chain
    add rsp, 24 ; drop loop_start/loop_end/loop_else_entry
    call pop_loop_context
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
    mov r12, rax
    ; Multi-return: "return a, b"
    mov eax, [current_token]
    cmp eax, TOK_COMMA
    jne .return_single
    call advance ; consume ','
    call parse_expr ; second return value in rax
    ; Emit IR_RET with src1 = first, src2 = second
    mov rdi, IR_RET
    xor rsi, rsi
    xor rdx, rdx
    mov rcx, r12
    mov r8, rax
    xor r9, r9
    xor r10, r10
    call emit_ir
    ret
.return_single:
    ; Emit IR_RET with return value vreg
    mov rdi, IR_RET
    xor rsi, rsi        ; type = void (return type)
    xor rdx, rdx        ; dst = 0 (void)
    mov rcx, r12        ; src1 = return value vreg
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir
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
; Grammar: stop_stmt ::= "stop" <INTEGER-LITERAL>? <NEWLINE>
; stop → break innermost loop; stop N → break N levels (design §8.5)
.stop_stmt:
    call advance ; consume 'stop'
    mov edx, 1 ; depth (default 1)
    mov eax, [current_token]
    cmp eax, TOK_INT_LIT
    jne .stop_no_arg
    mov rcx, [tok_ival]
    cmp rcx, 1
    jl .stop_depth_err
    mov edx, ecx
    push rdx
    call advance ; consume depth literal
    pop rdx
.stop_no_arg:
    ; Compile-time check: depth must not exceed current nesting
    mov ecx, [loop_depth]
    cmp edx, ecx
    jg .stop_outside_err
    ; Target the loop N levels up from the innermost: slot [loop_depth - depth]
    sub ecx, edx
    lea rax, [loop_end_labels]
    mov rdi, [rax + rcx * 8]
    call emit_jmp
    ret
.stop_depth_err:
    mov rdi, err_loop_ctl_depth
    jmp compile_error
.stop_outside_err:
    mov rdi, err_loop_ctl_outside
    jmp compile_error

; ============ Skip ============
; Grammar: skip_stmt ::= "skip" <INTEGER-LITERAL>? <NEWLINE>
; skip → continue innermost loop; skip N → continue N levels (design §8.5)
.skip_stmt:
    call advance ; consume 'skip'
    mov edx, 1 ; depth (default 1)
    mov eax, [current_token]
    cmp eax, TOK_INT_LIT
    jne .skip_no_arg
    mov rcx, [tok_ival]
    cmp rcx, 1
    jl .skip_depth_err
    mov edx, ecx
    push rdx
    call advance ; consume depth literal
    pop rdx
.skip_no_arg:
    mov ecx, [loop_depth]
    cmp edx, ecx
    jg .skip_outside_err
    ; Target the loop N levels up from the innermost: slot [loop_depth - depth]
    sub ecx, edx
    lea rax, [loop_skip_labels]
    mov rdi, [rax + rcx * 8]
    call emit_jmp
    ret
.skip_depth_err:
    mov rdi, err_loop_ctl_depth
    jmp compile_error
.skip_outside_err:
    mov rdi, err_loop_ctl_outside
    jmp compile_error

; ============ Swap ============
; Grammar: swap_stmt ::= "swap" "(" <IDENT> "," <IDENT> ")" <NEWLINE>
.swap_stmt:
    call advance ; consume 'swap'
    mov edi, TOK_LPAREN
    call expect
    mov eax, [current_token]
    cmp eax, TOK_IDENT
    jne expected_ident
    ; Look up first variable
    mov rdi, [tok_str_ptr]
    mov rsi, [tok_str_len]
    call sym_lookup
    cmp rax, -1
    je .swap_undef
    mov r12, rax ; sym_idx_a
    call advance ; consume first ident
    mov edi, TOK_COMMA
    call expect
    mov eax, [current_token]
    cmp eax, TOK_IDENT
    jne expected_ident
    mov rdi, [tok_str_ptr]
    mov rsi, [tok_str_len]
    call sym_lookup
    cmp rax, -1
    je .swap_undef
    mov r13, rax ; sym_idx_b
    call advance ; consume second ident
    mov edi, TOK_RPAREN
    call expect
    ; Get stack offsets for both variables
    mov rdi, r12
    call sym_get_offset
    mov r14, rax ; offset_a
    mov rdi, r13
    call sym_get_offset
    mov r15, rax ; offset_b
    ; Emit IR_SWAP_VARS: imm=offset_a, aux=offset_b
    mov rdi, IR_SWAP_VARS
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    xor r8, r8
    mov r9, r14  ; imm = offset_a
    mov r10, r15 ; aux = offset_b
    call emit_ir
    ret
.swap_undef:
    jmp undef_error

; ============ Inc/Dec Statements ============
; Grammar (grammar.md §13): inc_dec_stmt ::= ( "++" | "--" ) <IDENT> <NEWLINE>
;                                                   | <IDENT> ( "++" | "--" ) <NEWLINE>
; Design §5.7: ++x desugars to x += 1. Self-evidently a mutation, no ':' sigil needed.
.inc_dec_prefix:
    ; Prefix: ++IDENT / --IDENT
    mov r12d, [current_token] ; TOK_PLUSPLUS or TOK_MINUSMINUS
    call advance ; consume '++' / '--'
    mov eax, [current_token]
    cmp eax, TOK_IDENT
    jne expected_ident
    mov rdi, [tok_str_ptr]
    mov rsi, [tok_str_len]
    call sym_lookup
    cmp rax, -1
    je .inc_undef
    mov r14, rax
    jmp .inc_dec_emit

.inc_dec_emit:
    ; r14 = symbol index, r12d = TOK_PLUSPLUS or TOK_MINUSMINUS
    ; Desugar to: :x = x + 1  (or x - 1)
    ; Retroactive mutability (design §3.1), same as :name =.
    mov rdi, r14
    mov rsi, 1
    call sym_set_mutable
    call advance ; consume IDENT (both prefix and postfix have IDENT as current token)

    ; Postfix form: IDENT ++ / IDENT -- — consume the trailing operator
    mov eax, [current_token]
    cmp eax, TOK_PLUSPLUS
    je .inc_consume_op
    cmp eax, TOK_MINUSMINUS
    jne .inc_no_trailing_op
.inc_consume_op:
    call advance
.inc_no_trailing_op:

    ; Variable must be numeric
    mov rdi, r14
    call sym_get_type
    mov rbx, rax ; variable type
    cmp rbx, TYPE_INT
    je .inc_const_int
    cmp rbx, TYPE_BYTE
    je .inc_const_int
    cmp rbx, TYPE_FLOAT
    je .inc_const_float
    mov rdi, err_type_mismatch
    jmp compile_error

.inc_const_int:
    ; Constant 1 as an int vreg
    call alloc_vreg
    mov r15, rax
    mov rdi, IR_LOAD_IMM
    mov rsi, TYPE_INT
    mov rdx, r15
    xor rcx, rcx
    xor r8, r8
    mov r9, 1
    xor r10, r10
    call emit_ir
    jmp .inc_op

.inc_const_float:
    ; Constant 1.0 as a float vreg (double bits 0x3FF0000000000000)
    call alloc_vreg
    mov r15, rax
    mov rdi, IR_LOAD_FIMM
    mov rsi, TYPE_FLOAT
    mov rdx, r15
    xor rcx, rcx
    xor r8, r8
    mov r9, 0x3FF0000000000000
    xor r10, r10
    call emit_ir

.inc_op:
    ; Load current value: vreg r13 = var
    call alloc_vreg
    mov r13, rax
    mov rdi, r14
    call sym_get_offset
    mov r9, rax
    mov rdi, IR_LOAD_VAR
    mov rsi, rbx
    mov rdx, r13
    xor rcx, rcx
    xor r8, r8
    xor r10, r10
    call emit_ir

    ; result = old_value +- 1
    call alloc_vreg
    push rax ; result vreg
    mov rdi, IR_ADD
    cmp r12d, TOK_PLUSPLUS
    je .inc_is_add
    mov rdi, IR_SUB
.inc_is_add:
    mov rsi, rbx
    mov rdx, [rsp]
    mov rcx, r13
    mov r8, r15
    xor r9, r9
    xor r10, r10
    call emit_ir

    ; Store back: var = result
    mov rdi, r14
    call sym_get_offset
    mov r9, rax
    mov rdi, IR_STORE_VAR
    mov rsi, rbx
    xor rdx, rdx
    mov rcx, [rsp]
    xor r8, r8
    xor r10, r10
    call emit_ir
    add rsp, 8

    ; Mark initialized
    mov rdi, r14
    mov rsi, 1
    call sym_set_init
    ret

.inc_undef:
    jmp undef_error

; Helper: skip an indented block (consume until DEDENT)
.skip_block:
    ; Consume NEWLINE before INDENT (if present)
    mov eax, [current_token]
    cmp eax, TOK_NEWLINE
    jne .skip_block_no_nl
    call advance
.skip_block_no_nl:
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
    ; Expect newline after each statement in block
    mov eax, [current_token]
    cmp eax, TOK_NEWLINE
    jne .skip_skip_nl
    call advance
.skip_skip_nl:
    jmp .skip_loop
.skip_done:
    call advance ; consume DEDENT
.skip_single:
    ret

.explicit_decl:
    ; explicit_decl: type_expr [ "[" type_expr "]" ] <IDENT> [ "=" expr ]
    mov dword [pending_elem_type], 0
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
    mov [pending_elem_type], r13d
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

    ; Record container element type (seq[T]/dict[T]/arr[T,N]) on the symbol
    mov edi, r14d
    mov esi, [pending_elem_type]
    extern sym_set_elem_type
    call sym_set_elem_type

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
    
    ; Type check (rax holds the expr vreg — save it across the check;
    ; .type_ok expects rax = vreg)
    push rax ; save expr vreg
    mov rax, r12 ; declared type
    call types_compatible
    pop rax ; restore expr vreg (does not alter ZF)
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
    
    ; If the declared type is a struct, the RHS is a struct pointer vreg;
    ; copy it field-by-field into this variable's slot (value semantics).
    push rax ; save expr vreg
    mov rdi, r12
    call type_get_kind
    cmp al, TYPE_COMPLEX
    je .type_ok_struct

    ; Emit IR_STORE_VAR
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
    jmp .type_ok_done

.type_ok_struct:
    ; [rsp] = rhs ptr vreg, r12 = struct type id, r14 = sym idx
    mov rdi, r14
    call sym_get_offset
    mov r9, rax ; imm = destination absolute address
    call alloc_vreg
    mov rdx, rax ; dst ptr vreg
    push rax
    mov rdi, IR_LEA_VAR
    mov rsi, r12
    xor rcx, rcx
    xor r8, r8
    xor r10, r10
    call emit_ir
    pop rdi ; dst ptr vreg
    mov rsi, [rsp] ; rhs ptr vreg
    mov rdx, r12 ; struct type id
    call emit_struct_copy

.type_ok_done:
    ; Mark as initialized
    pop rax
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
    ; Qualified mutation: ":" <mod> "." <name> "=" expr
    call advance ; consume ':'
    mov eax, [current_token]
    cmp eax, TOK_IDENT
    jne expected_ident

    call lexer_peek_token
    cmp eax, TOK_DOT
    jne .mut_not_qualified
    mov rdi, [tok_str_ptr]
    mov rsi, [tok_str_len]
    call module_lookup
    cmp rax, -1
    je .mut_not_qualified
    mov r15, rax ; module id
    call advance ; consume module name → '.'
    mov edi, TOK_DOT
    call expect ; consume '.' → current token = member IDENT
    mov eax, [current_token]
    cmp eax, TOK_IDENT
    jne expected_ident
    jmp parse_qualified_mutation
.mut_not_qualified:
    ; Lookup variable
    mov rdi, [tok_str_ptr]
    mov rsi, [tok_str_len]
    call sym_lookup
    cmp rax, -1
    je .undef_error
    
    mov r14, rax ; Save symbol index
    ; Constants cannot be mutated (design.md §4.17).
    mov rdi, r14
    call sym_is_const
    test rax, rax
    jnz .mutation_not_allowed
    ; Per design.md §3.1: writing `:name =` makes the variable mutable.
    ; Mark it mutable now (retroactive mutability).
    mov rdi, r14
    mov rsi, 1
    call sym_set_mutable
    call advance ; consume IDENT

    ; Multi-target assignment: :a, :b = @f(...)
    mov eax, [current_token]
    cmp eax, TOK_COMMA
    je .multi_mutation

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
    call types_compatible
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

.multi_mutation:
    ; Multi-target mutation: :a, :b = @f(...)
    ; r14 = target0 sym index (saved above), current_token = ','
    mov [mut_target_syms + 0*4], r14d
    mov r15d, 1 ; target count
.multi_target_loop:
    call advance ; consume ','
    mov edi, TOK_COLON
    call expect ; consume ':' → IDENT
    mov eax, [current_token]
    cmp eax, TOK_IDENT
    jne expected_ident
    mov rdi, [tok_str_ptr]
    mov rsi, [tok_str_len]
    call sym_lookup
    cmp rax, -1
    je .undef_error
    cmp r15d, 65
    jae .multi_err
    push rax
    mov rdi, rax
    call sym_is_const
    test rax, rax
    jnz .mutation_not_allowed
    pop rax
    mov [mut_target_syms + r15*4], eax
    inc r15d
    call advance ; consume IDENT
    mov eax, [current_token]
    cmp eax, TOK_COMMA
    je .multi_target_loop
    ; Now expect '=' then a protocol call
    mov edi, TOK_ASSIGN
    call expect
    mov eax, [current_token]
    cmp eax, TOK_AT
    jne .multi_err
    call advance ; consume '@' → IDENT
    call parse_proto_call ; rax = lo vreg
    ; Require exactly 2 targets and a 2-return protocol
    cmp r15d, 2
    jne .multi_err
    cmp dword [call_result_hi], 0
    je .multi_err
    mov r13, rax ; lo vreg
    mov r12d, [call_result_hi] ; hi vreg
    ; STORE target0 ← lo
    mov edi, [mut_target_syms + 0*4]
    mov rsi, 1
    call sym_set_mutable
    mov edi, [mut_target_syms + 0*4]
    mov rsi, 1
    call sym_set_init
    mov edi, [mut_target_syms + 0*4]
    call sym_get_type
    push rax
    mov edi, [mut_target_syms + 0*4]
    call sym_get_offset
    push rax
    mov rdi, IR_STORE_VAR
    xor rsi, rsi
    xor rdx, rdx
    mov rcx, r13
    xor r8, r8
    pop r9 ; imm = offset
    pop rsi ; type
    xor r10, r10
    call emit_ir
    ; STORE target1 ← hi
    mov edi, [mut_target_syms + 1*4]
    mov rsi, 1
    call sym_set_mutable
    mov edi, [mut_target_syms + 1*4]
    mov rsi, 1
    call sym_set_init
    mov edi, [mut_target_syms + 1*4]
    call sym_get_type
    push rax
    mov edi, [mut_target_syms + 1*4]
    call sym_get_offset
    push rax
    mov rdi, IR_STORE_VAR
    xor rsi, rsi
    xor rdx, rdx
    mov rcx, r12
    xor r8, r8
    pop r9
    pop rsi
    xor r10, r10
    call emit_ir
    ret
.multi_err:
    mov rdi, err_arity
    jmp compile_error

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
    push rdx ; rhs type (for mixed-arithmetic promotion in .compound_emit)

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
    pop r8 ; rhs type
    pop rsi ; variable type (float compounds must be float-typed)
    ; String += must desugar to concat, not integer add on pointers
    cmp rsi, TYPE_STR
    jne .compound_not_str
    cmp rdi, IR_ADD
    jne type_error
    mov rdi, IR_STR_CONCAT
.compound_not_str:
    ; int/byte var op= float RHS → float dominates, but the result can't be
    ; stored back into an int/byte var → type mismatch.
    cmp rsi, TYPE_INT
    je .compound_rhs_float_check
    cmp rsi, TYPE_BYTE
    jne .compound_promote
.compound_rhs_float_check:
    cmp r8, TYPE_FLOAT
    je .compound_type_error
.compound_promote:
    ; float var op= int/byte RHS → promote RHS to float (design §5.2)
    cmp rsi, TYPE_FLOAT
    jne .compound_emit_op
    cmp r8, TYPE_FLOAT
    je .compound_emit_op
    push rdi ; save IR opcode
    push rdx ; save result vreg (coerce_to_float clobbers rdx)
    mov rdi, r15
    mov rsi, r8
    call coerce_to_float
    pop rdx
    pop rdi
    mov r15, rax
.compound_emit_op:
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

.compound_type_error:
    ; Reached from .compound_emit after all three stack items are popped.
    mov rdi, err_type_mismatch
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

    ; Struct vars hold pointers: load with LEA_VAR, not LOAD_VAR.
    mov rdi, r13
    call type_get_kind
    cmp al, TYPE_COMPLEX
    jne .mut_method_load_var
    mov rdi, IR_LEA_VAR
    jmp .mut_method_emit_load
.mut_method_load_var:
    mov rdi, IR_LOAD_VAR
.mut_method_emit_load:
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
    ; Struct base → field access: :q.x = v or a chain :q.x.y = v
    mov rdi, r13
    call type_get_kind
    cmp al, TYPE_COMPLEX
    jne .mut_real_method_name
    ; r12 = base pointer vreg, r13 = struct type; field name is current token
    mov rdi, r13
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call type_struct_find_field ; rax = offset, rcx = field type
    cmp rax, -1
    je .mut_struct_field_miss
    push rax                ; [rsp]   = field offset
    push rcx                ; [rsp+8] = field type
    call advance            ; consume field name
    mov eax, [current_token]
    cmp eax, TOK_ASSIGN
    je .mut_field_store
    ; Chain: :q.x.y = v — LEA_FIELD down into the field, update base, loop.
    pop rcx                 ; field type
    pop r9                  ; field offset
    push rcx                ; save field type across alloc_vreg
    push r9                 ; save offset across alloc_vreg
    call alloc_vreg
    mov rbx, rax            ; new base vreg
    pop r9
    pop rcx
    push rcx                ; save field type across emit_ir
    mov rdi, IR_LEA_FIELD
    mov rsi, rcx            ; type
    mov rdx, rbx            ; dst = new base vreg
    mov rcx, r12            ; src1 = current base vreg
    xor r8, r8
    ; r9 = field offset
    xor r10, r10
    call emit_ir
    pop rcx                 ; field type
    mov [vreg_type_map + rbx * 4], ecx
    mov r12, rbx
    mov r13, rcx
    jmp .mut_method_loop

.mut_struct_field_miss:
    ; Current token is the unknown field name. Stash it, then report
    ; "Unknown field '<name>' on type <struct>". r13 = struct type id.
    mov rsi, [tok_str_ptr]
    mov rcx, [tok_str_len]
    cmp rcx, 31
    jle .mut_fnlen_ok
    mov rcx, 31
.mut_fnlen_ok:
    mov [method_len], rcx
    lea rdi, [method_buf]
    test rcx, rcx
    jz .mut_fcopy_done
.mut_fcopy:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jnz .mut_fcopy
.mut_fcopy_done:
    lea rdi, [method_buf]
    add rdi, [method_len]
    mov byte [rdi], 0
    jmp unknown_field_error

.mut_field_store:
    ; :q.x = value — STORE_FIELD [base + off] = value
    pop rcx                 ; field type
    pop r9                  ; field offset
    push rcx                ; save field type across expect/parse_expr
    push r9                 ; save offset across expect/parse_expr
    mov edi, TOK_ASSIGN
    call expect             ; consume '='
    call parse_expr         ; rax = value vreg, rdx = value type
    pop r9                  ; field offset
    pop rcx                 ; field type
    push rax                ; save value vreg
    mov rax, rcx            ; field type
    call types_compatible
    pop r8                  ; r8 = value vreg
    jne .mut_method_type_err
    mov rdi, IR_STORE_FIELD
    mov rsi, rcx            ; field type
    xor rdx, rdx
    mov rcx, r12            ; base pointer vreg
    ; r9 = offset, r8 = value vreg
    xor r10, r10
    call emit_ir
    jmp .mut_method_done

.mut_real_method_name:
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
    cmp r13, TYPE_FILE
    je .mut_file_dispatch
    jmp .mut_method_unknown_err

.mut_file_dispatch:
    lea rdi, [str_write_m]
    call ident_is
    test rax, rax
    jnz .mut_file_write
    lea rdi, [str_writeln]
    call ident_is
    test rax, rax
    jnz .mut_file_writeln
    lea rdi, [str_write_bytes]
    call ident_is
    test rax, rax
    jnz .mut_file_write_bytes
    lea rdi, [str_seek]
    call ident_is
    test rax, rax
    jnz .mut_file_seek
    lea rdi, [str_seek_end]
    call ident_is
    test rax, rax
    jnz .mut_file_seek_end
    lea rdi, [str_flush]
    call ident_is
    test rax, rax
    jnz .mut_file_flush
    lea rdi, [str_close_m]
    call ident_is
    test rax, rax
    jnz .mut_file_close
    jmp .mut_method_unknown_err

.mut_file_write:
    ; :f.write(s) — void
    call parse_expr ; s vreg
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop rdx
    pop r14
    cmp rdx, TYPE_STR
    jne .mut_method_type_err
    mov rdi, IR_FILE_WRITE
    mov rsi, TYPE_FILE
    xor rdx, rdx       ; dst = 0 (void)
    mov rcx, r12       ; src1 = handle
    mov r8, r14        ; src2 = s
    xor r9, r9
    xor r10, r10
    call emit_ir
    jmp .mut_method_loop

.mut_file_writeln:
    ; :f.writeln(s) — void
    call parse_expr ; s vreg
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop rdx
    pop r14
    cmp rdx, TYPE_STR
    jne .mut_method_type_err
    mov rdi, IR_FILE_WRITELN
    mov rsi, TYPE_FILE
    xor rdx, rdx       ; dst = 0 (void)
    mov rcx, r12       ; src1 = handle
    mov r8, r14        ; src2 = s
    xor r9, r9
    xor r10, r10
    call emit_ir
    jmp .mut_method_loop

.mut_file_write_bytes:
    ; :f.write_bytes(b) — void
    call parse_expr ; b vreg
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop rdx
    pop r14
    cmp rdx, TYPE_SEQ
    jne .mut_method_type_err
    mov rdi, IR_FILE_WRITE_BYTES
    mov rsi, TYPE_FILE
    xor rdx, rdx       ; dst = 0 (void)
    mov rcx, r12       ; src1 = handle
    mov r8, r14        ; src2 = b
    xor r9, r9
    xor r10, r10
    call emit_ir
    jmp .mut_method_loop

.mut_file_seek:
    ; :f.seek(pos) — void
    call parse_expr ; pos vreg
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop rdx
    pop r14
    cmp rdx, TYPE_INT
    jne .mut_method_type_err
    mov rdi, IR_FILE_SEEK
    mov rsi, TYPE_FILE
    xor rdx, rdx       ; dst = 0 (void)
    mov rcx, r12       ; src1 = handle
    mov r8, r14        ; src2 = pos
    xor r9, r9
    xor r10, r10
    call emit_ir
    jmp .mut_method_loop

.mut_file_seek_end:
    ; :f.seek_end(n) — void (n bytes before end; default 0)
    mov r14, r12 ; save handle vreg
    mov eax, [current_token]
    cmp eax, TOK_RPAREN
    je .mut_seek_end_default
    call parse_expr ; n vreg
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop rdx
    pop r15
    cmp rdx, TYPE_INT
    jne .mut_method_type_err
    jmp .mut_seek_end_emit
.mut_seek_end_default:
    mov edi, TOK_RPAREN
    call expect
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
    pop r15
.mut_seek_end_emit:
    mov r12, r14 ; restore handle vreg
    mov rdi, IR_FILE_SEEK_END
    mov rsi, TYPE_FILE
    xor rdx, rdx
    mov rcx, r12     ; src1 = handle
    mov r8, r15      ; src2 = n
    xor r9, r9
    xor r10, r10
    call emit_ir
    jmp .mut_method_loop

.mut_file_flush:
    ; :f.flush() — void
    mov edi, TOK_RPAREN
    call expect
    mov rdi, IR_FILE_FLUSH
    mov rsi, TYPE_FILE
    xor rdx, rdx
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir
    jmp .mut_method_loop

.mut_file_close:
    ; :f.close() — void
    mov edi, TOK_RPAREN
    call expect
    mov rdi, IR_FILE_CLOSE
    mov rsi, TYPE_FILE
    xor rdx, rdx
    mov rcx, r12
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir
    jmp .mut_method_loop

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
    jmp unknown_method_error

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
    jmp undef_error

.mutation_not_allowed:
    mov rdi, err_immutable
    jmp compile_error

.ident_stmt:
    ; Qualified access: mod.name (design.md §17.2). A registered module name
    ; followed by '.' starts a qualified reference — either a call statement
    ; `mod.f(...)` or a mutation that requires the ':' sigil.
    call lexer_peek_token
    cmp eax, TOK_DOT
    jne .ident_stmt_not_qual
    mov rdi, [tok_str_ptr]
    mov rsi, [tok_str_len]
    call module_lookup
    cmp rax, -1
    je .ident_stmt_not_qual
    mov r15, rax ; module id
    call advance ; consume module name → '.'
    mov edi, TOK_DOT
    call expect ; consume '.' → current token = member IDENT
    mov eax, [current_token]
    cmp eax, TOK_IDENT
    jne expected_ident
    call save_ident
    call lexer_peek_token
    cmp eax, TOK_LPAREN
    jne .ident_stmt_qual_sigil
    call parse_qualified_expr
    ret
.ident_stmt_qual_sigil:
    mov rdi, err_sigil_req
    jmp compile_error
.ident_stmt_not_qual:
    ; A struct type name reaches here as TOK_IDENT (only builtin types are
    ; TOK_TYPE). If the ident names a registered struct, treat this as a
    ; declaration:  Point p [= Point{...}]
    mov rdi, [tok_str_ptr]
    mov rsi, [tok_str_len]
    call type_lookup
    cmp rax, -1
    je .ident_stmt_not_struct
    push rax
    mov rdi, rax
    call type_get_kind
    mov rcx, rax
    pop rax
    cmp rcx, TYPE_COMPLEX
    jne .ident_stmt_not_struct
    mov [tok_ival], rax
    jmp .explicit_decl
.ident_stmt_not_struct:
    ; Could be type-inferred declaration: x = 5
    ; or illegal reassignment without ':': x = 5 (when x exists)
    mov rdi, [tok_str_ptr]
    mov rsi, [tok_str_len]
    call sym_lookup
    cmp rax, -1
    je .inferred_decl
    
    ; Variable exists. Check if it's mutable (from a prior :name = site).
    mov r14, rax ; Save symbol index

    ; Postfix inc/dec: x++ / x-- (statement form, grammar.md §13)
    call lexer_peek_token
    cmp eax, TOK_PLUSPLUS
    je .ident_inc_dec
    cmp eax, TOK_MINUSMINUS
    je .ident_inc_dec

    ; Method-call statement: ident.method(args) (design.md §15.4)
    ; Same as the ':' mutation form, but without the sigil.
    call lexer_peek_token
    cmp eax, TOK_DOT
    je .ident_method_call

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
    call types_compatible
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

.ident_method_call:
    ; Method-call statement without ':' sigil (e.g. f.writeln("x")).
    ; r14 = sym_idx, current token = IDENT. Identical handling to the
    ; ':' mutation method form.
    mov rdi, r14
    mov rsi, 1
    call sym_set_mutable
    call advance ; consume IDENT
    jmp .mutation_method

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
    push rdx ; rhs type (for mixed-arithmetic promotion in .ident_compound_emit)

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
    pop r8 ; rhs type
    pop rsi ; variable type (float compounds must be float-typed)
    ; String += must desugar to concat, not integer add on pointers
    cmp rsi, TYPE_STR
    jne .ident_compound_not_str
    cmp rdi, IR_ADD
    jne type_error
    mov rdi, IR_STR_CONCAT
.ident_compound_not_str:
    ; int/byte var op= float RHS → float dominates, but the result can't be
    ; stored back into an int/byte var → type mismatch.
    cmp rsi, TYPE_INT
    je .ident_compound_rhs_float_check
    cmp rsi, TYPE_BYTE
    jne .ident_compound_promote
.ident_compound_rhs_float_check:
    cmp r8, TYPE_FLOAT
    je .ident_compound_type_error
.ident_compound_promote:
    ; float var op= int/byte RHS → promote RHS to float (design §5.2)
    cmp rsi, TYPE_FLOAT
    jne .ident_compound_emit_op
    cmp r8, TYPE_FLOAT
    je .ident_compound_emit_op
    push rdi ; save IR opcode
    push rdx ; save result vreg (coerce_to_float clobbers rdx)
    mov rdi, r15
    mov rsi, r8
    call coerce_to_float
    pop rdx
    pop rdi
    mov r15, rax
.ident_compound_emit_op:
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

.ident_compound_type_error:
    ; Reached from .ident_compound_emit after all three stack items are popped.
    mov rdi, err_type_mismatch
    jmp compile_error

.ident_inc_dec:
    ; Postfix inc/dec statement: x++ / x--
    ; r14 = symbol index, current_token = IDENT, eax = peeked op token
    mov r12d, eax
    jmp .inc_dec_emit

.inferred_decl:
    ; ++/-- on an undeclared variable is an error (no self-evident mutation target)
    call lexer_peek_token
    cmp eax, TOK_PLUSPLUS
    je .inc_undef
    cmp eax, TOK_MINUSMINUS
    je .inc_undef
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
    cmp rax, -1
    je full_error ; symbol table full
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
    ; output_stmt: output "(" [arg ("," arg)*] ")"
    ;   arg := expr | "sep" "=" expr | "end" "=" expr
    ; Values are printed space-separated (default sep=" ") and terminated
    ; by end (default end="\n"). sep/end are keyword args only.
    push rbx      ; sep vreg (0 = default " ")
    push r13      ; sep type
    push r14      ; end vreg (0 = default "\n")
    push r15      ; end type
    push r12      ; arg count
    xor ebx, ebx
    xor r13d, r13d
    xor r14d, r14d
    xor r15d, r15d
    xor r12d, r12d

    call advance ; consume output
    mov edi, TOK_LPAREN
    call expect  ; consume '('

.parse_loop:
    mov eax, [current_token]
    cmp eax, TOK_RPAREN
    je .args_done
    cmp eax, TOK_IDENT
    jne .parse_value_arg

    ; IDENT — could be a "sep=" or "end=" keyword arg.
    push rdi
    mov rdi, [tok_str_ptr]
    mov eax, [tok_str_len]
    cmp eax, 3
    jne .not_kwarg
    movzx edx, byte [rdi]
    cmp dl, 's'
    je .try_sep_kwarg
    cmp dl, 'e'
    jne .not_kwarg
    cmp byte [rdi + 1], 'n'
    jne .not_kwarg
    cmp byte [rdi + 2], 'd'
    jne .not_kwarg
    ; "end" — check next token is '='
    call lexer_peek_token
    cmp eax, TOK_ASSIGN
    jne .not_kwarg
    pop rdi
    jmp .parse_kwarg_end
.try_sep_kwarg:
    cmp byte [rdi + 1], 'e'
    jne .not_kwarg
    cmp byte [rdi + 2], 'p'
    jne .not_kwarg
    ; "sep" — check next token is '='
    call lexer_peek_token
    cmp eax, TOK_ASSIGN
    jne .not_kwarg
    pop rdi
    jmp .parse_kwarg_sep
.not_kwarg:
    pop rdi
    jmp .parse_value_arg

.parse_kwarg_sep:
    test rbx, rbx
    jnz .dup_kwarg
    call .parse_kwarg_value
    mov rbx, rax
    mov r13d, edx
    jmp .parse_after_arg
.parse_kwarg_end:
    test r14, r14
    jnz .dup_kwarg
    call .parse_kwarg_value
    mov r14, rax
    mov r15d, edx
    jmp .parse_after_arg
.dup_kwarg:
    mov rdi, err_syntax
    jmp compile_error

.parse_kwarg_value:
    ; current_token = kwarg name; value must be str or char.
    call advance ; consume kwarg name
    mov edi, TOK_ASSIGN
    call expect  ; consume '='
    call parse_expr ; rax = vreg, rdx = type
    cmp edx, TYPE_STR
    je .kwarg_type_ok
    cmp edx, TYPE_CHAR
    je .kwarg_type_ok
    mov rdi, err_type_mismatch
    jmp compile_error
.kwarg_type_ok:
    ret

.parse_value_arg:
    call parse_expr ; rax = vreg, rdx = type
    cmp r12d, 256
    jae .too_many_args
    mov [out_arg_vregs + r12 * 2], ax
    mov [out_arg_types + r12 * 4], edx
    inc r12d
.parse_after_arg:
    mov eax, [current_token]
    cmp eax, TOK_COMMA
    jne .expect_rparen
    call advance
    jmp .parse_loop
.expect_rparen:
    mov edi, TOK_RPAREN
    call expect
    jmp .emit_output
.args_done:
    mov edi, TOK_RPAREN
    call expect
    jmp .emit_output
.too_many_args:
    mov rdi, err_syntax
    jmp compile_error

.emit_output:
    ; Emit each value, separated by sep, then end.
    xor r8d, r8d ; i = 0
.emit_value_loop:
    cmp r8d, r12d
    jae .emit_end
    movzx eax, word [out_arg_vregs + r8 * 2]
    mov edx, dword [out_arg_types + r8 * 4]
    push r8
    call .emit_output_value ; rax = vreg, edx = type
    pop r8
    ; sep between values
    lea eax, [r8 + 1]
    cmp eax, r12d
    jae .no_sep
    push r8
    call .emit_sep
    pop r8
.no_sep:
    inc r8d
    jmp .emit_value_loop
.emit_end:
    push r8
    call .emit_end_val
    pop r8
    pop r12
    pop r15
    pop r14
    pop r13
    pop rbx
    ret

; Emit output IR for value vreg in rax, type in edx.
.emit_output_value:
    mov rcx, rax ; src1
    cmp edx, TYPE_INT
    je .eov_int
    cmp edx, TYPE_FLOAT
    je .eov_float
    cmp edx, TYPE_BOOL
    je .eov_bool
    cmp edx, TYPE_STR
    je .eov_str
    cmp edx, TYPE_CHAR
    je .eov_char
    cmp edx, TYPE_BYTE
    je .eov_int
    mov rdi, err_type_mismatch
    jmp compile_error
.eov_int:
    mov rdi, IR_OUT_INT
    xor r9, r9
    jmp .eov_emit
.eov_float:
    mov rdi, IR_OUT_FLOAT
    xor r9, r9
    jmp .eov_emit
.eov_bool:
    mov rdi, IR_OUT_BOOL
    xor r9, r9
    jmp .eov_emit
.eov_str:
    mov rdi, IR_OUT_STR
    xor r9, r9
    jmp .eov_emit
.eov_char:
    mov rdi, IR_OUT_CHAR
    xor r9, r9
.eov_emit:
    mov rsi, rdx ; type
    xor rdx, rdx ; no dst
    xor r8, r8
    xor r10, r10
    call emit_ir
    ret

; Emit sep: custom vreg (rbx, type r13d) or default ' '.
.emit_sep:
    test rbx, rbx
    jz .emit_default_sep
    mov rax, rbx
    mov edx, r13d
    jmp .emit_output_value
.emit_default_sep:
    call .emit_space
    ret

; Emit end: custom vreg (r14, type r15d) or default '\n'.
.emit_end_val:
    test r14, r14
    jz .emit_default_end
    mov rax, r14
    mov edx, r15d
    jmp .emit_output_value
.emit_default_end:
    call .emit_newline
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

; Parse Expression
parse_expr:
    ; Precedence chain (loosest to tightest) per grammar §27:
    ; or -> and -> not -> comparison -> ?? -> & | ^ -> + - -> * / % << >> -> unary -> postfix
    jmp parse_bool_or

parse_comparison:
    ; Comparison operators: == != < > <= >= is is not
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
    cmp eax, TOK_IS
    je .do_cmp
    cmp eax, TOK_IS_NOT
    je .do_cmp
    cmp eax, TOK_IN
    je .do_cmp
    jmp .done
.do_cmp:
    ; Save operator token type
    mov r14, rax
    call advance
    push r12
    push r13       ; save left type across parse_null_coalesce
    call parse_null_coalesce
    mov r15, rax
    pop r13        ; restore left type
    pop r12
    push rdx       ; [rsp] = right operand type

    ; `is`/`is not` are always identity (pointer) compares, even for structs.
    cmp r14, TOK_IS
    je .scalar_cmp
    cmp r14, TOK_IS_NOT
    je .scalar_cmp
    cmp r14, TOK_IN
    je .do_membership
    ; Struct comparison: if either operand is a struct, compare field-by-field.
    mov edi, r13d
    call type_get_kind
    cmp al, TYPE_COMPLEX
    je .do_struct_cmp
    mov edi, [rsp]
    call type_get_kind
    cmp al, TYPE_COMPLEX
    je .do_struct_cmp
    jmp .scalar_cmp
.do_membership:
    ; `x in collection` (design.md §5.6). r12 = element vreg, r15 = collection
    ; vreg, [rsp] = collection type.
    mov eax, [rsp]
    cmp eax, TYPE_SEQ
    je .mem_seq
    cmp eax, TYPE_STR
    je .mem_str
    cmp eax, TYPE_DICT
    je .mem_dict
    mov rdi, err_type_mismatch
    jmp compile_error
.mem_seq:
    add rsp, 8     ; discard collection type
    ; seq.contains(element): src1 = seq, src2 = element
    push r12
    push r15
    call alloc_vreg
    mov rbx, rax
    pop r15
    pop r12
    mov rdi, IR_SEQ_CONTAINS
    mov rsi, TYPE_BOOL
    mov rdx, rbx
    mov rcx, r15    ; seq
    mov r8, r12     ; element
    mov r9, SEQ_ELEMENT_SIZE
    xor r10, r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_BOOL
    jmp .done
.mem_str:
    ; str `in` (substring search) is not yet implemented — runtime helper absent.
    mov rdi, err_type_mismatch
    jmp compile_error
.mem_dict:
    ; dict `in` (key lookup) is not yet implemented.
    mov rdi, err_type_mismatch
    jmp compile_error

.scalar_cmp:
    add rsp, 8     ; discard right type
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
    cmp r14, TOK_IS
    je .cond_is
    cmp r14, TOK_IS_NOT
    je .cond_is_not
    jmp .cond_done
.cond_eq:
    xor r10, r10       ; COND_EQ = 0
    jmp .cond_done
.cond_ne:
    mov r10, 1         ; COND_NE = 1
    jmp .cond_done
.cond_is:
    xor r10, r10       ; identity == EQ for value/reference comparisons
    jmp .cond_done
.cond_is_not:
    mov r10, 1         ; identity-ne == NE
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
    jmp .chain_check

.do_struct_cmp:
    ; Both operands must be structs of the same type; op must be == or !=
    mov eax, [rsp]     ; right type
    cmp eax, r13d
    jne .cmp_struct_err
    cmp r14, TOK_EQ
    je .cmp_struct_eq
    cmp r14, TOK_NE
    je .cmp_struct_ne
.cmp_struct_err:
    mov rdi, err_type_mismatch
    jmp compile_error
.cmp_struct_eq:
    xor rcx, rcx       ; mode = EQ
    jmp .cmp_struct_call
.cmp_struct_ne:
    mov rcx, 1         ; mode = NE
.cmp_struct_call:
    add rsp, 8         ; discard right type
    mov rdi, r12       ; ptr_a
    mov rsi, r15       ; ptr_b
    mov rdx, r13       ; struct type id
    call emit_struct_cmp
    mov rbx, rax       ; result vreg
.chain_check:
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
    cmp eax, TOK_IS
    je .chain
    cmp eax, TOK_IS_NOT
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
    cmp r14, TOK_IS
    je .chain_cond_is
    cmp r14, TOK_IS_NOT
    je .chain_cond_is_not
    jmp .chain_cond_done
.chain_cond_eq:
    xor r10, r10
    jmp .chain_cond_done
.chain_cond_ne:
    mov r10, 1
    jmp .chain_cond_done
.chain_cond_is:
    xor r10, r10
    jmp .chain_cond_done
.chain_cond_is_not:
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
    call parse_bitwise_or
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
    call parse_bool_not
    mov r12, rax
    mov r13, rdx
.loop:
    mov eax, [current_token]
    cmp eax, TOK_BOOL_AND
    jne .done
    call advance
    push r12
    call parse_bool_not
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

; Parse Bool NOT ('not' = negate) -- tier 4, binds looser than comparison,
; tighter than and/or. Right-associative: 'not not x' = not(not x).
parse_bool_not:
    mov eax, [current_token]
    cmp eax, TOK_BOOL_NOT
    jne .no_not
    call advance ; consume 'not'
    call parse_bool_not ; right-assoc operand
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
.no_not:
    call parse_comparison
    ret

parse_bitwise_or:
    ; Tier 4 (design §5.1): `+ - | & ^` all share the SAME precedence,
    ; left-associative. `| & ^` are int/byte-only; `+ -` also handle float
    ; promotion (int/byte + float → float) and str concatenation (`+`).
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
    cmp eax, TOK_OR
    je .op_or
    cmp eax, TOK_XOR
    je .op_xor
    cmp eax, TOK_AND
    je .op_and
    cmp eax, TOK_PLUS
    je .op_plus
    cmp eax, TOK_MINUS
    je .op_minus
    jmp .done
.op_or:
    mov r14, IR_OR
    jmp .have_op
.op_xor:
    mov r14, IR_XOR
    jmp .have_op
.op_and:
    mov r14, IR_AND
    jmp .have_op
.op_plus:
    cmp r13, TYPE_STR
    je .op_concat
    mov r14, IR_ADD
    jmp .have_op
.op_concat:
    mov r14, IR_STR_CONCAT
    jmp .have_op
.op_minus:
    mov r14, IR_SUB
.have_op:
    call advance
    push r12
    call parse_mult
    mov r15, rax
    pop r12

    ; Float promotion for `+`/`-` (mixed int/byte with float). Bitwise ops
    ; and str concat require matching operand types — skip promotion.
    cmp r14, IR_ADD
    je .promote
    cmp r14, IR_SUB
    je .promote
    cmp rdx, r13
    jne .type_error
    jmp .no_promote
.promote:
    cmp r13, TYPE_FLOAT
    je .promote_right
    cmp rdx, TYPE_FLOAT
    jne .no_promote
    ; left is non-float, right is float → promote left
    mov rdi, r12
    mov rsi, r13
    call coerce_to_float
    mov r12, rax
    mov r13, TYPE_FLOAT
    mov rdx, TYPE_FLOAT
    jmp .no_promote
.promote_right:
    cmp rdx, TYPE_FLOAT
    je .no_promote
    mov rdi, r15
    mov rsi, rdx
    call coerce_to_float
    mov r15, rax
    mov rdx, TYPE_FLOAT
.no_promote:
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

; Coerce a numeric operand to float for mixed arithmetic (design §5.2:
; "float dominates in mixed arithmetic"). INT/BYTE → IR_CAST_ITF; FLOAT → no-op.
; rdi = src vreg, rsi = src type → rax = float vreg. Clobbers rdi/rsi/rcx/r8/r9/r10/rax.
coerce_to_float:
    cmp rsi, TYPE_FLOAT
    je .coerce_already
    cmp rsi, TYPE_INT
    je .coerce_cast
    cmp rsi, TYPE_BYTE
    jne .coerce_bad
.coerce_cast:
    push rdi
    call alloc_vreg
    mov rcx, [rsp] ; src vreg
    mov r8, rax    ; dst vreg
    mov rdi, IR_CAST_ITF
    mov rsi, TYPE_FLOAT
    mov rdx, r8
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir
    mov rax, rdx
    add rsp, 8
    ret
.coerce_already:
    mov rax, rdi
    ret
.coerce_bad:
    mov rdi, err_type_mismatch
    jmp compile_error

; Parse Additive Expression
; ─────────────────────────────────────────────────────────────
; emit_struct_copy: copy a struct field-by-field (value semantics).
; rdi = dst ptr vreg, rsi = src ptr vreg, rdx = struct type id
; Preserves rbx, r12-r15. Nested struct fields are copied recursively.
emit_struct_copy:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdx ; struct type id
    mov r14, rdi ; dst ptr vreg
    mov r15, rsi ; src ptr vreg
    xor r13d, r13d ; field index
.copy_loop:
    mov rdi, r12
    mov rsi, r13
    call type_struct_field_at ; rax = offset (-1 if none), rcx = ftype
    cmp rax, -1
    je .copy_done
    push rcx       ; [rsp]   = ftype
    push rax       ; [rsp+8] = offset
    mov rdi, rcx
    call type_get_kind
    cmp al, TYPE_COMPLEX
    je .copy_nested
    ; Scalar: LOAD_FIELD tmp, src, off; STORE_FIELD dst, tmp, off
    call alloc_vreg ; rax = tmp
    push rax       ; [rsp] = tmp ; [rsp+8] = offset ; [rsp+16] = ftype
    mov rdi, IR_LOAD_FIELD
    mov rsi, [rsp+16]
    mov rdx, [rsp]
    mov rcx, r15
    xor r8, r8
    mov r9, [rsp+8]
    xor r10, r10
    call emit_ir
    mov rdi, IR_STORE_FIELD
    mov rsi, [rsp+16]
    xor rdx, rdx
    mov rcx, r14
    mov r8, [rsp]
    mov r9, [rsp+8]
    xor r10, r10
    call emit_ir
    add rsp, 24
    inc r13d
    jmp .copy_loop
.copy_nested:
    ; dn = LEA_FIELD(dst, off); sn = LEA_FIELD(src, off); recurse(dn, sn, ftype)
    call alloc_vreg ; rax = dn
    push rax       ; [rsp] = dn ; [rsp+8] = offset ; [rsp+16] = ftype
    mov rdi, IR_LEA_FIELD
    mov rsi, [rsp+16]
    mov rdx, [rsp]
    mov rcx, r14
    xor r8, r8
    mov r9, [rsp+8]
    xor r10, r10
    call emit_ir
    call alloc_vreg ; rax = sn
    push rax       ; [rsp] = sn ; [rsp+8] = dn ; [rsp+16] = offset ; [rsp+24] = ftype
    mov rdi, IR_LEA_FIELD
    mov rsi, [rsp+24]
    mov rdx, [rsp]
    mov rcx, r15
    xor r8, r8
    mov r9, [rsp+16]
    xor r10, r10
    call emit_ir
    mov rdi, [rsp+8]  ; dn
    mov rsi, [rsp]    ; sn
    mov rdx, [rsp+24] ; ftype
    call emit_struct_copy
    add rsp, 32
    inc r13d
    jmp .copy_loop
.copy_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; emit_struct_cmp: compare two structs field-by-field (value semantics).
; rdi = ptr_a vreg, rsi = ptr_b vreg, rdx = struct type id, rcx = mode (0=EQ→AND, 1=NE→OR)
; Returns rax = bool result vreg. Preserves rbx, r12-r15. Nested structs recurse.
emit_struct_cmp:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdx ; struct type id
    mov r14, rdi ; ptr_a vreg
    mov r15, rsi ; ptr_b vreg
    mov r13, rcx ; mode (0=EQ, 1=NE)
    xor ebx, ebx ; acc vreg (0 = none yet)
    xor eax, eax ; field index
.cmp_loop:
    push rax     ; [rsp] = field index
    mov rdi, r12
    mov rsi, rax
    call type_struct_field_at ; rax = offset (-1 if none), rcx = ftype
    cmp rax, -1
    je .cmp_done
    push rcx     ; [rsp] = ftype ; [rsp+8] = field index
    push rax     ; [rsp] = offset ; [rsp+8] = ftype ; [rsp+16] = field index
    mov rdi, rcx
    call type_get_kind
    cmp al, TYPE_COMPLEX
    je .cmp_nested
    ; Scalar field: t1=LOAD_FIELD(a,off), t2=LOAD_FIELD(b,off), c=CMP_BOOL(t1,t2,cond)
    call alloc_vreg ; rax = t1
    push rax     ; [rsp] = t1 ; [rsp+8] = offset ; [rsp+16] = ftype ; [rsp+24] = field index
    mov rdi, IR_LOAD_FIELD
    mov rsi, [rsp+16]
    mov rdx, [rsp]
    mov rcx, r14
    xor r8, r8
    mov r9, [rsp+8]
    xor r10, r10
    call emit_ir
    call alloc_vreg ; rax = t2
    push rax     ; [rsp] = t2 ; [rsp+8] = t1 ; [rsp+16] = offset ; [rsp+24] = ftype ; [rsp+32] = field index
    mov rdi, IR_LOAD_FIELD
    mov rsi, [rsp+24]
    mov rdx, [rsp]
    mov rcx, r15
    xor r8, r8
    mov r9, [rsp+16]
    xor r10, r10
    call emit_ir
    call alloc_vreg ; rax = c
    push rax     ; [rsp] = c ; [rsp+8] = t2 ; [rsp+16] = t1 ; [rsp+24] = offset ; [rsp+32] = ftype ; [rsp+40] = field index
    mov rdi, IR_CMP_BOOL
    mov rsi, TYPE_BOOL
    mov rdx, [rsp]
    mov rcx, [rsp+16]
    mov r8, [rsp+8]
    xor r9, r9
    mov r10, r13 ; cond = mode (EQ=0, NE=1)
    call emit_ir
    pop rax      ; c
    pop rcx      ; t2
    pop rdx      ; t1
    pop r9       ; offset
    pop r10      ; ftype
    jmp .cmp_combine
.cmp_nested:
    ; pa=LEA_FIELD(a,off), pb=LEA_FIELD(b,off), c=recurse(pa,pb,ftype,mode)
    call alloc_vreg ; rax = pa
    push rax     ; [rsp] = pa ; [rsp+8] = offset ; [rsp+16] = ftype ; [rsp+24] = field index
    mov rdi, IR_LEA_FIELD
    mov rsi, [rsp+16]
    mov rdx, [rsp]
    mov rcx, r14
    xor r8, r8
    mov r9, [rsp+8]
    xor r10, r10
    call emit_ir
    call alloc_vreg ; rax = pb
    push rax     ; [rsp] = pb ; [rsp+8] = pa ; [rsp+16] = offset ; [rsp+24] = ftype ; [rsp+32] = field index
    mov rdi, IR_LEA_FIELD
    mov rsi, [rsp+24]
    mov rdx, [rsp]
    mov rcx, r15
    xor r8, r8
    mov r9, [rsp+16]
    xor r10, r10
    call emit_ir
    mov rdi, [rsp+8]  ; pa
    mov rsi, [rsp]    ; pb
    mov rdx, [rsp+24] ; ftype
    mov rcx, r13      ; mode
    call emit_struct_cmp ; rax = c
    pop rcx      ; pb
    pop rdx      ; pa
    pop r9       ; offset
    pop r10      ; ftype
.cmp_combine:
    ; rax = this field's result; rbx = acc (0 = none yet)
    test rbx, rbx
    jz .cmp_first
    push rbx     ; old acc
    push rax     ; c
    call alloc_vreg ; rax = new acc
    mov rbx, rax
    pop r8       ; c
    pop rcx      ; old acc
    push rbx     ; new acc
    mov rdi, IR_BOOL_AND
    test r13, r13
    jz .cmp_emit
    mov rdi, IR_BOOL_OR
.cmp_emit:
    mov rsi, TYPE_BOOL
    mov rdx, rbx
    xor r9, r9
    xor r10, r10
    call emit_ir
    pop rbx      ; rbx = new acc
    jmp .cmp_next
.cmp_first:
    mov rbx, rax ; acc = c
.cmp_next:
    pop rax      ; field index
    inc rax
    jmp .cmp_loop
.cmp_done:
    add rsp, 8   ; discard field index
    ; acc in rbx; if 0 (empty struct): EQ → true, NE → false
    test rbx, rbx
    jnz .cmp_return
    call alloc_vreg ; rax = literal
    push rax
    mov rdi, IR_LOAD_BOOL
    mov rsi, TYPE_BOOL
    mov rdx, [rsp]
    xor rcx, rcx
    xor r8, r8
    xor r9, r9
    mov r10, 1   ; true
    test r13, r13
    jz .cmp_lit
    mov r10, 0   ; false for NE of empty struct
.cmp_lit:
    call emit_ir
    pop rbx
.cmp_return:
    mov rax, rbx
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
    cmp eax, TOK_LSHIFT
    je .lshift
    cmp eax, TOK_RSHIFT
    je .rshift
    jmp .done
.mul:
    mov r14, IR_MUL
    jmp .consume
.div:
    mov r14, IR_DIV
    jmp .consume
.mod:
    mov r14, IR_MOD
    jmp .consume
.lshift:
    mov r14, IR_SHL
    jmp .consume
.rshift:
    mov r14, IR_SHR
.consume:
    call advance
    push r12
    call parse_postfix
    mov r15, rax
    pop r12

    ; Mixed arithmetic (design §5.2): int/byte op float → promote to float.
    ; Only MUL/DIV promote; MOD/SHL/SHR are integer-only (reject float operands).
    cmp r14, IR_MUL
    je .may_promote_mult
    cmp r14, IR_DIV
    je .may_promote_mult
    cmp r13, TYPE_FLOAT
    je .type_error
    cmp rdx, TYPE_FLOAT
    je .type_error
    jmp .no_promote_mult
.may_promote_mult:
    cmp r13, TYPE_FLOAT
    je .promote_mult_right
    cmp rdx, TYPE_FLOAT
    jne .no_promote_mult
    ; left is non-float, right is float → promote left
    mov rdi, r12
    mov rsi, r13
    call coerce_to_float
    mov r12, rax
    mov r13, TYPE_FLOAT
    mov rdx, TYPE_FLOAT
    jmp .no_promote_mult
.promote_mult_right:
    cmp rdx, TYPE_FLOAT
    je .no_promote_mult
    mov rdi, r15
    mov rsi, rdx
    call coerce_to_float
    mov r15, rax
    mov rdx, TYPE_FLOAT
.no_promote_mult:
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
    cmp eax, TOK_AT
    je .proto_call
    
    cmp eax, TOK_IF
    je .inline_if
    
    cmp eax, TOK_WHEN
    je .when_expr
    
    cmp eax, TOK_OPEN
    je .open_builtin
    
    mov rdi, err_syntax
    jmp compile_error

.open_builtin:
    ; open(path) or open(path, mode) → file handle (TYPE_FILE)
    ; open() is a builtin function, not a constructor: the handle is
    ; created by the runtime (rt_file_open), not by struct construction.
    call advance ; consume 'open'
    mov edi, TOK_LPAREN
    call expect
    call parse_expr ; rax = path vreg, rdx = path type
    push rax
    push rdx
    mov eax, [current_token]
    cmp eax, TOK_COMMA
    jne .open_default_mode
    call advance ; consume ','
    call parse_expr ; rax = mode vreg, rdx = mode type
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop r13 ; mode type
    pop r12 ; mode vreg
    cmp r13, TYPE_STR
    jne .open_type_err
    jmp .open_emit
.open_default_mode:
    mov edi, TOK_RPAREN
    call expect
    ; Synthesize a default "r" mode literal via IR_LOAD_STR
    call alloc_vreg
    mov r12, rax
    mov rdi, IR_LOAD_STR
    mov rsi, TYPE_STR
    mov rdx, r12
    xor rcx, rcx
    xor r8, r8
    mov r9, str_mode_r ; imm = string ptr (compiler-space)
    mov r10, 1         ; aux = length
    call emit_ir
.open_emit:
    pop rdx ; path type
    pop rcx ; path vreg
    cmp rdx, TYPE_STR
    jne .open_type_err
    call alloc_vreg
    push rax
    mov rdi, IR_FILE_OPEN
    mov rsi, TYPE_FILE
    mov rdx, [rsp] ; dst vreg
    mov r8, r12    ; src2 = mode vreg
    xor r9, r9
    xor r10, r10
    call emit_ir
    pop rax
    mov rdx, TYPE_FILE
    ret
.open_type_err:
    mov rdi, err_type_mismatch
    jmp compile_error

.inline_if:
    ; if <cond>: <expr> else: <expr>
    push rbx
    push r12
    push r13
    push r14
    call advance ; consume 'if'
    call parse_expr ; rax = cond vreg, rdx = cond type
    mov r12, rax ; cond vreg
    mov edi, TOK_COLON
    call expect
    ; else_label
    call gen_label
    mov r14, rax
    ; JCC cond != true → else_label
    mov rdi, r14
    mov rsi, COND_NE
    mov rcx, r12
    call emit_jcc
    ; then-expr
    call parse_expr ; rax = then vreg, rdx = then type
    push rax ; then vreg
    push rdx ; then type
    call alloc_vreg
    mov r13, rax ; result vreg
    ; IR_MOV result, then_vreg
    mov rdi, IR_MOV
    mov rsi, [rsp] ; type
    mov rdx, r13
    mov rcx, [rsp + 8] ; then vreg
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir
    ; JMP done_label
    call gen_label
    push rax ; done_label
    mov rdi, rax
    call emit_jmp
    ; else_label:
    mov rdi, r14
    call emit_label
    ; expect 'else'
    mov edi, TOK_ELSE
    call expect
    ; expect ':'
    mov edi, TOK_COLON
    call expect
    ; else-expr
    call parse_expr ; rax = else vreg, rdx = else type
    push rax ; else vreg
    push rdx ; else type
    ; Type check: then type == else type
    mov rax, [rsp + 24] ; then type
    cmp rax, [rsp]     ; else type
    jne type_error
    mov rdi, IR_MOV
    mov rsi, [rsp] ; type
    mov rdx, r13 ; result vreg
    mov rcx, [rsp + 8] ; else vreg
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir
    ; done_label:
    add rsp, 16 ; (discard else type + else vreg)
    pop rdi ; done_label
    call emit_label
    pop rdx ; then type
    pop rcx ; (discard then vreg)
    mov rax, r13 ; result vreg
    ; rdx = result type
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.when_expr:
    ; when <expr> → tri-state bool monitor (-1/0/1)
    ; design §7.3: one hidden state cell per unique `when expr` text;
    ; repeated occurrences of the same expression share the monitor.
    push rbx
    push r12
    push r13
    push r14
    call advance ; consume 'when'
    mov r14, [tok_str_ptr] ; start of expression text (first token)
    call parse_expr ; rax = cond vreg, rdx = cond type
    mov r13, [tok_str_ptr] ; end of expression text (start of next token)
    push rax ; save cond vreg
    ; FNV-1a 64 hash of the expression source span [r14, r13)
    mov rdi, r14
    mov rsi, r13
    call .hash_span
    mov r12, rax ; r12 = hash
    call .when_monitor_id ; rax = monitor_id (dedup)
    mov r14, rax ; r14 = monitor_id
    call alloc_vreg
    mov rbx, rax ; dst vreg
    pop rcx ; cond vreg
    mov rdi, IR_WHEN
    mov rsi, TYPE_BOOL
    mov rdx, rbx
    xor r8, r8
    mov r9, r14 ; imm = monitor_id
    xor r10, r10
    call emit_ir
    mov rax, rbx
    mov rdx, TYPE_BOOL
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; FNV-1a 64 hash of the byte span [rdi, rsi). Returns hash in rax.
; Clobbers rcx, rdx, r8, rdi, rsi. Preserves rbx, r12-r15.
.hash_span:
    mov rax, 0xcbf29ce484222325
    mov r8, 0x100000001b3
    mov rcx, rdi
    mov rdx, rsi
    sub rdx, rdi
    jz .done
.loop:
    movzx rdi, byte [rcx]
    xor rax, rdi
    imul rax, r8
    inc rcx
    dec rdx
    jnz .loop
.done:
    ret

; Look up/insert monitor hash (r12) → returns monitor_id in rax.
.when_monitor_id:
    xor ecx, ecx
.lookup:
    cmp ecx, [when_count]
    jae .add_new
    mov rax, [when_hash_table + rcx*8]
    cmp rax, r12
    je .found
    inc ecx
    jmp .lookup
.add_new:
    mov eax, [when_count]
    cmp eax, WHEN_MONITOR_MAX
    jae .overflow
    mov [when_hash_table + rax*8], r12
    inc dword [when_count]
    ret
.found:
    mov eax, ecx
    ret
.overflow:
    mov rdi, err_when_overflow
    jmp compile_error

.proto_call:
    ; '@' proto_name '(' args ')'
    call advance ; consume '@' → IDENT
    call parse_proto_call
    ret

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
    ; Struct construction: Type{ field: expr, ... } — the type name is a
    ; TOK_IDENT followed by '{'. Peek before committing.
    call lexer_peek_token
    cmp eax, TOK_LBRACE
    jne .ident_not_brace
    mov rdi, [tok_str_ptr]
    mov rsi, [tok_str_len]
    call type_lookup
    cmp rax, -1
    je .undef_error
    push rax
    mov rdi, rax
    call type_get_kind
    mov rcx, rax
    pop rax
    cmp rcx, TYPE_COMPLEX
    jne .ident_not_construct
    jmp .struct_construct
.ident_not_brace:
    ; Qualified module access: `mod.name` (design.md §17.2). A registered
    ; module name followed by '.' resolves to one of its members. Module
    ; names win over variable names when they collide.
    call lexer_peek_token
    cmp eax, TOK_DOT
    jne .ident_not_construct
    mov rdi, [tok_str_ptr]
    mov rsi, [tok_str_len]
    call module_lookup
    cmp rax, -1
    je .ident_not_construct
    mov r15, rax ; module id
    call advance ; consume module name → '.'
    mov edi, TOK_DOT
    call expect ; consume '.' → current token = member IDENT
    mov eax, [current_token]
    cmp eax, TOK_IDENT
    jne expected_ident
    jmp parse_qualified_expr
.ident_not_construct:
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

    ; Struct variables hold a pointer to their slot: emit LEA_VAR instead of
    ; LOAD_VAR (the struct body lives in the variable's storage).
    mov rdi, [rsp + 8] ; type
    push rdi
    call type_get_kind
    mov rcx, rax
    pop rdi
    cmp rcx, TYPE_COMPLEX
    je .ident_struct_var

    mov rdi, IR_LOAD_VAR
    mov rsi, [rsp + 8] ; type
    mov rdx, [rsp] ; dst
    xor rcx, rcx
    xor r8, r8
    xor r10, r10
    call emit_ir
    jmp .ident_vreg_ready

.ident_struct_var:
    mov rdi, IR_LEA_VAR
    mov rsi, [rsp + 8] ; type
    mov rdx, [rsp] ; dst
    xor rcx, rcx
    xor r8, r8
    xor r10, r10
    call emit_ir

.ident_vreg_ready:
    pop rax ; vreg
    pop rdx ; type
    ; Store type_id in vreg_type_map for struct field access
    push rax
    push rdx
    mov [vreg_type_map + rax * 4], edx
    ; Store container element type for bracket indexing
    push rbx
    push rcx
    push rax
    mov rdi, [rsp + 40] ; sym_idx
    extern sym_get_elem_type
    call sym_get_elem_type
    mov rcx, rax
    pop rax
    mov [vreg_elem_types + rax * 4], ecx
    pop rcx
    pop rbx
    pop rdx
    pop rax
    add rsp, 8 ; clean up sym_idx
    ret

; ─────────────────────────────────────────────────────────────
; Struct construction:  Type{ field: expr, ... }
; rax = struct type id on entry (from type_lookup in .ident)
; Returns: rax = scratch pointer vreg, rdx = struct type id
; The struct body is built into a bump-allocated scratch slot; the
; surrounding context (declaration/mutation/copy) moves it into place.
.struct_construct:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rax ; struct type id

    ; Allocate a scratch slot for the body (bump, never reclaimed)
    mov rdi, r12
    call type_get_size ; rax = struct size
    add rax, 7
    and rax, -8        ; round up to 8
    push rax           ; [rsp] = slot size (rounded)
    mov eax, [struct_scratch_ptr] ; bump offset into scratch pool
    push rax           ; [rsp] = offset ; [rsp+8] = slot size
    add eax, [rsp + 8]
    mov [struct_scratch_ptr], eax
    ; Base address in the running program = SCRATCH_BASE + offset
    mov eax, STRUCT_SCRATCH_BASE
    add eax, [rsp]
    mov [rsp], eax     ; [rsp] = absolute base address

    ; LEA base → pointer vreg (r15)
    call alloc_vreg
    mov r15, rax
    mov rdi, IR_LEA_VAR
    mov rsi, r12
    mov rdx, r15
    xor rcx, rcx
    xor r8, r8
    mov r9, [rsp] ; base address
    xor r10, r10
    call emit_ir
    mov [vreg_type_map + r15 * 4], r12d
    add rsp, 16 ; drop base + slot size

    ; Consume type name + '{'
    call advance ; consume Type name IDENT
    mov edi, TOK_LBRACE
    call expect

.field_loop:
    mov eax, [current_token]
    cmp eax, TOK_RBRACE
    je .field_done
    cmp eax, TOK_IDENT
    jne .construct_err
    ; Find field
    mov rdi, r12
    mov rsi, [tok_str_ptr]
    mov rdx, [tok_str_len]
    call type_struct_find_field ; rax = offset, rcx = field type
    cmp rax, -1
    je .construct_err
    mov r13, rax ; field offset
    mov r14, rcx ; field type
    call advance ; consume field name
    mov edi, TOK_COLON
    call expect
    ; Parse the field value
    call parse_expr ; rax = value vreg, rdx = value type
    ; r15 = base ptr vreg, r13 = offset, r14 = field type
    push rax                ; [rsp] = value vreg (survives the calls below)
    push rdx                ; [rsp+8] = value type
    mov rdi, r14
    call type_get_kind
    pop rdx                 ; rdx = value type
    cmp al, TYPE_COMPLEX
    jne .field_scalar_check
    mov rax, [rsp]
    add rsp, 8              ; drop saved value vreg
    jmp .field_nested
.field_scalar_check:
    ; Scalar field: type check then STORE_FIELD
    mov rax, r14
    call types_compatible   ; compares r14 (field) vs rdx (value type)
    je .field_scalar_ok
    cmp r14, TYPE_BYTE
    je .byte_field_checks
    add rsp, 8              ; drop saved value vreg
    jmp .construct_err
.byte_field_checks:
    cmp rdx, TYPE_CHAR
    je .field_scalar_ok
    cmp rdx, TYPE_INT
    je .field_scalar_ok
    add rsp, 8              ; drop saved value vreg
    jmp .construct_err
.field_scalar_ok:
    ; STORE_FIELD base_ptr, value, off
    mov rdi, IR_STORE_FIELD
    mov rsi, r14
    xor rdx, rdx
    mov rcx, r15 ; base ptr
    mov r8, [rsp] ; value
    mov r9, r13 ; offset
    xor r10, r10
    call emit_ir
    add rsp, 8              ; drop saved value vreg
    jmp .field_next
.field_nested:
    ; rax = value ptr vreg, rdx = value type; field type r14 is a struct.
    ; Copy value field-by-field into [base + off].
    push rax ; rax pushed first → [rsp+8] = value ptr vreg
    push rdx ; rdx pushed second → [rsp]   = value type
    mov rax, r14
    mov rdx, [rsp]   ; value type (at [rsp], since rdx was pushed last)
    call types_compatible
    jne .construct_err
    add rsp, 8 ; drop value type
    call alloc_vreg ; rax = target vreg
    push rax ; [rsp] = target vreg ; [rsp+8] = value ptr vreg
    mov rdi, IR_LEA_FIELD
    mov rsi, r14
    mov rdx, [rsp]
    mov rcx, r15
    xor r8, r8
    mov r9, r13
    xor r10, r10
    call emit_ir
    mov rdi, [rsp]   ; dst = target vreg
    mov rsi, [rsp+8] ; src = value ptr vreg
    mov rdx, r14     ; struct type
    call emit_struct_copy
    add rsp, 16
.field_next:
    mov eax, [current_token]
    cmp eax, TOK_COMMA
    jne .field_done
    call advance
    jmp .field_loop
.field_done:
    mov edi, TOK_RBRACE
    call expect
    mov rax, r15
    mov rdx, r12
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.construct_err:
    mov rdi, err_syntax
    jmp compile_error

.undef_error:
    ; Check if this is a known builtin function name before erroring
    ; The identifier string is still in tok_str_ptr/tok_str_len (advance not called)
    ; Populate method_buf from tok_str_ptr/tok_str_len for ident_is comparisons
    mov rsi, [tok_str_ptr]
    mov rcx, [tok_str_len]
    cmp rcx, 31
    jle .builtin_mlen_ok
    mov rcx, 31
.builtin_mlen_ok:
    mov [method_len], rcx
    lea rdi, [method_buf]
    push rcx
    test rcx, rcx
    jz .builtin_mcopy_done
.builtin_mcopy:
    movzx rax, byte [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jnz .builtin_mcopy
.builtin_mcopy_done:
    pop rcx
    lea rdi, [method_buf]
    add rdi, rcx
    mov byte [rdi], 0
    lea rdi, [str_abs]
    call ident_is
    test rax,rax
    jnz .builtin_abs
    lea rdi, [str_ceil]
    call ident_is
    test rax,rax
    jnz .builtin_ceil
    lea rdi, [str_sqrt]
    call ident_is
    test rax,rax
    jnz .builtin_sqrt
    lea rdi, [str_floor]
    call ident_is
    test rax,rax
    jnz .builtin_floor
    lea rdi, [str_round]
    call ident_is
    test rax,rax
    jnz .builtin_round
    lea rdi, [str_trunc]
    call ident_is
    test rax,rax
    jnz .builtin_trunc
    lea rdi, [str_fract]
    call ident_is
    test rax,rax
    jnz .builtin_fract
    lea rdi, [str_signum]
    call ident_is
    test rax,rax
    jnz .builtin_signum
    lea rdi, [str_min]
    call ident_is
    test rax,rax
    jnz .builtin_min
    lea rdi, [str_max]
    call ident_is
    test rax,rax
    jnz .builtin_max
    lea rdi, [str_clamp]
    call ident_is
    test rax,rax
    jnz .builtin_clamp
    lea rdi, [str_recip]
    call ident_is
    test rax,rax
    jnz .builtin_recip
    lea rdi, [str_sin]
    call ident_is
    test rax,rax
    jnz .builtin_sin
    lea rdi, [str_cos]
    call ident_is
    test rax,rax
    jnz .builtin_cos
    lea rdi, [str_tan]
    call ident_is
    test rax,rax
    jnz .builtin_tan
    lea rdi, [str_pow]
    call ident_is
    test rax,rax
    jnz .builtin_pow
    lea rdi, [str_cbrt]
    call ident_is
    test rax,rax
    jnz .builtin_cbrt
    lea rdi, [str_gcd]
    call ident_is
    test rax,rax
    jnz .builtin_gcd
    lea rdi, [str_lcm]
    call ident_is
    test rax,rax
    jnz .builtin_lcm
    lea rdi, [str_to_bin]
    call ident_is
    test rax,rax
    jnz .builtin_to_bin
    lea rdi, [str_to_hex]
    call ident_is
    test rax,rax
    jnz .builtin_to_hex
    lea rdi, [str_to_oct]
    call ident_is
    test rax,rax
    jnz .builtin_to_oct
    lea rdi, [str_sum_m]
    call ident_is
    test rax,rax
    jnz .builtin_sum
    lea rdi, [str_alpha]
    call ident_is
    test rax,rax
    jnz .builtin_alpha
    lea rdi, [str_digit]
    call ident_is
    test rax,rax
    jnz .builtin_digit
    lea rdi, [str_upper]
    call ident_is
    test rax,rax
    jnz .builtin_upper
    lea rdi, [str_lower]
    call ident_is
    test rax,rax
    jnz .builtin_lower
    lea rdi, [str_whitespace]
    call ident_is
    test rax,rax
    jnz .builtin_whitespace
    lea rdi, [str_alnum_m]
    call ident_is
    test rax,rax
    jnz .builtin_alnum
    lea rdi, [str_punct_m]
    call ident_is
    test rax,rax
    jnz .builtin_punct
    lea rdi, [str_printable_m]
    call ident_is
    test rax,rax
    jnz .builtin_printable
    lea rdi, [str_ascii_m]
    call ident_is
    test rax,rax
    jnz .builtin_ascii
    lea rdi, [str_hex_m]
    call ident_is
    test rax,rax
    jnz .builtin_hex
    lea rdi, [str_bin_m]
    call ident_is
    test rax,rax
    jnz .builtin_bin
    lea rdi, [str_oct_m]
    call ident_is
    test rax,rax
    jnz .builtin_oct
    lea rdi, [str_zero]
    call ident_is
    test rax,rax
    jnz .builtin_zero
    lea rdi, [str_positive]
    call ident_is
    test rax,rax
    jnz .builtin_positive
    lea rdi, [str_negative]
    call ident_is
    test rax,rax
    jnz .builtin_negative
    lea rdi, [str_even]
    call ident_is
    test rax,rax
    jnz .builtin_even
    lea rdi, [str_odd]
    call ident_is
    test rax,rax
    jnz .builtin_odd
    lea rdi, [str_nan]
    call ident_is
    test rax,rax
    jnz .builtin_nan
    lea rdi, [str_inf]
    call ident_is
    test rax,rax
    jnz .builtin_inf
    lea rdi, [str_finite]
    call ident_is
    test rax,rax
    jnz .builtin_finite
    lea rdi, [str_file_exists]
    call ident_is
    test rax,rax
    jnz .builtin_file_exists
    jmp undef_error

.uninit_error:
    add rsp, 8 ; clean up sym_idx
    mov rdi, err_uninit
    jmp compile_error

; === Builtin function handlers ===
; These are reached from .undef_error in parse_term
; The identifier has NOT been consumed yet (advance not called)

.builtin_abs:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop rdx
    pop rcx
    cmp rdx, TYPE_INT
    je .builtin_abs_int
    cmp rdx, TYPE_FLOAT
    je .builtin_abs_float
    mov rdi, err_type_mismatch
    jmp compile_error
.builtin_abs_int:
    call alloc_vreg
    push rax
    mov rdi, IR_ABS_INT
    mov rsi, TYPE_INT
    mov rdx, [rsp]
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_INT
    ret
.builtin_abs_float:
    call alloc_vreg
    push rax
    mov rdi, IR_ABS_FLOAT
    mov rsi, TYPE_FLOAT
    mov rdx, [rsp]
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_FLOAT
    ret

.builtin_ceil:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop rdx
    pop rcx
    cmp rdx, TYPE_FLOAT
    jne .builtin_float_type_err
    call alloc_vreg
    push rax
    mov rdi, IR_CEIL
    mov rsi, TYPE_FLOAT
    mov rdx, [rsp]
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_INT
    ret

.builtin_float_type_err:
    mov rdi, err_type_mismatch
    jmp compile_error

.builtin_sqrt:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop rdx
    pop rcx
    cmp rdx, TYPE_FLOAT
    jne .builtin_float_type_err
    call alloc_vreg
    push rax
    mov rdi, IR_SQRT
    mov rsi, TYPE_FLOAT
    mov rdx, [rsp]
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_FLOAT
    ret

.builtin_floor:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop rdx
    pop rcx
    cmp rdx, TYPE_FLOAT
    jne .builtin_float_type_err
    call alloc_vreg
    push rax
    mov rdi, IR_FLOOR
    mov rsi, TYPE_FLOAT
    mov rdx, [rsp]
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_INT
    ret

.builtin_round:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop rdx
    pop rcx
    cmp rdx, TYPE_FLOAT
    jne .builtin_float_type_err
    call alloc_vreg
    push rax
    mov rdi, IR_ROUND
    mov rsi, TYPE_FLOAT
    mov rdx, [rsp]
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_INT
    ret

.builtin_trunc:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop rdx
    pop rcx
    cmp rdx, TYPE_FLOAT
    jne .builtin_float_type_err
    call alloc_vreg
    push rax
    mov rdi, IR_TRUNC_F
    mov rsi, TYPE_FLOAT
    mov rdx, [rsp]
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_FLOAT
    ret

.builtin_fract:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop rdx
    pop r12
    cmp rdx, TYPE_FLOAT
    jne .builtin_float_type_err
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
    call alloc_vreg
    push rax
    mov rdi, IR_SUB
    mov rsi, TYPE_FLOAT
    mov rdx, [rsp]
    mov rcx, r12
    mov r8, [rsp+8]
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    add rsp, 8
    mov rdx, TYPE_FLOAT
    ret

.builtin_signum:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop rdx
    pop rcx
    cmp rdx, TYPE_INT
    je .builtin_signum_int
    cmp rdx, TYPE_FLOAT
    je .builtin_signum_float
    mov rdi, err_type_mismatch
    jmp compile_error
.builtin_signum_int:
    call alloc_vreg
    push rax
    mov rdi, IR_SIGNUM
    mov rsi, TYPE_INT
    mov rdx, [rsp]
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_INT
    ret
.builtin_signum_float:
    call alloc_vreg
    push rax
    mov rdi, IR_SIGNUM_F
    mov rsi, TYPE_FLOAT
    mov rdx, [rsp]
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_FLOAT
    ret

.builtin_min:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_COMMA
    call expect
    call parse_expr
    push rax
    mov edi, TOK_RPAREN
    call expect
    pop r8
    pop rdx
    pop rcx
    cmp rdx, TYPE_INT
    je .builtin_min_int
    cmp rdx, TYPE_FLOAT
    je .builtin_min_float
    mov rdi, err_type_mismatch
    jmp compile_error
.builtin_min_int:
    push rcx
    push r8
    call alloc_vreg
    pop r8
    pop rcx
    push rax
    mov rdi, IR_MIN_INT
    mov rsi, TYPE_INT
    mov rdx, [rsp]
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_INT
    ret
.builtin_min_float:
    push rcx
    push r8
    call alloc_vreg
    pop r8
    pop rcx
    push rax
    mov rdi, IR_MIN_FLOAT
    mov rsi, TYPE_FLOAT
    mov rdx, [rsp]
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_FLOAT
    ret

.builtin_max:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_COMMA
    call expect
    call parse_expr
    push rax
    mov edi, TOK_RPAREN
    call expect
    pop r8
    pop rdx
    pop rcx
    cmp rdx, TYPE_INT
    je .builtin_max_int
    cmp rdx, TYPE_FLOAT
    je .builtin_max_float
    mov rdi, err_type_mismatch
    jmp compile_error
.builtin_max_int:
    push rcx
    push r8
    call alloc_vreg
    pop r8
    pop rcx
    push rax
    mov rdi, IR_MAX_INT
    mov rsi, TYPE_INT
    mov rdx, [rsp]
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_INT
    ret
.builtin_max_float:
    push rcx
    push r8
    call alloc_vreg
    pop r8
    pop rcx
    push rax
    mov rdi, IR_MAX_FLOAT
    mov rsi, TYPE_FLOAT
    mov rdx, [rsp]
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_FLOAT
    ret

.builtin_clamp:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax        ; value
    push rdx        ; type
    mov edi, TOK_COMMA
    call expect
    call parse_expr
    push rax        ; lo
    mov edi, TOK_COMMA
    call expect
    call parse_expr
    push rax        ; hi
    mov edi, TOK_RPAREN
    call expect
    pop r15         ; hi
    pop r14         ; lo
    pop rdx         ; type
    pop r12         ; value
    cmp rdx, TYPE_INT
    je .builtin_clamp_int
    cmp rdx, TYPE_FLOAT
    je .builtin_clamp_float
    mov rdi, err_type_mismatch
    jmp compile_error
.builtin_clamp_int:
    ; temp = min(value, hi)
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
    push rax
    mov rdi, IR_MAX_INT
    mov rsi, TYPE_INT
    mov rdx, [rsp]
    mov rcx, r14
    mov r8, [rsp+8]
    xor r9,r9
    xor r10,r10
    call emit_ir
    add rsp, 8
    pop rax
    mov rdx, TYPE_INT
    ret
.builtin_clamp_float:
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
    push rax
    mov rdi, IR_MAX_FLOAT
    mov rsi, TYPE_FLOAT
    mov rdx, [rsp]
    mov rcx, r14
    mov r8, [rsp+8]
    xor r9,r9
    xor r10,r10
    call emit_ir
    add rsp, 8
    pop rax
    mov rdx, TYPE_FLOAT
    ret

.builtin_recip:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax                ; [arg]
    push rdx                ; [argtype, arg]
    mov edi, TOK_RPAREN
    call expect
    pop rdx                 ; [arg]
    cmp rdx, TYPE_FLOAT
    jne .builtin_float_type_err
    call alloc_vreg
    push rax                ; [one, arg]
    mov rdi, IR_LOAD_FIMM
    mov rsi, TYPE_FLOAT
    mov rdx, [rsp]
    xor rcx,rcx
    xor r8,r8
    mov r9, [float_pp_one]
    xor r10,r10
    call emit_ir
    call alloc_vreg
    push rax                ; [result, one, arg]
    mov rdi, IR_DIV
    mov rsi, TYPE_FLOAT
    mov rdx, [rsp]          ; dst = result
    mov rcx, [rsp+8]        ; src1 = one
    mov r8, [rsp+16]        ; src2 = arg
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov rax, [rsp]          ; rax = result
    add rsp, 24
    mov rdx, TYPE_FLOAT
    ret

.builtin_sin:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop rdx
    pop rcx
    cmp rdx, TYPE_FLOAT
    jne .builtin_float_type_err
    call alloc_vreg
    push rax
    mov rdi, IR_SIN
    mov rsi, TYPE_FLOAT
    mov rdx, [rsp]
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_FLOAT
    ret

.builtin_cos:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop rdx
    pop rcx
    cmp rdx, TYPE_FLOAT
    jne .builtin_float_type_err
    call alloc_vreg
    push rax
    mov rdi, IR_COS
    mov rsi, TYPE_FLOAT
    mov rdx, [rsp]
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_FLOAT
    ret

.builtin_tan:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop rdx
    pop rcx
    cmp rdx, TYPE_FLOAT
    jne .builtin_float_type_err
    call alloc_vreg
    push rax
    mov rdi, IR_TAN
    mov rsi, TYPE_FLOAT
    mov rdx, [rsp]
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_FLOAT
    ret

.builtin_pow:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_COMMA
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop r15          ; arg2 type
    pop r14          ; arg2 vreg
    pop r13          ; arg1 type
    pop r12          ; arg1 vreg
    ; Both int → integer exponentiation
    cmp r13, TYPE_INT
    jne .builtin_pow_float
    cmp r15, TYPE_INT
    jne .builtin_pow_float
    call alloc_vreg
    push rax
    mov rdi, IR_POW_I
    mov rsi, TYPE_INT
    mov rdx, [rsp]
    mov rcx, r12
    mov r8, r14
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_INT
    ret
.builtin_pow_float:
    ; Both args must be float (no implicit int→float coercion in Rex)
    cmp r13, TYPE_FLOAT
    jne .builtin_pow_type_err
    cmp r15, TYPE_FLOAT
    jne .builtin_pow_type_err
    call alloc_vreg
    push rax
    mov rdi, IR_POW_F
    mov rsi, TYPE_FLOAT
    mov rdx, [rsp]
    mov rcx, r12
    mov r8, r14
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_FLOAT
    ret
.builtin_pow_type_err:
    mov rdi, err_type_mismatch
    jmp compile_error

.builtin_cbrt:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop rdx
    pop rcx
    cmp rdx, TYPE_FLOAT
    jne .builtin_float_type_err
    call alloc_vreg
    push rax
    mov rdi, IR_CBRT
    mov rsi, TYPE_FLOAT
    mov rdx, [rsp]
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_FLOAT
    ret

.builtin_gcd:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    mov edi, TOK_COMMA
    call expect
    call parse_expr
    push rax
    mov edi, TOK_RPAREN
    call expect
    pop r8
    pop rcx
    push rcx
    push r8
    call alloc_vreg
    pop r8
    pop rcx
    push rax
    mov rdi, IR_GCD
    mov rsi, TYPE_INT
    mov rdx, [rsp]
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_INT
    ret

.builtin_lcm:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    mov edi, TOK_COMMA
    call expect
    call parse_expr
    push rax
    mov edi, TOK_RPAREN
    call expect
    pop r8
    pop rcx
    push rcx
    push r8
    call alloc_vreg
    pop r8
    pop rcx
    push rax
    mov rdi, IR_LCM
    mov rsi, TYPE_INT
    mov rdx, [rsp]
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_INT
    ret

.builtin_to_bin:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    mov edi, TOK_RPAREN
    call expect
    pop rcx
    call alloc_vreg
    push rax
    mov rdi, IR_TO_BIN_STR
    mov rsi, TYPE_STR
    mov rdx, [rsp]
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_STR
    ret

.builtin_to_hex:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    mov edi, TOK_RPAREN
    call expect
    pop rcx
    call alloc_vreg
    push rax
    mov rdi, IR_TO_HEX_STR
    mov rsi, TYPE_STR
    mov rdx, [rsp]
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_STR
    ret

.builtin_to_oct:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    mov edi, TOK_RPAREN
    call expect
    pop rcx
    call alloc_vreg
    push rax
    mov rdi, IR_TO_OCT_STR
    mov rsi, TYPE_STR
    mov rdx, [rsp]
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_STR
    ret

.builtin_sum:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop rdx
    pop rcx
    cmp rdx, TYPE_SEQ
    jne .builtin_sum_type_err
    call alloc_vreg
    push rax
    mov rdi, IR_SEQ_SUM
    mov rsi, TYPE_INT
    mov rdx, [rsp]
    ; rcx = seq vreg (src1)
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_INT
    ret
.builtin_sum_type_err:
    mov rdi, err_type_mismatch
    jmp compile_error

; Single-arg char predicates: alpha / whitespace / alnum / punct / printable
; Uses r13=type, returns bool
%macro builtin_char_pred 1
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop r13
    pop r12
    cmp r13, TYPE_CHAR
    jne .char_pred_type_err
    call alloc_vreg
    push rax
    mov rdi, %1
    mov rsi, TYPE_BOOL
    mov rdx, [rsp]
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_BOOL
    ret
%endmacro

.builtin_alpha:        builtin_char_pred IR_IS_ALPHA
.builtin_whitespace:   builtin_char_pred IR_IS_SPACE
.builtin_alnum:        builtin_char_pred IR_IS_ALNUM
.builtin_punct:        builtin_char_pred IR_IS_PUNCT
.builtin_printable:    builtin_char_pred IR_IS_PRINT

.char_pred_type_err:
    mov rdi, err_type_mismatch
    jmp compile_error

.builtin_digit:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop r13
    pop r12
    cmp r13, TYPE_CHAR
    jne .char_pred_type_err
    call alloc_vreg
    push rax
    mov rdi, IR_TO_DIGIT
    mov rsi, TYPE_INT
    mov rdx, [rsp]
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_INT
    ret

.builtin_upper:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop r13
    pop r12
    cmp r13, TYPE_CHAR
    jne .char_pred_type_err
    call alloc_vreg
    push rax
    mov rdi, IR_TO_UPPER
    mov rsi, TYPE_CHAR
    mov rdx, [rsp]
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_CHAR
    ret

.builtin_lower:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop r13
    pop r12
    cmp r13, TYPE_CHAR
    jne .char_pred_type_err
    call alloc_vreg
    push rax
    mov rdi, IR_TO_LOWER
    mov rsi, TYPE_CHAR
    mov rdx, [rsp]
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_CHAR
    ret

.builtin_ascii:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop r13
    pop r12
    cmp r13, TYPE_CHAR
    je .ascii_cmp
    cmp r13, TYPE_BYTE
    jne .char_pred_type_err
.ascii_cmp:
    call alloc_vreg
    push rax
    mov rdi, IR_CMP_BOOL
    mov rsi, TYPE_INT
    mov rdx, [rsp]
    mov rcx, r12
    xor r8,r8
    mov r9,128
    mov r10,COND_LT
    call emit_ir
    pop rax
    mov rdx, TYPE_BOOL
    ret

.builtin_hex:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop r13
    pop r12
    cmp r13, TYPE_INT
    je .hex_int
    cmp r13, TYPE_BYTE
    je .hex_byte
    mov rdi, err_type_mismatch
    jmp compile_error
.hex_int:
    call alloc_vreg
    push rax
    mov rdi, IR_TO_HEX_STR
    mov rsi, TYPE_STR
    mov rdx, [rsp]
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_STR
    ret
.hex_byte:
    call alloc_vreg
    push rax
    mov rdi, IR_BYTE_HEX
    mov rsi, TYPE_STR
    mov rdx, [rsp]
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_STR
    ret

.builtin_bin:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop r13
    pop r12
    cmp r13, TYPE_INT
    je .bin_int
    cmp r13, TYPE_BYTE
    je .bin_byte
    mov rdi, err_type_mismatch
    jmp compile_error
.bin_int:
    call alloc_vreg
    push rax
    mov rdi, IR_TO_BIN_STR
    mov rsi, TYPE_STR
    mov rdx, [rsp]
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_STR
    ret
.bin_byte:
    call alloc_vreg
    push rax
    mov rdi, IR_BYTE_BIN
    mov rsi, TYPE_STR
    mov rdx, [rsp]
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_STR
    ret

.builtin_oct:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop r13
    pop r12
    cmp r13, TYPE_INT
    je .oct_int
    mov rdi, err_type_mismatch
    jmp compile_error
.oct_int:
    call alloc_vreg
    push rax
    mov rdi, IR_TO_OCT_STR
    mov rsi, TYPE_STR
    mov rdx, [rsp]
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_STR
    ret

; zero/positive/negative: int/byte via CMP_BOOL, float via IR_IS_*_F
%macro builtin_cmp_bool 2
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop r13
    pop r12
    cmp r13, TYPE_FLOAT
    je .num_pred_float_%2
    call alloc_vreg
    push rax
    mov rdi, IR_CMP_BOOL
    mov rsi, TYPE_INT
    mov rdx, [rsp]
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    mov r10,%1
    call emit_ir
    pop rax
    mov rdx, TYPE_BOOL
    ret
%endmacro

.builtin_zero:
    builtin_cmp_bool COND_EQ, zero
.builtin_positive:
    builtin_cmp_bool COND_GT, pos
.builtin_negative:
    builtin_cmp_bool COND_LT, neg

.num_pred_float_zero:
    mov rdi, IR_IS_ZERO_F
    jmp .num_pred_float_emit
.num_pred_float_pos:
    mov rdi, IR_IS_POS_F
    jmp .num_pred_float_emit
.num_pred_float_neg:
    mov rdi, IR_IS_NEG_F
.num_pred_float_emit:
    push rdi
    call alloc_vreg
    pop rdi
    push rax
    mov rsi, TYPE_BOOL
    mov rdx, [rsp]
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_BOOL
    ret

.builtin_even:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop r13
    pop r12
    cmp r13, TYPE_FLOAT
    je .char_pred_type_err
    call alloc_vreg
    push rax
    mov rdi, IR_IS_EVEN
    mov rsi, TYPE_BOOL
    mov rdx, [rsp]
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_BOOL
    ret

.builtin_odd:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop r13
    pop r12
    cmp r13, TYPE_FLOAT
    je .char_pred_type_err
    call alloc_vreg
    push rax
    mov rdi, IR_IS_ODD
    mov rsi, TYPE_BOOL
    mov rdx, [rsp]
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_BOOL
    ret

.builtin_nan:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop r13
    pop r12
    cmp r13, TYPE_FLOAT
    jne .char_pred_type_err
    call alloc_vreg
    push rax
    mov rdi, IR_IS_NAN
    mov rsi, TYPE_BOOL
    mov rdx, [rsp]
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_BOOL
    ret

.builtin_inf:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop r13
    pop r12
    cmp r13, TYPE_FLOAT
    jne .char_pred_type_err
    call alloc_vreg
    push rax
    mov rdi, IR_IS_INF
    mov rsi, TYPE_BOOL
    mov rdx, [rsp]
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_BOOL
    ret

.builtin_finite:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop r13
    pop r12
    cmp r13, TYPE_FLOAT
    jne .char_pred_type_err
    call alloc_vreg
    push rax
    mov rdi, IR_IS_FINITE
    mov rsi, TYPE_BOOL
    mov rdx, [rsp]
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_BOOL
    ret

; file_exists(path) — bool
.builtin_file_exists:
    call advance
    mov edi, TOK_LPAREN
    call expect
    call parse_expr
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop r13
    pop r12
    cmp r13, TYPE_STR
    jne .char_pred_type_err
    call alloc_vreg
    push rax
    mov rdi, IR_FILE_EXISTS
    mov rsi, TYPE_BOOL
    mov rdx, [rsp]
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    pop rax
    mov rdx, TYPE_BOOL
    ret

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
    mov rbx, [rsp+8] ; recover dst vreg (was pushed, not yet popped)
    add rsp, 24
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
    jmp undef_error

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
    ; [v1, v2, ...] in expression context → real seq value (TYPE_SEQ).
    ; (M-fix: previously this merely counted elements and returned an int,
    ;  so f.write_bytes([1,2,3]) saw an int and failed to type-check.)
    push rbx
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

.array_loop:
    mov eax, [current_token]
    cmp eax, TOK_RBRACKET
    je .array_done
    cmp eax, TOK_EOF
    je .array_done
    ; Parse the element value
    call parse_expr    ; rax = elem vreg, rdx = elem type
    mov r14, rax       ; save elem vreg
    mov rbx, rdx       ; save elem type

    ; Emit IR_SEQ_PUSH
    mov rdi, IR_SEQ_PUSH
    mov rsi, rbx       ; element type
    xor rdx, rdx       ; dst = 0 (void)
    mov rcx, r15       ; src1 = seq vreg
    mov r8, r14        ; src2 = elem vreg
    mov r9, SEQ_ELEMENT_SIZE  ; imm = element size
    xor r10, r10
    call emit_ir

    ; Check for comma
    mov eax, [current_token]
    cmp eax, TOK_COMMA
    jne .array_done
    call advance ; consume comma
    jmp .array_loop
.array_done:
    mov edi, TOK_RBRACKET
    call expect ; consume ']'

    mov rax, r15
    mov rdx, TYPE_SEQ

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
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
    cmp r12, TYPE_STR
    je .cast_to_str
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
    cmp r13, TYPE_STR
    je .cast_use_stoi
    ; int(x) where x is already int — no-op, just use the vreg
    jmp .cast_noop
.cast_use_fti:
    mov r14, IR_CAST_FTI
    jmp .cast_done_emit
.cast_use_stoi:
    mov r14, IR_STOI
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
    cmp r13, TYPE_STR
    je .cast_use_stof
    ; float(x) where x is already float — no-op
    jmp .cast_noop
.cast_use_itf:
    mov r14, IR_CAST_ITF
    jmp .cast_done_emit
.cast_use_stof:
    mov r14, IR_STOF
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

.cast_to_str:
    cmp r13, TYPE_INT
    je .cast_use_itos
    cmp r13, TYPE_FLOAT
    je .cast_use_ftos
    cmp r13, TYPE_BOOL
    je .cast_use_btos
    cmp r13, TYPE_CHAR
    je .cast_use_ctos
    cmp r13, TYPE_BYTE
    je .cast_use_ctos
    ; str(x) where x is already str — no-op
    jmp .cast_noop
.cast_use_itos:
    mov r14, IR_ITOS
    jmp .cast_done_emit
.cast_use_ftos:
    mov r14, IR_FTOS
    jmp .cast_done_emit
.cast_use_btos:
    mov r14, IR_BTOS
    jmp .cast_done_emit
.cast_use_ctos:
    mov r14, IR_CTOS
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
    cmp eax, 65536
    jae .overflow
    inc dword [label_counter]
    ret
.overflow:
    mov rdi, err_label_overflow
    jmp compile_error

; Build unique hidden loop variable name "_for_end<label_counter>" into for_hidden_buf
; Returns: rdi = name ptr, rax = length (excluding null terminator)
build_for_hidden_name:
    push rbx
    push rcx
    push rdx
    lea rdi, [for_hidden_buf]
    lea rsi, [str_for_end]
    mov ecx, 8
    rep movsb ; copy "_for_end"
    ; Convert label_counter to decimal, digits built backward from buffer[16]
    mov eax, [label_counter]
    lea rdi, [for_hidden_buf + 16]
    mov ebx, 10
    xor ecx, ecx ; digit count
.test_zero:
    test eax, eax
    jne .digit_loop
    mov byte [rdi], '0'
    inc ecx
    jmp .digits_done
.digit_loop:
    xor edx, edx
    div ebx
    add edx, '0'
    dec rdi
    mov [rdi], dl
    inc ecx
    test eax, eax
    jnz .digit_loop
.digits_done:
    ; Move digits so they immediately follow "_for_end"
    mov rax, rcx ; digit count (rep movsb zeroes ecx)
    mov rdx, rdi ; source = first digit
    lea rdi, [for_hidden_buf + 8]
    mov rsi, rdx
    rep movsb
    add rax, 8 ; total length
    lea rdi, [for_hidden_buf]
    pop rdx
    pop rcx
    pop rbx
    ret

; Build unique hidden step variable name "_for_step<label_counter>"
; Returns: rdi = name ptr, rax = length (excluding null terminator)
build_for_hidden_step_name:
    push rbx
    push rcx
    push rdx
    lea rdi, [for_hidden_buf]
    lea rsi, [str_for_step]
    mov ecx, 9
    rep movsb ; copy "_for_step"
    ; Convert label_counter to decimal, digits built backward from buffer[17]
    mov eax, [label_counter]
    lea rdi, [for_hidden_buf + 17]
    mov ebx, 10
    xor ecx, ecx ; digit count
.test_zero:
    test eax, eax
    jne .digit_loop
    mov byte [rdi], '0'
    inc ecx
    jmp .digits_done
.digit_loop:
    xor edx, edx
    div ebx
    add edx, '0'
    dec rdi
    mov [rdi], dl
    inc ecx
    test eax, eax
    jnz .digit_loop
.digits_done:
    ; Move digits so they immediately follow "_for_step"
    mov rax, rcx ; digit count (rep movsb zeroes ecx)
    mov rdx, rdi ; source = first digit
    lea rdi, [for_hidden_buf + 9]
    mov rsi, rdx
    rep movsb
    add rax, 9 ; total length
    lea rdi, [for_hidden_buf]
    pop rdx
    pop rcx
    pop rbx
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

; Helper: push a loop context frame for stop/skip (design §8.5)
; rdi = loop_end label, rsi = loop_skip label
push_loop_context:
    mov eax, [loop_depth]
    cmp eax, LOOP_MAX_DEPTH
    jge .ctx_overflow
    mov [loop_end_labels + rax * 8], rdi
    mov [loop_skip_labels + rax * 8], rsi
    inc dword [loop_depth]
    xor eax, eax
    ret
.ctx_overflow:
    mov rdi, err_loop_nesting
    jmp compile_error

; Helper: pop a loop context frame (called at loop exit)
pop_loop_context:
    dec dword [loop_depth]
    ret

; Helper: emit a label into the loop_skip slot of the current (innermost) frame
; Used to mark the increment section of for/each/repeat loops so `skip`
; lands before the increment runs (design §8.5: "jump to condition check").
emit_loop_skip_label:
    mov eax, [loop_depth]
    test eax, eax
    jz .skip_no_frame
    dec eax
    mov rdi, [loop_skip_labels + rax * 8]
    call emit_label
.skip_no_frame:
    ret

; Helper: finish a loop by checking for an optional `else:` clause
; (design.md §8.6 — runs only when the loop exits naturally, not via `stop`).
; The loop's natural-exit JCC targets loop_else_entry; `stop` targets loop_end
; (stored in loop_end_labels), which is past the else block.
; Stack on entry: [retaddr][loop_else_entry][loop_end][loop_start].
; Emits the labels (else block between else_entry and loop_end). Does NOT touch
; the stack — the caller drops the three labels with `add rsp, 24` after the call.
loop_else_chain:
    mov eax, [current_token]
    cmp eax, TOK_NEWLINE
    jne .lec_cont
    call advance ; single-line loop body ends with NEWLINE before `else:`
    mov eax, [current_token]
.lec_cont:
    cmp eax, TOK_ELSE
    je .lec_else
    ; No else — else_entry and loop_end coincide at the loop's exit point
    mov rdi, [rsp + 8]  ; loop_else_entry
    call emit_label
    mov rdi, [rsp + 16] ; loop_end
    call emit_label
    ret
.lec_else:
    mov rdi, [rsp + 8]  ; loop_else_entry
    call emit_label
    call advance ; consume 'else'
    mov edi, TOK_COLON
    call expect
    call parse_block
    mov rdi, [rsp + 16] ; loop_end
    call emit_jmp
    mov rdi, [rsp + 16] ; loop_end
    call emit_label
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

    ret

.block_single:
    ; Single-line block: the body is one statement on the same line as
    ; the ':' (e.g. `if cond: :x = 5`). The condition's JCC and the
    ; trailing JMP/labels were already emitted by the caller, so the
    ; body MUST be parsed here, while the current token still points at
    ; the body statement. Otherwise the body would be left to the outer
    ; statement loop, landing AFTER the end-label in the IR and
    ; executing unconditionally (miscompile: both branches fall through).
    call parse_stmt
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
; rdi = message string (null-terminated; carries its own "Compile Error: "/"Syntax Error: " prefix)
 compile_error:
    mov rbx, rdi             ; rbx = message

    ; Print message to stderr
    xor rdx, rdx
.len_loop:
    cmp byte [rbx + rdx], 0
    je .len_done
    inc rdx
    jmp .len_loop
.len_done:
    mov rax, 1
    mov rdi, 2
    mov rsi, rbx
    syscall

    ; Print " at line "
    mov rax, 1
    mov rdi, 2
    lea rsi, [rel .at_line]
    mov rdx, .at_line_len
    syscall

    ; Print line number
    mov rdi, [line_num]
    call print_uint_to_stderr

    ; Print ", column "
    mov rax, 1
    mov rdi, 2
    lea rsi, [rel .at_col]
    mov rdx, .at_col_len
    syscall

    ; Print token start column (1-based).
    ; tok_str_ptr points at the token in the source (identifiers, numbers,
    ; operators). For string literals it points into the translation pool,
    ; so fall back to get_error_loc when it is outside the source buffer.
    mov rax, [tok_str_ptr]
    test rax, rax
    jz .col_fallback
    mov rcx, [src_ptr]
    cmp rax, rcx
    jb .col_fallback
    mov rdx, [src_len]
    add rdx, rcx
    cmp rax, rdx
    ja .col_fallback
    sub rax, rcx            ; token start offset in source
    mov rcx, [line_start_idx]
    sub rax, rcx            ; 0-based column
    inc rax                 ; 1-based
    jmp .col_ready
.col_fallback:
    call get_error_loc      ; rax = line, rdx = column
    mov rax, rdx
.col_ready:
    test rax, rax
    jg .col_positive
    mov rax, 1
.col_positive:
    mov r13, rax            ; save column for the caret line
    mov rdi, rax
    call print_uint_to_stderr

    ; Print newline
    mov rax, 1
    mov rdi, 2
    lea rsi, [rel .nl]
    mov rdx, 1
    syscall

    ; Print the offending source line (indented two spaces, capped at 120 cols)
    ; Skip the source line + caret entirely if the current line is empty
    ; (e.g. an error that fires on a NEWLINE/EOF at the end of the statement).
    mov rbx, [src_ptr]
    mov rcx, [line_start_idx]
    add rbx, rcx            ; rbx = start of current line
    xor r12, r12            ; r12 = line length
.line_loop:
    cmp r12, 120
    jae .line_done
    movzx rax, byte [rbx + r12]
    cmp al, 10
    je .line_done
    cmp al, 13
    je .line_done
    test al, al
    jz .line_done
    inc r12
    jmp .line_loop
.line_done:
    test r12, r12
    jz .exit
    mov rax, 1
    mov rdi, 2
    lea rsi, [rel .two_sp]
    mov rdx, 2
    syscall
    mov rax, 1
    mov rdi, 2
    mov rsi, rbx
    mov rdx, r12
    syscall
    mov rax, 1
    mov rdi, 2
    lea rsi, [rel .nl]
    mov rdx, 1
    syscall

    ; Print caret line: two spaces, (col-1) spaces, then '^'
    ; r13 = column (1-based) — must be stored by the header computation.
    ; Build "  <spaces>^\n" in err_caret_buf and write it once.
    lea rdi, [err_caret_buf]
    mov byte [rdi], ' '
    mov byte [rdi + 1], ' '
    add rdi, 2
    mov rcx, r13
    dec rcx                 ; spaces before caret = col-1
    cmp rcx, 120
    jbe .cap_ok
    mov rcx, 120
.cap_ok:
    mov r12, rcx            ; remember space count
.caret_space:
    test rcx, rcx
    jz .caret_space_done
    mov byte [rdi], ' '
    inc rdi
    dec rcx
    jmp .caret_space
.caret_space_done:
    mov byte [rdi], '^'
    inc rdi
    mov byte [rdi], 10
    inc rdi
    mov byte [rdi], 0
    ; write caret line: 2 + spaces + '^' + newline
    mov rax, 1
    mov rdi, 2
    lea rsi, [err_caret_buf]
    lea rdx, [r12 + 4]
    syscall

.exit:
    ; Exit with code 1
    mov rax, 60
    mov rdi, 1
    syscall

section .rodata
    .at_line db " at line "
    .at_line_len equ $ - .at_line
    .at_col db ", column "
    .at_col_len equ $ - .at_col
    .nl db 10
    .two_sp db "  "

section .text

; ======================================================
; print_uint_to_stderr: print unsigned integer in rdi to stderr (fd 2)
; ======================================================
print_uint_to_stderr:
    lea rsi, [print_num_buf + 15]
    mov r8, 10
    xor ecx, ecx
    test rdi, rdi
    jnz .num_loop
    mov byte [rsi], '0'
    mov ecx, 1
    jmp .num_print
.num_loop:
    xor edx, edx
    mov rax, rdi
    div r8
    add dl, '0'
    mov [rsi], dl
    dec rsi
    inc ecx
    mov rdi, rax
    test rdi, rdi
    jnz .num_loop
    inc rsi
.num_print:
    mov rax, 1
    mov rdi, 2
    mov rdx, rcx
    syscall
    ret

section .text

; ======================================================
; strcpy_z: copy null-terminated string from rsi to rdi.
; Returns: rdi = pointer to the terminating null (so callers can append).
; ======================================================
strcpy_z:
.str_cp:
    cmp byte [rsi], 0
    je .str_done
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    jmp .str_cp
.str_done:
    mov byte [rdi], 0
    ret

; ======================================================
; undef_error: report "Undefined variable '<name>'".
; The offending identifier must still be the current token
; (tok_str_ptr / tok_str_len). Never returns.
; ======================================================
undef_error:
    lea rdi, [error_msg_buf]
    lea rsi, [err_undef]
    call strcpy_z
    mov byte [rdi], ' '
    inc rdi
    mov byte [rdi], 39      ; opening '
    inc rdi
    mov rsi, [tok_str_ptr]
    mov rcx, [tok_str_len]
    cmp rcx, 64
    jbe .tok_len_ok
    mov rcx, 64
.tok_len_ok:
    test rcx, rcx
    jz .tok_cp_done
.tok_cp:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jnz .tok_cp
.tok_cp_done:
    mov byte [rdi], 39      ; closing '
    inc rdi
    mov byte [rdi], 0
    lea rdi, [error_msg_buf]
    jmp compile_error

; ======================================================
; type_name_str: map a type id to a display name.
; rdi = type id → rax = pointer to null-terminated string.
; ======================================================
type_name_str:
    cmp rdi, TYPE_INT
    je .t_int
    cmp rdi, TYPE_FLOAT
    je .t_float
    cmp rdi, TYPE_BOOL
    je .t_bool
    cmp rdi, TYPE_STR
    je .t_str
    cmp rdi, TYPE_SEQ
    je .t_seq
    cmp rdi, TYPE_DICT
    je .t_dict
    cmp rdi, TYPE_CHAR
    je .t_char
    cmp rdi, TYPE_BYTE
    je .t_byte
    cmp rdi, TYPE_FILE
    je .t_file
    cmp rdi, TYPE_TUP
    je .t_tuple
    cmp rdi, TYPE_COMPLEX
    je .t_struct
    cmp rdi, TYPE_TUP
    ja .t_registered
    jmp .t_value
.t_int:    lea rax, [str_t_int]
    ret
.t_float:  lea rax, [str_t_float]
    ret
.t_bool:   lea rax, [str_t_bool]
    ret
.t_str:    lea rax, [str_t_str]
    ret
.t_seq:    lea rax, [str_t_seq]
    ret
.t_dict:   lea rax, [str_t_dict]
    ret
.t_char:   lea rax, [str_t_char]
    ret
.t_byte:   lea rax, [str_t_byte]
    ret
.t_file:   lea rax, [str_t_file]
    ret
.t_tuple:  lea rax, [str_t_tuple]
    ret
.t_struct: lea rax, [str_t_struct]
    ret
.t_registered:
    ; User-defined type id: look up the registered name.
    ; type_table entry: kind@0, size@4, name_ptr@8, name_len@16, aux@24.
    extern type_count
    extern type_table
    cmp rdi, [type_count]
    jae .t_value
    imul rdi, rdi, 32
    mov rax, [type_table + rdi + 8]   ; name_ptr
    test rax, rax
    jz .t_value
    ret
.t_value:  lea rax, [str_t_value]
    ret

; ======================================================
; unknown_method_error: report "Unknown method '<name>' on type <type>".
; method_buf / method_len = method name; r13 = type id. Never returns.
; ======================================================
unknown_method_error:
    lea r14, [err_unknown_method_on]
    jmp unknown_member_error

; ======================================================
; unknown_field_error: report "Unknown field '<name>' on type <type>".
; method_buf / method_len = field name; r13 = type id. Never returns.
; ======================================================
unknown_field_error:
    lea r14, [err_unknown_field]
    jmp unknown_member_error

; ======================================================
; unknown_member_error: shared body for the two above.
; r14 = base message, r13 = type id, method_buf / method_len = member name.
; ======================================================
unknown_member_error:
    lea rdi, [error_msg_buf]
    mov rsi, r14
    call strcpy_z
    mov byte [rdi], ' '
    inc rdi
    mov byte [rdi], 39      ; opening '
    inc rdi
    lea rsi, [method_buf]
    mov rcx, [method_len]
    cmp rcx, 64
    jbe .m_len_ok
    mov rcx, 64
.m_len_ok:
    test rcx, rcx
    jz .m_cp_done
.m_cp:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jnz .m_cp
.m_cp_done:
    mov byte [rdi], 39      ; closing '
    inc rdi
    mov byte [rdi], 0
    ; append " on type <name>"
    lea rsi, [str_on_type]
    call strcpy_z
    mov r12, rdi            ; save buffer end
    mov rdi, r13
    call type_name_str      ; rax = type name
    mov rsi, rax
    mov rdi, r12
    call strcpy_z
    lea rdi, [error_msg_buf]
    jmp compile_error

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
; parse_proto_call: parse a protocol call
; Expects current_token = proto name IDENT (after '@' was consumed).
; Emits IR_CALL_ARG records for each argument (register args immediately,
; stack args right-to-left after saving caller locals), then IR_CALL.
; Returns: rax = lo return vreg (0 = void), rdx = type,
;          [call_result_hi] = hi return vreg (0 = none)
; ======================================================
parse_proto_call:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov eax, [current_token]
    cmp eax, TOK_IDENT
    jne .pc_syntax_err
    mov rdi, [tok_str_ptr]
    mov rsi, [tok_str_len]
    call proto_resolve_call
    cmp rax, -1
    je .pc_undef
    mov r15, rax ; proto_id

; Shared call-parsing body. Entry: r15 = proto_id (resolved), current token
; = the proto name IDENT (advance → '('). Used by @name calls and qualified
; mod.name(...) calls. Expects rbx/r12-r15 pushed on entry (popped on ret).
; Referenced as parse_proto_call.pc_resolved.
.pc_resolved:
    call advance ; consume name → '('
    mov edi, TOK_LPAREN
    call expect ; consume '('

    ; Parse arguments left-to-right (side effects evaluate in order).
    ; Register args (0-5) emit IR_CALL_ARG immediately; stack args are
    ; deferred and emitted right-to-left just before IR_CALL so the callee
    ; sees param 7 at [rsp+8], param 8 at [rsp+16], etc.
    xor r12d, r12d ; arg count
.pc_arg_loop:
    mov eax, [current_token]
    cmp eax, TOK_RPAREN
    je .pc_args_done
    cmp r12d, 65
    jae .pc_arg_err
    call parse_expr ; rax = vreg, rdx = type
    mov [call_arg_vregs + r12*2], ax
    mov [call_arg_types + r12*4], edx
    cmp r12d, 6
    jae .pc_arg_defer
    ; Register argument: emit IR_CALL_ARG now
    push rax
    push rdx
    mov rdi, IR_CALL_ARG
    xor rsi, rsi
    xor rdx, rdx
    mov rcx, [rsp + 8] ; src1 = arg vreg
    xor r8, r8
    mov r9d, r12d      ; imm = arg index
    xor r10, r10
    call emit_ir
    add rsp, 16
    jmp .pc_arg_next
.pc_arg_defer:
    ; Stack argument: defer (vreg kept in call_arg_vregs)
.pc_arg_next:
    inc r12d
    mov eax, [current_token]
    cmp eax, TOK_COMMA
    jne .pc_args_done
    call advance
    jmp .pc_arg_loop
.pc_args_done:
    mov edi, TOK_RPAREN
    call expect ; consume ')'

    ; Validate argument count against the protocol signature
    mov rdi, r15
    call proto_get_param_count
    cmp rax, r12
    jne .pc_arg_count

    ; Save caller's in-scope local vars before the call.  Protocol bodies
    ; reuse the same absolute var slots, so a callee can overwrite this
    ; body's slots (recursion / mutual calls).  Saves happen before the
    ; stack-arg pushes so the callee's [rsp+8k] param reads stay correct.
    cmp dword [block_nesting], 0
    je .pc_no_saves
    xor ebx, ebx
.pc_save_loop:
    cmp ebx, [sym_count]
    jae .pc_saves_done
    mov rdi, rbx
    push rbx
    call sym_get_scope
    pop rbx
    cmp rax, SCOPE_GLOBAL
    je .pc_save_next
    mov rdi, rbx
    push rbx
    call sym_get_offset
    pop rbx
    push rbx
    push rax
    mov rdi, IR_SAVE_LOCAL_VAR
    xor rsi, rsi
    xor rdx, rdx
    xor rcx, rcx
    xor r8, r8
    pop r9 ; imm = var absolute offset
    xor r10, r10
    call emit_ir
    pop rbx
.pc_save_next:
    inc ebx
    jmp .pc_save_loop
.pc_saves_done:
.pc_no_saves:

    ; Emit stack-argument pushes right-to-left (params 7..65)
    mov r13d, r12d
.pc_stack_loop:
    cmp r13d, 6
    jbe .pc_stack_done
    dec r13d
    movzx eax, word [call_arg_vregs + r13*2]
    push rax
    push r13
    mov rdi, IR_CALL_ARG
    xor rsi, rsi
    xor rdx, rdx
    mov rcx, [rsp + 8] ; src1 = arg vreg
    xor r8, r8
    mov r9d, r13d      ; imm = arg index
    xor r10, r10
    call emit_ir
    add rsp, 16
    jmp .pc_stack_loop
.pc_stack_done:

    ; Allocate return vregs
    mov rdi, r15
    call proto_get_ret_count
    mov r14, rax ; ret count
    cmp r14, 2
    ja .pc_arity
    xor ebx, ebx ; lo vreg
    test r14, r14
    jz .pc_no_lo
    call alloc_vreg
    mov rbx, rax
.pc_no_lo:
    xor r13d, r13d ; hi vreg
    cmp r14, 2
    jne .pc_no_hi
    call alloc_vreg
    mov r13, rax
.pc_no_hi:
    ; IR_CALL(dst = lo, src2 = hi, imm = proto_id, aux = arg_count)
    push rbx
    push r13
    push r14
    mov rdi, IR_CALL
    xor rsi, rsi
    mov rdx, rbx
    xor rcx, rcx
    mov r8, r13
    mov r9, r15
    mov r10, r12
    call emit_ir
    pop r14
    pop r13
    pop rbx

    ; Restore caller's local vars (reverse order — LIFO)
    ; NOTE: rbx holds the lo return vreg here — do NOT clobber it.
    cmp dword [block_nesting], 0
    je .pc_no_restores
    push rbx
    mov ebx, [sym_count]
    jz .pc_restores_pop
.pc_restore_loop:
    dec ebx
    mov rdi, rbx
    push rbx
    call sym_get_scope
    pop rbx
    cmp rax, SCOPE_GLOBAL
    je .pc_restore_next
    mov rdi, rbx
    push rbx
    call sym_get_offset
    pop rbx
    push rbx
    push rax
    mov rdi, IR_RESTORE_LOCAL_VAR
    xor rsi, rsi
    xor rdx, rdx
    xor rcx, rcx
    xor r8, r8
    pop r9
    xor r10, r10
    call emit_ir
    pop rbx
.pc_restore_next:
    test ebx, ebx
    jnz .pc_restore_loop
.pc_restores_pop:
    pop rbx
.pc_no_restores:

    ; Record hi return vreg for multi-target mutation
    mov [call_result_hi], r13d

    ; Return lo vreg + type
    xor rdx, rdx
    test rbx, rbx
    jz .pc_type_set
    mov rdi, r15 ; proto_id
    xor esi, esi ; return index 0 (lo)
    call proto_get_ret_conc_type ; eax = concrete return type
    mov rdx, rax
.pc_type_set:
    mov rax, rbx ; lo return vreg (recompute after type lookup clobbered rax)
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.pc_syntax_err:
    mov rdi, err_syntax
    jmp compile_error
.pc_undef:
    mov rdi, err_unknown_proto
    jmp compile_error
.pc_arg_err:
    mov rdi, err_arity
    jmp compile_error
.pc_arg_count:
    mov rdi, err_proto_arg_count
    jmp compile_error
.pc_arity:
    mov rdi, err_arity
    jmp compile_error

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
    cmp eax, TOK_TYPE
    je .pp_method_name
    jmp .pp_syntax_err

.pp_method_name:

    ; Check if this is a struct field access (base vreg holds a pointer to a
    ; struct slot; vreg_type_map carries the struct type id).
    movzx eax, word [vreg_type_map + r12 * 4]
    test eax, eax
    jz .pp_not_struct_field
    push rax
    mov rdi, rax
    call type_get_kind
    mov rcx, rax
    pop rax
    cmp rcx, TYPE_COMPLEX
    jne .pp_not_struct_field
    ; Look up field by name
    ; Stash the field name in method_buf first — it is needed if the
    ; lookup misses (advance below clobbers tok_str_ptr).
    ; NOTE: must not clobber rax here — it holds the struct type id, and
    ; the copy loop below writes al.
    push rax                ; save struct type id
    mov rsi, [tok_str_ptr]
    mov rcx, [tok_str_len]
    cmp rcx, 31
    jle .pp_fnlen_ok
    mov rcx, 31
.pp_fnlen_ok:
    mov [method_len], rcx
    lea rdi, [method_buf]
    test rcx, rcx
    jz .pp_fcopy_done
.pp_fcopy:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jnz .pp_fcopy
.pp_fcopy_done:
    lea rdi, [method_buf]
    add rdi, [method_len]
    mov byte [rdi], 0
    pop rax                 ; restore struct type id
    mov rdi, rax            ; struct type_id
    mov rsi, [tok_str_ptr]  ; field name ptr
    mov rdx, [tok_str_len]  ; field name len
    push r12                ; save base vreg
    call type_struct_find_field
    push rax                ; save offset
    push rcx                ; save field type
    call advance            ; consume field name
    pop r13                 ; r13 = field type
    pop rax                 ; rax = field offset
    cmp rax, -1
    je .pp_struct_miss
    ; rax = field offset, r13 = field_type_id
    push rax                ; save offset
    call alloc_vreg
    pop r9                  ; r9 = field offset
    mov rdx, rax            ; dst vreg
    pop rcx                 ; src1 = base vreg (pointer)
    push rcx                ; preserve base across type_get_kind
    push rdx                ; save result vreg
    push r9                 ; preserve offset across type_get_kind
    push r13                ; save field type
    mov rdi, r13
    call type_get_kind
    mov rbx, rax
    pop r13
    pop r9
    pop rdx
    pop rcx
    ; Nested struct field → the result is a pointer into the parent body:
    ; dst = base + offset (IR_LEA_FIELD). Scalar field → dst = [base + offset].
    cmp rbx, TYPE_COMPLEX
    jne .pp_field_scalar
    mov rdi, IR_LEA_FIELD
    mov rsi, r13            ; type
    xor r8, r8
    xor r10, r10
    push rdx
    call emit_ir
    pop rdx
    mov [vreg_type_map + rdx * 4], r13d
    mov r12, rdx
    jmp .pp_loop
.pp_field_scalar:
    mov rdi, IR_LOAD_FIELD
    mov rsi, r13            ; type
    xor r8, r8
    xor r10, r10
    push rdx
    call emit_ir
    pop r12                 ; r12 = result vreg
    jmp .pp_loop
.pp_struct_miss:
    pop r12                 ; restore base vreg
    ; r12 = base vreg → struct type id is in vreg_type_map[r12*4];
    ; method_buf holds the field name.
    movzx r13, word [vreg_type_map + r12 * 4]
    jmp unknown_field_error
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
    cmp r13, TYPE_FILE
    je .pp_file_dispatch
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
    lea rdi, [str_zero]
    call ident_is
    test rax,rax
    jnz .pp_int_is_zero
    lea rdi, [str_positive]
    call ident_is
    test rax,rax
    jnz .pp_int_is_pos
    lea rdi, [str_negative]
    call ident_is
    test rax,rax
    jnz .pp_int_is_neg
    lea rdi, [str_even]
    call ident_is
    test rax,rax
    jnz .pp_int_is_even
    lea rdi, [str_odd]
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
    lea rdi, [str_gcd]
    call ident_is
    test rax,rax
    jnz .pp_int_gcd
    lea rdi, [str_lcm]
    call ident_is
    test rax,rax
    jnz .pp_int_lcm
    lea rdi, [str_to_bin]
    call ident_is
    test rax,rax
    jnz .pp_int_to_bin
    lea rdi, [str_to_hex]
    call ident_is
    test rax,rax
    jnz .pp_int_to_hex
    lea rdi, [str_to_oct]
    call ident_is
    test rax,rax
    jnz .pp_int_to_oct
    lea rdi, [str_pow]
    call ident_is
    test rax,rax
    jnz .pp_int_pow
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

.pp_int_gcd:
    call parse_expr
    mov r14, rax
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_GCD
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r12
    mov r8, r14
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

.pp_int_lcm:
    call parse_expr
    mov r14, rax
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_LCM
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r12
    mov r8, r14
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

.pp_int_to_bin:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_TO_BIN_STR
    mov rsi, TYPE_STR
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_STR
    jmp .pp_loop

.pp_int_to_hex:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_TO_HEX_STR
    mov rsi, TYPE_STR
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_STR
    jmp .pp_loop

.pp_int_to_oct:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_TO_OCT_STR
    mov rsi, TYPE_STR
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_STR
    jmp .pp_loop

.pp_int_pow:
    call parse_expr
    mov r14, rax
    cmp rdx, TYPE_INT
    jne .pp_pow_type_err
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_POW_I
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r12
    mov r8, r14
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

.pp_pow_type_err:
    mov rdi, err_type_mismatch
    jmp compile_error

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
    lea rdi, [str_zero]
    call ident_is
    test rax,rax
    jnz .pp_float_is_zero
    lea rdi, [str_positive]
    call ident_is
    test rax,rax
    jnz .pp_float_is_pos
    lea rdi, [str_negative]
    call ident_is
    test rax,rax
    jnz .pp_float_is_neg
    lea rdi, [str_nan]
    call ident_is
    test rax,rax
    jnz .pp_float_is_nan
    lea rdi, [str_inf]
    call ident_is
    test rax,rax
    jnz .pp_float_is_inf
    lea rdi, [str_finite]
    call ident_is
    test rax,rax
    jnz .pp_float_is_finite
    lea rdi, [str_sin]
    call ident_is
    test rax,rax
    jnz .pp_float_sin
    lea rdi, [str_cos]
    call ident_is
    test rax,rax
    jnz .pp_float_cos
    lea rdi, [str_tan]
    call ident_is
    test rax,rax
    jnz .pp_float_tan
    lea rdi, [str_pow]
    call ident_is
    test rax,rax
    jnz .pp_float_pow
    lea rdi, [str_cbrt]
    call ident_is
    test rax,rax
    jnz .pp_float_cbrt
    lea rdi, [str_signum]
    call ident_is
    test rax,rax
    jnz .pp_float_signum
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

.pp_float_sin:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_SIN
    mov rsi, TYPE_FLOAT
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

.pp_float_cos:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_COS
    mov rsi, TYPE_FLOAT
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

.pp_float_tan:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_TAN
    mov rsi, TYPE_FLOAT
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

.pp_float_pow:
    call parse_expr
    mov r14, rax
    cmp rdx, TYPE_FLOAT
    jne .pp_pow_type_err
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_POW_F
    mov rsi, TYPE_FLOAT
    mov rdx, rbx
    mov rcx, r12
    mov r8, r14
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

.pp_float_cbrt:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_CBRT
    mov rsi, TYPE_FLOAT
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

.pp_float_signum:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_SIGNUM_F
    mov rsi, TYPE_FLOAT
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
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
    lea rdi, [str_str_m]
    call ident_is
    test rax,rax
    jnz .pp_bool_str
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

.pp_bool_str:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_BTOS
    mov rsi, TYPE_STR
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_STR
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
    lea rdi, [str_str_m]
    call ident_is
    test rax,rax
    jnz .pp_char_str
    lea rdi, [str_int_m]
    call ident_is
    test rax,rax
    jnz .pp_char_to_int
    lea rdi, [str_byte_m]
    call ident_is
    test rax,rax
    jnz .pp_char_to_byte
    lea rdi, [str_alpha]
    call ident_is
    test rax,rax
    jnz .pp_char_is_alpha
    lea rdi, [str_digit]
    call ident_is
    test rax,rax
    jnz .pp_char_to_digit
    lea rdi, [str_alnum_m]
    call ident_is
    test rax,rax
    jnz .pp_char_is_alnum
    lea rdi, [str_whitespace]
    call ident_is
    test rax,rax
    jnz .pp_char_is_space
    lea rdi, [str_upper]
    call ident_is
    test rax,rax
    jnz .pp_char_to_upper
    lea rdi, [str_lower]
    call ident_is
    test rax,rax
    jnz .pp_char_to_lower
    lea rdi, [str_punct_m]
    call ident_is
    test rax,rax
    jnz .pp_char_is_punct
    lea rdi, [str_printable_m]
    call ident_is
    test rax,rax
    jnz .pp_char_is_print
    lea rdi, [str_ascii_m]
    call ident_is
    test rax,rax
    jnz .pp_char_is_ascii
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

.pp_char_str:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_CTOS
    mov rsi, TYPE_STR
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_STR
    jmp .pp_loop

; ─────────── BYTE methods ──────────────────────────────
.pp_byte_dispatch:
    lea rdi, [str_popcount]
    call ident_is
    test rax,rax
    jnz .pp_byte_popcount
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
    lea rdi, [str_str_m]
    call ident_is
    test rax,rax
    jnz .pp_byte_str
    lea rdi, [str_int_m]
    call ident_is
    test rax,rax
    jnz .pp_byte_to_int
    lea rdi, [str_char_m]
    call ident_is
    test rax,rax
    jnz .pp_byte_to_char
    lea rdi, [str_bit]
    call ident_is
    test rax,rax
    jnz .pp_byte_bit
    lea rdi, [str_rotate_left]
    call ident_is
    test rax,rax
    jnz .pp_byte_rol
    lea rdi, [str_rotate_right]
    call ident_is
    test rax,rax
    jnz .pp_byte_ror
    lea rdi, [str_hex_m]
    call ident_is
    test rax,rax
    jnz .pp_byte_hex
    lea rdi, [str_bin_m]
    call ident_is
    test rax,rax
    jnz .pp_byte_bin
    lea rdi, [str_zero]
    call ident_is
    test rax,rax
    jnz .pp_byte_is_zero
    lea rdi, [str_ascii_m]
    call ident_is
    test rax,rax
    jnz .pp_byte_is_ascii
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

.pp_byte_str:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_CTOS
    mov rsi, TYPE_STR
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_STR
    jmp .pp_loop

.pp_byte_bit:
    call parse_expr
    mov r14, rax
    cmp rdx, TYPE_INT
    jne .pp_pow_type_err
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_BYTE_BIT
    mov rsi, TYPE_BOOL
    mov rdx, rbx
    mov rcx, r12
    mov r8, r14
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_BOOL
    jmp .pp_loop

.pp_byte_rol:
    call parse_expr
    mov r14, rax
    cmp rdx, TYPE_INT
    jne .pp_pow_type_err
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_BYTE_ROL
    mov rsi, TYPE_BYTE
    mov rdx, rbx
    mov rcx, r12
    mov r8, r14
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

.pp_byte_ror:
    call parse_expr
    mov r14, rax
    cmp rdx, TYPE_INT
    jne .pp_pow_type_err
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_BYTE_ROR
    mov rsi, TYPE_BYTE
    mov rdx, rbx
    mov rcx, r12
    mov r8, r14
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    jmp .pp_loop

.pp_byte_hex:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_BYTE_HEX
    mov rsi, TYPE_STR
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_STR
    jmp .pp_loop

.pp_byte_bin:
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_BYTE_BIN
    mov rsi, TYPE_STR
    mov rdx, rbx
    mov rcx, r12
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_STR
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
    lea rdi, [str_index]
    call ident_is
    test rax,rax
    jnz .pp_seq_index_of
    lea rdi, [str_index_of]
    call ident_is
    test rax,rax
    jnz .pp_seq_index_of
    lea rdi, [str_count]
    call ident_is
    test rax,rax
    jnz .pp_seq_count_of
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

; ─────────── File methods (design.md §15.4) ───────────
.pp_file_dispatch:
    lea rdi, [str_read]
    call ident_is
    test rax,rax
    jnz .pp_file_read
    lea rdi, [str_read_line]
    call ident_is
    test rax,rax
    jnz .pp_file_read_line
    lea rdi, [str_read_bytes]
    call ident_is
    test rax,rax
    jnz .pp_file_read_bytes
    lea rdi, [str_read_all_bytes]
    call ident_is
    test rax,rax
    jnz .pp_file_read_all_bytes
    lea rdi, [str_lines_m]
    call ident_is
    test rax,rax
    jnz .pp_file_lines
    lea rdi, [str_write_m]
    call ident_is
    test rax,rax
    jnz .pp_file_write
    lea rdi, [str_writeln]
    call ident_is
    test rax,rax
    jnz .pp_file_writeln
    lea rdi, [str_write_bytes]
    call ident_is
    test rax,rax
    jnz .pp_file_write_bytes
    lea rdi, [str_seek]
    call ident_is
    test rax,rax
    jnz .pp_file_seek
    lea rdi, [str_seek_end]
    call ident_is
    test rax,rax
    jnz .pp_file_seek_end
    lea rdi, [str_pos]
    call ident_is
    test rax,rax
    jnz .pp_file_pos
    lea rdi, [str_size]
    call ident_is
    test rax,rax
    jnz .pp_file_size
    lea rdi, [str_is_eof]
    call ident_is
    test rax,rax
    jnz .pp_file_is_eof
    lea rdi, [str_flush]
    call ident_is
    test rax,rax
    jnz .pp_file_flush
    lea rdi, [str_path]
    call ident_is
    test rax,rax
    jnz .pp_file_path
    jmp .pp_method_err

.pp_file_read:
    ; .read() → str (remaining file)
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_FILE_READ
    mov rsi, TYPE_STR
    mov rdx, rbx
    mov rcx, r12    ; src1 = handle
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_STR
    jmp .pp_loop

.pp_file_read_line:
    ; .read_line() → str (includes \n, empty at EOF)
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_FILE_READ_LINE
    mov rsi, TYPE_STR
    mov rdx, rbx
    mov rcx, r12    ; src1 = handle
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_STR
    jmp .pp_loop

.pp_file_read_bytes:
    ; .read_bytes(n) → seq[byte]
    call parse_expr ; n vreg
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop rdx
    pop r14
    cmp rdx, TYPE_INT
    jne .pp_file_type_err
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_FILE_READ_BYTES
    mov rsi, TYPE_SEQ
    mov rdx, rbx
    mov rcx, r12    ; src1 = handle
    mov r8, r14     ; src2 = n
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_SEQ
    mov dword [vreg_elem_types + r12 * 4], TYPE_BYTE
    jmp .pp_loop

.pp_file_read_all_bytes:
    ; .read_all_bytes() → seq[byte]
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_FILE_READ_ALL_BYTES
    mov rsi, TYPE_SEQ
    mov rdx, rbx
    mov rcx, r12    ; src1 = handle
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_SEQ
    mov dword [vreg_elem_types + r12 * 4], TYPE_BYTE
    jmp .pp_loop

.pp_file_lines:
    ; .lines() → seq[str]
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_FILE_LINES
    mov rsi, TYPE_SEQ
    mov rdx, rbx
    mov rcx, r12    ; src1 = handle
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_SEQ
    mov dword [vreg_elem_types + r12 * 4], TYPE_STR
    jmp .pp_loop

.pp_file_write:
    ; .write(s) — void
    call parse_expr ; s vreg
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop rdx
    pop r14
    cmp rdx, TYPE_STR
    jne .pp_file_type_err
    mov rdi, IR_FILE_WRITE
    mov rsi, TYPE_FILE
    xor rdx, rdx     ; dst = 0 (void)
    mov rcx, r12     ; src1 = handle
    mov r8, r14      ; src2 = s
    xor r9,r9
    xor r10,r10
    call emit_ir
    jmp .pp_loop

.pp_file_writeln:
    ; .writeln(s) — void
    call parse_expr ; s vreg
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop rdx
    pop r14
    cmp rdx, TYPE_STR
    jne .pp_file_type_err
    mov rdi, IR_FILE_WRITELN
    mov rsi, TYPE_FILE
    xor rdx, rdx     ; dst = 0 (void)
    mov rcx, r12     ; src1 = handle
    mov r8, r14      ; src2 = s
    xor r9,r9
    xor r10,r10
    call emit_ir
    jmp .pp_loop

.pp_file_write_bytes:
    ; .write_bytes(b) — void
    call parse_expr ; b vreg
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop rdx
    pop r14
    cmp rdx, TYPE_SEQ
    jne .pp_file_type_err
    mov rdi, IR_FILE_WRITE_BYTES
    mov rsi, TYPE_FILE
    xor rdx, rdx     ; dst = 0 (void)
    mov rcx, r12     ; src1 = handle
    mov r8, r14      ; src2 = b
    xor r9,r9
    xor r10,r10
    call emit_ir
    jmp .pp_loop

.pp_file_seek:
    ; .seek(pos) — void
    call parse_expr ; pos vreg
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop rdx
    pop r14
    cmp rdx, TYPE_INT
    jne .pp_file_type_err
    mov rdi, IR_FILE_SEEK
    mov rsi, TYPE_FILE
    xor rdx, rdx     ; dst = 0 (void)
    mov rcx, r12     ; src1 = handle
    mov r8, r14      ; src2 = pos
    xor r9,r9
    xor r10,r10
    call emit_ir
    jmp .pp_loop

.pp_file_seek_end:
    ; .seek_end(n) — void (n bytes before end; default 0)
    mov r14, r12 ; save handle vreg (arg parse may use r12)
    mov eax, [current_token]
    cmp eax, TOK_RPAREN
    je .pp_seek_end_default
    call parse_expr ; n vreg
    push rax
    push rdx
    mov edi, TOK_RPAREN
    call expect
    pop rdx
    pop r15
    cmp rdx, TYPE_INT
    jne .pp_file_type_err
    jmp .pp_seek_end_emit
.pp_seek_end_default:
    mov edi, TOK_RPAREN
    call expect
    ; default offset 0: emit IR_LOAD_IMM 0
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
    pop r15
.pp_seek_end_emit:
    mov r12, r14 ; restore handle vreg
    mov rdi, IR_FILE_SEEK_END
    mov rsi, TYPE_FILE
    xor rdx, rdx
    mov rcx, r12     ; src1 = handle
    mov r8, r15      ; src2 = n
    xor r9, r9
    xor r10, r10
    call emit_ir
    jmp .pp_loop

.pp_file_pos:
    ; .pos() → int
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_FILE_POS
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r12    ; src1 = handle
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_INT
    jmp .pp_loop

.pp_file_size:
    ; .size() → int
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_FILE_SIZE
    mov rsi, TYPE_INT
    mov rdx, rbx
    mov rcx, r12    ; src1 = handle
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_INT
    jmp .pp_loop

.pp_file_is_eof:
    ; .is_eof() → bool
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_FILE_IS_EOF
    mov rsi, TYPE_BOOL
    mov rdx, rbx
    mov rcx, r12    ; src1 = handle
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_BOOL
    jmp .pp_loop

.pp_file_flush:
    ; .flush() — void
    mov edi, TOK_RPAREN
    call expect
    mov rdi, IR_FILE_FLUSH
    mov rsi, TYPE_FILE
    xor rdx, rdx
    xor r8, r8
    xor r9, r9
    xor r10, r10
    call emit_ir
    jmp .pp_loop

.pp_file_path:
    ; .path → str (no parentheses in Python; here used as path())
    mov edi, TOK_RPAREN
    call expect
    call alloc_vreg
    mov rbx, rax
    mov rdi, IR_FILE_PATH
    mov rsi, TYPE_STR
    mov rdx, rbx
    mov rcx, r12    ; src1 = handle
    xor r8,r8
    xor r9,r9
    xor r10,r10
    call emit_ir
    mov r12, rbx
    mov r13, TYPE_STR
    jmp .pp_loop

.pp_file_type_err:
    mov rdi, err_type_mismatch
    jmp compile_error

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
    ; Determine element type: seq[T] → T (from vreg_elem_types); default INT
    mov eax, [vreg_elem_types + r12 * 4]
    test eax, eax
    jnz .pp_bracket_seq_elem_ok
    mov eax, TYPE_INT
.pp_bracket_seq_elem_ok:
    mov r15d, eax ; element type
    mov rdi, IR_SEQ_LOAD
    mov rsi, r15 ; element type
    mov rdx, [rsp] ; dst
    ; rcx = seq vreg (src1)
    mov r8, r14 ; index vreg (src2)
    mov r9, SEQ_ELEMENT_SIZE ; element size
    xor r10, r10
    call emit_ir
    pop r12 ; result vreg
    mov r13, r15
    ; record element type on the result vreg for further indexing
    mov [vreg_elem_types + r12 * 4], r15d
    jmp .pp_loop
.pp_bracket_dict:
    call alloc_vreg
    push rax
    ; Determine value type: dict[T] → T (from vreg_elem_types); default INT
    mov eax, [vreg_elem_types + r12 * 4]
    test eax, eax
    jnz .pp_bracket_dict_val_ok
    mov eax, TYPE_INT
.pp_bracket_dict_val_ok:
    mov r15d, eax ; value type
    mov rdi, IR_DICT_LOAD
    mov rsi, r15 ; value type
    mov rdx, [rsp] ; dst
    ; rcx = dict vreg (src1)
    mov r8, r14 ; key vreg (src2)
    xor r9, r9
    xor r10, r10
    call emit_ir
    pop r12 ; result vreg
    mov r13, r15
    ; record value type on the result vreg for further indexing
    mov [vreg_elem_types + r12 * 4], r15d
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
    jmp unknown_method_error

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

; ─────────────────────────────────────────────────────────────
; parse_qualified_expr — evaluate a qualified module reference as an
; expression (design.md §17.2): `mod.name` (global read) or `mod.name(...)`
; (protocol call). Entry: r15 = module id, current token = member IDENT
; (the `mod.` prefix already consumed). Returns rax = vreg, rdx = type.
parse_qualified_expr:
    call save_ident
    call lexer_peek_token
    cmp eax, TOK_LPAREN
    je .q_expr_call
    ; --- Qualified global read: mod.name ---
    mov rdi, ident_buf
    mov rsi, [ident_len]
    mov edx, r15d
    call sym_lookup_module
    cmp rax, -1
    je .q_expr_undef
    mov r14, rax ; sym idx
    ; Private members are visible only inside the defining module.
    mov rdi, r14
    call sym_is_private
    test rax, rax
    jz .q_expr_read
    mov eax, [current_module]
    cmp eax, r15d
    je .q_expr_read
    jmp .q_expr_private
.q_expr_read:
    call advance ; consume member name
    push r14 ; sym_idx
    mov rdi, [rsp]
    call sym_is_init
    test rax, rax
    jz .q_expr_uninit
    mov rdi, [rsp]
    call sym_get_type
    push rax ; type
    call alloc_vreg
    push rax ; vreg
    mov rdi, [rsp + 16] ; sym_idx
    call sym_get_offset
    mov r9, rax ; offset
    ; Struct variables hold a pointer to their slot: emit LEA_VAR.
    mov rdi, [rsp + 8] ; type
    push rdi
    call type_get_kind
    mov rcx, rax
    pop rdi
    cmp rcx, TYPE_COMPLEX
    je .q_expr_struct
    mov rdi, IR_LOAD_VAR
    mov rsi, [rsp + 8] ; type
    mov rdx, [rsp] ; dst
    xor rcx, rcx
    xor r8, r8
    xor r10, r10
    call emit_ir
    jmp .q_expr_ready
.q_expr_struct:
    mov rdi, IR_LEA_VAR
    mov rsi, [rsp + 8] ; type
    mov rdx, [rsp] ; dst
    xor rcx, rcx
    xor r8, r8
    xor r10, r10
    call emit_ir
.q_expr_ready:
    pop rax ; vreg
    pop rdx ; type
    ; Store type_id in vreg_type_map for struct field access
    push rax
    push rdx
    mov [vreg_type_map + rax * 4], edx
    ; Store container element type for bracket indexing
    push rbx
    push rcx
    push rax
    mov rdi, [rsp + 40] ; sym_idx
    call sym_get_elem_type
    mov rcx, rax
    pop rax
    mov [vreg_elem_types + rax * 4], ecx
    pop rcx
    pop rbx
    pop rdx
    pop rax
    add rsp, 8 ; clean up sym_idx
    ret
.q_expr_call:
    ; --- Qualified protocol call: mod.name(...) ---
    mov rdi, ident_buf
    mov rsi, [ident_len]
    mov edx, r15d
    call proto_lookup_module
    cmp rax, -1
    je .q_expr_undef
    mov r14, rax ; proto id
    ; Private protos are callable only inside the defining module.
    mov rdi, r14
    call proto_get_private
    test rax, rax
    jz .q_expr_call_ok
    mov eax, [current_module]
    cmp eax, r15d
    je .q_expr_call_ok
    jmp .q_expr_private
.q_expr_call_ok:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r15, r14 ; proto id
    jmp parse_proto_call.pc_resolved
.q_expr_undef:
    jmp undef_error
.q_expr_uninit:
    mov rdi, err_uninit
    jmp compile_error
.q_expr_private:
    mov rdi, err_private_member
    jmp compile_error

; ─────────────────────────────────────────────────────────────
; parse_qualified_mutation — `:mod.name = expr`. Entry: r15 = module id,
; current token = member IDENT (the `mod.` prefix already consumed).
parse_qualified_mutation:
    call save_ident
    mov rdi, ident_buf
    mov rsi, [ident_len]
    mov edx, r15d
    call sym_lookup_module
    cmp rax, -1
    je .q_mut_undef
    mov r14, rax ; sym idx
    ; Private members are visible only inside the defining module.
    mov rdi, r14
    call sym_is_private
    test rax, rax
    jz .q_mut_ok
    mov eax, [current_module]
    cmp eax, r15d
    jne .q_mut_private
.q_mut_ok:
    mov rdi, r14
    mov rsi, 1
    call sym_set_mutable
    call advance ; consume member name
    mov edi, TOK_ASSIGN
    call expect
    call parse_expr ; rax = vreg, rdx = type
    mov rdi, r14
    push rax
    push rdx
    call sym_get_type
    pop rdx
    call types_compatible
    je .q_mut_type_ok
    jmp type_error
.q_mut_type_ok:
    mov rdi, r14
    mov rsi, 1
    call sym_set_init
    mov rdi, r14
    call sym_get_offset
    mov r9, rax ; imm = offset
    mov rdi, r14
    call sym_get_type
    mov r12, rax ; type
    pop rcx ; src1 vreg
    mov rdi, IR_STORE_VAR
    mov rsi, r12
    xor rdx, rdx
    xor r8, r8
    xor r10, r10
    call emit_ir
    ret
.q_mut_undef:
    jmp undef_error
.q_mut_private:
    mov rdi, err_private_member
    jmp compile_error

; Null-compatible type check (design.md §4.16):
; A `null` literal (expr type = TYPE_VOID) may be stored into any reference
; type: str, seq, dict, tup, and struct (TYPE_COMPLEX).
; Inputs:  rax = declared type, rdx = expression type
; Output:  ZF = 1 if compatible (types equal, or null -> reference type)
types_compatible:
    cmp rax, rdx
    je .tc_match
    cmp rdx, TYPE_VOID
    jne .tc_nomatch
    cmp rax, TYPE_STR
    je .tc_match
    cmp rax, TYPE_SEQ
    je .tc_match
    cmp rax, TYPE_DICT
    je .tc_match
    cmp rax, TYPE_TUP
    je .tc_match
    cmp rax, TYPE_COMPLEX
    je .tc_match
.tc_nomatch:
    ret ; ZF = 0 (last cmp mismatch)
.tc_match:
    cmp rax, rax ; ZF = 1
    ret
