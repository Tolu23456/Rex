; rt_prb.asm - print tri-state bool (RDI) to stdout followed by newline
BITS 64

    push rbx
    push rbp
    mov rbp, rsp

    cmp rdi, 0
    jg .print_true
    je .print_neutral

    ; print "false"
    mov rsi, .str_false
    mov rdx, 6
    jmp .print
    
.print_neutral:
    mov rsi, .str_neutral
    mov rdx, 8
    jmp .print

.print_true:
    mov rsi, .str_true
    mov rdx, 5

.print:
    mov rax, 1          ; sys_write
    mov rdi, 1          ; stdout
    syscall

    mov rsp, rbp
    pop rbp
    ret

; Pad to exactly 256 bytes
times 256 - ($ - $$) db 0

section .rodata
    .str_true db "true", 10
    .str_neutral db "neutral", 10
    .str_false db "false", 10

