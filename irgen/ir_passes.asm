; ============================================================
; IR Optimization Passes
; irgen/ir_passes.asm
; ============================================================

bits 64
default rel

%include "rex_defs.inc"
%include "rex_ir.inc"

extern ir_buffer
extern ir_idx

; ============================================================
; Register Allocation Constants
; ============================================================
%define REG_POOL_SIZE   12
%define REG_SPILLED     0xFF

section .bss

live_start:     resw 256    ; first definition index per vreg
live_end:       resw 256    ; last use index per vreg
vreg_phys:      resw 256    ; physical register assignment per vreg (0xFF = spilled)
spill_slot:     resw 256    ; stack offset for spilled vregs
num_spills:     resw 1      ; count of spill slots used
sorted_vregs:   resw 256    ; vreg IDs sorted by live_start
sorted_start:   resw 256    ; corresponding live_start values
sorted_end:     resw 256    ; corresponding live_end values
sorted_count:   resw 1      ; number of vregs with live ranges
active_vregs:   resw 12     ; active vreg IDs
active_phys:    resw 12     ; active physical register IDs
active_end:     resw 12     ; active live_end values
active_count:   resw 1      ; number of active vregs

section .data

; Register pool in priority order (most preferred first)
; r10(8), r11(9), r8(6), r9(7), rsi(4), rdi(5), rcx(2), rdx(3), r12(10), r13(11), rbx(1), rax(0)
reg_pool:
    dw 8, 9, 6, 7, 4, 5, 2, 3, 10, 11, 1, 0

section .text

global ir_optimize_pass1
global ir_optimize_pass2
global ir_optimize_pass3
global ir_optimize_pass4
global ir_optimize_pass5
global vreg_phys

; ============================================================
; ir_optimize_pass1 — Constant Folding
; ============================================================
ir_optimize_pass1:
    push    rbx
    push    r12
    push    r13

    ; Stack layout: [const_table: 256 qwords] [known_flags: 256 bytes]
    sub     rsp, 2048 + 256

    ; Zero known flags
    lea     rdi, [rsp + 2048]
    xor     eax, eax
    mov     ecx, 256
    rep stosb

    ; Zero const values
    lea     rdi, [rsp]
    mov     ecx, 256
    rep stosq

    lea     r12, [ir_buffer]
    mov     r13d, [ir_idx]
    xor     ebx, ebx

.pass1_loop:
    cmp     ebx, r13d
    jae     .pass1_done

    mov     rax, rbx
    shl     rax, 5
    add     rax, r12

    movzx   ecx, byte [rax + IR_OFF_OPCODE]

    cmp     cl, IR_LOAD_IMM
    je      .pass1_load_imm

    cmp     cl, IR_NEG
    je      .pass1_neg

    ; Binary ops: IR_ADD..IR_MOD (0x11..0x15)
    cmp     cl, IR_ADD
    jb      .pass1_next
    cmp     cl, IR_MOD
    ja      .pass1_next
    jmp     .pass1_binary

.pass1_load_imm:
    movzx   edx, word [rax + IR_OFF_DST]
    cmp     edx, 256
    jae     .pass1_next
    mov     r8, [rax + IR_OFF_IMM]
    mov     [rsp + rdx*8], r8
    mov     byte [rsp + 2048 + rdx], 1
    or      dword [rax + IR_OFF_FLAGS], IR_FLAG_CONST
    jmp     .pass1_next

.pass1_binary:
    movzx   edx, word [rax + IR_OFF_SRC1]
    movzx   r8d, word [rax + IR_OFF_SRC2]
    cmp     edx, 256
    jae     .pass1_next
    cmp     r8d, 256
    jae     .pass1_next
    cmp     byte [rsp + 2048 + rdx], 0
    je      .pass1_next
    cmp     byte [rsp + 2048 + r8], 0
    je      .pass1_next

    mov     r9, [rsp + rdx*8]
    mov     r10, [rsp + r8*8]

    cmp     cl, IR_ADD
    je      .fold_add
    cmp     cl, IR_SUB
    je      .fold_sub
    cmp     cl, IR_MUL
    je      .fold_mul
    cmp     cl, IR_DIV
    je      .fold_div
    jmp     .fold_mod

.fold_add:
    add     r9, r10
    jmp     .fold_replace
.fold_sub:
    sub     r9, r10
    jmp     .fold_replace
.fold_mul:
    imul    r9, r10
    jmp     .fold_replace
.fold_div:
    test    r10, r10
    jz      .pass1_next
    mov     r11, rax
    mov     rax, r9
    cqo
    idiv    r10
    mov     r9, rax
    mov     rax, r11
    jmp     .fold_replace
