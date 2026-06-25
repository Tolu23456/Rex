; ============================================================
; rt_inp — read one line from stdin, return pointer to it
; Input:  rdi = pointer to prompt string (0 = no prompt)
; Output: rax = pointer to NUL-terminated line (INPUT_BUF_BASE)
;         trailing newline stripped
; Uses:   INPUT_BUF_BASE (4096-byte static buffer)
; ============================================================
bits 64
%include "rex_defs.inc"
org LOAD_BASE + RT_INP_OFFSET

rt_inp_blob:
    push    rbx
    push    r12

    mov     r12, rdi                    ; save prompt pointer

    ; Print prompt if given (no trailing newline)
    test    r12, r12
    jz      .no_prompt

    ; strlen(r12)
    xor     ecx, ecx
.strlen:
    cmp     byte [r12 + rcx], 0
    je      .strlen_done
    inc     ecx
    jmp     .strlen
.strlen_done:
    test    ecx, ecx
    jz      .no_prompt

    mov     rax, 1                      ; SYS_write
    mov     edi, 1                      ; stdout
    mov     rsi, r12
    mov     rdx, rcx
    syscall

.no_prompt:
    ; Read from stdin into INPUT_BUF_BASE
    mov     rax, 0                      ; SYS_read
    xor     edi, edi                    ; stdin fd = 0
    mov     rsi, INPUT_BUF_BASE
    mov     rdx, INPUT_BUF_MAX
    syscall

    ; Handle empty read (EOF / error)
    test    rax, rax
    jle     .empty

    ; rax = bytes read
    mov     rbx, INPUT_BUF_BASE
    mov     rcx, rax

    ; Strip trailing newline
    cmp     byte [rbx + rcx - 1], 0x0a
    jne     .nul
    dec     rcx

.nul:
    mov     byte [rbx + rcx], 0         ; NUL-terminate
    mov     rax, INPUT_BUF_BASE
    pop     r12
    pop     rbx
    ret

.empty:
    mov     byte [INPUT_BUF_BASE], 0    ; empty string
    mov     rax, INPUT_BUF_BASE
    pop     r12
    pop     rbx
    ret

times RT_INP_SIZE - ($ - rt_inp_blob) db 0x90
