; rt_math.asm — mathematical runtime functions for Rex compiler
; Flat binary blob (BITS 64, no ELF headers)
;
; Calling convention (SysV AMD64):
;   Float args/returns: xmm0, xmm1
;   Int args/returns:   rdi, rsi → rax
;
; Functions (offsets calculated from start of blob):
;   rt_math_sin   — sin(x)       xmm0 → xmm0
;   rt_math_cos   — cos(x)       xmm0 → xmm0
;   rt_math_tan   — tan(x)       xmm0 → xmm0
;   rt_math_pow   — pow(x, y)    xmm0=x, xmm1=y → xmm0
;   rt_math_cbrt  — cbrt(x)      xmm0 → xmm0
;   rt_math_gcd   — gcd(a, b)    rdi, rsi → rax
;   rt_math_lcm   — lcm(a, b)    rdi, rsi → rax

BITS 64
default rel                     ; all memory refs are RIP-relative

; ──────────────────────────────────────────────────────────────
; rt_math_sin: sin(x) using x87 FPU fsin
; Input:  xmm0 = x (double)
; Output: xmm0 = sin(x)
; Clobbers: rax
; ──────────────────────────────────────────────────────────────
rt_math_sin:
    sub rsp, 8
    movq [rsp], xmm0           ; store x to stack
    fld qword [rsp]            ; st(0) = x
    fsin                       ; st(0) = sin(x)
    fstp qword [rsp]           ; store result
    movq xmm0, [rsp]          ; load into xmm0
    add rsp, 8
    ret

; ──────────────────────────────────────────────────────────────
; rt_math_cos: cos(x) using x87 FPU fcos
; Input:  xmm0 = x (double)
; Output: xmm0 = cos(x)
; ──────────────────────────────────────────────────────────────
rt_math_cos:
    sub rsp, 8
    movq [rsp], xmm0
    fld qword [rsp]
    fcos
    fstp qword [rsp]
    movq xmm0, [rsp]
    add rsp, 8
    ret

; ──────────────────────────────────────────────────────────────
; rt_math_tan: tan(x) using x87 FPU fptan
; Input:  xmm0 = x (double)
; Output: xmm0 = tan(x)
; fptan pushes 1.0 and tan(x) onto stack; we want tan(x) only
; ──────────────────────────────────────────────────────────────
rt_math_tan:
    sub rsp, 8
    movq [rsp], xmm0
    fld qword [rsp]            ; st(0) = x
    fptan                      ; st(0) = 1.0, st(1) = tan(x)
    fstp st0                   ; pop the 1.0, st(0) = tan(x)
    fstp qword [rsp]
    movq xmm0, [rsp]
    add rsp, 8
    ret

; ──────────────────────────────────────────────────────────────
; rt_math_pow: pow(x, y) = 2^(y * log2(x))
; Input:  xmm0 = x, xmm1 = y
; Output: xmm0 = x^y
; ──────────────────────────────────────────────────────────────
rt_math_pow:
    sub rsp, 16
    movq [rsp], xmm0           ; [rsp] = x
    movq [rsp+8], xmm1         ; [rsp+8] = y

    ; If y == 0.0, result is 1.0 (covers x^0 and 0^0)
    fld qword [rsp+8]          ; st(0) = y
    fldz                       ; st(0) = 0.0, st(1) = y
    fcomip st0, st1
    fstp st0
    je .pow_one

    ; General case: x^y = 2^(y * log2(x))
    fld qword [rsp+8]          ; st(0) = y
    fld qword [rsp]            ; st(0) = x, st(1) = y
    fyl2x                      ; st(0) = y*log2(x)
    fld st0                    ; duplicate
    frndint                    ; st(0)=round(t), st(1)=t
    fxch st1                   ; st(0)=t, st(1)=round(t)
    fsub st0, st1              ; st(0)=frac=t-round(t)
    f2xm1                      ; st(0)=2^frac-1
    fld1                       ; st(0)=1, st(1)=2^frac-1, st(2)=round(t)
    faddp st1, st0             ; st(0)=2^frac, st(1)=round(t)
    fscale                     ; st(0)=2^frac*2^round(t)=x^y
    fstp st1                   ; pop the integer exponent
    jmp .pow_store

.pow_one:
    fld1                       ; st(0) = 1.0
.pow_store:
    fstp qword [rsp]
    movq xmm0, [rsp]
    add rsp, 16
    ret

    ; Pad to keep rt_math_cbrt at its fixed offset (0xA3)
    times 80-($-rt_math_pow) db 0x90

