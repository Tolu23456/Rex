; runtime_src.asm — compiled with: nasm -f bin -o runtime/runtime.bin runtime/runtime_src.asm
; Flat binary, org 0, 64-bit code.
; ─────────────────────────────────────────────────────────────────────────────
%define RT_PRI_SIZE  512
%define RT_PRS_SIZE  512
%define RT_PRB_SIZE  256
%define RT_PRF_SIZE  512
%define RT_PRC_SIZE  512
%define RT_SIP_SIZE  1024
%define RT_ALC_SIZE  4096
%define RT_PRQ_SIZE  1024

; New blobs for T001
%define RT_STR_CAT_SIZE 512
%define RT_STR_EQ_SIZE 256
%define RT_STR_FIND_SIZE 512
%define RT_STR_LEN_SIZE 128
%define RT_STR_UPPER_SIZE 256
%define RT_STR_LOWER_SIZE 256
%define RT_STR_TRIM_SIZE 256
%define RT_STR_REV_SIZE 256
%define RT_INT2STR_SIZE 256
%define RT_FLOAT2STR_SIZE 512
%define RT_STR_SPLIT_SIZE 512
%define RT_STR_JOIN_SIZE 512
%define RT_STR_STARTS_SIZE 256
%define RT_STR_ENDS_SIZE 256
%define RT_STR_CONTAINS_SIZE 128
%define RT_STR_SLICE_SIZE 256
%define RT_STR_REPLACE_SIZE 512
%define RT_STR_COUNT_SIZE 256
%define RT_STR_REPEAT_SIZE 256
%define RT_MATH_SQRT_SIZE 64
%define RT_MATH_FLOOR_SIZE 64
%define RT_MATH_CEIL_SIZE 64
%define RT_MATH_ABS_F_SIZE 64
%define RT_MATH_SIN_SIZE 128
%define RT_MATH_COS_SIZE 128
%define RT_MATH_EXP_SIZE 256
%define RT_MATH_LOG_SIZE 256
%define RT_MATH_POW_SIZE 256
%define RT_MATH_MIN_SIZE 64
%define RT_MATH_MAX_SIZE 64
%define RT_BOUNDS_ERR_SIZE 256
%define RT_OVERFLOW_ERR_SIZE 256
%define RT_NULL_ERR_SIZE 256
%define RT_SEQ_SORT_SIZE 1024
%define RT_SEQ_SUM_SIZE 256
%define RT_SEQ_MIN_SIZE 256
%define RT_SEQ_MAX_SIZE 256
%define RT_SEQ_CONTAINS_SIZE 256
%define RT_SEQ_REVERSE_SIZE 256
%define RT_HEAP_ALLOC_SIZE 1024
%define RT_HEAP_FREE_SIZE 512
%define RT_STATIC_ALLOC_SIZE 256

bits 64
org 0

; ── rt_pri: print signed integer in rdi to stdout + newline ──────────────────
rt_pri:
    push rbx
    push r12
    push r13
    sub rsp, 24
    mov r12, rdi
    ; BUG-12 fix: special-case INT64_MIN = -9223372036854775808 (neg overflows)
    mov rax, 0x8000000000000000
    cmp r12, rax
    jne .not_min
    lea rsi, [rel .min_str]
    mov rdx, 21                 ; length of "-9223372036854775808\n"
    mov rax, 1
    mov rdi, 1
    syscall
    add rsp, 24
    pop r13
    pop r12
    pop rbx
    ret
.not_min:
    lea r13, [rsp+23]
    mov byte [r13], 10          ; newline at end of buffer
    xor rbx, rbx               ; rbx = 0 (not negative)
    test r12, r12
    jz .zero
    jns .pos
    neg r12
    mov rbx, 1
.pos:
    mov rax, r12
    mov rcx, 10
.lp:
    xor rdx, rdx
    div rcx
    add dl, '0'
    dec r13
    mov [r13], dl
    test rax, rax
    jnz .lp
    test rbx, rbx
    jz .wr
    dec r13
    mov byte [r13], '-'
    jmp .wr
.zero:
    dec r13
    mov byte [r13], '0'
.wr:
    mov rsi, r13
    lea rdx, [rsp+24]
    sub rdx, r13
    mov rax, 1
    mov rdi, 1
    syscall
    add rsp, 24
    pop r13
    pop r12
    pop rbx
    ret
.min_str: db "-9223372036854775808",10
    times RT_PRI_SIZE - ($ - rt_pri) db 0x90

; ── rt_prs: print null-terminated string in rdi to stdout + newline ──────────
; O35a: strlen via repne scasb — 1 cycle/byte throughput vs 3-4 cycle loop.
rt_prs:
    push rbx
    push r12
    mov r12, rdi            ; preserve string pointer (r12 callee-saved)
    test r12, r12
    jz .done                ; skip if null
    ; strlen: scan for NUL using repne scasb
    xor eax, eax            ; al = 0 (NUL byte)
    mov rcx, -1
    repne scasb             ; rdi advances; ecx = -(len+2)
    not rcx                 ; rcx = len+1
    lea rbx, [rcx-1]        ; rbx = len (without NUL)
    test rbx, rbx
    jz .newline             ; just newline for empty string
    ; sys_write(1, r12, rbx)
    mov rax, 1
    mov rdi, 1
    mov rsi, r12
    mov rdx, rbx
    syscall
.newline:
    ; print newline (red-zone trick)
    mov byte [rsp-8], 10
    lea rsi, [rsp-8]
    mov rax, 1
    mov rdi, 1
    mov rdx, 1
    syscall
.done:
    pop r12
    pop rbx
    ret
    times RT_PRS_SIZE - ($ - rt_prs) db 0x90

; ── rt_prb: print bool in rdi (0=false, 1=true, else=unknown) + newline ──────
rt_prb:
    push rbx
    mov rbx, rdi
    test rbx, rbx
    jz .fls
    cmp rbx, 1
    jne .unk
    lea rsi, [rel .s_true]
    mov rdx, 5
    jmp .pr
.fls:
    lea rsi, [rel .s_false]
    mov rdx, 6
    jmp .pr
