; main.asm - Compiler orchestration engine
;
; Responsibilities:
;   • OS argument parsing (argv[1] = source filename)
;   • File I/O: open / read source, open / write / close output binary
;   • Driving the full compilation pipeline:
;       codegen_write_headers → codegen_init → lexer_init → parse loop → codegen_finish
;   • Writing out_buffer to disk as the executable "output"

global _start

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

%include "rex_defs.inc"

; Token constants (mirrors rex_defs.inc — needed here for the parse loop)
TOK_EOF_L    equ 0
TOK_NEWLINE_L equ 1
TOK_INDENT_L  equ 2
TOK_DEDENT_L  equ 3

; ─── BSS ────────────────────────────────────────────────────────────────────
section .bss
    src_buffer: resb 4096
    src_fd:     resq 1
    out_fd:     resq 1
    bytes_read: resq 1

; ─── DATA ───────────────────────────────────────────────────────────────────
section .data
    usage_msg:      db "Usage: rexc <file.rex>", 10
    usage_msg_len   equ $ - usage_msg
    err_open_msg:   db "error: cannot open source file", 10
    err_open_len    equ $ - err_open_msg
    err_write_msg:  db "error: cannot write output file", 10
    err_write_len   equ $ - err_write_msg

; ─── TEXT ───────────────────────────────────────────────────────────────────
section .text

; ── fatal ────────────────────────────────────────────────────────────────────
; Write message to stderr and exit with code 1.
; rsi = msg ptr, rdx = length
fatal:
    mov  rax, 1
    mov  rdi, 2             ; stderr
    syscall
    mov  rax, 60
    mov  rdi, 1
    syscall

; ── _start ───────────────────────────────────────────────────────────────────
_start:
    ; ── 1. Parse command-line arguments ──────────────────────────────────────
    pop  rax                ; argc
    cmp  rax, 2
    jl   .usage

    pop  rax                ; argv[0] (program name) — discard
    pop  rdi                ; argv[1] = source filename

    ; ── 2. Open source file (O_RDONLY = 0) ───────────────────────────────────
    mov  rax, 2             ; sys_open
    xor  rsi, rsi           ; O_RDONLY
    xor  rdx, rdx
    syscall
    test rax, rax
    js   .err_open
    mov  [rel src_fd], rax

    ; ── 3. Read source file ───────────────────────────────────────────────────
    mov  rdi, rax           ; fd
    mov  rax, 0             ; sys_read
    lea  rsi, [rel src_buffer]
    mov  rdx, 4096
    syscall
    test rax, rax
    js   .err_open
    mov  [rel bytes_read], rax

    ; Close source file
    mov  rax, 3             ; sys_close
    mov  rdi, [rel src_fd]
    syscall

    ; ── 4. Initialise codegen: write ELF header + PH + padding ───────────────
    call codegen_write_headers

    ; ── 5. Write runtime scaffolding: JMP + rt_pri + rt_prs ──────────────────
    call codegen_init

    ; ── 6. Initialise lexer ───────────────────────────────────────────────────
    lea  rdi, [rel src_buffer]
    mov  rsi, [rel bytes_read]
    call lexer_init

    ; ── 7. Main compilation loop ──────────────────────────────────────────────
    call lexer_next         ; prime the token stream

.compile_loop:
    movzx eax, byte [rel tok_type]

    cmp  al, TOK_EOF_L
    je   .compile_done

    ; Skip structural / blank tokens
    cmp  al, TOK_NEWLINE_L
    je   .skip_tok
    cmp  al, TOK_INDENT_L
    je   .skip_tok
    cmp  al, TOK_DEDENT_L
    je   .skip_tok

    ; Parse one full statement
    call parse_stmt
    jmp  .compile_loop

.skip_tok:
    call lexer_next
    jmp  .compile_loop

.compile_done:
    ; ── 8. Emit exit syscall ─────────────────────────────────────────────────
    call codegen_finish

    ; ── 9. Write output binary ───────────────────────────────────────────────
    ; Open "output" for writing (O_WRONLY|O_CREAT|O_TRUNC = 0x241, mode 0755 = 493)
    mov  rax, 2
    lea  rdi, [rel out_name]
    mov  rsi, 0x241
    mov  rdx, 493           ; 0755 octal = 493 decimal
    syscall
    test rax, rax
    js   .err_write
    mov  [rel out_fd], rax

    mov  rdi, rax           ; fd
    mov  rax, 1             ; sys_write
    lea  rsi, [rel out_buffer]
    mov  rdx, [rel out_idx]
    syscall

    ; Close output file
    mov  rax, 3
    mov  rdi, [rel out_fd]
    syscall

    ; ── 10. Exit cleanly ─────────────────────────────────────────────────────
    mov  rax, 60
    xor  rdi, rdi
    syscall

    ; ── Error / usage paths ───────────────────────────────────────────────────
.usage:
    lea  rsi, [rel usage_msg]
    mov  rdx, usage_msg_len
    call fatal

.err_open:
    lea  rsi, [rel err_open_msg]
    mov  rdx, err_open_len
    call fatal

.err_write:
    lea  rsi, [rel err_write_msg]
    mov  rdx, err_write_len
    call fatal
