; rxc_codegen.asm — RexC bytecode backend
; Implements the full codegen_* interface that the Rex parser calls,
; emitting RexC opcodes instead of x86-64 machine code.
;
; Accumulator model:
;   r0 = accumulator  (was rax in x86-64 backend)
;   r1 = scratch/temp (was rbx)
;   r2 = spill depth-0 (was r10)
;   r3 = spill depth-1 (was r11)
;
; Variable storage: slot index = var_idx (passed as rdi to load/store)
; Jump patching: relative offsets (target_out_idx - (patch_pos + 4))

default rel
%include "include/rex_defs.inc"
%include "rxc_defs.inc"

; ── Exports (all symbols the parser, main.asm, and other modules need) ────────
global codegen_write_headers, codegen_init, codegen_finish, codegen_finalize
global codegen_output_const, codegen_output_typed, codegen_output_rax
global codegen_patch_jump, codegen_save_chain_base
global codegen_emit_jmp_end, codegen_patch_chain_end
global codegen_begin_protos, codegen_end_protos
global codegen_emit_for_start, codegen_emit_for_end
global codegen_emit_while_start, codegen_emit_while_end
global codegen_emit_break, codegen_patch_breaks, codegen_emit_loop_base
global codegen_emit_ret, codegen_emit_mov_eax_imm32, codegen_emit_mov_rax_imm64
global codegen_emit_call_prot
global codegen_emit_push_var_slot, codegen_emit_pop_var_slot
global codegen_emit_assign_var, codegen_emit_zero_var
global codegen_emit_cmp_var_jne, codegen_emit_unknown_bool
global codegen_emit_mm_switch, codegen_emit_gc_switch
global codegen_emit_test_rax_jnz, codegen_emit_normalize_bool_rax
global actual_prs_va, actual_prq_va, actual_sip_va
global codegen_emit_jmp_get_slot, codegen_patch_slot_to_here
global codegen_emit_push_rax, codegen_emit_pop_rbx
global codegen_emit_expr_save_rax, codegen_emit_expr_restore_rbx
global codegen_emit_expr_spill_save, codegen_emit_expr_spill_restore
global codegen_emit_mov_rax_var, codegen_emit_store_rax_to_var
global push_style_frame
global codegen_emit_memo_check, codegen_emit_memo_store, codegen_emit_memo_reset
global codegen_emit_rdrand_rax, codegen_emit_neg_rax, codegen_emit_not_rax
global codegen_emit_bitwise_not_rax
global codegen_emit_add_rax_rbx, codegen_emit_sub_rax_rbx
global codegen_emit_imul_rax_rbx, codegen_emit_idiv_rbx_by_rax, codegen_emit_imod_rbx_by_rax
global codegen_emit_cmp_rbx_rax_setcc, codegen_emit_test_rax_jz
global codegen_emit_addsd_rax_rbx, codegen_emit_subsd_rax_rbx
global codegen_emit_mulsd_rax_rbx, codegen_emit_divsd_rax_rbx
global codegen_emit_cvttsd2si_rax, codegen_emit_cvtsi2sd_rax, codegen_emit_cvtsi2sd_rbx
global codegen_emit_bitwise_and_rax_rbx, codegen_emit_bitwise_or_rax_rbx
global codegen_emit_bitwise_xor_rax_rbx
global codegen_emit_and_bool_rax_rbx, codegen_emit_or_bool_rax_rbx
global codegen_emit_lnot_int_rax
global codegen_emit_shl_rax_by_rbx, codegen_emit_shr_rax_by_rbx
global codegen_set_frame, codegen_clear_frame, codegen_find_frame_slot
global codegen_emit_frame_prologue, codegen_emit_leave
global codegen_emit_regalloc_epilogue
global regalloc_cnt, regalloc_active
global codegen_emit_jmp_prot
global codegen_add_frame_local
global codegen_emit_str_rax, codegen_emit_str_method
global codegen_emit_seq_alloc, codegen_emit_seq_push, codegen_emit_seq_pop_rax
global codegen_emit_seq_len_rax, codegen_emit_seq_elem_load
global codegen_emit_mov_rdi_rax, codegen_emit_call_rt_err, codegen_emit_exit1
global codegen_emit_for_start_dyn, codegen_emit_arg_pops
global codegen_push_cont, codegen_pop_cont, codegen_emit_skip
global codegen_emit_b_raw, codegen_emit_d_raw, codegen_get_var_va_proxy
global codegen_emit_inc_var, codegen_emit_dec_var
global codegen_emit_swap_vars
global codegen_emit_abs_rax, codegen_emit_cap_rax
global codegen_emit_clock_ms
global codegen_set_for_step, for_step_val
global codegen_push_loop_else_flag, codegen_pop_loop_else_flag, codegen_peek_loop_else_flag
global codegen_emit_each_start, codegen_emit_each_end
global cur_proto_is_unsafe, overflow_err_cnt, compiler_error_count
global codegen_emit_const_decl, codegen_emit_repeat_start, codegen_emit_repeat_end
global codegen_emit_warn_str, codegen_emit_show_rax
global codegen_set_for_step
global codegen_cur_proto_seq_idx, proto_needs_r12_save
global codegen_mark_r12_needed
global codegen_skip_pin_save
global o13_inhibit
global codegen_peephole
global codegen_emit_bounds_check, codegen_emit_overflow_check
global codegen_emit_int2str, codegen_emit_float2str
global codegen_emit_str_concat

; ── External dependencies ─────────────────────────────────────────────────────
extern rxc_emit_b, rxc_emit_d, rxc_emit_q, rxc_emit_name
extern out_buffer, out_idx
extern proto_count, var_table, var_count
extern tok_type, tok_int, tok_ident

; ── BSS: internal state ───────────────────────────────────────────────────────
section .bss

