; rex.asm - The Rex Bootstrap Compiler (Stage 0)
; This compiler reads a .rex file and produces a raw ELF64 binary.
; No external assembler or linker required for the output.

section .data
    ; ELF Header Constants
    elf_header:
        db 0x7F, 'ELF'      ; e_ident[EI_MAG0..3]
        db 2                ; EI_CLASS (64-bit)
        db 1                ; EI_DATA (Little endian)
        db 1                ; EI_VERSION
        db 0                ; EI_OSABI (System V)
        db 0                ; EI_ABIVERSION
        times 7 db 0        ; Padding
        dw 2                ; e_type (Executable)
        dw 0x3E             ; e_machine (x86-64)
        dd 1                ; e_version
        dq 0x400000 + 0x78  ; e_entry (Entry point address)
        dq 0x40             ; e_phoff (Program header offset)
        dq 0                ; e_shoff (Section header offset)
        dd 0                ; e_flags
        dw 64               ; e_ehsize (ELF header size)
        dw 56               ; e_phentsize (Program header size)
        dw 1                ; e_phnum (Number of program headers)
        dw 64               ; e_shentsize (Section header size)
        dw 0                ; e_shnum
        dw 0                ; e_shstrndx

    program_header:
        dd 1                ; p_type (PT_LOAD)
        dd 7                ; p_flags (PF_R | PF_W | PF_X)
        dq 0                ; p_offset
        dq 0x400000         ; p_vaddr
        dq 0x400000         ; p_paddr
        dq 0x1000           ; p_filesz (Temporary fixed size)
        dq 0x1000           ; p_memsz
        dq 0x1000           ; p_align

    error_msg db "Error: Could not open source file.", 10
    error_len equ $ - error_msg

    usage_msg db "Usage: rexc <file.rex>", 10
    usage_len equ $ - usage_msg

section .bss
    file_buffer resb 4096   ; Source file buffer
    out_buffer resb 8192    ; Output binary buffer
    file_fd resq 1
    out_fd resq 1
    var_name resb 1
    var_value resb 1

section .text
    global _start

_start:
    ; Check arguments
    pop rax                 ; argc
    cmp rax, 2
    jl .usage

    pop rax                 ; program name
    pop rdi                 ; filename (first argument)

    ; Open source file
    mov rax, 2              ; sys_open
    xor rsi, rsi            ; O_RDONLY
    syscall
    test rax, rax
    js .error_open
    mov [file_fd], rax

    ; Read source file
    mov rdi, rax
    mov rax, 0              ; sys_read
    mov rsi, file_buffer
    mov rdx, 4096
    syscall
    mov r12, rax            ; r12 = source length
    mov r13, 0              ; r13 = source index
    mov r14, 0              ; r14 = output buffer index

.compile_loop:
    cmp r13, r12
    jge .finish_compilation

    ; Skip whitespace
    mov al, [file_buffer + r13]
    cmp al, ' '
    je .next_char
    cmp al, 10              ; newline
    je .next_char
    cmp al, 9               ; tab
    je .next_char

    ; Check for 'let'
    cmp dword [file_buffer + r13], 'let '
    jne .check_output
    add r13, 4              ; skip 'let '
    
    ; Parse variable name (simplified: single char)
    mov bl, [file_buffer + r13]
    mov [var_name], bl
    add r13, 2              ; skip 'x '
    add r13, 2              ; skip '= '

    ; Parse integer (simplified: single digit)
    mov al, [file_buffer + r13]
    sub al, '0'
    mov [var_value], al
    inc r13
    jmp .compile_loop

