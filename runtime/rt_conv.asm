; rt_conv.asm — integer to string conversion runtime functions for Rex compiler
; Flat binary blob (BITS 64, no ELF headers)
;
; Calling convention (SysV AMD64):
;   Int args:   rdi = value
;   Returns:    rax = pointer to null-terminated string in a static buffer
;               (buffer is 72 bytes, enough for 64-bit binary representation)
;
; Functions (offsets from start of blob):
;   rt_conv_to_bin — rdi → rax (binary string, e.g. "1010")
;   rt_conv_to_hex — rdi → rax (hex string, e.g. "ff")
;   rt_conv_to_oct — rdi → rax (octal string, e.g. "77")

BITS 64
default rel                     ; all memory refs are RIP-relative

; rt_conv_alloc: allocate a fresh 96-byte zero-initialized buffer via brk
; (two-step: brk(0) to learn the frontier, then brk(base+96)). Every
; conversion allocates its OWN buffer so results never alias each other.
; Input:  none
; Output: rax = buffer pointer
; Clobbers: rax, rcx, rdi, r8, r11 (SysV caller-saved)
rt_conv_alloc:
    mov rax, 12         ; sys_brk
    xor rdi, rdi
    syscall
    mov r8, rax         ; r8 = current brk (syscall does not clobber r8)
    lea rdi, [r8 + 96]
    mov rax, 12
    syscall
    mov rax, r8
    ret

; ──────────────────────────────────────────────────────────────
; rt_conv_to_bin: convert integer to binary string
; Input:  rdi = integer value (signed 64-bit)
; Output: rax = pointer to null-terminated string (fresh buffer)
; ──────────────────────────────────────────────────────────────
rt_conv_to_bin:
    push rbx
    push rcx
    push rdx
    push rdi

    call rt_conv_alloc
    lea rbx, [rax + 65] ; end of buffer
    mov byte [rbx], 0           ; null terminator
    pop rdi
    push rdi
    mov rax, rdi

    ; Work with the magnitude (matches to_dec semantics)
    test rax, rax
    jns .bin_mag
    neg rax
.bin_mag:
    ; Handle zero specially
    test rax, rax
    jnz .bin_loop
    dec rbx
    mov byte [rbx], '0'
    mov rax, rbx
    jmp .bin_done

.bin_loop:
    test rax, rax
    jz .bin_sign
    mov rcx, rax
    and rcx, 1                  ; bit = value & 1
    add cl, '0'
    dec rbx
    mov [rbx], cl
    shr rax, 1                  ; unsigned shift right
    jmp .bin_loop

.bin_sign:
    ; Check if original value was negative
    pop rdi
    push rdi
    test rdi, rdi
    jns .bin_result
    dec rbx
    mov byte [rbx], '-'

.bin_result:
    mov rax, rbx

.bin_done:
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    ret

; ──────────────────────────────────────────────────────────────
; rt_conv_to_hex: convert integer to hexadecimal string
; Input:  rdi = integer value (signed 64-bit)
; Output: rax = pointer to null-terminated string
; ──────────────────────────────────────────────────────────────
rt_conv_to_hex:
    push rbx
    push rcx
    push rdx
    push rdi

    call rt_conv_alloc
    lea rbx, [rax + 17] ; end: 16 hex digits + null
    mov byte [rbx], 0
    pop rdi
    push rdi
    mov rax, rdi

    ; Work with the magnitude (matches to_dec semantics)
    test rax, rax
    jns .hex_mag
    neg rax
.hex_mag:
    ; Handle zero specially
    test rax, rax
    jnz .hex_loop
    dec rbx
    mov byte [rbx], '0'
    mov rax, rbx
    jmp .hex_done

.hex_loop:
    test rax, rax
    jz .hex_sign
    mov rcx, rax
    and rcx, 0xF                ; nibble = value & 0xF
    cmp cl, 10
    jl .hex_digit
    add cl, 'a' - 10
    jmp .hex_store
.hex_digit:
    add cl, '0'
