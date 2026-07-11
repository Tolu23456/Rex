; Rex Compiler Main Entry Point
; written in x86-64 NASM assembly

%include "include/rex_defs.inc"

section .data
    usage_msg       db "Usage: rexc <source.rex> [-o <output>]", 10, 0
    usage_len       equ $ - usage_msg
    
    err_open_in     db "Error: Cannot open source file", 10, 0
    err_open_in_len equ $ - err_open_in
    
    err_open_out    db "Error: Cannot open output file", 10, 0
    err_open_out_len equ $ - err_open_out

    default_out     db "a.out", 0
    success_msg     db "Compilation successful!", 10, 0
    success_len     equ $ - success_msg

section .bss
    src_file_buf    resb 65536
    src_file_size   resq 1
    out_filename    resq 1

section .text
    global _start
    
    extern lex_init
    extern sym_clear
    extern ir_init
    extern parse_program
    extern run_optimizations
    extern allocate_registers
    extern codegen_init
    extern codegen_emit_all
    extern codegen_finish

    extern out_buffer
    extern out_idx

_start:
    ; Command line arguments on stack:
    ; [rsp] = argc
    ; [rsp + 8] = argv[0]
    ; [rsp + 16] = argv[1]
    
    mov rdi, [rsp] ; argc
    cmp rdi, 2
    jl .print_usage
    
    ; Parse arguments to find source filename and optional -o output
    ; rbx = argv index
    mov rbx, 2 ; start checking from argv[2]
    mov qword [out_filename], default_out ; default output file

.arg_loop:
    mov rdi, [rsp] ; argc
    cmp rbx, rdi
    jge .args_done
    
    ; Compare argv[rbx] with "-o"
    mov rsi, [rsp + 8 + rbx * 8] ; argv[rbx]
    cmp byte [rsi], '-'
    jne .next_arg
    cmp byte [rsi + 1], 'o'
    jne .next_arg
    cmp byte [rsi + 2], 0
    jne .next_arg
    
    ; Found "-o", output file is argv[rbx + 1]
    inc rbx
    cmp rbx, rdi
    jge .print_usage
    mov rdx, [rsp + 8 + rbx * 8]
    mov [out_filename], rdx

.next_arg:
    inc rbx
    jmp .arg_loop

.args_done:
    ; Source file is argv[1]
    mov r12, [rsp + 16] ; source file path
    
    ; Open source file (sys_open, flags = O_RDONLY)
    mov rax, 2          ; sys_open
    mov rdi, r12
    xor rsi, rsi        ; O_RDONLY = 0
    xor rdx, rdx
    syscall
    
    cmp rax, 0
    jl .err_open_source
    mov r13, rax        ; r13 = source fd
    
    ; Find size (sys_lseek SEEK_END)
    mov rax, 8          ; sys_lseek
    mov rdi, r13
    xor rsi, rsi
    mov rdx, 2          ; SEEK_END = 2
    syscall
    mov [src_file_size], rax
    
    ; Seek back to 0 (sys_lseek SEEK_SET)
    mov rax, 8          ; sys_lseek
    mov rdi, r13
    xor rsi, rsi
    xor rdx, rdx        ; SEEK_SET = 0
    syscall
    
    ; Read source file into buffer
    mov rax, 0          ; sys_read
    mov rdi, r13
    mov rsi, src_file_buf
    mov rdx, [src_file_size]
    syscall
    
    ; Close source fd
    mov rax, 3          ; sys_close
    mov rdi, r13
    syscall
    
    ; Compile pipeline
    ; 1. Initialize Lexer
    mov rdi, src_file_buf
    mov rsi, [src_file_size]
    call lex_init
    
    ; 2. Initialize Symbol Table & IR Emitter
    call sym_clear
    call ir_init
    
    ; 3. Parse Program (emits IR)
    call parse_program
    
    ; 3.5 Run Optimization Passes
    ; call run_optimizations
    
    ; 4. Linear Scan Register Allocation
    call allocate_registers
    
    ; 5. Generate ELF64 executable bytes
    call codegen_init
    call codegen_emit_all
    call codegen_finish
    
    ; Write output file
    ; sys_open(filename, O_WRONLY | O_CREAT | O_TRUNC, 0755)
    ; O_WRONLY | O_CREAT | O_TRUNC = 0x241
    ; Mode 0755 = 493 decimal
    mov rax, 2          ; sys_open
    mov rdi, [out_filename]
    mov rsi, 0x241      ; flags
    mov rdx, 493        ; mode
    syscall
    
    cmp rax, 0
    jl .err_open_output
    mov r13, rax        ; r13 = output fd
    
    ; Write out_buffer to output fd
    mov rax, 1          ; sys_write
    mov rdi, r13
    mov rsi, out_buffer
    mov edx, [out_idx]
    syscall
    
    ; Close output fd
    mov rax, 3          ; sys_close
    mov rdi, r13
    syscall
    
    ; Print success message
    mov rax, 1          ; sys_write
    mov rdi, 1          ; stdout
    mov rsi, success_msg
    mov rdx, success_len
    syscall
    
    ; Exit 0
    mov rax, 60         ; sys_exit
    xor rdi, rdi        ; exit code 0
    syscall

.print_usage:
    mov rax, 1          ; sys_write
    mov rdi, 2          ; stderr
    mov rsi, usage_msg
    mov rdx, usage_len
    syscall
    
    mov rax, 60         ; sys_exit
    mov rdi, 1          ; exit code 1
    syscall

.err_open_source:
    mov rax, 1
    mov rdi, 2
    mov rsi, err_open_in
    mov rdx, err_open_in_len
    syscall
    
    mov rax, 60
    mov rdi, 1
    syscall

.err_open_output:
    mov rax, 1
    mov rdi, 2
    mov rsi, err_open_out
    mov rdx, err_open_out_len
    syscall
    
    mov rax, 60
    mov rdi, 1
    syscall
