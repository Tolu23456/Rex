default rel
%include "include/rex_defs.inc"
global _start
extern lexer_init, lexer_next, parse_stmt, codegen_write_headers, codegen_init, codegen_finish
extern out_buffer, out_idx, out_name, tok_type
section .bss
src_buffer: resb 65536
src_len: resq 1
src_fd:  resq 1
out_fd:  resq 1
section .text
_start:
    mov rax, [rsp]; cmp rax, 2; jl .err
    mov rdi, [rsp+16]; mov rax, 2; xor rsi, rsi; xor rdx, rdx; syscall
    test rax, rax; js .err
    mov [src_fd], rax; mov rdi, rax; mov rax, 0; lea rsi, [src_buffer]; mov rdx, 65536; syscall
    mov [src_len], rax; mov rax, 3; mov rdi, [src_fd]; syscall
    call codegen_write_headers; call codegen_init
    lea rdi, [src_buffer]; mov rsi, [src_len]; call lexer_init; call lexer_next
.l: movzx eax, byte [tok_type]; cmp al, TOK_EOF; je .d
    cmp al, TOK_NEWLINE; je .s; call parse_stmt; jmp .l
.s: call lexer_next; jmp .l
.d: call codegen_finish
    mov rax, 87; lea rdi, [out_name]; syscall
    mov rax, 2; lea rdi, [out_name]; mov rsi, 0x41; mov rdx, 493; syscall
    test rax, rax; js .err; mov [out_fd], rax
    mov rdi, rax; mov rax, 1; lea rsi, [out_buffer]; mov rdx, [out_idx]; syscall
    mov rax, 3; mov rdi, [out_fd]; syscall
    mov rax, 60; xor rdi, rdi; syscall
.err: mov rax, 60; mov rdi, 1; syscall