.hex_store:
    dec rbx
    mov [rbx], cl
    shr rax, 4                  ; unsigned shift right
    jmp .hex_loop

.hex_sign:
    pop rdi
    push rdi
    test rdi, rdi
    jns .hex_result
    dec rbx
    mov byte [rbx], '-'

.hex_result:
    mov rax, rbx

.hex_done:
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    ret

; ──────────────────────────────────────────────────────────────
; rt_conv_to_oct: convert integer to octal string
; Input:  rdi = integer value (signed 64-bit)
; Output: rax = pointer to null-terminated string
; ──────────────────────────────────────────────────────────────
rt_conv_to_oct:
    push rbx
    push rcx
    push rdx
    push rdi

    call rt_conv_alloc
    lea rbx, [rax + 23] ; end: 22 octal digits + null
    mov byte [rbx], 0
    pop rdi
    push rdi
    mov rax, rdi

    ; Work with the magnitude (matches to_dec semantics)
    test rax, rax
    jns .oct_mag
    neg rax
.oct_mag:
    ; Handle zero specially
    test rax, rax
    jnz .oct_loop
    dec rbx
    mov byte [rbx], '0'
    mov rax, rbx
    jmp .oct_done

.oct_loop:
    test rax, rax
    jz .oct_sign
    mov rcx, rax
    and rcx, 7                  ; digit = value & 7
    add cl, '0'
    dec rbx
    mov [rbx], cl
    shr rax, 3                  ; unsigned shift right
    jmp .oct_loop

.oct_sign:
    pop rdi
    push rdi
    test rdi, rdi
    jns .oct_result
    dec rbx
    mov byte [rbx], '-'

.oct_result:
    mov rax, rbx

.oct_done:
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    ret

; ──────────────────────────────────────────────────────────────
; rt_conv_to_dec: convert integer to decimal string
; Input:  rdi = integer value (signed 64-bit)
; Output: rax = pointer to null-terminated string
; ──────────────────────────────────────────────────────────────
rt_conv_to_dec:
    push rbx
    push rcx
    push rdx
    push rdi

    call rt_conv_alloc
    lea rbx, [rax + 24] ; end: 20 decimal digits + sign + null
    mov byte [rbx], 0   ; null terminator

    ; Work with the magnitude (two's-complement negate; INT64_MIN wraps
    ; and prints as 2^63 — acceptable best-effort)
    pop rdi
    push rdi
    mov rax, rdi
    test rax, rax
    jns .dec_mag
    neg rax
.dec_mag:
    ; Handle zero specially
    test rax, rax
    jnz .dec_loop
    dec rbx
    mov byte [rbx], '0'
    jmp .dec_sign

.dec_loop:
    test rax, rax
    jz .dec_sign
    xor rdx, rdx
    mov rcx, 10
    div rcx                    ; rax = quotient, rdx = digit
    add dl, '0'
    dec rbx
    mov [rbx], dl
    jmp .dec_loop

.dec_sign:
    ; Check if original value was negative
    pop rdi
    push rdi
    test rdi, rdi
    jns .dec_result
    dec rbx
    mov byte [rbx], '-'

.dec_result:
    mov rax, rbx

.dec_done:
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    ret

; ──────────────────────────────────────────────────────────────
; rt_conv_ftos: convert double to decimal string
; Input:  XMM0 = double value
; Output: rax = pointer to null-terminated string
; Format matches rt_prf.asm: precision 16, trailing zeros stripped,
; NaN → "nan", +inf → "inf", -inf → "-inf"
; ──────────────────────────────────────────────────────────────
rt_conv_ftos:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    mov rbp, rsp
    sub rsp, 64         ; Scratch space (same layout as rt_prf)

    call rt_conv_alloc
    mov r14, rax        ; buffer start (fresh per-call allocation)

    mov rdi, 16         ; default precision 16
    ; Cap precision between 1 and 48
    cmp rdi, 1
    jge .prec_min_ok
    mov rdi, 1
