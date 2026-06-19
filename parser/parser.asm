default rel
%include "include/rex_defs.inc"
global parse_stmt, parse_expr
global var_table, var_count
extern lexer_init, lexer_next, tok_type, tok_int, tok_ident
extern codegen_output_const, codegen_output_typed
extern codegen_patch_jump, codegen_save_chain_base, codegen_emit_jmp_end, codegen_patch_chain_end
extern codegen_begin_protos, codegen_end_protos
extern codegen_emit_for_start, codegen_emit_for_end
extern codegen_emit_while_start, codegen_emit_while_end
extern codegen_emit_break, codegen_patch_breaks, codegen_emit_loop_base
extern codegen_emit_ret, codegen_emit_mov_eax_imm32, codegen_emit_mov_rax_imm64, codegen_emit_call_prot
extern codegen_emit_push_var_slot, codegen_emit_pop_var_slot
extern codegen_emit_assign_var, codegen_emit_cmp_var_jne, codegen_emit_unknown_bool
extern codegen_emit_mm_switch, codegen_emit_gc_switch, out_idx
extern codegen_emit_test_rax_jnz, codegen_emit_normalize_bool_rax
extern actual_prs_va, actual_prq_va, actual_sip_va
extern codegen_emit_jmp_get_slot, codegen_patch_slot_to_here
extern codegen_emit_push_rax, codegen_emit_pop_rbx
extern codegen_emit_expr_save_rax, codegen_emit_expr_restore_rbx
extern codegen_emit_expr_spill_save, codegen_emit_expr_spill_restore
extern codegen_emit_mov_rax_var, codegen_emit_store_rax_to_var
extern push_style_frame, codegen_emit_memo_check, codegen_emit_memo_store
extern codegen_emit_rdrand_rax, codegen_emit_neg_rax, codegen_emit_not_rax
extern codegen_emit_bitwise_not_rax
extern codegen_emit_add_rax_rbx, codegen_emit_sub_rax_rbx
extern codegen_emit_imul_rax_rbx, codegen_emit_idiv_rbx_by_rax, codegen_emit_imod_rbx_by_rax
extern codegen_emit_cmp_rbx_rax_setcc, codegen_emit_test_rax_jz
extern codegen_output_rax
extern codegen_emit_addsd_rax_rbx, codegen_emit_subsd_rax_rbx
extern codegen_emit_mulsd_rax_rbx, codegen_emit_divsd_rax_rbx
extern codegen_emit_cvttsd2si_rax, codegen_emit_cvtsi2sd_rax, codegen_emit_cvtsi2sd_rbx
extern codegen_emit_bitwise_and_rax_rbx, codegen_emit_bitwise_or_rax_rbx
extern codegen_emit_bitwise_xor_rax_rbx
extern codegen_emit_and_bool_rax_rbx, codegen_emit_or_bool_rax_rbx
extern codegen_emit_lnot_int_rax
extern out_buffer
extern codegen_emit_shl_rax_by_rbx, codegen_emit_shr_rax_by_rbx
extern codegen_set_frame, codegen_clear_frame
extern codegen_emit_frame_prologue, codegen_emit_leave
extern codegen_emit_regalloc_epilogue
extern regalloc_cnt
extern codegen_emit_jmp_prot
extern codegen_add_frame_local
extern codegen_emit_str_rax
extern codegen_emit_str_method
extern codegen_emit_seq_alloc, codegen_emit_seq_push, codegen_emit_seq_pop_rax
extern codegen_emit_seq_len_rax
extern codegen_emit_mov_rdi_rax, codegen_emit_call_rt_err, codegen_emit_exit1
extern codegen_emit_for_start_dyn, codegen_emit_arg_pops
extern codegen_push_cont, codegen_pop_cont, codegen_emit_skip
extern codegen_emit_b_raw, codegen_emit_d_raw, codegen_get_var_va_proxy
extern codegen_emit_inc_var, codegen_emit_dec_var
extern codegen_emit_swap_vars
extern codegen_emit_abs_rax
extern codegen_emit_cap_rax
extern codegen_emit_clock_ms
extern codegen_set_for_step
extern codegen_push_loop_else_flag, codegen_pop_loop_else_flag
extern codegen_emit_each_start, codegen_emit_each_end
extern codegen_emit_zero_var
extern codegen_emit_memo_reset
extern codegen_skip_pin_save
extern o13_inhibit
extern codegen_cur_proto_seq_idx, proto_needs_r12_save, codegen_mark_r12_needed
section .bss
var_table:       resb VAR_ENTRY_SIZE * VAR_MAX
var_count:       resq 1
proto_table:     resb PROTO_ENTRY_SIZE * PROTO_MAX    ; BUG-01 fix: was * 32, must match PROTO_MAX=128
global proto_count
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
when_cond_mode:  resb 1
when_mode_stack: resb 8
fwd_ref_names:   resb 4096       ; BUG-14 fix: 128 entries * 32 bytes (was 512 = 16 entries)
fwd_ref_patches: resq 128        ; BUG-14 fix: match PROTO_MAX=128 (was 16)
fwd_ref_count:   resq 1
decl_mutable:          resb 1
decl_const:            resb 1
cur_proto_param_count: resb 1       ; B-1: param count of the protocol being compiled
cur_proto_param_vars:  resb 6       ; B-1: var indices for each param (up to 6)
tco_return_active:     resb 1       ; O4: 1 if we are inside a .ret that may be TCO
tco_was_emitted:       resb 1       ; O4: 1 if TCO jmp was emitted for this return
tco_body_entry:        resq 1       ; O4: out_idx of current protocol body start (after prologue)
proto_is_self_recursive: resb 1    ; O20: 1 if current protocol calls itself
proto_memo_active:     resb 1      ; @memo: 1 if current protocol is memoized
next_proto_memo:       resb 1      ; @memo: pending flag set by 'memo' keyword
proto_find_seq_idx:    resq 1      ; sequential index of last proto_find match (0,1,2...)
for_start_tok:         resb 1       ; static-bounds: tok_type before start parse_expr
for_end_tok:           resb 1       ; static-bounds: tok_type before end parse_expr
for_start_val:         resq 1       ; static-bounds: tok_int before start parse_expr
for_end_val:           resq 1       ; static-bounds: tok_int before end parse_expr
for_rollback_idx:      resq 1       ; static-bounds: out_idx before for init code
cur_call_proto_seq_idx: resq 1     ; O26: seq idx of called proto (saved before parse_expr clobbers)
section .data
err_id:    db "error: expected identifier",10
err_id_l   equ $ - err_id
err_undef:   db "error: undefined variable",10   ; BUG-04
err_undef_l  equ $ - err_undef
fe_suffix: db "_fe",0
when_tmp:  db "__when__",0
le_name:   db "__le",0
section .text

; ── string helpers ────────────────────────────────────────────────────────────
; O33a: strcpy — find src length with repne scasb, bulk-copy with rep movsb
strcpy:
    ; rdi = dest, rsi = src
    push rdi
    push rcx
    mov rdi, rsi        ; scan src for NUL
    xor eax, eax
    mov ecx, -1
    cld
    repne scasb         ; rdi past NUL; ecx = -(len+2) [as uint32: 0xFFFFFFFE-L]
    not ecx             ; ecx = len+1 (zero-extends to rcx)
    pop rax             ; discard saved rcx (stack balance; rcx = len+1 is in ecx)
    pop rdi             ; restore dest
    rep movsb           ; copy len+1 bytes src → dest
    ret

; O33b: strlen_local — repne scasb instead of byte-at-a-time loop
strlen_local:
    ; rdi = string → rax = length (NUL not counted)
    push rcx
    xor eax, eax        ; al = NUL byte to find
    mov ecx, -1
    cld
    repne scasb         ; ecx = -(len+2)
    not ecx             ; ecx = len+1
    dec ecx             ; ecx = len
    mov rax, rcx
    pop rcx
    ret

; O33c: strcat_local — find dest-end with repne scasb, byte-copy src
strcat_local:
    ; rdi = dest, rsi = src
    push rbx
    push rcx
    mov rbx, rdi        ; save original dest (callee-saved)
    xor eax, eax
    mov ecx, 64         ; max name length (always safe for our 64-byte buffers)
    cld
    repne scasb         ; rdi = one past NUL of dest
    dec rdi             ; rdi = NUL position (append here)
.cat_cp:
    movzx eax, byte [rsi]
    mov [rdi], al
    inc rdi
    inc rsi
    test al, al
    jnz .cat_cp
    pop rcx
    pop rbx
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
; var_find: reverse linear scan (newest/innermost scope wins).
; BUG-09 fix: scan from var_count-1 down to 0 so inner-scope vars shadow outer ones.
; VAR_ENTRY_SIZE=64=2^6, so index*64 = shl 6 (replaces imul).
var_find:
    push rbx
    push rcx
    push rsi
    push rdi
    mov rcx, [var_count]    ; start at var_count
    test rcx, rcx
    jz .nf                  ; no variables at all
    dec rcx                 ; start at var_count - 1 (most-recent)
