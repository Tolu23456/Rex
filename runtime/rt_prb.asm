; rt_prb.asm - print tri-state bool (RDI) to stdout (no newline)
BITS 64

    push rbp
    mov rbp, rsp

    cmp rdi, 0
    jg .print_true
    je .print_neutral

    ; print "false"
    lea rsi, [rel .str_false]
    mov rdx, 5
    jmp .print

.print_neutral:
    lea rsi, [rel .str_neutral]
    mov rdx, 7
    jmp .print

.print_true:
    lea rsi, [rel .str_true]
    mov rdx, 4

.print:
    mov rax, 1          ; sys_write
    mov rdi, 1          ; stdout
    syscall

    mov rsp, rbp
    pop rbp
    ret

.str_true    db "true"
.str_neutral db "neutral"
.str_false   db "false"

; Pad to exactly 256 bytes