.prec_min_ok:
    cmp rdi, 48
    jle .prec_max_ok
    mov rdi, 48
.prec_max_ok:
    mov [rbp-56], rdi

    ; Check for NaN/Inf (exponent field = 0x7FF)
    movq rax, xmm0
    mov rcx, rax
    mov rdx, [rel .mask_exp]
    and rcx, rdx
    cmp rcx, rdx
    je .nan_or_inf

    ; Check sign (bit-level: handles -0.0 correctly)
    test rax, rax
    jns .positive
    ; Sign bit set — check if -0.0 (only sign bit, no magnitude)
    shl rax, 1
    jz .positive            ; -0.0 → treat as positive

    ; Write leading minus sign into the buffer
    mov rbx, r14
    mov byte [rbx], '-'
    inc rbx
    movsd xmm1, [rel .float_neg_one]
    mulsd xmm0, xmm1
    jmp .whole_start

.positive:
    mov rbx, r14

.whole_start:
    ; Convert whole part to integer
    cvttsd2si r12, xmm0 ; r12 = whole part (INT64_MIN on overflow — best-effort)

    ; Write whole-part digits into the buffer (forward order via reversed scratch)
    mov rax, r12
    lea rcx, [rbp-20]
    mov byte [rcx], 0
    test rax, rax
    jnz .whole_loop
    mov byte [rbx], '0'
    inc rbx
    jmp .frac_print
.whole_loop:
    xor rdx, rdx
    mov r8, 10
    div r8
    add dl, '0'
    mov [rcx], dl
    inc rcx
    test rax, rax
    jnz .whole_loop
    ; copy reversed digits into buffer in order
.whole_copy:
    dec rcx
    mov al, [rcx]
    mov [rbx], al
    inc rbx
    lea rdx, [rbp-20]
    cmp rcx, rdx
    ja .whole_copy

.frac_print:
    ; Write '.'
    mov byte [rbx], '.'
    inc rbx

    ; Get fractional part
    cvtsi2sd xmm1, r12
    subsd xmm0, xmm1    ; xmm0 = fractional part (0 <= xmm0 < 1)

    ; Format exactly [rbp-56] digits into [rbp-48]
    mov r13, [rbp-56]
    lea rcx, [rbp-48]
    movsd xmm2, [rel .float_10]
.frac_loop:
    mulsd xmm0, xmm2
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
    subsd xmm0, xmm1

    add al, '0'
    mov [rcx], al
    inc rcx
    dec r13d
    jnz .frac_loop

    ; Strip trailing zeros
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

    ; Copy fraction digits into buffer
    lea rsi, [rbp-48]
    mov r8, rsi
    add r8, rcx
.copy_frac:
    cmp rsi, r8
    jae .copy_done
    mov al, [rsi]
    mov [rbx], al
    inc rsi
    inc rbx
    jmp .copy_frac
.copy_done:
    mov byte [rbx], 0
    mov rax, r14
    mov rsp, rbp
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

.nan_or_inf:
    ; Check if NaN (fraction bits != 0) or Inf (fraction bits == 0)
    movq rax, xmm0
    mov rdx, [rel .mask_frac]
    test rax, rdx
    jnz .print_nan
    ; Inf — check sign
    test rax, rax
    jns .print_inf_pos
    mov rbx, r14
    mov byte [rbx], '-'
    mov byte [rbx+1], 'i'
    mov byte [rbx+2], 'n'
    mov byte [rbx+3], 'f'
    mov byte [rbx+4], 0
    mov rax, r14
    mov rsp, rbp
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
.print_inf_pos:
    mov rbx, r14
    mov byte [rbx], 'i'
    mov byte [rbx+1], 'n'
    mov byte [rbx+2], 'f'
    mov byte [rbx+3], 0
    mov rax, r14
    mov rsp, rbp
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
.print_nan:
    mov rbx, r14
    mov byte [rbx], 'n'
    mov byte [rbx+1], 'a'
    mov byte [rbx+2], 'n'
    mov byte [rbx+3], 0
    mov rax, r14
    mov rsp, rbp
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

