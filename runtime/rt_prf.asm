; rt_prf.asm - print float in XMM0 to stdout followed by newline
BITS 64

    push rbx
    push rbp
    push r12
    push r13
    mov rbp, rsp
    sub rsp, 48         ; Scratch buffer

    ; Check sign
    xorpd xmm1, xmm1
    ucomisd xmm0, xmm1
    jae .positive
    jp .positive        ; if NaN, treat as positive for now

    ; Print minus sign '-'
    movapd xmm2, xmm0   ; Save xmm0
    mov rax, 1          ; sys_write
    mov rdi, 1          ; stdout
    mov byte [rbp-1], '-'
    lea rsi, [rbp-1]
    mov rdx, 1
    syscall
    movapd xmm0, xmm2
    
    ; Negate xmm0
    movsd xmm1, qword [rel .float_neg_one]
    mulsd xmm0, xmm1

.positive:
    ; Convert whole part to integer
    cvttsd2si r12, xmm0 ; r12 = whole part
    
    ; Print whole part (same logic as rt_pri)
    mov rax, r12
    mov rbx, 10
    lea rcx, [rbp-1]
.whole_loop:
    xor rdx, rdx
    div rbx
    add dl, '0'
    mov [rcx], dl
    dec rcx
    test rax, rax
    jnz .whole_loop
    
    inc rcx
    lea rdx, [rbp-1]
    sub rdx, rcx
    inc rdx             ; len
    mov rsi, rcx
    mov rax, 1          ; sys_write
    mov rdi, 1          ; stdout
    syscall

    ; Print '.'
    mov byte [rbp-1], '.'
    lea rsi, [rbp-1]
    mov rdx, 1
    mov rax, 1
    mov rdi, 1
    syscall

    ; Get fractional part
    cvtsi2sd xmm1, r12
    subsd xmm0, xmm1    ; xmm0 = fractional part (0 <= xmm0 < 1)
    
    ; Multiply by 1,000,000
    mulsd xmm0, qword [rel .float_1m]
    cvttsd2si rax, xmm0 ; rax = fractional part as integer (0 <= rax < 1,000,000)

    ; Format exactly 6 digits with leading zeros
    mov rbx, 10
    lea rcx, [rbp-1]
    mov r13d, 6         ; 6 digits
.frac_loop:
    xor rdx, rdx
    div rbx
    add dl, '0'
    mov [rcx], dl
    dec rcx
    dec r13d
    jnz .frac_loop

    ; Print 6 fractional digits
    inc rcx
    mov rsi, rcx
    mov rdx, 6
    mov rax, 1          ; sys_write
    mov rdi, 1          ; stdout
    syscall

    ; Print newline
    mov byte [rbp-1], 10
    lea rsi, [rbp-1]
    mov rdx, 1
    mov rax, 1          ; sys_write
    mov rdi, 1          ; stdout
    syscall

    mov rsp, rbp
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

.float_neg_one dq -1.0
.float_1m      dq 1000000.0

; Pad to exactly 512 bytes
times 512 - ($ - $$) db 0
