; ══════════════════════════════════════════════════════════════════════════════
; ir/pass3_dse.asm — Pass 3: Dead Store Elimination
; Scans forward; for each IR_STORE_VAR, if the same var is stored again before
; any load of that var, the first store is dead and gets IRF_DEAD.
; ══════════════════════════════════════════════════════════════════════════════
default rel
%include "include/rex_defs.inc"
%include "ir/ir_defs.inc"

global ir_pass3_dse
extern ir_buffer, ir_idx

; Bitmap: 1 bit per var slot — was the slot stored but not yet loaded?
; We support up to 512 var slots (64 bytes = 512 bits).
DSE_VAR_MAX equ 512

section .bss
dse_stored:  resb DSE_VAR_MAX / 8   ; bit i is set if var i was last stored but not loaded
dse_store_idx: resd DSE_VAR_MAX     ; record index of the last store for each var slot

section .text

ir_pass3_dse:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14

    ; Zero bitmaps
    lea rdi, [dse_stored]
    xor eax, eax
    mov ecx, DSE_VAR_MAX / 8
    rep stosb
    lea rdi, [dse_store_idx]
    xor eax, eax
    mov ecx, DSE_VAR_MAX
    rep stosd

    xor r12, r12
.dse_loop:
    mov rax, [ir_idx]
    cmp r12, rax
    jge .dse_done
    mov rax, r12
    imul rax, IR_RECORD_SIZE
    lea r14, [ir_buffer]
    add r14, rax               ; r14 = current record ptr

    test byte [r14 + IR_OFF_FLAGS], IRF_DEAD
    jnz .dse_next

    movzx r13d, byte [r14 + IR_OFF_OP]

    cmp r13b, IR_STORE_VAR
    jne .dse_check_load

    ; STORE_VAR: var_idx in ir_imm (32-bit)
    mov r8d, [r14 + IR_OFF_IMM]   ; var index (low 32 bits)
    cmp r8d, DSE_VAR_MAX
    jge .dse_next
    ; check if already stored without load
    mov ecx, r8d
    shr ecx, 3                     ; byte index
    mov rbx, rcx                   ; save byte index
    mov edx, r8d
    and edx, 7                     ; bit index
    lea rsi, [dse_stored]
    test byte [rsi + rbx], 1
    jz .dse_no_prev_store
    ; There is a previous store that was never loaded: mark it dead
    lea rsi, [dse_store_idx]
    mov eax, [rsi + r8*4]         ; prev store record index
    imul eax, IR_RECORD_SIZE
    lea rdi, [ir_buffer]
    add rdi, rax
    or byte [rdi + IR_OFF_FLAGS], IRF_DEAD
.dse_no_prev_store:
    ; Record this store as pending
    lea rsi, [dse_stored]
    mov ecx, r8d
    shr ecx, 3
    mov edx, r8d
    and edx, 7
    lea rdi, [dse_store_idx]
    mov dword [rdi + r8*4], r12d  ; record index of this store
    ; rcx already = r8d>>3 (byte index), edx = r8d&7 (bit index)
    mov eax, 1
    mov ecx, edx
    shl eax, cl
    or [rsi + rbx], al             ; set bit; rbx = byte index saved below
    jmp .dse_next

.dse_check_load:
    cmp r13b, IR_LOAD_VAR
    jne .dse_next
    ; LOAD_VAR: clear the stored bit for this var
    mov r8d, [r14 + IR_OFF_IMM]
    cmp r8d, DSE_VAR_MAX
    jge .dse_next
    mov ebx, r8d
    shr ebx, 3                     ; rbx = byte index
    mov edx, r8d
    and edx, 7                     ; edx = bit index
    lea rsi, [dse_stored]
    mov eax, 1
    mov ecx, edx                   ; cl = bit index
    shl eax, cl
    not eax
    and [rsi + rbx], al            ; clear bit

.dse_next:
    inc r12
    jmp .dse_loop

.dse_done:
    pop r14
    pop r13
    pop r12
    leave
    ret
