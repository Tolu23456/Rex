; random.asm - Pseudo-Random Number Generator for Rex
; Implements a simple Xorshift64* PRNG for the 'unknown' boolean state

section .data
    ; Seed for the PRNG
    prng_seed dq 0x123456789ABCDEF0

section .text
    global rex_random_init
    global rex_get_random_bool

; Initialise the PRNG seed using getrandom syscall
rex_random_init:
    push rax
    push rdi
    push rsi
    push rdx

    mov rax, 318            ; SYS_GETRANDOM
    mov rdi, prng_seed      ; buffer
    mov rsi, 8              ; count
    xor rdx, rdx            ; flags
    syscall

    pop rdx
    pop rsi
    pop rdi
    pop rax
    ret

; Returns a random boolean (0 or 1) in RAX
; Also used for the 'unknown' state in Rex
rex_get_random_bool:
    push rbx

    mov rax, [prng_seed]    ; Load current seed
    mov rbx, rax
    shl rbx, 13
    xor rax, rbx
    mov rbx, rax
    shr rbx, 7
    xor rax, rbx
    mov rbx, rax
    shl rbx, 17
    xor rax, rbx
    mov [prng_seed], rax    ; Store new seed

    ; Simple way to get 0 or 1: check parity or bit
    and rax, 1              ; RAX is now 0 or 1

    pop rbx
    ret
