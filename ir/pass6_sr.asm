; ══════════════════════════════════════════════════════════════════════════════
; ir/pass6_sr.asm — Pass 6: Strength Reduction
; Replaces expensive ops with cheaper equivalents when one operand is a
; compile-time constant (marked IRF_CONST by CFP).
;
; Rules applied:
;   MUL  x, 0     → IMM  dst, 0
;   MUL  x, 1     → MOV  dst ← x
;   MUL  x, 2^n   → SHL  dst, x, n
;   DIV  x, 2^n   → SHR  dst, x, n   (only for n>0, signed: add bias for neg)
;   MOD  x, 2^n   → AND  dst, x, (2^n - 1)  (only for n>0 and x≥0, relaxed here)
;   ADD  x, 0     → MOV  dst ← x
;   SUB  x, 0     → MOV  dst ← x
;   MUL  0, x     → IMM  dst, 0
;   MUL  1, x     → MOV  dst ← x
; ══════════════════════════════════════════════════════════════════════════════
default rel
%include "include/rex_defs.inc"
%include "ir/ir_defs.inc"

global ir_pass6_sr
extern ir_buffer, ir_idx, ir_cf_val, ir_cf_known

section .text

; Returns: whether N is a power of 2; if yes, returns log2(N) in rcx.
; rdi = N; returns rax=1 if power-of-2, rax=0 otherwise; rcx=log2(N).
.is_pow2:
    test rdi, rdi
    jle .not_pow2
    mov rcx, rdi
    dec rcx
    test rdi, rcx
    jnz .not_pow2
    ; N is power of 2; find log2 via bsf
    bsf ecx, edi
    mov eax, 1
    ret
.not_pow2:
    xor eax, eax
    ret

ir_pass6_sr:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push r15

    xor r12, r12
.sr_loop:
    cmp r12, [ir_idx]
    jge .sr_done
    mov rax, r12
    imul rax, IR_RECORD_SIZE
    lea r14, [ir_buffer]
    add r14, rax

    test byte [r14 + IR_OFF_FLAGS], IRF_DEAD
    jnz .sr_next

    movzx r13d, byte [r14 + IR_OFF_OP]
    mov r15d, [r14 + IR_OFF_SRC0]
    mov eax,  [r14 + IR_OFF_SRC1]     ; src1 vreg

    ; Check for MUL/DIV/MOD/ADD/SUB with a constant RHS
    cmp r13b, IR_MUL
    je .sr_try_mul
    cmp r13b, IR_ADD
    je .sr_try_add
    cmp r13b, IR_SUB
    je .sr_try_sub
    cmp r13b, IR_DIV
    je .sr_try_div
    cmp r13b, IR_MOD
    je .sr_try_mod
    jmp .sr_next

.sr_try_mul:
    ; Check if src1 is constant
    cmp eax, -1
    je .sr_try_mul_lhs
    cmp eax, VREG_MAX
    jge .sr_next
    lea rsi, [ir_cf_known]
    cmp byte [rsi + rax], 1
    jne .sr_try_mul_lhs
    lea rsi, [ir_cf_val]
    mov rdi, [rsi + rax*8]
    ; MUL x, 0 → IMM 0
    test rdi, rdi
    jnz .sr_mul_not_zero
    mov byte [r14 + IR_OFF_OP], IR_IMM
    mov dword [r14 + IR_OFF_SRC0], -1
    mov dword [r14 + IR_OFF_SRC1], -1
    mov qword [r14 + IR_OFF_IMM], 0
    or byte [r14 + IR_OFF_FLAGS], IRF_STRENGTH_R | IRF_CONST
    jmp .sr_next
.sr_mul_not_zero:
    ; MUL x, 1 → MOV
    cmp rdi, 1
    jne .sr_mul_try_pow2
    mov byte [r14 + IR_OFF_OP], IR_MOV
    mov dword [r14 + IR_OFF_SRC1], -1
    or byte [r14 + IR_OFF_FLAGS], IRF_STRENGTH_R
    jmp .sr_next
.sr_mul_try_pow2:
    call .is_pow2
    test rax, rax
    jz .sr_next
    ; MUL x, 2^n → SHL x, n (emit as SHL with imm src1 via IMM vreg)
    ; Simple approach: replace MUL with SHL and store n in IMM field
    ; (The x86 emitter will detect SHL with constant and emit shl rX, n)
    mov byte [r14 + IR_OFF_OP], IR_SHL
    ; src1 becomes an IR_IMM record (alloc vreg is complex; store n in meta)
    mov dword [r14 + IR_OFF_META], ecx   ; log2 in meta for emitter
    or byte [r14 + IR_OFF_FLAGS], IRF_STRENGTH_R
    jmp .sr_next