.check_output:
    ; Check for 'output'
    ; 'outp' 'ut '
    cmp dword [file_buffer + r13], 'outp'
    jne .unknown_token
    cmp dword [file_buffer + r13 + 4], 'ut '
    jne .unknown_token
    add r13, 7              ; skip 'output '

    ; Generate code for outputting variable
    ; mov rax, 1 (write)
    mov byte [out_buffer + r14], 0x48
    mov byte [out_buffer + r14 + 1], 0xC7
    mov byte [out_buffer + r14 + 2], 0xC0
    mov byte [out_buffer + r14 + 3], 0x01
    mov byte [out_buffer + r14 + 4], 0x00
    mov byte [out_buffer + r14 + 5], 0x00
    mov byte [out_buffer + r14 + 6], 0x00
    add r14, 7

    ; mov rdi, 1 (stdout)
    mov byte [out_buffer + r14], 0x48
    mov byte [out_buffer + r14 + 1], 0xC7
    mov byte [out_buffer + r14 + 2], 0xC7
    mov byte [out_buffer + r14 + 3], 0x01
    mov byte [out_buffer + r14 + 4], 0x00
    mov byte [out_buffer + r14 + 5], 0x00
    mov byte [out_buffer + r14 + 6], 0x00
    add r14, 7

    ; Push char and newline to stack
    ; push 0x0A (newline)
    mov byte [out_buffer + r14], 0x6A
    mov byte [out_buffer + r14 + 1], 0x0A
    add r14, 2
    
    ; push [value + 48]
    mov al, [var_value]
    add al, '0'
    mov byte [out_buffer + r14], 0x6A
    mov byte [out_buffer + r14 + 1], al
    add r14, 2

    ; mov rsi, rsp
    mov byte [out_buffer + r14], 0x48
    mov byte [out_buffer + r14 + 1], 0x89
    mov byte [out_buffer + r14 + 2], 0xE6
    add r14, 3

    ; mov rdx, 2 (length)
    mov byte [out_buffer + r14], 0x48
    mov byte [out_buffer + r14 + 1], 0xC7
    mov byte [out_buffer + r14 + 2], 0xC2
    mov byte [out_buffer + r14 + 3], 0x02
    mov byte [out_buffer + r14 + 4], 0x00
    mov byte [out_buffer + r14 + 5], 0x00
    mov byte [out_buffer + r14 + 6], 0x00
    add r14, 7

    ; syscall
    mov byte [out_buffer + r14], 0x0F
    mov byte [out_buffer + r14 + 1], 0x05
    add r14, 2

    ; Clean up stack: add rsp, 16
    mov byte [out_buffer + r14], 0x48
    mov byte [out_buffer + r14 + 1], 0x83
    mov byte [out_buffer + r14 + 2], 0xC4
    mov byte [out_buffer + r14 + 3], 0x10
    add r14, 4
    
    jmp .compile_loop

.next_char:
    inc r13
    jmp .compile_loop

.unknown_token:
    inc r13
    jmp .compile_loop

.finish_compilation:
    ; Add exit syscall to the end of the generated code
    mov byte [out_buffer + r14], 0x48
    mov byte [out_buffer + r14 + 1], 0xC7
    mov byte [out_buffer + r14 + 2], 0xC0
    mov byte [out_buffer + r14 + 3], 0x3C
    mov byte [out_buffer + r14 + 4], 0x00
    mov byte [out_buffer + r14 + 5], 0x00
    mov byte [out_buffer + r14 + 6], 0x00
    mov byte [out_buffer + r14 + 7], 0x48
    mov byte [out_buffer + r14 + 8], 0x31
    mov byte [out_buffer + r14 + 9], 0xFF
    mov byte [out_buffer + r14 + 10], 0x0F
    mov byte [out_buffer + r14 + 11], 0x05
    add r14, 12

    ; Create output file "output"
    mov rax, 2              ; sys_open
    mov rdi, out_name
    mov rsi, 0x41           ; O_CREAT | O_WRONLY | O_TRUNC (0x41 is O_CREAT | O_WRONLY)
    ; Fix: O_TRUNC is needed if file exists. 0x41 | 0x200 = 0x241
    mov rsi, 0x241
    mov rdx, 0755o          ; Permissions
    syscall
    mov [out_fd], rax

    ; Write ELF Header
    mov rdi, rax
    mov rax, 1              ; sys_write
    mov rsi, elf_header
    mov rdx, 64
    syscall

    ; Write Program Header
    mov rdi, [out_fd]
    mov rax, 1
    mov rsi, program_header
    mov rdx, 56
    syscall

    ; Write Generated Code
    mov rdi, [out_fd]
    mov rax, 1
    mov rsi, out_buffer
    mov rdx, r14
    syscall

    ; Close files
    mov rax, 3              ; sys_close
    mov rdi, [file_fd]
    syscall
    mov rax, 3
    mov rdi, [out_fd]
    syscall

    ; Exit
    mov rax, 60
    xor rdi, rdi
    syscall

.usage:
    mov rax, 1
    mov rdi, 1
    mov rsi, usage_msg
    mov rdx, usage_len
    syscall
    mov rax, 60
    mov rdi, 1
    syscall

.error_open:
    mov rax, 1
    mov rdi, 1
    mov rsi, error_msg
    mov rdx, error_len
    syscall
    mov rax, 60
    mov rdi, 1
    syscall

section .data
    out_name db "output", 0
