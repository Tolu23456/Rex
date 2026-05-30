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
global codegen_emit_assign_var, codegen_emit_cmp_var_jne, codegen_emit_unknown_bool
global codegen_emit_mm_switch
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
global codegen_emit_str_rax
global codegen_emit_seq_alloc, codegen_emit_seq_push, codegen_emit_seq_pop_rax
global codegen_emit_seq_len_rax
global codegen_emit_mov_rdi_rax, codegen_emit_call_rt_err
global codegen_emit_for_start_dyn, codegen_emit_arg_pops
global codegen_push_cont, codegen_pop_cont, codegen_emit_skip
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
section .text

; ── internal emit helpers ─────────────────────────────────────────────────────
emit_b:
    push rbx
    push rcx
    mov rcx, [out_idx]
    lea rbx, [out_buffer]
    mov [rbx+rcx], al
    inc qword [out_idx]
    pop rcx
    pop rbx
    ret
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
    mov qword [rcx+64+40], 0x80000
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
    ; rdi=var_idx rsi=type: emit mov rdi,[var_addr]; call rt_pXX
    push rsi
    push rdi
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

; ── for loop (static bounds) ──────────────────────────────────────────────────
codegen_emit_for_start:
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
    ; init loop var: emit mov rax,imm64; mov [var_addr],rax
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
    mov rbx, [out_idx]
    ; condition: emit mov rax,[var_addr]; cmp rax,end; jge .exit
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
    mov al, 0x3D
    call emit_b
    mov rax, r13
    call emit_d
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
    mov r12, rdi
    mov r13, rsi
    ; emit: mov rax,[loop_var]; inc rax; mov [loop_var],rax
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    mov rdi, r13
    call get_var_va
    call emit_d
    mov al, 0x48
    call emit_b
    mov al, 0xFF
    call emit_b
    mov al, 0xC0
    call emit_b
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
    mov rax, [break_jump_depth]
    mov r14, [break_base_depth]
    lea rcx, [break_base_stack]
    mov [rcx+r14*8], rax
    inc qword [break_base_depth]
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
    mov al, 0xE9
    call emit_b
    mov rax, [out_idx]
    mov rbx, [break_jump_depth]
    lea rcx, [break_jump_stack]
    mov [rcx+rbx*8], rax
    inc qword [break_jump_depth]
    xor eax, eax
    call emit_d
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
    ; emit jmp to cont_base_stack top (loop continue target)
    mov rax, [cont_base_depth]
    test rax, rax
    jz .done
    dec rax
    lea rcx, [cont_base_stack]
    mov rdi, [rcx+rax*8]
    mov al, 0xE9
    call emit_b
    mov rax, rdi
    add rax, LOAD_BASE
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d
.done:
    ret

; ── protocol helpers ──────────────────────────────────────────────────────────
codegen_emit_ret:
    mov al, 0xC3
    call emit_b
    ret

codegen_emit_mov_eax_imm32:
    ; rdi=imm: emit mov eax,imm32  (zero-extends to rax; result in rax)
    mov al, 0xB8
    call emit_b
    mov eax, edi
    call emit_d
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
    ; rdi=count: emit pop instructions (pop rdi, rsi, rdx, rcx)
    push rbx
    push rcx
    mov rbx, rdi
    mov rcx, rbx
    cmp rcx, 4
    jle .ok
    mov rcx, 4
.ok:
    test rcx, rcx
    jz .done
    dec rcx
    lea rax, [rel .pop_bytes]
    movzx eax, byte [rax+rcx]
    call emit_b
    jmp .ok
.done:
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

; ── expression emit helpers ───────────────────────────────────────────────────
codegen_emit_push_rax:
    mov al, 0x50
    call emit_b
    ret

codegen_emit_pop_rbx:
    mov al, 0x5B
    call emit_b
    ret

codegen_emit_mov_rax_var:
    ; rdi=var_idx: emit mov rax,[var_addr]
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
    ; rdi=var_idx: emit mov [var_addr],rax
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
    ; add rax,rbx
    mov al, 0x48
    call emit_b
    mov al, 0x01
    call emit_b
    mov al, 0xD8
    call emit_b
    ret

codegen_emit_sub_rax_rbx:
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
    push rdi
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
