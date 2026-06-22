; ============================================================
; rt_sip — RXHASH-64: FNV-1a per-byte + M31 rotation + SplitMix64
; Input:  rdi = key pointer, rsi = key length (bytes)
; Output: rax = 64-bit hash
; Clobbers: rax, rbx, rcx, rdi, r9, r10
; Preserves: rdx, rsi, rbp, r11–r15
; ============================================================
bits 64
%include "rex_defs.inc"
org LOAD_BASE + RT_SIP_OFFSET

rt_sip_blob:
    mov     rax, 0xcbf29ce484222325  ; FNV offset basis / seed

    test    rsi, rsi
    jz      .finalize

    mov     rbx, 0x100000001b3       ; FNV prime
    mov     rcx, rsi                 ; byte count

.mix_loop:
    movzx   r9d, byte [rdi]
    xor     rax, r9
    imul    rax, rbx
    inc     rdi
    dec     rcx
    jnz     .mix_loop

    rol     rax, 31                  ; M₃₁ bijection

.finalize:
    ; SplitMix64 step 1: rax ^= rax >> 30
    mov     r9, rax
    shr     r9, 30
    xor     rax, r9
    mov     r9, 0xbf58476d1ce4e5b9
    imul    rax, r9

    ; SplitMix64 step 2: rax ^= rax >> 27
    mov     r9, rax
    shr     r9, 27
    xor     rax, r9
    mov     r9, 0x94d049bb133111eb
    imul    rax, r9

    ; SplitMix64 step 3: rax ^= rax >> 31
    mov     r9, rax
    shr     r9, 31
    xor     rax, r9

    ret

times RT_SIP_SIZE - ($ - rt_sip_blob) db 0x90
