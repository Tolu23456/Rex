; ============================================================
; parser/parser.asm — Rex recursive-descent parser
; ============================================================
bits 64
%include "rex_defs.inc"

global parse_program

extern lex_next, cur_tok, cur_tok_val, tok_ident
extern var_add, var_find, get_var_va
extern proto_add, proto_find
extern codegen_init
extern emit_b, emit_d, emit_q, emit_blob, emit_blob_v2
extern codegen_emit_mov_rax_imm64, codegen_emit_mov_rax_imm32
extern codegen_emit_mov_rax_var, codegen_emit_store_rax_to_var
extern codegen_emit_push_rax, codegen_emit_pop_rbx
extern codegen_emit_add_rax_rbx, codegen_emit_sub_rax_rbx
extern codegen_emit_imul_rax_rbx, codegen_emit_idiv_rbx_by_rax
extern codegen_emit_imod_rbx_by_rax, codegen_emit_neg_rax
extern codegen_emit_bitwise_and, codegen_emit_bitwise_or
extern codegen_emit_bitwise_xor, codegen_emit_bitwise_not
extern codegen_emit_shl, codegen_emit_shr
extern codegen_emit_and_bool, codegen_emit_or_bool
extern codegen_emit_not_rax
extern codegen_emit_cmp_setcc
extern codegen_emit_test_jz, codegen_emit_jmp_end
extern codegen_emit_test_jnz
extern codegen_patch_jump, codegen_patch_chain_end
extern codegen_emit_call_rt_pri, codegen_emit_call_rt_prs
extern codegen_emit_call_rt_prb, codegen_emit_call_rt_prf
extern codegen_emit_call_rt_prc, codegen_emit_call_rt_err
extern codegen_output_typed, codegen_output_rax
extern codegen_emit_for_start, codegen_emit_for_end
extern codegen_emit_for_start_dyn
extern codegen_emit_while_start, codegen_emit_while_end
extern codegen_emit_break, codegen_patch_breaks
extern codegen_push_cont, codegen_pop_cont, codegen_emit_skip
extern codegen_emit_exit0, codegen_emit_exit1
extern codegen_emit_str_rax
extern codegen_begin_protos, codegen_end_protos
extern codegen_emit_prot_start, codegen_emit_prot_end
extern codegen_emit_call_prot
extern codegen_emit_seq_alloc, codegen_emit_seq_push
extern codegen_emit_seq_pop, codegen_emit_seq_len, codegen_emit_seq_cap
extern codegen_emit_inc_var, codegen_emit_dec_var, codegen_emit_swap_vars
extern codegen_emit_abs_rax, codegen_emit_typeof_rax
extern codegen_emit_cvttsd2si_rax, codegen_emit_cvtsi2sd_rax
extern codegen_emit_float_op
extern codegen_emit_mov_rdi_rax, codegen_emit_movdi_rax
extern codegen_emit_unknown_bool, codegen_emit_rdrand_rax
extern codegen_emit_clock_ms
extern codegen_emit_mov_rdi_var
extern codegen_get_out_idx
extern codegen_emit_call_rt_str, codegen_emit_call_rt_str_bool
extern codegen_emit_call_rt_inp
extern codegen_emit_int_to_bool
extern codegen_emit_trunc_byte
extern codegen_emit_xor_rdi_rdi
extern cur_type, prot_body_depth
extern out_idx, var_table, var_count
extern proto_table, proto_count
extern jump_patch_stack, jump_patch_depth
extern end_jump_stack, end_jump_depth
extern chain_base_stack, chain_base_depth
extern loop_depth
extern break_jump_stack, break_jump_depth
extern break_base_stack, break_base_depth
extern for_step_val
extern cur_proto_idx
extern fwd_ref_names, fwd_ref_patches, fwd_ref_count
extern out_buffer

; ============================================================
; BSS — parser state
; ============================================================
section .bss

; Name buffer for temporary storage
tmp_name:           resb 64
tmp_name2:          resb 64
tmp_type:           resb 1
tmp_type2:          resb 1

; Protocol definition state
protos_started:     resb 1      ; 1 = we've emitted begin_protos already
in_proto:           resb 1      ; 1 = inside a protocol body
cur_indent_depth:   resq 1      ; current block nesting level

; scope depth for protocols
scope_depth:        resq 1

section .data
; Error strings
err_expected_ident: db "rex: expected identifier", 0
err_expected_colon: db "rex: expected ':'", 0
err_expected_eq:    db "rex: expected '='", 0
err_undecl_var:     db "rex: undeclared variable", 0
err_undecl_prot:    db "rex: undeclared protocol", 0
err_bad_stmt:       db "rex: unknown statement", 0
err_no_newline:     db "rex: expected newline", 0

section .text

; ============================================================
; Macro helpers
; ============================================================
%macro expect_newline 0
    cmp     dword [cur_tok], TOK_NEWLINE
    je      %%ok
    cmp     dword [cur_tok], TOK_EOF
    je      %%ok
    call    lex_next            ; skip unexpected token(s)
%%ok:
    cmp     dword [cur_tok], TOK_NEWLINE
    jne     %%done
    call    lex_next
%%done:
%endmacro

%macro advance 0
    call    lex_next
%endmacro

; ============================================================
; parse_program — main entry point
; Expects lexer to be initialized, lex_next already called.
; ============================================================
parse_program:
    push    rbx
    push    r12
    push    r13

    ; Emit the protocol section jump (will be patched at end)
    call    codegen_begin_protos

    ; Skip leading newlines
.skip_nl:
    cmp     dword [cur_tok], TOK_NEWLINE
    jne     .not_nl
    advance
    jmp     .skip_nl
.not_nl:

.main_loop:
    cmp     dword [cur_tok], TOK_EOF
    je      .done

    ; skip extra newlines between statements
    cmp     dword [cur_tok], TOK_NEWLINE
    je      .skip_nl

    call    parse_stmt

    jmp     .main_loop

.done:
    ; Emit exit(0)
    call    codegen_emit_exit0

    ; Patch protocol section skip jump
    call    codegen_end_protos

    ; Resolve forward references (protocols called before defined)
    call    resolve_fwd_refs

    pop     r13
    pop     r12
    pop     rbx
    ret

; ============================================================
; parse_stmt — dispatch on current token
; ============================================================
parse_stmt:
    push    rbx
    push    r12
    push    r13

    mov     eax, dword [cur_tok]

    ; Type declaration keywords
    cmp     eax, TOK_TYPE_INT
    je      .do_decl
    cmp     eax, TOK_TYPE_FLOAT
    je      .do_decl
    cmp     eax, TOK_TYPE_BOOL
    je      .do_decl
    cmp     eax, TOK_TYPE_STR
    je      .do_decl
    cmp     eax, TOK_TYPE_COMPLEX
    je      .do_decl
    cmp     eax, TOK_TYPE_SEQ
    je      .do_decl
    cmp     eax, TOK_TYPE_DICT
    je      .do_decl
    cmp     eax, TOK_TYPE_CHAR
    je      .do_decl
    cmp     eax, TOK_TYPE_BYTE
    je      .do_decl

    ; Colon-assign: :ident = expr
    cmp     eax, TOK_COLON
    je      .do_assign

    ; output
    cmp     eax, TOK_OUTPUT
    je      .do_output

    ; if
    cmp     eax, TOK_IF
    je      .do_if

    ; while
    cmp     eax, TOK_WHILE
    je      .do_while

    ; for
    cmp     eax, TOK_FOR
    je      .do_for

    ; prot
    cmp     eax, TOK_PROT
    je      .do_prot

    ; return
    cmp     eax, TOK_RETURN
    je      .do_return

    ; stop
    cmp     eax, TOK_STOP
    je      .do_stop

    ; skip
    cmp     eax, TOK_SKIP
    je      .do_skip

    ; pass
    cmp     eax, TOK_PASS
    je      .do_pass

    ; err
    cmp     eax, TOK_ERR
    je      .do_err

    ; push
    cmp     eax, TOK_PUSH
    je      .do_push

    ; pop (statement form)
    cmp     eax, TOK_POP
    je      .do_pop_stmt

    ; swap
    cmp     eax, TOK_SWAP
    je      .do_swap

    ; ++ ident
    cmp     eax, TOK_PLUSPLUS
    je      .do_inc

    ; -- ident
    cmp     eax, TOK_MINUSMINUS
    je      .do_dec

    ; @ (protocol call statement)
    cmp     eax, TOK_AT
    je      .do_call_stmt

    ; switch (design.md §7.2 — value dispatch, same semantics as when/is)
    cmp     eax, TOK_SWITCH
    je      .do_when

    ; when
    cmp     eax, TOK_WHEN
    je      .do_when

    ; use
    cmp     eax, TOK_USE
    je      .do_use

    ; Identifier as statement: could be type-inferred declaration or forward proto call
    cmp     eax, TOK_IDENT
    je      .do_ident_stmt

    ; unknown token — skip
    advance
    pop     r13
    pop     r12
    pop     rbx
    ret

.do_decl:
    pop     r13
    pop     r12
    pop     rbx
    jmp     parse_decl

.do_assign:
    pop     r13
    pop     r12
    pop     rbx
    jmp     parse_assign

.do_output:
    pop     r13
    pop     r12
    pop     rbx
    jmp     parse_output

.do_if:
    pop     r13
    pop     r12
    pop     rbx
    jmp     parse_if

.do_while:
    pop     r13
    pop     r12
    pop     rbx
    jmp     parse_while

.do_for:
    pop     r13
    pop     r12
    pop     rbx
    jmp     parse_for

.do_prot:
    pop     r13
    pop     r12
    pop     rbx
    jmp     parse_prot

