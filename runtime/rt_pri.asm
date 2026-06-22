; ============================================================
; rt_pri — print signed int64 + newline to stdout
; Input:  rdi = signed 64-bit integer
; Output: decimal digits + 0x0a to fd 1
; Clobbers: rax, rcx, rdx, rsi, rdi, r8, r9, r10
; Preserves: rbx, rbp, r12–r15
; ============================================================
bits 64
%include "rex_defs.inc"
org LOAD_BASE + RT_PRI_OFFSET

rt_pri_blob:
    push    rbx

    mov     rax, rdi            ; working copy
    sub     rsp, 24             ; digit buffer: 21 bytes max + newline
    lea     r8,  [rsp+22]       ; r8 → last slot (will hold '\n')
    mov     byte [r8], 0x0a     ; '\n'
    dec     r8                  ; r8 → slot before '\n'

    ; ---- zero? ----
    test    rax, rax
    jnz     .nonzero
    mov     byte [r8], '0'
    mov     rax, 1
    mov     rdi, 1              ; stdout
    mov     rsi, r8
    mov     rdx, 2              ; '0' '\n'
    syscall
    add     rsp, 24
    pop     rbx
    ret

.nonzero:
    ; ---- INT64_MIN? ----
    mov     r9,  0x8000000000000000
    cmp     rax, r9
    je      .print_min

    ; ---- sign ----
    xor     r10, r10
    test    rax, rax
    jns     .convert
    mov     r10, 1
    neg     rax

.convert:
    mov     rbx, 10
.digit_loop:
    xor     rdx, rdx
    div     rbx                 ; rax = q, rdx = remainder
    add     dl, '0'
    mov     [r8], dl
    dec     r8
    test    rax, rax
    jnz     .digit_loop

    ; prepend '-' if negative
    test    r10, r10
    jz      .write
    mov     byte [r8], '-'
    dec     r8

.write:
    inc     r8                  ; start of string
    lea     rcx, [rsp+23]       ; one past '\n'
    sub     rcx, r8             ; length
    mov     rax, 1
    mov     rdi, 1
    mov     rsi, r8
    mov     rdx, rcx
    syscall
    add     rsp, 24
    pop     rbx
    ret

.print_min:
    add     rsp, 24
    lea     rsi, [rel .min_str]
    mov     rax, 1
    mov     rdi, 1
    mov     rdx, 21
    syscall
    pop     rbx
    ret

.min_str:
    db "-9223372036854775808", 0x0a

times RT_PRI_SIZE - ($ - rt_pri_blob) db 0x90
