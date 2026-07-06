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

section .text

global ir_optimize_pass1
global ir_optimize_pass2
global ir_optimize_pass3
global ir_optimize_pass4
global ir_optimize_pass5

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
    mov     r11, rax
    mov     rax, r9
    cqo
    idiv    r10
    mov     r9, rax
    mov     rax, r11
    jmp     .fold_replace
.fold_mod:
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

    mov     byte [rax + IR_OFF_OPCODE], IR_NOP
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
; ir_optimize_pass4 — Linear Scan Register Allocation (stub)
; ============================================================
ir_optimize_pass4:
    ret

; ============================================================
; ir_optimize_pass5 — Peephole Optimization (stub)
; ============================================================
ir_optimize_pass5:
    ret
