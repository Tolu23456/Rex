; ============================================================
; rt_str — convert int64 / bool → null-terminated decimal string
; Entry:
;   rt_str_blob      (byte 0)   : rdi = int64  → rax = ptr
;   rt_str_bool_blob (byte 128) : rdi = bool   → rax = ptr to
;                                                 "true"/"neutral"/"false"
; Ring buffer: STR_RING_BASE (8 slots × 32 bytes), index at STR_RING_IDX
; ============================================================
bits 64
%include "rex_defs.inc"
org LOAD_BASE + RT_STR_OFFSET

rt_str_blob:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi                    ; save value

    ; Advance ring index (0–7)
    mov     rax, STR_RING_IDX
    movzx   ebx, byte [rax]
    mov     r14d, ebx                   ; current slot index
    inc     bl
    and     bl, 7
    mov     [rax], bl

    ; Slot address = STR_RING_BASE + r14 * 32
    imul    r14d, r14d, 32
    mov     r13, STR_RING_BASE
    add     r13, r14                    ; r13 = 32-byte slot

    ; Handle negative
    xor     r15, r15
    test    r12, r12
    jns     .pos
    neg     r12
    inc     r15
.pos:
    ; NUL at slot[31]
    mov     byte [r13 + 31], 0

    ; Write digits right-to-left from slot[30]
    lea     rbx, [r13 + 30]

    test    r12, r12
    jnz     .digits
    mov     byte [rbx], '0'
    dec     rbx
    jmp     .sign

.digits:
    test    r12, r12
    jz      .sign
    mov     rax, r12
    xor     edx, edx
    mov     rcx, 10
    div     rcx
    mov     r12, rax
    add     dl, '0'
    mov     [rbx], dl
    dec     rbx
    jmp     .digits

.sign:
    test    r15, r15
    jz      .ret
    mov     byte [rbx], '-'
    dec     rbx

.ret:
    lea     rax, [rbx + 1]

    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- Pad to byte 160 so rt_str_bool_blob has a fixed address ----
times 160 - ($ - rt_str_blob) db 0x90

; ---- bool → string (at fixed byte 128) -------------------------
rt_str_bool_blob:
    cmp     rdi, 1
    je      .is_true
    test    rdi, rdi
    jz      .is_neutral
    mov     rax, LOAD_BASE + RT_STR_OFFSET + (rt_str_s_false - rt_str_blob)
    ret
.is_neutral:
    mov     rax, LOAD_BASE + RT_STR_OFFSET + (rt_str_s_neutral - rt_str_blob)
    ret
.is_true:
    mov     rax, LOAD_BASE + RT_STR_OFFSET + (rt_str_s_true - rt_str_blob)
    ret

rt_str_s_false:   db "false", 0
rt_str_s_neutral: db "neutral", 0
rt_str_s_true:    db "true", 0

times RT_STR_SIZE - ($ - rt_str_blob) db 0x90