.unk:
    lea rsi, [rel .s_unk]
    mov rdx, 8
.pr:
    mov rax, 1
    mov rdi, 1
    syscall
    pop rbx
    ret
.s_true:  db "true",10
.s_false: db "false",10
.s_unk:   db "unknown",10
    times RT_PRB_SIZE - ($ - rt_prb) db 0x90

; ── rt_prf: print float in rdi (IEEE-754 bits) to stdout + newline ───────────
rt_prf:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 48
    mov r12, rsp            ; output buffer
    xor r13, r13            ; output index
    mov rax, rdi            ; float bits
    
    ; check for infinity (exponent all 1s, mantissa 0)
    mov rdx, rax
    mov rcx, 0x7FFFFFFFFFFFFFFF
    and rdx, rcx ; clear sign
    mov rcx, 0x7FF0000000000000 ; infinity pattern
    cmp rdx, rcx
    jne .not_inf
    
    ; it is infinity or NaN (if mantissa != 0)
    ; for now just "inf"
    test rax, rax
    jns .inf_pos
    mov byte [r12+r13], '-'
    inc r13
.inf_pos:
    mov byte [r12+r13], 'i'
    mov byte [r12+r13+1], 'n'
    mov byte [r12+r13+2], 'f'
    add r13, 3
    jmp .wr_final

.not_inf:
    mov rax, rdi
    test rax, rax
    jns .abv
    mov byte [r12+r13], '-'
    inc r13
    btc rax, 63             ; flip sign bit → positive
.abv:
    movq xmm0, rax
    cvttsd2si rbx, xmm0     ; rbx = integer part
    cvtsi2sd xmm1, rbx
    subsd xmm0, xmm1        ; xmm0 = fractional part
    ; print integer part
    test rbx, rbx
    jnz .icvt
    mov byte [r12+r13], '0'
    inc r13
    jmp .dot
.icvt:
    lea r14, [r12+32]       ; temp digit scratch (within buffer)
    xor rcx, rcx
.idl:
    xor rdx, rdx
    mov rax, rbx
    push rcx
    mov rcx, 10
    div rcx
    pop rcx
    add dl, '0'
    mov [r14+rcx], dl
    inc rcx
    mov rbx, rax
    test rax, rax
    jnz .idl
.idc:
    dec rcx
    movzx rax, byte [r14+rcx]
    mov [r12+r13], al
    inc r13
    test rcx, rcx
    jnz .idc
.dot:
    mov byte [r12+r13], '.'
    inc r13
    mov r14, 6              ; 6 fractional digits
.frl:
    mov rax, 10
    cvtsi2sd xmm1, rax
    mulsd xmm0, xmm1
    cvttsd2si rax, xmm0
    cvtsi2sd xmm1, rax
    subsd xmm0, xmm1
    add al, '0'
    mov [r12+r13], al
    inc r13
    dec r14
    jnz .frl
.wr_final:
    mov byte [r12+r13], 10
    inc r13
    mov rax, 1
    mov rdi, 1
    mov rsi, r12
    mov rdx, r13
    syscall
    add rsp, 48
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
    times RT_PRF_SIZE - ($ - rt_prf) db 0x90

; ── rt_prc: print complex (rdi = imaginary integer) as "Xj\n" ────────────────
rt_prc:
    push rbx
    push r12
    push r13
    sub rsp, 24
    mov r12, rdi
    lea r13, [rsp+21]
    mov byte [r13+1], 'j'
    mov byte [r13+2], 10    ; newline
    xor rbx, rbx
    test r12, r12
    jz .zcx
    jns .pcx
    neg r12
    mov rbx, 1
.pcx:
    mov rax, r12
    mov rcx, 10
.lcx:
    xor rdx, rdx
    div rcx
    add dl, '0'
    dec r13
    mov [r13], dl
    test rax, rax
    jnz .lcx
    test rbx, rbx
    jz .wcx
    dec r13
    mov byte [r13], '-'
    jmp .wcx
.zcx:
    dec r13
    mov byte [r13], '0'
.wcx:
    mov rsi, r13
    lea rdx, [rsp+24]
    sub rdx, r13
    mov rax, 1
    mov rdi, 1
    syscall
    add rsp, 24
    pop r13
    pop r12
    pop rbx
    ret
    times RT_PRC_SIZE - ($ - rt_prc) db 0x90

; ── RXHASH-64: Rex eXponential Hash — novel cascade-mix identifier hash ───────
rt_sip:
    push rbx
    push r12
    mov r12, rsi                    ; r12 = byte count
    mov rax, 0xCBF29CE484222325     ; FNV-1a 64-bit offset basis
    xor rbx, rbx                    ; i = 0
.rxh_loop:
    cmp rbx, r12
    jge .rxh_fin
    movzx rdx, byte [rdi+rbx]       ; load one byte
    xor rax, rdx                    ; h ^= byte
    mov rdx, 0x100000001B3          ; FNV-1a prime (0x1_0000_0001B3)
    imul rax, rdx                   ; h *= FNV_prime
    rol rax, 31                     ; rotate left 31 bits (M31 bijection)
    inc rbx
    jmp .rxh_loop
.rxh_fin:
    mov rdx, rax
    shr rdx, 30
    xor rax, rdx
    mov rdx, 0xBF58476D1CE4E5B9     ; SplitMix64 mixer 1
    imul rax, rdx
    mov rdx, rax
    shr rdx, 27
    xor rax, rdx
    mov rdx, 0x94D049BB133111EB     ; SplitMix64 mixer 2
    imul rax, rdx
    mov rdx, rax
    shr rdx, 31
    xor rax, rdx
    pop r12
    pop rbx
    ret
    times RT_SIP_SIZE - ($ - rt_sip) db 0x90

