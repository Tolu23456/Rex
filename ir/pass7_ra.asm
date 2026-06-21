; ══════════════════════════════════════════════════════════════════════════════
; ir/pass7_ra.asm — Pass 7: Linear Scan Register Allocation
; Classic Poletto–Sarkar linear scan over a single flat IR buffer.
; Phase A: compute live ranges [lr_start, lr_end] per vreg by one linear scan.
; Phase B: linear scan assigns physical registers, spills to stack when needed.
; Writes ir_phys_map[vreg] = PHYS_* and ir_spill_slot[vreg] for spills.
; ir_frame_sz holds the total bytes needed for spill slots.
; ══════════════════════════════════════════════════════════════════════════════
default rel
%include "include/rex_defs.inc"
%include "ir/ir_defs.inc"

global ir_pass7_ra
extern ir_buffer, ir_idx
extern ir_lr_start, ir_lr_end, ir_phys_map, ir_spill_slot, ir_frame_sz

; Allocatable caller-saved regs (don't use rsp/rbp; avoid r10/r11 scratch):
; We use: rcx(2) rdx(3) rsi(4) rdi(5) r8(6) r9(7) rbx(10) r12(11) r13(12) r14(13) r15(14)
RA_REG_COUNT    equ 11

section .bss
ra_free_regs:   resb RA_REG_COUNT   ; ring: 0=free 1=occupied
ra_reg_vreg:    resw RA_REG_COUNT   ; which vreg holds each phys reg (-1=none)
ra_active_cnt:  resd 1
ra_spill_top:   resd 1

section .data
ra_regs:
    db PHYS_RCX, PHYS_RDX, PHYS_RSI, PHYS_RDI
    db PHYS_R8,  PHYS_R9,  PHYS_RBX, PHYS_R12
    db PHYS_R13, PHYS_R14, PHYS_R15

section .text

; Allocate a physical register; returns PHYS_* in al, or PHYS_SPILL if none free.
ra_alloc_phys:
    xor ecx, ecx
.rap_loop:
    cmp ecx, RA_REG_COUNT
    jge .rap_spill
    lea rsi, [ra_free_regs]
    cmp byte [rsi + rcx], 0
    jne .rap_try_next
    lea rsi, [ra_regs]
    movzx eax, byte [rsi + rcx]
    lea rsi, [ra_free_regs]
    mov byte [rsi + rcx], 1
    ret
.rap_try_next:
    inc ecx
    jmp .rap_loop
.rap_spill:
    mov al, PHYS_SPILL
    ret

; Free physical register PHYS_* in dil
ra_free_phys:
    xor ecx, ecx
.rfp_loop:
    cmp ecx, RA_REG_COUNT
    jge .rfp_done
    lea rsi, [ra_regs]
    cmp byte [rsi + rcx], dil
    jne .rfp_next
    lea rsi, [ra_free_regs]
    mov byte [rsi + rcx], 0
    ret
.rfp_next:
    inc ecx
    jmp .rfp_loop
.rfp_done:
    ret

ir_pass7_ra:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push r15

    ; Init
    lea rdi, [ra_free_regs]
    xor eax, eax
    mov ecx, RA_REG_COUNT
    rep stosb
    mov dword [ra_active_cnt], 0
    mov dword [ra_spill_top], 0
    mov dword [ir_frame_sz], 0

    ; Phase A: compute live ranges
    lea rdi, [ir_lr_start]
    mov eax, -1
    mov ecx, VREG_MAX
    rep stosd
    lea rdi, [ir_lr_end]
    mov eax, -1
    mov ecx, VREG_MAX
    rep stosd

    xor r12, r12
.ra_lr_loop:
    cmp r12, [ir_idx]
    jge .ra_lr_done
    mov rax, r12
    imul rax, IR_RECORD_SIZE
    lea rcx, [ir_buffer]
    add rcx, rax
    test byte [rcx + IR_OFF_FLAGS], IRF_DEAD
    jnz .ra_lr_next
    ; dst vreg
    mov r13d, [rcx + IR_OFF_DST]
    cmp r13d, -1
    je .ra_lr_s0
    cmp r13d, VREG_MAX
    jge .ra_lr_s0
    lea rsi, [ir_lr_start]
    cmp dword [rsi + r13*4], -1
    jne .ra_lr_s0
    mov [rsi + r13*4], r12d       ; first def = live range start
    lea rsi, [ir_lr_end]
    mov [rsi + r13*4], r12d       ; initially end = start
.ra_lr_s0:
    ; src0 use
    mov r13d, [rcx + IR_OFF_SRC0]
    cmp r13d, -1
    je .ra_lr_s1
    cmp r13d, VREG_MAX
    jge .ra_lr_s1
    lea rsi, [ir_lr_end]
    mov [rsi + r13*4], r12d       ; extend live range to this use
.ra_lr_s1:
    ; src1 use
    mov r13d, [rcx + IR_OFF_SRC1]
    cmp r13d, -1
    je .ra_lr_next
    cmp r13d, VREG_MAX
    jge .ra_lr_next
    lea rsi, [ir_lr_end]
    mov [rsi + r13*4], r12d
.ra_lr_next:
    inc r12
    jmp .ra_lr_loop

.ra_lr_done:
    ; Phase B: linear scan assign
    lea rdi, [ir_phys_map]
    xor eax, eax
    mov ecx, VREG_MAX
    rep stosb

    xor r12, r12           ; r12 = current position
.ra_scan_loop:
    cmp r12, [ir_idx]
    jge .ra_done
    mov rax, r12
    imul rax, IR_RECORD_SIZE
    lea rcx, [ir_buffer]
    add rcx, rax

    test byte [rcx + IR_OFF_FLAGS], IRF_DEAD
    jnz .ra_scan_next

    ; Expire old intervals (vregs whose end < r12)
    xor r13, r13
.ra_expire_loop:
    cmp r13, VREG_MAX
    jge .ra_expire_done
    lea rsi, [ir_lr_start]
    cmp dword [rsi + r13*4], -1
    je .ra_exp_next
    lea rsi, [ir_lr_end]
    mov eax, [rsi + r13*4]
    cmp eax, r12d
    jge .ra_exp_next
    ; vreg r13 expired: free its reg
    lea rsi, [ir_phys_map]
    movzx edi, byte [rsi + r13]
    test dil, dil
    jz .ra_exp_next
    call ra_free_phys
    lea rsi, [ir_phys_map]
    mov byte [rsi + r13], 0
.ra_exp_next:
    inc r13
    jmp .ra_expire_loop
.ra_expire_done:

    ; Assign register to dst vreg
    mov r13d, [rcx + IR_OFF_DST]
    cmp r13d, -1
    je .ra_scan_next
    cmp r13d, VREG_MAX
    jge .ra_scan_next
    lea rsi, [ir_lr_start]
    cmp dword [rsi + r13*4], -1
    je .ra_scan_next            ; never defined, skip

    call ra_alloc_phys
    cmp al, PHYS_SPILL
    je .ra_do_spill
    lea rsi, [ir_phys_map]
    mov [rsi + r13], al
    ; write phys into record
    mov [rcx + IR_OFF_PHYS], al
    jmp .ra_scan_next

.ra_do_spill:
    ; Allocate a spill slot (8-byte aligned)
    mov eax, [ra_spill_top]
    lea rsi, [ir_spill_slot]
    mov [rsi + r13*4], eax
    add dword [ra_spill_top], 8
    mov eax, [ra_spill_top]
    cmp eax, [ir_frame_sz]
    jle .ra_spill_no_grow
    mov [ir_frame_sz], eax
.ra_spill_no_grow:
    lea rsi, [ir_phys_map]
    mov byte [rsi + r13], PHYS_SPILL
    or byte [rcx + IR_OFF_FLAGS], IRF_SPILL
    mov byte [rcx + IR_OFF_PHYS], PHYS_SPILL

.ra_scan_next:
    inc r12
    jmp .ra_scan_loop

.ra_done:
    pop r15
    pop r14
    pop r13
    pop r12
    leave
    ret
