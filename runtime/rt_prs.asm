; rt_prs.asm - print null-terminated string in RDI to stdout (no newline)
BITS 64

    push rbp
    mov rbp, rsp
    
    mov rsi, rdi        ; rsi = string pointer
    test rsi, rsi
    jz .done
    
    ; Find length
    xor rdx, rdx
.len_loop:
    cmp byte [rsi + rdx], 0
    je .len_done
    inc rdx
    jmp .len_loop
.len_done:
    test rdx, rdx
    jz .done
    
    mov rax, 1          ; sys_write
    mov rdi, 1          ; stdout
    syscall

.done:
    mov rsp, rbp
    pop rbp
    ret

; Pad to exactly 512 bytes
