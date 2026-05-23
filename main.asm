; main.asm - Entry point for Rex Compiler (rexc)

%include "include/common.inc"

section .data
    usage_msg db "Usage: rexc <file.rex>", 10, 0
    usage_len equ $ - usage_msg

section .bss
    file_fd resq 1
    file_buf resb 65536
    file_len resq 1

section .text
    global _start
    extern rex_parse

_start:
    ; Check argc
    pop rax
    cmp rax, 2
    jl .usage

    pop rax ; program name
    pop rdi ; filename

    ; Open file
    mov rax, SYS_OPEN
    mov rsi, O_RDONLY
    syscall
    test rax, rax
    js .error
    mov [file_fd], rax

    ; Read file
    mov rdi, rax
    mov rax, SYS_READ
    mov rsi, file_buf
    mov rdx, 65536
    syscall
    mov [file_len], rax

    ; Parse and Compile
    mov rdi, file_buf
    mov rsi, rax
    call rex_parse

    ; Exit
    mov rax, SYS_EXIT
    xor rdi, rdi
    syscall

.usage:
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, usage_msg
    mov rdx, usage_len
    syscall
    mov rax, SYS_EXIT
    mov rdi, 1
    syscall

.error:
    mov rax, SYS_EXIT
    mov rdi, 1
    syscall