; ──────────────────────────────────────────────────────────────
; rt_math_cbrt: cbrt(x) = 2^(log2(x)/3)
; Input:  xmm0 = x (double)
; Output: xmm0 = cbrt(x)
; Handles negative x: cbrt(-x) = -cbrt(x)
; ──────────────────────────────────────────────────────────────
rt_math_cbrt:
    sub rsp, 8
    movq [rsp], xmm0

    ; Check for negative
    fld qword [rsp]
    fldz
    fcomip st0, st1            ; compare 0 vs x
    fstp st0                   ; pop x
    ja .cbrt_negative

    ; x >= 0: cbrt(x) = 2^(log2(x)/3)
    fld qword [rsp]
    fld1
    fxch st1
    fyl2x                      ; st(0) = log2(x)
    ; Divide by 3
    push dword 3
    fild dword [rsp]
    add rsp, 8
    fdivp st1, st0             ; st(0) = log2(x)/3
    ; Compute 2^(result)
    fld st0
    frndint
    fxch st1
    f2xm1
    fld1
    faddp
    fscale
    fstp st1
    jmp .cbrt_done

.cbrt_negative:
    ; x < 0: cbrt(x) = -cbrt(-x)
    fld qword [rsp]
    fchs                       ; st(0) = -x (positive)
    fld1
    fxch st1
    fyl2x                      ; st(0) = log2(-x)
    push dword 3
    fild dword [rsp]
    add rsp, 8
    fdivp st1, st0
    fld st0
    frndint
    fxch st1
    f2xm1
    fld1
    faddp
    fscale
    fstp st1
    fchs                       ; negate result

.cbrt_done:
    fstp qword [rsp]
    movq xmm0, [rsp]
    add rsp, 8
    ret

; ──────────────────────────────────────────────────────────────
; rt_math_gcd: Greatest Common Divisor (Euclidean algorithm)
; Input:  rdi = a, rsi = b
; Output: rax = gcd(a, b)
; ──────────────────────────────────────────────────────────────
rt_math_gcd:
    ; gcd(a, b) = gcd(|a|, |b|); gcd(x, 0) = |x|
    mov rax, rdi
    cqo
    xor rax, rdx
    sub rax, rdx               ; rax = |a|
    mov rdi, rax
    mov rax, rsi
    cqo
    xor rax, rdx
    sub rax, rdx               ; rax = |b|
    mov rsi, rax
    test rdi, rdi
    jnz .gcd_have_a
    mov rax, rsi
    ret
.gcd_have_a:
    test rsi, rsi
    jnz .gcd_loop
    mov rax, rdi
    ret
.gcd_loop:
    mov rax, rdi               ; dividend = a
    xor rdx, rdx
    div rsi                    ; rdx = a % b, rax = a / b
    mov rdi, rsi               ; a = b
    mov rsi, rdx               ; b = a % b
    test rsi, rsi
    jnz .gcd_loop
    mov rax, rdi               ; result = last non-zero divisor
    ret

; ──────────────────────────────────────────────────────────────
; rt_math_lcm: Least Common Multiple
; lcm(a, b) = (|a| / gcd(|a|, |b|)) * |b|
; Divide before multiply so |a*b| >= 2^63 does not corrupt the result.
; Input:  rdi = a, rsi = b
; Output: rax = lcm(a, b)
; ──────────────────────────────────────────────────────────────
rt_math_lcm:
    mov rax, rdi
    cqo
    xor rax, rdx
    sub rax, rdx               ; rax = |a|
    mov r8, rax                ; r8 = |a|
    mov rax, rsi
    cqo
    xor rax, rdx
    sub rax, rdx               ; rax = |b|
    mov r9, rax                ; r9 = |b|
    ; gcd(|a|, |b|)
    mov rdi, r8
    mov rsi, r9
    push r8
    push r9
    call rt_math_gcd
    pop r9
    pop r8
    test rax, rax
    jz .lcm_zero
    mov rcx, rax               ; rcx = gcd
    mov rax, r8
    xor edx, edx
    div rcx                    ; rax = |a| / gcd
    imul rax, r9               ; rax = (|a|/gcd) * |b|
    ret

.lcm_zero:
    xor eax, eax
    ret

; ──────────────────────────────────────────────────────────────
; rt_math_int_pow: integer exponentiation
; Input:  rdi = base, rsi = exponent (>= 0)
; Output: rax = base^exp (0^0 = 1; overflow wraps — best-effort)
; ──────────────────────────────────────────────────────────────
rt_math_int_pow:
    mov rax, 1
    mov rcx, rdi
    test rsi, rsi
    jz .pow_done
    js .pow_neg
.pow_loop:
    imul rax, rcx
    dec rsi
    jnz .pow_loop
.pow_done:
    ret
.pow_neg:
    xor eax, eax            ; negative exponent → 0 (integer truncation)
    ret
