; ============================================================
; rt_prc — print complex number + newline to stdout
; Input:  rdi = pointer to {real: f64, imag: f64} pair
; Output: "(real+imagj)\n" or "(real-imagj)\n"
; ============================================================
bits 64
%include "rex_defs.inc"
org LOAD_BASE + RT_PRC_OFFSET

rt_prc_blob:
    push    rbx
    push    r13
    push    r14
    sub     rsp, 8              ; 16-byte align

    mov     r13, rdi            ; save struct pointer

    ; print "("
    push    qword 0x28          ; '('
    mov     rax, SYS_write
    mov     rdi, 1
    mov     rsi, rsp
    mov     rdx, 1
    syscall
    add     rsp, 8

    ; print real part without newline
    mov     rdi, [r13]
    call    .print_f64

    ; check sign of imag
    mov     r14, [r13 + 8]      ; imag bits
    test    r14, r14
    js      .neg_imag

    ; positive imag: "+"
    push    qword 0x2b
    mov     rax, SYS_write
    mov     rdi, 1
    mov     rsi, rsp
    mov     rdx, 1
    syscall
    add     rsp, 8

    mov     rdi, r14
    call    .print_f64
    jmp     .end_imag

.neg_imag:
    ; "-"
    push    qword 0x2d
    mov     rax, SYS_write
    mov     rdi, 1
    mov     rsi, rsp
    mov     rdx, 1
    syscall
    add     rsp, 8

    btr     r14, 63             ; clear sign bit (absolute value)
    mov     rdi, r14
    call    .print_f64

.end_imag:
    ; print "j)\n" (3 bytes)
    lea     rsi, [rel .suffix]
    mov     rax, SYS_write
    mov     rdi, 1
    mov     rdx, 3
    syscall

    add     rsp, 8
    pop     r14
    pop     r13
    pop     rbx
    ret

.suffix: db "j)", 0x0a

; ---- helper: print f64 in rdi without newline ----
; prints like "3.000000"
.print_f64:
    push    rbp
    sub     rsp, 72             ; local scratch (must keep 16-byte align)
    mov     rbp, rsp

    movq    xmm0, rdi

    ; negative?
    test    rdi, rdi
    jns     .pf_pos

    ; print '-'
    push    qword 0x2d
    mov     rax, SYS_write
    mov     rdi, 1
    mov     rsi, rsp
    mov     rdx, 1
    syscall
    add     rsp, 8

    ; flip sign
    pcmpeqd xmm1, xmm1
    psllq   xmm1, 63
    pxor    xmm0, xmm1

.pf_pos:
    movq    r11, xmm0           ; save positive bits

    ; integer part
    cvttsd2si rax, xmm0
    push    rax                 ; save int part

    ; build integer digit string in scratch
    lea     r9, [rbp + 60]
    mov     byte [r9], 0
    dec     r9
    mov     rcx, rax
    test    rcx, rcx
    jnz     .pf_id
    mov     byte [r9], '0'
    dec     r9
    jmp     .pf_idone
.pf_id:
    mov     rbx, 10
.pf_il:
    xor     rdx, rdx
    mov     rax, rcx
    div     rbx
    add     dl, '0'
    mov     [r9], dl
    dec     r9
    mov     rcx, rax
    test    rcx, rcx
    jnz     .pf_il
.pf_idone:
    inc     r9
    lea     rcx, [rbp + 61]
    sub     rcx, r9
    mov     rax, SYS_write
    mov     rdi, 1
    mov     rsi, r9
    mov     rdx, rcx
    syscall

    ; '.'
    push    qword 0x2e
    mov     rax, SYS_write
    mov     rdi, 1
    mov     rsi, rsp
    mov     rdx, 1
    syscall
    add     rsp, 8

    ; fractional part × 1000000
    pop     rax
    cvtsi2sd xmm1, rax
    movq    xmm0, r11
    subsd   xmm0, xmm1
    mov     rax, 0x412E848000000000  ; 1000000.0
    movq    xmm2, rax
    mulsd   xmm0, xmm2
    cvttsd2si rax, xmm0
    cmp     rax, 999999
    jle     .pf_fok
    mov     rax, 999999
.pf_fok:
    test    rax, rax
    jns     .pf_fpos
    xor     eax, eax
.pf_fpos:
    lea     r8, [rbp + 10]      ; 6-digit buffer
    mov     r9d, 5
    mov     rbx, 10
.pf_fl:
    xor     rdx, rdx
    div     rbx
    add     dl, '0'
    mov     [r8 + r9], dl
    dec     r9d
    jns     .pf_fl
    mov     rax, SYS_write
    mov     rdi, 1
    mov     rsi, r8
    mov     rdx, 6
    syscall

    add     rsp, 72
    pop     rbp
    ret

times RT_PRC_SIZE - ($ - rt_prc_blob) db 0x90
