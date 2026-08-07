; Temporary debug: dump IR records to stderr (hex) if REX_IRDUMP=1
; Linked into rexc; called from main.asm between pipeline stages.

%include "include/rex_defs.inc"
%include "include/rex_ir.inc"

section .bss
    global dbg_ch_buf
    dbg_ch_buf resb 1

section .rodata
    env_name db "REX_IRDUMP", 0
    dbg_prefix db "IR ", 0
    hexdig db "0123456789abcdef", 0

section .text
    global ir_dump_debug
    global wr_stderr
    global wr_ch
    global wr_hex8
    global wr_hex16
    global wr_hex32

    extern ir_buffer
    extern ir_count

ir_dump_debug:
    mov rbx, [rsp + 8]     ; argc (retaddr at [rsp])
    lea rbx, [rsp + 24 + rbx * 8] ; envp[0]
.scan_env:
    mov rdi, [rbx]
    test rdi, rdi
    jz .done
    lea rsi, [env_name]
    call str_eq
    test rax, rax
    jnz .found
    add rbx, 8
    jmp .scan_env
.found:
    ; rdi points to "REX_IRDUMP=..." — scan for '='
    mov rax, rdi
.loop_eq:
    cmp byte [rax], '='
    je .have_eq
    inc rax
    jmp .loop_eq
.have_eq:
    inc rax
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12d, [ir_count]
    xor r13d, r13d
.loop:
    cmp r13d, r12d
    jae .out
    movsxd r14, r13d
    imul r14, r14, IR_RECORD_SIZE
    lea r14, [ir_buffer + r14]
    lea rdi, [dbg_prefix]
    call wr_stderr
    movzx rdi, byte [r14 + 0]
    call wr_hex8
    mov rdi, ' '
    call wr_ch
    movzx rdi, byte [r14 + 1]
    call wr_hex8
    mov rdi, ' '
    call wr_ch
    movzx rdi, word [r14 + 2]
    call wr_hex16
    mov rdi, ' '
    call wr_ch
    movzx rdi, word [r14 + 4]
    call wr_hex16
    mov rdi, ' '
    call wr_ch
    movzx rdi, word [r14 + 6]
    call wr_hex16
    mov rdi, ' '
    call wr_ch
    mov rdi, [r14 + 8]
    call wr_hex64
    mov rdi, ' '
    call wr_ch
    mov rdi, [r14 + 16]
    call wr_hex64
    mov rdi, 10
    call wr_ch
    inc r13d
    jmp .loop
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
.done:
    ret

str_eq:
    ; compare env entry at rdi (NAME=value) with env_name; rax=1 if equal
    lea rsi, [env_name]
.se:
    mov al, [rdi]
    mov dl, [rsi]
    test al, al
    jz .end_chk
    cmp al, '='
    je .end_chk
    cmp al, dl
    jne .ne
    inc rdi
    inc rsi
    jmp .se
.end_chk:
    cmp dl, 0
    jne .ne
    mov rax, 1
    ret
.ne:
    xor eax, eax
    ret

wr_stderr:
    ; rdi = string ptr (0-terminated)
    push rbx
    xor rbx, rbx
.sl:
    cmp byte [rdi + rbx], 0
    je .sgo
    inc rbx
    jmp .sl
.sgo:
    mov rax, 1
    mov rsi, rdi
    mov rdx, rbx
    push rdi
    mov rdi, 2
    syscall
    pop rdi
    pop rbx
    ret

wr_ch:
    ; rdi = char to write
    mov byte [dbg_ch_buf], dil
    mov rax, 1
    mov rsi, dbg_ch_buf
    mov rdx, 1
    push rdi
    mov rdi, 2
    syscall
    pop rdi
    ret

wr_hex8:
    ; rdi = value
    push rdi
    shr rdi, 4
    call .nib
    pop rdi
    jmp .nib
.nib:
    and rdi, 0xF
    lea rsi, [hexdig]
    movzx rdi, byte [rsi + rdi]
    jmp wr_ch

wr_hex16:
    push rdi
    shr rdi, 8
    call wr_hex8
    pop rdi
    jmp wr_hex8

wr_hex32:
    push rdi
    shr rdi, 16
    call wr_hex16
    pop rdi
    jmp wr_hex16

wr_hex64:
    push rdi
    shr rdi, 32
    call wr_hex32
    pop rdi
    jmp wr_hex32