; Jump patch stacks (parallel to x86-64 backend's jump_patch_stack etc.)
rxc_jmp_patch_stk:   resq 64    ; positions of conditional jump operands
rxc_jmp_patch_dep:   resq 1
rxc_end_jmp_stk:     resq 64    ; positions of unconditional end-jumps
rxc_end_jmp_dep:     resq 1
rxc_chain_base_stk:  resq 32    ; elif chain base positions
rxc_chain_base_dep:  resq 1
rxc_break_jmp_stk:   resq 64    ; break jump positions
rxc_break_jmp_dep:   resq 1
rxc_break_base_stk:  resq 32    ; per-loop break base depth
rxc_break_base_dep:  resq 1
rxc_cont_base_stk:   resq 32    ; continue target positions
rxc_cont_base_dep:   resq 1
rxc_cont_type_stk:   resb 32    ; 0=while, 1=for
rxc_skip_jmp_stk:    resq 64
rxc_skip_jmp_dep:    resq 1
rxc_loop_start_stk:  resq 32    ; loop back-jump targets
rxc_loop_start_dep:  resq 1
rxc_loop_else_stk:   resq 32
rxc_loop_else_dep:   resq 1

; Proto / func state
rxc_prot_jmp_pos:    resq 1     ; position of skip-protos jump operand
rxc_prot_jmp_live:   resb 1

; Frame state
rxc_frame_active:    resb 1
rxc_frame_param_cnt: resb 1
rxc_frame_local_cnt: resb 1
rxc_spill_depth:     resb 1

; For-loop state
for_step_val:        resq 1
rxc_for_end_stk:     resq 32    ; end-value stack for for loops
rxc_for_end_dep:     resq 1
rxc_for_var_stk:     resq 32    ; loop var_idx stack
rxc_for_var_dep:     resq 1

; Memo state
rxc_memo_jmp_patch:  resq 1
rxc_memo_end_patch:  resq 1

; Slot-jump state
rxc_slot_jmp_stk:    resq 32
rxc_slot_jmp_dep:    resq 1

; String pool: collects string literals during compilation
; Format: [8-byte count] [count × {4-byte len, len bytes}]
rxc_str_pool_buf:    resb 131072   ; 128KB string pool
rxc_str_pool_idx:    resq 1        ; current write position in pool
rxc_str_pool_cnt:    resq 1        ; number of strings in pool

; Current function name (for FUNC_DEF)
rxc_cur_func_name:   resb 64
rxc_cur_func_namelen: resb 1
rxc_cur_proto_param:  resb 1       ; param count of current proto

; Exported data symbols the parser reads/writes
push_style_frame:    resb 1
regalloc_active:     resb 1
regalloc_cnt:        resb 1
codegen_skip_pin_save: resb 1
codegen_cur_proto_seq_idx: resq 1
proto_needs_r12_save: resb 64
cur_proto_is_unsafe: resb 1
overflow_err_cnt:    resq 1
compiler_error_count: resq 1
o13_inhibit:         resb 1
actual_prs_va:       resq 1
actual_prq_va:       resq 1
actual_sip_va:       resq 1

; ── Data ─────────────────────────────────────────────────────────────────────
section .data
rxc_out_filename: db "output", 0

; ── TEXT ─────────────────────────────────────────────────────────────────────
section .text

; ═══════════════════════════════════════════════════════════════════════════════
; INIT / FINISH
; ═══════════════════════════════════════════════════════════════════════════════

; codegen_write_headers — called first; write the 20-byte .rxc file header
; (entry_point, const_pool, sym_table offsets are patched later in codegen_finish)
codegen_write_headers:
    ; Magic: REXC
    mov dil, RXC_MAGIC_0
    call rxc_emit_b
    mov dil, RXC_MAGIC_1
    call rxc_emit_b
    mov dil, RXC_MAGIC_2
    call rxc_emit_b
    mov dil, RXC_MAGIC_3
    call rxc_emit_b
    ; Version 1.0
    mov dil, RXC_VERSION_MAJ
    call rxc_emit_b
    mov dil, RXC_VERSION_MIN
    call rxc_emit_b
    ; Flags (2 bytes, zero)
    xor edi, edi
    call rxc_emit_b
    call rxc_emit_b
    ; Entry point offset (4 bytes) — placeholder, patched in finish
    xor edi, edi
    call rxc_emit_d
    ; Const pool offset (4 bytes) — placeholder
    xor edi, edi
    call rxc_emit_d
    ; Sym table offset (4 bytes) — placeholder
    xor edi, edi
    call rxc_emit_d
    ret

; codegen_init — rdi = blob mask (ignored for RexC backend)
codegen_init:
    ; Patch header: entry point = current out_idx (= RXC_HEADER_SIZE = 20)
    mov rax, [out_idx]
    lea rcx, [out_buffer]
    mov [rcx+8], eax       ; entry_point at byte offset 8
    ret

; codegen_finish — called last; append string pool, patch const_pool offset, write file
codegen_finish:
    ; Patch const_pool offset = current out_idx
    mov rax, [out_idx]
    lea rcx, [out_buffer]
    mov [rcx+12], eax
    ; Append string pool: [8-byte count] then the pool bytes
    mov rdi, [rxc_str_pool_cnt]
    call rxc_emit_q
    ; Copy pool bytes into out_buffer
    mov rcx, [rxc_str_pool_idx]
    test rcx, rcx
    jz .no_pool
    xor r8, r8
    lea r9, [rxc_str_pool_buf]
    mov r10, [out_idx]
    lea r11, [out_buffer]
.pool_loop:
    cmp r8, rcx
    jge .done_pool
    movzx eax, byte [r9+r8]
    mov [r11+r10], al
    inc r8
    inc r10
    jmp .pool_loop
.done_pool:
    mov [out_idx], r10
.no_pool:
    ; Patch sym_table offset = current out_idx
    mov rax, [out_idx]
    lea rcx, [out_buffer]
    mov [rcx+16], eax
    ret

; codegen_finalize — O27 retroactive elision; no-op in RexC backend
codegen_finalize:
    ret

; ═══════════════════════════════════════════════════════════════════════════════
; INTERNAL HELPERS
; ═══════════════════════════════════════════════════════════════════════════════

; emit a RXC_JMP_F + 4-byte placeholder, push patch pos to rxc_jmp_patch_stk
; (used for conditional forward jumps — if/while condition)
rxc_emit_cond_jmp:
    mov dil, RXC_JMP_F
    call rxc_emit_b
    mov rax, [out_idx]                   ; save position of the 4-byte operand
    mov rbx, [rxc_jmp_patch_dep]
    lea rcx, [rxc_jmp_patch_stk]
    mov [rcx+rbx*8], rax
    inc qword [rxc_jmp_patch_dep]
    xor edi, edi
    call rxc_emit_d
    ret

; patch the last entry in rxc_jmp_patch_stk with (current_out_idx - (saved+4))
rxc_patch_last_cond_jmp:
    dec qword [rxc_jmp_patch_dep]
    mov rbx, [rxc_jmp_patch_dep]
    lea rcx, [rxc_jmp_patch_stk]
    mov rdx, [rcx+rbx*8]                ; saved patch position
    mov rax, [out_idx]
    sub rax, rdx
    sub rax, 4
    lea rcx, [out_buffer]
    mov [rcx+rdx], eax
    ret

; emit RXC_JMP + 4-byte placeholder, push to rxc_end_jmp_stk
rxc_emit_fwd_jmp:
    mov dil, RXC_JMP
    call rxc_emit_b
    mov rax, [out_idx]
    mov rbx, [rxc_end_jmp_dep]
    lea rcx, [rxc_end_jmp_stk]
    mov [rcx+rbx*8], rax
    inc qword [rxc_end_jmp_dep]
    xor edi, edi
    call rxc_emit_d
    ret

; patch the last entry in rxc_end_jmp_stk
rxc_patch_last_fwd_jmp:
    dec qword [rxc_end_jmp_dep]
    mov rbx, [rxc_end_jmp_dep]
    lea rcx, [rxc_end_jmp_stk]
    mov rdx, [rcx+rbx*8]
    mov rax, [out_idx]
    sub rax, rdx
    sub rax, 4
    lea rcx, [out_buffer]
    mov [rcx+rdx], eax
    ret

; ═══════════════════════════════════════════════════════════════════════════════
; OUTPUT (print)
; ═══════════════════════════════════════════════════════════════════════════════

; codegen_output_const — rdi=int_value: load imm into r0, print
codegen_output_const:
    push rbx
    mov rbx, rdi           ; save value
    mov dil, RXC_LOAD_IMM
    call rxc_emit_b
    mov dil, RXC_R0
    call rxc_emit_b
    mov rdi, rbx
    call rxc_emit_q        ; emit 8-byte immediate
    mov dil, RXC_PRINT_INT
    call rxc_emit_b
    pop rbx
    ret

; codegen_output_typed — rdi=value, rsi=type: load imm, print typed
codegen_output_typed:
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    ; Emit LOAD_IMM r0, value
    mov dil, RXC_LOAD_IMM
    call rxc_emit_b
    mov dil, RXC_R0
    call rxc_emit_b
    mov rdi, rbx
    call rxc_emit_q
    ; Select print opcode by type
    cmp r12, TYPE_FLOAT
    je .pf
    cmp r12, TYPE_STR
    je .ps
    cmp r12, TYPE_BOOL
    je .pb
    mov dil, RXC_PRINT_INT
    jmp .emit
.pf: mov dil, RXC_PRINT_FLOAT
    jmp .emit
.ps: mov dil, RXC_PRINT_STR
    jmp .emit
.pb: mov dil, RXC_PRINT_BOOL
.emit:
    call rxc_emit_b
    pop r12
    pop rbx
    ret

; codegen_output_rax — print r0 (type already in r0)
codegen_output_rax:
    mov dil, RXC_PRINT_INT
    call rxc_emit_b
    ret

codegen_emit_show_rax:
    mov dil, RXC_SHOW_INT
    call rxc_emit_b
    ret

codegen_emit_warn_str:
    mov dil, RXC_WARN_STR
    call rxc_emit_b
    ret

codegen_emit_str_rax:
    mov dil, RXC_PRINT_STR
    call rxc_emit_b
    ret

; ═══════════════════════════════════════════════════════════════════════════════
; VARIABLE LOAD / STORE
; ═══════════════════════════════════════════════════════════════════════════════

; codegen_emit_mov_rax_var — rdi=var_idx: emit LOAD_MEM r0, slot
codegen_emit_mov_rax_var:
    push rbx
    mov rbx, rdi
    mov dil, RXC_LOAD_MEM
    call rxc_emit_b
    mov edi, ebx
    call rxc_emit_d
    pop rbx
    ret

; codegen_emit_store_rax_to_var — rdi=var_idx: emit STORE_MEM slot, r0
codegen_emit_store_rax_to_var:
    push rbx
    mov rbx, rdi
    mov dil, RXC_STORE_MEM
    call rxc_emit_b
    mov edi, ebx
    call rxc_emit_d
    pop rbx
    ret

; codegen_emit_assign_var — rdi=var_idx, rsi=value: LOAD_IMM + STORE_MEM
codegen_emit_assign_var:
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    mov dil, RXC_LOAD_IMM
    call rxc_emit_b
    mov dil, RXC_R0
    call rxc_emit_b
    mov rdi, r12
    call rxc_emit_q
    mov dil, RXC_STORE_MEM
    call rxc_emit_b
    mov edi, ebx
    call rxc_emit_d
    pop r12
    pop rbx
    ret

; codegen_emit_zero_var — rdi=var_idx: store 0 to slot
codegen_emit_zero_var:
    push rbx
    mov rbx, rdi
    mov dil, RXC_LOAD_IMM
    call rxc_emit_b
    mov dil, RXC_R0
    call rxc_emit_b
    xor edi, edi
    call rxc_emit_q
    mov dil, RXC_STORE_MEM
    call rxc_emit_b
    mov edi, ebx
    call rxc_emit_d
    pop rbx
    ret

; codegen_emit_inc_var — rdi=var_idx: LOAD_MEM, INC, STORE_MEM
codegen_emit_inc_var:
    push rbx
    mov rbx, rdi
    mov dil, RXC_LOAD_MEM
    call rxc_emit_b
    mov edi, ebx
    call rxc_emit_d
    mov dil, RXC_INC
    call rxc_emit_b
    mov dil, RXC_STORE_MEM
    call rxc_emit_b
    mov edi, ebx
    call rxc_emit_d
    pop rbx
    ret

; codegen_emit_dec_var — rdi=var_idx
codegen_emit_dec_var:
    push rbx
    mov rbx, rdi
    mov dil, RXC_LOAD_MEM
    call rxc_emit_b
    mov edi, ebx
    call rxc_emit_d
    mov dil, RXC_DEC
    call rxc_emit_b
    mov dil, RXC_STORE_MEM
    call rxc_emit_b
    mov edi, ebx
    call rxc_emit_d
    pop rbx
    ret

; codegen_emit_swap_vars — rdi=var_idx_a, rsi=var_idx_b
codegen_emit_swap_vars:
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    ; load a into r0, b into r1
    mov dil, RXC_LOAD_MEM
    call rxc_emit_b
    mov edi, ebx
    call rxc_emit_d
    mov dil, RXC_PUSH
    call rxc_emit_b
    mov dil, RXC_R0
    call rxc_emit_b
    mov dil, RXC_LOAD_MEM
    call rxc_emit_b
    mov edi, r12d
    call rxc_emit_d
    ; store r0 (b) into a
    mov dil, RXC_STORE_MEM
    call rxc_emit_b
    mov edi, ebx
    call rxc_emit_d
    ; pop old a into r0, store into b
    mov dil, RXC_POP
    call rxc_emit_b
    mov dil, RXC_R0
    call rxc_emit_b
    mov dil, RXC_STORE_MEM
    call rxc_emit_b
    mov edi, r12d
    call rxc_emit_d
    pop r12
    pop rbx
    ret

; codegen_emit_cmp_var_jne — rdi=var_idx, rsi=value: load var, cmp imm, JMP_T past
; (used for loop-else flag check)
codegen_emit_cmp_var_jne:
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
    mov dil, RXC_LOAD_MEM
    call rxc_emit_b
    mov edi, ebx
    call rxc_emit_d
    ; r0 = var; load r1 = r12
    mov dil, RXC_LOAD_IMM
    call rxc_emit_b
    mov dil, RXC_R1
    call rxc_emit_b
    mov rdi, r12
    call rxc_emit_q
    mov dil, RXC_CMP_NE
    call rxc_emit_b
    ; JMP_T placeholder (jump if r0!=0, i.e. var != value)
    mov dil, RXC_JMP_T
    call rxc_emit_b
    mov rax, [out_idx]
    mov rbx, [rxc_jmp_patch_dep]
    lea rcx, [rxc_jmp_patch_stk]
    mov [rcx+rbx*8], rax
    inc qword [rxc_jmp_patch_dep]
    xor edi, edi
    call rxc_emit_d
    pop r12
    pop rbx
    ret

codegen_emit_get_var_va_proxy:
codegen_get_var_va_proxy:
    ; rdi=var_idx → return the "address" as slot_idx*8 (proxy for VA)
    ; The runtime will interpret this as a slot reference
    imul rdi, rdi, 8
    mov rax, rdi
    ret

; ═══════════════════════════════════════════════════════════════════════════════
; LOAD IMMEDIATE (integer/float values)
; ═══════════════════════════════════════════════════════════════════════════════

; codegen_emit_mov_eax_imm32 — rdi=imm32: LOAD_IMM r0, imm (sign-extended)
codegen_emit_mov_eax_imm32:
    push rbx
    mov rbx, rdi
    mov dil, RXC_LOAD_IMM
    call rxc_emit_b
    mov dil, RXC_R0
    call rxc_emit_b
    mov rdi, rbx
    call rxc_emit_q
    pop rbx
    ret

; codegen_emit_mov_rax_imm64 — rdi=imm64: LOAD_IMM r0, imm
codegen_emit_mov_rax_imm64:
    push rbx
    mov rbx, rdi
    mov dil, RXC_LOAD_IMM
    call rxc_emit_b
    mov dil, RXC_R0
    call rxc_emit_b
    mov rdi, rbx
    call rxc_emit_q
    pop rbx
    ret

; ═══════════════════════════════════════════════════════════════════════════════
; STACK OPERATIONS (push/pop accumulator)
; ═══════════════════════════════════════════════════════════════════════════════

codegen_emit_push_rax:
    mov dil, RXC_PUSH
    call rxc_emit_b
    mov dil, RXC_R0
    call rxc_emit_b
    ret

codegen_emit_pop_rbx:
    mov dil, RXC_POP
    call rxc_emit_b
    mov dil, RXC_R1
    call rxc_emit_b
    ret

; Expression spill: push r0 to a depth-indexed spill slot
codegen_emit_expr_save_rax:
codegen_emit_expr_spill_save:
    movzx edi, byte [rxc_spill_depth]
    push rbx
    mov rbx, rdi
    mov dil, RXC_SPILL_SAVE
    call rxc_emit_b
    mov dil, bl
    call rxc_emit_b
    inc byte [rxc_spill_depth]
    pop rbx
    ret

; Expression restore: pop from depth into r1
codegen_emit_expr_restore_rbx:
codegen_emit_expr_spill_restore:
    dec byte [rxc_spill_depth]
    movzx edi, byte [rxc_spill_depth]
    push rbx
    mov rbx, rdi
    mov dil, RXC_SPILL_LOAD
    call rxc_emit_b
    mov dil, bl
    call rxc_emit_b
    pop rbx
    ret

; ═══════════════════════════════════════════════════════════════════════════════
; ARITHMETIC — INTEGER
; ═══════════════════════════════════════════════════════════════════════════════

codegen_emit_add_rax_rbx:
    mov dil, RXC_ADD
    call rxc_emit_b
    ret

codegen_emit_sub_rax_rbx:
    mov dil, RXC_SUB
    call rxc_emit_b
    ret

codegen_emit_imul_rax_rbx:
    mov dil, RXC_MUL
    call rxc_emit_b
    ret

codegen_emit_idiv_rbx_by_rax:
    mov dil, RXC_DIV
    call rxc_emit_b
    ret

codegen_emit_imod_rbx_by_rax:
    mov dil, RXC_MOD
    call rxc_emit_b
    ret

codegen_emit_neg_rax:
    mov dil, RXC_NEG
    call rxc_emit_b
    ret

codegen_emit_abs_rax:
    mov dil, RXC_IABS
    call rxc_emit_b
    ret

codegen_emit_cap_rax:
    ; cap — clamp to 0..1 (used for Kleene logic, treated as BOOL_NORM)
    mov dil, RXC_BOOL_NORM
    call rxc_emit_b
    ret

; ═══════════════════════════════════════════════════════════════════════════════
; ARITHMETIC — FLOAT
; ═══════════════════════════════════════════════════════════════════════════════

codegen_emit_addsd_rax_rbx:
    mov dil, RXC_FADD
    call rxc_emit_b
    ret

codegen_emit_subsd_rax_rbx:
    mov dil, RXC_FSUB
    call rxc_emit_b
    ret

codegen_emit_mulsd_rax_rbx:
    mov dil, RXC_FMUL
    call rxc_emit_b
    ret

codegen_emit_divsd_rax_rbx:
    mov dil, RXC_FDIV
    call rxc_emit_b
    ret

codegen_emit_cvttsd2si_rax:
    mov dil, RXC_CVTF2I
    call rxc_emit_b
    ret

codegen_emit_cvtsi2sd_rax:
    ; convert r0 int→float
    mov dil, RXC_CVTI2F
    call rxc_emit_b
    mov dil, RXC_R0
    call rxc_emit_b
    ret

codegen_emit_cvtsi2sd_rbx:
    ; convert r1 int→float (so both operands are float before fadd/fmul etc.)
    mov dil, RXC_CVTI2F
    call rxc_emit_b
    mov dil, RXC_R1
    call rxc_emit_b
    ret

; ═══════════════════════════════════════════════════════════════════════════════
; BITWISE & LOGIC
; ═══════════════════════════════════════════════════════════════════════════════

codegen_emit_bitwise_and_rax_rbx:
    mov dil, RXC_AND
    call rxc_emit_b
    ret

codegen_emit_bitwise_or_rax_rbx:
    mov dil, RXC_OR
    call rxc_emit_b
    ret

codegen_emit_bitwise_xor_rax_rbx:
    mov dil, RXC_XOR
    call rxc_emit_b
    ret

codegen_emit_bitwise_not_rax:
codegen_emit_not_rax:
    mov dil, RXC_NOT
    call rxc_emit_b
    ret

codegen_emit_lnot_int_rax:
    mov dil, RXC_LNOT
    call rxc_emit_b
    ret

codegen_emit_shl_rax_by_rbx:
    mov dil, RXC_SHL
    call rxc_emit_b
    ret

codegen_emit_shr_rax_by_rbx:
    mov dil, RXC_SHR
    call rxc_emit_b
    ret

codegen_emit_and_bool_rax_rbx:
    mov dil, RXC_AND
    call rxc_emit_b
    ret

codegen_emit_or_bool_rax_rbx:
    mov dil, RXC_OR
    call rxc_emit_b
    ret

codegen_emit_rdrand_rax:
    mov dil, RXC_RAND
    call rxc_emit_b
    ret

; ═══════════════════════════════════════════════════════════════════════════════
; COMPARISON
; ═══════════════════════════════════════════════════════════════════════════════

; codegen_emit_cmp_rbx_rax_setcc — rdi=setcc_byte (x86 setCC opcode)
; Map x86 setCC byte to RexC CMP opcode
codegen_emit_cmp_rbx_rax_setcc:
    ; x86 setCC: 0x94=sete 0x95=setne 0x9C=setl 0x9F=setg 0x9E=setle 0x9D=setge
    push rbx
    mov rbx, rdi
    cmp rbx, 0x94
    je .eq
    cmp rbx, 0x95
    je .ne
    cmp rbx, 0x9C
    je .lt
    cmp rbx, 0x9F
    je .gt
    cmp rbx, 0x9E
    je .le
    cmp rbx, 0x9D
    je .ge
    ; default: eq
.eq: mov dil, RXC_CMP_EQ
    jmp .emit
.ne: mov dil, RXC_CMP_NE
    jmp .emit
.lt: mov dil, RXC_CMP_LT
    jmp .emit
.gt: mov dil, RXC_CMP_GT
    jmp .emit
.le: mov dil, RXC_CMP_LE
    jmp .emit
.ge: mov dil, RXC_CMP_GE
.emit:
    call rxc_emit_b
    pop rbx
    ret

codegen_emit_test_rax_jnz:
    ; Test r0, if nonzero jump — emit JMP_T placeholder onto jmp_patch_stk
    call rxc_emit_cond_jmp
    ret

codegen_emit_test_rax_jz:
    ; Jump if r0 == 0 — JMP_F placeholder (rxc_emit_cond_jmp already emits JMP_F)
    call rxc_emit_cond_jmp
    ret

codegen_emit_normalize_bool_rax:
    mov dil, RXC_BOOL_NORM
    call rxc_emit_b
    ret

codegen_emit_unknown_bool:
    mov dil, RXC_UNKNOWN_BOOL
    call rxc_emit_b
    ret

; ═══════════════════════════════════════════════════════════════════════════════
; JUMP PATCHING
; ═══════════════════════════════════════════════════════════════════════════════

; codegen_patch_jump — patch last conditional jump to land here
codegen_patch_jump:
    jmp rxc_patch_last_cond_jmp

; codegen_emit_jmp_end — emit unconditional forward jump (end of if-body)
codegen_emit_jmp_end:
    jmp rxc_emit_fwd_jmp

; codegen_patch_chain_end — patch all end-jumps in an elif/else chain
codegen_patch_chain_end:
    cmp qword [rxc_end_jmp_dep], 0
    je .done
    ; patch the top end-jump
    call rxc_patch_last_fwd_jmp
.done:
    ret

; codegen_save_chain_base — save current end_jmp_dep as chain base
codegen_save_chain_base:
    mov rax, [rxc_end_jmp_dep]
    mov rbx, [rxc_chain_base_dep]
    lea rcx, [rxc_chain_base_stk]
    mov [rcx+rbx*8], rax
    inc qword [rxc_chain_base_dep]
    ret

; codegen_emit_jmp_get_slot — emit JMP, push to slot-jump stack
codegen_emit_jmp_get_slot:
    mov dil, RXC_JMP
    call rxc_emit_b
    mov rax, [out_idx]
    mov rbx, [rxc_slot_jmp_dep]
    lea rcx, [rxc_slot_jmp_stk]
    mov [rcx+rbx*8], rax
    inc qword [rxc_slot_jmp_dep]
    xor edi, edi
    call rxc_emit_d
    ret

; codegen_patch_slot_to_here — patch top slot jump to current pos
codegen_patch_slot_to_here:
    dec qword [rxc_slot_jmp_dep]
    mov rbx, [rxc_slot_jmp_dep]
    lea rcx, [rxc_slot_jmp_stk]
    mov rdx, [rcx+rbx*8]
    mov rax, [out_idx]
    sub rax, rdx
    sub rax, 4
    lea rcx, [out_buffer]
    mov [rcx+rdx], eax
    ret

; ═══════════════════════════════════════════════════════════════════════════════
; CONTROL FLOW: IF/ELIF/ELSE
; ═══════════════════════════════════════════════════════════════════════════════
; (These are handled by codegen_emit_test_rax_jnz / codegen_patch_jump /
;  codegen_emit_jmp_end / codegen_patch_chain_end above)

; ═══════════════════════════════════════════════════════════════════════════════
; CONTROL FLOW: WHILE LOOP
; ═══════════════════════════════════════════════════════════════════════════════

codegen_emit_while_start:
    ; Save current out_idx as the loop-back target
    mov rax, [out_idx]
    mov rbx, [rxc_loop_start_dep]
    lea rcx, [rxc_loop_start_stk]
    mov [rcx+rbx*8], rax
    inc qword [rxc_loop_start_dep]
    ; Save current break_jmp_dep as base for this loop's breaks
    mov rax, [rxc_break_jmp_dep]
    mov rbx, [rxc_break_base_dep]
    lea rcx, [rxc_break_base_stk]
    mov [rcx+rbx*8], rax
    inc qword [rxc_break_base_dep]
    ; Save continue base (while condition = loop start)
    mov rax, [out_idx]
    mov rbx, [rxc_cont_base_dep]
    lea rcx, [rxc_cont_base_stk]
    mov [rcx+rbx*8], rax
    inc qword [rxc_cont_base_dep]
    mov byte [rxc_cont_type_stk + rbx], 0    ; type 0 = while
    ret

codegen_emit_while_end:
    ; Emit JMP back to loop start
    dec qword [rxc_loop_start_dep]
    mov rbx, [rxc_loop_start_dep]
    lea rcx, [rxc_loop_start_stk]
    mov r12, [rcx+rbx*8]          ; saved loop start pos
    mov dil, RXC_JMP
    call rxc_emit_b
    mov rax, [out_idx]
    add rax, 4                     ; position after this jump instruction
    mov rdx, r12
    sub rdx, rax                   ; negative offset (backward jump)
    mov edi, edx
    call rxc_emit_d
    ; Patch all break jumps from this loop
    call codegen_patch_breaks
    ; Pop continue base
    dec qword [rxc_cont_base_dep]
    ; Pop break base
    dec qword [rxc_break_base_dep]
    ret

; ═══════════════════════════════════════════════════════════════════════════════
; CONTROL FLOW: FOR LOOP
; ═══════════════════════════════════════════════════════════════════════════════

; codegen_emit_for_start — rdi=loop_var_idx, rsi=from_val, rdx=end_val
codegen_emit_for_start:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi    ; loop var
    mov r13, rsi    ; from
    mov r14, rdx    ; to (end)

    ; Save break base
    mov rax, [rxc_break_jmp_dep]
    mov rbx, [rxc_break_base_dep]
    lea rcx, [rxc_break_base_stk]
    mov [rcx+rbx*8], rax
    inc qword [rxc_break_base_dep]

    ; init: loop_var = from
    mov dil, RXC_LOAD_IMM
    call rxc_emit_b
    mov dil, RXC_R0
    call rxc_emit_b
    mov rdi, r13
    call rxc_emit_q
    mov dil, RXC_STORE_MEM
    call rxc_emit_b
    mov edi, r12d
    call rxc_emit_d

    ; loop top — save this position
    mov rax, [out_idx]
    mov rbx, [rxc_loop_start_dep]
    lea rcx, [rxc_loop_start_stk]
    mov [rcx+rbx*8], rax
    inc qword [rxc_loop_start_dep]

    ; Save continue base (= loop top, where increment happens in for_end)
    ; For simplicity: continue re-enters the increment/test at for_end patching
    mov rbx, [rxc_cont_base_dep]
    lea rcx, [rxc_cont_base_stk]
    mov [rcx+rbx*8], rax
    inc qword [rxc_cont_base_dep]
    mov byte [rxc_cont_type_stk + rbx], 1    ; type 1 = for

    ; push end_val onto for-end stack
    mov rbx, [rxc_for_end_dep]
    lea rcx, [rxc_for_end_stk]
    mov [rcx+rbx*8], r14
    inc qword [rxc_for_end_dep]

    ; push loop var onto for-var stack
    mov rbx, [rxc_for_var_dep]
    lea rcx, [rxc_for_var_stk]
    mov [rcx+rbx*8], r12
    inc qword [rxc_for_var_dep]

    ; Condition check: load loop_var, compare to end_val
    mov dil, RXC_LOAD_MEM
    call rxc_emit_b
    mov edi, r12d
    call rxc_emit_d
    ; load end into r1
    mov dil, RXC_LOAD_IMM
    call rxc_emit_b
    mov dil, RXC_R1
    call rxc_emit_b
    mov rdi, r14
    call rxc_emit_q
    ; check step direction: if for_step_val < 0 → use CMP_GE (loop while var >= end)
    ;                        else → CMP_LT (loop while var < end)
    cmp qword [for_step_val], 0
    jl .neg_step
    mov dil, RXC_CMP_GE        ; exit when var >= end
    jmp .cmp_emit
.neg_step:
    mov dil, RXC_CMP_LE        ; exit when var <= end
.cmp_emit:
    call rxc_emit_b
    ; JMP_T (exit loop when condition true = var out of range)
    mov dil, RXC_JMP_T
    call rxc_emit_b
    mov rax, [out_idx]
    mov rbx, [rxc_jmp_patch_dep]
    lea rcx, [rxc_jmp_patch_stk]
    mov [rcx+rbx*8], rax
    inc qword [rxc_jmp_patch_dep]
    xor edi, edi
    call rxc_emit_d

    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; codegen_emit_for_end
codegen_emit_for_end:
    push r12
    push r13

    ; Pop loop var
    dec qword [rxc_for_var_dep]
    mov rbx, [rxc_for_var_dep]
    lea rcx, [rxc_for_var_stk]
    mov r12, [rcx+rbx*8]   ; loop var idx

    ; Pop end_val
    dec qword [rxc_for_end_dep]
    mov rbx, [rxc_for_end_dep]
    lea rcx, [rxc_for_end_stk]
    mov r13, [rcx+rbx*8]   ; end val (not used for increment, just here for reference)

    ; Increment: loop_var += for_step_val
    mov dil, RXC_LOAD_MEM
    call rxc_emit_b
    mov edi, r12d
    call rxc_emit_d
    ; load step into r1
    mov dil, RXC_LOAD_IMM
    call rxc_emit_b
    mov dil, RXC_R1
    call rxc_emit_b
    mov rdi, [for_step_val]
    call rxc_emit_q
    mov dil, RXC_ADD
    call rxc_emit_b
    mov dil, RXC_STORE_MEM
    call rxc_emit_b
    mov edi, r12d
    call rxc_emit_d

    ; Jump back to loop top
    dec qword [rxc_loop_start_dep]
    mov rbx, [rxc_loop_start_dep]
    lea rcx, [rxc_loop_start_stk]
    mov r13, [rcx+rbx*8]   ; loop top
    mov dil, RXC_JMP
    call rxc_emit_b
    mov rax, [out_idx]
    add rax, 4
    mov rdx, r13
    sub rdx, rax            ; negative relative offset
    mov edi, edx
    call rxc_emit_d

    ; Patch exit condition jump to here
    call codegen_patch_jump

    ; Patch all break jumps
    call codegen_patch_breaks

    ; Pop continue and break bases
    dec qword [rxc_cont_base_dep]
    dec qword [rxc_break_base_dep]

    pop r13
    pop r12
    ret

; codegen_emit_for_start_dyn — rdi=loop_var_idx, rsi=end_var_idx
codegen_emit_for_start_dyn:
    push rbx
    push r12
    push r13
    mov r12, rdi    ; loop var
    mov r13, rsi    ; end var

    ; Save break base
    mov rax, [rxc_break_jmp_dep]
    mov rbx, [rxc_break_base_dep]
    lea rcx, [rxc_break_base_stk]
    mov [rcx+rbx*8], rax
    inc qword [rxc_break_base_dep]

    ; init: loop_var = 0 (dynamic loops start from current value)
    ; (the parser already assigned the start value, just save loop top)

    ; loop top
    mov rax, [out_idx]
    mov rbx, [rxc_loop_start_dep]
    lea rcx, [rxc_loop_start_stk]
    mov [rcx+rbx*8], rax
    inc qword [rxc_loop_start_dep]

    mov rbx, [rxc_cont_base_dep]
    lea rcx, [rxc_cont_base_stk]
    mov [rcx+rbx*8], rax
    inc qword [rxc_cont_base_dep]
    mov byte [rxc_cont_type_stk + rbx], 1

    ; push end var idx
    mov rbx, [rxc_for_end_dep]
    lea rcx, [rxc_for_end_stk]
    mov [rcx+rbx*8], r13
    inc qword [rxc_for_end_dep]

    mov rbx, [rxc_for_var_dep]
    lea rcx, [rxc_for_var_stk]
    mov [rcx+rbx*8], r12
    inc qword [rxc_for_var_dep]

    ; Condition: load loop_var; load end_var; cmp < ; JMP_T exit
    mov dil, RXC_LOAD_MEM
    call rxc_emit_b
    mov edi, r12d
    call rxc_emit_d
    mov dil, RXC_PUSH
    call rxc_emit_b
    mov dil, RXC_R0
    call rxc_emit_b
    mov dil, RXC_LOAD_MEM
    call rxc_emit_b
    mov edi, r13d
    call rxc_emit_d
    mov dil, RXC_MOV
    call rxc_emit_b
    mov dil, RXC_R1
    call rxc_emit_b
    mov dil, RXC_R0
    call rxc_emit_b
    mov dil, RXC_POP
    call rxc_emit_b
    mov dil, RXC_R0
    call rxc_emit_b
    mov dil, RXC_CMP_GE
    call rxc_emit_b
    mov dil, RXC_JMP_T
    call rxc_emit_b
    mov rax, [out_idx]
    mov rbx, [rxc_jmp_patch_dep]
    lea rcx, [rxc_jmp_patch_stk]
    mov [rcx+rbx*8], rax
    inc qword [rxc_jmp_patch_dep]
    xor edi, edi
    call rxc_emit_d

    pop r13
    pop r12
    pop rbx
    ret

; codegen_emit_loop_base — emit a NOP as an alignment marker (no-op in RexC)
codegen_emit_loop_base:
    ret

; ═══════════════════════════════════════════════════════════════════════════════
; BREAK / CONTINUE / SKIP
; ═══════════════════════════════════════════════════════════════════════════════

codegen_emit_break:
    ; Emit unconditional jump, push to break stack
    mov dil, RXC_JMP
    call rxc_emit_b
    mov rax, [out_idx]
    mov rbx, [rxc_break_jmp_dep]
    lea rcx, [rxc_break_jmp_stk]
    mov [rcx+rbx*8], rax
    inc qword [rxc_break_jmp_dep]
    xor edi, edi
    call rxc_emit_d
    ret

; codegen_patch_breaks — patch all break jumps from current loop to here
codegen_patch_breaks:
    ; Get base break index for this loop
    mov rbx, [rxc_break_base_dep]
    dec rbx
    lea rcx, [rxc_break_base_stk]
    mov r8, [rcx+rbx*8]       ; base = break_jmp_dep at loop start
.loop:
    mov rax, [rxc_break_jmp_dep]
    cmp rax, r8
    je .done
    dec qword [rxc_break_jmp_dep]
    mov rbx, [rxc_break_jmp_dep]
    lea rcx, [rxc_break_jmp_stk]
    mov rdx, [rcx+rbx*8]      ; patch pos
    mov rax, [out_idx]
    sub rax, rdx
    sub rax, 4
    lea rcx, [out_buffer]
    mov [rcx+rdx], eax
    jmp .loop
.done:
    ret

; codegen_push_cont — push continue target
codegen_push_cont:
    ; rdi = target (0 = use current loop top)
    ; The continue position is already saved in rxc_cont_base_stk by while/for_start
    ret

; codegen_pop_cont — pop continue target
codegen_pop_cont:
    ret

; codegen_emit_skip — emit continue: jump to loop increment/test
codegen_emit_skip:
    ; Jump to continue base of current loop
    mov rbx, [rxc_cont_base_dep]
    dec rbx
    lea rcx, [rxc_cont_base_stk]
    mov r8, [rcx+rbx*8]    ; loop-back target
    movzx eax, byte [rxc_cont_type_stk + rbx]
    ; For for-loops (type 1): the increment hasn't been emitted yet at skip time,
    ; so we can't jump back directly. Emit a forward-patch skip jump instead.
    ; For while-loops (type 0): jump directly back to loop top.
    test eax, eax
    jnz .for_skip
    ; while: backward jump to loop top
    mov dil, RXC_JMP
    call rxc_emit_b
    mov rax, [out_idx]
    add rax, 4
    mov rdx, r8
    sub rdx, rax
    mov edi, edx
    call rxc_emit_d
    ret
.for_skip:
    ; for: forward-patch jump (skip the current body, jump past for_end increment)
    mov dil, RXC_JMP
    call rxc_emit_b
    mov rax, [out_idx]
    mov rbx, [rxc_skip_jmp_dep]
    lea rcx, [rxc_skip_jmp_stk]
    mov [rcx+rbx*8], rax
    inc qword [rxc_skip_jmp_dep]
    xor edi, edi
    call rxc_emit_d
    ret

; ═══════════════════════════════════════════════════════════════════════════════
; FUNCTIONS / PROTOCOLS
; ═══════════════════════════════════════════════════════════════════════════════

; codegen_begin_protos — emit a skip-past-protos jump
codegen_begin_protos:
    cmp byte [rxc_prot_jmp_live], 0
    jne .done
    mov dil, RXC_JMP
    call rxc_emit_b
    mov rax, [out_idx]
    mov [rxc_prot_jmp_pos], rax
    xor edi, edi
    call rxc_emit_d
    mov byte [rxc_prot_jmp_live], 1
.done:
    ret

; codegen_end_protos — patch the skip-protos jump to land here
codegen_end_protos:
    cmp byte [rxc_prot_jmp_live], 0
    je .done
    mov rdx, [rxc_prot_jmp_pos]
    mov rax, [out_idx]
    sub rax, rdx
    sub rax, 4
    lea rcx, [out_buffer]
    mov [rcx+rdx], eax
    mov byte [rxc_prot_jmp_live], 0
.done:
    ret

; codegen_emit_frame_prologue — emit FUNC_DEF + FRAME_ENTER
; Parser has set rxc_cur_func_name and rxc_cur_proto_param beforehand via
; the name/param info it has at parse time.
codegen_emit_frame_prologue:
    ; FUNC_DEF [1-byte namelen] [name bytes] [1-byte param_cnt]
    mov dil, RXC_FUNC_DEF
    call rxc_emit_b
    movzx edi, byte [rxc_cur_func_namelen]
    push rbx
    mov rbx, rdi
    call rxc_emit_b              ; emit namelen
    test rbx, rbx
    jz .no_name
    xor ecx, ecx
    lea r8, [rxc_cur_func_name]
.name_loop:
    cmp rcx, rbx
    jge .no_name
    movzx edi, byte [r8+rcx]
    call rxc_emit_b
    inc rcx
    jmp .name_loop
.no_name:
    movzx edi, byte [rxc_cur_proto_param]
    call rxc_emit_b              ; emit param_cnt
    pop rbx
    ; FRAME_ENTER [param_cnt] [local_cnt=0 initially]
    mov dil, RXC_FRAME_ENTER
    call rxc_emit_b
    movzx edi, byte [rxc_cur_proto_param]
    call rxc_emit_b
    mov dil, 0
    call rxc_emit_b
    ret

; codegen_emit_leave — emit FRAME_LEAVE
codegen_emit_leave:
    mov dil, RXC_FRAME_LEAVE
    call rxc_emit_b
    ret

; codegen_emit_ret — emit RET_VAL or RET
codegen_emit_ret:
    mov dil, RXC_RET_VAL
    call rxc_emit_b
    ret

; codegen_end_protos already emits FUNC_END implicitly — but we need explicit FUNC_END
; when the parser finishes a proto body (via codegen_emit_leave + codegen_emit_ret)
; The parser calls codegen_emit_ret as its last statement in a proto,
; then codegen_end_protos patches the skip jump.

; codegen_emit_call_prot — rdi=proto_out_idx (byte offset of proto in output)
; In RexC: sym_idx = proto_out_idx (runtime resolves by instruction offset)
codegen_emit_call_prot:
    push rbx
    mov rbx, rdi
    ; ARG_PUSH is emitted by the parser via codegen_emit_push_var_slot before this
    mov dil, RXC_CALL
    call rxc_emit_b
    mov edi, ebx
    call rxc_emit_d
    pop rbx
    ret

; codegen_emit_jmp_prot — rdi=proto_out_idx: tail-call via JMP
codegen_emit_jmp_prot:
    push rbx
    mov rbx, rdi
    mov dil, RXC_JMP
    call rxc_emit_b
    mov rax, [out_idx]
    add rax, 4
    mov rdx, rbx
    sub rdx, rax
    mov edi, edx
    call rxc_emit_d
    pop rbx
    ret

; codegen_emit_arg_pops — rdi=count: emit ARG_POP count
codegen_emit_arg_pops:
    push rbx
    mov rbx, rdi
    mov dil, RXC_ARG_POP
    call rxc_emit_b
    mov dil, bl
    call rxc_emit_b
    pop rbx
    ret

; codegen_emit_push_var_slot — rdi=var_idx: load var, push as arg
codegen_emit_push_var_slot:
    push rbx
    mov rbx, rdi
    ; Load var into r0
    mov dil, RXC_LOAD_MEM
    call rxc_emit_b
    mov edi, ebx
    call rxc_emit_d
    ; Push as argument
    mov dil, RXC_ARG_PUSH
    call rxc_emit_b
    pop rbx
    ret

; codegen_emit_pop_var_slot — rdi=var_idx: pop arg into var
codegen_emit_pop_var_slot:
    push rbx
    mov rbx, rdi
    ; The ARG_POP will handle storing into frame slots,
    ; but for direct popping, store r0 to var
    mov dil, RXC_STORE_MEM
    call rxc_emit_b
    mov edi, ebx
    call rxc_emit_d
    pop rbx
    ret

; codegen_set_frame — rdi=param_cnt, rsi=param_var_indices (array)
codegen_set_frame:
    mov [rxc_cur_proto_param], dil
    mov byte [rxc_frame_active], 1
    ret

; codegen_clear_frame
codegen_clear_frame:
    mov byte [rxc_frame_active], 0
    mov byte [rxc_frame_param_cnt], 0
    mov byte [rxc_frame_local_cnt], 0
    mov byte [rxc_spill_depth], 0
    ret

; codegen_find_frame_slot — rdi=var_idx → rax=slot (identity mapping in RexC)
codegen_find_frame_slot:
    mov rax, rdi
    ret

; codegen_add_frame_local — rdi=var_idx: register as a local
codegen_add_frame_local:
    inc byte [rxc_frame_local_cnt]
    ret

; codegen_emit_regalloc_epilogue — no-op in RexC (no physical register allocation)
codegen_emit_regalloc_epilogue:
    ret

; ═══════════════════════════════════════════════════════════════════════════════
; STRING OPERATIONS
; ═══════════════════════════════════════════════════════════════════════════════

; codegen_emit_str_concat
codegen_emit_str_concat:
    mov dil, RXC_STR_CONCAT
    call rxc_emit_b
    ret

; codegen_emit_int2str
codegen_emit_int2str:
    mov dil, RXC_INT_TO_STR
    call rxc_emit_b
    ret

; codegen_emit_float2str
codegen_emit_float2str:
    mov dil, RXC_FLOAT_TO_STR
    call rxc_emit_b
    ret

; codegen_emit_str_method — rdi=method_id
codegen_emit_str_method:
    push rbx
    mov rbx, rdi
    mov dil, RXC_STR_METHOD
    call rxc_emit_b
    mov dil, bl
    call rxc_emit_b
    pop rbx
    ret

; ═══════════════════════════════════════════════════════════════════════════════
; SEQUENCE OPERATIONS
; ═══════════════════════════════════════════════════════════════════════════════

codegen_emit_seq_alloc:
    mov dil, RXC_SEQ_ALLOC
    call rxc_emit_b
    ret

codegen_emit_seq_push:
    mov dil, RXC_SEQ_PUSH
    call rxc_emit_b
    ret

codegen_emit_seq_pop_rax:
    mov dil, RXC_SEQ_POP
    call rxc_emit_b
    ret

codegen_emit_seq_len_rax:
    mov dil, RXC_SEQ_LEN
    call rxc_emit_b
    ret

codegen_emit_seq_elem_load:
    mov dil, RXC_SEQ_ELEM
    call rxc_emit_b
    ret

; ═══════════════════════════════════════════════════════════════════════════════
; MISC BUILTINS
; ═══════════════════════════════════════════════════════════════════════════════

codegen_emit_clock_ms:
    mov dil, RXC_CLOCK_MS
    call rxc_emit_b
    ret

codegen_emit_exit1:
    mov dil, RXC_LOAD_IMM
    call rxc_emit_b
    mov dil, RXC_R0
    call rxc_emit_b
    mov rdi, 1
    call rxc_emit_q
    mov dil, RXC_EXIT
    call rxc_emit_b
    ret

codegen_emit_bounds_check:
    mov dil, RXC_BOUNDS_CHK
    call rxc_emit_b
    ret

codegen_emit_overflow_check:
    mov dil, RXC_OVERFLOW_CHK
    call rxc_emit_b
    ret

codegen_emit_mov_rdi_rax:
    ; In x86: move rax→rdi for syscall setup. In RexC: mov r1, r0 (copy acc to scratch)
    mov dil, RXC_MOV
    call rxc_emit_b
    mov dil, RXC_R1
    call rxc_emit_b
    mov dil, RXC_R0
    call rxc_emit_b
    ret

codegen_emit_call_rt_err:
    ; rdi = error code: emit PANIC r0
    mov dil, RXC_PANIC
    call rxc_emit_b
    ret

; ═══════════════════════════════════════════════════════════════════════════════
; LOOP-ELSE FLAG
; ═══════════════════════════════════════════════════════════════════════════════

codegen_push_loop_else_flag:
    ; rdi = var_idx of __le flag
    mov rbx, [rxc_loop_else_dep]
    lea rcx, [rxc_loop_else_stk]
    mov [rcx+rbx*8], rdi
    inc qword [rxc_loop_else_dep]
    ret

codegen_pop_loop_else_flag:
    dec qword [rxc_loop_else_dep]
    ret

codegen_peek_loop_else_flag:
    mov rbx, [rxc_loop_else_dep]
    dec rbx
    lea rcx, [rxc_loop_else_stk]
    mov rax, [rcx+rbx*8]
    ret

; ═══════════════════════════════════════════════════════════════════════════════
; EACH LOOP (for each x in seq)
; ═══════════════════════════════════════════════════════════════════════════════

codegen_emit_each_start:
    ; rdi=elem_var_idx, rsi=seq_var_idx
    ; In RexC: load seq, loop with index var
    push rbx
    push r12
    mov r12, rdi    ; elem var

    ; Save break base
    mov rax, [rxc_break_jmp_dep]
    mov rbx, [rxc_break_base_dep]
    lea rcx, [rxc_break_base_stk]
    mov [rcx+rbx*8], rax
    inc qword [rxc_break_base_dep]

    ; Loop top
    mov rax, [out_idx]
    mov rbx, [rxc_loop_start_dep]
    lea rcx, [rxc_loop_start_stk]
    mov [rcx+rbx*8], rax
    inc qword [rxc_loop_start_dep]
    mov rbx, [rxc_cont_base_dep]
    lea rcx, [rxc_cont_base_stk]
    mov [rcx+rbx*8], rax
    inc qword [rxc_cont_base_dep]
    mov byte [rxc_cont_type_stk + rbx], 0

    ; Emit SEQ_ELEM load + conditional exit
    mov dil, RXC_SEQ_ELEM
    call rxc_emit_b
    ; conditional exit placeholder
    mov dil, RXC_JMP_F
    call rxc_emit_b
    mov rax, [out_idx]
    mov rbx, [rxc_jmp_patch_dep]
    lea rcx, [rxc_jmp_patch_stk]
    mov [rcx+rbx*8], rax
    inc qword [rxc_jmp_patch_dep]
    xor edi, edi
    call rxc_emit_d

    pop r12
    pop rbx
    ret

codegen_emit_each_end:
    ; Jump back, patch exit
    dec qword [rxc_loop_start_dep]
    mov rbx, [rxc_loop_start_dep]
    lea rcx, [rxc_loop_start_stk]
    mov r8, [rcx+rbx*8]
    mov dil, RXC_JMP
    call rxc_emit_b
    mov rax, [out_idx]
    add rax, 4
    mov rdx, r8
    sub rdx, rax
    mov edi, edx
    call rxc_emit_d
    call codegen_patch_jump
    call codegen_patch_breaks
    dec qword [rxc_cont_base_dep]
    dec qword [rxc_break_base_dep]
    ret

; ═══════════════════════════════════════════════════════════════════════════════
; REPEAT LOOP
; ═══════════════════════════════════════════════════════════════════════════════

codegen_emit_repeat_start:
    ; rdi = count: same as for-loop with var=hidden, from=0, to=count
    push rbx
    mov rbx, rdi
    ; Save break base
    mov rax, [rxc_break_jmp_dep]
    push r12
    mov r12, [rxc_break_base_dep]
    lea rcx, [rxc_break_base_stk]
    mov [rcx+r12*8], rax
    inc qword [rxc_break_base_dep]
    ; Loop top
    mov rax, [out_idx]
    mov r12, [rxc_loop_start_dep]
    lea rcx, [rxc_loop_start_stk]
    mov [rcx+r12*8], rax
    inc qword [rxc_loop_start_dep]
    ; Push count on for-end stack (used by repeat_end to decrement)
    mov r12, [rxc_for_end_dep]
    lea rcx, [rxc_for_end_stk]
    mov [rcx+r12*8], rbx
    inc qword [rxc_for_end_dep]
    pop r12
    pop rbx
    ret

codegen_emit_repeat_end:
    ; dec counter; if > 0 jump back
    dec qword [rxc_for_end_dep]
    ; jump back
    dec qword [rxc_loop_start_dep]
    mov rbx, [rxc_loop_start_dep]
    lea rcx, [rxc_loop_start_stk]
    mov r8, [rcx+rbx*8]
    mov dil, RXC_JMP
    call rxc_emit_b
    mov rax, [out_idx]
    add rax, 4
    mov rdx, r8
    sub rdx, rax
    mov edi, edx
    call rxc_emit_d
    call codegen_patch_breaks
    dec qword [rxc_break_base_dep]
    ret

; ═══════════════════════════════════════════════════════════════════════════════
; CONST DECL, MM/GC SWITCH, MEMO
; ═══════════════════════════════════════════════════════════════════════════════

codegen_emit_const_decl:
    ; const vars are handled same as regular vars in RexC (immutability is type info)
    ret

codegen_emit_mm_switch:
    ; memory model switch — no-op in RexC (runtime manages memory)
    ret

codegen_emit_gc_switch:
    ret

codegen_emit_memo_check:
    ; @memo: check cache — emit a NOP sequence for now
    ; (full memo support requires runtime hash table)
    mov dil, RXC_NOP
    call rxc_emit_b
    ; Patch positions for the conditional jumps
    mov rax, [out_idx]
    mov [rxc_memo_jmp_patch], rax
    mov [rxc_memo_end_patch], rax
    ret

codegen_emit_memo_store:
    mov dil, RXC_NOP
    call rxc_emit_b
    ret

codegen_emit_memo_reset:
    mov dil, RXC_NOP
    call rxc_emit_b
    ret

; ═══════════════════════════════════════════════════════════════════════════════
; RAW EMIT (used by parser for inline bytes)
; ═══════════════════════════════════════════════════════════════════════════════

; codegen_emit_b_raw — rdi=byte: emit one raw byte into output
codegen_emit_b_raw:
    call rxc_emit_b
    ret

; codegen_emit_d_raw — rdi=dword
codegen_emit_d_raw:
    call rxc_emit_d
    ret

; ═══════════════════════════════════════════════════════════════════════════════
; CODEGEN_SET_FOR_STEP
; ═══════════════════════════════════════════════════════════════════════════════

codegen_set_for_step:
    ; rdi = step value
    mov [for_step_val], rdi
    ret

; ═══════════════════════════════════════════════════════════════════════════════
; PEEPHOLE (no-op in RexC — no x86 peephole needed)
; ═══════════════════════════════════════════════════════════════════════════════

codegen_peephole:
    ret

; codegen_mark_r12_needed — no-op (no r12 register in RexC backend)
codegen_mark_r12_needed:
    ret