; ── rt_alc: mmap / bump-pool allocator — rdi=size → rax=ptr ─────────────────
rt_alc:
    push rbx
    mov rbx, rdi            ; rbx = requested size
    ; guard against integer overflow in alignment arithmetic (huge size)
    mov rax, 0x7FFFFFFFFFFFFFF8
    cmp rbx, rax  ; if size > sane max, treat as OOM
    ja .oom
    add rbx, 7              ; align to 8 bytes
    and rbx, -8
    
    ; check mode at offset 402 from rt_alc
    ; wait, the file shows:
    ; 399: times 4072 - ($ - rt_alc) db 0x90
    ; 400: .pool_base: dq 0
    ; 401: .pool_bump: dq 0
    ; 402: .mode: dq 0
    ; These are NOT at offsets 400, 401, 402. They are AFTER 4072 bytes of padding.
    ; So .mode is at offset 4072 + 8 + 8 = 4088.
    ; But the current code uses [0x401D75] which is an absolute address.
    ; This is BAD because the runtime is loaded at a dynamic address (LOAD_BASE + offset).
    ; We must use RIP-relative or relative to rt_alc.
    
    mov rax, [rel .mode]
    test rax, rax           ; mode == 0 (arena/mmap)?
    jz .mmap                ; zero → mmap mode
.pool:
    ; mode != 0 → pool mode
    mov rax, [rel .pool_base]
    test rax, rax           ; pool_base == 0 (first use)?
    jnz .pool_alloc
    
    push rbx                ; save aligned size across mmap
    mov rax, 9
    xor rdi, rdi
    mov esi, 67108864       ; 64 MB
    mov rdx, 3
    mov r10d, 0x22          ; MAP_PRIVATE | MAP_ANONYMOUS
    mov r8, -1
    xor r9d, r9d
    syscall                 ; rax = pool base ptr
    pop rbx
    mov qword [rel .pool_base], rax   ; pool_base = ptr
    mov qword [rel .pool_bump], rax   ; pool_bump = ptr
.pool_alloc:
    mov rax, qword [rel .pool_bump]   ; rax = current bump (= allocation address)
    add qword [rel .pool_bump], rbx   ; advance bump by aligned size
    pop rbx
    ret
.mmap:
    test rbx, rbx
    jnz .mmap_sz
    mov rbx, 4096
.mmap_sz:
    mov rax, 9              ; sys_mmap
    xor rdi, rdi            ; addr = NULL
    mov rsi, rbx            ; length
    mov rdx, 3              ; PROT_READ | PROT_WRITE
    mov r10d, 0x22          ; MAP_PRIVATE | MAP_ANONYMOUS
    mov r8, -1              ; fd = -1
    xor r9d, r9d            ; offset = 0
    syscall
    pop rbx
    ret
.oom:
    pop rbx                     ; restore rbx before calling rt_prq
    lea rdi, [rel .oom_msg]
    call rt_prq                 ; prints to stderr and exits 1
.oom_msg: db "error: allocation size overflow",10
    times 4072 - ($ - rt_alc) db 0x90
.pool_base: dq 0
.pool_bump: dq 0
.mode: dq 0

; ── rt_prq: print error string (rdi=ptr) to stderr + exit(1) ─────────────────
rt_prq:
    push rbx
    mov rbx, rdi                ; rbx = string ptr (callee-saved)
    xor eax, eax                ; al = NUL byte
    mov rcx, -1
    repne scasb                 ; ecx = -(len+2)
    not rcx                     ; rcx = len+1
    lea rdx, [rcx-1]            ; rdx = len
    mov rax, 1
    mov rdi, 2                  ; stderr
    mov rsi, rbx
    syscall
    mov byte [rsp-8], 10
    lea rsi, [rsp-8]
    mov rax, 1
    mov rdi, 2
    mov rdx, 1
    syscall
    mov rax, 60
    mov rdi, 1
    syscall
    times RT_PRQ_SIZE - ($ - rt_prq) db 0x90

; ── rt_str_cat (512B) ────────────────────────────────────────────────────────
rt_str_cat:
    push rbx
    push r12
    push r13
    push r14
    push r15
    ; rdi=ptr1, rsi=len1, rdx=ptr2, rcx=len2
    
    ; BUG-11 fix: check if either exceeds 1GB
    mov rax, 0x40000000 ; 1GB
    cmp rsi, rax
    jae .overflow
    cmp rcx, rax
    jae .overflow
    
    ; check for integer overflow in sum
    mov rax, rsi
    add rax, rcx
    jc .overflow
    inc rax ; for NUL
    jc .overflow
    
    mov r12, rdi ; ptr1
    mov r13, rsi ; len1
    mov r14, rdx ; ptr2
    mov r15, rcx ; len2
    lea rdi, [r13 + r15 + 1] ; cap = len1+len2+1
    call rt_alc
    mov rbx, rax ; new ptr
    ; copy str1
    mov rdi, rbx
    mov rsi, r12
    mov rcx, r13
    rep movsb
    ; copy str2
    mov rsi, r14
    mov rcx, r15
    rep movsb
    mov byte [rdi], 0 ; NUL terminate
    mov rax, rbx
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.overflow:
    call rt_overflow_err
    times RT_STR_CAT_SIZE - ($ - rt_str_cat) db 0x90

; ── rt_str_eq (256B) ─────────────────────────────────────────────────────────
rt_str_eq:
    cmp rsi, rcx
    jne .fail
    test rsi, rsi
    jz .success
    ; use SSE2 for >= 16 bytes
    mov rcx, rsi
    xor rax, rax
.loop:
    cmp rcx, 16
    jl .scalar
    movdqu xmm0, [rdi+rax]
    movdqu xmm1, [rdx+rax]
    pcmpeqb xmm0, xmm1
    pmovmskb r8d, xmm0
    cmp r8d, 0xFFFF
    jne .fail
    add rax, 16
    sub rcx, 16
    jnz .loop
    jmp .success
.scalar:
    test rcx, rcx
    jz .success
.sloop:
    mov r8b, [rdi+rax]
    cmp r8b, [rdx+rax]
    jne .fail
    inc rax
    loop .sloop
.success:
    mov rax, 1
    ret
.fail:
    xor rax, rax
    ret
    times RT_STR_EQ_SIZE - ($ - rt_str_eq) db 0x90