.l:
    mov rax, rcx
    shl rax, 6              ; rax = rcx * 64 (VAR_ENTRY_SIZE = 64 = 2^6)
    lea rsi, [var_table]
    add rsi, rax
    mov rdi, [rsp]          ; restore query name pointer (bottom of pushed regs)
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
    test rcx, rcx           ; was this the last (index 0) entry?
    jz .nf
    dec rcx
    jmp .l
.nf:
    mov rax, -1
.done:
    pop rdi
    pop rsi
    pop rcx
    pop rbx
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
    shl rax, 6          ; rax = rbx * 64 (VAR_ENTRY_SIZE = 64 = 2^6)
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
    shl rax, 6          ; rax = rbx * 64 (same shift)
    lea rdi, [var_table]
    add rdi, rax
    mov [rdi+32], r13
    mov byte [rdi+40], r14b
    mov byte [rdi+48], r15b
    movzx ecx, byte [decl_const]
    mov [rdi+42], cl
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
    cmp al, TOK_TYPE_STR
    je .casts
    cmp al, TOK_LEN
    je .lenx
    cmp al, TOK_POP
    je .popx
    cmp al, TOK_ABS
    je .absx
    cmp al, TOK_CAP
    je .capx
    cmp al, TOK_CLOCK
    je .clockx
    ; default: zero + advance past unknown token (#35)
    call lexer_next
    mov rdi, 0
    call codegen_emit_mov_eax_imm32
    mov byte [cur_type], TYPE_INT
    jmp .done
.int:
    mov rdi, [tok_int]
    mov eax, edi          ; zero-extend lower 32 bits → rax; rdi unchanged
    cmp rdi, rax          ; if upper 32 bits are set, they differ → 64-bit constant
    jne .int_imm64
    call codegen_emit_mov_eax_imm32
    jmp .int_done
.int_imm64:
    call codegen_emit_mov_rax_imm64
.int_done:
    mov byte [cur_type], TYPE_INT
    call lexer_next
    jmp .done
.flt:
    mov rdi, [tok_int]          ; tok_int holds full 64-bit IEEE 754 bit pattern
    call codegen_emit_mov_rax_imm64  ; movabs rax, imm64 — preserve all 64 bits
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
    mov rdi, 2
    call codegen_emit_mov_eax_imm32
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
    shl rbx, 6          ; rbx = rax * 64
    lea rcx, [var_table]
    add rcx, rbx
    ; check if constant for folding (O29)
    cmp byte [rcx+42], 1
    jne .idn_not_const
    ; fold constant: load value from [rcx+32] and emit as immediate
    mov rdi, [rcx+32]
    movzx r12d, byte [rcx+48]
    mov eax, edi
    cmp rdi, rax
    jne .idn_const64
    call codegen_emit_mov_eax_imm32
    jmp .idn_const_done
.idn_const64:
    call codegen_emit_mov_rax_imm64
.idn_const_done:
    mov byte [cur_type], r12b
    pop rax
    call lexer_next
    jmp .done
.idn_not_const:
    movzx r12d, byte [rcx+48]
    pop rdi
    call codegen_emit_mov_rax_var
    mov byte [cur_type], r12b
    call lexer_next
    jmp .done
.idn_skip:
    ; BUG-04 fix: undefined variable must be a fatal error, not silent 0
    lea rsi, [err_undef]
    mov rdx, err_undef_l
    call fatal
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
    ; O26: save seq_idx before parse_expr calls may overwrite proto_find_seq_idx
    mov rax, [proto_find_seq_idx]
    mov [cur_call_proto_seq_idx], rax
    call lexer_next
    mov rbx, [var_count]        ; snapshot var_count for caller-save (Gap-1)
    ; O4: save tco_return_active because argument parsing may clobber it
    push qword [tco_return_active]
    mov byte [tco_return_active], 0
    cmp byte [tok_type], TOK_LPAREN
    jne .prt_call_pre
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
.prt_call_pre:
    pop rax
    mov [tco_return_active], al
    jmp .prt_call
.prt_call:
    ; O4: tail-call optimisation — if this call is the tail of a .ret expression
    ; and is a self-recursive call to the current protocol, emit leave+jmp
    cmp byte [tco_return_active], 1
    jne .prt_do_normal
    ; check that the next token is end-of-statement (newline/EOF/dedent)
    movzx eax, byte [tok_type]
    cmp al, TOK_NEWLINE
    je .prt_tco_check
    cmp al, TOK_EOF
    je .prt_tco_check
    cmp al, TOK_DEDENT
    je .prt_tco_check
    jmp .prt_do_normal
.prt_tco_check:
    ; TCO: emit leave + jmp to protocol body start
    ; Check if it's self-recursion for optimized entry (skip prologue)
    cmp r12, [cur_proto_idx]
    jne .prt_sco
    call codegen_emit_leave
    mov rdi, [tco_body_entry]
    test rdi, rdi
    jz .prt_do_normal           ; fallback if entry point not captured
    call codegen_emit_jmp_prot
    mov byte [tco_was_emitted], 1
    jmp .done
.prt_sco:
    ; Sibling-Call Optimization (SCO): call to another protocol in tail position
    ; Emit leave to clean up current frame, then jump to callee's start
    call codegen_emit_leave
    mov rdi, r12                ; r12 is the proto_idx from proto_find
    ; We need the actual out_idx of the callee.
    ; r12 is the index in proto_table.
    mov rax, r12
    imul rax, PROTO_ENTRY_SIZE
    lea rdx, [proto_table]
    mov rdi, [rdx + rax + 32]   ; out_idx is at offset 32 (after 32-byte name)
    call codegen_emit_jmp_prot
    mov byte [tco_was_emitted], 1
    jmp .done
.prt_do_normal:
    ; O20: detect self-recursive call (r12 = called proto idx, cur_proto_idx = current)
    cmp r12, [cur_proto_idx]
    jne .prt_not_self_recur
    mov byte [proto_is_self_recursive], 1
.prt_not_self_recur:
    ; O26: set skip-pin-save flag based on called proto's has_loop flag at offset 46
    ; If proto has no loop, r15/r14 won't be clobbered — skip save/restore.
    mov rax, [cur_call_proto_seq_idx]
    imul rax, PROTO_ENTRY_SIZE
    lea rdx, [proto_table]
    movzx eax, byte [rdx + rax + 46]   ; proto_has_loop flag (0=no loops, 1=has loops)
    xor al, 1                           ; invert: no_loop→skip=1, has_loop→skip=0
    mov [codegen_skip_pin_save], al
    ; O27: if this call is from inside another proto, mark callee as needing r12 save
    cmp qword [prot_body_depth], 0
    je .o27_outer_call
    mov rdi, [cur_call_proto_seq_idx]
    call codegen_mark_r12_needed        ; proto_needs_r12_save[rdi] = 1
.o27_outer_call:
    ; O6: save r10/r11 if live as expression spill regs (noop when depth=0)
    call codegen_emit_expr_spill_save
    ; ── Gap-1 fix: caller-save all in-scope vars before call ─────────────────
    xor r13, r13                ; loop counter i = 0
.prt_cs:
    cmp r13, rbx                ; i < var_count snapshot?
    jge .prt_cs_done
    mov rdi, r13
    call codegen_emit_push_var_slot
    inc r13
    jmp .prt_cs
.prt_cs_done:
    ; ── emit the actual call ──────────────────────────────────────────────────
    mov rdi, r12
    call codegen_emit_call_prot
    ; ── caller-restore all in-scope vars in reverse order ─────────────────────
.prt_cr:
    test rbx, rbx
    jz .prt_cr_done
    dec rbx
    mov rdi, rbx
    call codegen_emit_pop_var_slot
    jmp .prt_cr
.prt_cr_done:
    ; O26: clear skip-pin-save flag after save/restore loops complete
    mov byte [codegen_skip_pin_save], 0
    ; O6: restore r10/r11 after call if they were saved
    call codegen_emit_expr_spill_restore
    movzx ecx, byte [proto_ret_type]
    test cl, cl
    jz .prt_default_type
    mov byte [cur_type], cl
    jmp .done
.prt_default_type:
    mov byte [cur_type], TYPE_INT
    jmp .done
.prt_skip:
    ; Forward reference: proto not defined yet — emit placeholder call and register for patching
    mov r13, [fwd_ref_count]
    cmp r13, 16
    jge .prt_fwd_overflow
    ; Reserve this slot immediately so nested forward refs use later slots
    inc qword [fwd_ref_count]
    ; Save proto name at fwd_ref_names[r13*32]
    imul r14, r13, 32
    lea rdi, [fwd_ref_names]
    add rdi, r14
    lea rsi, [tok_ident]
    call strcpy
    call lexer_next             ; consume proto name
    ; Parse arguments (same logic as .prt_al/.prt_ad)
    xor r12, r12                ; arg count
    cmp byte [tok_type], TOK_LPAREN
    jne .prt_fwd_emit
    call lexer_next             ; skip '('
.prt_fwd_al:
    cmp byte [tok_type], TOK_RPAREN
    je .prt_fwd_ad
    cmp byte [tok_type], TOK_EOF
    je .prt_fwd_ad
    cmp byte [tok_type], TOK_NEWLINE
    je .prt_fwd_ad
    push r12
    push r13
    call parse_expr
    call codegen_emit_push_rax
    pop r13
    pop r12
    inc r12
    cmp byte [tok_type], TOK_COMMA
    jne .prt_fwd_ad
    call lexer_next
    jmp .prt_fwd_al
.prt_fwd_ad:
    cmp byte [tok_type], TOK_RPAREN
    jne .prt_fwd_emit
    call lexer_next             ; skip ')'
.prt_fwd_emit:
    ; Emit arg pops to set up registers rdi/rsi/...
    push r13
    mov rdi, r12
    call codegen_emit_arg_pops
    pop r13
    ; Emit E8 (call opcode)
    mov al, 0xE8
    call emit_b_indirect
    ; Record patch position (current out_idx is where rel32 goes)
    mov rax, [out_idx]
    mov [fwd_ref_patches + r13*8], rax
    ; Emit 4 zero bytes (rel32 placeholder)
    xor eax, eax
    call emit_d_indirect
    mov byte [cur_type], TYPE_INT
    jmp .done
.prt_fwd_overflow:
    ; Too many forward refs — emit 0 and skip name
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
    cmp byte [cur_type], TYPE_BOOL
    jne .lnot_int
    call codegen_emit_not_rax
    jmp .done
.lnot_int:
    call codegen_emit_lnot_int_rax
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
.casts:
    call lexer_next
    cmp byte [tok_type], TOK_LPAREN
    jne .done
    call lexer_next
    call parse_expr
    movzx ecx, byte [cur_type]
    cmp cl, TYPE_INT
    je .cs_int
    cmp cl, TYPE_FLOAT
    je .cs_flt
    jmp .cs_done
.cs_int:
    ; call rt_int2str
    mov rax, RT_INT2STR_OFFSET
    add rax, LOAD_BASE
    mov rdx, [out_idx]
    add rdx, 5
    add rdx, LOAD_BASE
    sub rax, rdx
    mov r12, rax
    mov al, 0xE8
    call emit_b_indirect
    mov eax, r12d
    call emit_d_indirect
    jmp .cs_done
.cs_flt:
    ; call rt_float2str
    mov rax, RT_FLOAT2STR_OFFSET
    add rax, LOAD_BASE
    mov rdx, [out_idx]
    add rdx, 5
    add rdx, LOAD_BASE
    sub rax, rdx
    mov r12, rax
    mov al, 0xE8
    call emit_b_indirect
    mov eax, r12d
    call emit_d_indirect
.cs_done:
    mov byte [cur_type], TYPE_STR
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
    ; check var type: TYPE_STR (5) uses str method 0; else use seq len
    push rax
    imul rbx, rax, VAR_ENTRY_SIZE
    lea rcx, [var_table]
    movzx edx, byte [rcx + rbx + 48]   ; type field at offset 48
    pop rax
    cmp dl, TYPE_STR
    jne .lenx_seq
    ; string length: load var → rax, call str_len method
    mov rdi, rax
    call codegen_emit_mov_rax_var
    mov rdi, 0
    call codegen_emit_str_method
    jmp .lenx_done
.lenx_seq:
    mov rdi, rax
    call codegen_emit_seq_len_rax
.lenx_done:
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
.clockx:
    ; clock / clock() — emit inline clock_gettime(CLOCK_MONOTONIC) → ms in rax
    call lexer_next                     ; consume 'clock'
    cmp byte [tok_type], TOK_LPAREN
    jne .clock_noparen
    call lexer_next                     ; consume '('
    cmp byte [tok_type], TOK_RPAREN
    jne .clock_noparen
    call lexer_next                     ; consume ')'
.clock_noparen:
    call codegen_emit_clock_ms
    mov byte [cur_type], TYPE_INT
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
    cmp byte [cur_type], TYPE_BOOL
    jne .lnot_int
    call codegen_emit_not_rax
    jmp .done
.lnot_int:
    call codegen_emit_lnot_int_rax
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
    mov byte [tco_return_active], 0
    call lexer_next
    call codegen_emit_expr_save_rax
    call parse_unary
    call codegen_emit_expr_restore_rbx
    cmp r12b, TYPE_FLOAT
    je .mulf
    ; BUG-10 fix: right is float but left was int — promote left (rbx)
    cmp byte [cur_type], TYPE_FLOAT
    jne .mul_int
    call codegen_emit_cvtsi2sd_rbx
    call codegen_emit_mulsd_rax_rbx
    mov byte [cur_type], TYPE_FLOAT
    jmp .loop
.mul_int:
    call codegen_emit_imul_rax_rbx
    mov byte [cur_type], TYPE_INT
    jmp .loop
.mulf:
    ; BUG-10 fix: left is float, right may be int — promote right (rax)
    cmp byte [cur_type], TYPE_INT
    jne .mulf_do
    call codegen_emit_cvtsi2sd_rax
.mulf_do:
    call codegen_emit_mulsd_rax_rbx
    mov byte [cur_type], TYPE_FLOAT
    jmp .loop
.div:
    movzx r12d, byte [cur_type]
    mov byte [tco_return_active], 0
    call lexer_next
    call codegen_emit_expr_save_rax
    call parse_unary
    call codegen_emit_expr_restore_rbx
    cmp r12b, TYPE_FLOAT
    je .divf
    ; BUG-10 fix: right is float but left was int — promote left (rbx)
    cmp byte [cur_type], TYPE_FLOAT
    jne .div_int
    call codegen_emit_cvtsi2sd_rbx
    call codegen_emit_divsd_rax_rbx
    mov byte [cur_type], TYPE_FLOAT
    jmp .loop
.div_int:
    call codegen_emit_idiv_rbx_by_rax
    mov byte [cur_type], TYPE_INT
    jmp .loop
.divf:
    ; BUG-10 fix: left is float, right may be int — promote right (rax)
    cmp byte [cur_type], TYPE_INT
    jne .divf_do
    call codegen_emit_cvtsi2sd_rax
.divf_do:
    call codegen_emit_divsd_rax_rbx
    mov byte [cur_type], TYPE_FLOAT
    jmp .loop
.mod:
    mov byte [tco_return_active], 0
    call lexer_next
    call codegen_emit_expr_save_rax
    call parse_unary
    call codegen_emit_expr_restore_rbx
    call codegen_emit_imod_rbx_by_rax
    mov byte [cur_type], TYPE_INT
    jmp .loop
.shl:
    mov byte [tco_return_active], 0
    call lexer_next
    call codegen_emit_expr_save_rax
    call parse_unary
    call codegen_emit_expr_restore_rbx
    call codegen_emit_shl_rax_by_rbx
    mov byte [cur_type], TYPE_INT
    jmp .loop
.shr:
    mov byte [tco_return_active], 0
    call lexer_next
    call codegen_emit_expr_save_rax
    call parse_unary
    call codegen_emit_expr_restore_rbx
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
    mov byte [tco_return_active], 0
    call lexer_next
    call codegen_emit_expr_save_rax
    call parse_term
    call codegen_emit_expr_restore_rbx
    cmp r12b, TYPE_FLOAT
    je .addf
    cmp r12b, TYPE_STR
    je .adds
    ; BUG-10 fix: if right operand is float but left was int, promote left (rbx) to float
    cmp byte [cur_type], TYPE_FLOAT
    jne .add_int
    call codegen_emit_cvtsi2sd_rbx  ; convert left (rbx) int → float
    call codegen_emit_addsd_rax_rbx
    mov byte [cur_type], TYPE_FLOAT
    jmp .loop
.add_int:
    call codegen_emit_add_rax_rbx
    mov byte [cur_type], TYPE_INT
    jmp .loop
.addf:
    ; BUG-10 fix: left is float, right may be int — promote right (rax)
    cmp byte [cur_type], TYPE_INT
    jne .addf_do
    call codegen_emit_cvtsi2sd_rax
.addf_do:
    call codegen_emit_addsd_rax_rbx
    mov byte [cur_type], TYPE_FLOAT
    jmp .loop
.adds:
    ; call rt_str_cat(rax, len1, rbx, len2)
    ; This is a bit simplified, but let's emit the call
    mov rax, RT_STR_CAT_OFFSET
    add rax, LOAD_BASE
    mov rdx, [out_idx]
    add rdx, 5
    add rdx, LOAD_BASE
    sub rax, rdx
    mov r12, rax
    mov al, 0xE8
    call emit_b_indirect
    mov eax, r12d
    call emit_d_indirect
    mov byte [cur_type], TYPE_STR
    jmp .loop
.sub:
    movzx r12d, byte [cur_type]
    mov byte [tco_return_active], 0
    call lexer_next
    call codegen_emit_expr_save_rax
    call parse_term
    call codegen_emit_expr_restore_rbx
    cmp r12b, TYPE_FLOAT
    je .subf
    ; BUG-10 fix: if right is float but left was int, promote left (rbx) to float
    cmp byte [cur_type], TYPE_FLOAT
    jne .sub_int
    call codegen_emit_cvtsi2sd_rbx  ; convert left (rbx) int → float
    call codegen_emit_subsd_rax_rbx
    mov byte [cur_type], TYPE_FLOAT
    jmp .loop
.sub_int:
    call codegen_emit_sub_rax_rbx
    mov byte [cur_type], TYPE_INT
    jmp .loop
.subf:
    ; BUG-10 fix: left is float, right may be int — promote right (rax)
    cmp byte [cur_type], TYPE_INT
    jne .subf_do
    call codegen_emit_cvtsi2sd_rax
.subf_do:
    call codegen_emit_subsd_rax_rbx
    mov byte [cur_type], TYPE_FLOAT
    jmp .loop
.band:
    mov byte [tco_return_active], 0
    call lexer_next
    call codegen_emit_expr_save_rax
    call parse_term
    call codegen_emit_expr_restore_rbx
    call codegen_emit_bitwise_and_rax_rbx
    mov byte [cur_type], TYPE_INT
    jmp .loop
.bor:
    mov byte [tco_return_active], 0
    call lexer_next
    call codegen_emit_expr_save_rax
    call parse_term
    call codegen_emit_expr_restore_rbx
    call codegen_emit_bitwise_or_rax_rbx
    mov byte [cur_type], TYPE_INT
    jmp .loop
.bxor:
    mov byte [tco_return_active], 0
    call lexer_next
    call codegen_emit_expr_save_rax
    call parse_term
    call codegen_emit_expr_restore_rbx
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
    mov byte [tco_return_active], 0
    call lexer_next
    call codegen_emit_expr_save_rax
    call parse_additive
    call codegen_emit_expr_restore_rbx
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
    cmp al, TOK_IN
    je .in
    jmp .done
.in:
    call lexer_next
    push rax                    ; save LHS (expr1) value (it's in rax at runtime)
    push rcx                    ; save LHS type
    movzx ecx, byte [cur_type]
    mov [rsp], rcx
    call codegen_emit_push_rax
    call parse_comparison       ; parse RHS (expr2) -> rax (ptr)
    ; now rax = expr2_ptr, rbx = expr1_val (after pop)
    call codegen_emit_pop_rbx
    pop rcx                     ; rcx = expr1 type
    ; check expr2 type (cur_type)
    movzx edx, byte [cur_type]
    cmp dl, TYPE_SEQ
    je .in_seq
    cmp dl, TYPE_STR
    je .in_str
    ; TODO: dict
    jmp .in_done
.in_seq:
    ; rdi = seq_ptr (rax), rsi = value (rbx)
    mov rdi, rax
    mov rsi, rbx
    ; call rt_seq_contains
    mov rax, [actual_prq_va] ; Fallback or use specific blob if found
    ; Let's just emit a call to RT_SEQ_CONTAINS_OFFSET relative to LOAD_BASE
    mov rax, RT_SEQ_CONTAINS_OFFSET
    add rax, LOAD_BASE
    mov rdx, [out_idx]
    add rdx, 5
    add rdx, LOAD_BASE
    sub rax, rdx
    mov r12, rax
    ; call it
    mov al, 0xE8
    call emit_b_indirect
    mov eax, r12d
    call emit_d_indirect
    jmp .in_done
.in_str:
    ; haystack = rax, needle = rbx
    ; call rt_str_contains
    mov rax, RT_STR_CONTAINS_OFFSET
    add rax, LOAD_BASE
    mov rdx, [out_idx]
    add rdx, 5
    add rdx, LOAD_BASE
    sub rax, rdx
    mov r12, rax
    mov al, 0xE8
    call emit_b_indirect
    mov eax, r12d
    call emit_d_indirect
    jmp .in_done
.in_done:
    mov byte [cur_type], TYPE_BOOL
    jmp .loop
.land:
    ; Kleene AND: push LHS, eval RHS, pop LHS→rbx, call Kleene AND
    mov byte [tco_return_active], 0
    call codegen_emit_push_rax
    call lexer_next
    call parse_comparison           ; RHS → rax
    call codegen_emit_pop_rbx       ; LHS → rbx
    call codegen_emit_and_bool_rax_rbx
    mov byte [cur_type], TYPE_BOOL
    jmp .loop
.lor:
    ; Kleene OR: push LHS, eval RHS, pop LHS→rbx, call Kleene OR
    mov byte [tco_return_active], 0
    call codegen_emit_push_rax
    call lexer_next
    call parse_comparison           ; RHS → rax
    call codegen_emit_pop_rbx       ; LHS → rbx
    call codegen_emit_or_bool_rax_rbx
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
    mov [proto_find_seq_idx], r13   ; save sequential index for callers that need it
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
    cmp al, TOK_CONST
    jne .not_const
    mov byte [decl_const], 1
    call lexer_next
    movzx eax, byte [tok_type]
.not_const:
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
    cmp al, TOK_SHOW
    je .show
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
    cmp al, TOK_MEMO
    je .memo
    cmp al, TOK_MEMO_RESET
    je .memo_reset
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
    cmp al, TOK_REPEAT
    je .repeat
    cmp al, TOK_EACH
    je .each
    cmp al, TOK_UNREACHABLE
    je .unreachable
    cmp al, TOK_ASSERT
    je .assert
    cmp al, TOK_IDENT
    je .ident_stmt
    call lexer_next
    jmp .done

; ── @memo — memoize next protocol definition ───────────────────────────────────
.memo:
    mov byte [next_proto_memo], 1
    call lexer_next
    call parse_stmt
    jmp .done

; ── memo_reset — clear a protocol's memo hash table at runtime ─────────────────
; Syntax: memo_reset <proto_name>
; Looks up the named protocol, then emits a rep-stosq reset of its 1024-entry
; cache table.  Safe to call when the table has not been allocated yet (null guard
; in the emitted runtime code makes it a no-op in that case).
.memo_reset:
    call lexer_next
    cmp byte [tok_type], TOK_IDENT
    jne .done
    lea rdi, [tok_ident]
    call proto_find
    cmp rax, -1
    je .done
    mov rdi, [proto_find_seq_idx]   ; sequential proto index (not the out_idx body offset)
    call codegen_emit_memo_reset
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
    mov byte [decl_const], 0
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
    ; O5: if inside protocol body, register as frame local
    cmp rax, -1
    je .done
    cmp qword [prot_body_depth], 0
    jle .done
    push rax
    mov rdi, rax
    call codegen_add_frame_local
    pop rax
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
    ; O5: register as frame local BEFORE store so store uses frame slot
    cmp qword [prot_body_depth], 0
    jle .pinit_store
    push rax
    mov rdi, rax
    call codegen_add_frame_local
    pop rax
.pinit_store:
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
    mov r13b, 1                ; r13b = newline flag
    jmp .out_cont
.show:
    mov r13b, 0
.out_cont:
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
    call lexer_next             ; skip 'for' → ':' (optional) or ident
    cmp byte [tok_type], TOK_COLON
    jne .for_have_ident
    call lexer_next             ; skip optional ':' → loop var ident
.for_have_ident:
    lea rdi, [saved_name]
    lea rsi, [tok_ident]
    call strcpy
    call lexer_next             ; skip varname → 'in'
    call lexer_next             ; skip 'in' → start expr
    ; static-bounds O2: save start token state and out_idx before any emit
    movzx rax, byte [tok_type]
    mov [for_start_tok], al
    mov rax, [tok_int]
    mov [for_start_val], rax
    mov rax, [out_idx]
    mov [for_rollback_idx], rax
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
    mov byte [o13_inhibit], 1      ; suppress O13 promotion: this is a synthetic for-init store
    call codegen_emit_store_rax_to_var
    mov byte [o13_inhibit], 0
    cmp byte [tok_type], TOK_DOTDOT
    jne .for_nodd
    call lexer_next
.for_nodd:
    ; static-bounds: save end token state before emit
    movzx rax, byte [tok_type]
    mov [for_end_tok], al
    mov rax, [tok_int]
    mov [for_end_val], rax
    call parse_expr             ; parse end expr
    cmp byte [tok_type], TOK_STEP
    jne .for_nostep
    ; step present — disable static path by clearing sentinel
    mov byte [for_start_tok], 0
    call lexer_next             ; skip 'step'
    cmp byte [tok_type], TOK_INT_LIT
    jne .for_nostep
    mov rdi, [tok_int]
    call codegen_set_for_step
    call lexer_next             ; skip step value
.for_nostep:
    ; static-bounds check: were both bounds compile-time integer literals?
    cmp byte [for_start_tok], TOK_INT_LIT
    jne .for_dynamic
    cmp byte [for_end_tok], TOK_INT_LIT
    jne .for_dynamic
    ; static path: rollback the emitted start/end init code — codegen_emit_for_start
    ; will re-emit the init using optimal encodings and then pin i to r15 (O2).
    mov rax, [for_rollback_idx]
    mov [out_idx], rax
    xor r13, r13                ; no i_fe var in static path
    jmp .for_le_alloc
.for_dynamic:
    ; dynamic path: store rax (end value) into a dedicated i_fe runtime variable
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
    mov byte [o13_inhibit], 1      ; suppress O13 promotion: synthetic i_fe end-value store
    call codegen_emit_store_rax_to_var
    mov byte [o13_inhibit], 0
.for_le_alloc:
    ; allocate __le flag var for loop-else (reclaimed by scope_stack at loop exit)
    push r13
    push r14
    lea rdi, [le_name]
    xor rsi, rsi
    mov dl, 0
    mov cl, TYPE_BOOL
    call var_add
    pop r14
    pop r13
    cmp rax, -1
    jne .for_le_ok
    mov rdi, -1
    call codegen_push_loop_else_flag
    jmp .for_le_cont
.for_le_ok:
    push rax
    mov rdi, rax
    call codegen_push_loop_else_flag
    pop rdi
    push r13
    push r14
    call codegen_emit_zero_var  ; emit: mov qword [__le], 0  (9 bytes, not 18)
    pop r14
    pop r13
.for_le_cont:
    ; O26: mark current proto as having a for-loop (call-site pin-save skip opt)
    cmp qword [prot_body_depth], 0
    je .for_no_mark
    mov rax, [cur_proto_idx]
    imul rax, PROTO_ENTRY_SIZE
    lea rcx, [proto_table]
    mov byte [rcx + rax + 46], 1
.for_no_mark:
    ; dispatch: static bounds → register-pinned loop, dynamic → memory-based loop
    cmp byte [for_start_tok], TOK_INT_LIT
    jne .for_start_dyn
    ; static: constant bounds let codegen_emit_for_start pin i to r15 (O2)
    mov rdi, r14
    mov rsi, [for_start_val]
    mov rdx, [for_end_val]
    call codegen_emit_for_start
    jmp .for_started
.for_start_dyn:
    mov rdi, r14
    mov rsi, r13
    call codegen_emit_for_start_dyn
.for_started:
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
    ; restore var_count — reclaim synthetic loop vars (#37, __le)
    dec qword [scope_depth]
    mov rax, [scope_depth]
    lea rcx, [scope_stack]
    mov rbx, [rcx+rax*8]
    mov [var_count], rbx
    ; pop loop-else flag + handle optional else: clause
    call codegen_pop_loop_else_flag  ; rax = le_var_idx or -1
    cmp byte [tok_type], TOK_ELSE
    jne .for_no_else
    cmp rax, -1
    je .for_no_else
    mov r14, rax                     ; r14 = le_var_idx (loop_var no longer needed)
    mov rdi, r14
    call codegen_emit_mov_rax_var    ; load __le into rax
    call codegen_emit_test_rax_jnz   ; jnz = stop was taken → skip else body
    call lexer_next                   ; skip 'else'
    call lexer_next                   ; skip ':'
    cmp byte [tok_type], TOK_NEWLINE
    jne .for_el_in
    call lexer_next
.for_el_in:
    cmp byte [tok_type], TOK_INDENT
    jne .for_ell
    call lexer_next
.for_ell:
    movzx eax, byte [tok_type]
    cmp al, TOK_EOF
    je .for_el_end
    cmp al, TOK_DEDENT
    je .for_el_end
    call parse_stmt
    jmp .for_ell
.for_el_end:
    cmp byte [tok_type], TOK_DEDENT
    jne .for_el_done
    call lexer_next
.for_el_done:
    call codegen_patch_jump           ; patch the jnz past the else body
    jmp .done
.for_no_else:
    jmp .done

; ── while loop ────────────────────────────────────────────────────────────────
.while:
    call lexer_next
    ; save scope for __le flag var (loop-else support)
    mov rbx, [scope_depth]
    lea rcx, [scope_stack]
    mov rax, [var_count]
    mov [rcx+rbx*8], rax
    inc qword [scope_depth]
    ; allocate + init __le flag BEFORE loop_top so init runs only once
    lea rdi, [le_name]
    xor rsi, rsi
    mov dl, 0
    mov cl, TYPE_BOOL
    call var_add
    cmp rax, -1
    jne .whl_le_ok
    mov rdi, -1
    call codegen_push_loop_else_flag
    jmp .whl_le_cont
.whl_le_ok:
    push rax
    mov rdi, rax
    call codegen_push_loop_else_flag
    pop rdi
    xor rsi, rsi
    call codegen_emit_assign_var     ; emit: __le = 0
.whl_le_cont:
    ; O31: emit 16-byte NOP prolog placeholder (register-promotes loop vars into r12/r13)
    call codegen_emit_while_start
    ; save loop top (AFTER prolog, BEFORE condition check)
    mov r15, [out_idx]
    mov rdi, r15
    call codegen_push_cont
    call parse_expr
    call codegen_emit_test_rax_jz
    call codegen_emit_loop_base
    ; O26: mark current proto as having a while-loop
    cmp qword [prot_body_depth], 0
    je .whl_no_mark
    mov rax, [cur_proto_idx]
    imul rax, PROTO_ENTRY_SIZE
    lea rcx, [proto_table]
    mov byte [rcx + rax + 46], 1
.whl_no_mark:
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
    call codegen_pop_loop_else_flag  ; rax = le_var_idx or -1
    mov r14, rax                     ; save le_var_idx (r15 no longer needed)
    ; restore scope (reclaim __le var)
    dec qword [scope_depth]
    mov rax, [scope_depth]
    lea rcx, [scope_stack]
    mov rbx, [rcx+rax*8]
    mov [var_count], rbx
    ; check for loop else:
    cmp byte [tok_type], TOK_ELSE
    jne .whl_no_else
    cmp r14, -1
    je .whl_no_else
    mov rdi, r14
    call codegen_emit_mov_rax_var    ; load __le into rax
    call codegen_emit_test_rax_jnz   ; jnz = stop taken → skip else body
    call lexer_next                   ; skip 'else'
    call lexer_next                   ; skip ':'
    cmp byte [tok_type], TOK_NEWLINE
    jne .whl_el_in
    call lexer_next
.whl_el_in:
    cmp byte [tok_type], TOK_INDENT
    jne .whl_ell
    call lexer_next
.whl_ell:
    movzx eax, byte [tok_type]
    cmp al, TOK_EOF
    je .whl_el_end
    cmp al, TOK_DEDENT
    je .whl_el_end
    call parse_stmt
    jmp .whl_ell
.whl_el_end:
    cmp byte [tok_type], TOK_DEDENT
    jne .whl_el_done
    call lexer_next
.whl_el_done:
    call codegen_patch_jump           ; patch the jnz past the else body
    jmp .done
.whl_no_else:
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
    ; Patch any pending forward references to this protocol
    push r13
    mov rdi, r13
    call patch_forward_refs
    pop r13
    mov byte [r13+40], 0
    mov byte [r13+46], 0    ; clear has_loop flag for new proto
    mov byte [r13+47], 0
    mov rax, [proto_count]
    mov [cur_proto_idx], rax
    mov [codegen_cur_proto_seq_idx], rax   ; O27: tell codegen which proto we are compiling
    inc qword [proto_count]
    ; O20: reset self-recursive flag for this protocol
    mov byte [proto_is_self_recursive], 0
    ; @memo: latch memo flag if requested by 'memo' keyword
    cmp byte [next_proto_memo], 0
    je .prot_no_memo_set
    mov byte [proto_memo_active], 1
    mov byte [next_proto_memo], 0
    jmp .prot_memo_latch
.prot_no_memo_set:
    mov byte [proto_memo_active], 0
.prot_memo_latch:
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
    ; skip optional type keyword before param name (typed params: int a, float b, ...)
    cmp byte [tok_type], TOK_TYPE_INT
    je .prot_skip_type
    cmp byte [tok_type], TOK_TYPE_FLOAT
    je .prot_skip_type
    cmp byte [tok_type], TOK_TYPE_BOOL
    je .prot_skip_type
    cmp byte [tok_type], TOK_TYPE_STR
    je .prot_skip_type
    cmp byte [tok_type], TOK_TYPE_SEQ
    je .prot_skip_type
    jmp .prot_check_ident
.prot_skip_type:
    call lexer_next
.prot_check_ident:
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
    cmp r12, 6
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
    ; B-1: save compile-time param count + indices for per-call frame codegen
    mov [cur_proto_param_count], r12b
    push r14
    xor r14, r14
.prot_pidx:
    cmp r14, r12
    jge .prot_pidx_done
    movzx rax, byte [r13+41+r14]
    mov [cur_proto_param_vars+r14], al
    inc r14
    jmp .prot_pidx
.prot_pidx_done:
    pop r14
    cmp byte [tok_type], TOK_RPAREN
    jne .prot_nobody
    call lexer_next
    cmp byte [tok_type], TOK_ARROW
    jne .prot_push_old
    call lexer_next
    call lexer_next
.prot_push_old:
    ; O1: stack-frame optimisation — emit push rbp/mov rbp,rsp/sub rsp,N*8
    ; then store each param register to [rbp-(K+1)*8], no global spill
    ; register params with codegen frame tracking
    push r12
    push r13
    mov rdi, r12
    lea rsi, [r13+41]
    call codegen_set_frame
    ; emit frame prologue
    mov rdi, r12
    call codegen_emit_frame_prologue
    pop r13
    pop r12
    ; emit frame-relative param stores: REX 89 ModRM disp8
    ; O18: skip params K < regalloc_cnt (already in r12/r13 via frame_prologue)
    ; O18: displacement offset by regalloc_cnt (callee-save slots at top of frame)
    ; O4: capture TCO entry point (start of param stores)
    mov rax, [out_idx]
    mov [tco_body_entry], rax
    xor r14, r14
.prot_fs:
    cmp r14, r12
    jge .prot_nobody
    cmp r14, 6
    jge .prot_nobody
    ; O18: skip regalloc params (loaded into r12/r13 by frame_prologue)
    movzx rax, byte [regalloc_cnt]
    cmp r14, rax
    jl .prot_fs_next
    cmp r14, 4
    jge .prot_fs_rex_r
    mov al, 0x48
    jmp .prot_fs_emit
.prot_fs_rex_r:
    mov al, 0x4C
.prot_fs_emit:
    call emit_b_indirect
    mov al, 0x89
    call emit_b_indirect
    ; ModRM byte for [rsp+disp8] destination (rm=100 → SIB follows)
    lea rax, [rel .prot_fs_mrm]
    movzx ecx, byte [rax+r14]
    mov al, cl
    call emit_b_indirect
    ; SIB = 0x24 (scale=0, index=none, base=rsp)
    mov al, 0x24
    call emit_b_indirect
    ; disp8 = (K+regalloc_cnt)*8  (FLC: positive rsp-relative offset, bottom-up slots)
    movzx rax, byte [regalloc_cnt]
    add rax, r14
    shl al, 3
    call emit_b_indirect
.prot_fs_next:
    inc r14
    jmp .prot_fs
.prot_fs_mrm: db 0x7C, 0x74, 0x54, 0x4C, 0x44, 0x4C

.prot_nobody:
    ; @memo: emit cache lookup check at body entry (before any user code)
    cmp byte [proto_memo_active], 0
    je .prot_no_memo_check
    mov rdi, [cur_proto_idx]
    call codegen_emit_memo_check
.prot_no_memo_check:
    ; save var_count for protocol-level scoping (subtract param count so restore gives pre-param value)
    mov rax, [scope_depth]
    lea rcx, [scope_stack]
    mov rbx, [var_count]
    movzx rdx, byte [cur_proto_param_count]
    sub rbx, rdx
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
    call proto_emit_restore     ; O1: emit leave (frame teardown)
    call codegen_emit_ret
    call codegen_clear_frame
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
    ; O4: enable TCO detection for this return expression
    cmp qword [prot_body_depth], 0
    jle .ret_notco
    mov byte [tco_return_active], 1
    mov byte [tco_was_emitted], 0
.ret_notco:
    call parse_expr
    ; store return type into current proto entry (B-8 fix)
    mov rax, [cur_proto_idx]
    imul rax, PROTO_ENTRY_SIZE
    lea rbx, [proto_table]
    add rbx, rax
    movzx ecx, byte [cur_type]
    mov [rbx+47], cl
    ; O4: if TCO jmp was emitted by parse_expr → skip leave+ret
    cmp byte [tco_was_emitted], 1
    je .ret_tco_done
    call proto_emit_restore     ; O1: emit leave
    call codegen_emit_ret
.ret_tco_done:
    mov byte [tco_return_active], 0
    ; DO NOT call codegen_clear_frame here — body parsing continues after return
    jmp .done
.ret_bare:
    call proto_emit_restore     ; O1: emit leave
    call codegen_emit_ret
    ; DO NOT call codegen_clear_frame here
    jmp .done

; ── stop / skip / pass ────────────────────────────────────────────────────────
.stop:
    call lexer_next
    xor rdi, rdi
    cmp byte [tok_type], TOK_INT_LIT
    jne .stop_emit
    mov rdi, [tok_int]
    test rdi, rdi
    jz .stop_emit
    dec rdi
    call lexer_next
.stop_emit:
    call codegen_emit_break
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

; ── unreachable — emit ud2 (0F 0B) ───────────────────────────────────────────
.unreachable:
    mov al, 0x0F
    call emit_b_indirect
    mov al, 0x0B
    call emit_b_indirect
    call lexer_next
    jmp .done

; ── assert expr — eval condition, ud2 if zero ────────────────────────────────
.assert:
    call lexer_next             ; skip 'assert'
    call parse_expr             ; condition → rax at runtime
    ; emit: test rax, rax
    mov al, 0x48
    call emit_b_indirect
    mov al, 0x85
    call emit_b_indirect
    mov al, 0xC0
    call emit_b_indirect
    ; emit: jnz +2 (skip ud2 when condition true)
    mov al, 0x75
    call emit_b_indirect
    mov al, 0x02
    call emit_b_indirect
    ; emit: ud2 (0F 0B)
    mov al, 0x0F
    call emit_b_indirect
    mov al, 0x0B
    call emit_b_indirect
    jmp .done

; ── repeat N: — counted loop, hidden counter var ─────────────────────────────
.repeat:
    call lexer_next             ; skip 'repeat'
    call parse_expr             ; emit N-loading code; result in rax at runtime
    ; save var_count for scope reclaim
    mov rbx, [scope_depth]
    lea rcx, [scope_stack]
    mov r13, [var_count]
    mov [rcx+rbx*8], r13
    inc qword [scope_depth]
    ; allocate hidden counter var "__rp"
    sub rsp, 64
    mov byte [rsp+0], '_'
    mov byte [rsp+1], '_'
    mov byte [rsp+2], 'r'
    mov byte [rsp+3], 'p'
    mov byte [rsp+4], 0
    mov rdi, rsp
    xor rsi, rsi
    mov dl, 0
    mov cl, TYPE_INT
    call var_add
    add rsp, 64
    cmp rax, -1
    je .done
    mov r14, rax                ; r14 = hidden counter var index
    ; emit: mov [cnt_addr], rax  (store N into counter)
    mov rdi, r14
    call codegen_emit_store_rax_to_var
    ; allocate __le flag var for repeat-else (reclaimed by scope_stack)
    push r14
    push r15
    lea rdi, [le_name]
    xor rsi, rsi
    mov dl, 0
    mov cl, TYPE_BOOL
    call var_add
    pop r15
    pop r14
    cmp rax, -1
    jne .rpt_le_ok
    mov rdi, -1
    call codegen_push_loop_else_flag
    jmp .rpt_le_cont
.rpt_le_ok:
    push rax
    mov rdi, rax
    call codegen_push_loop_else_flag
    pop rdi
    xor rsi, rsi
    push r14
    push r15
    call codegen_emit_assign_var
    pop r15
    pop r14
.rpt_le_cont:
    ; save loop-top offset for back-jump
    mov r15, [out_idx]
    mov rdi, r15
    call codegen_push_cont
    ; emit: mov rax, [cnt_addr]; test rax,rax; jz exit_patch
    mov rdi, r14
    call codegen_emit_mov_rax_var
    call codegen_emit_test_rax_jz
    call codegen_emit_loop_base
    ; skip ':', optional newline, optional indent
    call lexer_next
    cmp byte [tok_type], TOK_NEWLINE
    jne .rptl_enter
    call lexer_next
.rptl_enter:
    cmp byte [tok_type], TOK_INDENT
    jne .rptl
    call lexer_next
.rptl:
    movzx eax, byte [tok_type]
    cmp al, TOK_EOF
    je .rptd
    cmp al, TOK_DEDENT
    je .rptd
    call parse_stmt
    jmp .rptl
.rptd:
    cmp byte [tok_type], TOK_DEDENT
    jne .rptnd
    call lexer_next
.rptnd:
    ; emit: dec qword [cnt_addr]
    mov rdi, r14
    call codegen_emit_dec_var
    ; emit: jmp loop_top + patch all breaks
    mov rdi, r15
    call codegen_emit_while_end
    ; restore var_count (reclaim hidden counter var and __le flag var)
    dec qword [scope_depth]
    mov rax, [scope_depth]
    lea rcx, [scope_stack]
    mov rbx, [rcx+rax*8]
    mov [var_count], rbx
    ; pop loop-else flag + handle optional else: clause
    call codegen_pop_loop_else_flag  ; rax = le_var_idx or -1
    cmp byte [tok_type], TOK_ELSE
    jne .rpt_no_else
    cmp rax, -1
    je .rpt_no_else
    mov r14, rax                     ; r14 = le_var_idx (counter no longer needed)
    mov rdi, r14
    call codegen_emit_mov_rax_var    ; load __le into rax
    call codegen_emit_test_rax_jnz   ; jnz = stop taken → skip else body
    call lexer_next                   ; skip 'else'
    call lexer_next                   ; skip ':'
    cmp byte [tok_type], TOK_NEWLINE
    jne .rpt_el_in
    call lexer_next
.rpt_el_in:
    cmp byte [tok_type], TOK_INDENT
    jne .rpt_ell
    call lexer_next
.rpt_ell:
    movzx eax, byte [tok_type]
    cmp al, TOK_EOF
    je .rpt_el_end
    cmp al, TOK_DEDENT
    je .rpt_el_end
    call parse_stmt
    jmp .rpt_ell
.rpt_el_end:
    cmp byte [tok_type], TOK_DEDENT
    jne .rpt_el_done
    call lexer_next
.rpt_el_done:
    call codegen_patch_jump           ; patch the jnz past the else body
    jmp .done
.rpt_no_else:
    jmp .done

; ── each :i in seq — iterate sequence elements ────────────────────────────────
.each:
    call lexer_next                   ; skip 'each'
    cmp byte [tok_type], TOK_COLON
    jne .done
    call lexer_next                   ; skip ':'
    cmp byte [tok_type], TOK_IDENT
    jne .done
    ; save element variable name
    lea rdi, [saved_name]
    lea rsi, [tok_ident]
    call strcpy
    call lexer_next                   ; skip element var name
    ; optional 'in' keyword
    cmp byte [tok_type], TOK_IN
    jne .each_noin
    call lexer_next
.each_noin:
    cmp byte [tok_type], TOK_IDENT
    jne .done
    ; find sequence variable
    sub rsp, 64
    mov rdi, rsp
    lea rsi, [tok_ident]
    call strcpy
    mov rdi, rsp
    call var_find
    add rsp, 64
    cmp rax, -1
    je .done
    mov r12, rax                      ; r12 = seq_var_idx
    call lexer_next                   ; skip seq name
    ; save scope for synthetic vars
    mov rbx, [scope_depth]
    lea rcx, [scope_stack]
    mov rax, [var_count]
    mov [rcx+rbx*8], rax
    inc qword [scope_depth]
    ; add element variable (TYPE_INT stores the loaded element value)
    lea rdi, [saved_name]
    xor rsi, rsi
    mov dl, 0
    mov cl, TYPE_INT
    call var_add
    cmp rax, -1
    je .each_scope_pop
    mov r13, rax                      ; r13 = elem_var_idx
    ; add hidden counter var "__ec"
    sub rsp, 8
    mov byte [rsp+0], '_'
    mov byte [rsp+1], '_'
    mov byte [rsp+2], 'e'
    mov byte [rsp+3], 'c'
    mov byte [rsp+4], 0
    mov rdi, rsp
    xor rsi, rsi
    mov dl, 0
    mov cl, TYPE_INT
    call var_add
    add rsp, 8
    cmp rax, -1
    je .each_scope_pop
    mov r14, rax                      ; r14 = ctr_var_idx
    ; allocate __le flag var (for each-else)
    push r12
    push r13
    push r14
    lea rdi, [le_name]
    xor rsi, rsi
    mov dl, 0
    mov cl, TYPE_BOOL
    call var_add
    pop r14
    pop r13
    pop r12
    cmp rax, -1
    jne .each_le_ok
    mov rdi, -1
    call codegen_push_loop_else_flag
    jmp .each_le_cont
.each_le_ok:
    push rax
    mov rdi, rax
    call codegen_push_loop_else_flag
    pop rdi
    xor rsi, rsi
    push r12
    push r13
    push r14
    call codegen_emit_assign_var      ; emit: __le = 0
    pop r14
    pop r13
    pop r12
.each_le_cont:
    ; emit loop preamble + condition check; returns loop_top_pc in rax
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    call codegen_emit_each_start
    mov r15, rax                      ; r15 = loop_top_pc
    ; skip ':', optional newline + indent
    call lexer_next
    cmp byte [tok_type], TOK_NEWLINE
    jne .each_enter
    call lexer_next
.each_enter:
    cmp byte [tok_type], TOK_INDENT
    jne .eachl
    call lexer_next
.eachl:
    movzx eax, byte [tok_type]
    cmp al, TOK_EOF
    je .eachd
    cmp al, TOK_DEDENT
    je .eachd
    call parse_stmt
    jmp .eachl
.eachd:
    cmp byte [tok_type], TOK_DEDENT
    jne .eachnd
    call lexer_next
.eachnd:
    ; emit counter increment + back-jump + patch exits
    mov rdi, r15
    mov rsi, r14
    call codegen_emit_each_end
    ; restore scope (reclaim elem, __ec, __le vars)
    dec qword [scope_depth]
    mov rax, [scope_depth]
    lea rcx, [scope_stack]
    mov rbx, [rcx+rax*8]
    mov [var_count], rbx
    ; pop loop-else flag + handle optional else: clause
    call codegen_pop_loop_else_flag  ; rax = le_var_idx or -1
    cmp byte [tok_type], TOK_ELSE
    jne .each_no_else
    cmp rax, -1
    je .each_no_else
    mov r14, rax
    mov rdi, r14
    call codegen_emit_mov_rax_var    ; load __le into rax
    call codegen_emit_test_rax_jnz   ; jnz = stop taken → skip else body
    call lexer_next                   ; skip 'else'
    call lexer_next                   ; skip ':'
    cmp byte [tok_type], TOK_NEWLINE
    jne .each_el_in
    call lexer_next
.each_el_in:
    cmp byte [tok_type], TOK_INDENT
    jne .each_ell
    call lexer_next
.each_ell:
    movzx eax, byte [tok_type]
    cmp al, TOK_EOF
    je .each_el_end
    cmp al, TOK_DEDENT
    je .each_el_end
    call parse_stmt
    jmp .each_ell
.each_el_end:
    cmp byte [tok_type], TOK_DEDENT
    jne .each_el_done
    call lexer_next
.each_el_done:
    call codegen_patch_jump           ; patch the jnz past else body
    jmp .done
.each_no_else:
    jmp .done
.each_scope_pop:
    ; clean up scope on early exit
    dec qword [scope_depth]
    mov rax, [scope_depth]
    lea rcx, [scope_stack]
    mov rbx, [rcx+rax*8]
    mov [var_count], rbx
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
    ; issue #25: guard against non-string argument — passing an int as a pointer
    ; to rt_err's strlen loop causes a segfault.  If the expression is not a
    ; string, print the value via the appropriate printer then exit(1) cleanly.
    cmp byte [cur_type], TYPE_STR
    jne .err_not_str
    call codegen_emit_mov_rdi_rax
    call codegen_emit_call_rt_err
    jmp .done
.err_not_str:
    ; emit: output the value using the correct printer for cur_type, then exit(1)
    movzx edi, byte [cur_type]
    call codegen_output_rax
    call codegen_emit_exit1
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

; ── ident.push(expr) — method-call syntax for seq operations ──────────────────
; Syntax: data.push(value)
; Saves ident, peeks for DOT, checks method name, parses (expr), emits seq_push.
.ident_stmt:
    lea rdi, [saved_name]
    lea rsi, [tok_ident]
    call strcpy
    call lexer_next
    cmp byte [tok_type], TOK_ASSIGN   ; bare assignment: name = expr (no leading colon)
    je .ident_assign
    cmp byte [tok_type], TOK_DOT
    jne .done
    call lexer_next
    movzx eax, byte [tok_type]
    cmp al, TOK_PUSH
    je .ident_push
    cmp al, TOK_POP
    je .ident_pop
    cmp al, TOK_LEN
    je .ident_len
    jmp .done
.ident_push:
    call lexer_next
    cmp byte [tok_type], TOK_LPAREN
    jne .done
    lea rdi, [saved_name]
    call var_find
    cmp rax, -1
    je .done
    sub rsp, 16             ; allocate stack slot (maintains 8-misalign for calls)
    mov [rsp], rax          ; save var_idx
    call lexer_next         ; consume LPAREN
    call parse_expr         ; parse value expression (emits runtime code)
    cmp byte [tok_type], TOK_RPAREN
    jne .ident_push_emit
    call lexer_next         ; consume RPAREN
.ident_push_emit:
    mov rdi, [rsp]          ; restore var_idx
    add rsp, 16
    call codegen_emit_seq_push
    jmp .done
.ident_pop:
    call lexer_next
    cmp byte [tok_type], TOK_LPAREN
    jne .ident_pop_do
    call lexer_next
    cmp byte [tok_type], TOK_RPAREN
    jne .done
    call lexer_next
.ident_pop_do:
    lea rdi, [saved_name]
    call var_find
    cmp rax, -1
    je .done
    mov rdi, rax
    call codegen_emit_seq_pop_rax
    jmp .done
.ident_len:
    call lexer_next
    cmp byte [tok_type], TOK_LPAREN
    jne .ident_len_do
    call lexer_next
    cmp byte [tok_type], TOK_RPAREN
    jne .done
    call lexer_next
.ident_len_do:
    lea rdi, [saved_name]
    call var_find
    cmp rax, -1
    je .done
    mov rdi, rax
    call codegen_emit_seq_len_rax
    jmp .done

; ── bare compound assignment: name = expr (without leading ':') ─────────────
; Supports order-of-operations via the full parse_expr → parse_comparison →
; parse_additive (+/-) → parse_term (*/ %) → parse_unary hierarchy.
; Example: a = 3 * 4 + 2 / 5  (mul/div bind tighter than add/sub)
.ident_assign:
    lea rdi, [saved_name]
    call var_find
    cmp rax, -1
    jne .ident_assign_existing
    ; type inference: x = literal
    ; only if tok_type is literal
    movzx ecx, byte [cur_type]
    cmp cl, 0
    je .done
    lea rdi, [saved_name]
    xor rsi, rsi
    mov dl, 1
    ; cl already has cur_type
    call var_add
    cmp rax, -1
    je .done
.ident_assign_existing:
    mov r14, rax
    ; check const
    shl rax, 6
    lea rcx, [var_table]
    add rcx, rax
    cmp byte [rcx+42], 1      ; is_const
    je .done                  ; silently fail or emit error
    call lexer_next         ; consume '='
    call parse_expr         ; evaluate RHS with full operator precedence → rax
    mov rdi, r14
    call codegen_emit_store_rax_to_var
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
    ; push when_cond_mode onto mode stack
    lea rcx, [when_mode_stack]
    movzx rbx, byte [when_cond_mode]
    mov [rcx+rax], bl
    inc qword [when_stk_depth]
    call lexer_next
    ; detect cond mode: when: (colon immediately after 'when')
    cmp byte [tok_type], TOK_COLON
    je .when_cond_entry
    mov byte [when_cond_mode], 0
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
.when_cond_entry:
    ; Cond mode: no subject expr, cases are: <expr>: <body>
    mov byte [when_cond_mode], 1
    call codegen_save_chain_base
    mov qword [when_case_count], 0
    call lexer_next             ; skip ':'
    cmp byte [tok_type], TOK_NEWLINE
    jne .when_cond_in
    call lexer_next
.when_cond_in:
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
    cmp byte [when_cond_mode], 1
    je .when_cond_case
    call parse_stmt
    jmp .when_loop
.when_cond_case:
    ; Cond mode case: <expr>: <body>
    cmp qword [when_case_count], 0
    je .when_cc_first
    call codegen_emit_jmp_end
    call codegen_patch_jump
.when_cc_first:
    inc qword [when_case_count]
    call parse_expr             ; condition expr → rax
    call codegen_emit_test_rax_jz
    movzx eax, byte [tok_type]
    cmp al, TOK_COLON
    jne .when_cc_nl
    call lexer_next
.when_cc_nl:
    cmp byte [tok_type], TOK_NEWLINE
    jne .when_cc_in
    call lexer_next
.when_cc_in:
    cmp byte [tok_type], TOK_INDENT
    jne .when_cc_inline
    call lexer_next
.when_cc_multi:
    movzx eax, byte [tok_type]
    cmp al, TOK_EOF
    je .when_loop
    cmp al, TOK_DEDENT
    je .when_cc_md
    cmp al, TOK_ELSE
    je .when_loop
    call parse_stmt
    jmp .when_cc_multi
.when_cc_md:
    call lexer_next             ; consume DEDENT
    jmp .when_loop
.when_cc_inline:
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
    ; clean up __when__ temp var (skip in cond mode — no subject var was added)
    cmp byte [when_cond_mode], 1
    je .when_pop_state
    dec qword [var_count]
.when_pop_state:
    ; pop outer when state (#32)
    dec qword [when_stk_depth]
    mov rax, [when_stk_depth]
    lea rcx, [when_var_stack]
    mov rbx, [rcx+rax*8]
    mov [when_var_idx], rbx
    lea rcx, [when_cnt_stack]
    mov rbx, [rcx+rax*8]
    mov [when_case_count], rbx
    ; restore when_cond_mode from mode stack
    lea rcx, [when_mode_stack]
    movzx rbx, byte [rcx+rax]
    mov [when_cond_mode], bl
    jmp .done

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

; ── patch_forward_refs ──────────────────────────────────────────────────────
; rdi = proto_entry ptr (name at +0, out_idx at +32)
; Scans fwd_ref_names for name matches and patches each out_buffer rel32
patch_forward_refs:
    push rbx
    push rcx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                        ; r12 = proto_entry
    mov r13, [fwd_ref_count]            ; r13 = num forward refs
    test r13, r13
    jz .pfr_done
    xor r14, r14                        ; r14 = loop index
.pfr_loop:
    cmp r14, r13
    jge .pfr_done
    imul r15, r14, 32
    lea rcx, [fwd_ref_names]
    add rcx, r15                        ; rcx = &fwd_ref_names[r14*32]
    ; Compare 32-byte name (4 quadwords)
    mov rax, [rcx]
    cmp rax, [r12]
    jne .pfr_next
    mov rax, [rcx+8]
    cmp rax, [r12+8]
    jne .pfr_next
    mov rax, [rcx+16]
    cmp rax, [r12+16]
    jne .pfr_next
    mov rax, [rcx+24]
    cmp rax, [r12+24]
    jne .pfr_next
    ; Names match — patch rel32 at fwd_ref_patches[r14*8] in out_buffer
    mov rbx, [fwd_ref_patches + r14*8] ; rbx = patch position (where rel32 goes)
    mov rax, [r12+32]                   ; rax = proto start out_idx
    sub rax, rbx                        ; rax = proto_out_idx - patch_pos
    sub rax, 4                          ; rax = rel32 value (rel to end of call instr)
    lea rcx, [out_buffer]
    mov [rcx + rbx], eax                ; write rel32 at patch_pos
.pfr_next:
    inc r14
    jmp .pfr_loop
.pfr_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rcx
    pop rbx
    ret

; ── indirect emit helpers (wired to codegen raw exports) ─────────────────────
emit_b_indirect:
    jmp codegen_emit_b_raw

emit_d_indirect:
    jmp codegen_emit_d_raw

get_var_va_indirect:
    jmp codegen_get_var_va_proxy

; ── proto_emit_restore ────────────────────────────────────────────────────────
; Emit the protocol epilogue: optional memo store, then leave + regalloc restore.
; O21: for push-style (push r12 prologue) the order is leave→pop_r12, not the
;      default regalloc→leave, so that pop r12 undoes the push before sub rsp.
; @memo: emit cache store BEFORE regalloc so r12 still holds the param value.
proto_emit_restore:
    ; @memo: store result to cache (r12 = param, rax = result, must come first)
    cmp byte [proto_memo_active], 0
    je .por_no_memo
    mov rdi, [cur_proto_idx]
    call codegen_emit_memo_store
.por_no_memo:
    ; O21: push-style → leave (add rsp for locals) then pop r12
    cmp byte [push_style_frame], 0
    jne .por_push_style
    ; standard order: regalloc epilogue then leave
    call codegen_emit_regalloc_epilogue
    call codegen_emit_leave
    ret
.por_push_style:
    ; push-style order: leave first (locals), then pop r12 (undoes push r12)
    call codegen_emit_leave
    call codegen_emit_regalloc_epilogue
    ret
