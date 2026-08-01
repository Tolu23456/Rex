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

; Static conversion buffer (72 bytes: 64 digits + sign + null + padding)
rt_conv_buf: times 72 db 0

; ──────────────────────────────────────────────────────────────
; rt_conv_to_bin: convert integer to binary string
; Input:  rdi = integer value (signed 64-bit)
; Output: rax = pointer to null-terminated string in rt_conv_buf
; ──────────────────────────────────────────────────────────────
rt_conv_to_bin:
    push rbx
    push rcx
    push rdx
    push rdi

    mov rax, rdi
    lea rbx, [rt_conv_buf + 65] ; end of buffer
    mov byte [rbx], 0           ; null terminator
    dec rbx

    ; Handle zero specially
    test rax, rax
    jnz .bin_loop
    mov byte [rbx], '0'
    mov rax, rbx
    jmp .bin_done

.bin_loop:
    test rax, rax
    jz .bin_sign
    mov rcx, rax
    and rcx, 1                  ; bit = value & 1
    add cl, '0'
    mov [rbx], cl
    dec rbx
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

    mov rax, rdi
    lea rbx, [rt_conv_buf + 17] ; end: 16 hex digits + null
    mov byte [rbx], 0
    dec rbx

    ; Handle zero specially
    test rax, rax
    jnz .hex_loop
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
    mov [rbx], cl
    dec rbx
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

    mov rax, rdi
    lea rbx, [rt_conv_buf + 23] ; end: 22 octal digits + null
    mov byte [rbx], 0
    dec rbx

    ; Handle zero specially
    test rax, rax
    jnz .oct_loop
    mov byte [rbx], '0'
    mov rax, rbx
    jmp .oct_done

.oct_loop:
    test rax, rax
    jz .oct_sign
    mov rcx, rax
    and rcx, 7                  ; digit = value & 7
    add cl, '0'
    mov [rbx], cl
    dec rbx
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
