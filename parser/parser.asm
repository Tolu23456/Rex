default rel
%include "include/rex_defs.inc"
global parse_stmt, parse_expr
extern lexer_init, lexer_next, tok_type, tok_int, tok_ident
extern codegen_output_const, codegen_output_typed
extern codegen_patch_jump, codegen_save_chain_base, codegen_emit_jmp_end, codegen_patch_chain_end
extern codegen_begin_protos, codegen_end_protos
extern codegen_emit_for_start, codegen_emit_for_end
extern codegen_emit_while_start, codegen_emit_while_end
extern codegen_emit_break, codegen_patch_breaks, codegen_emit_loop_base
extern codegen_emit_ret, codegen_emit_mov_eax_imm32, codegen_emit_call_prot
extern codegen_emit_assign_var, codegen_emit_cmp_var_jne, codegen_emit_unknown_bool
extern codegen_emit_mm_switch, codegen_emit_gc_switch, out_idx
extern codegen_emit_test_rax_jnz, codegen_emit_normalize_bool_rax
extern codegen_emit_jmp_get_slot, codegen_patch_slot_to_here
extern codegen_emit_push_rax, codegen_emit_pop_rbx
extern codegen_emit_mov_rax_var, codegen_emit_store_rax_to_var
extern codegen_emit_rdrand_rax, codegen_emit_neg_rax, codegen_emit_not_rax
extern codegen_emit_bitwise_not_rax
extern codegen_emit_add_rax_rbx, codegen_emit_sub_rax_rbx
extern codegen_emit_imul_rax_rbx, codegen_emit_idiv_rbx_by_rax, codegen_emit_imod_rbx_by_rax
extern codegen_emit_cmp_rbx_rax_setcc, codegen_emit_test_rax_jz
extern codegen_output_rax
extern codegen_emit_addsd_rax_rbx, codegen_emit_subsd_rax_rbx
extern codegen_emit_mulsd_rax_rbx, codegen_emit_divsd_rax_rbx
extern codegen_emit_cvttsd2si_rax, codegen_emit_cvtsi2sd_rax
extern codegen_emit_bitwise_and_rax_rbx, codegen_emit_bitwise_or_rax_rbx
extern codegen_emit_bitwise_xor_rax_rbx
extern codegen_emit_and_bool_rax_rbx, codegen_emit_or_bool_rax_rbx
extern codegen_emit_shl_rax_by_rbx, codegen_emit_shr_rax_by_rbx
extern codegen_emit_str_rax
extern codegen_emit_seq_alloc, codegen_emit_seq_push, codegen_emit_seq_pop_rax
extern codegen_emit_seq_len_rax
extern codegen_emit_mov_rdi_rax, codegen_emit_call_rt_err
extern codegen_emit_for_start_dyn, codegen_emit_arg_pops
extern codegen_push_cont, codegen_pop_cont, codegen_emit_skip
extern codegen_emit_b_raw, codegen_emit_d_raw, codegen_get_var_va_proxy
extern codegen_emit_inc_var, codegen_emit_dec_var
extern codegen_emit_swap_vars
extern codegen_emit_abs_rax
extern codegen_emit_cap_rax
extern codegen_set_for_step
section .bss
var_table:       resb VAR_ENTRY_SIZE * VAR_MAX
var_count:       resq 1
proto_table:     resb PROTO_ENTRY_SIZE * 32
proto_count:     resq 1
prot_body_depth: resq 1
saved_name:      resb 64
for_end_name:    resb 64
cur_type:        resb 1
scope_stack:     resq 32
scope_depth:     resq 1
cur_proto_idx:   resq 1
proto_ret_type:  resb 1
when_var_idx:    resq 1
when_case_count: resq 1
when_var_stack:  resq 8
when_cnt_stack:  resq 8
when_stk_depth:  resq 1
decl_mutable:    resb 1
section .data
err_id:    db "error: expected identifier",10
err_id_l   equ $ - err_id
fe_suffix: db "_fe",0
when_tmp:  db "__when__",0
section .text

; ── string helpers ────────────────────────────────────────────────────────────
strcpy:
    push rbp
    mov rbp, rsp
    push rsi
    push rdi