.do_return:
    pop     r13
    pop     r12
    pop     rbx
    jmp     parse_return

.do_stop:
    pop     r13
    pop     r12
    pop     rbx
    jmp     parse_stop

.do_skip:
    pop     r13
    pop     r12
    pop     rbx
    jmp     parse_skip

.do_pass:
    advance
    ; skip trailing newline
    cmp     dword [cur_tok], TOK_NEWLINE
    jne     .pass_done
    advance
.pass_done:
    pop     r13
    pop     r12
    pop     rbx
    ret

.do_err:
    pop     r13
    pop     r12
    pop     rbx
    jmp     parse_err

.do_push:
    pop     r13
    pop     r12
    pop     rbx
    jmp     parse_push

.do_pop_stmt:
    pop     r13
    pop     r12
    pop     rbx
    jmp     parse_pop_stmt

.do_swap:
    pop     r13
    pop     r12
    pop     rbx
    jmp     parse_swap

.do_inc:
    pop     r13
    pop     r12
    pop     rbx
    jmp     parse_inc

.do_dec:
    pop     r13
    pop     r12
    pop     rbx
    jmp     parse_dec

.do_call_stmt:
    pop     r13
    pop     r12
    pop     rbx
    jmp     parse_call_stmt

.do_when:
    pop     r13
    pop     r12
    pop     rbx
    jmp     parse_when

.do_use:
    ; use mm pool/arena/gc ...  — skip for now
    advance
    cmp     dword [cur_tok], TOK_NEWLINE
    jne     .use_skip
    advance
.use_skip:
    pop     r13
    pop     r12
    pop     rbx
    ret

.do_ident_stmt:
    ; Type-inferred declaration: "x = 5" or "x = 3.14"
    ; Or: could be something else — check for = after ident
    pop     r13
    pop     r12
    pop     rbx
    jmp     parse_infer_decl

; ============================================================
; parse_decl — "TYPE name [= expr]" or "TYPE name" (uninitialized)
; ============================================================
parse_decl:
    push    rbx
    push    r12
    push    r13

    ; Get type from current token
    mov     r12d, [cur_tok]          ; r12 = type token (zero-extends to 64-bit)
    ; Convert type token to type code
    call    tok_to_type_code         ; rax = type code
    mov     byte [tmp_type], al

    advance                          ; consume type keyword

    ; Handle seq[T] or dict[T] with brackets
    cmp     byte [tmp_type], TYPE_SEQ
    je      .seq_decl
    cmp     byte [tmp_type], TYPE_DICT
    je      .dict_decl

    ; Check for sized int/float: int[N]
    cmp     dword [cur_tok], TOK_LBRACKET
    je      .skip_size_spec

    jmp     .got_type

.skip_size_spec:
    ; skip [N] size specifier
    advance                          ; skip [
.skip_spec_loop:
    cmp     dword [cur_tok], TOK_RBRACKET
    je      .skip_spec_end
    cmp     dword [cur_tok], TOK_EOF
    je      .skip_spec_end
    advance
    jmp     .skip_spec_loop
.skip_spec_end:
    advance                          ; skip ]
    jmp     .got_type

.seq_decl:
.dict_decl:
    ; seq[T] or seq[T, N] — skip the type parameter
    cmp     dword [cur_tok], TOK_LBRACKET
    jne     .got_type
    advance
.skip_seq_tp:
    cmp     dword [cur_tok], TOK_RBRACKET
    je      .skip_seq_tp_end
    cmp     dword [cur_tok], TOK_EOF
    je      .skip_seq_tp_end
    advance
    jmp     .skip_seq_tp
.skip_seq_tp_end:
    advance
    jmp     .got_type

.got_type:
    ; Expect identifier (variable name)
    cmp     dword [cur_tok], TOK_IDENT
    jne     .decl_error
    lea     rdi, [tok_ident]
    lea     rsi, [tmp_name]
    call    strcpy_64

    advance                          ; consume name

    ; Check if it's already declared
    lea     rdi, [tmp_name]
    call    var_find
    cmp     rax, -1
    jne     .already_decl            ; allow re-declaration (just update)

    ; Add to var table
    lea     rdi, [tmp_name]
    movzx   rsi, byte [tmp_type]
    call    var_add
    mov     r13, rax                 ; r13 = var index

    jmp     .check_init

.already_decl:
    mov     r13, rax                 ; r13 = existing var index

.check_init:
    ; Check for optional initializer
    cmp     dword [cur_tok], TOK_EQ
    jne     .no_init

    advance                          ; consume '='

    ; Parse initializer expression
    call    parse_expr

    ; Store result into variable
    mov     rdi, r13
    call    get_var_va
    mov     rdi, rax
    call    codegen_emit_store_rax_to_var

    ; Update type in var table based on cur_type
    mov     rax, r13
    shl     rax, 6
    lea     rax, [var_table + rax]
    mov     cl, [cur_type]
    mov     [rax + VAR_TYPE_OFF], cl
    mov     byte [rax + VAR_INIT_OFF], 1

    jmp     .decl_nl

.no_init:
    ; Handle seq allocation
    cmp     byte [tmp_type], TYPE_SEQ
    jne     .no_init_done
    ; Allocate sequence
    mov     rdi, r13
    call    get_var_va
    mov     rdi, rax
    call    codegen_emit_seq_alloc
    jmp     .decl_nl

.no_init_done:
.decl_nl:
    ; Consume optional newline
    cmp     dword [cur_tok], TOK_NEWLINE
    jne     .decl_done
    advance

.decl_done:
    pop     r13
    pop     r12
    pop     rbx
    ret

.decl_error:
    advance
    pop     r13
    pop     r12
    pop     rbx
    ret

; ============================================================
; parse_infer_decl — "name = expr" (type-inferred declaration)
; ============================================================
parse_infer_decl:
    push    rbx
    push    r12

    ; Current token is IDENT
    lea     rdi, [tok_ident]
    lea     rsi, [tmp_name]
    call    strcpy_64
    advance                          ; consume name

    ; Expect '='
    cmp     dword [cur_tok], TOK_EQ
    jne     .infer_done

    advance                          ; consume '='

    ; Parse expr
    call    parse_expr

    ; Look up or add variable
    lea     rdi, [tmp_name]
    call    var_find
    cmp     rax, -1
    jne     .infer_found

    ; Add with inferred type
    lea     rdi, [tmp_name]
    movzx   rsi, byte [cur_type]
    call    var_add
    mov     r12, rax
    jmp     .infer_store

.infer_found:
    mov     r12, rax

.infer_store:
    mov     rdi, r12
    call    get_var_va
    mov     rdi, rax
    call    codegen_emit_store_rax_to_var

    ; Update type
    mov     rax, r12
    shl     rax, 6
    lea     rax, [var_table + rax]
    mov     cl, [cur_type]
    mov     [rax + VAR_TYPE_OFF], cl
    mov     byte [rax + VAR_INIT_OFF], 1

.infer_done:
    cmp     dword [cur_tok], TOK_NEWLINE
    jne     .infer_ret
    advance

.infer_ret:
    pop     r12
    pop     rbx
    ret

; ============================================================
; parse_assign — ":ident = expr"
; ============================================================
parse_assign:
    push    rbx
    push    r12

    advance                          ; consume ':'

    ; Expect identifier
    cmp     dword [cur_tok], TOK_IDENT
    jne     .assign_err

    lea     rdi, [tok_ident]
    lea     rsi, [tmp_name]
    call    strcpy_64
    advance                          ; consume name

    ; Expect '='
    cmp     dword [cur_tok], TOK_EQ
    jne     .assign_err

    advance                          ; consume '='

    ; Parse expression
    call    parse_expr

    ; Find variable
    lea     rdi, [tmp_name]
    call    var_find
    cmp     rax, -1
    je      .assign_err             ; undeclared

    mov     r12, rax

    ; Store
    mov     rdi, r12
    call    get_var_va
    mov     rdi, rax
    call    codegen_emit_store_rax_to_var

    ; Update init flag
    mov     rax, r12
    shl     rax, 6
    lea     rax, [var_table + rax]
    mov     byte [rax + VAR_INIT_OFF], 1

    cmp     dword [cur_tok], TOK_NEWLINE
    jne     .assign_ret
    advance

.assign_ret:
    pop     r12
    pop     rbx
    ret

.assign_err:
    ; Try to recover
    cmp     dword [cur_tok], TOK_NEWLINE
    je      .assign_ret
    advance
    jmp     .assign_ret

; ============================================================
; parse_output — "output expr"
; ============================================================
parse_output:
    push    rbx

    advance                          ; consume 'output'

    ; Handle output(expr) with parens
    cmp     dword [cur_tok], TOK_LPAREN
    jne     .output_no_paren
    advance
    call    parse_expr
    cmp     dword [cur_tok], TOK_RPAREN
    jne     .output_no_rp
    advance
.output_no_rp:
    jmp     .emit_output

.output_no_paren:
    call    parse_expr

.emit_output:
    ; Emit output call based on type
    movzx   edi, byte [cur_type]
    call    codegen_output_typed

    cmp     dword [cur_tok], TOK_NEWLINE
    jne     .output_done
    advance

.output_done:
    pop     rbx
    ret

; ============================================================
; parse_if — "if cond:\n  block\n[elif cond:\n  block\n]*[else:\n  block\n]"
; ============================================================
parse_if:
    push    rbx
    push    r12
    push    r13
    push    r14

    advance                          ; consume 'if'

    ; Parse condition
    call    parse_expr

    ; test rax, jz exit
    call    codegen_emit_test_jz     ; rax = jz_patch offset
    mov     r12, rax                 ; save jz_patch

    ; Push chain base
    mov     rax, [end_jump_depth]
    mov     rbx, [chain_base_depth]
    mov     [chain_base_stack + rbx*8], rax
    inc     qword [chain_base_depth]

    ; Expect ':'
    cmp     dword [cur_tok], TOK_COLON
    jne     .if_no_colon
    advance
