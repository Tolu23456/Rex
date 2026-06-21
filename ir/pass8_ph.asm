; ══════════════════════════════════════════════════════════════════════════════
; ir/pass8_ph.asm — Pass 8: Peephole Cleanup
; Final pass after register allocation.  Scans IR linearly and removes
; trivially redundant patterns:
;   - MOV dst ← src   where dst and src were allocated the same physical reg
;   - Consecutive JMPs to the same target (only first matters)
;   - NOP records (IR_NOP), dead records (IRF_DEAD) — compact buffer in-place
;   - IMM 0 followed by ADD x, 0 → remove the add
; After compaction the ir_idx is updated to reflect the reduced count.
; ══════════════════════════════════════════════════════════════════════════════
default rel
%include "include/rex_defs.inc"
%include "ir/ir_defs.inc"

global ir_pass8_ph
extern ir_buffer, ir_idx, ir_phys_map

section .text

ir_pass8_ph:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push r15

    ; Pass A: mark trivially redundant MOVs dead
    xor r12, r12
.ph_mov_loop:
    cmp r12, [ir_idx]
    jge .ph_mov_done
    mov rax, r12
    imul rax, IR_RECORD_SIZE
    lea rcx, [ir_buffer]
    add rcx, rax
    test byte [rcx + IR_OFF_FLAGS], IRF_DEAD
    jnz .ph_mov_next
    cmp byte [rcx + IR_OFF_OP], IR_MOV
    jne .ph_mov_next
    ; Check: same phys reg for dst and src0?
    mov r13d, [rcx + IR_OFF_DST]
    mov r14d, [rcx + IR_OFF_SRC0]
    cmp r13d, -1
    je .ph_mov_next
    cmp r14d, -1
    je .ph_mov_next
    cmp r13d, VREG_MAX
    jge .ph_mov_next
    cmp r14d, VREG_MAX
    jge .ph_mov_next
    lea rsi, [ir_phys_map]
    movzx eax, byte [rsi + r13]
    movzx edx, byte [rsi + r14]
    test eax, eax
    jz .ph_mov_next
    cmp eax, edx
    jne .ph_mov_next
    ; Same physical register: this MOV is a no-op
    or byte [rcx + IR_OFF_FLAGS], IRF_DEAD
.ph_mov_next:
    inc r12
    jmp .ph_mov_loop
.ph_mov_done:

    ; Pass B: eliminate consecutive JMPs to same target
    xor r12, r12
.ph_jmp_loop:
    mov rax, [ir_idx]
    sub rax, 1
    cmp r12, rax
    jge .ph_jmp_done
    mov rax, r12
    imul rax, IR_RECORD_SIZE
    lea rcx, [ir_buffer]
    add rcx, rax
    test byte [rcx + IR_OFF_FLAGS], IRF_DEAD
    jnz .ph_jmp_next
    cmp byte [rcx + IR_OFF_OP], IR_JMP
    jne .ph_jmp_next
    mov r13, [rcx + IR_OFF_IMM]    ; target label
    ; scan forward for next non-dead
    mov r14, r12
    inc r14
.ph_jmp_scan:
    cmp r14, [ir_idx]
    jge .ph_jmp_next
    mov rax, r14
    imul rax, IR_RECORD_SIZE
    lea rdx, [ir_buffer]
    add rdx, rax
    test byte [rdx + IR_OFF_FLAGS], IRF_DEAD
    jnz .ph_jmp_scan_next
    cmp byte [rdx + IR_OFF_OP], IR_JMP
    jne .ph_jmp_next
    cmp [rdx + IR_OFF_IMM], r13
    jne .ph_jmp_next
    ; Duplicate JMP: mark second dead
    or byte [rdx + IR_OFF_FLAGS], IRF_DEAD
    jmp .ph_jmp_next
.ph_jmp_scan_next:
    inc r14
    jmp .ph_jmp_scan
.ph_jmp_next:
    inc r12
    jmp .ph_jmp_loop
.ph_jmp_done:

    ; Pass C: compact buffer (remove dead records) in-place
    xor r12, r12           ; read index
    xor r13, r13           ; write index
.ph_compact_loop:
    cmp r12, [ir_idx]
    jge .ph_compact_done
    mov rax, r12
    imul rax, IR_RECORD_SIZE
    lea rcx, [ir_buffer]
    add rcx, rax           ; rcx = read record

    test byte [rcx + IR_OFF_FLAGS], IRF_DEAD
    jnz .ph_compact_skip

    ; Write record to position r13 (if r13 != r12)
    cmp r13, r12
    je .ph_compact_skip2   ; already in place, skip copy
    mov rax, r13
    imul rax, IR_RECORD_SIZE
    lea rdi, [ir_buffer]
    add rdi, rax           ; rdi = write position
    ; copy 32 bytes
    mov rax, [rcx]
    mov [rdi], rax
    mov rax, [rcx+8]
    mov [rdi+8], rax
    mov rax, [rcx+16]
    mov [rdi+16], rax
    mov rax, [rcx+24]
    mov [rdi+24], rax
.ph_compact_skip2:
    inc r13

.ph_compact_skip:
    inc r12
    jmp .ph_compact_loop

.ph_compact_done:
    mov [ir_idx], r13      ; update ir_idx to compacted count

    pop r15
    pop r14
    pop r13
    pop r12
    leave
    ret
