default rel
%include "include/rex_defs.inc"
global codegen_write_headers, codegen_init, codegen_finish, out_buffer, out_idx
global codegen_output_const, codegen_output_typed, codegen_patch_jump
global codegen_save_chain_base, codegen_emit_jmp_end, codegen_patch_chain_end
global codegen_begin_protos, codegen_end_protos
global codegen_emit_for_start, codegen_emit_for_end
global codegen_emit_while_start, codegen_emit_while_end
global codegen_emit_break, codegen_patch_breaks, codegen_emit_loop_base
global codegen_emit_ret, codegen_emit_mov_eax_imm32, codegen_emit_call_prot
global codegen_emit_push_var_slot, codegen_emit_pop_var_slot
global codegen_emit_assign_var, codegen_emit_zero_var, codegen_emit_cmp_var_jne, codegen_emit_unknown_bool
global codegen_emit_mm_switch, codegen_emit_gc_switch
global codegen_emit_test_rax_jnz, codegen_emit_normalize_bool_rax
global codegen_emit_jmp_get_slot, codegen_patch_slot_to_here
global codegen_emit_push_rax, codegen_emit_pop_rbx
global codegen_emit_mov_rax_var, codegen_emit_store_rax_to_var
global codegen_emit_rdrand_rax, codegen_emit_neg_rax, codegen_emit_not_rax
global codegen_emit_bitwise_not_rax
global codegen_emit_add_rax_rbx, codegen_emit_sub_rax_rbx
global codegen_emit_imul_rax_rbx, codegen_emit_idiv_rbx_by_rax, codegen_emit_imod_rbx_by_rax
global codegen_emit_cmp_rbx_rax_setcc, codegen_emit_test_rax_jz
global codegen_output_rax
global codegen_emit_addsd_rax_rbx, codegen_emit_subsd_rax_rbx
global codegen_emit_mulsd_rax_rbx, codegen_emit_divsd_rax_rbx
global codegen_emit_cvttsd2si_rax, codegen_emit_cvtsi2sd_rax
global codegen_emit_bitwise_and_rax_rbx, codegen_emit_bitwise_or_rax_rbx
global codegen_emit_bitwise_xor_rax_rbx
global codegen_emit_and_bool_rax_rbx, codegen_emit_or_bool_rax_rbx
global codegen_emit_shl_rax_by_rbx, codegen_emit_shr_rax_by_rbx
global codegen_set_frame, codegen_clear_frame, codegen_find_frame_slot
global codegen_emit_frame_prologue, codegen_emit_leave, codegen_emit_jmp_prot
global codegen_peephole
global codegen_emit_str_rax
global codegen_emit_seq_alloc, codegen_emit_seq_push, codegen_emit_seq_pop_rax
global codegen_emit_seq_len_rax
global codegen_emit_mov_rdi_rax, codegen_emit_call_rt_err
global codegen_emit_for_start_dyn, codegen_emit_arg_pops
global codegen_push_cont, codegen_pop_cont, codegen_emit_skip
global codegen_emit_b_raw, codegen_emit_d_raw, codegen_get_var_va_proxy
global codegen_emit_inc_var, codegen_emit_dec_var
global codegen_emit_swap_vars
global codegen_emit_abs_rax
global codegen_emit_cap_rax
global codegen_set_for_step, for_step_val
global codegen_emit_exit1
global codegen_push_loop_else_flag, codegen_pop_loop_else_flag, codegen_peek_loop_else_flag
global codegen_emit_each_start, codegen_emit_each_end
; O1: stack frames  O2: loop pin  O3: peephole  O4: TCO  O5: frame locals
global codegen_set_frame, codegen_clear_frame
global codegen_emit_frame_prologue, codegen_emit_leave
global codegen_emit_jmp_prot
global codegen_add_frame_local
; O18: register allocator
global regalloc_cnt, regalloc_active
global codegen_emit_regalloc_epilogue
; O6: register-based expression spill
global codegen_emit_expr_save_rax, codegen_emit_expr_restore_rbx
global codegen_emit_expr_spill_save, codegen_emit_expr_spill_restore
extern elf_header, program_header
extern rt_pri_blob, rt_prs_blob, rt_prb_blob, rt_prf_blob, rt_prc_blob
extern rt_sip_blob, rt_alc_blob, rt_prq_blob
section .bss
out_buffer:       resb 131072
out_idx:          resq 1
jump_patch_stack: resq 32
jump_patch_depth: resq 1
end_jump_stack:   resq 32
end_jump_depth:   resq 1
chain_base_stack: resq 32
chain_base_depth: resq 1
break_jump_stack: resq 32
break_jump_depth: resq 1
break_base_stack: resq 32
break_base_depth: resq 1
cont_base_stack:  resq 32
cont_base_depth:  resq 1
prot_jmp_idx:     resq 1
prot_jmp_live:    resb 1
for_step_val:     resq 1
loop_else_flag_stack: resq 32
loop_else_flag_depth: resq 1
; O1: stack frame for protocol params
frame_active:     resb 1
frame_param_cnt:  resb 1
frame_param_vars: resb 6
; O5: protocol-local variables on stack frame
frame_local_cnt:  resb 1
frame_local_vars: resb 32
; O6: expression spill register depth (0=r10 free, 1=r10 in use, 2=r10+r11)
expr_spill_depth: resb 1
; O9: position in out_buffer of the sub rsp imm32 to patch with actual frame size
frame_size_patch_pos: resq 1
; FLC: frameless leave patch list — records imm32 positions of all add rsp epilogues
leave_patch_list: resq 16
leave_patch_cnt:  resb 1
; O2: loop counter register pin (r15)
loop_pin_active:  resb 1
loop_pin_var_idx: resq 1
loop_pin_depth:   resq 1
; O13: loop accumulator post-pass rewriter (r14)
; At loop start: emit mov r14,[placeholder] at patch_pos; save body start.
; At loop end:   scan body for first non-counter store, rewrite loads/stores
;                to use r14, patch pre-load address, emit post-loop flush.
loop_accum_patch_pos: resq 1      ; offset in out_buffer of the 8-byte pre-load placeholder
loop_body_start_idx:  resq 1      ; offset in out_buffer where loop body begins
loop_accum_addr_tmp:  resq 1      ; discovered accumulator VA (scratch during rewrite)
loop_accum_active:    resb 1      ; 1 = accumulator (r14) is live for this loop
loop_accum_var_idx:   resq 1      ; var_idx of the variable promoted to r14
loop_accum_read_first: resb 1     ; 1 = candidate var was LOADED before its first store
loop_accum_load_patch_pos: resq 1 ; out_buffer offset of that first global load (8 bytes)
; O14: strength-reduction — fuse :accum = accum + pin → single add r14,r15
sr_add_candidate:    resb 1  ; 1 = candidate 12-byte rewind sequence is live
sr_add_rhs_is_pin:   resb 1  ; 1 = the + RHS was the O2-pinned loop variable (r15)
sr_add_done:         resb 1  ; 1 = fusion fired; suppress the next O13 store of this accum
sr_add_patch_pos:    resq 1  ; out_idx at the start of the candidate sequence
; O15: strength-reduction operator (0=add 1=sub 2=mul 3=div)
sr_op:               resb 1
; O18: register allocator — pin first N protocol params to r12/r13
regalloc_active:     resb 1
regalloc_cnt:        resb 1
regalloc_vars:       resb 2
section .text

; ── internal emit helpers ─────────────────────────────────────────────────────
emit_b:
    push rbx
    push rcx
    mov rcx, [out_idx]
    cmp rcx, 131071
    jge .overflow
    lea rbx, [out_buffer]
    mov [rbx+rcx], al
    inc qword [out_idx]
    pop rcx
    pop rbx
    ret
.overflow:
    mov rax, 60
    mov rdi, 1
    syscall
emit_d:
    push rbx
    push rcx
    mov rcx, [out_idx]
    lea rbx, [out_buffer]
    mov [rbx+rcx], eax
    add qword [out_idx], 4
    pop rcx
    pop rbx
    ret
emit_q:
    push rbx
    push rcx
    mov rcx, [out_idx]
    lea rbx, [out_buffer]
    mov [rbx+rcx], rax
    add qword [out_idx], 8
    pop rcx
    pop rbx
    ret
emit_blob:
    push rdi
    push rsi
    push rcx
    push rdx
    mov rdx, [out_idx]
    lea rdi, [out_buffer]
    add rdi, rdx
    cld
    rep movsb
    pop rdx
    pop rcx
    pop rsi
    pop rdi
    add qword [out_idx], rcx
    ret
get_var_va:
    mov rax, rdi
    shl rax, 6
    add rax, VAR_STORAGE_BASE
    ret

; ── headers / init ────────────────────────────────────────────────────────────
codegen_write_headers:
    mov qword [out_idx], 0
    lea rsi, [elf_header]
    lea rdi, [out_buffer]
    mov rcx, 64
    cld
    rep movsb
    lea rsi, [program_header]
    mov rcx, 56
    rep movsb
    mov qword [out_idx], 120
    ret

codegen_init:
    mov qword [for_step_val], 1
    mov al, 0xE9
    call emit_b
    mov eax, RT_TOTAL_SIZE
    call emit_d
    lea rsi, [rt_pri_blob]
    mov rcx, RT_PRI_SIZE
    call emit_blob
    lea rsi, [rt_prs_blob]
    mov rcx, RT_PRS_SIZE
    call emit_blob
    lea rsi, [rt_prb_blob]
    mov rcx, RT_PRB_SIZE
    call emit_blob
    lea rsi, [rt_prf_blob]
    mov rcx, RT_PRF_SIZE
    call emit_blob
    lea rsi, [rt_prc_blob]
    mov rcx, RT_PRC_SIZE
    call emit_blob
    lea rsi, [rt_sip_blob]
    mov rcx, RT_SIP_SIZE
    call emit_blob
    lea rsi, [rt_alc_blob]
    mov rcx, RT_ALC_SIZE
    call emit_blob
    lea rsi, [rt_prq_blob]
    mov rcx, RT_PRQ_SIZE
    call emit_blob
    ret

codegen_finish:
    ; emit: mov rax, 60; xor rdi, rdi; syscall
    mov al, 0x48
    call emit_b
    mov al, 0xC7
    call emit_b
    mov al, 0xC0
    call emit_b
    mov eax, 60
    call emit_d
    mov al, 0x48
    call emit_b
    mov al, 0x31
    call emit_b
    mov al, 0xFF
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0x05
    call emit_b
    ; patch program header: file_size and mem_size = out_idx
    mov rax, [out_idx]
    lea rcx, [out_buffer]
    mov [rcx+64+32], rax
    mov rax, [out_idx]
    add rax, 0x44000
    mov [rcx+64+40], rax
    ; O3: peephole optimise the output buffer
    call codegen_peephole
    ret

; ── output helpers ────────────────────────────────────────────────────────────
codegen_output_const:
    ; rdi=value: emit mov edi,imm32; call rt_pXX
    mov al, 0xBF
    call emit_b
    mov eax, edi
    call emit_d
    mov al, 0xE8
    call emit_b
    mov rax, LOAD_BASE+RT_PRI_OFFSET
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d
    ret

codegen_output_typed:
    ; rdi=var_idx rsi=type: emit mov rdi,[var_addr]; call rt_pXX  (O1: frame-aware)
    push rsi
    push rdi
    call codegen_find_frame_slot  ; rdi preserved; rax=slot or -1
    cmp rax, -1
    je .ot_global
    ; frame slot K: emit mov rdi,[rsp+K*8] = 48 8B 7C 24 <disp8>
    mov rcx, rax
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x7C
    call emit_b
    mov al, 0x24
    call emit_b
    shl rcx, 3
    mov al, cl
    call emit_b
    pop rdi
    pop rsi
    jmp .ot_call
.ot_global:
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x3C
    call emit_b
    mov al, 0x25
    call emit_b
    pop rdi
    push rdi
    call get_var_va
    call emit_d
    pop rdi
    pop rsi
.ot_call:
    mov al, 0xE8
    call emit_b
    mov rax, RT_PRI_OFFSET
    cmp sil, TYPE_STR
    je .s
    cmp sil, TYPE_BOOL
    je .b
    cmp sil, TYPE_FLOAT
    je .f
    cmp sil, TYPE_COMPLEX
    je .c
    jmp .d
.s: mov rax, RT_PRS_OFFSET
    jmp .d
.b: mov rax, RT_PRB_OFFSET
    jmp .d
.f: mov rax, RT_PRF_OFFSET
    jmp .d
.c: mov rax, RT_PRC_OFFSET
.d: add rax, LOAD_BASE
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d
    ret

codegen_output_rax:
    ; rdi=type: emit mov rdi,rax; call rt_pXX
    push rdi
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC7
    call emit_b
    pop rsi
    mov al, 0xE8
    call emit_b
    mov rax, RT_PRI_OFFSET
    cmp sil, TYPE_STR
    je .s
    cmp sil, TYPE_BOOL
    je .b
    cmp sil, TYPE_FLOAT
    je .f
    cmp sil, TYPE_COMPLEX
    je .c
    jmp .d
.s: mov rax, RT_PRS_OFFSET
    jmp .d
.b: mov rax, RT_PRB_OFFSET
    jmp .d
.f: mov rax, RT_PRF_OFFSET
    jmp .d
.c: mov rax, RT_PRC_OFFSET
.d: add rax, LOAD_BASE
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d
    ret

; ── assign / bool ─────────────────────────────────────────────────────────────
codegen_emit_assign_var:
    ; rdi=var_idx rsi=value: emit mov rax,imm64; mov [var_addr],rax
    push rdi
    mov al, 0x48
    call emit_b
    mov al, 0xB8
    call emit_b
    mov rax, rsi
    call emit_q
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    pop rdi
    call get_var_va
    call emit_d
    ret

codegen_emit_zero_var:
    ; rdi=var_idx: emit  mov qword [var_addr], 0  (9 bytes vs 18-byte assign_var)
    ; Encoding: 48 C7 04 25 <addr32> 00 00 00 00
    push rdi
    mov al, 0x48
    call emit_b
    mov al, 0xC7
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    pop rdi
    call get_var_va
    call emit_d
    xor eax, eax
    call emit_d
    ret

codegen_emit_unknown_bool:
    ; emit: rdrand eax; and eax,1; mov [var_addr],eax
    push rdi
    mov al, 0x0F
    call emit_b
    mov al, 0xC7
    call emit_b
    mov al, 0xF0
    call emit_b
    mov al, 0x83
    call emit_b
    mov al, 0xE0
    call emit_b
    mov al, 0x01
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    pop rdi
    call get_var_va
    call emit_d
    ret

