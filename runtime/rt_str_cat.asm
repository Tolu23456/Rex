; ============================================================
; rt_str_cat — concatenate two null-terminated strings
; Entry (byte 0): rdi = ptr1, rsi = ptr2 → rax = new ptr
; Allocates via rt_alc; returns 0 on OOM.
; ============================================================
bits 64
%include "rex_defs.inc"
org LOAD_BASE + RT_STR_CAT_OFFSET

rt_str_cat_blob:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi            ; ptr1
    mov     r13, rsi            ; ptr2

    ; strlen(ptr1) → r14
    xor     r14, r14
.len1:
    cmp     byte [r12 + r14], 0
    je      .done1
    inc     r14
    jmp     .len1
.done1:
    ; strlen(ptr2) → r15
    xor     r15, r15
.len2:
    cmp     byte [r13 + r15], 0
    je      .done2
    inc     r15
    jmp     .len2
.done2:
    ; alloc len1 + len2 + 1
    lea     rdi, [r14 + r15 + 1]
    call    LOAD_BASE + RT_ALC_OFFSET
    test    rax, rax
    jz      .fail

    mov     rbx, rax            ; rbx = new buffer

    ; copy ptr1 into [rbx + 0..r14-1]
    xor     rcx, rcx
.copy1:
    cmp     rcx, r14
    je      .copy1_done
    movzx   edx, byte [r12 + rcx]
    mov     [rbx + rcx], dl
    inc     rcx
    jmp     .copy1
.copy1_done:
    ; copy ptr2 into [rbx + r14 .. r14+r15-1]
    ; Use rax as destination pointer = rbx + r14
    lea     rax, [rbx + r14]
    xor     rcx, rcx
.copy2:
    cmp     rcx, r15
    je      .copy2_done
    movzx   edx, byte [r13 + rcx]
    mov     [rax + rcx], dl
    inc     rcx
    jmp     .copy2
.copy2_done:
    ; NUL terminator at [rbx + r14 + r15]
    lea     rax, [rbx + r14]
    add     rax, r15
    mov     byte [rax], 0
    mov     rax, rbx
.fail:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

times RT_STR_CAT_SIZE - ($ - rt_str_cat_blob) db 0x90