.ftos_data:
.float_neg_one dq -1.0
.float_10      dq 10.0
.mask_exp      dq 0x7FF0000000000000
.mask_frac     dq 0x000FFFFFFFFFFFFF

; ──────────────────────────────────────────────────────────────
; rt_conv_stoi: parse decimal string to integer
; Input:  rdi = pointer to null-terminated string
; Output: rax = parsed integer (0 on malformed input — best-effort)
; Accepts optional sign and 0x / 0b / 0o prefixes
; ──────────────────────────────────────────────────────────────
rt_conv_stoi:
    push rbx
    push rcx
    push rdx
    push rsi

    mov rsi, rdi
    ; Skip leading whitespace
.stoi_ws:
    movzx ecx, byte [rsi]
    cmp cl, ' '
    je .stoi_ws_next
    cmp cl, 9
    je .stoi_ws_next
    cmp cl, 10
    je .stoi_ws_next
    cmp cl, 13
    je .stoi_ws_next
    jmp .stoi_first
.stoi_ws_next:
    inc rsi
    jmp .stoi_ws

.stoi_first:
    mov rbx, 1              ; sign = +1
    cmp cl, '-'
    je .stoi_neg
    cmp cl, '+'
    je .stoi_pos
    jmp .stoi_prefix
.stoi_neg:
    mov rbx, -1
    inc rsi
    movzx ecx, byte [rsi]
    jmp .stoi_prefix
.stoi_pos:
    inc rsi
    movzx ecx, byte [rsi]

.stoi_prefix:
    ; 0x / 0b / 0o prefixes
    cmp cl, '0'
    jne .stoi_digits
    movzx edx, byte [rsi+1]
    and dl, 0xDF            ; uppercase
    cmp dl, 'X'
    je .stoi_hex
    cmp dl, 'B'
    je .stoi_bin
    cmp dl, 'O'
    je .stoi_oct
    ; else: plain decimal digits
.stoi_digits:
    xor rax, rax
.stoi_digits_loop:
    movzx ecx, byte [rsi]
    cmp cl, '0'
    jb .stoi_done
    cmp cl, '9'
    ja .stoi_done
    lea rax, [rax + rax*4]
    shl rax, 1              ; rax *= 10
    add rax, rcx
    sub rax, '0'
    inc rsi
    jmp .stoi_digits_loop

.stoi_hex:
    add rsi, 2
    xor rax, rax
.stoi_hex_loop:
    movzx ecx, byte [rsi]
    cmp cl, '0'
    jb .stoi_done
    cmp cl, '9'
    ja .stoi_hex_letter
    sub cl, '0'
    jmp .stoi_hex_add
.stoi_hex_letter:
    or cl, 0x20             ; to lowercase
    cmp cl, 'a'
    jb .stoi_done
    cmp cl, 'f'
    ja .stoi_done
    sub cl, 'a' - 10
.stoi_hex_add:
    shl rax, 4
    or rax, rcx
    inc rsi
    jmp .stoi_hex_loop

.stoi_bin:
    add rsi, 2
    xor rax, rax
.stoi_bin_loop:
    movzx ecx, byte [rsi]
    cmp cl, '0'
    jb .stoi_done
    cmp cl, '1'
    ja .stoi_done
    shl rax, 1
    or rax, rcx
    sub rax, '0'
    inc rsi
    jmp .stoi_bin_loop

.stoi_oct:
    add rsi, 2
    xor rax, rax
.stoi_oct_loop:
    movzx ecx, byte [rsi]
    cmp cl, '0'
    jb .stoi_done
    cmp cl, '7'
    ja .stoi_done
    shl rax, 3
    or rax, rcx
    sub rax, '0'
    inc rsi
    jmp .stoi_oct_loop

.stoi_done:
    cmp rbx, -1
    jne .stoi_finish
    neg rax
