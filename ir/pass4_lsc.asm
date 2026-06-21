; ══════════════════════════════════════════════════════════════════════════════
; ir/pass4_lsc.asm — Pass 4: Load-Store Coalescing
; Finds patterns:  STORE_VAR v, x  followed immediately by  LOAD_VAR y, v
; with no intervening store or side effect on v.  Replaces the LOAD with
; IR_MOV y ← x and marks it IRF_COALESCED.  The STORE remains (the value
; still needs to persist in memory for later reads / out-of-scope refs).
; ══════════════════════════════════════════════════════════════════════════════
default rel
%include "include/rex_defs.inc"
%include "ir/ir_defs.inc"

global ir_pass4_lsc
extern ir_buffer, ir_idx

section .text

ir_pass4_lsc:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push r15

    xor r12, r12              ; r12 = current index
.lsc_loop:
    mov rax, [ir_idx]
    sub rax, 1                ; need at least 2 records
    cmp r12, rax
    jge .lsc_done

    ; Load current record
    mov rax, r12
    imul rax, IR_RECORD_SIZE
    lea r14, [ir_buffer]
    add r14, rax

    test byte [r14 + IR_OFF_FLAGS], IRF_DEAD
    jnz .lsc_next
    cmp byte [r14 + IR_OFF_OP], IR_STORE_VAR
    jne .lsc_next

    ; It's a STORE_VAR — remember var index and src vreg
    mov r13d, [r14 + IR_OFF_IMM]     ; var index
    mov r15d, [r14 + IR_OFF_SRC0]    ; src vreg stored

    ; Look ahead for a consecutive non-dead LOAD_VAR of the same var
    mov rax, r12
    inc rax
.lsc_look:
    cmp rax, [ir_idx]
    jge .lsc_next
    mov rbx, rax
    imul rbx, IR_RECORD_SIZE
    lea rcx, [ir_buffer]
    add rcx, rbx

    ; Skip dead records in lookahead
    test byte [rcx + IR_OFF_FLAGS], IRF_DEAD
    jnz .lsc_look_next

    ; If we hit another STORE_VAR for the same var → stop
    cmp byte [rcx + IR_OFF_OP], IR_STORE_VAR
    jne .lsc_check_load
    mov edx, [rcx + IR_OFF_IMM]
    cmp edx, r13d
    je .lsc_next           ; same var re-stored, can't coalesce

.lsc_check_load:
    cmp byte [rcx + IR_OFF_OP], IR_LOAD_VAR
    jne .lsc_look_not_load
    mov edx, [rcx + IR_OFF_IMM]
    cmp edx, r13d
    jne .lsc_look_not_load
    ; Match! Replace LOAD_VAR with MOV dst ← src (the stored vreg)
    mov byte [rcx + IR_OFF_OP], IR_MOV
    mov [rcx + IR_OFF_SRC0], r15d
    mov dword [rcx + IR_OFF_SRC1], -1
    or byte [rcx + IR_OFF_FLAGS], IRF_COALESCED
    jmp .lsc_next

.lsc_look_not_load:
    ; If this is a side-effecting op that might alias, stop looking
    movzx edi, byte [rcx + IR_OFF_OP]
    cmp dil, IR_CALL
    je .lsc_next
    cmp dil, IR_STORE
    je .lsc_next
    cmp dil, IR_FILE_WRITE
    je .lsc_next
    cmp dil, IR_EXIT
    je .lsc_next

.lsc_look_next:
    inc rax
    jmp .lsc_look

.lsc_next:
    inc r12
    jmp .lsc_loop

.lsc_done:
    pop r15
    pop r14
    pop r13
    pop r12
    leave
    ret
