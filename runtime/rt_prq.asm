; rt_prq.asm - print null-terminated error in RDI to stderr, then exit 1
BITS 64

    mov rsi, rdi        ; error string pointer
    test rsi, rsi
    jz .exit
    
    ; Find length
    xor rdx, rdx
.len_loop:
    cmp byte [rsi + rdx], 0
    je .len_done
    inc rdx
    jmp .len_loop
.len_done:
    test rdx, rdx
    jz .exit
    
    mov rax, 1          ; sys_write
    mov rdi, 2          ; stderr
    syscall
    
    ; Print newline
    sub rsp, 8
    mov byte [rsp], 10
    mov rsi, rsp
    mov rdx, 1
    mov rax, 1          ; sys_write
    mov rdi, 2          ; stderr
    syscall
    add rsp, 8

.exit:
    mov rax, 60         ; sys_exit
    mov rdi, 1          ; exit code 1
    syscall

; Pad to exactly 1024 bytes