; ── rt_str_find (512B) ───────────────────────────────────────────────────────
rt_str_find:
    push rbx
    push r12
    push r13
    push r14
    test rcx, rcx
    jz .found_zero
    cmp rcx, rsi
    jg .not_found
    
    mov r12, rdi ; haystack
    mov r13, rsi ; hlen
    mov r14, rdx ; needle
    mov rbx, rcx ; nlen
    
    xor r8, r8 ; index
.outer:
    mov rax, r13
    sub rax, r8
    cmp rax, rbx
    jl .not_found
    
    ; compare first 16 bytes of needle if possible
    movzx eax, byte [r14]
    movd xmm1, eax
    punpcklbw xmm1, xmm1
    punpcklwd xmm1, xmm1
    pshufd xmm1, xmm1, 0 ; xmm1 = [first_char]*16
    
.scan:
    mov rax, r13
    sub rax, r8
    cmp rax, 16
    jl .scalar_scan
    
    movdqu xmm0, [r12+r8]
    pcmpeqb xmm0, xmm1
    pmovmskb eax, xmm0
    test eax, eax
    jnz .match_candidate
    add r8, 16
    jmp .outer
    
.match_candidate:
    bsf eax, eax
    add r8, rax
    ; verify full needle
    mov rax, r13
    sub rax, r8
    cmp rax, rbx
    jl .not_found
    
    push rsi
    push rdi
    push rcx
    lea rdi, [r12+r8]
    mov rsi, r14
    mov rcx, rbx
    repe cmpsb
    pop rcx ; BUG-13 fix: restore rcx after repe cmpsb
    pop rdi
    pop rsi
    je .found
    inc r8
    jmp .outer

.scalar_scan:
    mov al, [r12+r8]
    cmp al, [r14]
    je .verify_scalar
    inc r8
    jmp .outer
.verify_scalar:
    push rsi
    push rdi
    push rcx
    lea rdi, [r12+r8]
    mov rsi, r14
    mov rcx, rbx
    repe cmpsb
    pop rcx ; BUG-13 fix: restore rcx after repe cmpsb
    pop rdi
    pop rsi
    je .found
    inc r8
    jmp .outer

.found:
    mov rax, r8
    jmp .done
.found_zero:
    xor rax, rax
    jmp .done
.not_found:
    mov rax, -1
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
    times RT_STR_FIND_SIZE - ($ - rt_str_find) db 0x90

; ── rt_str_len (128B) ────────────────────────────────────────────────────────
rt_str_len:
    push rdi
    xor eax, eax
    mov rcx, -1
    repne scasb
    not rcx
    dec rcx
    mov rax, rcx
    pop rdi
    ret
    times RT_STR_LEN_SIZE - ($ - rt_str_len) db 0x90

; ── rt_str_upper (256B) ──────────────────────────────────────────────────────
rt_str_upper:
    test rsi, rsi
    jz .done
    mov rcx, rsi
    xor rax, rax
.loop:
    cmp rcx, 16
    jl .scalar
    movdqu xmm0, [rdi+rax]
    movdqa xmm1, xmm0
    ; mask = (x >= 'a' && x <= 'z')
    ; x >= 'a' -> x - 'a' >= 0
    ; but psubusb is better: psubusb xmm0, 'a' (will be 0 if < 'a')
    ; actually, SIMD trick for upper:
    ; mask = (char - 'a' < 26)
    ; char - 'a'
    movdqa xmm2, xmm0
    mov rax, 0x6161616161616161
    movq xmm3, rax
    punpcklbw xmm3, xmm3
    psubb xmm2, xmm3
    ; compare < 26
    mov rax, 0x1A1A1A1A1A1A1A1A
    movq xmm3, rax
    punpcklbw xmm3, xmm3
    ; pcmpgtb is signed, so we need unsigned comparison or range check
    ; let's just do scalar for now to be safe and simple, or use a better SIMD mask
    jmp .scalar 

.scalar:
    mov al, [rdi]
    cmp al, 'a'
    jl .next
    cmp al, 'z'
    jg .next
    sub al, 32
    mov [rdi], al
.next:
    inc rdi
    loop .scalar
.done:
    ret
    times RT_STR_UPPER_SIZE - ($ - rt_str_upper) db 0x90

; ── rt_str_lower (256B) ──────────────────────────────────────────────────────
rt_str_lower:
    test rsi, rsi
    jz .done
    mov rcx, rsi
.loop:
    mov al, [rdi]
    cmp al, 'A'
    jl .next
    cmp al, 'Z'
    jg .next
    add al, 32
    mov [rdi], al
.next:
    inc rdi
    loop .loop
.done:
    ret
    times RT_STR_LOWER_SIZE - ($ - rt_str_lower) db 0x90

; ── rt_str_trim (256B) ───────────────────────────────────────────────────────
rt_str_trim:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi ; ptr
    mov r13, rsi ; len
    test rsi, rsi
    jz .empty
    
    ; find start
    xor rbx, rbx
.start_loop:
    cmp rbx, r13
    je .empty
    cmp byte [r12+rbx], ' '
    jne .found_start
    inc rbx
    jmp .start_loop
.found_start:
    ; find end
    mov r14, r13
    dec r14
.end_loop:
    cmp r14, rbx
    jl .empty
    cmp byte [r12+r14], ' '
    jne .found_end
    dec r14
    jmp .end_loop
.found_end:
    ; new len = r14 - rbx + 1
    mov rsi, r14
    sub rsi, rbx
    inc rsi
    lea rdi, [r12+rbx]
    mov rdx, rsi
    ; allocate and copy
    push rdx
    push rdi
    lea rdi, [rdx+1]
    call rt_alc
    mov rbx, rax
    pop rsi
    pop rdx
    mov rdi, rbx
    mov rcx, rdx
    rep movsb
    mov byte [rdi], 0
    mov rax, rbx
    jmp .done

.empty:
    mov rdi, 1
    call rt_alc
    mov byte [rax], 0
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
    times RT_STR_TRIM_SIZE - ($ - rt_str_trim) db 0x90