codegen_emit_cmp_var_jne:
    ; rdi=var_idx rsi=value: emit cmp [var_addr],imm32; jne <placeholder>
    push rsi
    push rdi
    mov al, 0x48
    call emit_b
    mov al, 0x81
    call emit_b
    mov al, 0x3C
    call emit_b
    mov al, 0x25
    call emit_b
    pop rdi
    call get_var_va
    call emit_d
    pop rsi
    mov eax, esi
    call emit_d
    mov al, 0x0F
    call emit_b
    mov al, 0x85
    call emit_b
    mov rax, [out_idx]
    mov rbx, [jump_patch_depth]
    lea rcx, [jump_patch_stack]
    mov [rcx+rbx*8], rax
    inc qword [jump_patch_depth]
    xor eax, eax
    call emit_d
    ret

; ── jump / chain patching ─────────────────────────────────────────────────────
codegen_patch_jump:
    dec qword [jump_patch_depth]
    mov rbx, [jump_patch_depth]
    lea rcx, [jump_patch_stack]
    mov rdx, [rcx+rbx*8]
    mov rax, [out_idx]
    sub rax, rdx
    sub rax, 4
    lea rcx, [out_buffer]
    mov [rcx+rdx], eax
    ret

codegen_save_chain_base:
    mov rax, [end_jump_depth]
    mov rbx, [chain_base_depth]
    lea rcx, [chain_base_stack]
    mov [rcx+rbx*8], rax
    inc qword [chain_base_depth]
    ret

codegen_emit_jmp_end:
    mov al, 0xE9
    call emit_b
    mov rax, [out_idx]
    mov rbx, [end_jump_depth]
    lea rcx, [end_jump_stack]
    mov [rcx+rbx*8], rax
    inc qword [end_jump_depth]
    xor eax, eax
    call emit_d
    ret

codegen_patch_chain_end:
    dec qword [chain_base_depth]
    mov rbx, [chain_base_depth]
    lea rcx, [chain_base_stack]
    mov rsi, [rcx+rbx*8]
.l:
    cmp rsi, [end_jump_depth]
    jae .done
    lea rcx, [end_jump_stack]
    mov rdx, [rcx+rsi*8]
    mov rax, [out_idx]
    sub rax, rdx
    sub rax, 4
    lea rcx, [out_buffer]
    mov [rcx+rdx], eax
    inc rsi
    jmp .l
.done:
    mov [end_jump_depth], rsi
    ret

; ── protocol jump frame ────────────────────────────────────────────────────────
codegen_begin_protos:
    cmp byte [prot_jmp_live], 0
    jne .done
    mov al, 0xE9
    call emit_b
    mov rax, [out_idx]
    mov [prot_jmp_idx], rax
    xor eax, eax
    call emit_d
    mov byte [prot_jmp_live], 1
.done:
    ret

codegen_end_protos:
    cmp byte [prot_jmp_live], 0
    je .done
    mov rdx, [prot_jmp_idx]
    mov rax, [out_idx]
    sub rax, rdx
    sub rax, 4
    lea rcx, [out_buffer]
    mov [rcx+rdx], eax
    mov byte [prot_jmp_live], 0
.done:
    ret

; ── loop-top alignment helper ─────────────────────────────────────────────────
; Emit 0–15 NOP bytes so the next byte lands on a 16-byte boundary.
; Aligning loop tops to 16 bytes maximises i-cache line utilisation.
codegen_align_loop_top:
    push rcx
.alt_spin:
    mov rcx, [out_idx]
    test rcx, 15
    jz .alt_done
    mov al, 0x90        ; NOP
    call emit_b
    jmp .alt_spin
.alt_done:
    pop rcx
    ret

; ── for loop (static bounds) ──────────────────────────────────────────────────
codegen_emit_for_start:
    ; rdi=loop_var_idx  rsi=from_val  rdx=end_val
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rdx
    mov rax, [break_jump_depth]
    mov rbx, [break_base_depth]
    lea rcx, [break_base_stack]
    mov [rcx+rbx*8], rax
    inc qword [break_base_depth]
    ; for_step_val already set by parser via codegen_set_for_step; do not reset here
    ; optimised init: choose smallest encoding for from_val (rsi)
    test rsi, rsi
    jnz .fs_init_nz
    mov al, 0x31
    call emit_b
    mov al, 0xC0
    call emit_b
    mov rdi, r12
    call get_var_va
    mov rbx, rax               ; save VA — subsequent mov al,* would clobber rax
    mov al, 0x89
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    mov rax, rbx               ; restore VA for emit_d
    call emit_d
    jmp .fs_cond
.fs_init_nz:
    mov rax, rsi
    shr rax, 32
    jnz .fs_init64
    mov al, 0xB8
    call emit_b
    mov eax, esi
    call emit_d
    mov rdi, r12
    call get_var_va
    mov rbx, rax               ; save VA — subsequent mov al,* would clobber rax
    mov al, 0x89
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    mov rax, rbx               ; restore VA for emit_d
    call emit_d
    jmp .fs_cond
.fs_init64:
    mov al, 0x48
    call emit_b
    mov al, 0xB8
    call emit_b
    mov rax, rsi
    call emit_q
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    mov rdi, r12
    call get_var_va
    call emit_d
