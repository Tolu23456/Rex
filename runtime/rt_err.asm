; rt_err.asm - Rex runtime: abort with message
; Input:  rdi = pointer to null-terminated message string
; Output: writes message to stderr (fd 2) and exits with code 1
; Preserves: all callee-saved regs (used as a terminator, never returns)
BITS 64

rt_abort:
    push rbx
    push r12
    mov rbx, rdi        ; rbx = msg ptr
    xor r12, r12        ; r12 = length
.len_loop:
    cmp byte [rbx + r12], 0
    je .len_done
    inc r12
    jmp .len_loop
.len_done:
    mov rax, 1          ; SYS_write
    mov rdi, 2          ; fd = stderr
    mov rsi, rbx
    mov rdx, r12
    syscall
    mov rax, 60         ; SYS_exit
    mov rdi, 1          ; exit code 1
    syscall
    pop r12
    pop rbx
    ret