.stoi_finish:
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; ──────────────────────────────────────────────────────────────
; rt_conv_stof: parse decimal string to double
; Input:  rdi = pointer to null-terminated string
; Output: XMM0 = parsed double (0.0 on malformed input — best-effort)
; Accepts sign, integer+fraction, optional exponent (e/E)
; ──────────────────────────────────────────────────────────────
rt_conv_stof:
    push rbx
    push rcx
    push rdx
    push rsi
    push r8

    mov rsi, rdi
    ; Skip leading whitespace
.stof_ws:
    movzx ecx, byte [rsi]
    cmp cl, ' '
    je .stof_ws_next
    cmp cl, 9
    je .stof_ws_next
    cmp cl, 10
    je .stof_ws_next
    cmp cl, 13
    je .stof_ws_next
    jmp .stof_first
.stof_ws_next:
    inc rsi
    jmp .stof_ws

.stof_first:
    mov rbx, 1              ; sign = +1
    cmp cl, '-'
    je .stof_neg
    cmp cl, '+'
    je .stof_pos
    jmp .stof_int_digits
.stof_neg:
    mov rbx, -1
    inc rsi
    movzx ecx, byte [rsi]
    jmp .stof_int_digits
.stof_pos:
    inc rsi
    movzx ecx, byte [rsi]

.stof_int_digits:
    fldz                    ; st(0) = 0.0
.stof_int_loop:
    movzx ecx, byte [rsi]
    cmp cl, '0'
    jb .stof_int_done
    cmp cl, '9'
    ja .stof_int_done
    ; st = st*10 + digit
    push dword 10
    fild dword [rsp]
    add rsp, 8
    fmulp st1, st0
    sub ecx, '0'
    push rcx
    fild dword [rsp]
    add rsp, 8
    faddp st1, st0
    inc rsi
    jmp .stof_int_loop

.stof_int_done:
    ; Fraction part?
    cmp cl, '.'
    jne .stof_exp
    inc rsi
    xor rcx, rcx            ; rcx = fraction digit count
.stof_frac_loop:
    movzx edx, byte [rsi]
    cmp dl, '0'
    jb .stof_frac_done
    cmp dl, '9'
    ja .stof_frac_done
    push dword 10
    fild dword [rsp]
    add rsp, 8
    fmulp st1, st0
    sub edx, '0'
    push rdx
    fild dword [rsp]
    add rsp, 8
    faddp st1, st0
    inc rcx
    inc rsi
    jmp .stof_frac_loop

.stof_frac_done:
    mov r8, rcx             ; save fraction digit count
    mov cl, dl              ; reload terminator char (frac loop used edx)
    ; Divide by 10^frac_count
    test r8, r8
    jz .stof_exp
    push dword 10
    fild dword [rsp]
    add rsp, 8
    dec r8
.stof_frac_scale:
    test r8, r8
    jz .stof_frac_scaled
    push dword 10
    fild dword [rsp]
    add rsp, 8
    fmulp st1, st0
    dec r8
    jmp .stof_frac_scale
.stof_frac_scaled:
    fdivp st1, st0

.stof_exp:
    ; Optional exponent e/E
    cmp cl, 'e'
    je .stof_exp_got
    cmp cl, 'E'
    jne .stof_sign
.stof_exp_got:
    inc rsi
    mov r8, 0               ; exp magnitude
    xor edx, edx            ; 0 = positive exponent
    movzx ecx, byte [rsi]
    cmp cl, '-'
    je .stof_exp_neg
    cmp cl, '+'
    je .stof_exp_pos
    jmp .stof_exp_digits
.stof_exp_neg:
    mov edx, 1
    inc rsi
    jmp .stof_exp_digits
.stof_exp_pos:
    inc rsi
.stof_exp_digits:
    movzx ecx, byte [rsi]
    cmp cl, '0'
    jb .stof_exp_done
    cmp cl, '9'
    ja .stof_exp_done
    lea r8, [r8 + r8*4]
    shl r8, 1               ; r8 *= 10
    sub ecx, '0'
    add r8, rcx
    inc rsi
    jmp .stof_exp_digits
