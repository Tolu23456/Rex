; ============================================================
; main/main.asm — Rex compiler entry point
; Usage: rexc <source.rex> [-o output]
; ============================================================
bits 64
%include "rex_defs.inc"

global _start

extern lexer_init, lex_next
extern parse_program
extern codegen_init, codegen_finish
extern codegen_write_headers, codegen_write_runtime, codegen_write_code
extern cur_tok

; ============================================================
; BSS
; ============================================================
section .bss
src_buffer:     resb SRC_BUF_SIZE    ; 1 MB source input
output_path:    resb 256             ; output filename
src_path:       resb 256             ; source filename
src_file_fd:    resq 1
out_file_fd:    resq 1
src_size:       resq 1

; ============================================================
; DATA
; ============================================================
section .data
usage_msg:  db "Usage: rexc <source.rex> [-o output]", 0x0a, 0
default_out: db "output", 0
opt_o:       db "-o", 0
err_open:    db "rex: cannot open input file", 0x0a, 0
err_write:   db "rex: write error", 0x0a, 0
err_chmod:   db "rex: chmod failed", 0x0a, 0
err_create:  db "rex: cannot create output file", 0x0a, 0
err_argc:    db "rex: no input file specified", 0x0a, 0

; ============================================================
; Entry point
; ============================================================
section .text

_start:
    ; Stack at entry: [rsp]=argc, [rsp+8]=argv[0], [rsp+16]=argv[1], ...
    mov     r12, [rsp]              ; r12 = argc (preserved across calls)
    cmp     r12, 2
    jl      .usage_exit

    ; argv[1] = source file
    mov     rdi, [rsp + 16]
    lea     rsi, [src_path]
    call    strcpy_to

    ; Default output: "output"
    lea     rdi, [default_out]
    lea     rsi, [output_path]
    call    strcpy_to

    ; If argc >= 3 and argv[2] is not "-o", treat argv[2] as output path (positional)
    cmp     r12, 3
    jl      .got_args
    mov     rdi, [rsp + 24]         ; argv[2]
    cmp     byte [rdi], '-'
    jne     .positional_out         ; not a flag → positional output path

    ; argv[2] starts with '-' — check for -o flag
    cmp     byte [rdi + 1], 'o'
    jne     .got_args
    cmp     r12, 4
    jl      .got_args
    mov     rdi, [rsp + 32]         ; argv[3] = output path
    lea     rsi, [output_path]
    call    strcpy_to
    jmp     .got_args

.positional_out:
    lea     rsi, [output_path]
    call    strcpy_to               ; rdi already = argv[2]

.got_args:
    ; Initialize compiler
    call    codegen_init

    ; Open source file
    mov     rax, 2                  ; SYS_open
    lea     rdi, [src_path]
    xor     esi, esi                ; O_RDONLY
    xor     edx, edx
    syscall
    cmp     rax, 0
    jl      .err_open

    mov     [src_file_fd], rax

    ; Read source into buffer
    mov     rax, 0                  ; SYS_read
    mov     rdi, [src_file_fd]
    lea     rsi, [src_buffer]
    mov     rdx, SRC_BUF_SIZE - 1
    syscall
    cmp     rax, 0
    jl      .err_open

    mov     [src_size], rax
    ; NUL-terminate
    lea     rbx, [src_buffer]
    add     rbx, rax
    mov     byte [rbx], 0

    ; Close source file
    mov     rax, 3                  ; SYS_close
    mov     rdi, [src_file_fd]
    syscall

    ; Open output file
    mov     rax, 2                  ; SYS_open
    lea     rdi, [output_path]
    mov     rsi, 0x241              ; O_WRONLY | O_CREAT | O_TRUNC
    mov     rdx, 0777o              ; permissions
    syscall
    cmp     rax, 0
    jl      .err_create

    mov     [out_file_fd], rax

    ; Initialize lexer
    lea     rdi, [src_buffer]
    mov     rsi, [src_size]
    call    lexer_init

    ; Prime lexer (advance to first token)
    call    lex_next

    ; Parse program (drives codegen)
    call    parse_program

    ; Patch ELF header with final sizes
    mov     rdi, [out_file_fd]
    call    codegen_finish

    ; Write ELF header + runtime JMP
    mov     rdi, [out_file_fd]
    call    codegen_write_headers

    ; Write runtime blobs
    mov     rdi, [out_file_fd]
    call    codegen_write_runtime

    ; DEBUG: dump first 20 bytes of out_buffer to stderr
    extern out_buffer
    mov     rax, 1          ; SYS_write
    mov     rdi, 2          ; stderr
    mov     rsi, out_buffer
    mov     rdx, 20
    syscall

    ; Write user code
    mov     rdi, [out_file_fd]
    call    codegen_write_code

    ; Close output file
    mov     rax, 3
    mov     rdi, [out_file_fd]
    syscall

    ; chmod 755 on output file
    mov     rax, 90                 ; SYS_chmod
    lea     rdi, [output_path]
    mov     rsi, 0755o
    syscall

    ; Exit success
    mov     rax, SYS_exit
    xor     edi, edi
    syscall

; ---- Error handlers ----
.usage_exit:
    mov     rax, SYS_write
    mov     rdi, 2
    lea     rsi, [usage_msg]
    mov     rdx, 40
    syscall
    mov     rax, SYS_exit
    mov     rdi, 1
    syscall

.err_open:
    mov     rax, SYS_write
    mov     rdi, 2
    lea     rsi, [err_open]
    mov     rdx, 28
    syscall
    mov     rax, SYS_exit
    mov     rdi, 1
    syscall

.err_create:
    mov     rax, SYS_write
    mov     rdi, 2
    lea     rsi, [err_create]
    mov     rdx, 31
    syscall
    mov     rax, SYS_exit
    mov     rdi, 1
    syscall

; ============================================================
; strcpy_to(rdi=src, rsi=dst): copy string
; ============================================================
strcpy_to:
    push    rcx
    xor     ecx, ecx
.loop:
    movzx   eax, byte [rdi + rcx]
    mov     [rsi + rcx], al
    test    al, al
    jz      .done
    inc     ecx
    jmp     .loop
.done:
    pop     rcx
    ret