.fs_cond:
    ; O2: pin outermost loop counter to r15
    cmp qword [loop_pin_depth], 0
    jne .fs_cond_global
    ; outermost loop: set pin, load r15 from just-stored [i_addr]
    mov [loop_pin_var_idx], r12
    mov byte [loop_pin_active], 1
    inc qword [loop_pin_depth]
    ; emit mov r15,[i_addr] = 4D 8B 3C 25 <addr32>
    mov al, 0x4D
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x3C
    call emit_b
    mov al, 0x25
    call emit_b
    mov rdi, r12
    call get_var_va
    call emit_d
    ; O13: emit pre-load placeholder for accumulator: mov r14,[0] = 4C 8B 34 25 00 00 00 00
    ; (address patched when first accumulator store is detected; NOP'd if none found)
    mov rax, [out_idx]
    mov [loop_accum_patch_pos], rax
    mov byte [loop_accum_active], 0
    mov qword [loop_accum_var_idx], -1
    mov byte [loop_accum_read_first], 0
    mov qword [loop_accum_load_patch_pos], 0
    mov byte [sr_add_candidate], 0
    mov byte [sr_add_rhs_is_pin], 0
    mov byte [sr_add_done], 0
    mov al, 0x4C
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x34
    call emit_b
    mov al, 0x25
    call emit_b
    xor eax, eax
    call emit_d
    call codegen_align_loop_top   ; align loop top to 16-byte i-cache boundary
    mov rbx, [out_idx]       ; loop cond start (after the init load)
    ; emit cmp r15,end_val = 49 81 FF <imm32>
    mov al, 0x49
    call emit_b
    mov al, 0x81
    call emit_b
    mov al, 0xFF
    call emit_b
    mov rax, r13             ; end_val
    call emit_d
    jmp .fs_patch
.fs_cond_global:
    inc qword [loop_pin_depth]
    call codegen_align_loop_top   ; align loop top to 16-byte i-cache boundary
    mov rbx, [out_idx]
    ; cmp qword [addr], imm32 = 48 81 3C 25 <addr32> <imm32>
    mov al, 0x48
    call emit_b
    mov al, 0x81
    call emit_b
    mov al, 0x3C
    call emit_b
    mov al, 0x25
    call emit_b
    mov rdi, r12
    call get_var_va
    call emit_d
    mov rax, r13
    call emit_d
.fs_patch:
    mov al, 0x0F
    call emit_b
    mov al, 0x8D
    call emit_b
    mov rax, [out_idx]
    mov r13, [jump_patch_depth]
    lea rcx, [jump_patch_stack]
    mov [rcx+r13*8], rax
    inc qword [jump_patch_depth]
    xor eax, eax
    call emit_d
    mov rdi, rbx
    call codegen_push_cont
    mov rax, rbx
    pop r13
    pop r12
    pop rbx
    ret

codegen_emit_for_end:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi             ; loop_start_pc
    mov r13, rsi             ; loop_var_idx
    mov r14, [for_step_val]  ; step value
    mov qword [for_step_val], 1
    ; O2: use r15 increment when loop is pinned
    cmp byte [loop_pin_active], 0
    je .fe_global_inc
    cmp r13, [loop_pin_var_idx]
    jne .fe_global_inc
    ; pinned: increment r15
    cmp r14, 1
    jne .fe_pin_step
    ; inc r15 = 49 FF C7
    mov al, 0x49
    call emit_b
    mov al, 0xFF
    call emit_b
    mov al, 0xC7
    call emit_b
    jmp .fe_jmp
.fe_pin_step:
    cmp r14, 127
    jg .fe_pin_imm32
    ; add r15, imm8 = 49 83 C7 <imm8>
    mov al, 0x49
    call emit_b
    mov al, 0x83
    call emit_b
    mov al, 0xC7
    call emit_b
    mov al, r14b
    call emit_b
    jmp .fe_jmp
.fe_pin_imm32:
    ; add r15, imm32 = 49 81 C7 <imm32>
    mov al, 0x49
    call emit_b
    mov al, 0x81
    call emit_b
    mov al, 0xC7
    call emit_b
    mov eax, r14d
    call emit_d
    jmp .fe_jmp
.fe_global_inc:
    cmp r14, 1
    jne .fe_step
    ; inc qword [loop_var_addr]  (7 bytes: 48 FF 04 25 <addr32>)
    mov al, 0x48
    call emit_b
    mov al, 0xFF
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    mov rdi, r13
    call get_var_va
    call emit_d
    jmp .fe_jmp
.fe_step:
    cmp r14, 127
    jg .fe_imm32
    ; add qword [addr], imm8  (8 bytes: 48 83 04 25 <addr32> <imm8>)
    mov al, 0x48
    call emit_b
    mov al, 0x83
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    mov rdi, r13
    call get_var_va
    call emit_d
    mov al, r14b
    call emit_b
    jmp .fe_jmp
.fe_imm32:
    ; add qword [addr], imm32  (11 bytes: 48 81 04 25 <addr32> <imm32>)
    mov al, 0x48
    call emit_b
    mov al, 0x81
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    mov rdi, r13
    call get_var_va
    call emit_d
    mov eax, r14d
    call emit_d
.fe_jmp:
    ; emit: jmp back to loop start
    mov al, 0xE9
    call emit_b
    mov rax, r12
    add rax, LOAD_BASE
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d
    call codegen_patch_jump
    call codegen_patch_breaks
    call codegen_pop_cont
    ; O2: if pinned loop exited, flush r15 → [i_addr] and clear pin
    cmp byte [loop_pin_active], 0
    je .fe_done
    cmp r13, [loop_pin_var_idx]
    jne .fe_done
    ; emit mov [i_addr], r15 = 4D 89 3C 25 <addr32>
    mov al, 0x4D
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0x3C
    call emit_b
    mov al, 0x25
    call emit_b
    mov rdi, r13
    call get_var_va
    call emit_d
    mov byte [loop_pin_active], 0
.fe_done:
    ; O13: accumulator flush/NOP — only for outermost loop (depth==1 before decrement)
    cmp qword [loop_pin_depth], 1
    jne .fe_accum_skip
    cmp byte [loop_accum_active], 0
    je .fe_accum_nop
    ; flush r14 → [accum_addr]: mov [accum_addr],r14 = 4C 89 34 25 <addr32>
    mov al, 0x4C
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0x34
    call emit_b
    mov al, 0x25
    call emit_b
    mov rdi, [loop_accum_var_idx]
    call get_var_va
    call emit_d
    jmp .fe_accum_done
.fe_accum_nop:
    ; no accumulator found: replace the 8-byte placeholder with an 8-byte NOP
    ; 8-byte NOP: 0F 1F 84 00 00 00 00 00
    mov rbx, [loop_accum_patch_pos]
    lea rdi, [out_buffer]
    mov byte [rdi+rbx+0], 0x0F
    mov byte [rdi+rbx+1], 0x1F
    mov byte [rdi+rbx+2], 0x84
    mov byte [rdi+rbx+3], 0x00
    mov byte [rdi+rbx+4], 0x00
    mov byte [rdi+rbx+5], 0x00
    mov byte [rdi+rbx+6], 0x00
    mov byte [rdi+rbx+7], 0x00
.fe_accum_done:
    mov byte [loop_accum_active], 0
    mov qword [loop_accum_var_idx], -1
.fe_accum_skip:
    dec qword [loop_pin_depth]
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ── for loop (dynamic bounds) ─────────────────────────────────────────────────
codegen_emit_for_start_dyn:
    ; rdi=loop_var_idx rsi=end_var_idx
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    ; O2: track nesting depth (no pin for dynamic loops)
    inc qword [loop_pin_depth]
    ; for_step_val already set by parser via codegen_set_for_step; do not reset here
    mov rax, [break_jump_depth]
    mov r14, [break_base_depth]
    lea rcx, [break_base_stack]
    mov [rcx+r14*8], rax
    inc qword [break_base_depth]
    call codegen_align_loop_top   ; align loop top to 16-byte i-cache boundary
    mov rbx, [out_idx]
    ; emit: mov rax,[loop_var]; cmp rax,[end_var]; jge .exit
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    mov rdi, r12
    call get_var_va
    call emit_d
    mov al, 0x48
    call emit_b
    mov al, 0x3B
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    mov rdi, r13
    call get_var_va
    call emit_d
    mov al, 0x0F
    call emit_b
    mov al, 0x8D
    call emit_b
    mov rax, [out_idx]
    mov r14, [jump_patch_depth]
    lea rcx, [jump_patch_stack]
    mov [rcx+r14*8], rax
    inc qword [jump_patch_depth]
    xor eax, eax
    call emit_d
    mov rdi, rbx
    call codegen_push_cont
    mov rax, rbx
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ── while loop ────────────────────────────────────────────────────────────────
codegen_emit_while_start:
    ret

codegen_emit_while_end:
    ; rdi = loop_start_pc (out_idx value at start of condition)
    mov al, 0xE9
    call emit_b
    mov rax, rdi
    add rax, LOAD_BASE
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d
    call codegen_patch_jump
    call codegen_patch_breaks
    call codegen_pop_cont
    ret

codegen_emit_loop_base:
    mov rax, [break_jump_depth]
    mov rbx, [break_base_depth]
    lea rcx, [break_base_stack]
    mov [rcx+rbx*8], rax
    inc qword [break_base_depth]
    ret

; ── break / continue ──────────────────────────────────────────────────────────
codegen_emit_break:
    push rbx
    ; if there is an active loop-else flag, mark the loop as broken (set flag=1)
    cmp qword [loop_else_flag_depth], 0
    je .do_break
    mov rax, [loop_else_flag_depth]
    dec rax
    lea rcx, [loop_else_flag_stack]
    mov rdi, [rcx+rax*8]          ; peek top: flag_var_idx
    cmp rdi, -1
    je .do_break
    ; emit: mov qword [flag_addr], 1  (48 C7 04 25 <addr32> 01 00 00 00)
    call get_var_va                ; rdi=var_idx → rax=var_addr
    mov rbx, rax                   ; save addr (get_var_va only uses rdi/rax)
    mov al, 0x48
    call emit_b
    mov al, 0xC7
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    mov rax, rbx
    call emit_d                    ; emit flag_addr as imm32
    mov eax, 1
    call emit_d                    ; emit immediate value 1
.do_break:
    mov al, 0xE9
    call emit_b
    mov rax, [out_idx]
    mov rbx, [break_jump_depth]
    lea rcx, [break_jump_stack]
    mov [rcx+rbx*8], rax
    inc qword [break_jump_depth]
    xor eax, eax
    call emit_d
    pop rbx
    ret

codegen_patch_breaks:
    dec qword [break_base_depth]
    mov rbx, [break_base_depth]
    lea rcx, [break_base_stack]
    mov rsi, [rcx+rbx*8]
.l:
    cmp rsi, [break_jump_depth]
    jae .done
    lea rcx, [break_jump_stack]
    mov rdx, [rcx+rsi*8]
    mov rax, [out_idx]
    sub rax, rdx
    sub rax, 4
    lea rcx, [out_buffer]
    mov [rcx+rdx], eax
    inc rsi
    jmp .l
.done:
    mov [break_jump_depth], rsi
    ret

codegen_push_cont:
    mov rax, [cont_base_depth]
    lea rcx, [cont_base_stack]
    mov [rcx+rax*8], rdi
    inc qword [cont_base_depth]
    ret

codegen_pop_cont:
    cmp qword [cont_base_depth], 0
    je .done
    dec qword [cont_base_depth]
.done:
    ret

codegen_emit_skip:
    ; rdi = depth: 0 = innermost continue, 1 = next outer, etc.
    push rbx
    push r12
    mov r12, rdi
    mov rax, [cont_base_depth]
    test rax, rax
    jz .done
    dec rax             ; rax = top index (0-based)
    sub rax, r12        ; rax = target index
    jl .clamp
    jmp .emit
.clamp:
    xor rax, rax
.emit:
    lea rcx, [cont_base_stack]
    mov rbx, [rcx+rax*8]
    mov al, 0xE9
    call emit_b
    mov rax, rbx
    add rax, LOAD_BASE
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d
.done:
    pop r12
    pop rbx
    ret

; ── protocol helpers ──────────────────────────────────────────────────────────
codegen_emit_ret:
    mov al, 0xC3
    call emit_b
    ret

codegen_emit_mov_eax_imm32:
    ; rdi=imm: emit mov eax,imm32 or xor eax,eax for zero
    test rdi, rdi
    jnz .nonzero
    mov al, 0x31
    call emit_b
    mov al, 0xC0
    call emit_b
    ret
.nonzero:
    mov al, 0xB8
    call emit_b
    mov eax, edi
    call emit_d
    ret

codegen_set_for_step:
    mov [for_step_val], rdi
    ret

codegen_emit_call_prot:
    ; rdi = proto out_idx: emit call rel32
    mov al, 0xE8
    call emit_b
    mov rax, rdi
    add rax, LOAD_BASE
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d
    ret

codegen_emit_arg_pops:
    ; rdi=count: emit pop instructions (pop rdi, rsi, rdx, rcx [, r8, r9])
    ; r8 = 41 58  r9 = 41 59  (2-byte pops)
    push rbx
    push rcx
    push r12
    mov rbx, rdi
    cmp rbx, 6
    jle .ok
    mov rbx, 6
.ok:
    test rbx, rbx
    jz .done
    dec rbx
    cmp rbx, 4
    jge .r89
    ; O7: for rdi (rbx=0) retroactively optimize if preceding emit was push rax (50)
    cmp rbx, 0
    jne .ap_normal
    mov rax, [out_idx]
    test rax, rax
    jz .ap_normal
    lea rcx, [out_buffer]
    cmp byte [rcx + rax - 1], 0x50
    jne .ap_normal
    mov byte [rcx + rax - 1], 0x90   ; patch push rax → NOP
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC7                       ; mov rdi, rax = 48 89 C7
    call emit_b
    jmp .ok
.ap_normal:
    lea rax, [rel .pop_bytes]
    movzx eax, byte [rax+rbx]
    call emit_b
    jmp .ok
.r89:
    ; pop r8 (41 58) or pop r9 (41 59)
    mov al, 0x41
    call emit_b
    cmp rbx, 4
    je .r8
    mov al, 0x59
    jmp .r89e
.r8:
    mov al, 0x58
.r89e:
    call emit_b
    jmp .ok
.done:
    pop r12
    pop rcx
    pop rbx
    ret
.pop_bytes: db 0x5F, 0x5E, 0x5A, 0x59   ; pop rdi, rsi, rdx, rcx

; ── memory manager ────────────────────────────────────────────────────────────
codegen_emit_mm_switch:
    ; rdi=mode (0=arena,1=pool): emit mov qword [rip+disp], rdi
    ; encodes: 48 C7 05 <rel32> <imm32>
    ; target address: LOAD_BASE + RT_ALC_OFFSET + RT_ALC_SIZE - 8  (the .mode variable)
    mov al, 0x48
    call emit_b
    mov al, 0xC7
    call emit_b
    mov al, 0x05
    call emit_b
    ; rel32 = target - (out_idx + 4 + 4 + LOAD_BASE)
    ; (rel32 field + imm32 field = 8 bytes; next instr is after both)
    mov rax, LOAD_BASE + RT_ALC_OFFSET + RT_ALC_SIZE - 8
    mov rdx, [out_idx]
    add rdx, 4          ; past rel32
    add rdx, 4          ; past imm32 = next instruction
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d
    mov eax, edi
    call emit_d
    ret

codegen_emit_gc_switch:
    ; rdi = gc mode (0=sweep,1=ref,2=gen,3=inc,4=region)
    ; emit: mov qword [GC_MODE_ADDR], rdi   (48 89 3C 25 <addr32>)
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0x3C
    call emit_b
    mov al, 0x25
    call emit_b
    mov eax, GC_MODE_ADDR
    call emit_d
    ret

; ── expression emit helpers ───────────────────────────────────────────────────
codegen_emit_push_rax:
    mov al, 0x50
    call emit_b
    ret

codegen_emit_pop_rbx:
    mov al, 0x5B
    call emit_b
    ret

; ── O6: register-based expression spill ───────────────────────────────────────
; Replaces push rax / pop rbx for binary-operator LHS saves with r10/r11 moves.
; depth=0 → save to r10 (free register); depth=1 → save to r11; depth≥2 → push.
; This eliminates hardware-stack memory traffic in hot expression-evaluation loops.

codegen_emit_expr_save_rax:
    ; Emit: save rax to r10 (depth=0), r11 (depth=1), or push rax (depth≥2).
    ; Increments expr_spill_depth.
    push rbx
    movzx rbx, byte [expr_spill_depth]
    cmp rbx, 0
    je .esr_d0
    cmp rbx, 1
    je .esr_d1
    ; depth ≥ 2: fallback — push rax (50)
    mov al, 0x50
    call emit_b
    inc byte [expr_spill_depth]
    pop rbx
    ret
.esr_d0:
    ; mov r10, rax = 49 89 C2
    mov al, 0x49 & 0xFF
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC2
    call emit_b
    inc byte [expr_spill_depth]
    pop rbx
    ret
.esr_d1:
    ; mov r11, rax = 49 89 C3
    mov al, 0x49 & 0xFF
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC3
    call emit_b
    inc byte [expr_spill_depth]
    pop rbx
    ret

codegen_emit_expr_restore_rbx:
    ; Emit: restore rbx from r10 (depth 1→0), r11 (depth 2→1), or pop rbx (depth≥3).
    ; Decrements expr_spill_depth.
    push rbx
    dec byte [expr_spill_depth]
    movzx rbx, byte [expr_spill_depth]
    cmp rbx, 0
    je .err_d0
    cmp rbx, 1
    je .err_d1
    ; depth was ≥ 3: fallback — pop rbx (5B)
    mov al, 0x5B
    call emit_b
    pop rbx
    ret
.err_d0:
    ; mov rbx, r10 = 4C 89 D3
    mov al, 0x4C
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xD3
    call emit_b
    pop rbx
    ret
.err_d1:
    ; mov rbx, r11 = 4C 89 DB
    mov al, 0x4C
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xDB
    call emit_b
    pop rbx
    ret

codegen_emit_expr_spill_save:
    ; Before a protocol call: if r10/r11 are live spill regs, push them.
    ; For most programs (expr_spill_depth=0 at call sites) this emits nothing.
    movzx rax, byte [expr_spill_depth]
    test rax, rax
    jz .ess_done
    ; push r10 = 41 52
    mov al, 0x41
    call emit_b
    mov al, 0x52
    call emit_b
    cmp byte [expr_spill_depth], 2
    jl .ess_done
    ; push r11 = 41 53
    mov al, 0x41
    call emit_b
    mov al, 0x53
    call emit_b
.ess_done:
    ret

codegen_emit_expr_spill_restore:
    ; After a protocol call: restore r10/r11 if they were saved.
    movzx rax, byte [expr_spill_depth]
    test rax, rax
    jz .esr2_done
    cmp rax, 2
    jl .esr2_one
    ; pop r11 = 41 5B
    mov al, 0x41
    call emit_b
    mov al, 0x5B
    call emit_b
.esr2_one:
    ; pop r10 = 41 5A
    mov al, 0x41
    call emit_b
    mov al, 0x5A
    call emit_b
.esr2_done:
    ret

codegen_emit_mov_rax_var:
    ; rdi=var_idx: emit mov rax,[var_addr]  (O2: r15 if pinned; O13: r14 if accum; O1: rbp-rel)
    ; O2: loop pin check — emit mov rax,r15 = 4C 89 F8
    cmp byte [loop_pin_active], 0
    je .mrv_no_pin
    cmp rdi, [loop_pin_var_idx]
    jne .mrv_no_pin
    ; O14: if fusion candidate is live, mark that RHS is the pinned var
    cmp byte [sr_add_candidate], 0
    je .mrv_pin_emit
    mov byte [sr_add_rhs_is_pin], 1
.mrv_pin_emit:
    mov al, 0x4C
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xF8
    call emit_b
    ret
.mrv_no_pin:
    ; O13: accumulator check — emit mov rax,r14 = 4C 89 F0
    cmp byte [loop_accum_active], 0
    je .mrv_no_accum
    cmp rdi, [loop_accum_var_idx]
    jne .mrv_no_accum
    ; O14: candidate setup — if pin is live and spill depth is 0, start a fusion candidate
    mov byte [sr_add_candidate], 0
    mov byte [sr_add_rhs_is_pin], 0
    cmp byte [loop_pin_active], 0
    je .mrv_accum_emit
    cmp byte [expr_spill_depth], 0
    jne .mrv_accum_emit
    mov byte [sr_add_candidate], 1
    mov rax, [out_idx]
    mov [sr_add_patch_pos], rax
.mrv_accum_emit:
    mov al, 0x4C
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xF0
    call emit_b
    ret
.mrv_no_accum:
    ; O14: not the accum var — cancel any pending fusion candidate
    mov byte [sr_add_candidate], 0
    ; O18: register allocator check — emit mov rax,r12/r13 for pinned params
    cmp byte [regalloc_active], 0
    je .mrv_no_regalloc
    movzx rcx, byte [regalloc_cnt]
    test rcx, rcx
    jz .mrv_no_regalloc
    movzx rax, byte [regalloc_vars]
    cmp rdi, rax
    jne .mrv_ra_slot1
    ; param 0 pinned to r12: mov rax,r12 = 4C 89 E0
    mov al, 0x4C
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xE0
    call emit_b
    ret
.mrv_ra_slot1:
    cmp rcx, 2
    jl .mrv_no_regalloc
    movzx rax, byte [regalloc_vars+1]
    cmp rdi, rax
    jne .mrv_no_regalloc
    ; param 1 pinned to r13: mov rax,r13 = 4C 89 E8
    mov al, 0x4C
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xE8
    call emit_b
    ret
.mrv_no_regalloc:
    ; O1: frame param check
    push rdi
    call codegen_find_frame_slot
    pop rdi
    cmp rax, -1
    je .mrv_global
    ; frame slot K: emit mov rax,[rsp+K*8] = 48 8B 44 24 <disp8>
    mov rcx, rax
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x44
    call emit_b
    mov al, 0x24
    call emit_b
    shl rcx, 3
    mov al, cl
    call emit_b
    ret
.mrv_global:
    ; O13 read-first detection: if accum not yet active and in outermost pinned loop,
    ; record the start of this 8-byte global load so it can be retroactively patched later
    cmp byte [loop_accum_active], 0
    jne .mrv_global_emit
    cmp byte [loop_pin_active], 0
    je .mrv_global_emit
    cmp qword [loop_pin_depth], 1
    jne .mrv_global_emit
    mov byte [loop_accum_read_first], 1
    mov rax, [out_idx]
    mov [loop_accum_load_patch_pos], rax   ; start of the 8-byte mov rax,[abs32] we're about to emit
    ; O14: also arm fusion candidate if spill depth is free (expr is at the outermost level)
    cmp byte [expr_spill_depth], 0
    jne .mrv_global_emit
    mov byte [sr_add_candidate], 1
    mov [sr_add_patch_pos], rax            ; same position: before the 8-byte global load
.mrv_global_emit:
    push rdi
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    pop rdi
    call get_var_va
    call emit_d
    ret

codegen_emit_store_rax_to_var:
    ; rdi=var_idx: emit mov [var_addr],rax  (O2: r15 if pinned; O13: r14 if accum; O1: rbp-rel)
    ; O2: loop pin check — emit mov r15,rax = 49 89 C7
    cmp byte [loop_pin_active], 0
    je .srv_no_pin
    cmp rdi, [loop_pin_var_idx]
    jne .srv_no_pin
    mov al, 0x49
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC7
    call emit_b
    ret
.srv_no_pin:
    ; O18: register allocator check — emit mov r12/r13,rax for pinned params
    cmp byte [regalloc_active], 0
    je .srv_no_regalloc
    ; guard: don't intercept if this var is the active O13 accumulator
    cmp byte [loop_accum_active], 0
    je .srv_ra_try
    cmp rdi, [loop_accum_var_idx]
    je .srv_no_regalloc
.srv_ra_try:
    movzx rcx, byte [regalloc_cnt]
    test rcx, rcx
    jz .srv_no_regalloc
    movzx rax, byte [regalloc_vars]
    cmp rdi, rax
    jne .srv_ra_slot1
    ; param 0 pinned to r12: mov r12,rax = 49 89 C4
    mov al, 0x49
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC4
    call emit_b
    ret
.srv_ra_slot1:
    cmp rcx, 2
    jl .srv_no_regalloc
    movzx rax, byte [regalloc_vars+1]
    cmp rdi, rax
    jne .srv_no_regalloc
    ; param 1 pinned to r13: mov r13,rax = 49 89 C5
    mov al, 0x49
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC5
    call emit_b
    ret
.srv_no_regalloc:
    ; O1: frame param check (frame params stay on stack, never pinned to r14)
    push rdi
    call codegen_find_frame_slot
    pop rdi
    cmp rax, -1
    je .srv_global_check
    ; frame slot K: emit mov [rsp+K*8],rax = 48 89 44 24 <disp8>
    mov rcx, rax
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0x44
    call emit_b
    mov al, 0x24
    call emit_b
    shl rcx, 3
    mov al, cl
    call emit_b
    ret
.srv_global_check:
    ; O13: if accumulator already known, redirect store to r14
    cmp byte [loop_accum_active], 0
    je .srv_first_check
    cmp rdi, [loop_accum_var_idx]
    jne .srv_global
    ; O14: if strength-reduction already wrote r14 via add r14,r15, skip this store
    cmp byte [sr_add_done], 0
    je .srv_accum_emit
    mov byte [sr_add_done], 0
    ret
.srv_accum_emit:
    ; emit mov r14,rax = 49 89 C6
    mov al, 0x49
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC6
    call emit_b
    ret
.srv_first_check:
    ; First global store inside the outermost loop → promote to accumulator (O13)
    cmp byte [loop_pin_active], 0
    je .srv_global             ; not in a pinned loop
    cmp qword [loop_pin_depth], 1
    jne .srv_global            ; nested loop: only pin in outermost
    cmp rdi, [loop_pin_var_idx]
    je .srv_global             ; this IS the loop counter
    ; If this var was globally loaded before its first store, retroactively rewrite
    ; the emitted  48 8B 04 25 <addr32>  (mov rax,[mem], 8 bytes)
    ; to            4C 89 F0 90 90 90 90 90  (mov rax,r14 + 5 NOPs)
    ; so every loop iteration reads the accumulator register instead of stale memory.
    cmp byte [loop_accum_read_first], 1
    jne .srv_do_promote
    lea rcx, [out_buffer]
    mov rdx, [loop_accum_load_patch_pos]
    mov byte [rcx+rdx],   0x4C   ; REX.WR
    mov byte [rcx+rdx+1], 0x89   ; MOV r/m64,r64
    mov byte [rcx+rdx+2], 0xF0   ; ModRM: mod=11 reg=r14(6) rm=rax(0)
    mov byte [rcx+rdx+3], 0x90   ; NOP
    mov byte [rcx+rdx+4], 0x90
    mov byte [rcx+rdx+5], 0x90
    mov byte [rcx+rdx+6], 0x90
    mov byte [rcx+rdx+7], 0x90
    mov byte [loop_accum_read_first], 0
.srv_do_promote:
    ; Promote: set accumulator, patch the pre-loop placeholder address
    mov [loop_accum_var_idx], rdi
    mov byte [loop_accum_active], 1
    call get_var_va            ; rdi=var_idx → rax=VA (rdi preserved by caller-save)
    mov rdx, [loop_accum_patch_pos]
    lea rcx, [out_buffer]
    mov [rcx+rdx+4], eax       ; patch 4-byte address into pre-loop mov r14,[addr] placeholder
    ; O14/O15: if deferred strength-reduction fired, rewind to sr_add_patch_pos
    ; and emit the fused operator (sr_op: 0=add 1=sub 2=mul 3=div)
    cmp byte [sr_add_done], 0
    je .srv_do_promote_normal
    mov byte [sr_add_done], 0
    mov byte [loop_accum_read_first], 0
    mov rax, [sr_add_patch_pos]
    mov [out_idx], rax
    movzx rcx, byte [sr_op]
    cmp rcx, 1
    je .sdp_sub
    cmp rcx, 2
    je .sdp_mul
    cmp rcx, 3
    je .sdp_div
    ; sr_op=0: add r14,r15 = 4D 01 FE
    mov al, 0x4D
    call emit_b
    mov al, 0x01
    call emit_b
    mov al, 0xFE
    call emit_b
    ret
.sdp_sub:
    ; sub r14,r15 = 4D 29 FE
    mov al, 0x4D
    call emit_b
    mov al, 0x29
    call emit_b
    mov al, 0xFE
    call emit_b
    ret
.sdp_mul:
    ; imul r14,r15 = 4D 0F AF F7
    mov al, 0x4D
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0xAF
    call emit_b
    mov al, 0xF7
    call emit_b
    ret
.sdp_div:
    ; mov rax,r14: 4C 89 F0  cqo: 48 99  idiv r15: 49 F7 FF  mov r14,rax: 49 89 C6
    mov al, 0x4C
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xF0
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0x99
    call emit_b
    mov al, 0x49
    call emit_b
    mov al, 0xF7
    call emit_b
    mov al, 0xFF
    call emit_b
    mov al, 0x49
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC6
    call emit_b
    ret
.srv_do_promote_normal:
    ; emit mov r14,rax = 49 89 C6
    mov al, 0x49
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC6
    call emit_b
    ret
.srv_global:
    push rdi
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    pop rdi
    call get_var_va
    call emit_d
    ret

codegen_emit_rdrand_rax:
    ; rdrand eax; and eax,1
    mov al, 0x0F
    call emit_b
    mov al, 0xC7
    call emit_b
    mov al, 0xF0
    call emit_b
    mov al, 0x83
    call emit_b
    mov al, 0xE0
    call emit_b
    mov al, 0x01
    call emit_b
    ret

codegen_emit_neg_rax:
    ; neg rax
    mov al, 0x48
    call emit_b
    mov al, 0xF7
    call emit_b
    mov al, 0xD8
    call emit_b
    ret

codegen_emit_not_rax:
    ; xor rax,1
    mov al, 0x48
    call emit_b
    mov al, 0x83
    call emit_b
    mov al, 0xF0
    call emit_b
    mov al, 0x01
    call emit_b
    ret

codegen_emit_bitwise_not_rax:
    ; not rax
    mov al, 0x48
    call emit_b
    mov al, 0xF7
    call emit_b
    mov al, 0xD0
    call emit_b
    ret

codegen_emit_add_rax_rbx:
    ; O14: strength-reduce :accum = accum + pin → add r14,r15 (4D 01 FE)
    ; Conditions: candidate live, RHS was the pin var, spill depth back to 0.
    ; If all met, rewind the 12 pre-emitted bytes and emit a single add r14,r15.
    cmp byte [sr_add_candidate], 0
    je .add_normal
    cmp byte [sr_add_rhs_is_pin], 0
    je .add_normal
    cmp byte [expr_spill_depth], 0
    jne .add_normal
    ; Conditions met. Check whether the accumulator is already live (Case 1)
    ; or this is the first-store promotion (Case 2: read-first / deferred).
    cmp byte [loop_accum_active], 0
    je .add_sr_deferred
    ; Case 1 — accum active: rewind the 12 pre-emitted bytes and emit add r14,r15 now.
    ;   mov rax,r14 (3) + mov r10,rax (3) + mov rax,r15 (3) + mov rbx,r10 (3) = 12
    mov rax, [sr_add_patch_pos]
    mov [out_idx], rax
    mov byte [sr_add_candidate], 0
    mov byte [sr_add_rhs_is_pin], 0
    mov byte [sr_add_done], 1      ; suppress the next O13 store
    mov al, 0x4D
    call emit_b
    mov al, 0x01
    call emit_b
    mov al, 0xFE
    call emit_b
    ret
.add_sr_deferred:
    ; Case 2 — read-first: accum not yet promoted. Signal .srv_do_promote to
    ; rewind the whole sequence (8-byte global load + save + pin-load + restore + add)
    ; and replace it with add r14,r15 at that time.
    mov byte [sr_add_candidate], 0
    mov byte [sr_add_rhs_is_pin], 0
    mov byte [sr_add_done], 1
    ; fall through: still emit add rax,rbx (will be rewound by .srv_do_promote)
.add_normal:
    mov byte [sr_add_candidate], 0
    mov byte [sr_add_rhs_is_pin], 0
    ; O19: frame-relative r10 round-trip look-back (11 bytes)
    ; If last 11 bytes = mov r10,rax (4989C2) + mov rax,[rsp+disp8] (488B4424 xx) + mov rbx,r10 (4C89D3),
    ; rewind 11 bytes and emit mov rbx,rax (4889C3) + mov rax,[rsp+disp8] (488B4424 xx),
    ; eliminating the r10 save/restore dependency chain.
    mov rax, [out_idx]
    cmp rax, 11
    jl .add_emit
    lea rcx, [out_buffer]
    add rcx, rax
    sub rcx, 11
    cmp byte [rcx+0],  0x49
    jne .add_emit
    cmp byte [rcx+1],  0x89
    jne .add_emit
    cmp byte [rcx+2],  0xC2
    jne .add_emit
    cmp byte [rcx+3],  0x48
    jne .add_emit
    cmp byte [rcx+4],  0x8B
    jne .add_emit
    cmp byte [rcx+5],  0x44
    jne .add_emit
    cmp byte [rcx+6],  0x24
    jne .add_emit
    ; [rcx+7] = disp8 (any value)
    cmp byte [rcx+8],  0x4C
    jne .add_emit
    cmp byte [rcx+9],  0x89
    jne .add_emit
    cmp byte [rcx+10], 0xD3
    jne .add_emit
    ; Match: rewind 11 bytes, emit mov rbx,rax + mov rax,[rsp+disp8]
    movzx edx, byte [rcx+7]    ; disp8
    sub rax, 11
    mov [out_idx], rax
    mov al, 0x48               ; mov rbx,rax = 48 89 C3
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC3
    call emit_b
    mov al, 0x48               ; mov rax,[rsp+disp8] = 48 8B 44 24 disp8
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x44
    call emit_b
    mov al, 0x24
    call emit_b
    mov al, dl                 ; disp8 (edx preserved across emit_b)
    call emit_b
.add_emit:
    ; add rax,rbx = 48 01 D8
    mov al, 0x48
    call emit_b
    mov al, 0x01
    call emit_b
    mov al, 0xD8
    call emit_b
    ret

codegen_emit_sub_rax_rbx:
    ; O15: strength-reduce :accum = accum - pin → sub r14,r15 (4D 29 FE)
    cmp byte [sr_add_candidate], 0
    je .sub_normal
    cmp byte [sr_add_rhs_is_pin], 0
    je .sub_normal
    cmp byte [expr_spill_depth], 0
    jne .sub_normal
    mov byte [sr_op], 1
    cmp byte [loop_accum_active], 0
    je .sub_sr_deferred
    ; Case 1: accum active — rewind 12 bytes, emit sub r14,r15
    mov rax, [sr_add_patch_pos]
    mov [out_idx], rax
    mov byte [sr_add_candidate], 0
    mov byte [sr_add_rhs_is_pin], 0
    mov byte [sr_add_done], 1
    mov al, 0x4D
    call emit_b
    mov al, 0x29
    call emit_b
    mov al, 0xFE
    call emit_b
    ret
.sub_sr_deferred:
    mov byte [sr_add_candidate], 0
    mov byte [sr_add_rhs_is_pin], 0
    mov byte [sr_add_done], 1
.sub_normal:
    mov byte [sr_add_candidate], 0
    mov byte [sr_add_rhs_is_pin], 0
    ; O19: O18-minus-literal look-back (14 bytes)
    ; If last 14 bytes = mov rax,r12 (4C89E0) + mov r10,rax (4989C2)
    ;   + mov eax,K (B8 K 00 00 00, K in 1..127) + mov rbx,r10 (4C89D3),
    ; rewind and emit lea rax,[r12-K] (5 bytes) instead of neg rax; add rax,rbx (6 bytes).
    mov rax, [out_idx]
    cmp rax, 14
    jl .sub_emit
    lea rcx, [out_buffer]
    add rcx, rax
    sub rcx, 14
    cmp byte [rcx+0],  0x4C
    jne .sub_emit
    cmp byte [rcx+1],  0x89
    jne .sub_emit
    cmp byte [rcx+2],  0xE0
    jne .sub_emit
    cmp byte [rcx+3],  0x49
    jne .sub_emit
    cmp byte [rcx+4],  0x89
    jne .sub_emit
    cmp byte [rcx+5],  0xC2
    jne .sub_emit
    cmp byte [rcx+6],  0xB8
    jne .sub_emit
    movzx edx, byte [rcx+7]
    test edx, edx
    jz .sub_emit
    cmp edx, 128
    jge .sub_emit
    cmp byte [rcx+8],  0x00
    jne .sub_emit
    cmp byte [rcx+9],  0x00
    jne .sub_emit
    cmp byte [rcx+10], 0x00
    jne .sub_emit
    cmp byte [rcx+11], 0x4C
    jne .sub_emit
    cmp byte [rcx+12], 0x89
    jne .sub_emit
    cmp byte [rcx+13], 0xD3
    jne .sub_emit
    ; Match: rewind 14 bytes, emit lea rax,[r12-K] = 49 8D 44 24 <(256-K)&0xFF>
    sub rax, 14
    mov [out_idx], rax
    neg edx
    and edx, 0xFF        ; dl = disp8 = byte(-K)
    mov al, 0x49
    call emit_b
    mov al, 0x8D
    call emit_b
    mov al, 0x44
    call emit_b
    mov al, 0x24
    call emit_b
    mov al, dl           ; edx preserved across emit_b
    call emit_b
    ret
.sub_emit:
    ; rbx - rax → rax: neg rax; add rax,rbx
    mov al, 0x48
    call emit_b
    mov al, 0xF7
    call emit_b
    mov al, 0xD8
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0x01
    call emit_b
    mov al, 0xD8
    call emit_b
    ret

codegen_emit_imul_rax_rbx:
    ; O15: strength-reduce :accum = accum * pin → imul r14,r15 (4D 0F AF F7)
    cmp byte [sr_add_candidate], 0
    je .mul_normal
    cmp byte [sr_add_rhs_is_pin], 0
    je .mul_normal
    cmp byte [expr_spill_depth], 0
    jne .mul_normal
    mov byte [sr_op], 2
    cmp byte [loop_accum_active], 0
    je .mul_sr_deferred
    ; Case 1: accum active — rewind 12 bytes, emit imul r14,r15
    mov rax, [sr_add_patch_pos]
    mov [out_idx], rax
    mov byte [sr_add_candidate], 0
    mov byte [sr_add_rhs_is_pin], 0
    mov byte [sr_add_done], 1
    mov al, 0x4D
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0xAF
    call emit_b
    mov al, 0xF7
    call emit_b
    ret
.mul_sr_deferred:
    mov byte [sr_add_candidate], 0
    mov byte [sr_add_rhs_is_pin], 0
    mov byte [sr_add_done], 1
.mul_normal:
    mov byte [sr_add_candidate], 0
    mov byte [sr_add_rhs_is_pin], 0
    ; imul rax,rbx
    mov al, 0x48
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0xAF
    call emit_b
    mov al, 0xC3
    call emit_b
    ret

codegen_emit_idiv_rbx_by_rax:
    ; O15: strength-reduce :accum = accum / pin → mov rax,r14; cqo; idiv r15; mov r14,rax
    cmp byte [sr_add_candidate], 0
    je .div_normal
    cmp byte [sr_add_rhs_is_pin], 0
    je .div_normal
    cmp byte [expr_spill_depth], 0
    jne .div_normal
    mov byte [sr_op], 3
    cmp byte [loop_accum_active], 0
    je .div_sr_deferred
    ; Case 1: accum active — rewind 12 bytes, emit fused div sequence
    mov rax, [sr_add_patch_pos]
    mov [out_idx], rax
    mov byte [sr_add_candidate], 0
    mov byte [sr_add_rhs_is_pin], 0
    mov byte [sr_add_done], 1
    mov al, 0x4C  ; mov rax,r14 = 4C 89 F0
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xF0
    call emit_b
    mov al, 0x48  ; cqo = 48 99
    call emit_b
    mov al, 0x99
    call emit_b
    mov al, 0x49  ; idiv r15 = 49 F7 FF
    call emit_b
    mov al, 0xF7
    call emit_b
    mov al, 0xFF
    call emit_b
    mov al, 0x49  ; mov r14,rax = 49 89 C6
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC6
    call emit_b
    ret
.div_sr_deferred:
    mov byte [sr_add_candidate], 0
    mov byte [sr_add_rhs_is_pin], 0
    mov byte [sr_add_done], 1
.div_normal:
    mov byte [sr_add_candidate], 0
    mov byte [sr_add_rhs_is_pin], 0
    ; rbx/rax → rax: mov rcx,rax; mov rax,rbx; cqo; idiv rcx
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC1
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xD8
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0x99
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0xF7
    call emit_b
    mov al, 0xF9
    call emit_b
    ret

codegen_emit_imod_rbx_by_rax:
    ; rbx%rax → rax (via rdx after idiv)
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC1
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xD8
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0x99
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0xF7
    call emit_b
    mov al, 0xF9
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xD0
    call emit_b
    ret

codegen_emit_cmp_rbx_rax_setcc:
    ; rdi=setCC byte: emit cmp rbx,rax; setCC al; movzx rax,al
    ; O19: look-back: if last 14 bytes = O18-minus-literal setup, emit cmp r12,K + setCC
    push rdi
    mov rax, [out_idx]
    cmp rax, 14
    jl .cmp_normal
    lea rcx, [out_buffer]
    add rcx, rax
    sub rcx, 14
    cmp byte [rcx+0],  0x4C
    jne .cmp_normal
    cmp byte [rcx+1],  0x89
    jne .cmp_normal
    cmp byte [rcx+2],  0xE0
    jne .cmp_normal
    cmp byte [rcx+3],  0x49
    jne .cmp_normal
    cmp byte [rcx+4],  0x89
    jne .cmp_normal
    cmp byte [rcx+5],  0xC2
    jne .cmp_normal
    cmp byte [rcx+6],  0xB8
    jne .cmp_normal
    movzx edx, byte [rcx+7]
    test edx, edx
    jz .cmp_normal
    cmp edx, 128
    jge .cmp_normal
    cmp byte [rcx+8],  0x00
    jne .cmp_normal
    cmp byte [rcx+9],  0x00
    jne .cmp_normal
    cmp byte [rcx+10], 0x00
    jne .cmp_normal
    cmp byte [rcx+11], 0x4C
    jne .cmp_normal
    cmp byte [rcx+12], 0x89
    jne .cmp_normal
    cmp byte [rcx+13], 0xD3
    jne .cmp_normal
    ; Match: rewind 14 bytes, emit cmp r12,K (49 83 FC K) + setCC al + movzx rax,al
    sub rax, 14
    mov [out_idx], rax
    mov al, 0x49
    call emit_b
    mov al, 0x83
    call emit_b
    mov al, 0xFC
    call emit_b
    mov al, dl           ; K (edx preserved across emit_b)
    call emit_b
    mov al, 0x0F
    call emit_b
    pop rax              ; setCC byte (was rdi)
    call emit_b
    mov al, 0xC0
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0xB6
    call emit_b
    mov al, 0xC0
    call emit_b
    ret
.cmp_normal:
    mov al, 0x48
    call emit_b
    mov al, 0x39
    call emit_b
    mov al, 0xC3
    call emit_b
    mov al, 0x0F
    call emit_b
    pop rax
    call emit_b
    mov al, 0xC0
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0xB6
    call emit_b
    mov al, 0xC0
    call emit_b
    ret

codegen_emit_test_rax_jz:
    ; emit: test rax,rax; jz <placeholder>
    mov al, 0x48
    call emit_b
    mov al, 0x85
    call emit_b
    mov al, 0xC0
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0x84
    call emit_b
    mov rax, [out_idx]
    mov rbx, [jump_patch_depth]
    lea rcx, [jump_patch_stack]
    mov [rcx+rbx*8], rax
    inc qword [jump_patch_depth]
    xor eax, eax
    call emit_d
    ret

codegen_emit_test_rax_jnz:
    ; emit: test rax,rax; jnz <placeholder>  — pushes patch slot on jump_patch_stack
    mov al, 0x48
    call emit_b
    mov al, 0x85
    call emit_b
    mov al, 0xC0
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0x85
    call emit_b
    mov rax, [out_idx]
    mov rbx, [jump_patch_depth]
    lea rcx, [jump_patch_stack]
    mov [rcx+rbx*8], rax
    inc qword [jump_patch_depth]
    xor eax, eax
    call emit_d
    ret

codegen_emit_normalize_bool_rax:
    ; emit: test rax,rax; setnz al; movzx rax,al
    mov al, 0x48
    call emit_b
    mov al, 0x85
    call emit_b
    mov al, 0xC0
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0x95
    call emit_b
    mov al, 0xC0
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0xB6
    call emit_b
    mov al, 0xC0
    call emit_b
    ret

codegen_emit_jmp_get_slot:
    ; emit: jmp 0x00000000; return patch-slot offset in rax (for caller to patch later)
    push rbx
    mov al, 0xE9
    call emit_b
    mov rbx, [out_idx]  ; offset of placeholder dword
    xor eax, eax
    call emit_d
    mov rax, rbx
    pop rbx
    ret

codegen_patch_slot_to_here:
    ; rdi = patch-slot offset in out_buffer
    ; patches rel32 at [out_buffer+rdi] to reach current out_idx
    mov rax, [out_idx]
    sub rax, rdi
    sub rax, 4
    lea rcx, [out_buffer]
    mov [rcx+rdi], eax
    ret

; ── float emit ────────────────────────────────────────────────────────────────
; All float ops: rax=rhs bits, rbx=lhs bits
; → movq xmm1,rax; movq xmm0,rbx; op xmm0,xmm1; movq rax,xmm0
%macro FLOAT_OP 1
    mov al, 0x66
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0x6E
    call emit_b
    mov al, 0xC8
    call emit_b
    mov al, 0x66
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0x6E
    call emit_b
    mov al, 0xC3
    call emit_b
    mov al, 0xF2
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, %1
    call emit_b
    mov al, 0xC1
    call emit_b
    mov al, 0x66
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0x7E
    call emit_b
    mov al, 0xC0
    call emit_b
%endmacro

codegen_emit_addsd_rax_rbx:
    FLOAT_OP 0x58
    ret
codegen_emit_subsd_rax_rbx:
    FLOAT_OP 0x5C
    ret
codegen_emit_mulsd_rax_rbx:
    FLOAT_OP 0x59
    ret
codegen_emit_divsd_rax_rbx:
    FLOAT_OP 0x5E
    ret

codegen_emit_cvttsd2si_rax:
    ; movq xmm0,rax; cvttsd2si rax,xmm0
    mov al, 0x66
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0x6E
    call emit_b
    mov al, 0xC0
    call emit_b
    mov al, 0xF2
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0x2C
    call emit_b
    mov al, 0xC0
    call emit_b
    ret

codegen_emit_cvtsi2sd_rax:
    ; cvtsi2sd xmm0,rax; movq rax,xmm0
    mov al, 0xF2
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0x2A
    call emit_b
    mov al, 0xC0
    call emit_b
    mov al, 0x66
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0x7E
    call emit_b
    mov al, 0xC0
    call emit_b
    ret

; ── bitwise emit ──────────────────────────────────────────────────────────────
codegen_emit_bitwise_and_rax_rbx:
    ; and rax,rbx
    mov al, 0x48
    call emit_b
    mov al, 0x21
    call emit_b
    mov al, 0xD8
    call emit_b
    ret

codegen_emit_bitwise_or_rax_rbx:
    ; or rax,rbx
    mov al, 0x48
    call emit_b
    mov al, 0x09
    call emit_b
    mov al, 0xD8
    call emit_b
    ret

codegen_emit_bitwise_xor_rax_rbx:
    ; xor rax,rbx
    mov al, 0x48
    call emit_b
    mov al, 0x31
    call emit_b
    mov al, 0xD8
    call emit_b
    ret

codegen_emit_and_bool_rax_rbx:
    ; test rbx,rbx; setnz cl; test rax,rax; setnz al; and al,cl; movzx rax,al
    mov al, 0x48
    call emit_b
    mov al, 0x85
    call emit_b
    mov al, 0xDB
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0x95
    call emit_b
    mov al, 0xC1
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0x85
    call emit_b
    mov al, 0xC0
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0x95
    call emit_b
    mov al, 0xC0
    call emit_b
    mov al, 0x20
    call emit_b
    mov al, 0xC8
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0xB6
    call emit_b
    mov al, 0xC0
    call emit_b
    ret

codegen_emit_or_bool_rax_rbx:
    ; or rax,rbx; setnz al; movzx rax,al
    mov al, 0x48
    call emit_b
    mov al, 0x09
    call emit_b
    mov al, 0xD8
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0x95
    call emit_b
    mov al, 0xC0
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0xB6
    call emit_b
    mov al, 0xC0
    call emit_b
    ret

codegen_emit_shl_rax_by_rbx:
    ; mov cl,bl; mov rax,rbx ... wait: rax=shift, rbx=value
    ; shl rbx by rax: mov cl,al; mov rax,rbx; shl rax,cl
    mov al, 0x88
    call emit_b
    mov al, 0xC1
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xD8
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0xD3
    call emit_b
    mov al, 0xE0
    call emit_b
    ret

codegen_emit_shr_rax_by_rbx:
    ; mov cl,al; mov rax,rbx; shr rax,cl
    mov al, 0x88
    call emit_b
    mov al, 0xC1
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xD8
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0xD3
    call emit_b
    mov al, 0xE8
    call emit_b
    ret

; ── string / sequence / error ─────────────────────────────────────────────────
codegen_emit_str_rax:
    ; rdi=str_ptr rsi=len: emit JMP-over + bytes + null + MOV rax,VA
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov al, 0xE9
    call emit_b
    mov rbx, [out_idx]
    xor eax, eax
    call emit_d
    mov r14, [out_idx]
    add r14, LOAD_BASE
    xor r15, r15
.sl:
    cmp r15, r13
    jge .sd
    movzx eax, byte [r12+r15]
    call emit_b
    inc r15
    jmp .sl
.sd:
    xor eax, eax
    call emit_b
    ; patch JMP rel32
    mov rdx, [out_idx]
    sub rdx, rbx
    sub rdx, 4
    lea rax, [out_buffer]
    mov [rax+rbx], edx
    ; emit: mov rax,<abs_addr64> (48 B8 <8 bytes>)
    mov al, 0x48
    call emit_b
    mov al, 0xB8
    call emit_b
    mov rax, r14
    call emit_q
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

codegen_emit_seq_alloc:
    ; rdi=var_idx: alloc 80 bytes, cap=8, len=0, store ptr
    push rdi
    ; emit: mov edi,80; call rt_alc
    mov al, 0xBF
    call emit_b
    mov eax, 80
    call emit_d
    mov al, 0xE8
    call emit_b
    mov rax, LOAD_BASE+RT_ALC_OFFSET
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d
    ; emit: mov qword [rax],8 (cap)
    mov al, 0x48
    call emit_b
    mov al, 0xC7
    call emit_b
    mov al, 0x00
    call emit_b
    mov eax, 8
    call emit_d
    ; emit: mov qword [rax+8],0 (len)
    mov al, 0x48
    call emit_b
    mov al, 0xC7
    call emit_b
    mov al, 0x40
    call emit_b
    mov al, 0x08
    call emit_b
    xor eax, eax
    call emit_d
    ; emit: mov [var_addr],rax
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    pop rdi
    call get_var_va
    call emit_d
    ret

codegen_emit_seq_push:
    ; rdi=var_idx; value in rax: push val; load ptr→rbx; load len→rcx; pop val; store; inc len
    push rdi
    ; push rax (save value)
    mov al, 0x50
    call emit_b
    ; mov rbx,[ptr_addr]
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x1C
    call emit_b
    mov al, 0x25
    call emit_b
    pop rdi
    push rdi
    call get_var_va
    call emit_d
    ; mov rcx,[rbx+8]
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x4B
    call emit_b
    mov al, 0x08
    call emit_b
    ; bounds check: cmp rcx,[rbx]  →  48 3B 0B
    ; if rcx < cap (CF=1) skip 57-byte grow block; else double-and-realloc (#19)
    mov al, 0x48
    call emit_b
    mov al, 0x3B
    call emit_b
    mov al, 0x0B
    call emit_b
    ; jb +56  →  72 38  (skip grow code when len < cap)
    ; grow block is exactly 56 bytes; landing on pop rax restores saved value
    mov al, 0x72
    call emit_b
    mov al, 0x38
    call emit_b
    ; ── inline grow (57 bytes) ───────────────────────────────────────────────
    ; Strategy: new_cap = old_cap*2; new_size = 16 + new_cap*8;
    ;           rt_alc(new_size) → rax (new ptr);
    ;           copy header+elements; update var slot; restore rbx/rcx.
    ; At entry: rbx=old_ptr rcx=old_len(=old_cap at overflow) stack=[value]
    ; push rcx          →  51        (save old cap across rt_alc call)
    mov al, 0x51
    call emit_b
    ; mov rdi,[rbx]     →  48 8B 3B  (rdi = old cap)
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x3B
    call emit_b
    ; shl rdi,4         →  48 C1 E7 04  (rdi = old_cap*16 = new_size-16)
    mov al, 0x48
    call emit_b
    mov al, 0xC1
    call emit_b
    mov al, 0xE7
    call emit_b
    mov al, 0x04
    call emit_b
    ; add rdi,16        →  48 83 C7 10  (rdi = new_size = 16 + old_cap*16)
    mov al, 0x48
    call emit_b
    mov al, 0x83
    call emit_b
    mov al, 0xC7
    call emit_b
    mov al, 0x10
    call emit_b
    ; call rt_alc       →  E8 <rel32>   (rax = new buffer ptr)
    mov al, 0xE8
    call emit_b
    mov rax, LOAD_BASE+RT_ALC_OFFSET
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d
    ; pop rcx           →  59           (rcx = old cap; syscall clobbered it)
    mov al, 0x59
    call emit_b
    ; push rax          →  50           (save new ptr)
    mov al, 0x50
    call emit_b
    ; mov r11,rcx       →  49 89 CB     (r11 = old cap)
    mov al, 0x49
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xCB
    call emit_b
    ; shl r11,1         →  49 D1 E3     (r11 = new cap = old_cap*2)
    mov al, 0x49
    call emit_b
    mov al, 0xD1
    call emit_b
    mov al, 0xE3
    call emit_b
    ; mov [rax],r11     →  4C 89 18     ([new_ptr+0] = new cap)
    mov al, 0x4C
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0x18
    call emit_b
    ; mov [rax+8],rcx   →  48 89 48 08  ([new_ptr+8] = len)
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0x08
    call emit_b
    ; lea rdi,[rax+16]  →  48 8D 78 10  (dst for rep movsq)
    mov al, 0x48
    call emit_b
    mov al, 0x8D
    call emit_b
    mov al, 0x78
    call emit_b
    mov al, 0x10
    call emit_b
    ; lea rsi,[rbx+16]  →  48 8D 73 10  (src = old ptr + 16)
    mov al, 0x48
    call emit_b
    mov al, 0x8D
    call emit_b
    mov al, 0x73
    call emit_b
    mov al, 0x10
    call emit_b
    ; rep movsq         →  F3 48 A5     (copy rcx qwords old→new)
    mov al, 0xF3
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0xA5
    call emit_b
    ; pop rbx           →  5B           (rbx = new ptr)
    mov al, 0x5B
    call emit_b
    ; mov [var_addr],rbx → 48 89 1C 25 <addr32>  (update var slot with new ptr)
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0x1C
    call emit_b
    mov al, 0x25
    call emit_b
    pop rdi              ; peek var_idx (left on stack at function entry)
    push rdi
    call get_var_va
    call emit_d
    ; mov rcx,[rbx+8]   →  48 8B 4B 08  (reload len; rbx is now new ptr)
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x4B
    call emit_b
    mov al, 0x08
    call emit_b
    ; ── end grow block ──────────────────────────────────────────────────────
    ; fall through: rbx=new_ptr rcx=len stack=[value]  → store proceeds
    ; pop rax (restore value)
    mov al, 0x58
    call emit_b
    ; mov [rbx+rcx*8+16],rax
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0x44
    call emit_b
    mov al, 0xCB
    call emit_b
    mov al, 0x10
    call emit_b
    ; inc qword [rbx+8]
    mov al, 0x48
    call emit_b
    mov al, 0xFF
    call emit_b
    mov al, 0x43
    call emit_b
    mov al, 0x08
    call emit_b
    pop rdi
    ret

codegen_emit_seq_pop_rax:
    ; rdi=var_idx: dec len, load last element → rax
    push rdi
    ; mov rbx,[ptr_addr]
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x1C
    call emit_b
    mov al, 0x25
    call emit_b
    pop rdi
    push rdi
    call get_var_va
    call emit_d
    ; dec qword [rbx+8]
    mov al, 0x48
    call emit_b
    mov al, 0xFF
    call emit_b
    mov al, 0x4B
    call emit_b
    mov al, 0x08
    call emit_b
    ; mov rcx,[rbx+8]
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x4B
    call emit_b
    mov al, 0x08
    call emit_b
    ; mov rax,[rbx+rcx*8+16]
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x44
    call emit_b
    mov al, 0xCB
    call emit_b
    mov al, 0x10
    call emit_b
    pop rdi
    ret

codegen_emit_seq_len_rax:
    ; rdi=var_idx: mov rax,[ptr_addr]; mov rax,[rax+8]
    push rdi
    ; mov rax,[ptr_addr]
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    pop rdi
    push rdi
    call get_var_va
    call emit_d
    ; mov rax,[rax+8]
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x40
    call emit_b
    mov al, 0x08
    call emit_b
    pop rdi
    ret

codegen_emit_mov_rdi_rax:
    ; emit: mov rdi,rax
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC7
    call emit_b
    ret

codegen_emit_call_rt_err:
    ; emit: call rt_prq (= RT_PRQ_OFFSET)
    mov al, 0xE8
    call emit_b
    mov rax, LOAD_BASE+RT_PRQ_OFFSET
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d
    ret

; ── raw emit proxy exports (for parser indirect calls) ────────────────────────
codegen_emit_b_raw:
    jmp emit_b

codegen_emit_d_raw:
    jmp emit_d

codegen_get_var_va_proxy:
    jmp get_var_va

; ── in-place inc/dec ──────────────────────────────────────────────────────────
; ── caller-save / caller-restore primitives (O1+O2 aware) ────────────────────
codegen_emit_push_var_slot:
    ; rdi=var_idx: push qword [var_addr]
    ; O1: frame params protected by hardware frame — skip
    ; O2: pinned var → push r15 = 41 57
    push rdi
    call codegen_find_frame_slot   ; rdi preserved; rax=slot or -1
    pop rdi
    cmp rax, -1
    jne .pvs_skip                  ; frame param: hardware frame protects it
    cmp byte [loop_pin_active], 0
    je .pvs_check_accum
    cmp rdi, [loop_pin_var_idx]
    jne .pvs_check_accum
    ; pinned to r15: push r15 = 41 57
    mov al, 0x41
    call emit_b
    mov al, 0x57
    call emit_b
    ret
.pvs_check_accum:
    ; O13: accumulator var → push r14 = 41 56
    cmp byte [loop_accum_active], 0
    je .pvs_global
    cmp rdi, [loop_accum_var_idx]
    jne .pvs_global
    mov al, 0x41
    call emit_b
    mov al, 0x56
    call emit_b
    ret
.pvs_global:
    push rdi
    mov al, 0xFF
    call emit_b
    mov al, 0x34
    call emit_b
    mov al, 0x25
    call emit_b
    pop rdi
    call get_var_va
    call emit_d
    ret
.pvs_skip:
    ret

codegen_emit_pop_var_slot:
    ; rdi=var_idx: pop qword [var_addr]
    ; O1: frame params — skip
    ; O2: pinned var → pop r15 = 41 5F
    push rdi
    call codegen_find_frame_slot
    pop rdi
    cmp rax, -1
    jne .ppv_skip
    cmp byte [loop_pin_active], 0
    je .ppv_check_accum
    cmp rdi, [loop_pin_var_idx]
    jne .ppv_check_accum
    ; pinned to r15: pop r15 = 41 5F
    mov al, 0x41
    call emit_b
    mov al, 0x5F
    call emit_b
    ret
.ppv_check_accum:
    ; O13: accumulator var → pop r14 = 41 5E
    cmp byte [loop_accum_active], 0
    je .ppv_global
    cmp rdi, [loop_accum_var_idx]
    jne .ppv_global
    mov al, 0x41
    call emit_b
    mov al, 0x5E
    call emit_b
    ret
.ppv_global:
    push rdi
    mov al, 0x8F
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    pop rdi
    call get_var_va
    call emit_d
    ret
.ppv_skip:
    ret

codegen_emit_inc_var:
    ; rdi=var_idx: emit inc [var_addr]; mov rax,[var_addr]  (O2: use r15 if pinned)
    cmp byte [loop_pin_active], 0
    je .eiv_global
    cmp rdi, [loop_pin_var_idx]
    jne .eiv_global
    ; pinned: inc r15 = 49 FF C7; mov rax,r15 = 4C 89 F8
    mov al, 0x49
    call emit_b
    mov al, 0xFF
    call emit_b
    mov al, 0xC7
    call emit_b
    mov al, 0x4C
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xF8
    call emit_b
    ret
.eiv_global:
    push rdi
    mov al, 0x48
    call emit_b
    mov al, 0xFF
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    pop rdi
    push rdi
    call get_var_va
    call emit_d
    pop rdi
    call codegen_emit_mov_rax_var
    ret

codegen_emit_dec_var:
    ; rdi=var_idx: emit dec qword [var_addr]; mov rax,[var_addr]
    push rdi
    mov al, 0x48
    call emit_b
    mov al, 0xFF
    call emit_b
    mov al, 0x0C
    call emit_b
    mov al, 0x25
    call emit_b
    pop rdi
    push rdi
    call get_var_va
    call emit_d
    pop rdi
    call codegen_emit_mov_rax_var
    ret

; ── variable swap ─────────────────────────────────────────────────────────────
codegen_emit_swap_vars:
    ; rdi=var1_idx rsi=var2_idx
    ; emit: mov rax,[v1]; mov rbx,[v2]; mov [v1],rbx; mov [v2],rax
    push rbx
    push rdi
    push rsi
    ; mov rax, [var1]
    call codegen_emit_mov_rax_var
    ; mov rbx, [var2] : 48 8B 1C 25 <addr>
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x1C
    call emit_b
    mov al, 0x25
    call emit_b
    pop rsi
    push rsi
    mov rdi, rsi
    call get_var_va
    call emit_d
    pop rsi
    pop rdi
    push rdi
    push rsi
    ; mov [var1], rbx : 48 89 1C 25 <addr>
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0x1C
    call emit_b
    mov al, 0x25
    call emit_b
    pop rsi
    pop rdi
    push rdi
    push rsi
    call get_var_va
    call emit_d
    pop rsi
    pop rdi
    ; mov [var2], rax : 48 89 04 25 <addr>
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    mov rdi, rsi
    call get_var_va
    call emit_d
    pop rbx
    ret

; ── abs(rax) ─────────────────────────────────────────────────────────────────
codegen_emit_abs_rax:
    ; emit: mov rbx,rax; neg rax; cmovns rax,rbx
    ; mov rbx,rax  : 48 89 C3
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC3
    call emit_b
    ; neg rax      : 48 F7 D8
    mov al, 0x48
    call emit_b
    mov al, 0xF7
    call emit_b
    mov al, 0xD8
    call emit_b
    ; cmovs rax,rbx : 48 0F 48 C3  (if SF=1 after neg, original was positive — keep rbx)
    mov al, 0x48
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0x48
    call emit_b
    mov al, 0xC3
    call emit_b
    ret

; ── cap(seq_var) → rax ───────────────────────────────────────────────────────
codegen_emit_cap_rax:
    ; rdi=var_idx: emit mov rax,[ptr_addr]; mov rax,[rax+0]
    push rdi
    ; mov rax, [ptr_addr]
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    pop rdi
    push rdi
    call get_var_va
    call emit_d
    ; mov rax, [rax+0] : 48 8B 00
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x00
    call emit_b
    pop rdi
    ret

; ── exit(1) syscall emitter ──────────────────────────────────────────────────
codegen_emit_exit1:
    ; emit: mov rax,60; mov rdi,1; syscall  →  exit(1)
    ; mov rax, 60  :  48 C7 C0 3C 00 00 00
    mov al, 0x48
    call emit_b
    mov al, 0xC7
    call emit_b
    mov al, 0xC0
    call emit_b
    mov al, 0x3C
    call emit_b
    mov al, 0x00
    call emit_b
    mov al, 0x00
    call emit_b
    mov al, 0x00
    call emit_b
    ; mov rdi, 1  :  48 C7 C7 01 00 00 00
    mov al, 0x48
    call emit_b
    mov al, 0xC7
    call emit_b
    mov al, 0xC7
    call emit_b
    mov al, 0x01
    call emit_b
    mov al, 0x00
    call emit_b
    mov al, 0x00
    call emit_b
    mov al, 0x00
    call emit_b
    ; syscall  :  0F 05
    mov al, 0x0F
    call emit_b
    mov al, 0x05
    call emit_b
    ret

; ── loop-else flag stack ───────────────────────────────────────────────────────
; Each loop pushes its __le flag variable's var_idx (or -1 for no flag).
; codegen_emit_break peeks the top and emits flag-set code before the JMP.

codegen_push_loop_else_flag:
    ; rdi = flag_var_idx  (-1 = sentinel / no flag for this loop)
    mov rax, [loop_else_flag_depth]
    lea rcx, [loop_else_flag_stack]
    mov [rcx+rax*8], rdi
    inc qword [loop_else_flag_depth]
    ret

codegen_pop_loop_else_flag:
    ; Returns flag_var_idx in rax  (-1 if stack empty)
    cmp qword [loop_else_flag_depth], 0
    je .empty
    dec qword [loop_else_flag_depth]
    mov rax, [loop_else_flag_depth]
    lea rcx, [loop_else_flag_stack]
    mov rax, [rcx+rax*8]
    ret
.empty:
    mov rax, -1
    ret

codegen_peek_loop_else_flag:
    ; Returns top of stack in rax  (-1 if empty or sentinel)
    cmp qword [loop_else_flag_depth], 0
    je .empty
    mov rax, [loop_else_flag_depth]
    dec rax
    lea rcx, [loop_else_flag_stack]
    mov rax, [rcx+rax*8]
    ret
.empty:
    mov rax, -1
    ret

; ── each iterator codegen ──────────────────────────────────────────────────────
; codegen_emit_each_start(rdi=seq_var_idx, rsi=elem_var_idx, rdx=ctr_var_idx)
;   Emits (in generated binary):
;     ctr = 0                            (once, before loop top — init only)
;   [loop top]:
;     rbx = *seq_ptr                     (load heap sequence pointer)
;     rax = ctr                          (load counter)
;     cmp rax, [rbx+8]                   (compare vs length)
;     jge exit                           (exit when counter >= length)
;     rax = [rbx + rax*8 + 16]          (load element[ctr])
;     *elem = rax                        (write to user variable)
;   Returns loop_top_pc (offset in out_buffer) in rax.

codegen_emit_each_start:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi            ; seq_var_idx
    mov r13, rsi            ; elem_var_idx
    mov r14, rdx            ; ctr_var_idx
    ; O2: track nesting depth (matches dec in each_end)
    inc qword [loop_pin_depth]
    ; push break base (same as codegen_emit_loop_base)
    mov rax, [break_jump_depth]
    mov rbx, [break_base_depth]
    lea rcx, [break_base_stack]
    mov [rcx+rbx*8], rax
    inc qword [break_base_depth]
    ; emit: mov qword [ctr_addr], 0  (48 C7 04 25 addr 00 00 00 00)
    mov al, 0x48
    call emit_b
    mov al, 0xC7
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    mov rdi, r14
    call get_var_va
    call emit_d
    xor eax, eax
    call emit_d
    ; save loop top (condition-check start, AFTER the one-time init)
    mov r15, [out_idx]
    ; push cont target (for skip)
    mov rdi, r15
    call codegen_push_cont
    ; emit: mov rbx, [seq_ptr_addr]  (48 8B 1C 25 addr)
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x1C
    call emit_b
    mov al, 0x25
    call emit_b
    mov rdi, r12
    call get_var_va
    call emit_d
    ; emit: mov rax, [ctr_addr]  (48 8B 04 25 addr)
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    mov rdi, r14
    call get_var_va
    call emit_d
    ; emit: cmp rax, [rbx+8]  (48 3B 43 08)
    mov al, 0x48
    call emit_b
    mov al, 0x3B
    call emit_b
    mov al, 0x43
    call emit_b
    mov al, 0x08
    call emit_b
    ; emit: jge exit  (0F 8D + placeholder rel32)
    mov al, 0x0F
    call emit_b
    mov al, 0x8D
    call emit_b
    mov rax, [out_idx]
    mov rbx, [jump_patch_depth]
    lea rcx, [jump_patch_stack]
    mov [rcx+rbx*8], rax
    inc qword [jump_patch_depth]
    xor eax, eax
    call emit_d
    ; emit: mov rax, [rbx+rax*8+16]  (48 8B 44 C3 10)
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x44
    call emit_b
    mov al, 0xC3
    call emit_b
    mov al, 0x10
    call emit_b
    ; emit: mov [elem_addr], rax  (48 89 04 25 addr)
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    mov rdi, r13
    call get_var_va
    call emit_d
    ; return loop_top_pc
    mov rax, r15
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; codegen_emit_each_end(rdi=loop_top_pc, rsi=ctr_var_idx)
;   Emits (in generated binary):
;     inc qword [ctr_addr]
;     jmp loop_top
;   Then patches the jge exit and all break jumps.

codegen_emit_each_end:
    push rbx
    push r12
    mov r12, rsi            ; ctr_var_idx
    ; emit: inc qword [ctr_addr]  (48 FF 04 25 addr)
    mov al, 0x48
    call emit_b
    mov al, 0xFF
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    push rdi                ; save loop_top_pc
    mov rdi, r12
    call get_var_va
    call emit_d             ; emit ctr_addr
    pop rdi                 ; restore loop_top_pc
    ; emit: jmp loop_top  (E9 rel32)
    ; rel32 = loop_top_pc - (out_idx_after_E9 + 4)
    mov al, 0xE9
    call emit_b
    mov rax, rdi            ; loop_top_pc (offset in out_buffer)
    mov rdx, [out_idx]      ; position of the rel32 field
    add rdx, 4              ; position of next instruction
    sub rax, rdx            ; rel32 = target - next_instr (LOAD_BASE cancels)
    call emit_d
    ; patch the jge exit jump
    call codegen_patch_jump
    ; patch all break jumps
    call codegen_patch_breaks
    ; pop cont (registered for skip)
    call codegen_pop_cont
    ; O2: decrement depth for dynamic loops (no pin flush needed since no pin was set)
    dec qword [loop_pin_depth]
    pop r12
    pop rbx
    ret

; ══════════════════════════════════════════════════════════════════════════════
; O1 / O2 / O4 new helpers
; ══════════════════════════════════════════════════════════════════════════════

; ── O1/O5: find frame slot for a var_idx (params + locals) ───────────────────
; rdi=var_idx → rax=slot K (0-based) or -1 (not in frame)
; Preserves rdi; clobbers rax, rcx, rdx only.
codegen_find_frame_slot:
    cmp byte [frame_active], 0
    je .not_frame
    xor ecx, ecx
    movzx rdx, byte [frame_param_cnt]
.scan_params:
    cmp rcx, rdx
    jge .scan_locals
    movzx eax, byte [frame_param_vars + rcx]
    cmp rdi, rax
    je .found
    inc rcx
    jmp .scan_params
.scan_locals:
    ; O5: search local vars after params
    xor ecx, ecx
    movzx rdx, byte [frame_local_cnt]
.scan_lc:
    cmp rcx, rdx
    jge .not_frame
    movzx eax, byte [frame_local_vars + rcx]
    cmp rdi, rax
    je .found_local
    inc rcx
    jmp .scan_lc
.found_local:
    ; slot = param_cnt + local_idx + regalloc_cnt (O18: offset past callee-save area)
    movzx eax, byte [frame_param_cnt]
    add rax, rcx
    movzx rdx, byte [regalloc_cnt]
    add rax, rdx
    ret
.found:
    ; slot = param_idx + regalloc_cnt (O18: offset past callee-save area)
    mov rax, rcx
    movzx rdx, byte [regalloc_cnt]
    add rax, rdx
    ret
.not_frame:
    mov rax, -1
    ret

; ── O1: set current frame params (called from parser at protocol entry) ────────
; rdi=param_cnt  rsi=ptr to byte array of param var indices
codegen_set_frame:
    push rbx
    push rcx
    movzx rbx, dil           ; param_cnt (byte)
    mov byte [frame_active], 1
    mov [frame_param_cnt], dil
    mov byte [frame_local_cnt], 0   ; O5: reset locals on each protocol entry
    xor ecx, ecx
.sf_copy:
    cmp cl, bl
    jge .sf_ra_init
    movzx eax, byte [rsi+rcx]
    mov [frame_param_vars+rcx], al
    inc cl
    jmp .sf_copy
.sf_ra_init:
    ; O18: init register allocator — pin first min(param_cnt, 2) params to r12/r13
    movzx rax, bl            ; param_cnt
    cmp al, 2
    jle .sf_ra_set
    mov al, 2
.sf_ra_set:
    mov byte [regalloc_active], 1
    mov [regalloc_cnt], al
    movzx rax, al            ; how many to copy
    xor ecx, ecx
.sf_ra_copy:
    cmp cl, [regalloc_cnt]
    jge .sf_done
    movzx rdx, byte [frame_param_vars + rcx]
    mov [regalloc_vars + rcx], dl
    inc cl
    jmp .sf_ra_copy
.sf_done:
    pop rcx
    pop rbx
    ret

; ── O1: clear frame state (called at protocol exit) ──────────────────────────
codegen_clear_frame:
    push rbx
    ; O9: patch the sub rsp imm32 in the prologue with the actual frame size.
    ; size = (param_cnt + local_cnt + regalloc_cnt) * 8, rounded to 16, min 16.
    movzx rax, byte [frame_param_cnt]
    movzx rcx, byte [frame_local_cnt]
    add rax, rcx
    movzx rcx, byte [regalloc_cnt]   ; O18: callee-save slots for r12/r13
    add rax, rcx
    shl rax, 3          ; × 8 bytes per slot
    add rax, 15
    and rax, -16        ; round up to multiple of 16
    cmp rax, 16
    jge .cf_patch
    mov rax, 16
.cf_patch:
    mov rcx, [frame_size_patch_pos]
    lea rdx, [out_buffer]
    mov [rdx + rcx], eax    ; patch sub rsp imm32
    ; FLC: patch all add rsp imm32 in leave epilogues with the same frame_size
    movzx rbx, byte [leave_patch_cnt]
    test rbx, rbx
    jz .cf_clear
    lea rdx, [out_buffer]
    xor ecx, ecx
.cf_leave_loop:
    cmp rcx, rbx
    jge .cf_clear
    mov r8, [leave_patch_list + rcx*8]
    mov [rdx + r8], eax
    inc rcx
    jmp .cf_leave_loop
.cf_clear:
    mov byte [frame_active], 0
    mov byte [frame_local_cnt], 0
    mov byte [regalloc_active], 0    ; O18: clear register allocator
    mov byte [regalloc_cnt], 0
    mov byte [leave_patch_cnt], 0    ; FLC: clear leave patch count
    pop rbx
    ret

; ── O5: register a var as a protocol-body local in the stack frame ─────────────
; rdi = var_idx: adds to frame_local_vars if capacity allows disp8 range
; Slot assigned = frame_param_cnt + current frame_local_cnt
; disp8 for slot K = -(K+1)*8; must fit in signed byte (≤ 128 magnitude)
codegen_add_frame_local:
    push rbx
    movzx rbx, byte [frame_local_cnt]
    cmp rbx, 32
    jge .afl_full
    ; verify disp8 range: slot = param_cnt + local_cnt + regalloc_cnt; slot*8 ≤ 127
    movzx rax, byte [frame_param_cnt]
    add rax, rbx        ; total slots so far
    movzx rdx, byte [regalloc_cnt]
    add rax, rdx        ; O18: account for callee-save slots
    shl rax, 3          ; * 8 = rsp-relative displacement
    cmp rax, 128        ; ≥ 128 overflows signed disp8
    jge .afl_full
    mov [frame_local_vars + rbx], dil
    inc byte [frame_local_cnt]
.afl_full:
    pop rbx
    ret

; ── FLC/O1/O5/O9: emit frameless prologue: sub rsp,<placeholder> ─────────────
; rdi = param_count.  No frame pointer — rsp-relative addressing throughout.
; Actual frame size is patched at codegen_clear_frame time (O9 patch-back).
codegen_emit_frame_prologue:
    ; sub rsp, <imm32> placeholder = 48 81 EC 00 00 00 00
    ; Save the imm32 offset so codegen_clear_frame can patch the actual size.
    mov al, 0x48
    call emit_b
    mov al, 0x81
    call emit_b
    mov al, 0xEC
    call emit_b
    ; record patch position = current out_idx (points at the 4-byte immediate)
    mov rax, [out_idx]
    mov [frame_size_patch_pos], rax
    xor eax, eax
    call emit_d        ; placeholder imm32 = 0
    ; O18: save callee-saved regs to rsp-relative slots and load from ABI regs
    ; Frame layout (bottom-up): [rsp+0]=saved r12, [rsp+8]=saved r13 (regalloc_cnt=2)
    ; Param loads: r12←rdi (param0), r13←rsi (param1)
    movzx rcx, byte [regalloc_cnt]
    test rcx, rcx
    jz .fp_done
    ; mov [rsp],r12 = 4C 89 24 24  (ModRM: mod=00 reg=100=r12 rm=100=SIB)
    mov al, 0x4C
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0x24
    call emit_b
    mov al, 0x24
    call emit_b
    ; mov r12,rdi = 49 89 FC
    mov al, 0x49
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xFC
    call emit_b
    cmp rcx, 2
    jl .fp_done
    ; mov [rsp+8],r13 = 4C 89 6C 24 08  (ModRM: mod=01 reg=101=r13 rm=100=SIB)
    mov al, 0x4C
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0x6C
    call emit_b
    mov al, 0x24
    call emit_b
    mov al, 0x08
    call emit_b
    ; mov r13,rsi = 49 89 F5
    mov al, 0x49
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xF5
    call emit_b
.fp_done:
    ret

; ── O18: restore r12/r13 from rsp-relative callee-save slots before epilogue ──
codegen_emit_regalloc_epilogue:
    movzx rcx, byte [regalloc_cnt]
    test rcx, rcx
    jz .re_done
    ; mov r12,[rsp] = 4C 8B 24 24  (ModRM: mod=00 reg=100=r12 rm=100=SIB)
    mov al, 0x4C
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x24
    call emit_b
    mov al, 0x24
    call emit_b
    cmp rcx, 2
    jl .re_done
    ; mov r13,[rsp+8] = 4C 8B 6C 24 08  (ModRM: mod=01 reg=101=r13 rm=100=SIB)
    mov al, 0x4C
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x6C
    call emit_b
    mov al, 0x24
    call emit_b
    mov al, 0x08
    call emit_b
.re_done:
    ret

; ── FLC: emit add rsp,imm32 (frameless epilogue) with patch-back ─────────────
; Records imm32 position in leave_patch_list; patched with frame_size at
; codegen_clear_frame time. Must be followed by codegen_emit_ret.
codegen_emit_leave:
    push rbx
    ; add rsp, imm32 = 48 81 C4 <imm32>
    mov al, 0x48
    call emit_b
    mov al, 0x81
    call emit_b
    mov al, 0xC4
    call emit_b
    ; record imm32 patch position
    movzx rbx, byte [leave_patch_cnt]
    mov rax, [out_idx]
    mov [leave_patch_list + rbx*8], rax
    inc byte [leave_patch_cnt]
    xor eax, eax
    call emit_d        ; placeholder imm32 = 0
    pop rbx
    ret

; ── O4: emit jmp rel32 to a protocol out_idx (like call_prot but jmp) ─────────
; rdi = proto out_idx
codegen_emit_jmp_prot:
    mov al, 0xE9
    call emit_b
    mov rax, rdi
    add rax, LOAD_BASE
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d
    ret

; ── O3: peephole optimiser ─────────────────────────────────────────────────────
; Scans out_buffer[0..out_idx-1] for hot patterns and eliminates them.
; Pattern A: 48 8B 04 25 <a4> 48 89 C7  → 48 8B 3C 25 <a4> 90 90 90
;   (load [abs32] into rax then mov rax,rdi  →  direct load into rdi + 3 NOPs)
; Pattern B: 50 58  (push rax; pop rax)  → 90 90
codegen_peephole:
    lea rsi, [out_buffer]
    mov rcx, [out_idx]
    xor rbx, rbx              ; scan index
.ph_loop:
    cmp rbx, rcx
    jge .ph_done
    ; ── Pattern A (11 bytes) ─────────────────────────────────────────────────
    mov rdx, rcx
    sub rdx, rbx
    cmp rdx, 11
    jl .ph_b
    lea rdi, [rsi+rbx]
    cmp byte [rdi],   0x48
    jne .ph_b
    cmp byte [rdi+1], 0x8B
    jne .ph_b
    cmp byte [rdi+2], 0x04
    jne .ph_b
    cmp byte [rdi+3], 0x25
    jne .ph_b
    ; bytes 4..7 are the address — skip check
    cmp byte [rdi+8],  0x48
    jne .ph_b
    cmp byte [rdi+9],  0x89
    jne .ph_b
    cmp byte [rdi+10], 0xC7
    jne .ph_b
    ; match: change ModRM 04→3C; NOP last 3 bytes
    mov byte [rdi+2],  0x3C
    mov byte [rdi+8],  0x90
    mov byte [rdi+9],  0x90
    mov byte [rdi+10], 0x90
    add rbx, 8
    jmp .ph_loop
.ph_b:
    ; ── Pattern B (2 bytes) ──────────────────────────────────────────────────
    cmp rdx, 2
    jl .ph_d
    lea rdi, [rsi+rbx]
    cmp byte [rdi],   0x50
    jne .ph_d
    cmp byte [rdi+1], 0x58
    jne .ph_d
    mov byte [rdi],   0x90
    mov byte [rdi+1], 0x90
    add rbx, 2
    jmp .ph_loop
.ph_d:
    ; ── Pattern D (16 bytes): setcc al + movzx rax,al + test rax,rax + jz → jcc ─
    ; Actual encoding: 0F 9X C0  48 0F B6 C0  48 85 C0  0F 84 <rel32>  (16 bytes)
    ; (movzx rax,al has REX.W prefix 48, making it 4 bytes, not 3)
    ; Folds setle/l/ge/g/e/ne + movzx + test + jz into a single 6-byte jcc,
    ; saving 3 instructions per comparison in if/while conditions.
    cmp rdx, 16
    jl .ph_next
    lea rdi, [rsi+rbx]
    cmp byte [rdi],   0x0F
    jne .ph_next
    ; [1] = setcc byte: high nibble must be 9
    ; NOTE: use edx (not ecx) here — ecx holds out_idx and must not be clobbered
    movzx eax, byte [rdi+1]
    mov edx, eax
    and edx, 0xF0
    cmp edx, 0x90
    jne .ph_next
    ; low nibble must be in {4,5,C,D,E,F}
    mov edx, eax
    and edx, 0x0F
    cmp edx, 0x04
    jl .ph_next
    cmp edx, 0x05
    jle .ph_d_ok    ; 4 or 5 → sete/setne
    cmp edx, 0x0C
    jl .ph_next     ; 6–B: not a recognized setcc
.ph_d_ok:
    ; verify the remaining 13 bytes:
    ; [2]=C0  [3]=48(REX.W)  [4]=0F  [5]=B6  [6]=C0(movzx rax,al)
    ; [7]=48  [8]=85  [9]=C0(test rax,rax)
    ; [10]=0F [11]=84 [12..15]=rel32(jz)
    cmp byte [rdi+2],  0xC0
    jne .ph_next
    cmp byte [rdi+3],  0x48
    jne .ph_next
    cmp byte [rdi+4],  0x0F
    jne .ph_next
    cmp byte [rdi+5],  0xB6
    jne .ph_next
    cmp byte [rdi+6],  0xC0
    jne .ph_next
    cmp byte [rdi+7],  0x48
    jne .ph_next
    cmp byte [rdi+8],  0x85
    jne .ph_next
    cmp byte [rdi+9],  0xC0
    jne .ph_next
    cmp byte [rdi+10], 0x0F
    jne .ph_next
    cmp byte [rdi+11], 0x84
    jne .ph_next
    ; Match! Transform to:  0F <NOT-jcc> <rel32+10>  90*10
    ; [1]: NOT-condition jcc byte = (setcc_byte XOR 1) + 0xF0  (≡ −0x10 mod 256)
    movzx eax, byte [rdi+1]
    xor al, 0x01
    add al, 0xF0
    mov byte [rdi+1], al
    ; [2..5]: new rel32 = old_rel32 + 10  (jcc is 10 bytes earlier than old jz)
    mov eax, dword [rdi+12]
    add eax, 10
    mov dword [rdi+2], eax
    ; [6..15]: 7-byte NOP + 3-byte NOP (2 µops decode vs 10 for single-byte NOPs)
    mov byte [rdi+6],  0x0F   ; 7-byte NOP: NOP DWORD PTR [rax+0x00000000]
    mov byte [rdi+7],  0x1F
    mov byte [rdi+8],  0x80
    mov byte [rdi+9],  0x00
    mov byte [rdi+10], 0x00
    mov byte [rdi+11], 0x00
    mov byte [rdi+12], 0x00
    mov byte [rdi+13], 0x0F   ; 3-byte NOP: NOP DWORD PTR [rax]
    mov byte [rdi+14], 0x1F
    mov byte [rdi+15], 0x00
    add rbx, 6
    jmp .ph_loop
; ── Pattern E (14 bytes) ─────────────────────────────────────────────────────
; Fold:  mov r10,rax  +  mov rax,[abs32]  +  mov rbx,r10
;        49 89 C2       48 8B 04 25 <a4>    4C 89 D3          (14 bytes)
;   →    mov rbx,rax  +  mov rax,[abs32]  +  NOP×3
;        48 89 C3       48 8B 04 25 <a4>    90 90 90
; Eliminates the r10 save/restore round-trip when a sub-expression load follows.
.ph_next:
    cmp rdx, 14
    jl .ph_e_miss
    lea rdi, [rsi+rbx]
    cmp byte [rdi+0],  0x49
    jne .ph_e_miss
    cmp byte [rdi+1],  0x89
    jne .ph_e_miss
    cmp byte [rdi+2],  0xC2
    jne .ph_e_miss
    cmp byte [rdi+3],  0x48
    jne .ph_e_miss
    cmp byte [rdi+4],  0x8B
    jne .ph_e_miss
    cmp byte [rdi+5],  0x04
    jne .ph_e_miss
    cmp byte [rdi+6],  0x25
    jne .ph_e_miss
    ; bytes 7..10: abs32 address — skip
    cmp byte [rdi+11], 0x4C
    jne .ph_e_miss
    cmp byte [rdi+12], 0x89
    jne .ph_e_miss
    cmp byte [rdi+13], 0xD3
    jne .ph_e_miss
    ; match: rewrite in-place
    mov byte [rdi+0],  0x48  ; REX.W (was REX.WB for r10)
    ; [1] stays 0x89
    mov byte [rdi+2],  0xC3  ; ModRM: rbx←rax (was C2 = r10←rax)
    ; [3..10]: mov rax,[abs32] unchanged
    mov byte [rdi+11], 0x90  ; NOP
    mov byte [rdi+12], 0x90  ; NOP
    mov byte [rdi+13], 0x90  ; NOP
    add rbx, 11              ; advance past mov rbx,rax (3) + mov rax,[abs32] (8)
    jmp .ph_loop
.ph_e_miss:
; ── Pattern F (6 bytes) ──────────────────────────────────────────────────────
; Fold adjacent:  mov r10,rax  +  mov rbx,r10  →  mov rbx,rax  +  NOP×3
;                 49 89 C2       4C 89 D3          48 89 C3       90 90 90
; Catches cases where both operands of a binary op were already in registers.
    cmp rdx, 6
    jl .ph_f_miss
    lea rdi, [rsi+rbx]
    cmp byte [rdi+0],  0x49
    jne .ph_f_miss
    cmp byte [rdi+1],  0x89
    jne .ph_f_miss
    cmp byte [rdi+2],  0xC2
    jne .ph_f_miss
    cmp byte [rdi+3],  0x4C
    jne .ph_f_miss
    cmp byte [rdi+4],  0x89
    jne .ph_f_miss
    cmp byte [rdi+5],  0xD3
    jne .ph_f_miss
    ; match: fold to mov rbx,rax + 3 NOPs
    mov byte [rdi+0],  0x48
    ; [1] stays 0x89
    mov byte [rdi+2],  0xC3
    mov byte [rdi+3],  0x90
    mov byte [rdi+4],  0x90
    mov byte [rdi+5],  0x90
    add rbx, 3              ; advance past mov rbx,rax (3 bytes)
    jmp .ph_loop
.ph_f_miss:
; ── Pattern G (18 bytes) ─────────────────────────────────────────────────────
; Fold: mov rax,r14 + mov r10,rax + mov rax,r15 + mov rbx,r10 + add rax,rbx + mov r14,rax
;       4C 89 F0    49 89 C2       4C 89 F8       4C 89 D3       48 01 D8      49 89 C6
;   →   add r14,r15  (4D 01 FE)  +  7-byte NOP  +  8-byte NOP  (18 bytes total)
; Fires when O13 (r14 accum) + O2 (r15 counter) both active and loop body is accum += counter.
    cmp rdx, 18
    jl .ph_g_miss
    lea rdi, [rsi+rbx]
    cmp byte [rdi+0],  0x4C
    jne .ph_g_miss
    cmp byte [rdi+1],  0x89
    jne .ph_g_miss
    cmp byte [rdi+2],  0xF0
    jne .ph_g_miss
    cmp byte [rdi+3],  0x49
    jne .ph_g_miss
    cmp byte [rdi+4],  0x89
    jne .ph_g_miss
    cmp byte [rdi+5],  0xC2
    jne .ph_g_miss
    cmp byte [rdi+6],  0x4C
    jne .ph_g_miss
    cmp byte [rdi+7],  0x89
    jne .ph_g_miss
    cmp byte [rdi+8],  0xF8
    jne .ph_g_miss
    cmp byte [rdi+9],  0x4C
    jne .ph_g_miss
    cmp byte [rdi+10], 0x89
    jne .ph_g_miss
    cmp byte [rdi+11], 0xD3
    jne .ph_g_miss
    cmp byte [rdi+12], 0x48
    jne .ph_g_miss
    cmp byte [rdi+13], 0x01
    jne .ph_g_miss
    cmp byte [rdi+14], 0xD8
    jne .ph_g_miss
    cmp byte [rdi+15], 0x49
    jne .ph_g_miss
    cmp byte [rdi+16], 0x89
    jne .ph_g_miss
    cmp byte [rdi+17], 0xC6
    jne .ph_g_miss
    ; Match: fold to add r14,r15 + 7-byte NOP + 8-byte NOP
    mov byte [rdi+0],  0x4D     ; add r14,r15 = 4D 01 FE
    mov byte [rdi+1],  0x01
    mov byte [rdi+2],  0xFE
    mov byte [rdi+3],  0x0F     ; 7-byte NOP: 0F 1F 80 00 00 00 00
    mov byte [rdi+4],  0x1F
    mov byte [rdi+5],  0x80
    mov byte [rdi+6],  0x00
    mov byte [rdi+7],  0x00
    mov byte [rdi+8],  0x00
    mov byte [rdi+9],  0x00
    mov byte [rdi+10], 0x0F     ; 8-byte NOP: 0F 1F 84 00 00 00 00 00
    mov byte [rdi+11], 0x1F
    mov byte [rdi+12], 0x84
    mov byte [rdi+13], 0x00
    mov byte [rdi+14], 0x00
    mov byte [rdi+15], 0x00
    mov byte [rdi+16], 0x00
    mov byte [rdi+17], 0x00
    add rbx, 3                  ; advance past add r14,r15 (3 bytes)
    jmp .ph_loop
.ph_g_miss:
; ── Pattern H (9 bytes) ──────────────────────────────────────────────────────
; Fold: lea rax,[r12+disp8] + NOP + mov rdi,rax  →  lea rdi,[r12+disp8] + 4-byte NOP
;       49 8D 44 24 xx        90    48 89 C7          49 8D 7C 24 xx       0F 1F 40 00
; Fires when O19 sub look-back (lea rax) + O7 arg-pop (NOP+mov rdi,rax) combine.
    cmp rdx, 9
    jl .ph_k2
    lea rdi, [rsi+rbx]
    cmp byte [rdi+0], 0x49
    jne .ph_k2
    cmp byte [rdi+1], 0x8D
    jne .ph_k2
    cmp byte [rdi+2], 0x44
    jne .ph_k2
    cmp byte [rdi+3], 0x24
    jne .ph_k2
    ; [rdi+4] = disp8, skip
    cmp byte [rdi+5], 0x90
    jne .ph_k2
    cmp byte [rdi+6], 0x48
    jne .ph_k2
    cmp byte [rdi+7], 0x89
    jne .ph_k2
    cmp byte [rdi+8], 0xC7
    jne .ph_k2
    ; Match: change ModRM 0x44→0x7C (rax→rdi in lea), replace NOP+mov rdi,rax with 4-byte NOP
    mov byte [rdi+2], 0x7C
    mov byte [rdi+5], 0x0F   ; 4-byte NOP: NOP DWORD PTR [rax+0x0]
    mov byte [rdi+6], 0x1F
    mov byte [rdi+7], 0x40
    mov byte [rdi+8], 0x00
    add rbx, 5
    jmp .ph_loop
.ph_k2:
; ── Pattern K2 (21 bytes) ────────────────────────────────────────────────────
; Fold: mov[rsp+D1],rax + mov rax,[rsp+D2] + mov rbx,rax + mov rax,[rsp+D1] + add rax,rbx
;       48 89 44 24 D1    48 8B 44 24 D2    48 89 C3        48 8B 44 24 D1     48 01 D8
;   →   mov rbx,rax + mov rax,[rsp+D2] + add rax,rbx + 10-byte NOP (D1≠D2)
;       48 89 C3         48 8B 44 24 D2   48 01 D8          66 2E 0F 1F 84 00 00 00 00 00
; Fires after fib(n-2) result is stored then redundantly reloaded to compute a+b.
; rax still holds b (store does not modify rax), so mov rbx,rax captures b correctly.
    cmp rdx, 21
    jl .ph_miss
    lea rdi, [rsi+rbx]
    cmp byte [rdi+0],  0x48
    jne .ph_miss
    cmp byte [rdi+1],  0x89
    jne .ph_miss
    cmp byte [rdi+2],  0x44
    jne .ph_miss
    cmp byte [rdi+3],  0x24
    jne .ph_miss
    ; [rdi+4] = D1 (store disp8)
    cmp byte [rdi+5],  0x48
    jne .ph_miss
    cmp byte [rdi+6],  0x8B
    jne .ph_miss
    cmp byte [rdi+7],  0x44
    jne .ph_miss
    cmp byte [rdi+8],  0x24
    jne .ph_miss
    ; [rdi+9] = D2 (load-a disp8, must differ from D1)
    movzx eax, byte [rdi+4]   ; D1
    movzx edx, byte [rdi+9]   ; D2 (rdx free now: size check passed)
    cmp al, dl
    je .ph_miss               ; D1 == D2? Not the store-then-reload pattern
    cmp byte [rdi+10], 0x48
    jne .ph_miss
    cmp byte [rdi+11], 0x89
    jne .ph_miss
    cmp byte [rdi+12], 0xC3
    jne .ph_miss
    cmp byte [rdi+13], 0x48
    jne .ph_miss
    cmp byte [rdi+14], 0x8B
    jne .ph_miss
    cmp byte [rdi+15], 0x44
    jne .ph_miss
    cmp byte [rdi+16], 0x24
    jne .ph_miss
    cmp byte [rdi+17], al     ; [+17] must equal D1 (same slot reloaded)
    jne .ph_miss
    cmp byte [rdi+18], 0x48
    jne .ph_miss
    cmp byte [rdi+19], 0x01
    jne .ph_miss
    cmp byte [rdi+20], 0xD8
    jne .ph_miss
    ; Match! Rewrite 21 bytes in-place:
    ;   [0..2]   → mov rbx,rax  = 48 89 C3  (b→rbx; rax=b before store, store leaves rax intact)
    ;   [3..7]   → mov rax,[rsp+D2]  (load a)
    ;   [8..10]  → add rax,rbx  (a+b)
    ;   [11..20] → 10-byte NOP
    ; [0] = 0x48 (unchanged)
    ; [1] = 0x89 (unchanged)
    mov byte [rdi+2],  0xC3   ; complete mov rbx,rax
    mov byte [rdi+3],  0x48   ; mov rax,[rsp+D2]
    mov byte [rdi+4],  0x8B
    mov byte [rdi+5],  0x44
    mov byte [rdi+6],  0x24
    mov byte [rdi+7],  dl     ; D2
    mov byte [rdi+8],  0x48   ; add rax,rbx
    mov byte [rdi+9],  0x01
    mov byte [rdi+10], 0xD8
    mov byte [rdi+11], 0x66   ; 10-byte NOP: 66 2E 0F 1F 84 00 00 00 00 00
    mov byte [rdi+12], 0x2E
    mov byte [rdi+13], 0x0F
    mov byte [rdi+14], 0x1F
    mov byte [rdi+15], 0x84
    mov byte [rdi+16], 0x00
    mov byte [rdi+17], 0x00
    mov byte [rdi+18], 0x00
    mov byte [rdi+19], 0x00
    mov byte [rdi+20], 0x00
    add rbx, 11               ; advance past mov rbx,rax(3)+mov rax,[rsp+D2](5)+add(3)
    jmp .ph_loop
.ph_miss:
    inc rbx
    jmp .ph_loop
.ph_done:
    ret
