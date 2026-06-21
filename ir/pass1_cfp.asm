; ══════════════════════════════════════════════════════════════════════════════
; ir/pass1_cfp.asm — Pass 1: Constant Fold & Propagate
; Scans IR linearly; when both src operands of an arithmetic/compare op are
; known constants, replaces the record with IR_IMM and marks sources dead.
; Sets IRF_CONST on newly known IR_IMM records to enable cascaded folding.
; ══════════════════════════════════════════════════════════════════════════════
default rel
%include "include/rex_defs.inc"
%include "ir/ir_defs.inc"

global ir_pass1_cfp
extern ir_buffer, ir_idx, ir_cf_val, ir_cf_known

section .text

; ir_pass1_cfp — constant-fold one full IR buffer.
; No args. Clobbers rax, rbx, rcx, rdx, rsi, rdi, r8–r11.
ir_pass1_cfp:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push r15

    ; Zero cf_val/cf_known tables
    lea rdi, [ir_cf_val]
    xor eax, eax
    mov ecx, VREG_MAX
    rep stosq
    lea rdi, [ir_cf_known]
    xor eax, eax
    mov ecx, VREG_MAX
    rep stosb

    xor r12, r12             ; r12 = record index

.cfp_loop:
    mov rax, [ir_idx]
    cmp r12, rax
    jge .cfp_done

    ; Get pointer to current record
    mov rax, r12
    imul rax, IR_RECORD_SIZE
    lea rcx, [ir_buffer]
    add rcx, rax             ; rcx = record ptr

    ; Skip dead records
    test byte [rcx + IR_OFF_FLAGS], IRF_DEAD
    jnz .cfp_next

    movzx r13d, byte [rcx + IR_OFF_OP]
    mov r14d, [rcx + IR_OFF_DST]    ; dst vreg

    ; IR_IMM: record a known constant for dst
    cmp r13b, IR_IMM
    jne .cfp_not_imm
    cmp r14d, -1
    je .cfp_next
    cmp r14d, VREG_MAX
    jge .cfp_next
    mov rax, [rcx + IR_OFF_IMM]
    lea rsi, [ir_cf_val]
    mov [rsi + r14*8], rax   ; cf_val[dst] = imm
    lea rsi, [ir_cf_known]
    mov byte [rsi + r14], 1  ; cf_known[dst] = 1
    or byte [rcx + IR_OFF_FLAGS], IRF_CONST
    jmp .cfp_next

.cfp_not_imm:
    ; For binary ops: check if both src0 and src1 are known constants
    cmp r13b, IR_ADD
    jl .cfp_next
    cmp r13b, IR_GE
    jg .cfp_not_binop_int
    ; integer binary op — check constant-ness
    mov r15d, [rcx + IR_OFF_SRC0]
    mov r11d, [rcx + IR_OFF_SRC1]
    cmp r15d, -1
    je .cfp_next
    cmp r11d, -1
    je .cfp_next
    cmp r15d, VREG_MAX
    jge .cfp_next
    cmp r11d, VREG_MAX
    jge .cfp_next
    ; both vregs within range — check cf_known
    lea rsi, [ir_cf_known]
    cmp byte [rsi + r15], 1
    jne .cfp_next
    cmp byte [rsi + r11], 1
    jne .cfp_next
    ; both constant: fold
    lea rsi, [ir_cf_val]
    mov rax, [rsi + r15*8]   ; val_a = cf_val[src0]
    mov r8,  [rsi + r11*8]   ; val_b = cf_val[src1]
    ; dispatch on opcode
    call .cfp_fold_int
    ; store folded result as IR_IMM
    cmp r14d, -1
    je .cfp_next
    cmp r14d, VREG_MAX
    jge .cfp_next
    ; overwrite record in-place with IR_IMM
    mov byte [rcx + IR_OFF_OP], IR_IMM
    or  byte [rcx + IR_OFF_FLAGS], IRF_CONST | IRF_FOLDED
    mov dword [rcx + IR_OFF_SRC0], -1
    mov dword [rcx + IR_OFF_SRC1], -1
    mov [rcx + IR_OFF_IMM], rax
    ; record new constant
    lea rsi, [ir_cf_val]
    mov [rsi + r14*8], rax
    lea rsi, [ir_cf_known]
    mov byte [rsi + r14], 1
    jmp .cfp_next

.cfp_not_binop_int:
    ; (float ops and other opcodes: no folding in pass 1 for brevity)
    jmp .cfp_next

.cfp_next:
    inc r12
    jmp .cfp_loop

.cfp_done:
    pop r15
    pop r14
    pop r13
    pop r12
    leave
    ret

; ── Internal: compute folded integer result ───────────────────────────────────
; rax = val_a, r8 = val_b, r13b = opcode
; Returns: rax = folded result
.cfp_fold_int:
    cmp r13b, IR_ADD
    jne .f1
    add rax, r8
    ret
.f1:cmp r13b, IR_SUB
    jne .f2
    sub rax, r8
    ret
.f2:cmp r13b, IR_MUL
    jne .f3
    imul rax, r8
    ret
.f3:cmp r13b, IR_DIV
    jne .f4
    test r8, r8
    jz .f_div0
    cqo
    idiv r8
    ret
.f_div0:
    xor eax, eax
    ret
.f4:cmp r13b, IR_MOD
    jne .f5
    test r8, r8
    jz .f_div0
    cqo
    idiv r8
    mov rax, rdx
    ret
.f5:cmp r13b, IR_AND
    jne .f6
    and rax, r8
    ret
.f6:cmp r13b, IR_OR
    jne .f7
    or rax, r8
    ret
.f7:cmp r13b, IR_XOR
    jne .f8
    xor rax, r8
    ret
.f8:cmp r13b, IR_SHL
    jne .f9
    mov rcx, r8
    shl rax, cl
    ret
.f9:cmp r13b, IR_SHR
    jne .f10
    mov rcx, r8
    sar rax, cl
    ret
.f10:cmp r13b, IR_EQ
    jne .f11
    cmp rax, r8
    sete al
    movzx rax, al
    ret
.f11:cmp r13b, IR_NE
    jne .f12
    cmp rax, r8
    setne al
    movzx rax, al
    ret
.f12:cmp r13b, IR_LT
    jne .f13
    cmp rax, r8
    setl al
    movzx rax, al
    ret
.f13:cmp r13b, IR_LE
    jne .f14
    cmp rax, r8
    setle al
    movzx rax, al
    ret
.f14:cmp r13b, IR_GT
    jne .f15
    cmp rax, r8
    setg al
    movzx rax, al
    ret
.f15:cmp r13b, IR_GE
    jne .f_default
    cmp rax, r8
    setge al
    movzx rax, al
    ret
.f_default:
    ret
