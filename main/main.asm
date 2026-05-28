; -----------------------------------------------------------------------------
; Rex V5.0 Compiler Entry Point
; Orchestrates the lexing, parsing, and code generation phases.
; -----------------------------------------------------------------------------

default rel

%include "include/rex_defs.inc"

global _start

; Externs from other modules
extern lexer_init
extern lexer_next
extern parse_stmt
extern codegen_write_headers
extern codegen_init
extern codegen_finish
extern out_buffer
extern out_idx
extern out_name
extern tok_type
extern tok_ident

section .bss
    src_buffer: resb 65536      ; Source file buffer
    src_len:    resq 1          ; Length of source
    src_fd:     resq 1          ; Source file descriptor
    out_fd:     resq 1          ; Output file descriptor

section .data
    msg_parse: db "Parsing token: ", 0
    msg_newline: db 10, 0

section .text

_start:
    ; 1. Check command line arguments
    mov rax, [rsp]              ; argc
    cmp rax, 2
    jl .error

    ; 2. Open source file
    mov rdi, [rsp+16]           ; argv[1]
    mov rax, 2                  ; sys_open
    xor rsi, rsi                ; O_RDONLY
    xor rdx, rdx
    syscall
    test rax, rax
    js .error
    mov [src_fd], rax

    ; 3. Read source file
    mov rdi, rax
    mov rax, 0                  ; sys_read
    lea rsi, [src_buffer]
    mov rdx, 65536
    syscall
    mov [src_len], rax

    ; 4. Close source file
    mov rax, 3                  ; sys_close
    mov rdi, [src_fd]
    syscall

    ; 5. Initialize Code Generation
    call codegen_write_headers
    call codegen_init

    ; 6. Initialize Lexer
    lea rdi, [src_buffer]
    mov rsi, [src_len]
    call lexer_init
    call lexer_next             ; Get first token

.parse_loop:
    movzx eax, byte [tok_type]
    cmp al, TOK_EOF
    je .compile_done

    cmp al, TOK_NEWLINE
    je .skip_newline

    ; Debug: Print token type and ident
    push rax
    mov rdi, 1
    lea rsi, [tok_ident]
    mov rdx, 8
    mov rax, 1
    syscall
    pop rax

    call parse_stmt
    jmp .parse_loop

.skip_newline:
    call lexer_next
    jmp .parse_loop

.compile_done:
    ; 7. Finalize Code Generation
    call codegen_finish

    ; 8. Unlink existing output
    mov rax, 87                 ; sys_unlink
    lea rdi, [out_name]
    syscall

    ; 9. Open output file for writing
    mov rax, 2                  ; sys_open
    lea rdi, [out_name]
    mov rsi, 0x41               ; O_CREAT | O_WRONLY
    mov rdx, 493                ; mode 0755
    syscall
    test rax, rax
    js .error
    mov [out_fd], rax

    ; 10. Write output buffer
    mov rdi, rax
    mov rax, 1                  ; sys_write
    lea rsi, [out_buffer]
    mov rdx, [out_idx]
    syscall

    ; 11. Close output file
    mov rax, 3                  ; sys_close
    mov rdi, [out_fd]
    syscall

    ; 12. Exit success
    mov rax, 60                 ; sys_exit
    xor rdi, rdi
    syscall

.error:
    mov rax, 60
    mov rdi, 1
    syscall
