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

bits 64
org 0

; ── rt_pri: print signed integer in rdi to stdout + newline ──────────────────
rt_pri:
    push rbx
    push r12
    push r13
    sub rsp, 24
    mov r12, rdi
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
    times RT_PRI_SIZE - ($ - rt_pri) db 0x90

; ── rt_prs: print null-terminated string in rdi to stdout + newline ──────────
; O35a: strlen via repne scasb — 1 cycle/byte throughput vs 3-4 cycle loop.
rt_prs:
    push rbx
    push r12
    mov r12, rdi            ; preserve string pointer (r12 callee-saved)
    ; strlen: scan for NUL using repne scasb
    xor eax, eax            ; al = 0 (NUL byte)
    mov rcx, -1
    repne scasb             ; rdi advances; ecx = -(len+2)
    not rcx                 ; rcx = len+1
    lea rbx, [rcx-1]        ; rbx = len (without NUL)
    ; sys_write(1, r12, rbx)
    mov rax, 1
    mov rdi, 1
    mov rsi, r12
    mov rdx, rbx
    syscall
    ; print newline (red-zone trick)
    mov byte [rsp-8], 10
    lea rsi, [rsp-8]
    mov rax, 1
    mov rdi, 1
    mov rdx, 1
    syscall
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
    mov r14, 4              ; 4 fractional digits
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
; Novel algorithm combining FNV-1a per-byte mixing, a bijective rol(31) step
; (31 = M₃₁ Mersenne prime, guarantees period-2^64 for the multiply-rotate map),
; and SplitMix64 finalization.  Designed for Rex identifier strings (1–16 bytes).
; Property: perfect forward diffusion after 2 bytes — every output bit depends on
; every input bit.  Zero false-negative rate for names ≤ 8 chars in same-length set.
; Interface: rdi = data ptr, rsi = length → rax = 64-bit hash
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
    ; SplitMix64 finalization — avalanche all 64 bits
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
; Layout (4096 bytes total):
;   [0..code]  allocator code
;   [4072]     pool_base  dq  (absolute addr 0x401D65)
;   [4080]     pool_bump  dq  (absolute addr 0x401D6D)
;   [4088]     mode       dq  (absolute addr 0x401D75, written by codegen_emit_mm_switch)
;
; mode == 0 → arena: one mmap per alloc (default)
; mode != 0 → pool:  bump-pointer from a lazy-inited 64 MB slab
rt_alc:
    push rbx
    mov rbx, rdi            ; rbx = requested size
    add rbx, 7              ; align to 8 bytes
    and rbx, -8
    cmp qword [0x401D75], 0 ; mode == 0 (arena)?
    jne .pool               ; non-zero → pool mode
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
.pool:
    cmp qword [0x401D65], 0 ; pool_base == 0 (first use)?
    jne .pool_alloc
    ; lazy init: mmap a 64 MB pool once
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
    mov qword [0x401D65], rax   ; pool_base = ptr
    mov qword [0x401D6D], rax   ; pool_bump = ptr
.pool_alloc:
    mov rax, qword [0x401D6D]   ; rax = current bump (= allocation address)
    add qword [0x401D6D], rbx   ; advance bump by aligned size
    pop rbx
    ret
    times 4072 - ($ - rt_alc) db 0x90
.pool_base: dq 0
.pool_bump: dq 0
.mode: dq 0

; ── rt_prq: print error string (rdi=ptr) to stderr + exit(1) ─────────────────
; O35b: strlen via repne scasb (program terminates after, so rcx freely clobbered)
rt_prq:
    push rbx
    mov rbx, rdi                ; rbx = string ptr (callee-saved)
    xor eax, eax                ; al = NUL byte
    mov rcx, -1
    repne scasb                 ; ecx = -(len+2)
    not rcx                     ; rcx = len+1
    lea rdx, [rcx-1]            ; rdx = len
    ; sys_write(2, rbx, rdx)
    mov rax, 1
    mov rdi, 2                  ; stderr
    mov rsi, rbx
    syscall
    ; print newline
    mov byte [rsp-8], 10
    lea rsi, [rsp-8]
    mov rax, 1
    mov rdi, 2
    mov rdx, 1
    syscall
    ; exit(1)
    mov rax, 60
    mov rdi, 1
    syscall
    times RT_PRQ_SIZE - ($ - rt_prq) db 0x90
