; rt_pri_min.asm - minimal print integer in RDI to stdout + newline
BITS 64

    push rbx
    push rbp
    mov rbp, rsp
    sub rsp, 32

    mov rax, rdi
    test rax, rax
    jge .positive

    ; Print negative sign
    push rax
    mov byte [rbp-1], '-'
    lea rsi, [rbp-1]
    mov edx, 1
    mov eax, 1
    mov edi, 1
    syscall
    pop rax
    neg rax

.positive:
    mov ebx, 10
    lea rcx, [rbp-1]

.loop:
    xor edx, edx
    div rbx
    add dl, '0'
    mov [rcx], dl
    dec rcx
    test rax, rax
    jnz .loop

    inc rcx
    lea rdx, [rbp-1]
    sub rdx, rcx
    inc rdx

    mov rsi, rcx
    mov eax, 1
    mov edi, 1
    syscall

    ; Print newline
    mov byte [rbp-1], 10
    lea rsi, [rbp-1]
    mov edx, 1
    mov eax, 1
    mov edi, 1
    syscall

    mov rsp, rbp
    pop rbp
    pop rbx
    ret