.l:
    movzx eax, byte [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .l
    pop rdi
    pop rsi
    leave
    ret

strlen_local:
    push rbx
    mov rbx, rdi
    xor rax, rax
.l:
    cmp byte [rbx+rax], 0
    je .d
    inc rax
    jmp .l
.d:
    pop rbx
    ret

strcat_local:
    push rbp
    mov rbp, rsp
    push rbx
    push rdx
    mov rbx, rdi
.f:
    cmp byte [rbx], 0
    je .a
    inc rbx
    jmp .f
.a:
    movzx edx, byte [rsi]
    mov [rbx], dl
    inc rbx
    inc rsi
    test dl, dl
    jnz .a
    pop rdx
    pop rbx
    leave
    ret

fatal:
    push rbp
    mov rbp, rsp
    mov r9, rdx
    mov r8, rsi
    mov rax, 1
    mov rdi, 2
    mov rsi, r8
    mov rdx, r9
    syscall
    mov rax, 60
    mov rdi, 1
    syscall

; ── variable table ────────────────────────────────────────────────────────────
var_find:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rsi
    push rdi            ; original rdi saved at [rbp-32]
    xor rcx, rcx
.l:
    cmp rcx, [var_count]
    jge .nf
    mov rax, rcx
    imul rax, VAR_ENTRY_SIZE
    lea rsi, [var_table]
    add rsi, rax
    mov rdi, [rbp-32]
.c:
    movzx eax, byte [rdi]
    movzx edx, byte [rsi]
    cmp al, dl
    jne .nx
    test al, al
    jz .match
    inc rdi
    inc rsi
    jmp .c
.match:
    mov rax, rcx
    jmp .done
.nx:
    inc rcx
    jmp .l
.nf:
    mov rax, -1
.done:
    pop rdi
    pop rsi
    pop rcx
    pop rbx
    leave
    ret

var_add:
    ; rdi=name rsi=value dl=is_init cl=type → rax=idx (-1=full)
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14b, dl
    mov r15b, cl
    mov rbx, [var_count]
    cmp rbx, VAR_MAX
    jge .full
    mov rax, rbx
    imul rax, VAR_ENTRY_SIZE
    lea rdi, [var_table]
    add rdi, rax
    push rdi
    mov ecx, VAR_ENTRY_SIZE/4
    xor eax, eax
    cld
    rep stosd
    pop rdi
    mov rsi, r12
    call strcpy
    mov rax, rbx
    imul rax, VAR_ENTRY_SIZE
    lea rdi, [var_table]
    add rdi, rax
    mov [rdi+32], r13
    mov byte [rdi+40], r14b
    mov byte [rdi+48], r15b
    inc qword [var_count]
    mov rax, rbx
    jmp .done
.full:
    mov rax, -1
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

; ── expression parser ─────────────────────────────────────────────────────────
parse_factor:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    movzx eax, byte [tok_type]
    cmp al, TOK_INT_LIT
    je .int
    cmp al, TOK_FLOAT_LIT
    je .flt
    cmp al, TOK_TRUE
    je .tru
    cmp al, TOK_FALSE
    je .fls
    cmp al, TOK_UNKNOWN
    je .unk
    cmp al, TOK_STR_LIT
    je .str
    cmp al, TOK_IDENT
    je .idn
    cmp al, TOK_LPAREN
    je .par
    cmp al, TOK_AT
    je .prt
    cmp al, TOK_MINUS
    je .neg
    cmp al, TOK_NOT
    je .lnot
    cmp al, TOK_TILDE
    je .bnot
    cmp al, TOK_TYPE_INT
    je .casti
    cmp al, TOK_TYPE_FLOAT
    je .castf
    cmp al, TOK_LEN
    je .lenx
    cmp al, TOK_POP
    je .popx
    cmp al, TOK_ABS
    je .absx
    cmp al, TOK_CAP
    je .capx
    ; default: zero + advance past unknown token (#35)
    call lexer_next
    mov rdi, 0
    call codegen_emit_mov_eax_imm32
    mov byte [cur_type], TYPE_INT
    jmp .done
.int:
    mov rdi, [tok_int]
    call codegen_emit_mov_eax_imm32
    mov byte [cur_type], TYPE_INT
    call lexer_next
    jmp .done
.flt:
    mov rdi, [tok_int]
    call codegen_emit_mov_eax_imm32
    mov byte [cur_type], TYPE_FLOAT
    call lexer_next
    jmp .done
.tru:
    mov rdi, 1
    call codegen_emit_mov_eax_imm32
    mov byte [cur_type], TYPE_BOOL
    call lexer_next
    jmp .done
.fls:
    mov rdi, 0
    call codegen_emit_mov_eax_imm32
    mov byte [cur_type], TYPE_BOOL
    call lexer_next
    jmp .done
.unk:
    call codegen_emit_rdrand_rax
    mov byte [cur_type], TYPE_BOOL
    call lexer_next
    jmp .done
.str:
    sub rsp, 64
    mov rdi, rsp
    lea rsi, [tok_ident]
    call strcpy
    mov rdi, rsp
    call strlen_local
    mov rsi, rax
    mov rdi, rsp
    call codegen_emit_str_rax
    add rsp, 64
    mov byte [cur_type], TYPE_STR
    call lexer_next
    jmp .done
.idn:
    sub rsp, 64
    mov rdi, rsp
    lea rsi, [tok_ident]
    call strcpy
    mov rdi, rsp
    call var_find
    add rsp, 64
    cmp rax, -1
    je .idn_skip
    push rax
    mov rbx, rax
    imul rbx, rbx, VAR_ENTRY_SIZE
    lea rcx, [var_table]
    add rcx, rbx
    movzx r12d, byte [rcx+48]
    pop rdi
    call codegen_emit_mov_rax_var
    mov byte [cur_type], r12b
    call lexer_next
    jmp .done
.idn_skip:
    mov rdi, 0
    call codegen_emit_mov_eax_imm32
    mov byte [cur_type], TYPE_INT
    call lexer_next
    jmp .done
.par:
    call lexer_next
    call parse_expr
    cmp byte [tok_type], TOK_RPAREN
    jne .done
    call lexer_next
    jmp .done
.prt:
    call lexer_next
    lea rdi, [tok_ident]
    call proto_find
    cmp rax, -1
    je .prt_skip
    mov r12, rax
    call lexer_next
    cmp byte [tok_type], TOK_LPAREN
    jne .prt_call
    call lexer_next
    xor r13, r13
.prt_al:
    cmp byte [tok_type], TOK_RPAREN
    je .prt_ad
    cmp byte [tok_type], TOK_EOF
    je .prt_ad
    cmp byte [tok_type], TOK_NEWLINE
    je .prt_ad
    call parse_expr
    call codegen_emit_push_rax
    inc r13
    cmp byte [tok_type], TOK_COMMA
    jne .prt_ad
    call lexer_next
    jmp .prt_al
.prt_ad:
    cmp byte [tok_type], TOK_RPAREN
    jne .prt_np
    call lexer_next
.prt_np:
    mov rdi, r13
    call codegen_emit_arg_pops
    jmp .prt_call
.prt_call:
    cmp byte [tok_type], TOK_LPAREN
    jne .prt_do
    call lexer_next
    cmp byte [tok_type], TOK_RPAREN
    jne .prt_do
    call lexer_next
.prt_do:
    mov rdi, r12
    call codegen_emit_call_prot
    movzx ecx, byte [proto_ret_type]
    test cl, cl
    jz .prt_default_type
    mov byte [cur_type], cl
    jmp .done
.prt_default_type:
    mov byte [cur_type], TYPE_INT
    jmp .done
.prt_skip:
    mov rdi, 0
    call codegen_emit_mov_eax_imm32
    mov byte [cur_type], TYPE_INT
    call lexer_next
    jmp .done
.neg:
    call lexer_next
    call parse_factor
    call codegen_emit_neg_rax
    jmp .done
.lnot:
    call lexer_next
    call parse_factor
    call codegen_emit_not_rax
    mov byte [cur_type], TYPE_BOOL
    jmp .done
.bnot:
    call lexer_next
    call parse_factor
    call codegen_emit_bitwise_not_rax
    jmp .done
.casti:
    call lexer_next
    cmp byte [tok_type], TOK_LPAREN
    jne .done
    call lexer_next
    call parse_expr
    cmp byte [cur_type], TYPE_FLOAT
    jne .ci_done
    call codegen_emit_cvttsd2si_rax
    mov byte [cur_type], TYPE_INT
.ci_done:
    cmp byte [tok_type], TOK_RPAREN
    jne .done
    call lexer_next
    jmp .done
.castf:
    call lexer_next
    cmp byte [tok_type], TOK_LPAREN
    jne .done
    call lexer_next
    call parse_expr
    cmp byte [cur_type], TYPE_INT
    jne .cf_done
    call codegen_emit_cvtsi2sd_rax
    mov byte [cur_type], TYPE_FLOAT
.cf_done:
    cmp byte [tok_type], TOK_RPAREN
    jne .done
    call lexer_next
    jmp .done
.lenx:
    call lexer_next
    cmp byte [tok_type], TOK_IDENT
    jne .done
    sub rsp, 64
    mov rdi, rsp
    lea rsi, [tok_ident]
    call strcpy
    mov rdi, rsp
    call var_find
    add rsp, 64
    cmp rax, -1
    je .done
    mov rdi, rax
    call codegen_emit_seq_len_rax
    mov byte [cur_type], TYPE_INT
    call lexer_next
    jmp .done
.popx:
    call lexer_next
    cmp byte [tok_type], TOK_IDENT
    jne .done
    sub rsp, 64
    mov rdi, rsp
    lea rsi, [tok_ident]
    call strcpy
    mov rdi, rsp
    call var_find
    add rsp, 64
    cmp rax, -1
    je .done
    mov rdi, rax
    call codegen_emit_seq_pop_rax
    mov byte [cur_type], TYPE_INT
    call lexer_next
    jmp .done
.absx:
    call lexer_next
    cmp byte [tok_type], TOK_LPAREN
    jne .done
    call lexer_next
    call parse_expr
    cmp byte [tok_type], TOK_RPAREN
    jne .abs_done
    call lexer_next
.abs_done:
    call codegen_emit_abs_rax
    jmp .done
.capx:
    call lexer_next
    cmp byte [tok_type], TOK_IDENT
    jne .done
    sub rsp, 64
    mov rdi, rsp
    lea rsi, [tok_ident]
    call strcpy
    mov rdi, rsp
    call var_find
    add rsp, 64
    cmp rax, -1
    je .done
    mov rdi, rax
    call codegen_emit_cap_rax
    mov byte [cur_type], TYPE_INT
    call lexer_next
    jmp .done
.done:
    pop r13
    pop r12
    pop rbx
    leave
    ret

parse_unary:
    push rbp
    mov rbp, rsp
    push rbx
    movzx eax, byte [tok_type]
    cmp al, TOK_MINUS
    je .neg
    cmp al, TOK_NOT
    je .lnot
    cmp al, TOK_TILDE
    je .bnot
    call parse_factor
    jmp .done
.neg:
    call lexer_next
    call parse_factor
    call codegen_emit_neg_rax
    jmp .done
.lnot:
    call lexer_next
    call parse_factor
    call codegen_emit_not_rax
    mov byte [cur_type], TYPE_BOOL
    jmp .done
.bnot:
    call lexer_next
    call parse_factor
    call codegen_emit_bitwise_not_rax
    jmp .done
.done:
    pop rbx
    leave
    ret

parse_term:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    call parse_unary
.loop:
    movzx eax, byte [tok_type]
    cmp al, TOK_STAR
    je .mul
    cmp al, TOK_SLASH
    je .div
    cmp al, TOK_PERCENT
    je .mod
    cmp al, TOK_LSHIFT
    je .shl
    cmp al, TOK_RSHIFT
    je .shr
    jmp .done
.mul:
    movzx r12d, byte [cur_type]
    call lexer_next
    call codegen_emit_push_rax
    call parse_unary
    call codegen_emit_pop_rbx
    cmp r12b, TYPE_FLOAT
    je .mulf
    call codegen_emit_imul_rax_rbx
    mov byte [cur_type], TYPE_INT
    jmp .loop
.mulf:
    call codegen_emit_mulsd_rax_rbx
    mov byte [cur_type], TYPE_FLOAT
    jmp .loop
.div:
    movzx r12d, byte [cur_type]
    call lexer_next
    call codegen_emit_push_rax
    call parse_unary
    call codegen_emit_pop_rbx
    cmp r12b, TYPE_FLOAT
    je .divf
    call codegen_emit_idiv_rbx_by_rax
    mov byte [cur_type], TYPE_INT
    jmp .loop
.divf:
    call codegen_emit_divsd_rax_rbx
    mov byte [cur_type], TYPE_FLOAT
    jmp .loop
.mod:
    call lexer_next
    call codegen_emit_push_rax
    call parse_unary
    call codegen_emit_pop_rbx
    call codegen_emit_imod_rbx_by_rax
    mov byte [cur_type], TYPE_INT
    jmp .loop
.shl:
    call lexer_next
    call codegen_emit_push_rax
    call parse_unary
    call codegen_emit_pop_rbx
    call codegen_emit_shl_rax_by_rbx
    mov byte [cur_type], TYPE_INT
    jmp .loop
.shr:
    call lexer_next
    call codegen_emit_push_rax
    call parse_unary
    call codegen_emit_pop_rbx
    call codegen_emit_shr_rax_by_rbx
    mov byte [cur_type], TYPE_INT
    jmp .loop
.done:
    pop r12
    pop rbx
    leave
    ret

parse_additive:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    call parse_term
.loop:
    movzx eax, byte [tok_type]
    cmp al, TOK_PLUS
    je .add
    cmp al, TOK_MINUS
    je .sub
    cmp al, TOK_AMP
    je .band
    cmp al, TOK_PIPE
    je .bor
    cmp al, TOK_CARET
    je .bxor
    jmp .done
.add:
    movzx r12d, byte [cur_type]
    call lexer_next
    call codegen_emit_push_rax
    call parse_term
    call codegen_emit_pop_rbx
    cmp r12b, TYPE_FLOAT
    je .addf
    call codegen_emit_add_rax_rbx
    mov byte [cur_type], TYPE_INT
    jmp .loop
.addf:
    call codegen_emit_addsd_rax_rbx
    mov byte [cur_type], TYPE_FLOAT
    jmp .loop
.sub:
    movzx r12d, byte [cur_type]
    call lexer_next
    call codegen_emit_push_rax
    call parse_term
    call codegen_emit_pop_rbx
    cmp r12b, TYPE_FLOAT
    je .subf
    call codegen_emit_sub_rax_rbx
    mov byte [cur_type], TYPE_INT
    jmp .loop
.subf:
    call codegen_emit_subsd_rax_rbx
    mov byte [cur_type], TYPE_FLOAT
    jmp .loop
.band:
    call lexer_next
    call codegen_emit_push_rax
    call parse_term
    call codegen_emit_pop_rbx
    call codegen_emit_bitwise_and_rax_rbx
    mov byte [cur_type], TYPE_INT
    jmp .loop
.bor:
    call lexer_next
    call codegen_emit_push_rax
    call parse_term
    call codegen_emit_pop_rbx
    call codegen_emit_bitwise_or_rax_rbx
    mov byte [cur_type], TYPE_INT
    jmp .loop
.bxor:
    call lexer_next
    call codegen_emit_push_rax
    call parse_term
    call codegen_emit_pop_rbx
    call codegen_emit_bitwise_xor_rax_rbx
    mov byte [cur_type], TYPE_INT
    jmp .loop
.done:
    pop r12
    pop rbx
    leave
    ret

parse_comparison:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    call parse_additive
    movzx eax, byte [tok_type]
    cmp al, TOK_EQEQ
    je .eq
    cmp al, TOK_NEQ
    je .ne
    cmp al, TOK_LT
    je .lt
    cmp al, TOK_GT
    je .gt
    cmp al, TOK_LTE
    je .le
    cmp al, TOK_GTE
    je .ge
    jmp .done
.eq:
    mov r12b, 0x94
    jmp .op
.ne:
    mov r12b, 0x95
    jmp .op
.lt:
    mov r12b, 0x9C
    jmp .op
.gt:
    mov r12b, 0x9F
    jmp .op
.le:
    mov r12b, 0x9E
    jmp .op
.ge:
    mov r12b, 0x9D
.op:
    call lexer_next
    call codegen_emit_push_rax
    call parse_additive
    call codegen_emit_pop_rbx
    movzx rdi, r12b
    call codegen_emit_cmp_rbx_rax_setcc
    mov byte [cur_type], TYPE_BOOL
.done:
    pop r12
    pop rbx
    leave
    ret

parse_expr:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    call parse_comparison
.loop:
    movzx eax, byte [tok_type]
    cmp al, TOK_AND
    je .land
    cmp al, TOK_OR
    je .lor
    jmp .done
.land:
    ; short-circuit and (#33): if LHS false → skip RHS, result = false
    call codegen_emit_test_rax_jz   ; emit test+jz; push J1 on jump_patch_stack
    call lexer_next
    call parse_comparison           ; RHS → rax
    call codegen_emit_normalize_bool_rax
    call codegen_emit_jmp_get_slot  ; emit jmp .end_and; rax = J2 patch slot
    mov r12, rax                    ; save J2 slot
    call codegen_patch_jump         ; patch J1 (jz) → here (.false_path)
    mov rdi, 0
    call codegen_emit_mov_eax_imm32 ; false path: xor eax,eax
    mov rdi, r12
    call codegen_patch_slot_to_here ; patch J2 → here (.end_and)
    mov byte [cur_type], TYPE_BOOL
    jmp .loop
.lor:
    ; short-circuit or (#33): if LHS true → skip RHS, result = true
    call codegen_emit_test_rax_jnz  ; emit test+jnz; push J1 on jump_patch_stack
    call lexer_next
    call parse_comparison           ; RHS → rax
    call codegen_emit_normalize_bool_rax
    call codegen_emit_jmp_get_slot  ; emit jmp .end_or; rax = J2 patch slot
    mov r12, rax                    ; save J2 slot
    call codegen_patch_jump         ; patch J1 (jnz) → here (.true_path)
    mov rdi, 1
    call codegen_emit_mov_eax_imm32 ; true path: mov eax,1
    mov rdi, r12
    call codegen_patch_slot_to_here ; patch J2 → here (.end_or)
    mov byte [cur_type], TYPE_BOOL
    jmp .loop
.done:
    pop r12
    pop rbx
    leave
    ret

; ── proto_find ────────────────────────────────────────────────────────────────
proto_find:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push rbx
    mov r12, rdi
    xor r13, r13
.l:
    cmp r13, [proto_count]
    jge .nf
    mov rax, r13
    imul rax, PROTO_ENTRY_SIZE
    lea rbx, [proto_table]
    add rbx, rax
    mov rdi, rbx
    mov rsi, r12
    mov ecx, 32
.cl:
    movzx eax, byte [rdi]
    movzx edx, byte [rsi]
    cmp eax, edx
    jne .nm
    test eax, eax
    jz .m
    inc rdi
    inc rsi
    dec ecx
    jnz .cl
.m:
    mov rax, [rbx+32]
    movzx ecx, byte [rbx+47]
    mov [proto_ret_type], cl
    jmp .done
.nm:
    inc r13
    jmp .l
.nf:
    mov rax, -1
.done:
    pop rbx
    pop r13
    pop r12
    leave
    ret

; ── parse_stmt ────────────────────────────────────────────────────────────────
parse_stmt:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    movzx eax, byte [tok_type]
    cmp al, TOK_PROT
    je .s1
    cmp qword [prot_body_depth], 0
    jne .s1
    call codegen_end_protos
    movzx eax, byte [tok_type]
.s1:
    cmp al, TOK_TYPE_INT
    je .pi
    cmp al, TOK_TYPE_FLOAT
    je .pf
    cmp al, TOK_TYPE_BOOL
    je .pb
    cmp al, TOK_TYPE_STR
    je .ps
    cmp al, TOK_TYPE_COMPLEX
    je .pc
    cmp al, TOK_TYPE_SEQ
    je .pq
    cmp al, TOK_COLON
    je .assign
    cmp al, TOK_OUTPUT
    je .out
    cmp al, TOK_IF
    je .if
    cmp al, TOK_FOR
    je .for
    cmp al, TOK_WHILE
    je .while
    cmp al, TOK_PROT
    je .prot
    cmp al, TOK_RETURN
    je .ret
    cmp al, TOK_STOP
    je .stop
    cmp al, TOK_SKIP
    je .skip
    cmp al, TOK_PASS
    je .pass
    cmp al, TOK_AT
    je .at
    cmp al, TOK_USE
    je .use
    cmp al, TOK_ERR
    je .err_stmt
    cmp al, TOK_PUSH
    je .push_stmt
    cmp al, TOK_PLUSPLUS
    je .incr_stmt
    cmp al, TOK_MINUSMINUS
    je .decr_stmt
    cmp al, TOK_SWAP
    je .swap_stmt
    cmp al, TOK_WHEN
    je .when
    call lexer_next
    jmp .done

; ── type declarations ──────────────────────────────────────────────────────────
.pf:
    mov r15b, TYPE_FLOAT
    jmp .pg
.pb:
    mov r15b, TYPE_BOOL
    jmp .pg
.ps:
    mov r15b, TYPE_STR
    jmp .pg
.pc:
    mov r15b, TYPE_COMPLEX
    jmp .pg
.pi:
    mov r15b, TYPE_INT
.pg:
    mov byte [decl_mutable], 0
    call lexer_next
    cmp byte [tok_type], TOK_COLON
    jne .pg_name
    mov byte [decl_mutable], 1
    call lexer_next
.pg_name:
    cmp byte [tok_type], TOK_IDENT
    jne .err
    lea rsi, [tok_ident]
    lea rdi, [saved_name]
    call strcpy
    call lexer_next
    cmp byte [tok_type], TOK_ASSIGN
    je .pinit
    lea rdi, [saved_name]
    xor rsi, rsi
    mov dl, 0
    mov cl, r15b
    call var_add
    jmp .done
.pinit:
    call lexer_next
    call parse_expr
    lea rdi, [saved_name]
    xor rsi, rsi
    movzx edx, byte [decl_mutable]
    xor dl, 1
    mov cl, r15b
    call var_add
    cmp rax, -1
    je .done
    mov r14, rax
    mov rdi, r14
    call codegen_emit_store_rax_to_var
    jmp .done
.err:
    lea rsi, [err_id]
    mov rdx, err_id_l
    call fatal

; ── seq declaration: allocates and registers seq variable ──────────────────────
.pq:
    call lexer_next
    cmp byte [tok_type], TOK_IDENT
    jne .done
    lea rsi, [tok_ident]
    lea rdi, [saved_name]
    call strcpy
    call lexer_next
    lea rdi, [saved_name]
    xor rsi, rsi
    mov dl, 0
    mov cl, TYPE_SEQ
    call var_add
    cmp rax, -1
    je .done
    mov r14, rax
    mov rdi, r14
    call codegen_emit_seq_alloc
    jmp .done

; ── assignment :x = expr ──────────────────────────────────────────────────────
.assign:
    call lexer_next
    cmp byte [tok_type], TOK_IDENT
    jne .done
    lea rdi, [saved_name]
    lea rsi, [tok_ident]
    call strcpy
    call lexer_next
    cmp byte [tok_type], TOK_ASSIGN
    jne .done
    call lexer_next
    lea rdi, [saved_name]
    call var_find
    cmp rax, -1
    je .done
    mov r14, rax
    call parse_expr
    mov rdi, r14
    call codegen_emit_store_rax_to_var
    jmp .done

; ── output expr ───────────────────────────────────────────────────────────────
.out:
    call lexer_next
    cmp byte [tok_type], TOK_LPAREN
    jne .out_nopar
    call lexer_next
    call parse_expr
    cmp byte [tok_type], TOK_RPAREN
    jne .out_emit
    call lexer_next
    jmp .out_emit
.out_nopar:
    call parse_expr
.out_emit:
    movzx edi, byte [cur_type]
    call codegen_output_rax
    jmp .done

; ── if / elif / else ──────────────────────────────────────────────────────────
.if:
    call codegen_save_chain_base
.ifn:
    call lexer_next
    call parse_expr
    call codegen_emit_test_rax_jz
    call lexer_next
    cmp byte [tok_type], TOK_NEWLINE
    jne .ifnn
    call lexer_next
.ifnn:
    cmp byte [tok_type], TOK_INDENT
    jne .ifb
    call lexer_next
    mov r13, 1
    jmp .ifbl
.ifb:
    xor r13, r13
.ifbl:
    movzx eax, byte [tok_type]
    cmp al, TOK_EOF
    je .ifen
    cmp al, TOK_DEDENT
    je .ifen
    call parse_stmt
    test r13, r13
    jnz .ifbl
.ifen:
    test r13, r13
    jz .ifad
    cmp byte [tok_type], TOK_DEDENT
    jne .ifad
    call lexer_next
.ifad:
    movzx eax, byte [tok_type]
    cmp al, TOK_ELIF
    je .elif
    cmp al, TOK_ELSE
    je .else
    call codegen_patch_jump
    call codegen_patch_chain_end
    jmp .done
.elif:
    call codegen_emit_jmp_end
    call codegen_patch_jump
    jmp .ifn
.else:
    call codegen_emit_jmp_end
    call codegen_patch_jump
    call lexer_next
    call lexer_next
    cmp byte [tok_type], TOK_NEWLINE
    jne .elnn
    call lexer_next
.elnn:
    cmp byte [tok_type], TOK_INDENT
    jne .elb
    call lexer_next
    mov r13, 1
    jmp .elbl
.elb:
    xor r13, r13
.elbl:
    movzx eax, byte [tok_type]
    cmp al, TOK_EOF
    je .elen
    cmp al, TOK_DEDENT
    je .elen
    call parse_stmt
    test r13, r13
    jnz .elbl
.elen:
    test r13, r13
    jz .eldo
    cmp byte [tok_type], TOK_DEDENT
    jne .eldo
    call lexer_next
.eldo:
    call codegen_patch_chain_end
    jmp .done

; ── for loop ──────────────────────────────────────────────────────────────────
.for:
    call lexer_next             ; skip 'for' → ':'
    call lexer_next             ; skip ':' → loop var ident
    lea rdi, [saved_name]
    lea rsi, [tok_ident]
    call strcpy
    call lexer_next             ; skip varname → 'in'
    call lexer_next             ; skip 'in' → start expr
    call parse_expr             ; parse start, tok = '..'
    ; save var_count before synthetic loop vars (#37)
    mov rbx, [scope_depth]
    lea rcx, [scope_stack]
    mov rax, [var_count]
    mov [rcx+rbx*8], rax
    inc qword [scope_depth]
    lea rdi, [saved_name]
    xor rsi, rsi
    mov dl, 0
    mov cl, TYPE_INT
    call var_add
    cmp rax, -1
    je .done
    mov r14, rax
    mov rdi, r14
    call codegen_emit_store_rax_to_var
    cmp byte [tok_type], TOK_DOTDOT
    jne .for_nodd
    call lexer_next
.for_nodd:
    call parse_expr             ; parse end expr
    cmp byte [tok_type], TOK_STEP
    jne .for_nostep
    call lexer_next             ; skip 'step'
    cmp byte [tok_type], TOK_INT_LIT
    jne .for_nostep
    mov rdi, [tok_int]
    call codegen_set_for_step
    call lexer_next             ; skip step value
.for_nostep:
    lea rdi, [for_end_name]
    lea rsi, [saved_name]
    call strcpy
    lea rdi, [for_end_name]
    lea rsi, [fe_suffix]
    call strcat_local
    lea rdi, [for_end_name]
    xor rsi, rsi
    mov dl, 0
    mov cl, TYPE_INT
    call var_add
    cmp rax, -1
    je .done
    mov r13, rax
    mov rdi, r13
    call codegen_emit_store_rax_to_var
    mov rdi, r14
    mov rsi, r13
    call codegen_emit_for_start_dyn
    mov r15, rax
    call lexer_next             ; skip ':'
    cmp byte [tok_type], TOK_NEWLINE
    jne .forl_enter
    call lexer_next
.forl_enter:
    cmp byte [tok_type], TOK_INDENT
    jne .forl
    call lexer_next
.forl:
    movzx eax, byte [tok_type]
    cmp al, TOK_EOF
    je .ford
    cmp al, TOK_DEDENT
    je .ford
    call parse_stmt
    jmp .forl
.ford:
    cmp byte [tok_type], TOK_DEDENT
    jne .fornd
    call lexer_next
.fornd:
    mov rdi, r15
    mov rsi, r14
    call codegen_emit_for_end
    ; restore var_count — reclaim synthetic loop vars (#37)
    dec qword [scope_depth]
    mov rax, [scope_depth]
    lea rcx, [scope_stack]
    mov rbx, [rcx+rax*8]
    mov [var_count], rbx
    jmp .done

; ── while loop ────────────────────────────────────────────────────────────────
.while:
    call lexer_next
    mov r15, [out_idx]
    mov rdi, r15
    call codegen_push_cont
    call parse_expr
    call codegen_emit_test_rax_jz
    call codegen_emit_loop_base
    call lexer_next
    cmp byte [tok_type], TOK_NEWLINE
    jne .whl_enter
    call lexer_next
.whl_enter:
    cmp byte [tok_type], TOK_INDENT
    jne .whilel
    call lexer_next
.whilel:
    movzx eax, byte [tok_type]
    cmp al, TOK_EOF
    je .whiled
    cmp al, TOK_DEDENT
    je .whiled
    call parse_stmt
    jmp .whilel
.whiled:
    cmp byte [tok_type], TOK_DEDENT
    jne .whilend
    call lexer_next
.whilend:
    mov rdi, r15
    call codegen_emit_while_end
    jmp .done

; ── protocol definition ────────────────────────────────────────────────────────
.prot:
    inc qword [prot_body_depth]
    call codegen_begin_protos
    call lexer_next
    mov rax, [proto_count]
    imul rax, PROTO_ENTRY_SIZE
    lea r13, [proto_table]
    add r13, rax
    lea rsi, [tok_ident]
    mov rdi, r13
    call strcpy
    mov rbx, [out_idx]
    mov [r13+32], rbx
    mov byte [r13+40], 0
    mov byte [r13+47], 0
    mov rax, [proto_count]
    mov [cur_proto_idx], rax
    inc qword [proto_count]
    call lexer_next
    cmp byte [tok_type], TOK_LPAREN
    jne .prot_nobody
    call lexer_next
    xor r12, r12
.prot_pl:
    cmp byte [tok_type], TOK_RPAREN
    je .prot_pd
    cmp byte [tok_type], TOK_EOF
    je .prot_pd
    cmp byte [tok_type], TOK_NONE
    jne .prot_pl_ident
    call lexer_next
    jmp .prot_pd
.prot_pl_ident:
    cmp byte [tok_type], TOK_IDENT
    jne .prot_pd
    sub rsp, 64
    mov rdi, rsp
    lea rsi, [tok_ident]
    call strcpy
    mov rdi, rsp
    xor rsi, rsi
    mov dl, 0
    mov cl, TYPE_INT
    call var_add
    add rsp, 64
    cmp rax, -1
    jge .prot_pok
    jmp .prot_pd
.prot_pok:
    cmp r12, 5
    jge .prot_pskip
    mov [r13+41+r12], al
.prot_pskip:
    inc r12
    call lexer_next
    cmp byte [tok_type], TOK_COMMA
    jne .prot_pd
    call lexer_next
    jmp .prot_pl
.prot_pd:
    mov [r13+40], r12b
    cmp byte [tok_type], TOK_RPAREN
    jne .prot_nobody
    call lexer_next
    cmp byte [tok_type], TOK_ARROW
    jne .prot_se_init
    call lexer_next
    call lexer_next
.prot_se_init:
    xor r14, r14
.prot_se:
    cmp r14, r12
    jge .prot_nobody
    cmp r14, 6
    jge .prot_nobody
    movzx rbx, byte [r13+41+r14]
    lea rax, [rel .prot_mrm]
    movzx ecx, byte [rax+r14]
    ; choose REX prefix: 0x4C for r8/r9 (params 4,5), 0x48 for rdi/rsi/rdx/rcx
    push rbx
    push rcx
    push r14
    cmp r14, 4
    jge .prot_rex_r
    mov al, 0x48
    jmp .prot_rex_emit
.prot_rex_r:
    mov al, 0x4C
.prot_rex_emit:
    call emit_b_indirect
    mov al, 0x89
    call emit_b_indirect
    pop r14
    pop rcx
    pop rbx
    push rbx
    push r14
    mov al, cl
    call emit_b_indirect
    mov al, 0x25
    call emit_b_indirect
    mov rdi, rbx
    call get_var_va_indirect
    call emit_d_indirect
    pop r14
    pop rbx
    inc r14
    jmp .prot_se
.prot_mrm: db 0x3C, 0x34, 0x14, 0x0C, 0x04, 0x0C

.prot_nobody:
    ; save var_count for protocol-level scoping
    mov rax, [scope_depth]
    lea rcx, [scope_stack]
    mov rbx, [var_count]
    mov [rcx+rax*8], rbx
    inc qword [scope_depth]
    cmp byte [tok_type], TOK_COLON
    jne .prot_skip_nl
    call lexer_next
.prot_skip_nl:
    cmp byte [tok_type], TOK_NEWLINE
    jne .prot_skip_in
    call lexer_next
.prot_skip_in:
    cmp byte [tok_type], TOK_INDENT
    jne .protl
    call lexer_next
.protl:
    movzx eax, byte [tok_type]
    cmp al, TOK_EOF
    je .protd
    cmp al, TOK_DEDENT
    je .protd
    call parse_stmt
    jmp .protl
.protd:
    cmp byte [tok_type], TOK_DEDENT
    jne .protnd
    call lexer_next
.protnd:
    call codegen_emit_ret
    dec qword [prot_body_depth]
    ; restore var_count (protocol scoping)
    dec qword [scope_depth]
    mov rax, [scope_depth]
    lea rcx, [scope_stack]
    mov rbx, [rcx+rax*8]
    mov [var_count], rbx
    jmp .done

; ── return ────────────────────────────────────────────────────────────────────
.ret:
    call lexer_next
    movzx eax, byte [tok_type]
    cmp al, TOK_NEWLINE
    je .ret_bare
    cmp al, TOK_EOF
    je .ret_bare
    cmp al, TOK_DEDENT
    je .ret_bare
    call parse_expr
    ; store return type into current proto entry (B-8 fix)
    mov rax, [cur_proto_idx]
    imul rax, PROTO_ENTRY_SIZE
    lea rbx, [proto_table]
    add rbx, rax
    movzx ecx, byte [cur_type]
    mov [rbx+47], cl
    call codegen_emit_ret
    jmp .done
.ret_bare:
    call codegen_emit_ret
    jmp .done

; ── stop / skip / pass ────────────────────────────────────────────────────────
.stop:
    call codegen_emit_break
    call lexer_next
    jmp .done
.skip:
    call lexer_next             ; skip 'skip' keyword
    xor rdi, rdi                ; default depth=0 (innermost continue, #31)
    cmp byte [tok_type], TOK_INT_LIT
    jne .skip_emit
    mov rdi, [tok_int]
    test rdi, rdi
    jz .skip_emit               ; skip 0 == skip 1 == innermost
    dec rdi                     ; skip 1→depth 0, skip 2→depth 1, etc.
    call lexer_next
.skip_emit:
    call codegen_emit_skip
    jmp .done
.pass:
    call lexer_next
    jmp .done

; ── @prot call (statement) ────────────────────────────────────────────────────
.at:
    call lexer_next
    lea rdi, [tok_ident]
    call proto_find
    cmp rax, -1
    je .done
    mov r12, rax
    call lexer_next
    cmp byte [tok_type], TOK_LPAREN
    jne .at_call
    call lexer_next
    xor r13, r13
.at_al:
    cmp byte [tok_type], TOK_RPAREN
    je .at_ad
    cmp byte [tok_type], TOK_EOF
    je .at_ad
    cmp byte [tok_type], TOK_NEWLINE
    je .at_ad
    call parse_expr
    call codegen_emit_push_rax
    inc r13
    cmp byte [tok_type], TOK_COMMA
    jne .at_ad
    call lexer_next
    jmp .at_al
.at_ad:
    cmp byte [tok_type], TOK_RPAREN
    jne .at_np
    call lexer_next
.at_np:
    mov rdi, r13
    call codegen_emit_arg_pops
    jmp .at_call
.at_call:
    mov rdi, r12
    call codegen_emit_call_prot
    jmp .done

; ── use mm/gc block ────────────────────────────────────────────────────────────
; Syntax: use mm <mode> [gc <mode>]:  OR  use gc <mode>:
; MM modes: arena=0, pool=1, stack=2, heap=3, static=4
; GC modes: sweep=0, ref=1, gen=2, inc=3, region=4
.use:
    call lexer_next             ; skip 'use' → 'mm'/'gc'/other
    xor r14d, r14d              ; mm_mode = 0 (arena default)
    mov r15, -1                 ; gc_mode = -1 (none specified)

    cmp byte [tok_type], TOK_MM
    jne .use_chk_gc

    ; ── parse mm mode ─────────────────────────────────────────────────────────
    call lexer_next             ; skip 'mm' → mode ident (tok_ident set)
    ; arena: a,r,e,n → dword 0x6E657261, then 'a'
    cmp dword [tok_ident], 0x6E657261
    jne .use_mm_pool
    cmp byte [tok_ident+4], 'a'
    jne .use_mm_pool
    xor r14d, r14d
    jmp .use_mm_done
.use_mm_pool:
    ; pool: p,o,o,l → dword 0x6C6F6F70, then null
    cmp dword [tok_ident], 0x6C6F6F70
    jne .use_mm_stack
    cmp byte [tok_ident+4], 0
    jne .use_mm_stack
    mov r14d, 1
    jmp .use_mm_done
.use_mm_stack:
    ; stack: s,t,a,c → dword 0x63617473, then 'k'
    cmp dword [tok_ident], 0x63617473
    jne .use_mm_heap
    cmp byte [tok_ident+4], 'k'
    jne .use_mm_heap
    mov r14d, 2
    jmp .use_mm_done
.use_mm_heap:
    ; heap: h,e,a,p → dword 0x70616568, then null
    cmp dword [tok_ident], 0x70616568
    jne .use_mm_static
    cmp byte [tok_ident+4], 0
    jne .use_mm_static
    mov r14d, 3
    jmp .use_mm_done
.use_mm_static:
    ; static: s,t,a,t → dword 0x74617473, then 'i','c'
    cmp dword [tok_ident], 0x74617473
    jne .use_mm_done
    cmp byte [tok_ident+4], 'i'
    jne .use_mm_done
    cmp byte [tok_ident+5], 'c'
    jne .use_mm_done
    mov r14d, 4
.use_mm_done:
    call lexer_next             ; advance past mode name

    ; ── optional gc clause after mm mode ──────────────────────────────────────
.use_chk_gc:
    cmp byte [tok_type], TOK_GC
    jne .use_emit

    call lexer_next             ; skip 'gc' → gc mode ident
    xor r15d, r15d
    ; sweep: s,w,e,e → dword 0x65657773, then 'p'
    cmp dword [tok_ident], 0x65657773
    jne .use_gc_ref
    cmp byte [tok_ident+4], 'p'
    jne .use_gc_ref
    xor r15d, r15d
    jmp .use_gc_done
.use_gc_ref:
    ; ref: r,e,f → dword 0x00666572
    cmp dword [tok_ident], 0x00666572
    jne .use_gc_gen
    mov r15d, 1
    jmp .use_gc_done
.use_gc_gen:
    ; gen: g,e,n → dword 0x006E6567
    cmp dword [tok_ident], 0x006E6567
    jne .use_gc_inc
    mov r15d, 2
    jmp .use_gc_done
.use_gc_inc:
    ; inc: i,n,c → dword 0x00636E69
    cmp dword [tok_ident], 0x00636E69
    jne .use_gc_region
    mov r15d, 3
    jmp .use_gc_done
.use_gc_region:
    ; region: r,e,g,i → dword 0x69676572, then 'o','n'
    cmp dword [tok_ident], 0x69676572
    jne .use_gc_done
    cmp byte [tok_ident+4], 'o'
    jne .use_gc_done
    cmp byte [tok_ident+5], 'n'
    jne .use_gc_done
    mov r15d, 4
.use_gc_done:
    call lexer_next             ; advance past gc mode name

.use_emit:
    mov rdi, r14
    call codegen_emit_mm_switch
    cmp r15, -1
    je .use_body
    mov rdi, r15
    call codegen_emit_gc_switch

.use_body:
    call lexer_next             ; skip ':'
    cmp byte [tok_type], TOK_NEWLINE
    jne .use_un
    call lexer_next
.use_un:
    cmp byte [tok_type], TOK_INDENT
    jne .use_ub
    call lexer_next
    mov r13, 1
    jmp .use_ubl
.use_ub:
    xor r13, r13
.use_ubl:
    movzx eax, byte [tok_type]
    cmp al, TOK_EOF
    je .use_uen
    cmp al, TOK_DEDENT
    je .use_uen
    call parse_stmt
    test r13, r13
    jnz .use_ubl
.use_uen:
    test r13, r13
    jz .use_udo
    cmp byte [tok_type], TOK_DEDENT
    jne .use_udo
    call lexer_next
.use_udo:
    xor rdi, rdi
    call codegen_emit_mm_switch
    jmp .done

; ── err statement ─────────────────────────────────────────────────────────────
.err_stmt:
    call lexer_next
    call parse_expr
    call codegen_emit_mov_rdi_rax
    call codegen_emit_call_rt_err
    jmp .done

; ── push statement ────────────────────────────────────────────────────────────
.push_stmt:
    call lexer_next
    cmp byte [tok_type], TOK_IDENT
    jne .done
    lea rdi, [saved_name]
    lea rsi, [tok_ident]
    call strcpy
    lea rdi, [saved_name]
    call var_find
    cmp rax, -1
    je .done
    mov r14, rax
    call lexer_next
    call parse_expr
    mov rdi, r14
    call codegen_emit_seq_push
    jmp .done

; ── ++ / -- prefix increment / decrement ──────────────────────────────────────
.incr_stmt:
    call lexer_next
    cmp byte [tok_type], TOK_IDENT
    jne .done
    lea rdi, [saved_name]
    lea rsi, [tok_ident]
    call strcpy
    lea rdi, [saved_name]
    call var_find
    cmp rax, -1
    je .done
    mov rdi, rax
    call codegen_emit_inc_var
    call lexer_next
    jmp .done

.decr_stmt:
    call lexer_next
    cmp byte [tok_type], TOK_IDENT
    jne .done
    lea rdi, [saved_name]
    lea rsi, [tok_ident]
    call strcpy
    lea rdi, [saved_name]
    call var_find
    cmp rax, -1
    je .done
    mov rdi, rax
    call codegen_emit_dec_var
    call lexer_next
    jmp .done

; ── swap x y ─────────────────────────────────────────────────────────────────
.swap_stmt:
    call lexer_next
    cmp byte [tok_type], TOK_IDENT
    jne .done
    lea rdi, [saved_name]
    lea rsi, [tok_ident]
    call strcpy
    lea rdi, [saved_name]
    call var_find
    cmp rax, -1
    je .done
    mov r14, rax
    call lexer_next
    cmp byte [tok_type], TOK_IDENT
    jne .done
    sub rsp, 64
    mov rdi, rsp
    lea rsi, [tok_ident]
    call strcpy
    mov rdi, rsp
    call var_find
    add rsp, 64
    cmp rax, -1
    je .done
    mov rdi, r14
    mov rsi, rax
    call codegen_emit_swap_vars
    call lexer_next
    jmp .done

; ── when x: is N: body ... ─────────────────────────────────────────────────────
.when:
    ; push outer when state for nesting (#32)
    mov rax, [when_stk_depth]
    lea rcx, [when_var_stack]
    mov rbx, [when_var_idx]
    mov [rcx+rax*8], rbx
    lea rcx, [when_cnt_stack]
    mov rbx, [when_case_count]
    mov [rcx+rax*8], rbx
    inc qword [when_stk_depth]
    call lexer_next
    call parse_expr
    ; store when value in __when__ temp var
    lea rdi, [when_tmp]
    xor rsi, rsi
    xor dl, dl
    mov cl, TYPE_INT
    call var_add
    cmp rax, -1
    je .done
    mov [when_var_idx], rax
    mov rdi, rax
    call codegen_emit_store_rax_to_var
    call codegen_save_chain_base
    mov qword [when_case_count], 0
    ; skip ':' newline indent
    movzx eax, byte [tok_type]
    cmp al, TOK_COLON
    jne .when_nl
    call lexer_next
.when_nl:
    cmp byte [tok_type], TOK_NEWLINE
    jne .when_in
    call lexer_next
.when_in:
    cmp byte [tok_type], TOK_INDENT
    jne .when_loop
    call lexer_next
    mov r13, 1
    jmp .when_loop
.when_loop:
    movzx eax, byte [tok_type]
    cmp al, TOK_EOF
    je .when_end
    cmp al, TOK_DEDENT
    je .when_end
    cmp al, TOK_IS
    je .when_is
    cmp al, TOK_ELSE
    je .when_else
    call parse_stmt
    jmp .when_loop
.when_is:
    ; if not first case: emit jmp_end + patch previous jz
    cmp qword [when_case_count], 0
    je .when_is_first
    call codegen_emit_jmp_end
    call codegen_patch_jump
.when_is_first:
    inc qword [when_case_count]
    call lexer_next
    ; emit: load when_var → rax, push it; parse is-value → rax; pop rbx; cmp
    mov rdi, [when_var_idx]
    call codegen_emit_mov_rax_var
    call codegen_emit_push_rax
    call parse_expr
    call codegen_emit_pop_rbx
    mov rdi, 0x94
    call codegen_emit_cmp_rbx_rax_setcc
    call codegen_emit_test_rax_jz
    ; skip ':' newline indent body
    movzx eax, byte [tok_type]
    cmp al, TOK_COLON
    jne .when_ib_nl
    call lexer_next
.when_ib_nl:
    cmp byte [tok_type], TOK_NEWLINE
    jne .when_ib_in
    call lexer_next
.when_ib_in:
    cmp byte [tok_type], TOK_INDENT
    jne .when_ibl
    call lexer_next
    mov r13, 1
.when_ibl:
    movzx eax, byte [tok_type]
    cmp al, TOK_EOF
    je .when_ib_end
    cmp al, TOK_DEDENT
    je .when_ib_end
    cmp al, TOK_IS
    je .when_ib_end
    cmp al, TOK_ELSE
    je .when_ib_end
    call parse_stmt
    jmp .when_ibl
.when_ib_end:
    test r13, r13
    jz .when_loop
    cmp byte [tok_type], TOK_DEDENT
    jne .when_loop
    call lexer_next
    xor r13, r13
    jmp .when_loop
.when_else:
    ; patch the last jz if any case was open
    cmp qword [when_case_count], 0
    je .when_else_body
    call codegen_emit_jmp_end
    call codegen_patch_jump
.when_else_body:
    call lexer_next
    call lexer_next
    cmp byte [tok_type], TOK_NEWLINE
    jne .when_el_in
    call lexer_next
.when_el_in:
    cmp byte [tok_type], TOK_INDENT
    jne .when_ell
    call lexer_next
    mov r13, 1
.when_ell:
    movzx eax, byte [tok_type]
    cmp al, TOK_EOF
    je .when_el_end
    cmp al, TOK_DEDENT
    je .when_el_end
    call parse_stmt
    jmp .when_ell
.when_el_end:
    test r13, r13
    jz .when_end
    cmp byte [tok_type], TOK_DEDENT
    jne .when_end
    call lexer_next
.when_end:
    ; patch final open jz if no else was present
    cmp qword [when_case_count], 0
    je .when_done
    call codegen_patch_jump
.when_done:
    call codegen_patch_chain_end
    ; clean up __when__ temp var
    dec qword [var_count]
    ; pop outer when state (#32)
    dec qword [when_stk_depth]
    mov rax, [when_stk_depth]
    lea rcx, [when_var_stack]
    mov rbx, [rcx+rax*8]
    mov [when_var_idx], rbx
    lea rcx, [when_cnt_stack]
    mov rbx, [rcx+rax*8]
    mov [when_case_count], rbx
    jmp .done

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

; ── indirect emit helpers (wired to codegen raw exports) ─────────────────────
emit_b_indirect:
    jmp codegen_emit_b_raw

emit_d_indirect:
    jmp codegen_emit_d_raw

get_var_va_indirect:
    jmp codegen_get_var_va_proxy