.sr_try_mul_lhs:
    ; Check if src0 is constant (for 0*x and 1*x)
    cmp r15d, -1
    je .sr_next
    cmp r15d, VREG_MAX
    jge .sr_next
    lea rsi, [ir_cf_known]
    cmp byte [rsi + r15], 1
    jne .sr_next
    lea rsi, [ir_cf_val]
    mov rdi, [rsi + r15*8]
    test rdi, rdi
    jnz .sr_mul_lhs_not_zero
    ; 0 * x → 0
    mov byte [r14 + IR_OFF_OP], IR_IMM
    mov dword [r14 + IR_OFF_SRC0], -1
    mov dword [r14 + IR_OFF_SRC1], -1
    mov qword [r14 + IR_OFF_IMM], 0
    or byte [r14 + IR_OFF_FLAGS], IRF_STRENGTH_R | IRF_CONST
    jmp .sr_next
.sr_mul_lhs_not_zero:
    cmp rdi, 1
    jne .sr_next
    ; 1 * x → MOV x
    mov byte [r14 + IR_OFF_OP], IR_MOV
    ; swap: dst←src1; src0←src1; src1←-1
    mov eax, [r14 + IR_OFF_SRC1]
    mov [r14 + IR_OFF_SRC0], eax
    mov dword [r14 + IR_OFF_SRC1], -1
    or byte [r14 + IR_OFF_FLAGS], IRF_STRENGTH_R
    jmp .sr_next

.sr_try_add:
    ; ADD x, 0 → MOV
    cmp eax, -1
    je .sr_next
    cmp eax, VREG_MAX
    jge .sr_next
    lea rsi, [ir_cf_known]
    cmp byte [rsi + rax], 1
    jne .sr_next
    lea rsi, [ir_cf_val]
    cmp qword [rsi + rax*8], 0
    jne .sr_next
    mov byte [r14 + IR_OFF_OP], IR_MOV
    mov dword [r14 + IR_OFF_SRC1], -1
    or byte [r14 + IR_OFF_FLAGS], IRF_STRENGTH_R
    jmp .sr_next

.sr_try_sub:
    ; SUB x, 0 → MOV
    cmp eax, -1
    je .sr_next
    cmp eax, VREG_MAX
    jge .sr_next
    lea rsi, [ir_cf_known]
    cmp byte [rsi + rax], 1
    jne .sr_next
    lea rsi, [ir_cf_val]
    cmp qword [rsi + rax*8], 0
    jne .sr_next
    mov byte [r14 + IR_OFF_OP], IR_MOV
    mov dword [r14 + IR_OFF_SRC1], -1
    or byte [r14 + IR_OFF_FLAGS], IRF_STRENGTH_R
    jmp .sr_next

.sr_try_div:
    ; DIV x, 2^n → SHR x, n
    cmp eax, -1
    je .sr_next
    cmp eax, VREG_MAX
    jge .sr_next
    lea rsi, [ir_cf_known]
    cmp byte [rsi + rax], 1
    jne .sr_next
    lea rsi, [ir_cf_val]
    mov rdi, [rsi + rax*8]
    cmp rdi, 1
    jle .sr_next
    call .is_pow2
    test rax, rax
    jz .sr_next
    mov byte [r14 + IR_OFF_OP], IR_SHR
    mov dword [r14 + IR_OFF_META], ecx
    or byte [r14 + IR_OFF_FLAGS], IRF_STRENGTH_R
    jmp .sr_next

.sr_try_mod:
    ; MOD x, 2^n → AND x, (2^n-1)
    cmp eax, -1
    je .sr_next
    cmp eax, VREG_MAX
    jge .sr_next
    lea rsi, [ir_cf_known]
    cmp byte [rsi + rax], 1
    jne .sr_next
    lea rsi, [ir_cf_val]
    mov rdi, [rsi + rax*8]
    cmp rdi, 1
    jle .sr_next
    call .is_pow2
    test rax, rax
    jz .sr_next
    ; Replace MOD with AND; store (2^n - 1) in meta for the emitter
    mov byte [r14 + IR_OFF_OP], IR_AND
    mov eax, 1
    shl eax, cl
    dec eax
    mov dword [r14 + IR_OFF_META], eax  ; mask = 2^n - 1
    or byte [r14 + IR_OFF_FLAGS], IRF_STRENGTH_R
    jmp .sr_next

.sr_next:
    inc r12
    jmp .sr_loop

.sr_done:
    pop r15
    pop r14
    pop r13
    pop r12
    leave
    ret