; ── rt_str_rev (256B) ────────────────────────────────────────────────────────
rt_str_rev:
    test rsi, rsi
    jz .done
    lea rsi, [rdi+rsi-1] ; end
.loop:
    cmp rdi, rsi
    jge .done
    mov al, [rdi]
    mov bl, [rsi]
    mov [rdi], bl
    mov [rsi], al
    inc rdi
    dec rsi
    jmp .loop
.done:
    ret
    times RT_STR_REV_SIZE - ($ - rt_str_rev) db 0x90

; ── rt_int2str (256B) ────────────────────────────────────────────────────────
rt_int2str:
    push rbx
    push r12
    push r13
    sub rsp, 32
    mov r12, rdi
    lea r13, [rsp+31]
    mov byte [r13], 0
    xor rbx, rbx
    test r12, r12
    jz .zero
    jns .pos
    neg r12
    mov rbx, 1
.pos:
    mov rax, r12
    mov rcx, 10
.lp:
    xor rdx, rdx
    div rcx
    add dl, '0'
    dec r13
    mov [r13], dl
    test rax, rax
    jnz .lp
    test rbx, rbx
    jz .alloc
    dec r13
    mov byte [r13], '-'
    jmp .alloc
.zero:
    dec r13
    mov byte [r13], '0'
.alloc:
    lea rdx, [rsp+31]
    sub rdx, r13 ; len
    push rdx
    push r13
    lea rdi, [rdx+1]
    call rt_alc
    pop rsi
    pop rdx
    mov rdi, rax
    push rax
    push rdx
    mov rcx, rdx
    rep movsb
    mov byte [rdi], 0
    pop rdx
    pop rax
    add rsp, 32
    pop r13
    pop r12
    pop rbx
    ret
    times RT_INT2STR_SIZE - ($ - rt_int2str) db 0x90

; ── rt_float2str (512B) ──────────────────────────────────────────────────────
rt_float2str:
    push rbx
    push r12
    push r13
    sub rsp, 64
    movq rax, xmm0
    mov r12, rsp
    xor r13, r13
    test rax, rax
    jns .pos
    mov byte [r12+r13], '-'
    inc r13
.pos:
    movq rax, xmm0
    mov r10, 0x7FFFFFFFFFFFFFFF
    and rax, r10
    movq xmm0, rax
    cvttsd2si rbx, xmm0
    cvtsi2sd xmm1, rbx
    subsd xmm0, xmm1
    ; int part
    mov rdi, rbx
    sub rsp, 8
    movsd [rsp], xmm0
    call .u64_to_buf
    movsd xmm0, [rsp]
    add rsp, 8
    mov byte [r12+r13], '.'
    inc r13
    ; 6 dec places
    mov rcx, 6
.dec_lp:
    mov rax, 10
    cvtsi2sd xmm1, rax
    mulsd xmm0, xmm1
    cvttsd2si rax, xmm0
    cvtsi2sd xmm1, rax
    subsd xmm0, xmm1
    add al, '0'
    mov [r12+r13], al
    inc r13
    loop .dec_lp
    ; alloc and copy
    mov rdx, r13
    lea rdi, [rdx+1]
    call rt_alc
    mov rdi, rax
    mov rsi, r12
    mov rcx, rdx
    rep movsb
    mov byte [rdi], 0
    mov rax, rdi
    sub rax, rdx
    add rsp, 64
    pop r13
    pop r12
    pop rbx
    ret

.u64_to_buf:
    test rdi, rdi
    jnz .nz
    mov byte [r12+r13], '0'
    inc r13
    ret
.nz:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    lea rcx, [rsp+31]
    mov rax, rdi
    mov r8, 10
.lp:
    xor rdx, rdx
    div r8
    add dl, '0'
    mov [rcx], dl
    dec rcx
    test rax, rax
    jnz .lp
    inc rcx
.copy:
    mov al, [rcx]
    mov [r12+r13], al
    inc r13
    inc rcx
    lea rdx, [rsp+32]
    cmp rcx, rdx
    jne .copy
    mov rsp, rbp
    pop rbp
    ret
    times RT_FLOAT2STR_SIZE - ($ - rt_float2str) db 0x90

; ── rt_str_split (512B) ──────────────────────────────────────────────────────
rt_str_split:
    ; rdi=str, rsi=len, rdx=delim
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi ; str
    mov r13, rsi ; len
    mov r14, rdx ; delim
    
    ; count parts
    mov rcx, r13
    mov rbx, 1
    xor rax, rax
.count_lp:
    test rcx, rcx
    jz .alloc_seq
    cmp byte [r12+rax], r14b
    jne .next_count
    inc rbx
.next_count:
    inc rax
    loop .count_lp

.alloc_seq:
    ; seq header: [len:8][cap:8][data...]
    ; data is pointers to strings
    mov r15, rbx ; count
    ; check overflow: count*8 + 16
    mov rax, r15
    mov rcx, 8
    mul rcx
    jc .overflow
    add rax, 16
    jc .overflow
    mov rdi, rax
    call rt_alc
    mov qword [rax], r15
    mov qword [rax+8], r15
    lea rbx, [rax+16] ; pointer to elements
    mov r11, rax ; seq ptr
    
    xor r10, r10 ; current offset
    xor r9, r9  ; start of current part
.split_lp:
    cmp r10, r13
    je .last_part
    cmp byte [r12+r10], r14b
    jne .next_char
    ; extract part [r9...r10-1]
    mov rsi, r10
    sub rsi, r9 ; part len
    lea rdi, [r12+r9]
    call .copy_part
    mov [rbx], rax
    add rbx, 8
    lea r9, [r10+1]
.next_char:
    inc r10
    jmp .split_lp

.last_part:
    mov rsi, r13
    sub rsi, r9
    lea rdi, [r12+r9]
    call .copy_part
    mov [rbx], rax
    mov rax, r11
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.overflow:
    call rt_overflow_err

.copy_part:
    ; rdi=src, rsi=len
    push rsi
    push rdi
    lea rdi, [rsi+1]
    call rt_alc
    pop rsi
    pop rcx
    mov rdi, rax
    push rax
    rep movsb
    mov byte [rdi], 0
    pop rax
    ret
    times RT_STR_SPLIT_SIZE - ($ - rt_str_split) db 0x90

