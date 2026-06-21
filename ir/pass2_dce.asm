; ══════════════════════════════════════════════════════════════════════════════
; ir/pass2_dce.asm — Pass 2: Dead Code Elimination
; Two-phase: (1) count uses per vreg; (2) mark records whose dst is never used
; as dead (IRF_DEAD). Respects side-effecting ops (stores, calls, I/O).
; ══════════════════════════════════════════════════════════════════════════════
default rel
%include "include/rex_defs.inc"
%include "ir/ir_defs.inc"

global ir_pass2_dce
extern ir_buffer, ir_idx, ir_use_cnt

section .text

; Helper: is op side-effecting? (stores, calls, I/O, control flow, prints)
; rdi = opcode byte; returns rax = 1 if side-effecting, 0 if pure
.is_side_effecting:
    cmp dil, IR_STORE
    je .se_yes
    cmp dil, IR_STORE_VAR
    je .se_yes
    cmp dil, IR_CALL
    je .se_yes
    cmp dil, IR_ARG
    je .se_yes
    cmp dil, IR_RET
    je .se_yes
    cmp dil, IR_RET_VOID
    je .se_yes
    cmp dil, IR_JMP
    je .se_yes
    cmp dil, IR_JZ
    je .se_yes
    cmp dil, IR_JNZ
    je .se_yes
    cmp dil, IR_LABEL
    je .se_yes
    cmp dil, IR_FILE_WRITE
    je .se_yes
    cmp dil, IR_FILE_CLOSE
    je .se_yes
    cmp dil, IR_EXIT
    je .se_yes
    cmp dil, IR_PRINT
    je .se_yes
    xor eax, eax
    ret
.se_yes:
    mov eax, 1
    ret

ir_pass2_dce:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14

    ; Phase 1: zero use counts
    lea rdi, [ir_use_cnt]
    xor eax, eax
    mov ecx, VREG_MAX
    rep stosw

    ; Phase 1: count uses
    xor r12, r12
.dce_count_loop:
    mov rax, [ir_idx]
    cmp r12, rax
    jge .dce_count_done
    mov rax, r12
    imul rax, IR_RECORD_SIZE
    lea rcx, [ir_buffer]
    add rcx, rax
    ; src0
    mov r13d, [rcx + IR_OFF_SRC0]
    cmp r13d, -1
    je .dce_c_s1
    cmp r13d, VREG_MAX
    jge .dce_c_s1
    lea rdi, [ir_use_cnt]
    inc word [rdi + r13*2]
.dce_c_s1:
    mov r13d, [rcx + IR_OFF_SRC1]
    cmp r13d, -1
    je .dce_c_next
    cmp r13d, VREG_MAX
    jge .dce_c_next
    lea rdi, [ir_use_cnt]
    inc word [rdi + r13*2]
.dce_c_next:
    inc r12
    jmp .dce_count_loop

.dce_count_done:
    ; Phase 2: mark dead records
    xor r12, r12
.dce_mark_loop:
    mov rax, [ir_idx]
    cmp r12, rax
    jge .dce_done
    mov rax, r12
    imul rax, IR_RECORD_SIZE
    lea rcx, [ir_buffer]
    add rcx, rax
    ; skip already-dead
    test byte [rcx + IR_OFF_FLAGS], IRF_DEAD
    jnz .dce_mark_next
    ; side-effecting ops are never dead
    movzx edi, byte [rcx + IR_OFF_OP]
    call .is_side_effecting
    test rax, rax
    jnz .dce_mark_next
    ; no result → pure NOP-like, can eliminate
    mov r13d, [rcx + IR_OFF_DST]
    cmp r13d, -1
    je .dce_mark_dead
    cmp r13d, VREG_MAX
    jge .dce_mark_next
    ; check use count
    lea rdi, [ir_use_cnt]
    movzx eax, word [rdi + r13*2]
    test eax, eax
    jnz .dce_mark_next
.dce_mark_dead:
    or byte [rcx + IR_OFF_FLAGS], IRF_DEAD
.dce_mark_next:
    inc r12
    jmp .dce_mark_loop

.dce_done:
    pop r14
    pop r13
    pop r12
    leave
    ret
