global _start
%include "include/rex_defs.inc"

section .data
    key_a db "a", 0
    key_b db "b", 0

section .bss
    outbuf resb 32

section .text
extern rt_dict_new
extern rt_dict_set
extern rt_dict_get
extern rt_dict_len

_start:
    ; Create dict with capacity 16
    mov rdi, 16
    call rt_dict_new
    mov rbx, rax    ; rbx = dict ptr

    ; d["a"] = 10
    mov rdi, rbx
    lea rsi, [key_a]
    mov rdx, 10
    call rt_dict_set

    ; d["b"] = 20
    mov rdi, rbx
    lea rsi, [key_b]
    mov rdx, 20
    call rt_dict_set

    ; d["a"]
    mov rdi, rbx
    lea rsi, [key_a]
    call rt_dict_get
    ; rax should be 10
    mov r12, rax

    ; d["b"]
    mov rdi, rbx
    lea rsi, [key_b]
    call rt_dict_get
    ; rax should be 20
    mov r13, rax

    ; print r12 (should be 10)
    mov rdi, r12
    call print_int
    ; print newline
    mov rax, 1
    mov rdi, 1
    lea rsi, [newline]
    mov rdx, 1
    syscall

    ; print r13 (should be 20)
    mov rdi, r13
    call print_int
    ; print newline
    mov rax, 1
    mov rdi, 1
    lea rsi, [newline]
    mov rdx, 1
    syscall

    ; exit
    mov rax, 60
    xor rdi, rdi
    syscall

print_int:
    ; rdi = integer to print
    push rbx
    mov rax, rdi
    lea rbx, [outbuf + 20]
    mov byte [rbx], 0
    dec rbx
    mov rcx, 10
.digit_loop:
    xor rdx, rdx
    div rcx
    add dl, '0'
    mov [rbx], dl
    dec rbx
    test rax, rax
    jnz .digit_loop
    inc rbx
    ; write
    mov rax, 1
    mov rdi, 1
    mov rsi, rbx
    lea rdx, [outbuf + 20]
    sub rdx, rbx
    syscall
    pop rbx
    ret

section .rodata
    newline db 10