; ── rt_str_join (512B) ───────────────────────────────────────────────────────
rt_str_join:
    ; rdi=seq_ptr, rsi=sep_ptr, rdx=sep_len
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi ; seq
    mov r13, rsi ; sep
    mov r14, rdx ; sep_len
    
    mov rbx, [r12] ; count
    test rbx, rbx
    jz .empty
    
    ; calc total len
    xor r15, r15 ; total len
    xor rcx, rcx
.len_lp:
    cmp rcx, rbx
    je .alloc
    mov rax, [r12 + 16 + rcx*8]
    push rcx
    mov rdi, rax
    call rt_str_len
    pop rcx
    add r15, rax
    inc rcx
    cmp rcx, rbx
    je .len_lp
    add r15, r14
    jmp .len_lp

.alloc:
    lea rdi, [r15+1]
    jc .overflow
    call rt_alc
    mov r11, rax ; result
    mov rdi, rax
    xor rcx, rcx
.join_lp:
    cmp rcx, rbx
    je .done
    mov rsi, [r12 + 16 + rcx*8]
    push rcx
    push rsi
    mov rdi, rsi
    call rt_str_len
    mov rdx, rax
    pop rsi
    mov rcx, rdx
    rep movsb
    pop rcx
    inc rcx
    cmp rcx, rbx
    je .done
    ; copy separator
    push rcx
    mov rsi, r13
    mov rcx, r14
    rep movsb
    pop rcx
    jmp .join_lp

.overflow:
    call rt_overflow_err

.empty:
    mov rdi, 1
    call rt_alc
    mov byte [rax], 0
    jmp .exit
.done:
    mov byte [rdi], 0
    mov rax, r11
.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
    times RT_STR_JOIN_SIZE - ($ - rt_str_join) db 0x90

; ── rt_str_starts (256B) ─────────────────────────────────────────────────────
rt_str_starts:
    cmp rsi, rcx
    jl .fail
    mov rsi, rdx
    repe cmpsb
    je .pass
.fail:
    xor rax, rax
    ret
.pass:
    mov rax, 1
    ret
    times RT_STR_STARTS_SIZE - ($ - rt_str_starts) db 0x90

; ── rt_str_ends (256B) ───────────────────────────────────────────────────────
rt_str_ends:
    cmp rsi, rcx
    jl .fail
    add rdi, rsi
    sub rdi, rcx
    mov rsi, rdx
    repe cmpsb
    je .pass
.fail:
    xor rax, rax
    ret
.pass:
    mov rax, 1
    ret
    times RT_STR_ENDS_SIZE - ($ - rt_str_ends) db 0x90

; ── rt_str_contains (128B) ───────────────────────────────────────────────────
rt_str_contains:
    call rt_str_find
    cmp rax, -1
    setne al
    movzx rax, al
    ret
    times RT_STR_CONTAINS_SIZE - ($ - rt_str_contains) db 0x90

; ── rt_str_slice (256B) ──────────────────────────────────────────────────────
rt_str_slice:
    ; rdi=ptr, rsi=len, rdx=start, rcx=end
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rdx ; start
    mov r14, rcx ; end
    cmp r13, 0
    jl .empty
    cmp r14, rsi
    jg .empty
    cmp r13, r14
    jge .empty
    
    mov rsi, r14
    sub rsi, r13 ; len
    lea rdi, [rsi+1]
    push rsi
    call rt_alc
    pop rcx
    mov rdi, rax
    lea rsi, [r12+r13]
    push rax
    rep movsb
    mov byte [rdi], 0
    pop rax
    jmp .done

.empty:
    mov rdi, 1
    call rt_alc
    mov byte [rax], 0
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
    times RT_STR_SLICE_SIZE - ($ - rt_str_slice) db 0x90

; ── rt_str_replace (512B) ────────────────────────────────────────────────────
rt_str_replace:
    ; simplified: just allocate a large enough buffer for now
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 64
    ; TODO: Implement full replacement
    ; For now, just return a copy of the string to satisfy build
    mov rdi, rsi
    inc rdi
    call rt_alc
    mov rdi, rax
    mov rsi, rdi
    mov rcx, rsi
    rep movsb
    mov byte [rdi], 0
    mov rax, rdi
    add rsp, 64
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
    times RT_STR_REPLACE_SIZE - ($ - rt_str_replace) db 0x90

; ── rt_str_count (256B) ──────────────────────────────────────────────────────
rt_str_count:
    xor rax, rax
    ret
    times RT_STR_COUNT_SIZE - ($ - rt_str_count) db 0x90

; ── rt_str_repeat (256B) ─────────────────────────────────────────────────────
rt_str_repeat:
    xor rax, rax
    ret
    times RT_STR_REPEAT_SIZE - ($ - rt_str_repeat) db 0x90

; ── rt_math_sqrt (64B) ───────────────────────────────────────────────────────
rt_math_sqrt:
    sqrtsd xmm0, xmm0
    ret
    times RT_MATH_SQRT_SIZE - ($ - rt_math_sqrt) db 0x90

; ── rt_math_floor (64B) ──────────────────────────────────────────────────────
rt_math_floor:
    roundsd xmm0, xmm0, 1
    ret
    times RT_MATH_FLOOR_SIZE - ($ - rt_math_floor) db 0x90

; ── rt_math_ceil (64B) ───────────────────────────────────────────────────────
rt_math_ceil:
    roundsd xmm0, xmm0, 2
    ret
    times RT_MATH_CEIL_SIZE - ($ - rt_math_ceil) db 0x90

; ── rt_math_abs_f (64B) ──────────────────────────────────────────────────────
rt_math_abs_f:
    mov rax, 0x7FFFFFFFFFFFFFFF
    movq xmm1, rax
    andpd xmm0, xmm1
    ret
    times RT_MATH_ABS_F_SIZE - ($ - rt_math_abs_f) db 0x90

