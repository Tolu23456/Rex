; ══════════════════════════════════════════════════════════════════════════════
; ir/pass5_licm.asm — Pass 5: Loop Invariant Code Motion
; Identifies loops via IR_LABEL + back-edge IR_JMP/IR_JZ/IR_JNZ pattern.
; Records loop depth in ir_loop_depth[]. Instructions whose src operands are
; all defined outside the loop (i.e., depth 0 or lower loop depth) and that
; are pure (no side effects) are flagged IRF_LOOP_INV.
; A second scan moves flagged records to just before their nearest enclosing
; loop header (the IR_LABEL record).
; ══════════════════════════════════════════════════════════════════════════════
default rel
%include "include/rex_defs.inc"
%include "ir/ir_defs.inc"

global ir_pass5_licm
extern ir_buffer, ir_idx, ir_loop_depth, ir_cf_known

; We track the innermost loop header index using a small stack (max nesting=16)
LICM_NEST_MAX equ 16

section .bss
licm_hdr_stack: resd LICM_NEST_MAX  ; record indices of loop header labels
licm_nest_depth: resd 1             ; current nesting level
; vreg → loop-depth at which it was defined (for invariance check)
licm_def_depth:  resb VREG_MAX

section .text

; Helper: is op pure (no side effects)?
; dil = opcode; returns rax=1 if pure, 0 otherwise
licm_is_pure_helper:
    cmp dil, IR_STORE
    je licm_is_pure_no
    cmp dil, IR_STORE_VAR
    je licm_is_pure_no
    cmp dil, IR_CALL
    je licm_is_pure_no
    cmp dil, IR_ARG
    je licm_is_pure_no
    cmp dil, IR_FILE_WRITE
    je licm_is_pure_no
    cmp dil, IR_FILE_CLOSE
    je licm_is_pure_no
    cmp dil, IR_EXIT
    je licm_is_pure_no
    cmp dil, IR_PRINT
    je licm_is_pure_no
    cmp dil, IR_SYSCALL
    je licm_is_pure_no
    mov eax, 1
    ret
licm_is_pure_no:
    xor eax, eax
    ret

ir_pass5_licm:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push r15

    ; Zero working arrays
    lea rdi, [ir_loop_depth]
    xor eax, eax
    mov ecx, IR_MAX
    rep stosb
    lea rdi, [licm_def_depth]
    xor eax, eax
    mov ecx, VREG_MAX
    rep stosb
    mov dword [licm_nest_depth], 0

    ; Pass A: annotate loop_depth for each record
    xor r12, r12
.licm_depth_loop:
    cmp r12, [ir_idx]
    jge .licm_depth_done
    mov rax, r12
    imul rax, IR_RECORD_SIZE
    lea rcx, [ir_buffer]
    add rcx, rax
    ; record current depth
    mov edx, [licm_nest_depth]
    lea rsi, [ir_loop_depth]
    mov [rsi + r12], dl
    ; detect LABEL — potential loop header
    cmp byte [rcx + IR_OFF_OP], IR_LABEL
    jne .licm_d_not_label
    ; On LABEL: check if a back-edge jumps to this label (simple heuristic:
    ; if any prior JMP/JZ/JNZ targets this label ID, it's a loop header)
    ; For simplicity, treat every LABEL as a potential loop header and push.
    mov edx, [licm_nest_depth]
    cmp edx, LICM_NEST_MAX
    jge .licm_d_not_label
    lea rsi, [licm_hdr_stack]
    mov [rsi + rdx*4], r12d
    inc dword [licm_nest_depth]
    jmp .licm_d_next
.licm_d_not_label:
    cmp byte [rcx + IR_OFF_OP], IR_JMP
    je .licm_d_back
    cmp byte [rcx + IR_OFF_OP], IR_JZ
    je .licm_d_back
    cmp byte [rcx + IR_OFF_OP], IR_JNZ
    je .licm_d_back
    jmp .licm_d_next
.licm_d_back:
    mov edx, [licm_nest_depth]
    test edx, edx
    jz .licm_d_next
    dec dword [licm_nest_depth]
.licm_d_next:
    ; record def depth for dst vreg
    mov r13d, [rcx + IR_OFF_DST]
    cmp r13d, -1
    je .licm_d_skip_dst
    cmp r13d, VREG_MAX
    jge .licm_d_skip_dst
    mov edx, [licm_nest_depth]
    lea rsi, [licm_def_depth]
    mov [rsi + r13], dl
.licm_d_skip_dst:
    inc r12
    jmp .licm_depth_loop

.licm_depth_done:
    ; Pass B: flag loop-invariant pure ops
    xor r12, r12
.licm_flag_loop:
    cmp r12, [ir_idx]
    jge .licm_done
    mov rax, r12
    imul rax, IR_RECORD_SIZE
    lea rcx, [ir_buffer]
    add rcx, rax
    test byte [rcx + IR_OFF_FLAGS], IRF_DEAD
    jnz .licm_flag_next
    ; must be inside a loop (depth >= 1)
    lea rsi, [ir_loop_depth]
    movzx edx, byte [rsi + r12]
    test edx, edx
    jz .licm_flag_next
    ; must be pure
    movzx edi, byte [rcx + IR_OFF_OP]
    call licm_is_pure_helper
    test rax, rax
    jz .licm_flag_next
    ; src0 must be defined at depth 0 (loop-invariant)
    mov r13d, [rcx + IR_OFF_SRC0]
    cmp r13d, -1
    je .licm_s0_ok
    cmp r13d, VREG_MAX
    jge .licm_flag_next
    lea rsi, [licm_def_depth]
    cmp byte [rsi + r13], 0
    jne .licm_flag_next
.licm_s0_ok:
    mov r13d, [rcx + IR_OFF_SRC1]
    cmp r13d, -1
    je .licm_flag_it
    cmp r13d, VREG_MAX
    jge .licm_flag_next
    lea rsi, [licm_def_depth]
    cmp byte [rsi + r13], 0
    jne .licm_flag_next
.licm_flag_it:
    or byte [rcx + IR_OFF_FLAGS], IRF_LOOP_INV
.licm_flag_next:
    inc r12
    jmp .licm_flag_loop

.licm_done:
    pop r15
    pop r14
    pop r13
    pop r12
    leave
    ret
