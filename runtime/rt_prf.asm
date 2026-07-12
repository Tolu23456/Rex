; rt_prf.asm - print float in XMM0 to stdout followed by newline
BITS 64

    push rbx
    push rbp
    push r12
    push r13
    mov rbp, rsp
    sub rsp, 64         ; Scratch buffer (aligned, room for precision at [rbp-56])

    ; Cap precision (passed in rdi) between 1 and 48
    cmp rdi, 1
    jge .prec_min_ok
    mov rdi, 1
.prec_min_ok:
    cmp rdi, 48
    jle .prec_max_ok
    mov rdi, 48
.prec_max_ok:

    ; Save precision to stack slot [rbp-56]
    mov [rbp-56], rdi

    ; Check for NaN/Inf (exponent field = 0x7FF)
    movq rax, xmm0
    mov rcx, rax
    mov rdx, [rel .mask_exp]
    and rcx, rdx
    cmp rcx, rdx
    je .print_nan_or_inf

    ; Check sign (bit-level: handles -0.0 correctly)
    test rax, rax
    jns .positive
    ; Sign bit set — check if -0.0 (only sign bit, no magnitude)
    shl rax, 1
    jz .positive            ; -0.0 → treat as positive

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
    
    ; Format exactly [rbp-56] digits
    mov r13, [rbp-56]   ; Loop counter
    lea rcx, [rbp-48]
    movsd xmm2, qword [rel .float_10]
.frac_loop:
    mulsd xmm0, xmm2    ; xmm0 = xmm0 * 10
    cvttsd2si rax, xmm0
    cmp rax, 9
    jle .digit_ok
    mov rax, 9
.digit_ok:
    test rax, rax
    jns .digit_nn
    xor rax, rax
.digit_nn:
    cvtsi2sd xmm1, rax
    subsd xmm0, xmm1    ; subtract digit
    
    add al, '0'
    mov [rcx], al
    inc rcx
    dec r13d
    jnz .frac_loop

    ; Strip trailing zeroes
    ; rsi = [rbp-48] (buffer start)
    ; rdx = original precision [rbp-56]
    lea rsi, [rbp-48]
    mov rdx, [rbp-56]
    mov rcx, rdx
.strip_loop:
    cmp rcx, 1
    jle .strip_done
    movzx eax, byte [rsi + rcx - 1]
    cmp al, '0'
    jne .strip_done
    dec rcx
    jmp .strip_loop
.strip_done:
    mov rdx, rcx

    ; Print fractional digits
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
.float_10      dq 10.0
.mask_exp      dq 0x7FF0000000000000

.print_nan_or_inf:
    ; Check if NaN (fraction bits != 0) or Inf (fraction bits == 0)
    movq rax, xmm0
    test rax, 0x000FFFFFFFFFFFFF
    jnz .print_nan
    ; Inf — check sign
    test rax, rax
    jns .print_inf_pos
    ; Print "-inf"
    mov byte [rbp-8], '-'
    mov byte [rbp-7], 'i'
    mov byte [rbp-6], 'n'
    mov byte [rbp-5], 'f'
    mov byte [rbp-4], 10
    lea rsi, [rbp-8]
    mov rdx, 5
    jmp .print_nan_inf_write
.print_inf_pos:
    mov byte [rbp-8], 'i'
    mov byte [rbp-7], 'n'
    mov byte [rbp-6], 'f'
    mov byte [rbp-5], 10
    lea rsi, [rbp-8]
    mov rdx, 4
    jmp .print_nan_inf_write
.print_nan:
    ; Print "nan"
    mov byte [rbp-8], 'n'
    mov byte [rbp-7], 'a'
    mov byte [rbp-6], 'n'
    mov byte [rbp-5], 10
    lea rsi, [rbp-8]
    mov rdx, 4
.print_nan_inf_write:
    mov rax, 1
    mov rdi, 1
    syscall
    mov rsp, rbp
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; Pad to exactly 512 bytes
times 512 - ($ - $$) db 0