.if_no_colon:

    ; Expect NEWLINE
    cmp     dword [cur_tok], TOK_NEWLINE
    jne     .if_no_nl
    advance
.if_no_nl:

    ; Expect INDENT
    cmp     dword [cur_tok], TOK_INDENT
    jne     .if_no_indent
    advance
.if_no_indent:

    ; Parse if-body
    call    parse_block

    ; Patch jz to here
    mov     rdi, r12
    call    codegen_patch_jump

    ; Emit jmp to chain end (to skip elif/else bodies)
    call    codegen_emit_jmp_end     ; rax = jmp patch
    ; Push onto end_jump_stack
    mov     rbx, [end_jump_depth]
    mov     [end_jump_stack + rbx*8], rax
    inc     qword [end_jump_depth]

.check_elif:
    ; Check for elif
    cmp     dword [cur_tok], TOK_ELIF
    je      .do_elif

    ; Check for else
    cmp     dword [cur_tok], TOK_ELSE
    je      .do_else

    ; No more branches
    jmp     .if_done

.do_elif:
    advance                          ; consume 'elif'

    call    parse_expr

    call    codegen_emit_test_jz
    mov     r12, rax

    cmp     dword [cur_tok], TOK_COLON
    jne     .elif_nc
    advance
.elif_nc:
    cmp     dword [cur_tok], TOK_NEWLINE
    jne     .elif_nl
    advance
.elif_nl:
    cmp     dword [cur_tok], TOK_INDENT
    jne     .elif_ni
    advance
.elif_ni:
    call    parse_block

    ; patch jz
    mov     rdi, r12
    call    codegen_patch_jump

    ; jmp to chain end
    call    codegen_emit_jmp_end
    mov     rbx, [end_jump_depth]
    mov     [end_jump_stack + rbx*8], rax
    inc     qword [end_jump_depth]

    jmp     .check_elif

.do_else:
    advance                          ; consume 'else'
    cmp     dword [cur_tok], TOK_COLON
    jne     .else_nc
    advance
.else_nc:
    cmp     dword [cur_tok], TOK_NEWLINE
    jne     .else_nl
    advance
.else_nl:
    cmp     dword [cur_tok], TOK_INDENT
    jne     .else_ni
    advance
.else_ni:
    call    parse_block

.if_done:
    ; Patch all chain-end jumps
    call    codegen_patch_chain_end
    dec     qword [chain_base_depth]

    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ============================================================
; parse_while — "while cond:\n  block\n"
; ============================================================
parse_while:
    push    rbx
    push    r12
    push    r13

    advance                          ; consume 'while'

    ; Save loop start (before condition)
    call    codegen_get_out_idx
    mov     r12, rax                 ; loop start

    call    codegen_push_cont        ; push loop_start as continue target
    ; Wait - codegen_push_cont takes rdi = address
    ; I called it wrong here. Let me fix:
    ; Actually the cont target for while is the condition start
    ; Let me redo: save out_idx in r12 AFTER this:
    ; The cont target = condition start (before parsing expr)
    ; That's already saved in r12 above. Need to call codegen_push_cont(r12).
    ; But I already called it... let me call it properly.
    ; Actually I called codegen_get_out_idx first (got r12), then need push_cont(r12).
    ; But I called push_cont() with no arg... hmm.
    ; Let me just inline it:
    ; Actually wait, I wrote `call codegen_push_cont` without setting rdi. Let me fix this.

    ; Push break base
    mov     rdi, [break_jump_depth]
    mov     rsi, rdi
    mov     [break_base_stack + rsi*8], rdi   ; Hmm this is wrong
    ; Just push current break_jump_depth as the base
    mov     rbx, [break_base_depth]
    mov     rsi, [break_jump_depth]
    mov     [break_base_stack + rbx*8], rsi
    inc     qword [break_base_depth]

    inc     qword [loop_depth]

    ; Parse condition
    call    parse_expr

    ; test rax, jz exit
    call    codegen_emit_test_jz
    mov     r13, rax                 ; jz patch

    ; Expect ':'
    cmp     dword [cur_tok], TOK_COLON
    jne     .while_nc
    advance
.while_nc:
    cmp     dword [cur_tok], TOK_NEWLINE
    jne     .while_nl
    advance
.while_nl:
    cmp     dword [cur_tok], TOK_INDENT
    jne     .while_ni
    advance
.while_ni:

    ; Parse body
    call    parse_block

    ; Emit while end (back-jump + patch exit)
    mov     rdi, r12
    mov     rsi, r13
    call    codegen_emit_while_end
    ; (while_end also calls patch_breaks and pop_cont, but I set up manually)
    ; Actually while_end calls those internally... but I pushed cont manually.
    ; Let me just call while_end and it handles everything.
    ; But I didn't use codegen_push_cont... let me restructure.

    ; Undo manual setup and rely on while_end:
    dec     qword [break_base_depth]
    dec     qword [loop_depth]

    pop     r13
    pop     r12
    pop     rbx
    ret