.stof_exp_done:
    ; Cap exponent magnitude to avoid runaway loops (double range limit)
    cmp r8, 308
    jle .stof_exp_capped
    mov r8, 308
.stof_exp_capped:
    ; temp = 10^r8
    fld1
    test r8, r8
    jz .stof_scale_done
.stof_exp_loop:
    push dword 10
    fild dword [rsp]
    add rsp, 8
    fmulp st1, st0
    dec r8
    jnz .stof_exp_loop
.stof_scale_done:
    ; st(0) = 10^exp, st(1) = value
    test edx, edx
    jnz .stof_scale_div
    fmulp st1, st0          ; value *= 10^exp
    jmp .stof_sign
.stof_scale_div:
    fdivp st1, st0          ; value /= 10^exp

.stof_sign:
    cmp rbx, -1
    jne .stof_finish
    fchs

.stof_finish:
    sub rsp, 8
    fstp qword [rsp]
    movq xmm0, [rsp]
    add rsp, 8
    pop r8
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; ──────────────────────────────────────────────────────────────
; rt_conv_btos: convert bool to string
; Input:  rdi = bool value (true=1, neutral=0, false=-1)
; Output: rax = pointer to "true" / "neutral" / "false"
; ──────────────────────────────────────────────────────────────
rt_conv_btos:
    cmp rdi, 0
    jg .bt_true
    jl .bt_false
    lea rax, [rel .bt_neutral_str]
    ret
.bt_true:
    lea rax, [rel .bt_true_str]
    ret
.bt_false:
    lea rax, [rel .bt_false_str]
    ret

.bt_true_str    db "true", 0
.bt_neutral_str db "neutral", 0
.bt_false_str   db "false", 0

; ──────────────────────────────────────────────────────────────
; rt_conv_ctos: convert char/byte value to single-char string
; Input:  rdi = value (byte 0-255)
; Output: rax = pointer to 2-byte buffer [char, null]
; ──────────────────────────────────────────────────────────────
rt_conv_ctos:
    movzx esi, dil      ; save byte (rt_conv_alloc clobbers rdi)
    call rt_conv_alloc
    mov [rax], sil
    mov byte [rax+1], 0
    ret

; ──────────────────────────────────────────────────────────────
; rt_conv_btohex: convert byte to 2-char zero-padded lowercase hex
; Input:  rdi = byte value
; Output: rax = pointer to "0f"-style string
; ──────────────────────────────────────────────────────────────
rt_conv_btohex:
    movzx esi, dil      ; save byte (rt_conv_alloc clobbers rdi)
    call rt_conv_alloc
    movzx ecx, sil
    shr ecx, 4              ; high nibble
    call .bh_digit
    mov [rax], cl
    movzx ecx, sil
    and ecx, 0xF            ; low nibble
    call .bh_digit
    mov [rax+1], cl
    mov byte [rax+2], 0
    ret

.bh_digit:
    ; ecx = nibble 0-15 → cl = hex char
    cmp cl, 10
    jb .bh_d0
    add cl, 'a' - 10
    ret
.bh_d0:
    add cl, '0'
    ret

; ──────────────────────────────────────────────────────────────
; rt_conv_btobin: convert byte to 8-char zero-padded binary
; Input:  rdi = byte value
; Output: rax = pointer to "00001111"-style string
; ──────────────────────────────────────────────────────────────
rt_conv_btobin:
    movzx esi, dil      ; save byte (rt_conv_alloc clobbers rdi)
    call rt_conv_alloc
    mov ecx, 8
    movzx r8d, sil
    mov r9, rax
.bb_loop:
    test r8d, 0x80
    jz .bb_zero
    mov byte [r9], '1'
    jmp .bb_next
.bb_zero:
    mov byte [r9], '0'
.bb_next:
    shl r8d, 1
    inc r9
    dec ecx
    jnz .bb_loop
    mov byte [r9], 0
    ret
