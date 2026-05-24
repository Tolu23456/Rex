; semant.asm - Semantic Analysis and Boundary Checks for Rex

%include "common.inc"

section .data
    err_escape db "Compile-time Error: Variable escapes custom memory manager block.", 10, 0
    err_escape_len equ $ - err_escape

section .bss
    ; Scope tracking (simplified stack)
    scope_depth resq 1
    scope_mm    resq 64 ; Store MM for each scope depth

section .text
    global rex_semant_init
    global rex_enter_scope
    global rex_exit_scope
    global rex_check_escape

rex_semant_init:
    mov qword [scope_depth], 0
    mov qword [scope_mm], 0 ; Default AMM
    ret

rex_enter_scope:
    mov rax, [scope_depth]
    inc qword [scope_depth]
    ; Default to parent MM unless changed by 'use'
    mov rdx, [scope_mm + rax*8]
    mov [scope_mm + (rax+1)*8], rdx
    ret

rex_exit_scope:
    dec qword [scope_depth]
    ret

; If a variable from scope N is assigned to scope < N, it's an escape
rex_check_escape:
    ; RDI = var_scope, RSI = target_scope
    cmp rdi, rsi
    jle .ok

    ; If MM is different, it's an error
    mov rax, [scope_mm + rdi*8]
    mov rdx, [scope_mm + rsi*8]
    cmp rax, rdx
    je .ok

    ; Print error and exit compilation
    mov rax, SYS_WRITE
    mov rdi, STDERR
    mov rsi, err_escape
    mov rdx, err_escape_len
    syscall
    mov rax, SYS_EXIT
    mov rdi, 1
    syscall

.ok:
    ret
