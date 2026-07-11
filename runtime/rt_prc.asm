; rt_prc.asm — Rex runtime: print char
; Input:  rdi = character value (lower byte used)
; Output: writes 1 byte to stdout (fd 1)
; Preserves: all callee-saved regs
bits 64
    push rdi               ; char on stack (8 bytes, use 1)
    mov  eax, 1            ; SYS_write = 1
    mov  edi, 1            ; fd = stdout
    mov  rsi, rsp          ; buf = &char on stack
    mov  edx, 1            ; count = 1
    syscall
    pop  rdi               ; restore stack
    ret
