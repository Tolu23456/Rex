; codegen.asm - Code Generator for Rex
; Generates x86_64 machine code and ELF64 header

%include "src/include/common.inc"

section .data
    ; ELF Header (64-bit)
    elf_header:
        db 0x7F, 'ELF', 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0
        dw 2, 62
        dd 1
        dq 0x400000 + 0x78  ; e_entry
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
        dq 0                ; p_filesz (updated at finish)
        dq 0                ; p_memsz (updated at finish)
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
    global rex_emit_call
    global rex_finish

; Initialize the code generator
rex_codegen_init:
    lea rax, [code_buffer]
    mov [code_ptr], rax
    ret

; Emit a single byte
rex_emit_byte:
    mov rdx, [code_ptr]
    mov [rdx], dil
    inc qword [code_ptr]
    ret

; Emit 64-bit imm
rex_emit_dq:
    mov rdx, [code_ptr]
    mov [rdx], rdi
    add qword [code_ptr], 8
    ret

; Emit mov rax, imm64
rex_emit_mov_rax_imm:
    mov dil, 0x48
    call rex_emit_byte
    mov dil, 0xB8
    call rex_emit_byte
    call rex_emit_dq
    ret

; Emit call rel32 (placeholder logic)
rex_emit_call:
    mov dil, 0xE8
    call rex_emit_byte
    ; For now, emit dummy offset
    mov rdi, 0
    mov rdx, [code_ptr]
    mov [rdx], edi
    add qword [code_ptr], 4
    ret

; Write the final ELF binary
rex_finish:
    ; Calculate sizes
    lea rbx, [code_buffer]
    mov rdx, [code_ptr]
    sub rdx, rbx            ; rdx = code size

    ; Total file size = 64 (EH) + 56 (PH) + code size
    mov rax, rdx
    add rax, 120
    mov [program_header + 32], rax ; p_filesz
    mov [program_header + 40], rax ; p_memsz

    ; Open output file
    mov rax, SYS_OPEN
    mov rdi, out_filename
    mov rsi, O_CREAT | O_WRONLY | O_TRUNC
    mov rdx, 0755o
    syscall
    mov [out_fd], rax

    ; Write headers
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

    ; Write code
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
