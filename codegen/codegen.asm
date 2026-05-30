default rel
%include "include/rex_defs.inc"
global codegen_write_headers, codegen_init, codegen_finish, out_buffer, out_idx
global codegen_output_const, codegen_output_typed, codegen_patch_jump, codegen_save_chain_base, codegen_emit_jmp_end, codegen_patch_chain_end
global codegen_begin_protos, codegen_end_protos, codegen_emit_for_start, codegen_emit_for_end, codegen_emit_while_start, codegen_emit_while_end
global codegen_emit_break, codegen_patch_breaks, codegen_emit_ret, codegen_emit_mov_eax_imm32, codegen_emit_call_prot, codegen_emit_assign_var, codegen_emit_cmp_var_jne, codegen_emit_unknown_bool
global codegen_emit_mm_switch, codegen_emit_loop_base
extern elf_header, program_header, rt_pri_blob, rt_prs_blob, rt_prb_blob, rt_prf_blob, rt_prc_blob, rt_sip_blob, rt_alc_blob, rt_prq_blob
section .bss
out_buffer: resb 131072
    out_idx: resq 1
    jump_patch_stack: resq 32
    jump_patch_depth: resq 1
    end_jump_stack: resq 32
    end_jump_depth: resq 1
    chain_base_stack: resq 32
    chain_base_depth: resq 1
break_jump_stack: resq 32
    break_jump_depth: resq 1
    break_base_stack: resq 32
    break_base_depth: resq 1
    prot_jmp_idx: resq 1
    prot_jmp_live: resb 1
section .text
emit_b: push rbx
    push rcx
    mov rcx, [out_idx]
    lea rbx, [out_buffer]
    mov [rbx+rcx], al
    inc qword [out_idx]
    pop rcx
    pop rbx
    ret
emit_d: push rbx
    push rcx
    mov rcx, [out_idx]
    lea rbx, [out_buffer]
    mov [rbx+rcx], eax
    add qword [out_idx], 4
    pop rcx
    pop rbx
    ret
emit_q: push rbx
    push rcx
    mov rcx, [out_idx]
    lea rbx, [out_buffer]
    mov [rbx+rcx], rax
    add qword [out_idx], 8
    pop rcx
    pop rbx
    ret
emit_blob: push rdi
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
get_var_va: mov rax, rdi
    shl rax, 6
    add rax, VAR_STORAGE_BASE
    ret
codegen_write_headers: mov qword [out_idx], 0
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
codegen_init: mov al, 0xE9
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
codegen_output_const: mov al, 0xBF
    call emit_b
    mov eax, edi
    call emit_d
    mov al, 0xE8
    call emit_b
    mov rax, LOAD_BASE + RT_PRI_OFFSET
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d
    ret
codegen_output_typed: push rsi
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
codegen_emit_assign_var: push rdi
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
codegen_emit_unknown_bool: push rdi
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
codegen_emit_cmp_var_jne: push rsi
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
codegen_patch_jump: dec qword [jump_patch_depth]
    mov rbx, [jump_patch_depth]
    lea rcx, [jump_patch_stack]
    mov rdx, [rcx+rbx*8]
    mov rax, [out_idx]
    sub rax, rdx
    sub rax, 4
    lea rcx, [out_buffer]
    mov [rcx+rdx], eax
    ret
codegen_save_chain_base: mov rax, [end_jump_depth]
    mov rbx, [chain_base_depth]
    lea rcx, [chain_base_stack]
    mov [rcx+rbx*8], rax
    inc qword [chain_base_depth]
    ret
codegen_emit_jmp_end: mov al, 0xE9
    call emit_b
    mov rax, [out_idx]
    mov rbx, [end_jump_depth]
    lea rcx, [end_jump_stack]
    mov [rcx+rbx*8], rax
    inc qword [end_jump_depth]
    xor eax, eax
    call emit_d
    ret
codegen_patch_chain_end: dec qword [chain_base_depth]
    mov rbx, [chain_base_depth]
    lea rcx, [chain_base_stack]
    mov rsi, [rcx+rbx*8]
.l: cmp rsi, [end_jump_depth]
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
.done: mov [end_jump_depth], rsi
    ret
codegen_begin_protos: cmp byte [prot_jmp_live], 0
    jne .done
    mov al, 0xE9
    call emit_b
    mov rax, [out_idx]
    mov [prot_jmp_idx], rax
    xor eax, eax
    call emit_d
    mov byte [prot_jmp_live], 1
.done: ret
codegen_end_protos: cmp byte [prot_jmp_live], 0
    je .done
    mov rdx, [prot_jmp_idx]
    mov rax, [out_idx]
    sub rax, rdx
    sub rax, 4
    lea rcx, [out_buffer]
    mov [rcx+rdx], eax
    mov byte [prot_jmp_live], 0
.done: ret
codegen_emit_for_start: mov rax, [break_jump_depth]
    mov rbx, [break_base_depth]
    lea rcx, [break_base_stack]
    mov [rcx+rbx*8], rax
    inc qword [break_base_depth]
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rdx
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
    mov rax, rbx
    pop r13
    pop r12
    pop rbx
    ret
codegen_emit_for_end: push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
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
    pop r13
    pop r12
    pop rbx
    ret
codegen_emit_while_end: mov al, 0xE9
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
    ret
codegen_emit_break: mov al, 0xE9
    call emit_b
    mov rax, [out_idx]
    mov rbx, [break_jump_depth]
    lea rcx, [break_jump_stack]
    mov [rcx+rbx*8], rax
    inc qword [break_jump_depth]
    xor eax, eax
    call emit_d
    ret
codegen_patch_breaks: dec qword [break_base_depth]
    mov rbx, [break_base_depth]
    lea rcx, [break_base_stack]
    mov rsi, [rcx+rbx*8]
.l: cmp rsi, [break_jump_depth]
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
.done: mov [break_jump_depth], rsi
    ret
codegen_emit_ret: mov al, 0xC3
    call emit_b
    ret
codegen_emit_mov_eax_imm32: mov al, 0xB8
    call emit_b
    mov eax, edi
    call emit_d
    ret
codegen_emit_call_prot: mov al, 0xE8
    call emit_b
    mov rax, rdi
    add rax, LOAD_BASE
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d
    ret
codegen_emit_mm_switch: mov al, 0x48
    call emit_b
    mov al, 0xC7
    call emit_b
    mov al, 0x05
    call emit_b
    mov rax, LOAD_BASE + RT_ALC_OFFSET + 4096 - 8
    mov rdx, [out_idx]
    add rdx, 4
    sub rax, rdx
    call emit_d
    mov eax, edi
    call emit_d
    ret
codegen_emit_loop_base: mov rax, [break_jump_depth]
    mov rbx, [break_base_depth]
    lea rcx, [break_base_stack]
    mov [rcx+rbx*8], rax
    inc qword [break_base_depth]
    ret
codegen_finish: mov al, 0x48
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
    mov rax, [out_idx]
    lea rcx, [out_buffer]
    mov [rcx + 64 + 32], rax
    mov qword [rcx + 64 + 40], 0x80000
    ret