.fold_mod:
    test    r10, r10
    jz      .pass1_next
    mov     r11, rax
    mov     rax, r9
    cqo
    idiv    r10
    mov     r9, rdx
    mov     rax, r11

.fold_replace:
    mov     byte [rax + IR_OFF_OPCODE], IR_LOAD_IMM
    mov     byte [rax + IR_OFF_TYPE], TYPE_INT
    mov     word [rax + IR_OFF_SRC1], 0
    mov     word [rax + IR_OFF_SRC2], 0
    mov     [rax + IR_OFF_IMM], r9

    movzx   ecx, word [rax + IR_OFF_DST]
    cmp     ecx, 256
    jae     .pass1_next
    mov     [rsp + rcx*8], r9
    mov     byte [rsp + 2048 + rcx], 1
    jmp     .pass1_next

.pass1_neg:
    movzx   edx, word [rax + IR_OFF_SRC1]
    cmp     edx, 256
    jae     .pass1_next
    cmp     byte [rsp + 2048 + rdx], 0
    je      .pass1_next

    mov     r9, [rsp + rdx*8]
    neg     r9

    mov     byte [rax + IR_OFF_OPCODE], IR_LOAD_IMM
    mov     byte [rax + IR_OFF_TYPE], TYPE_INT
    mov     word [rax + IR_OFF_SRC1], 0
    mov     word [rax + IR_OFF_SRC2], 0
    mov     [rax + IR_OFF_IMM], r9

    movzx   ecx, word [rax + IR_OFF_DST]
    cmp     ecx, 256
    jae     .pass1_next
    mov     [rsp + rcx*8], r9
    mov     byte [rsp + 2048 + rcx], 1

.pass1_next:
    inc     ebx
    jmp     .pass1_loop

.pass1_done:
    add     rsp, 2048 + 256
    pop     r13
    pop     r12
    pop     rbx
    ret

; ============================================================
; ir_optimize_pass2 — Dead Store Elimination
; ============================================================
ir_optimize_pass2:
    push    rbx
    push    r12
    push    r13
    push    r14

    lea     r12, [ir_buffer]
    mov     r13d, [ir_idx]
    mov     ebx, r13d
    dec     ebx

.pass2_loop:
    cmp     ebx, 0
    jl      .pass2_done

    mov     rax, rbx
    shl     rax, 5
    add     rax, r12

    cmp     byte [rax + IR_OFF_OPCODE], IR_STORE_VAR
    jne     .pass2_next

    movzx   r14d, word [rax + IR_OFF_SRC1]

    mov     ecx, ebx
    inc     ecx

.pass2_scan:
    cmp     ecx, r13d
    jae     .pass2_next

    mov     rdx, rcx
    shl     rdx, 5
    add     rdx, r12

    movzx   esi, byte [rdx + IR_OFF_OPCODE]

    cmp     sil, IR_LOAD_VAR
    jne     .pass2_scan_store
    cmp     word [rdx + IR_OFF_SRC1], r14w
    jne     .pass2_scan_inc
    jmp     .pass2_next

.pass2_scan_store:
    cmp     sil, IR_STORE_VAR
    jne     .pass2_scan_inc
    cmp     word [rdx + IR_OFF_SRC1], r14w
    jne     .pass2_scan_inc
    mov     byte [rax + IR_OFF_OPCODE], IR_NOP
    jmp     .pass2_next

.pass2_scan_inc:
    inc     ecx
    jmp     .pass2_scan

.pass2_next:
    dec     ebx
    jmp     .pass2_loop

.pass2_done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ============================================================
; ir_optimize_pass3 — Load-Store Coalescing
; ============================================================
ir_optimize_pass3:
    push    rbx
    push    r12
    push    r13

    lea     r12, [ir_buffer]
    mov     r13d, [ir_idx]

    cmp     r13d, 2
    jb      .pass3_done

    xor     ebx, ebx

.pass3_loop:
    mov     eax, ebx
    inc     eax
    cmp     eax, r13d
    jae     .pass3_done

    mov     rax, rbx
    shl     rax, 5
    add     rax, r12

    mov     rdx, rbx
    inc     rdx
    shl     rdx, 5
    add     rdx, r12

    cmp     byte [rax + IR_OFF_OPCODE], IR_LOAD_VAR
    jne     .pass3_next
    cmp     byte [rdx + IR_OFF_OPCODE], IR_STORE_VAR
    jne     .pass3_next

    movzx   ecx, word [rax + IR_OFF_DST]
    cmp     cx, word [rdx + IR_OFF_SRC2]
    jne     .pass3_next

    movzx   esi, word [rax + IR_OFF_SRC1]
    cmp     si, word [rdx + IR_OFF_SRC1]
    jne     .pass3_next

    mov     edi, ebx
    add     edi, 2
