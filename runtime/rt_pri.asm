; rt_pri.asm - print integer in RDI to stdout followed by newline
BITS 64

    push rbx
    push rbp
    mov rbp, rsp
    sub rsp, 32         ; 32-byte scratch buffer for string conversion

    mov rax, rdi
    cmp rax, 0
    jge .positive

    ; Check for INT64_MIN (negation would overflow)
    mov rcx, rax
    cmp rcx, -0x8000000000000000
    jne .not_min
    ; INT64_MIN: print directly from constant
    lea rsi, [rel .str_min]
    mov rdx, 20
    push rax
    mov rax, 1
    mov rdi, 1
    syscall
    pop rax
    jmp .print_newline
.not_min:

    ; Print negative sign '-'
    push rax
    mov rax, 1          ; sys_write
    mov rdi, 1          ; stdout
    mov byte [rbp-1], '-'
    lea rsi, [rbp-1]
    mov rdx, 1
    syscall
    pop rax
    neg rax

.positive:
    mov rbx, 10
    lea rcx, [rbp-1]    ; Start writing from end of buffer

.loop:
    xor rdx, rdx
    div rbx
    add dl, '0'
    mov [rcx], dl
    dec rcx
    test rax, rax
    jnz .loop

    ; Print digits
    inc rcx             ; Points to first digit
    lea rdx, [rbp-1]
    sub rdx, rcx
    inc rdx             ; rdx = string length

    mov rsi, rcx        ; rsi = buffer pointer
    mov rax, 1          ; sys_write
    mov rdi, 1          ; stdout
    syscall

.print_newline:
    ; Print newline
    mov byte [rbp-1], 10
    lea rsi, [rbp-1]
    mov rdx, 1
    mov rax, 1          ; sys_write
    mov rdi, 1          ; stdout
    syscall

    mov rsp, rbp
    pop rbp
    pop rbx
    ret

.str_min db "-9223372036854775808"

; Pad to exactly 512 bytes