; ── rt_math_sin (128B) ───────────────────────────────────────────────────────
rt_math_sin:
    movsd [rsp-8], xmm0
    fld qword [rsp-8]
    fsin
    fstp qword [rsp-8]
    movsd xmm0, [rsp-8]
    ret
    times RT_MATH_SIN_SIZE - ($ - rt_math_sin) db 0x90

; ── rt_math_cos (128B) ───────────────────────────────────────────────────────
rt_math_cos:
    movsd [rsp-8], xmm0
    fld qword [rsp-8]
    fcos
    fstp qword [rsp-8]
    movsd xmm0, [rsp-8]
    ret
    times RT_MATH_COS_SIZE - ($ - rt_math_cos) db 0x90

; ── rt_math_exp (256B) — e^x via x87 (xmm0 in/out) ─────────────────────────
rt_math_exp:
    ; exp(x) = 2^(x * log2(e)), using x87 f2xm1 + fscale
    movsd [rsp-8], xmm0       ; store x
    fld qword [rsp-8]          ; st0 = x
    fldl2e                     ; st0 = log2(e), st1 = x
    fmulp                      ; st0 = x * log2(e)   (pops both, pushes result)
    ; compute 2^st0
    fld st0                    ; st0 = y (copy), st1 = y
    frndint                    ; st0 = floor(y)
    fxch st1                   ; st0 = y, st1 = floor(y)
    fsub st0, st1              ; st0 = frac = y - floor(y)
    f2xm1                      ; st0 = 2^frac - 1
    fld1                       ; st0 = 1.0
    faddp                      ; st0 = 2^frac
    fscale                     ; st0 = 2^frac * 2^floor(y) = 2^y = e^x
    fstp qword [rsp-8]         ; store result, pop st0
    fstp st0                   ; discard floor(y) (st1 left from fscale)
    movsd xmm0, [rsp-8]       ; return value in xmm0
    ret
    times RT_MATH_EXP_SIZE - ($ - rt_math_exp) db 0x90

; ── rt_math_log (256B) — ln(x) via x87 fyl2x (xmm0 in/out) ─────────────────
rt_math_log:
    ; ln(x) = log2(x) * ln(2) — fyl2x computes y*log2(x): st1=y, st0=x → result
    movsd [rsp-8], xmm0       ; store x
    fld qword [rsp-8]          ; st0 = x
    fldln2                     ; st0 = ln(2), st1 = x
    fxch st1                   ; st0 = x, st1 = ln(2)
    fyl2x                      ; st0 = ln(2) * log2(x) = ln(x)
    fstp qword [rsp-8]         ; store result
    movsd xmm0, [rsp-8]       ; return value in xmm0
    ret
    times RT_MATH_LOG_SIZE - ($ - rt_math_log) db 0x90

; ── rt_math_pow (256B) — x^y via x87 fyl2x + f2xm1+fscale (xmm0=x, xmm1=y) ─
rt_math_pow:
    ; pow(x,y) = 2^(y*log2(x)) — uses 16 bytes on red zone
    sub rsp, 16
    movsd [rsp], xmm0         ; [rsp]   = x (base)
    movsd [rsp+8], xmm1       ; [rsp+8] = y (exponent)
    fld qword [rsp]            ; st0 = x
    fld qword [rsp+8]          ; st0 = y, st1 = x
    fxch st1                   ; st0 = x, st1 = y
    fyl2x                      ; st0 = y * log2(x)
    ; compute 2^st0
    fld st0                    ; st0 = t (copy), st1 = t
    frndint                    ; st0 = floor(t)
    fxch st1                   ; st0 = t, st1 = floor(t)
    fsub st0, st1              ; st0 = frac = t - floor(t)
    f2xm1                      ; st0 = 2^frac - 1
    fld1                       ; st0 = 1.0
    faddp                      ; st0 = 2^frac
    fscale                     ; st0 = 2^frac * 2^floor(t) = x^y
    fstp qword [rsp]           ; store result, pop st0
    fstp st0                   ; discard floor(t)
    movsd xmm0, [rsp]         ; return value in xmm0
    add rsp, 16
    ret
    times RT_MATH_POW_SIZE - ($ - rt_math_pow) db 0x90

; ── rt_math_min (64B) ────────────────────────────────────────────────────────
rt_math_min:
    minsd xmm0, xmm1
    ret
    times RT_MATH_MIN_SIZE - ($ - rt_math_min) db 0x90

; ── rt_math_max (64B) ────────────────────────────────────────────────────────
rt_math_max:
    maxsd xmm0, xmm1
    ret
    times RT_MATH_MAX_SIZE - ($ - rt_math_max) db 0x90

; ── rt_bounds_err (256B) ─────────────────────────────────────────────────────
rt_bounds_err:
    lea rdi, [rel .msg]
    call rt_prq
.msg: db "bounds error",0
    times RT_BOUNDS_ERR_SIZE - ($ - rt_bounds_err) db 0x90

; ── rt_overflow_err (256B) ───────────────────────────────────────────────────
rt_overflow_err:
    lea rdi, [rel .msg]
    call rt_prq
.msg: db "overflow error",0
    times RT_OVERFLOW_ERR_SIZE - ($ - rt_overflow_err) db 0x90

; ── rt_null_err (256B) ───────────────────────────────────────────────────────
rt_null_err:
    lea rdi, [rel .msg]
    call rt_prq
.msg: db "null dereference error",0
    times RT_NULL_ERR_SIZE - ($ - rt_null_err) db 0x90

; ── rt_seq_sort (1024B) ──────────────────────────────────────────────────────
; BUG-07 fix: implement in-place insertion sort (int64 elements).
; rdi = seq pointer (layout: [len:q][cap:q][data:N*q])
rt_seq_sort:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r15, [r12]              ; n = len
    test r15, r15
    jle .done
    cmp r15, 1
    jle .done
    lea r14, [r12+16]           ; r14 = data base pointer
    mov r13, 1                  ; i = 1 (outer loop index)
.outer:
    cmp r13, r15
    jge .done
    mov rbx, [r14+r13*8]       ; key = data[i]
    mov rcx, r13
    dec rcx                     ; j = i - 1
