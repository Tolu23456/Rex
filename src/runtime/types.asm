; types.asm - Rex Data Types and Operations
; Handles strings, sequences, dictionaries, sets, and complex numbers

section .text
    global rex_print_str
    global rex_complex_add

; Print a UTF-8 length-prefixed string
; RDI = pointer to string structure (length-prefixed)
rex_print_str:
    mov rsi, [rdi]      ; First 8 bytes is length
    lea rsi, [rdi + 8]  ; Data starts after length
    mov rdx, [rdi]      ; Length
    mov rax, 1          ; SYS_WRITE
    mov rdi, 1          ; STDOUT
    syscall
    ret

; Complex addition
; XMM0, XMM1 = real1, imag1
; XMM2, XMM3 = real2, imag2
; Returns XMM0, XMM1 = result real, imag
rex_complex_add:
    addsd xmm0, xmm2
    addsd xmm1, xmm3
    ret