.pass3_check_live:
    cmp     edi, r13d
    jae     .pass3_coalesce
    mov     rax, rdi
    shl     rax, 5
    add     rax, r12
    cmp     word [rax + IR_OFF_SRC1], cx
    je      .pass3_next
    cmp     word [rax + IR_OFF_SRC2], cx
    je      .pass3_next
    inc     edi
    jmp     .pass3_check_live

.pass3_coalesce:
    mov     rax, rbx
    shl     rax, 5
    add     rax, r12
    mov     byte [rax + IR_OFF_OPCODE], IR_NOP
    mov     rdx, rbx
    inc     rdx
    shl     rdx, 5
    add     rdx, r12
    mov     byte [rdx + IR_OFF_OPCODE], IR_NOP

.pass3_next:
    inc     ebx
    jmp     .pass3_loop

.pass3_done:
    pop     r13
    pop     r12
    pop     rbx
    ret

; ============================================================
; ir_optimize_pass4 — Linear Scan Register Allocation
;
; Phase A: Compute live ranges for each vreg by scanning ir_buffer.
; Phase B: Assign physical registers using linear scan algorithm.
;   - Available pool: 12 GPRs (r10,r11,r8,r9,rsi,rdi,rcx,rdx,r12,r13,rbx,rax)
;   - r14,r15 excluded (used by type propagation and loop pin)
;   - Vregs that cannot be assigned are marked spilled (0xFF)
;
; Results stored in vreg_phys[vreg_id] → physical register ID or 0xFF.
; The x86 emission pass reads vreg_phys to emit register-to-register
; instructions instead of stack-based operations.
; ============================================================
ir_optimize_pass4:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    ; ---- Phase A: Zero arrays ----
    lea     rdi, [live_start]
    xor     eax, eax
    mov     ecx, 256
    rep stosw

    lea     rdi, [live_end]
    mov     ecx, 256
    rep stosw

    lea     rdi, [vreg_phys]
    mov     ax, REG_SPILLED
    mov     ecx, 256
    rep stosw

    mov     word [num_spills], 0
    mov     word [sorted_count], 0
    mov     word [active_count], 0

    ; ---- Phase A: Compute live ranges ----
    lea     r12, [ir_buffer]
    mov     r13d, [ir_idx]
    xor     ebx, ebx

.pass4_scan:
    cmp     ebx, r13d
    jae     .pass4_scan_done

    mov     rax, rbx
    shl     rax, 5
    add     rax, r12

    ; Check dst: first definition of this vreg
    movzx   ecx, word [rax + IR_OFF_DST]
    test    cx, cx
    jz      .pass4_scan_src1
    cmp     ecx, 256
    jae     .pass4_scan_src1
    cmp     word [live_start + rcx*2], 0
    jne     .pass4_scan_src1
    mov     word [live_start + rcx*2], bx

.pass4_scan_src1:
    ; Check src1: last use of this vreg
    movzx   ecx, word [rax + IR_OFF_SRC1]
    test    cx, cx
    jz      .pass4_scan_src2
    cmp     ecx, 256
    jae     .pass4_scan_src2
    mov     word [live_end + rcx*2], bx

.pass4_scan_src2:
    ; Check src2: last use of this vreg
    movzx   ecx, word [rax + IR_OFF_SRC2]
    test    cx, cx
    jz      .pass4_scan_next
    cmp     ecx, 256
    jae     .pass4_scan_next
    mov     word [live_end + rcx*2], bx

.pass4_scan_next:
    inc     ebx
    jmp     .pass4_scan

.pass4_scan_done:
    ; ---- Phase B: Assign physical registers ----

    ; Build sorted list of vregs with live ranges
    mov     word [sorted_count], 0
    mov     r14d, 1

.pass4_build:
    cmp     r14d, 256
    jae     .pass4_build_done

    movzx   eax, word [live_start + r14*2]
    test    ax, ax
    jz      .pass4_build_next

    movzx   ecx, word [sorted_count]
    mov     word [sorted_vregs + rcx*2], r14w
    mov     word [sorted_start + rcx*2], ax
    movzx   eax, word [live_end + r14*2]
    mov     word [sorted_end + rcx*2], ax
    inc     word [sorted_count]

.pass4_build_next:
    inc     r14d
    jmp     .pass4_build