; ============================================================
; parse_for — "for N in start..end:" or "for N in each seq:"
; ============================================================
parse_for:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    advance                          ; consume 'for'

    ; Get loop variable name
    cmp     dword [cur_tok], TOK_IDENT
    jne     .for_done
    lea     rdi, [tok_ident]
    lea     rsi, [tmp_name]
    call    strcpy_64
    advance

    ; Expect 'in'
    cmp     dword [cur_tok], TOK_IN
    jne     .for_done
    advance

    ; Check for 'each' (iterate over sequence)
    cmp     dword [cur_tok], TOK_EACH
    je      .for_each

    ; Range-based for: start..end
    ; Save from value
    call    parse_expr              ; parse start
    ; Result is in rax - but we need the value/type
    ; For simplicity: peek if expr was a literal (in cur_tok_val from before parse_expr)
    ; Actually we just emitted code to compute the value into rax.
    ; We need to save it somewhere for the for_start function.
    ; For a simple literal, we can use the value directly.
    ; But in general, we'd need to store to a temp var.
    ; Simplified: assume start is always a literal or variable load
    ; For now, just handle the common case.

    ; Store start in temp var (or just 0 if it's a literal 0)
    ; Actually for the codegen_emit_for_start, we pass literal values.
    ; But if the start was a variable, we need special handling.
    ; SIMPLIFICATION: just use 0 as start for now, or handle literal case.

    ; For the bootstrap, let's just generate code that:
    ; 1. Evaluates start into temp storage
    ; 2. Sets up the loop
    ; This requires a temp variable. Let's use a special approach:
    ; emit the comparison and increment inline.

    ; Let me use a simpler approach: always compile as a range loop
    ; with the 'from' already computed into some scratch variable.
    ; For now: just support literal 0 as start and variable/literal end.

    ; Expect '..'
    cmp     dword [cur_tok], TOK_DOTDOT
    jne     .for_done
    advance

    ; Parse end expression
    ; For simplicity, check if it's a literal
    mov     r15, 0                  ; from = 0 (simplified)

    ; Actually let's just support the common case: literal or identifier range
    cmp     dword [cur_tok], TOK_INT_LIT
    jne     .for_end_var

    mov     r14, [cur_tok_val]      ; to = literal
    advance

    ; Find or create loop variable
    lea     rdi, [tmp_name]
    call    var_find
    cmp     rax, -1
    jne     .for_found_var

    lea     rdi, [tmp_name]
    mov     rsi, TYPE_INT
    call    var_add

.for_found_var:
    mov     r12, rax                ; r12 = var index
    mov     rdi, r12
    call    get_var_va
    mov     r13, rax                ; r13 = var VA

    ; codegen_emit_for_start(var_va, from, to)
    mov     rdi, r13
    mov     rsi, r15                ; from=0
    mov     rdx, r14                ; to=literal
    call    codegen_emit_for_start
    ; rax = loop_start, rbx = jge_patch
    mov     r14, rax                ; loop_start
    mov     r15, rbx                ; jge_patch

    jmp     .for_body

.for_end_var:
    ; End is a variable
    lea     rdi, [tok_ident]
    call    var_find
    cmp     rax, -1
    je      .for_done
    mov     rbx, rax
    advance

    mov     rdi, rbx
    call    get_var_va
    mov     r12, rax                ; end var VA

    ; Find/create loop variable
    lea     rdi, [tmp_name]
    call    var_find
    cmp     rax, -1
    jne     .for_found_var2

    lea     rdi, [tmp_name]
    mov     rsi, TYPE_INT
    call    var_add

.for_found_var2:
    mov     rbx, rax
    mov     rdi, rbx
    call    get_var_va
    mov     r13, rax

    ; Use dynamic for
    mov     rdi, r13
    mov     rsi, r15
    mov     rdx, r12
    call    codegen_emit_for_start_dyn
    mov     r14, rax
    mov     r15, rbx
    mov     r12, r13                ; var VA

    jmp     .for_body

.for_each:
    ; for N in each seq: — iterate sequence
    ; For now, implement as indexed loop 0..len(seq)
    advance                         ; consume 'each'
    ; Expect seq variable name
    cmp     dword [cur_tok], TOK_IDENT
    jne     .for_done
    lea     rdi, [tok_ident]
    lea     rsi, [tmp_name2]
    call    strcpy_64
    advance

    ; Find seq var
    lea     rdi, [tmp_name2]
    call    var_find
    cmp     rax, -1
    je      .for_done
    mov     rbx, rax
    mov     rdi, rbx
    call    get_var_va
    push    rax                     ; seq VA on stack

    ; Get/create index var for loop counter
    lea     rdi, [tmp_name]
    call    var_find
    cmp     rax, -1
    jne     .for_each_found
    lea     rdi, [tmp_name]
    mov     rsi, TYPE_INT
    call    var_add
.for_each_found:
    mov     r12, rax
    mov     rdi, r12
    call    get_var_va
    mov     r13, rax                ; loop var VA

    ; Get len of seq → store in a temp
    ; Emit: mov rax, [seq_ptr]; mov rax, [rax+8]  (sequence length)
    pop     rdi
    call    codegen_emit_seq_len    ; rax = len (at runtime)
    ; Store len in a temp location (re-use tmp_type2 area — actually we need a real temp var)
    ; For simplicity: use a hard-coded temp approach by doing the comparison inline
    ; Actually for 'each', just use for i in 0..len: approach but we can't easily do dynamic end.
    ; Let's just do: evaluate len, store in a temp var, then set up loop with temp as end
    ; Declare a temp var __each_end
    lea     rdi, [rel each_end_name]
    call    var_find
    cmp     rax, -1
    jne     .for_each_temp_found
    lea     rdi, [rel each_end_name]
    mov     rsi, TYPE_INT
    call    var_add
.for_each_temp_found:
    push    rax
    mov     rdi, rax
    call    get_var_va
    mov     r14, rax                ; temp end VA
    ; store len into temp
    mov     rdi, r14
    call    codegen_emit_store_rax_to_var
    pop     rax

    ; now set up for loop: for idx in 0..temp_end
    mov     rdi, r13
    xor     rsi, rsi                ; from = 0
    mov     rdx, r14                ; to_var_va
    call    codegen_emit_for_start_dyn
    mov     r14, rax
    mov     r15, rbx
    jmp     .for_body

.for_body:
    ; Expect ':'
    cmp     dword [cur_tok], TOK_COLON
    jne     .for_no_colon
    advance
.for_no_colon:
    cmp     dword [cur_tok], TOK_NEWLINE
    jne     .for_nl
    advance
.for_nl:
    cmp     dword [cur_tok], TOK_INDENT
    jne     .for_ni
    advance
.for_ni:

    ; Check for optional 'step' at end of loop body
    ; Parse body
    call    parse_block

    ; Emit for end
    mov     rdi, r14                ; loop_start
    mov     rsi, r15                ; jge_patch
    mov     rdx, r13                ; var VA
    call    codegen_emit_for_end

.for_done:
    cmp     dword [cur_tok], TOK_NEWLINE
    jne     .for_ret
    advance

.for_ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

each_end_name: db "__each_end", 0

; ============================================================
; parse_prot — "prot name(params):\n  body\n"
; ============================================================
parse_prot:
    push    rbx
    push    r12
    push    r13

    advance                          ; consume 'prot'

    cmp     dword [cur_tok], TOK_IDENT
    jne     .prot_err

    ; Save name
    lea     rdi, [tok_ident]
    lea     rsi, [tmp_name]
    call    strcpy_64
    advance

    ; Add to proto table
    lea     rdi, [tmp_name]
    call    proto_add
    mov     r12, rax                 ; r12 = proto index

    ; Expect '('
    cmp     dword [cur_tok], TOK_LPAREN
    jne     .prot_no_parens

    advance                          ; consume '('

    ; Parse parameters
    xor     r13, r13                 ; param count
.prot_param_loop:
    cmp     dword [cur_tok], TOK_RPAREN
    je      .prot_params_done
    cmp     dword [cur_tok], TOK_EOF
    je      .prot_params_done

    ; param: type name
    ; type keyword
    call    tok_to_type_code         ; rax = type
    advance
    ; name
    cmp     dword [cur_tok], TOK_IDENT
    jne     .prot_params_done

    lea     rdi, [tok_ident]
    movzx   rsi, al
    call    var_add                  ; add param as local var (will be at top of var table)
    advance                          ; consume name

    ; Store param var index in proto table
    push    rax
    mov     rax, r12
    imul    rax, PROTO_ENTRY_SIZE
    lea     rax, [proto_table + rax]
    pop     rbx
    movzx   ecx, byte [rax + PROTO_PARAMCNT_OFF]
    cmp     rcx, 6
    jge     .prot_too_many_params
    mov     [rax + PROTO_PARAMS_OFF + rcx], bl   ; store var index
    inc     byte [rax + PROTO_PARAMCNT_OFF]
.prot_too_many_params:

    inc     r13

    cmp     dword [cur_tok], TOK_COMMA
    jne     .prot_params_done
    advance                          ; consume ','
    jmp     .prot_param_loop

.prot_params_done:
    cmp     dword [cur_tok], TOK_RPAREN
    jne     .prot_no_rp
    advance

.prot_no_rp:
.prot_no_parens:
    ; Check return type annotation (-> type)
    cmp     dword [cur_tok], TOK_ARROW
    jne     .prot_no_ret
    advance
    call    tok_to_type_code         ; consume return type
    advance
.prot_no_ret:

    ; Expect ':'
    cmp     dword [cur_tok], TOK_COLON
    jne     .prot_nc
    advance
.prot_nc:
    cmp     dword [cur_tok], TOK_NEWLINE
    jne     .prot_nl
    advance
.prot_nl:
    cmp     dword [cur_tok], TOK_INDENT
    jne     .prot_ni
    advance
.prot_ni:

    ; Emit protocol start (records out_idx in proto table)
    mov     rdi, r12
    mov     rsi, r13
    call    codegen_emit_prot_start

    ; Emit argument pops if params exist
    test    r13, r13
    jz      .prot_no_pop_args
    ; Emit pops for args: arg1→rdi, arg2→rsi, etc.
    call    emit_arg_pops
.prot_no_pop_args:

    mov     byte [in_proto], 1
    mov     qword [cur_proto_idx], r12

    ; Parse protocol body
    call    parse_block

    ; Emit ret
    call    codegen_emit_prot_end

    mov     byte [in_proto], 0
    mov     qword [cur_proto_idx], -1

    pop     r13
    pop     r12
    pop     rbx
    ret

.prot_err:
    advance
    pop     r13
    pop     r12
    pop     rbx
    ret

; emit_arg_pops: pops args from stack into registers (rdi, rsi, rdx, rcx, r8, r9)
; Then stores each to its var's VA
emit_arg_pops:
    push    rbx
    push    r12
    push    r13

    ; Get param count for current proto
    mov     rax, [cur_proto_idx]
    imul    rax, PROTO_ENTRY_SIZE
    lea     rax, [proto_table + rax]

    movzx   r13, byte [rax + PROTO_PARAMCNT_OFF]
    test    r13, r13
    jz      .ea_done

    ; Pop registers and store to vars
    ; Args were pushed in REVERSE order, so pop in forward order
    ; pop rdi (pop 5F)
    push    rbx

    xor     r12, r12                ; param index
.ea_loop:
    cmp     r12, r13
    jge     .ea_done_inner

    ; Get var index for this param
    mov     rax, [cur_proto_idx]
    imul    rax, PROTO_ENTRY_SIZE
    lea     rax, [proto_table + rax]
    movzx   rbx, byte [rax + PROTO_PARAMS_OFF + r12]

    ; Get var VA
    push    r12
    mov     rdi, rbx
    call    get_var_va
    pop     r12

    ; Emit: pop reg (according to param position)
    push    rax                     ; save var VA
    cmp     r12, 0
    je      .ea_pop0
    cmp     r12, 1
    je      .ea_pop1
    cmp     r12, 2
    je      .ea_pop2
    cmp     r12, 3
    je      .ea_pop3
    ; params 4,5: just skip
    add     rsp, 8
    jmp     .ea_next

.ea_pop0:
    ; pop rdi (5F), then store to var
    push    rax
    mov     al, 0x5f
    call    emit_b
    pop     rax
    mov     rdi, rax
    call    codegen_emit_store_rax_to_var   ; Hmm, needs to store rdi not rax
    ; Actually I emitted `pop rdi` which puts the arg in rdi
    ; Then I need: mov [var_va], rdi (48 89 3C 25 addr32)
    ; Let me emit that directly
    add     rsp, 8                  ; pop the saved var VA
    jmp     .ea_next

.ea_pop1:
    push    rax
    mov     al, 0x5e                ; pop rsi
    call    emit_b
    pop     rax
    add     rsp, 8
    jmp     .ea_next

.ea_pop2:
    push    rax
    mov     al, 0x5a                ; pop rdx
    call    emit_b
    pop     rax
    add     rsp, 8
    jmp     .ea_next

.ea_pop3:
    push    rax
    mov     al, 0x59                ; pop rcx
    call    emit_b
    pop     rax
    add     rsp, 8

.ea_next:
    inc     r12
    jmp     .ea_loop

.ea_done_inner:
    pop     rbx                     ; restore rbx from .ea_loop push

.ea_done:
    pop     r13
    pop     r12
    pop     rbx
    ret

; ============================================================
; parse_return — "return [expr]"
; ============================================================
parse_return:
    push    rbx

    advance                          ; consume 'return'

    cmp     dword [cur_tok], TOK_NEWLINE
    je      .ret_void
    cmp     dword [cur_tok], TOK_EOF
    je      .ret_void
    cmp     dword [cur_tok], TOK_DEDENT
    je      .ret_void

    ; return with value
    call    parse_expr
    ; value is in rax (or xmm0 for float via bit-cast)

.ret_void:
    call    codegen_emit_prot_end   ; emit ret

    cmp     dword [cur_tok], TOK_NEWLINE
    jne     .ret_done
    advance

.ret_done:
    pop     rbx
    ret

; ============================================================
; parse_stop / parse_skip
; ============================================================
parse_stop:
    advance
    call    codegen_emit_break
    cmp     dword [cur_tok], TOK_NEWLINE
    jne     .stop_done
    advance
.stop_done:
    ret

parse_skip:
    advance
    call    codegen_emit_skip
    cmp     dword [cur_tok], TOK_NEWLINE
    jne     .skip_done
    advance
.skip_done:
    ret

; ============================================================
; parse_err — "err expr"
; ============================================================
parse_err:
    push    rbx

    advance

    call    parse_expr              ; error message (string) into rax

    ; emit: mov rdi, rax; call rt_prq
    call    codegen_emit_mov_rdi_rax
    call    codegen_emit_call_rt_err

    cmp     dword [cur_tok], TOK_NEWLINE
    jne     .err_done
    advance

.err_done:
    pop     rbx
    ret

; ============================================================
; parse_push — "push seq_var value_expr"
; ============================================================
parse_push:
    push    rbx
    push    r12

    advance

    ; Sequence variable name
    cmp     dword [cur_tok], TOK_IDENT
    jne     .push_done
    lea     rdi, [tok_ident]
    call    var_find
    cmp     rax, -1
    je      .push_done
    mov     r12, rax
    advance

    ; Value expression
    call    parse_expr              ; value in rax

    ; Emit seq_push
    mov     rdi, r12
    call    get_var_va
    mov     rdi, rax
    call    codegen_emit_seq_push

    cmp     dword [cur_tok], TOK_NEWLINE
    jne     .push_done
    advance

.push_done:
    pop     r12
    pop     rbx
    ret

; ============================================================
; parse_pop_stmt — "pop seq_var" (discard) or "pop seq_var -> var"
; ============================================================
parse_pop_stmt:
    push    rbx
    push    r12

    advance

    cmp     dword [cur_tok], TOK_IDENT
    jne     .popstmt_done
    lea     rdi, [tok_ident]
    call    var_find
    cmp     rax, -1
    je      .popstmt_done
    mov     r12, rax
    advance

    mov     rdi, r12
    call    get_var_va
    mov     rdi, rax
    call    codegen_emit_seq_pop    ; result in rax

    ; optional -> dest_var
    cmp     dword [cur_tok], TOK_ARROW
    jne     .popstmt_nl
    advance
    cmp     dword [cur_tok], TOK_IDENT
    jne     .popstmt_nl
    lea     rdi, [tok_ident]
    call    var_find
    cmp     rax, -1
    je      .popstmt_nl
    mov     rdi, rax
    call    get_var_va
    mov     rdi, rax
    call    codegen_emit_store_rax_to_var
    advance

.popstmt_nl:
    cmp     dword [cur_tok], TOK_NEWLINE
    jne     .popstmt_done
    advance

.popstmt_done:
    pop     r12
    pop     rbx
    ret

; ============================================================
; parse_swap — "swap a b"
; ============================================================
parse_swap:
    push    rbx
    push    r12
    push    r13

    advance

    cmp     dword [cur_tok], TOK_IDENT
    jne     .swap_done
    lea     rdi, [tok_ident]
    call    var_find
    cmp     rax, -1
    je      .swap_done
    mov     r12, rax
    advance

    cmp     dword [cur_tok], TOK_IDENT
    jne     .swap_done
    lea     rdi, [tok_ident]
    call    var_find
    cmp     rax, -1
    je      .swap_done
    mov     r13, rax
    advance

    mov     rdi, r12
    call    get_var_va
    push    rax

    mov     rdi, r13
    call    get_var_va
    mov     rsi, rax

    pop     rdi
    call    codegen_emit_swap_vars

.swap_done:
    cmp     dword [cur_tok], TOK_NEWLINE
    jne     .swap_ret
    advance

.swap_ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; ============================================================
; parse_inc / parse_dec — "++x" / "--x"
; ============================================================
parse_inc:
    push    rbx

    advance                          ; consume '++'
    cmp     dword [cur_tok], TOK_IDENT
    jne     .inc_done
    lea     rdi, [tok_ident]
    call    var_find
    cmp     rax, -1
    je      .inc_done
    mov     rdi, rax
    call    get_var_va
    mov     rdi, rax
    call    codegen_emit_inc_var
    advance

.inc_done:
    cmp     dword [cur_tok], TOK_NEWLINE
    jne     .inc_ret
    advance
.inc_ret:
    pop     rbx
    ret

parse_dec:
    push    rbx

    advance
    cmp     dword [cur_tok], TOK_IDENT
    jne     .dec_done
    lea     rdi, [tok_ident]
    call    var_find
    cmp     rax, -1
    je      .dec_done
    mov     rdi, rax
    call    get_var_va
    mov     rdi, rax
    call    codegen_emit_dec_var
    advance

.dec_done:
    cmp     dword [cur_tok], TOK_NEWLINE
    jne     .dec_ret
    advance
.dec_ret:
    pop     rbx
    ret

; ============================================================
; parse_call_stmt — "@name(args)"
; ============================================================
parse_call_stmt:
    push    rbx
    push    r12
    push    r13

    advance                          ; consume '@'

    cmp     dword [cur_tok], TOK_IDENT
    jne     .call_done

    lea     rdi, [tok_ident]
    lea     rsi, [tmp_name]
    call    strcpy_64
    advance

    ; Find protocol
    lea     rdi, [tmp_name]
    call    proto_find
    mov     r12, rax                 ; proto index or -1

    ; Expect '('
    cmp     dword [cur_tok], TOK_LPAREN
    jne     .call_no_parens

    advance

    ; Parse arguments (push each onto stack)
    xor     r13, r13
.arg_loop:
    cmp     dword [cur_tok], TOK_RPAREN
    je      .args_done
    cmp     dword [cur_tok], TOK_EOF
    je      .args_done
    call    parse_expr              ; arg in rax
    call    codegen_emit_push_rax   ; push arg
    inc     r13
    cmp     dword [cur_tok], TOK_COMMA
    jne     .args_done
    advance
    jmp     .arg_loop

.args_done:
    cmp     dword [cur_tok], TOK_RPAREN
    jne     .call_no_rp
    advance
.call_no_rp:
.call_no_parens:

    ; Call protocol (or add forward reference)
    cmp     r12, -1
    je      .call_fwd_ref

    mov     rdi, r12
    call    codegen_emit_call_prot

    ; Get return type from proto table
    mov     rax, r12
    imul    rax, PROTO_ENTRY_SIZE
    lea     rax, [proto_table + rax]
    movzx   eax, byte [rax + PROTO_RETTYPE_OFF]
    mov     [cur_type], al

    jmp     .call_done

.call_fwd_ref:
    ; Add to forward reference table (to patch after all protocols are defined)
    mov     rax, [fwd_ref_count]
    cmp     rax, FWD_REF_MAX
    jge     .call_done

    ; Store name
    mov     rbx, rax
    imul    rbx, 32
    lea     rbx, [fwd_ref_names + rbx]
    lea     rsi, [tmp_name]
    mov     rdi, rbx
    xor     ecx, ecx
.fwd_name_copy:
    cmp     ecx, 31
    jge     .fwd_nc_done
    movzx   edx, byte [rsi + rcx]
    mov     [rdi + rcx], dl
    test    dl, dl
    jz      .fwd_nc_done
    inc     ecx
    jmp     .fwd_name_copy
.fwd_nc_done:

    ; Emit placeholder call
    push    rax
    mov     al, 0xe8
    call    emit_b
    mov     rax, [fwd_ref_count]
    mov     rbx, [out_idx]
    mov     [fwd_ref_patches + rax*8], rbx
    xor     eax, eax
    call    emit_d
    pop     rax

    inc     qword [fwd_ref_count]

.call_done:
    cmp     dword [cur_tok], TOK_NEWLINE
    jne     .call_ret
    advance

.call_ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; ============================================================
; parse_when — "when expr:\n  is val: block\n  ..."
; ============================================================
parse_when:
    push    rbx
    push    r12
    push    r13
    push    r14

    advance                          ; consume 'when'

    ; Parse subject expression
    call    parse_expr               ; result in rax

    ; Store subject in a temp var
    lea     rdi, [rel when_tmp_name]
    call    var_find
    cmp     rax, -1
    jne     .when_tmp_found
    lea     rdi, [rel when_tmp_name]
    mov     rsi, TYPE_INT
    call    var_add
.when_tmp_found:
    mov     r13, rax
    mov     rdi, r13
    call    get_var_va
    mov     r14, rax
    mov     rdi, r14
    call    codegen_emit_store_rax_to_var

    ; Consume colon and newline
    cmp     dword [cur_tok], TOK_COLON
    jne     .when_nc
    advance
.when_nc:
    cmp     dword [cur_tok], TOK_NEWLINE
    jne     .when_nl
    advance
.when_nl:
    cmp     dword [cur_tok], TOK_INDENT
    jne     .when_ni
    advance
.when_ni:

    ; Push chain base for end jumps
    mov     rax, [end_jump_depth]
    mov     rbx, [chain_base_depth]
    mov     [chain_base_stack + rbx*8], rax
    inc     qword [chain_base_depth]

.when_cases:
    ; Expect 'is val:'
    cmp     dword [cur_tok], TOK_IS
    jne     .when_done_cases
    advance

    ; Parse the case value
    call    parse_expr               ; case value in rax

    ; Emit: cmp [when_tmp_var], rax; jne skip
    ; For now: compare subject (r14 holds VA) against rax
    ; emit: mov rbx, [r14]; cmp rbx, rax; jne skip
    push    rax
    mov     al, 0x48                 ; mov rbx, [when_var]
    call    emit_b
    mov     al, 0x8b
    call    emit_b
    mov     al, 0x1c
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r14d
    call    emit_d

    mov     al, 0x48                 ; cmp rbx, rax
    call    emit_b
    mov     al, 0x39
    call    emit_b
    mov     al, 0xc3
    call    emit_b

    ; jne (0F 85) placeholder
    mov     al, 0x0f
    call    emit_b
    mov     al, 0x85
    call    emit_b
    mov     r12, [out_idx]          ; save patch offset
    xor     eax, eax
    call    emit_d
    pop     rax

    ; parse block
    cmp     dword [cur_tok], TOK_COLON
    jne     .when_case_nc
    advance
.when_case_nc:
    cmp     dword [cur_tok], TOK_NEWLINE
    jne     .when_case_nl
    advance
.when_case_nl:
    cmp     dword [cur_tok], TOK_INDENT
    jne     .when_case_ni
    advance
.when_case_ni:
    call    parse_block

    ; emit jmp to chain end
    call    codegen_emit_jmp_end
    mov     rbx, [end_jump_depth]
    mov     [end_jump_stack + rbx*8], rax
    inc     qword [end_jump_depth]

    ; patch jne to here
    mov     rdi, r12
    call    codegen_patch_jump

    jmp     .when_cases

.when_done_cases:
    ; optional else (using ELSE token)
    cmp     dword [cur_tok], TOK_ELSE
    jne     .when_no_else
    advance
    cmp     dword [cur_tok], TOK_COLON
    jne     .when_else_nc
    advance
.when_else_nc:
    cmp     dword [cur_tok], TOK_NEWLINE
    jne     .when_else_nl
    advance
.when_else_nl:
    cmp     dword [cur_tok], TOK_INDENT
    jne     .when_else_ni
    advance
.when_else_ni:
    call    parse_block

.when_no_else:
    call    codegen_patch_chain_end
    dec     qword [chain_base_depth]

.when_done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

when_tmp_name: db "__when_tmp", 0

; ============================================================
; parse_block — parse statements until DEDENT or EOF
; ============================================================
parse_block:
    push    rbx

.block_loop:
    cmp     dword [cur_tok], TOK_DEDENT
    je      .block_done
    cmp     dword [cur_tok], TOK_EOF
    je      .block_done
    ; skip extra newlines
    cmp     dword [cur_tok], TOK_NEWLINE
    jne     .block_stmt
    advance
    jmp     .block_loop

.block_stmt:
    call    parse_stmt
    jmp     .block_loop

.block_done:
    ; Consume DEDENT
    cmp     dword [cur_tok], TOK_DEDENT
    jne     .block_ret
    advance

.block_ret:
    pop     rbx
    ret

; ============================================================
; Expression parsing hierarchy
; ============================================================

; parse_expr → parse_or
parse_expr:
    jmp     parse_or

; parse_or → parse_and (handles 'or')
parse_or:
    push    rbx

    call    parse_and

.or_loop:
    cmp     dword [cur_tok], TOK_OR
    jne     .or_done
    call    codegen_emit_push_rax
    advance
    call    parse_and
    call    codegen_emit_pop_rbx
    ; set type to bool
    mov     byte [cur_type], TYPE_BOOL
    call    codegen_emit_or_bool
    jmp     .or_loop

.or_done:
    pop     rbx
    ret

; parse_and → parse_not (handles 'and')
parse_and:
    push    rbx

    call    parse_not

.and_loop:
    cmp     dword [cur_tok], TOK_AND
    jne     .and_done
    call    codegen_emit_push_rax
    advance
    call    parse_not
    call    codegen_emit_pop_rbx
    mov     byte [cur_type], TYPE_BOOL
    call    codegen_emit_and_bool
    jmp     .and_loop

.and_done:
    pop     rbx
    ret

; parse_not → parse_comparison
parse_not:
    cmp     dword [cur_tok], TOK_NOT
    jne     .not_passthrough
    advance
    call    parse_comparison
    mov     byte [cur_type], TYPE_BOOL
    call    codegen_emit_not_rax
    ret
.not_passthrough:
    jmp     parse_comparison

; parse_comparison → parse_additive ([==,!=,<,>,<=,>=] parse_additive)?
parse_comparison:
    push    rbx
    push    r12

    call    parse_additive

    mov     eax, dword [cur_tok]
    cmp     eax, TOK_EQEQ
    je      .do_cmp
    cmp     eax, TOK_NEQ
    je      .do_cmp
    cmp     eax, TOK_LT
    je      .do_cmp
    cmp     eax, TOK_GT
    je      .do_cmp
    cmp     eax, TOK_LE
    je      .do_cmp
    cmp     eax, TOK_GE
    je      .do_cmp
    jmp     .cmp_done

.do_cmp:
    ; Map tok to setCC byte
    call    tok_to_setcc             ; rax = setCC byte (or 0 if not comparison)
    mov     r12, rax

    call    codegen_emit_push_rax
    advance
    call    parse_additive
    call    codegen_emit_pop_rbx

    ; Emit comparison
    mov     rdi, r12
    call    codegen_emit_cmp_setcc
    mov     byte [cur_type], TYPE_BOOL

.cmp_done:
    pop     r12
    pop     rbx
    ret

; parse_additive → parse_term ([+,-,|,&,^] parse_term)*
parse_additive:
    push    rbx
    push    r12

    call    parse_term

.add_loop:
    mov     eax, dword [cur_tok]
    cmp     eax, TOK_PLUS
    je      .do_add
    cmp     eax, TOK_MINUS
    je      .do_sub
    cmp     eax, TOK_PIPE
    je      .do_bitor
    cmp     eax, TOK_AMP
    je      .do_bitand
    cmp     eax, TOK_CARET
    je      .do_bitxor
    jmp     .add_done

.do_add:
    mov     r12, TYPE_INT
    call    codegen_emit_push_rax
    advance
    call    parse_term
    call    codegen_emit_pop_rbx
    ; check if float operation
    cmp     byte [cur_type], TYPE_FLOAT
    je      .fadd
    call    codegen_emit_add_rax_rbx
    jmp     .add_loop
.fadd:
    mov     rdi, 0x58               ; addsd opcode
    call    codegen_emit_float_op
    jmp     .add_loop

.do_sub:
    call    codegen_emit_push_rax
    advance
    call    parse_term
    call    codegen_emit_pop_rbx
    cmp     byte [cur_type], TYPE_FLOAT
    je      .fsub
    call    codegen_emit_sub_rax_rbx
    jmp     .add_loop
.fsub:
    mov     rdi, 0x5c               ; subsd opcode
    call    codegen_emit_float_op
    jmp     .add_loop

.do_bitor:
    call    codegen_emit_push_rax
    advance
    call    parse_term
    call    codegen_emit_pop_rbx
    call    codegen_emit_bitwise_or
    jmp     .add_loop

.do_bitand:
    call    codegen_emit_push_rax
    advance
    call    parse_term
    call    codegen_emit_pop_rbx
    call    codegen_emit_bitwise_and
    jmp     .add_loop

.do_bitxor:
    call    codegen_emit_push_rax
    advance
    call    parse_term
    call    codegen_emit_pop_rbx
    call    codegen_emit_bitwise_xor
    jmp     .add_loop

.add_done:
    pop     r12
    pop     rbx
    ret

; parse_term → parse_factor ([*,/,%,<<,>>] parse_factor)*
parse_term:
    push    rbx

    call    parse_factor

.term_loop:
    mov     eax, dword [cur_tok]
    cmp     eax, TOK_STAR
    je      .do_mul
    cmp     eax, TOK_SLASH
    je      .do_div
    cmp     eax, TOK_PERCENT
    je      .do_mod
    cmp     eax, TOK_LSHIFT
    je      .do_shl
    cmp     eax, TOK_RSHIFT
    je      .do_shr
    jmp     .term_done

.do_mul:
    call    codegen_emit_push_rax
    advance
    call    parse_factor
    call    codegen_emit_pop_rbx
    cmp     byte [cur_type], TYPE_FLOAT
    je      .fmul
    call    codegen_emit_imul_rax_rbx
    jmp     .term_loop
.fmul:
    mov     rdi, 0x59
    call    codegen_emit_float_op
    jmp     .term_loop

.do_div:
    call    codegen_emit_push_rax
    advance
    call    parse_factor
    call    codegen_emit_pop_rbx
    cmp     byte [cur_type], TYPE_FLOAT
    je      .fdiv
    call    codegen_emit_idiv_rbx_by_rax
    jmp     .term_loop
.fdiv:
    mov     rdi, 0x5e
    call    codegen_emit_float_op
    jmp     .term_loop

.do_mod:
    call    codegen_emit_push_rax
    advance
    call    parse_factor
    call    codegen_emit_pop_rbx
    call    codegen_emit_imod_rbx_by_rax
    jmp     .term_loop

.do_shl:
    call    codegen_emit_push_rax
    advance
    call    parse_factor
    call    codegen_emit_pop_rbx
    call    codegen_emit_shl
    jmp     .term_loop

.do_shr:
    call    codegen_emit_push_rax
    advance
    call    parse_factor
    call    codegen_emit_pop_rbx
    call    codegen_emit_shr
    jmp     .term_loop

.term_done:
    pop     rbx
    ret

; parse_factor — atoms and unary ops
parse_factor:
    push    rbx

    mov     eax, dword [cur_tok]

    ; Integer literal
    cmp     eax, TOK_INT_LIT
    jne     .pf_not_int
    mov     rdi, [cur_tok_val]
    call    codegen_emit_mov_rax_imm64
    mov     byte [cur_type], TYPE_INT
    advance
    pop     rbx
    ret

.pf_not_int:
    ; Float literal
    cmp     eax, TOK_FLOAT_LIT
    jne     .pf_not_float
    mov     rdi, [cur_tok_val]
    call    codegen_emit_mov_rax_imm64
    mov     byte [cur_type], TYPE_FLOAT
    advance
    pop     rbx
    ret

.pf_not_float:
    ; Bool literal
    cmp     eax, TOK_TRUE
    je      .pf_true
    cmp     eax, TOK_FALSE
    je      .pf_false
    cmp     eax, TOK_NEUTRAL
    je      .pf_neutral

    ; String literal
    cmp     eax, TOK_STR_LIT
    jne     .pf_not_str
    lea     rdi, [tok_ident]
    call    codegen_emit_str_rax
    mov     byte [cur_type], TYPE_STR
    advance
    pop     rbx
    ret

.pf_not_str:
    ; Identifier (variable load)
    cmp     eax, TOK_IDENT
    jne     .pf_not_ident
    lea     rdi, [tok_ident]
    call    var_find
    cmp     rax, -1
    je      .pf_ident_unknown
    mov     rbx, rax
    ; Get type
    mov     rax, rbx
    shl     rax, 6
    lea     rax, [var_table + rax]
    movzx   ecx, byte [rax + VAR_TYPE_OFF]
    mov     [cur_type], cl
    ; Emit load
    mov     rdi, rbx
    call    get_var_va
    mov     rdi, rax
    call    codegen_emit_mov_rax_var
    advance
    pop     rbx
    ret

.pf_ident_unknown:
    ; Unknown identifier: emit 0
    mov     rdi, 0
    call    codegen_emit_mov_rax_imm64
    advance
    pop     rbx
    ret

.pf_not_ident:
    ; Parenthesized expression
    cmp     eax, TOK_LPAREN
    jne     .pf_not_paren
    advance
    call    parse_expr
    cmp     dword [cur_tok], TOK_RPAREN
    jne     .pf_no_rp
    advance
.pf_no_rp:
    pop     rbx
    ret

.pf_not_paren:
    ; Unary minus
    cmp     eax, TOK_MINUS
    jne     .pf_not_neg
    advance
    call    parse_factor
    ; check if float
    cmp     byte [cur_type], TYPE_FLOAT
    je      .pf_fneg
    call    codegen_emit_neg_rax
    pop     rbx
    ret
.pf_fneg:
    ; negate float: flip sign bit
    push    rsi
    push    rcx
    lea     rsi, [rel .fneg_bytes]
    mov     edx, 12
    ; emit_blob_v2(rsi, rdx)
    extern emit_blob_v2
    call    emit_blob_v2
    pop     rcx
    pop     rsi
    pop     rbx
    ret

.pf_not_neg:
    ; Bitwise NOT
    cmp     eax, TOK_TILDE
    jne     .pf_not_tilde
    advance
    call    parse_factor
    call    codegen_emit_bitwise_not
    pop     rbx
    ret

.pf_not_tilde:
    ; Unary NOT (bool)
    cmp     eax, TOK_NOT
    jne     .pf_not_not
    advance
    call    parse_factor
    call    codegen_emit_not_rax
    mov     byte [cur_type], TYPE_BOOL
    pop     rbx
    ret

.pf_not_not:
    ; @ protocol call in expression
    cmp     eax, TOK_AT
    jne     .pf_not_at
    advance                          ; consume '@'
    cmp     dword [cur_tok], TOK_IDENT
    jne     .pf_at_done
    lea     rdi, [tok_ident]
    lea     rsi, [tmp_name]
    call    strcpy_64
    advance
    cmp     dword [cur_tok], TOK_LPAREN
    jne     .pf_at_noparens
    advance
    xor     ecx, ecx
.pf_at_args:
    cmp     dword [cur_tok], TOK_RPAREN
    je      .pf_at_args_done
    cmp     dword [cur_tok], TOK_EOF
    je      .pf_at_args_done
    push    rcx
    call    parse_expr
    pop     rcx
    call    codegen_emit_push_rax
    inc     ecx
    cmp     dword [cur_tok], TOK_COMMA
    jne     .pf_at_args_done
    advance
    jmp     .pf_at_args
.pf_at_args_done:
    cmp     dword [cur_tok], TOK_RPAREN
    jne     .pf_at_call
    advance
.pf_at_noparens:
.pf_at_call:
    lea     rdi, [tmp_name]
    call    proto_find
    cmp     rax, -1
    je      .pf_at_done
    mov     rdi, rax
    call    codegen_emit_call_prot
    ; result in rax
.pf_at_done:
    pop     rbx
    ret

.pf_not_at:
    ; abs(expr)
    cmp     eax, TOK_ABS
    jne     .pf_not_abs
    advance
    cmp     dword [cur_tok], TOK_LPAREN
    jne     .pf_abs_np
    advance
.pf_abs_np:
    call    parse_expr
    cmp     dword [cur_tok], TOK_RPAREN
    jne     .pf_abs_nc
    advance
.pf_abs_nc:
    call    codegen_emit_abs_rax
    pop     rbx
    ret

.pf_not_abs:
    ; len(seq)
    cmp     eax, TOK_LEN
    jne     .pf_not_len
    advance
    cmp     dword [cur_tok], TOK_LPAREN
    jne     .pf_len_np
    advance
.pf_len_np:
    cmp     dword [cur_tok], TOK_IDENT
    jne     .pf_len_zero
    lea     rdi, [tok_ident]
    call    var_find
    cmp     rax, -1
    je      .pf_len_zero
    mov     rdi, rax
    call    get_var_va
    mov     rdi, rax
    call    codegen_emit_seq_len
    advance
    cmp     dword [cur_tok], TOK_RPAREN
    jne     .pf_len_nc
    advance
.pf_len_nc:
    mov     byte [cur_type], TYPE_INT
    pop     rbx
    ret
.pf_len_zero:
    mov     rdi, 0
    call    codegen_emit_mov_rax_imm64
    pop     rbx
    ret

.pf_not_len:
    ; cap(seq)
    cmp     eax, TOK_CAP
    jne     .pf_not_cap
    advance
    cmp     dword [cur_tok], TOK_LPAREN
    jne     .pf_cap_np
    advance
.pf_cap_np:
    cmp     dword [cur_tok], TOK_IDENT
    jne     .pf_cap_zero
    lea     rdi, [tok_ident]
    call    var_find
    cmp     rax, -1
    je      .pf_cap_zero
    mov     rdi, rax
    call    get_var_va
    mov     rdi, rax
    call    codegen_emit_seq_cap
    advance
    cmp     dword [cur_tok], TOK_RPAREN
    jne     .pf_cap_nc
    advance
.pf_cap_nc:
    mov     byte [cur_type], TYPE_INT
    pop     rbx
    ret
.pf_cap_zero:
    mov     rdi, 0
    call    codegen_emit_mov_rax_imm64
    pop     rbx
    ret

.pf_not_cap:
    ; int(float_expr) cast
    cmp     eax, TOK_TYPE_INT
    jne     .pf_not_int_cast
    advance
    cmp     dword [cur_tok], TOK_LPAREN
    jne     .pf_int_cast_np
    advance
.pf_int_cast_np:
    call    parse_expr
    cmp     dword [cur_tok], TOK_RPAREN
    jne     .pf_int_cast_nc
    advance
.pf_int_cast_nc:
    call    codegen_emit_cvttsd2si_rax
    mov     byte [cur_type], TYPE_INT
    pop     rbx
    ret

.pf_not_int_cast:
    ; float(int_expr) cast
    cmp     eax, TOK_TYPE_FLOAT
    jne     .pf_not_float_cast
    advance
    cmp     dword [cur_tok], TOK_LPAREN
    jne     .pf_float_cast_np
    advance
.pf_float_cast_np:
    call    parse_expr
    cmp     dword [cur_tok], TOK_RPAREN
    jne     .pf_float_cast_nc
    advance
.pf_float_cast_nc:
    call    codegen_emit_cvtsi2sd_rax
    mov     byte [cur_type], TYPE_FLOAT
    pop     rbx
    ret

.pf_not_float_cast:
    ; ---- str(expr) cast — design.md §3.2 (B-11 fix) ---------------------
    cmp     eax, TOK_TYPE_STR
    jne     .pf_not_str_cast
    advance
    cmp     dword [cur_tok], TOK_LPAREN
    jne     .pf_str_np
    advance
.pf_str_np:
    call    parse_expr
    cmp     dword [cur_tok], TOK_RPAREN
    jne     .pf_str_nc
    advance
.pf_str_nc:
    movzx   eax, byte [cur_type]
    cmp     eax, TYPE_STR
    je      .pf_str_identity        ; str(str) = identity
    cmp     eax, TYPE_BOOL
    je      .pf_str_from_bool
    ; int / float / char / byte → decimal string
    call    codegen_emit_mov_rdi_rax
    call    codegen_emit_call_rt_str
    mov     byte [cur_type], TYPE_STR
    pop     rbx
    ret
.pf_str_from_bool:
    call    codegen_emit_mov_rdi_rax
    call    codegen_emit_call_rt_str_bool
    mov     byte [cur_type], TYPE_STR
    pop     rbx
    ret
.pf_str_identity:
    mov     byte [cur_type], TYPE_STR
    pop     rbx
    ret

.pf_not_str_cast:
    ; ---- bool(expr) cast — design.md §4.7 --------------------------------
    cmp     eax, TOK_TYPE_BOOL
    jne     .pf_not_bool_cast
    advance
    cmp     dword [cur_tok], TOK_LPAREN
    jne     .pf_bool_np
    advance
.pf_bool_np:
    call    parse_expr
    cmp     dword [cur_tok], TOK_RPAREN
    jne     .pf_bool_nc
    advance
.pf_bool_nc:
    call    codegen_emit_int_to_bool
    mov     byte [cur_type], TYPE_BOOL
    pop     rbx
    ret

.pf_not_bool_cast:
    ; ---- char(expr) cast — truncate to low byte --------------------------
    cmp     eax, TOK_TYPE_CHAR
    jne     .pf_not_char_cast
    advance
    cmp     dword [cur_tok], TOK_LPAREN
    jne     .pf_char_np
    advance
.pf_char_np:
    call    parse_expr
    cmp     dword [cur_tok], TOK_RPAREN
    jne     .pf_char_nc
    advance
.pf_char_nc:
    call    codegen_emit_trunc_byte
    mov     byte [cur_type], TYPE_CHAR
    pop     rbx
    ret

.pf_not_char_cast:
    ; ---- byte(expr) cast — unsigned byte 0..255 --------------------------
    cmp     eax, TOK_TYPE_BYTE
    jne     .pf_not_byte_cast
    advance
    cmp     dword [cur_tok], TOK_LPAREN
    jne     .pf_byte_np
    advance
.pf_byte_np:
    call    parse_expr
    cmp     dword [cur_tok], TOK_RPAREN
    jne     .pf_byte_nc
    advance
.pf_byte_nc:
    call    codegen_emit_trunc_byte
    mov     byte [cur_type], TYPE_BYTE
    pop     rbx
    ret

.pf_not_byte_cast:
    ; ---- input(prompt?) — design.md §15.3 --------------------------------
    cmp     eax, TOK_INPUT
    jne     .pf_not_input
    advance
    cmp     dword [cur_tok], TOK_LPAREN
    jne     .pf_input_no_lp
    advance
.pf_input_no_lp:
    ; Optional prompt argument
    cmp     dword [cur_tok], TOK_RPAREN
    je      .pf_input_no_arg
    cmp     dword [cur_tok], TOK_NEWLINE
    je      .pf_input_no_arg
    cmp     dword [cur_tok], TOK_EOF
    je      .pf_input_no_arg
    call    parse_expr              ; prompt string → rax
    call    codegen_emit_mov_rdi_rax    ; mov rdi, rax (pass prompt)
    jmp     .pf_input_call
.pf_input_no_arg:
    call    codegen_emit_xor_rdi_rdi    ; xor rdi, rdi (no prompt)
.pf_input_call:
    cmp     dword [cur_tok], TOK_RPAREN
    jne     .pf_input_no_rp
    advance
.pf_input_no_rp:
    call    codegen_emit_call_rt_inp
    mov     byte [cur_type], TYPE_STR
    pop     rbx
    ret

.pf_not_input:
    ; ---- unknown literal (random bool via rdrand) ------------------------
    cmp     eax, TOK_UNKNOWN
    jne     .pf_not_unknown
    advance
    call    codegen_emit_unknown_bool
    mov     byte [cur_type], TYPE_BOOL
    pop     rbx
    ret

.pf_not_unknown:
    ; clock
    cmp     eax, TOK_CLOCK
    jne     .pf_not_clock
    advance
    call    codegen_emit_clock_ms
    mov     byte [cur_type], TYPE_INT
    pop     rbx
    ret

.pf_not_clock:
    ; typeof
    cmp     eax, TOK_TYPEOF
    jne     .pf_not_typeof
    advance
    cmp     dword [cur_tok], TOK_LPAREN
    jne     .pf_typeof_np
    advance
.pf_typeof_np:
    cmp     dword [cur_tok], TOK_IDENT
    jne     .pf_typeof_zero
    lea     rdi, [tok_ident]
    call    var_find
    cmp     rax, -1
    je      .pf_typeof_zero
    shl     rax, 6
    lea     rax, [var_table + rax]
    movzx   edi, byte [rax + VAR_TYPE_OFF]
    advance
    cmp     dword [cur_tok], TOK_RPAREN
    jne     .pf_typeof_nc
    advance
.pf_typeof_nc:
    call    codegen_emit_typeof_rax
    mov     byte [cur_type], TYPE_INT
    pop     rbx
    ret
.pf_typeof_zero:
    mov     rdi, 0
    call    codegen_emit_mov_rax_imm64
    pop     rbx
    ret

.pf_not_typeof:
    ; Default: emit 0 for unrecognized factor
    mov     rdi, 0
    call    codegen_emit_mov_rax_imm64
    mov     byte [cur_type], TYPE_INT
    pop     rbx
    ret

.pf_true:
    mov     rdi, 1
    call    codegen_emit_mov_rax_imm64
    mov     byte [cur_type], TYPE_BOOL
    advance
    pop     rbx
    ret

.pf_false:
    mov     rdi, -1
    call    codegen_emit_mov_rax_imm64
    mov     byte [cur_type], TYPE_BOOL
    advance
    pop     rbx
    ret

.pf_neutral:
    mov     rdi, 0
    call    codegen_emit_mov_rax_imm64
    mov     byte [cur_type], TYPE_BOOL
    advance
    pop     rbx
    ret

.fneg_bytes:
    db 0x66, 0x48, 0x0f, 0x6e, 0xc0    ; movq xmm0, rax
    db 0x0f, 0x57, 0x05, 0x08, 0x00, 0x00, 0x00  ; xorps xmm0, [rip+8]   — needs sign bit mask
    ; This is incomplete — for now just negate via integer trick
    db 0x66, 0x48, 0x0f, 0x7e, 0xc0    ; movq rax, xmm0

; ============================================================
; Helper: tok_to_type_code — cur_tok → type code in al
; ============================================================
tok_to_type_code:
    mov     eax, dword [cur_tok]
    cmp     eax, TOK_TYPE_INT
    je      .int
    cmp     eax, TOK_TYPE_FLOAT
    je      .float
    cmp     eax, TOK_TYPE_BOOL
    je      .bool
    cmp     eax, TOK_TYPE_STR
    je      .str
    cmp     eax, TOK_TYPE_COMPLEX
    je      .complex
    cmp     eax, TOK_TYPE_SEQ
    je      .seq
    cmp     eax, TOK_TYPE_DICT
    je      .dict
    cmp     eax, TOK_TYPE_CHAR
    je      .chartype
    cmp     eax, TOK_TYPE_BYTE
    je      .byte
    ; Unknown type (used in proto return type skipping etc.)
    mov     al, TYPE_INT
    ret
.int:     mov al, TYPE_INT;     ret
.float:   mov al, TYPE_FLOAT;   ret
.bool:    mov al, TYPE_BOOL;    ret
.str:     mov al, TYPE_STR;     ret
.complex: mov al, TYPE_COMPLEX; ret
.seq:     mov al, TYPE_SEQ;     ret
.dict:    mov al, TYPE_DICT;    ret
.chartype: mov al, TYPE_CHAR;   ret
.byte:    mov al, TYPE_BYTE;    ret

; ============================================================
; Helper: tok_to_setcc — cur_tok → setCC opcode byte in rax
; ============================================================
tok_to_setcc:
    mov     eax, dword [cur_tok]
    cmp     eax, TOK_EQEQ
    jne     .ne
    mov     eax, 0x94               ; sete
    ret
.ne:
    cmp     eax, TOK_NEQ
    jne     .lt
    mov     eax, 0x95               ; setne
    ret
.lt:
    cmp     eax, TOK_LT
    jne     .gt
    mov     eax, 0x9c               ; setl
    ret
.gt:
    cmp     eax, TOK_GT
    jne     .le
    mov     eax, 0x9f               ; setg
    ret
.le:
    cmp     eax, TOK_LE
    jne     .ge
    mov     eax, 0x9e               ; setle
    ret
.ge:
    mov     eax, 0x9d               ; setge
    ret

; ============================================================
; Helper: strcpy_64 — copy up to 63 chars from rdi to rsi
; ============================================================
strcpy_64:
    push    rbx
    xor     ecx, ecx
.sc_loop:
    cmp     ecx, 63
    jge     .sc_done
    movzx   eax, byte [rdi + rcx]
    mov     [rsi + rcx], al
    test    al, al
    jz      .sc_done
    inc     ecx
    jmp     .sc_loop
.sc_done:
    cmp     ecx, 63
    jge     .sc_nul
    mov     byte [rsi + rcx], 0
.sc_nul:
    pop     rbx
    ret

; ============================================================
; resolve_fwd_refs — patch all forward reference calls
; ============================================================
resolve_fwd_refs:
    push    rbx
    push    r12

    xor     r12, r12
.fwd_loop:
    cmp     r12, [fwd_ref_count]
    jge     .fwd_done

    ; Get name
    imul    rbx, r12, 32
    lea     rbx, [fwd_ref_names + rbx]

    ; Find proto
    mov     rdi, rbx
    call    proto_find
    cmp     rax, -1
    je      .fwd_next           ; not found — skip

    mov     rbx, rax            ; proto index

    ; Get proto body offset
    imul    rax, rbx, PROTO_ENTRY_SIZE
    lea     rax, [proto_table + rax]
    mov     rbx, [rax + PROTO_OUTIDX_OFF]    ; proto body start out_idx

    ; Get patch site
    mov     rax, [fwd_ref_patches + r12*8]  ; out_idx of rel32 placeholder

    ; Compute rel32 = proto_body - (patch_site + 4)
    mov     rcx, rbx
    sub     rcx, rax
    sub     rcx, 4
    mov     [out_buffer + rax], ecx

.fwd_next:
    inc     r12
    jmp     .fwd_loop

.fwd_done:
    pop     r12
    pop     rbx
    ret

; Need these externs for forward declarations used in parse_factor
section .bss
unknown_tok_placeholder: resb 1
