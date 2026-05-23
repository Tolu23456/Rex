; types.asm - Rex Data Types and Operations
; Handles strings, sequences, dictionaries, sets, and complex numbers

section .data
    newline db 10
    int_buf db "00000000000000000000", 0 ; Buffer for int to string

section .text
    global rex_print_str
    global rex_print_int
    global rex_print_newline
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

; Print an integer in RAX
rex_print_int:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    mov rbx, 10
    lea rdi, [int_buf + 19] ; Start from end
    mov byte [rdi], 0       ; Null terminator (not needed for write but good)

.loop:
    xor rdx, rdx
    div rbx
    add dl, '0'
    dec rdi
    mov [rdi], dl
    test rax, rax
    jnz .loop

    ; Write out the string
    mov rsi, rdi
    lea rdx, [int_buf + 19]
    sub rdx, rsi
    mov rax, 1
    mov rdi, 1
    syscall

    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

rex_print_newline:
    mov rax, 1
    mov rdi, 1
    mov rsi, newline
    mov rdx, 1
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