.pass4_build_done:
    ; Sort by live_start ascending (insertion sort)
    movzx   ecx, word [sorted_count]
    cmp     ecx, 2
    jb      .pass4_sort_done

    mov     r14d, 1

.pass4_sort_outer:
    cmp     r14d, ecx
    jae     .pass4_sort_done

    movzx   eax, word [sorted_start + r14*2]
    mov     r15d, eax
    movzx   edx, word [sorted_vregs + r14*2]
    mov     r12d, edx
    movzx   edx, word [sorted_end + r14*2]
    mov     r13d, edx

    mov     ebx, r14d
    dec     ebx

.pass4_sort_inner:
    cmp     ebx, 0
    jl      .pass4_sort_insert

    movzx   eax, word [sorted_start + rbx*2]
    cmp     ax, r15w
    jbe     .pass4_sort_insert

    movzx   edx, word [sorted_vregs + rbx*2]
    mov     word [sorted_vregs + (rbx+1)*2], dx
    movzx   edx, word [sorted_start + rbx*2]
    mov     word [sorted_start + (rbx+1)*2], dx
    movzx   edx, word [sorted_end + rbx*2]
    mov     word [sorted_end + (rbx+1)*2], dx

    dec     ebx
    jmp     .pass4_sort_inner

.pass4_sort_insert:
    inc     ebx
    mov     word [sorted_vregs + rbx*2], r12w
    mov     word [sorted_start + rbx*2], r15w
    mov     word [sorted_end + rbx*2], r13w

    inc     r14d
    movzx   ecx, word [sorted_count]
    jmp     .pass4_sort_outer

.pass4_sort_done:
    ; Linear scan over sorted vregs
    mov     word [active_count], 0
    xor     ebx, ebx        ; pool index
    mov     r14d, 0         ; sorted index

.pass4_linear:
    movzx   eax, word [sorted_count]
    cmp     r14d, eax
    jae     .pass4_linear_done

    movzx   eax, word [sorted_vregs + r14*2]
    mov     r12d, eax        ; r12 = current vreg
    movzx   eax, word [sorted_start + r14*2]
    mov     r13d, eax        ; r13 = current live_start
    movzx   eax, word [sorted_end + r14*2]
    mov     r15d, eax        ; r15 = current live_end

    ; Remove expired vregs from active list
    movzx   ecx, word [active_count]
    xor     edx, edx

.pass4_remove:
    cmp     edx, ecx
    jae     .pass4_remove_done

    movzx   eax, word [active_end + rdx*2]
    cmp     ax, r13w
    jae     .pass4_remove_next

    ; Expired: shift left
    dec     ecx
    mov     esi, edx
.pass4_remove_shift:
    cmp     esi, ecx
    jge     .pass4_remove_shift_done
    movzx   eax, word [active_vregs + (rsi+1)*2]
    mov     word [active_vregs + rsi*2], ax
    movzx   eax, word [active_phys + (rsi+1)*2]
    mov     word [active_phys + rsi*2], ax
    movzx   eax, word [active_end + (rsi+1)*2]
    mov     word [active_end + rsi*2], ax
    inc     esi
    jmp     .pass4_remove_shift
.pass4_remove_shift_done:
    dec     edx
    jmp     .pass4_remove_next

.pass4_remove_next:
    inc     edx
    jmp     .pass4_remove

.pass4_remove_done:
    mov     word [active_count], cx

    ; Try to assign a free physical register
    cmp     ebx, REG_POOL_SIZE
    jae     .pass4_try_spill

    movzx   eax, word [reg_pool + ebx*2]
    mov     word [vreg_phys + r12*2], ax

    movzx   ecx, word [active_count]
    mov     word [active_vregs + rcx*2], r12w
    mov     word [active_phys + rcx*2], ax
    mov     word [active_end + rcx*2], r15w
    inc     word [active_count]

    inc     ebx
    jmp     .pass4_linear_next

.pass4_try_spill:
    ; All registers in use — find active vreg with furthest live_end
    movzx   ecx, word [active_count]
    test    ecx, ecx
    jz      .pass4_linear_next

    xor     edx, edx        ; furthest index
    xor     esi, esi        ; scan index
    movzx   eax, word [active_end]
    mov     edi, eax        ; furthest_end

.pass4_find_furthest:
    inc     esi
    cmp     esi, ecx
    jae     .pass4_check_furthest
    movzx   eax, word [active_end + rsi*2]
    cmp     ax, di
    jbe     .pass4_find_furthest
    mov     edi, eax
    mov     edx, esi
    jmp     .pass4_find_furthest

