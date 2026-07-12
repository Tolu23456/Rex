; rt_prb.asm - print tri-state bool (RDI) to stdout followed by newline
BITS 64

    push rbp
    mov rbp, rsp

    cmp rdi, 0
    jg .print_true
    je .print_neutral

    ; print "false\n"
    lea rsi, [rel .str_false]
    mov rdx, 6
    jmp .print

.print_neutral:
    lea rsi, [rel .str_neutral]
    mov rdx, 8
    jmp .print

.print_true:
    lea rsi, [rel .str_true]
    mov rdx, 5

.print:
    mov rax, 1          ; sys_write
    mov rdi, 1          ; stdout
    syscall

    mov rsp, rbp
    pop rbp
    ret

.str_true    db "true",    10
.str_neutral db "neutral", 10
.str_false   db "false",   10

; Pad to exactly 256 bytes
times 256 - ($ - $$) db 0
