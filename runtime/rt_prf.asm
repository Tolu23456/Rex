; ============================================================
; rt_prf — print IEEE-754 double + newline to stdout
; Input:  rdi = 64-bit float bit pattern
; Output: decimal representation (6 fractional digits) + '\n'
; Clobbers: rax, rbx, rcx, rdx, rsi, rdi, r8–r11, xmm0–xmm3
; Preserves: rbp, r12–r15
; ============================================================
bits 64
%include "rex_defs.inc"
org LOAD_BASE + RT_PRF_OFFSET

rt_prf_blob:
    push    rbx
    sub     rsp, 80             ; scratch: digits area

    movq    xmm0, rdi           ; xmm0 = float value

    ; handle sign
    test    rdi, rdi
    jns     .positive

    ; negative: print '-'
    push    qword 0x2d
    mov     rax, SYS_write
    mov     rdi, 1
    mov     rsi, rsp
    mov     rdx, 1
    syscall
    add     rsp, 8

    ; flip sign bit
    pcmpeqd xmm1, xmm1
    psllq   xmm1, 63
    pxor    xmm0, xmm1

.positive:
    push    rax                 ; save float bits on stack (syscall-safe)
    movq    [rsp], xmm0        ; store float bits at top of stack (overwrite the push)

    ; --- print integer part ---
    cvttsd2si rax, xmm0         ; truncate toward zero → integer part
    push    rax                 ; save integer part (8 bytes on stack)

    ; build integer digit string right-to-left in scratch
    lea     r9, [rsp + 72]      ; end of scratch buffer
    mov     byte [r9], 0        ; sentinel NUL
    dec     r9

    mov     rcx, rax
    test    rcx, rcx
    jnz     .int_digits
    ; zero
    mov     byte [r9], '0'
    dec     r9
    jmp     .int_done

.int_digits:
    mov     rbx, 10
.int_loop:
    xor     rdx, rdx
    mov     rax, rcx
    div     rbx                 ; rax = q, rdx = remainder
    add     dl, '0'
    mov     [r9], dl
    dec     r9
    mov     rcx, rax
    test    rcx, rcx
    jnz     .int_loop

.int_done:
    inc     r9                  ; r9 = first digit
    lea     rcx, [rsp + 73]     ; one past NUL
    sub     rcx, r9             ; length
    mov     rax, SYS_write
    mov     rdi, 1
    mov     rsi, r9
    mov     rdx, rcx
    syscall

    ; --- print '.' ---
    push    qword 0x2e
    mov     rax, SYS_write
    mov     rdi, 1
    mov     rsi, rsp
    mov     rdx, 1
    syscall
    add     rsp, 8

    ; --- compute fractional part × 1000000 ---
    pop     rax                 ; integer part
    cvtsi2sd xmm1, rax         ; xmm1 = float(int_part)
    movq    xmm0, [rsp]        ; restore positive float from stack
    add     rsp, 8             ; clean up saved float bits
    subsd   xmm0, xmm1          ; xmm0 = frac part (0 ≤ frac < 1)

    ; multiply by 1000000.0
    mov     rax, 0x412E848000000000  ; IEEE-754 bits for 1000000.0
    movq    xmm2, rax
    mulsd   xmm0, xmm2
    cvttsd2si rax, xmm0         ; integer 0..999999

    ; clamp to valid range
    test    rax, rax
    jns     .frac_pos
    xor     eax, eax
.frac_pos:
    cmp     rax, 999999
    jle     .frac_ok
    mov     rax, 999999
.frac_ok:

    ; write 6 digits right-to-left into a 7-byte buffer [digit0..digit5, '\n']
    lea     r8, [rsp + 50]
    mov     byte [r8 + 6], 0x0a     ; '\n' at position 6
    mov     r9d, 5
    mov     rbx, 10
.frac_loop:
    xor     rdx, rdx
    div     rbx
    add     dl, '0'
    mov     [r8 + r9], dl
    dec     r9d
    jns     .frac_loop

    ; write 7 bytes (6 digits + '\n')
    mov     rax, SYS_write
    mov     rdi, 1
    mov     rsi, r8
    mov     rdx, 7
    syscall

    add     rsp, 80
    pop     rbx
    ret

times RT_PRF_SIZE - ($ - rt_prf_blob) db 0x90
