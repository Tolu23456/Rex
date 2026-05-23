; siphash.asm - Full SipHash-2-4 implementation

section .text
    global rex_siphash

; rex_siphash(key[16], data, len)
rex_siphash:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov r8, [rdi]       ; k0
    mov r9, [rdi + 8]   ; k1

    mov r10, 0x736f6d6570736575
    xor r10, r8
    mov r11, 0x646f72616e646f6d
    xor r11, r9
    mov r12, 0x6c7967656e657261
    xor r12, r8
    mov r13, 0x7465646279746573
    xor r13, r9

    mov rcx, rdx
    shr rcx, 3
    jz .process_tail

.block_loop:
    mov r14, [rsi]
    xor r13, r14
    call sipround
    call sipround
    xor r10, r14
    add rsi, 8
    dec rcx
    jnz .block_loop

.process_tail:
    mov rcx, rdx
    and rcx, 7
    xor r14, r14

    ; Load tail bytes
    test rcx, rcx
    jz .tail_done

    ; Simple loop for tail bytes
    xor rbx, rbx
.tail_loop:
    movzx rax, byte [rsi + rbx]
    mov rdx, rbx
    shl rdx, 3
    mov rbp, rax
    mov rdi, rcx ; backup rcx
    mov rcx, rdx
    shl rbp, cl
    mov rcx, rdi
    or r14, rbp
    inc rbx
    cmp rbx, rcx
    jl .tail_loop

.tail_done:
    ; Length in top byte
    mov rax, rdx ; original length is in RDX
    shl rax, 56
    or r14, rax

    xor r13, r14
    call sipround
    call sipround
    xor r10, r14

    xor r12, 0xff
    call sipround
    call sipround
    call sipround
    call sipround

    mov rax, r10
    xor rax, r11
    xor rax, r12
    xor rax, r13

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

sipround:
    add r10, r11
    rol r11, 13
    xor r11, r10
    rol r10, 32

    add r12, r13
    rol r13, 16
    xor r13, r12

    add r12, r11
    rol r11, 17
    xor r11, r12
    rol r12, 32

    add r10, r13
    rol r13, 21
    xor r13, r10
    ret
