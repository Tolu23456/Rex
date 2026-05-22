section .data
    msg db 'Rex is alive.', 0xA
    len equ $ - msg

section .text
    global _start

_start:
    ; sys_write(stdout, msg, len)
    mov rax, 1          ; syscall number for sys_write
    mov rdi, 1          ; file descriptor 1 is stdout
    mov rsi, msg        ; pointer to the message
    mov rdx, len        ; length of the message
    syscall

    ; sys_exit(0)
    mov rax, 60         ; syscall number for sys_exit
    xor rdi, rdi        ; exit code 0
    syscall
