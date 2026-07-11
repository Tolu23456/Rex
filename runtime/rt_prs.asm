; rt_prs.asm - print null-terminated string in RDI to stdout followed by newline
BITS 64

    push rbx
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
    jz .newline
    
    mov rax, 1          ; sys_write
    mov rdi, 1          ; stdout
    syscall
    
.newline:
    sub rsp, 8
    mov byte [rsp], 10
    mov rsi, rsp
    mov rdx, 1
    mov rax, 1          ; sys_write
    mov rdi, 1          ; stdout
    syscall
    add rsp, 8

.done:
    mov rsp, rbp
    pop rbp
    ret

; Pad to exactly 512 bytes
times 512 - ($ - $$) db 0