.pass4_check_furthest:
    ; If current vreg dies later than the furthest active, spill current
    cmp     r15w, di
    ja      .pass4_linear_next

    ; Spill the active vreg with furthest live_end
    movzx   eax, word [active_vregs + rdx*2]
    mov     word [vreg_phys + rax*2], REG_SPILLED

    ; Reuse its register for current vreg
    movzx   eax, word [active_phys + rdx*2]
    mov     word [vreg_phys + r12*2], ax

    ; Update active list entry
    mov     word [active_vregs + rdx*2], r12w
    mov     word [active_end + rdx*2], r15w

.pass4_linear_next:
    inc     r14d
    jmp     .pass4_linear

.pass4_linear_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ============================================================
; ir_optimize_pass5 — Peephole Optimization
;   Pattern 3: INC/DEC recognition
;     IR_ADD dst, src1, src2 where src2 is known 1 → IR_INC dst, src1
;     IR_SUB dst, src1, src2 where src2 is known 1 → IR_DEC dst, src1
;   Pattern 5: Strength reduction
;     IR_MUL dst, src1, src2 where src2 is known 2 → IR_BSHL dst, src1, imm=1
; ============================================================
ir_optimize_pass5:
    push    rbx
    push    r12
    push    r13

    sub     rsp, 2048 + 256

    lea     rdi, [rsp + 2048]
    xor     eax, eax
    mov     ecx, 256
    rep stosb

    lea     rdi, [rsp]
    mov     ecx, 256
    rep stosq

    lea     r12, [ir_buffer]
    mov     r13d, [ir_idx]
    xor     ebx, ebx

.pass5_loop:
    cmp     ebx, r13d
    jae     .pass5_done

    mov     rax, rbx
    shl     rax, 5
    add     rax, r12

    movzx   ecx, byte [rax + IR_OFF_OPCODE]

    cmp     cl, IR_NOP
    je      .pass5_next

    cmp     cl, IR_LOAD_IMM
    je      .pass5_load_imm

    cmp     cl, IR_ADD
    je      .pass5_check_inc

    cmp     cl, IR_SUB
    je      .pass5_check_dec

    cmp     cl, IR_MUL
    je      .pass5_check_shl

    jmp     .pass5_invalidate_dst

.pass5_load_imm:
    movzx   edx, word [rax + IR_OFF_DST]
    cmp     edx, 256
    jae     .pass5_next
    mov     r8, [rax + IR_OFF_IMM]
    mov     [rsp + rdx*8], r8
    mov     byte [rsp + 2048 + rdx], 1
    jmp     .pass5_next

.pass5_check_inc:
    movzx   edx, word [rax + IR_OFF_SRC2]
    cmp     edx, 256
    jae     .pass5_next
    cmp     byte [rsp + 2048 + rdx], 0
    je      .pass5_next
    cmp     qword [rsp + rdx*8], 1
    jne     .pass5_next

    mov     byte [rax + IR_OFF_OPCODE], IR_INC
    mov     word [rax + IR_OFF_SRC2], 0
    jmp     .pass5_invalidate_dst

.pass5_check_dec:
    movzx   edx, word [rax + IR_OFF_SRC2]
    cmp     edx, 256
    jae     .pass5_next
    cmp     byte [rsp + 2048 + rdx], 0
    je      .pass5_next
    cmp     qword [rsp + rdx*8], 1
    jne     .pass5_next

    mov     byte [rax + IR_OFF_OPCODE], IR_DEC
    mov     word [rax + IR_OFF_SRC2], 0
    jmp     .pass5_invalidate_dst

.pass5_check_shl:
    movzx   edx, word [rax + IR_OFF_SRC2]
    cmp     edx, 256
    jae     .pass5_next
    cmp     byte [rsp + 2048 + rdx], 0
    je      .pass5_next
    cmp     qword [rsp + rdx*8], 2
    jne     .pass5_next

    mov     byte [rax + IR_OFF_OPCODE], IR_BSHL
    mov     word [rax + IR_OFF_SRC2], 0
    mov     qword [rax + IR_OFF_IMM], 1
    jmp     .pass5_invalidate_dst

.pass5_invalidate_dst:
    movzx   ecx, word [rax + IR_OFF_DST]
    cmp     ecx, 256
    jae     .pass5_next
    mov     byte [rsp + 2048 + rcx], 0

.pass5_next:
    inc     ebx
    jmp     .pass5_loop

.pass5_done:
    add     rsp, 2048 + 256
    pop     r13
    pop     r12
    pop     rbx
    ret
