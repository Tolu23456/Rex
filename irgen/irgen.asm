; Rex IR Emitter Implementation
; written in x86-64 NASM assembly

%include "include/rex_defs.inc"
%include "include/rex_ir.inc"

section .bss
    global ir_buffer
    global ir_count
    global vreg_counter

    ir_buffer       resb IR_RECORD_SIZE * IR_MAX_RECORDS
    ir_count        resd 1
    vreg_counter    resd 1

section .text
    global ir_init
    global emit_ir
    global alloc_vreg
    global print_ir ; For debugging

ir_init:
    mov dword [ir_count], 0
    mov dword [vreg_counter], 1 ; vregs start at 1 (0 = unused)
    ret

alloc_vreg:
    mov eax, [vreg_counter]
    cmp eax, 65535
    jae err_vreg_overflow
    inc dword [vreg_counter]
    ret

err_vreg_overflow:
    mov rax, 1
    mov rdi, 2
    mov rsi, err_vreg_msg
    mov rdx, err_vreg_len
    syscall
    
    mov rax, 60
    mov rdi, 1
    syscall

; Emit IR instruction
; rdi = opcode, rsi = type, rdx = dst, rcx = src1, r8 = src2, r9 = imm, r10 = aux
emit_ir:
    push rbx
    mov eax, [ir_count]
    cmp eax, IR_MAX_RECORDS
    jae .overflow

    ; Validate vreg IDs are within range
    cmp edx, VREG_MAX
    jae .overflow
    cmp ecx, VREG_MAX
    jae .overflow
    cmp r8d, VREG_MAX
    jae .overflow

    imul eax, eax, IR_RECORD_SIZE
    lea rbx, [ir_buffer + rax]
    
    mov [rbx + 0], dil  ; opcode
    mov [rbx + 1], sil  ; type
    mov [rbx + 2], dx   ; dst
    mov [rbx + 4], cx   ; src1
    mov [rbx + 6], r8w  ; src2
    mov [rbx + 8], r9   ; imm
    mov [rbx + 16], r10 ; aux
    mov dword [rbx + 24], 0 ; flags
    mov dword [rbx + 28], 0 ; _pad
    
    inc dword [ir_count]
    pop rbx
    ret

.overflow:
    ; Exit with error (write error to stderr and exit)
    mov rax, 1          ; sys_write
    mov rdi, 2          ; stderr
    mov rsi, .err_msg
    mov rdx, .err_len
    syscall
    
    mov rax, 60         ; sys_exit
    mov rdi, 1          ; exit code 1
    syscall

section .rodata
    .err_msg db "Error: IR buffer overflow", 10
    .err_len equ $ - .err_msg
    err_vreg_msg db "Error: Virtual register overflow", 10
    err_vreg_len equ $ - err_vreg_msg
