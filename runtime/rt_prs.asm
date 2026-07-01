; ============================================================
; rt_prs — print null-terminated UTF-8 string + newline to stdout
; Input:  rdi = pointer to null-terminated string
; Output: string bytes + 0x0a to fd 1
; Clobbers: rax, rcx, rdx, rsi, rdi
; Preserves: rbx, rbp, r12–r15
; ============================================================
bits 64
%include "rex_defs.inc"
org LOAD_BASE + RT_PRS_OFFSET

rt_prs_blob:
    push    r12
    mov     r12, rdi            ; save string pointer (callee-saved)

    ; find length with repne scasb
    mov     rdi, r12
    xor     eax, eax
    mov     rcx, -1
    repne   scasb
    not     rcx
    dec     rcx                 ; rcx = strlen (without NUL)

    ; write string
    mov     rax, 1              ; SYS_write
    mov     rdi, 1              ; stdout
    mov     rsi, r12
    mov     rdx, rcx
    syscall

    ; write '\n'
    push    qword 0x0a          ; newline on stack
    mov     rax, 1
    mov     rdi, 1
    mov     rsi, rsp
    mov     rdx, 1
    syscall
    add     rsp, 8

    pop     r12
    ret

times RT_PRS_SIZE - ($ - rt_prs_blob) db 0x90
