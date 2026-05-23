; codegen.asm - Code Generator for Rex
; Generates x86_64 machine code and ELF64 header

%include "src/include/common.inc"

section .data
    ; ELF Header (64-bit)
    elf_header:
        db 0x7F, 'ELF', 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0
        dw 2, 62
        dd 1
        dq 0x400000 + 120    ; e_entry
        dq 0x40             ; e_phoff
        dq 0                ; e_shoff
        dd 0                ; e_flags
        dw 64, 56, 1, 64, 0, 0

    program_header:
        dd 1                ; p_type (PT_LOAD)
        dd 7                ; p_flags (PF_R | PF_W | PF_X)
        dq 0                ; p_offset
        dq 0x400000         ; p_vaddr
        dq 0x400000         ; p_paddr
        dq 0                ; p_filesz
        dq 0                ; p_memsz
        dq 0x1000           ; p_align

    out_filename db "output", 0

section .bss
    code_buffer resb 65536
    code_ptr    resq 1
    out_fd      resq 1

section .text
    global rex_codegen_init
    global rex_emit_byte
    global rex_emit_dq
    global rex_emit_mov_rax_imm
    global rex_emit_push_rax
    global rex_emit_pop_rax
    global rex_emit_pop_rcx
    global rex_emit_add_rax_rcx
    global rex_emit_sub_rax_rcx
    global rex_emit_mul_rcx
    global rex_emit_syscall
    global rex_emit_call_rax
    global rex_emit_cmp_rax_rcx
    global rex_emit_jmp
    global rex_emit_je
    global rex_finish

rex_codegen_init:
    lea rax, [code_buffer]
    mov [code_ptr], rax
    ret

rex_emit_byte:
    mov rdx, [code_ptr]
    mov [rdx], dil
    inc qword [code_ptr]
    ret

rex_emit_dq:
    mov rdx, [code_ptr]
    mov [rdx], rdi
    add qword [code_ptr], 8
    ret

rex_emit_mov_rax_imm:
    mov r9, rdi
    mov dil, 0x48 \ call rex_emit_byte
    mov dil, 0xB8 \ call rex_emit_byte
    mov rdi, r9
    call rex_emit_dq
    ret

rex_emit_push_rax:
    mov dil, 0x50 \ call rex_emit_byte
    ret

rex_emit_pop_rax:
    mov dil, 0x58 \ call rex_emit_byte
    ret

rex_emit_pop_rcx:
    mov dil, 0x59 \ call rex_emit_byte
    ret

rex_emit_add_rax_rcx:
    mov dil, 0x48 \ call rex_emit_byte
    mov dil, 0x01 \ call rex_emit_byte
    mov dil, 0xC8 \ call rex_emit_byte
    ret

rex_emit_sub_rax_rcx:
    mov dil, 0x48 \ call rex_emit_byte
    mov dil, 0x29 \ call rex_emit_byte
    mov dil, 0xC8 \ call rex_emit_byte
    ret

rex_emit_mul_rcx:
    mov dil, 0x48 \ call rex_emit_byte
    mov dil, 0xF7 \ call rex_emit_byte
    mov dil, 0xE1 \ call rex_emit_byte
    ret

rex_emit_syscall:
    mov dil, 0x0F \ call rex_emit_byte
    mov dil, 0x05 \ call rex_emit_byte
    ret

rex_emit_call_rax:
    mov dil, 0xFF \ call rex_emit_byte
    mov dil, 0xD0 \ call rex_emit_byte
    ret

rex_emit_cmp_rax_rcx:
    mov dil, 0x48 \ call rex_emit_byte
    mov dil, 0x39 \ call rex_emit_byte
    mov dil, 0xC8 \ call rex_emit_byte
    ret

; Simple relative jumps
rex_emit_jmp:
    mov dil, 0xE9 \ call rex_emit_byte
    mov rdi, 0 ; placeholder
    mov rdx, [code_ptr] \ mov [rdx], edi \ add qword [code_ptr], 4
    ret

rex_emit_je:
    mov dil, 0x0F \ call rex_emit_byte
    mov dil, 0x84 \ call rex_emit_byte
    mov rdi, 0 ; placeholder
    mov rdx, [code_ptr] \ mov [rdx], edi \ add qword [code_ptr], 4
    ret

rex_finish:
    lea rbx, [code_buffer]
    mov rdx, [code_ptr]
    sub rdx, rbx

    mov rax, rdx
    add rax, 120
    mov [program_header + 32], rax
    mov [program_header + 40], rax

    mov rax, SYS_OPEN
    mov rdi, out_filename
    mov rsi, O_CREAT | O_WRONLY | O_TRUNC
    mov rdx, 0755o
    syscall
    mov [out_fd], rax

    mov rdi, rax
    mov rax, SYS_WRITE
    mov rsi, elf_header
    mov rdx, 64
    syscall

    mov rdi, [out_fd]
    mov rax, SYS_WRITE
    mov rsi, program_header
    mov rdx, 56
    syscall

    mov rdi, [out_fd]
    mov rax, SYS_WRITE
    lea rsi, [code_buffer]
    mov rdx, [code_ptr]
    sub rdx, rsi
    syscall

    mov rax, SYS_CLOSE
    mov rdi, [out_fd]
    syscall
    ret