.inner:
    test rcx, rcx
    js .insert                  ; j < 0 (j wrapped to -1): insert at position 0
    mov rax, [r14+rcx*8]       ; rax = data[j]
    cmp rax, rbx
    jle .insert                 ; data[j] <= key: insert here (at j+1)
    mov rdx, rcx
    inc rdx
    mov [r14+rdx*8], rax       ; data[j+1] = data[j]  (shift right)
    dec rcx
    jmp .inner
.insert:
    inc rcx                     ; slot = j + 1
    mov [r14+rcx*8], rbx       ; data[j+1] = key
    inc r13
    jmp .outer
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
    times RT_SEQ_SORT_SIZE - ($ - rt_seq_sort) db 0x90

; ── rt_seq_sum (256B) ────────────────────────────────────────────────────────
rt_seq_sum:
    mov rsi, [rdi] ; len
    lea rdi, [rdi+16] ; data
    xor rax, rax
    test rsi, rsi
    jz .done
    mov rcx, rsi
.lp:
    add rax, [rdi]
    add rdi, 8
    loop .lp
.done:
    ret
    times RT_SEQ_SUM_SIZE - ($ - rt_seq_sum) db 0x90

; ── rt_seq_min (256B) ────────────────────────────────────────────────────────
; rdi = seq ptr → rax = minimum int64 element (0 if empty)
rt_seq_min:
    push rbx
    push r12
    mov r12, rdi
    mov rcx, [r12]              ; len
    test rcx, rcx
    jz .empty
    lea rdi, [r12+16]           ; data
    mov rbx, [rdi]              ; min = first element
    dec rcx
    jz .done
.loop:
    add rdi, 8
    mov rax, [rdi]
    cmp rax, rbx
    jge .no_update
    mov rbx, rax
.no_update:
    dec rcx
    jnz .loop
.done:
    mov rax, rbx
    pop r12
    pop rbx
    ret
.empty:
    xor rax, rax
    pop r12
    pop rbx
    ret
    times RT_SEQ_MIN_SIZE - ($ - rt_seq_min) db 0x90

; ── rt_seq_max (256B) ────────────────────────────────────────────────────────
; rdi = seq ptr → rax = maximum int64 element (0 if empty)
rt_seq_max:
    push rbx
    push r12
    mov r12, rdi
    mov rcx, [r12]              ; len
    test rcx, rcx
    jz .empty
    lea rdi, [r12+16]           ; data
    mov rbx, [rdi]              ; max = first element
    dec rcx
    jz .done
.loop:
    add rdi, 8
    mov rax, [rdi]
    cmp rax, rbx
    jle .no_update
    mov rbx, rax
.no_update:
    dec rcx
    jnz .loop
.done:
    mov rax, rbx
    pop r12
    pop rbx
    ret
.empty:
    xor rax, rax
    pop r12
    pop rbx
    ret
    times RT_SEQ_MAX_SIZE - ($ - rt_seq_max) db 0x90

; ── rt_seq_contains (256B) ───────────────────────────────────────────────────
; rdi = seq ptr, rsi = int64 value to find → rax = 1 (found) or 0 (not found)
rt_seq_contains:
    push rbx
    mov rbx, rsi                ; value to find
    mov rcx, [rdi]              ; len
    test rcx, rcx
    jz .not_found
    lea rdi, [rdi+16]           ; data
.loop:
    cmp [rdi], rbx
    je .found
    add rdi, 8
    dec rcx
    jnz .loop
.not_found:
    xor rax, rax
    pop rbx
    ret
.found:
    mov rax, 1
    pop rbx
    ret
    times RT_SEQ_CONTAINS_SIZE - ($ - rt_seq_contains) db 0x90

; ── rt_seq_reverse (256B) ────────────────────────────────────────────────────
rt_seq_reverse:
    mov rcx, [rdi] ; len
    test rcx, rcx
    jz .done
    cmp rcx, 1
    jle .done
    lea rsi, [rdi+16] ; start
    lea rdx, [rdi+16+rcx*8-8] ; end
.lp:
    cmp rsi, rdx
    jge .done
    mov rax, [rsi]
    mov rbx, [rdx]
    mov [rsi], rbx
    mov [rdx], rax
    add rsi, 8
    sub rdx, 8
    jmp .lp
.done:
    ret
    times RT_SEQ_REVERSE_SIZE - ($ - rt_seq_reverse) db 0x90

; ── rt_seq_pop (256B) ────────────────────────────────────────────────────────
; rdi = seq ptr → rax = popped value (0 if empty)
rt_seq_pop:
    mov rcx, [rdi] ; len
    test rcx, rcx
    jz .empty
    dec rcx
    mov [rdi], rcx ; update len
    mov rax, [rdi+rcx*8+16] ; load value
    ret
.empty:
    xor rax, rax
    ret
    times 256 - ($ - rt_seq_pop) db 0x90

; ── rt_str_idx (256B) ────────────────────────────────────────────────────────
; rdi = str ptr, rsi = index → rax = new single-char string ptr
rt_str_idx:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    ; allocate 2 bytes (1 char + NUL)
    mov rdi, 2
    call rt_alc
    mov rbx, rax
    mov al, [r12+r13]
    mov [rbx], al
    mov byte [rbx+1], 0
    mov rax, rbx
    pop r13
    pop r12
    pop rbx
    ret
    times 256 - ($ - rt_str_idx) db 0x90

; ── rt_heap_alloc (1024B) ────────────────────────────────────────────────────
rt_heap_alloc:
    call rt_alc
    ret
    times RT_HEAP_ALLOC_SIZE - ($ - rt_heap_alloc) db 0x90

; ── rt_heap_free (512B) ──────────────────────────────────────────────────────
rt_heap_free:
    ret
    times RT_HEAP_FREE_SIZE - ($ - rt_heap_free) db 0x90

; ── rt_static_alloc (256B) ───────────────────────────────────────────────────
rt_static_alloc:
    call rt_alc
    ret
    times RT_STATIC_ALLOC_SIZE - ($ - rt_static_alloc) db 0x90
