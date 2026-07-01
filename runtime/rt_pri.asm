; ============================================================
; rt_pri — print signed int64 + newline to stdout (buffered)
; Input:  rdi = signed 64-bit integer
; Output: decimal digits + 0x0a to stdout output buffer
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
    mov     rsi, r8             ; "0\n"
    mov     edx, 2
    call    .buf_write
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
    mov     rsi, r8
    mov     rdx, rcx
    call    .buf_write
    add     rsp, 24
    pop     rbx
    ret

.print_min:
    add     rsp, 24
    lea     rsi, [rel .min_str]
    mov     edx, 21
    call    .buf_write
    pop     rbx
    ret

.min_str:
    db "-9223372036854775808", 0x0a

; ============================================================
; .buf_write(rsi=str, rdx=len): write rdx bytes from rsi into
;   the output buffer, flushing to stdout first if needed.
; Clobbers: rax, rcx, rdi  Preserves: rbx, rsi, rdx, r8–r15
; ============================================================
.buf_write:
    ; Load current write pointer
    mov     eax, dword [OUTPUT_BUF_WPTR]
    ; Check space: eax + rdx > 4095 → flush first
    lea     ecx, [eax + edx]           ; ecx = new wptr (rdx ≤ 22, no overflow)
    cmp     ecx, 4095
    jg      .bw_flush
.bw_copy:
    ; Dest = OUTPUT_BUF_BASE + eax (eax = current wptr)
    mov     rdi, OUTPUT_BUF_BASE
    add     rdi, rax
    mov     rcx, rdx                   ; length
    push    rsi
    rep     movsb                      ; copies [rsi..rsi+rcx) → [rdi..)
    pop     rsi
    ; Update write pointer to ecx (= old wptr + rdx, or rdx after flush)
    mov     dword [OUTPUT_BUF_WPTR], ecx
    ret
.bw_flush:
    ; Flush buffer: write current contents to stdout
    test    eax, eax
    jz      .bw_empty
    push    rsi
    push    rdx
    mov     rdx, rax                   ; bytes to flush
    mov     rax, 1                     ; SYS_write
    mov     rdi, 1                     ; stdout fd
    mov     rsi, OUTPUT_BUF_BASE
    syscall
    pop     rdx
    pop     rsi
.bw_empty:
    xor     eax, eax                   ; wptr = 0 after flush
    mov     dword [OUTPUT_BUF_WPTR], eax
    mov     ecx, edx                   ; new wptr after copy = 0 + rdx = rdx
    jmp     .bw_copy

times RT_PRI_SIZE - ($ - rt_pri_blob) db 0x90
