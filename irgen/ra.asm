; Rex Linear Scan Register Allocator
; written in x86-64 NASM assembly

%include "include/rex_defs.inc"
%include "include/rex_ir.inc"

section .data
    ; Available physical registers: r10, r11, r12, r13, r14, r15 (6 total)
    ; We assign IDs 0 to 5:
    ; 0 -> r10
    ; 1 -> r11
    ; 2 -> r12
    ; 3 -> r13
    ; 4 -> r14
    ; 5 -> r15
    phys_reg_owner      times 6 dd 0 ; Maps phys reg ID -> vreg ID (0 if free)
    num_phys_regs       equ 6

section .bss
    global vreg_phys
    global vreg_offset
    global stack_frame_size

    vreg_phys           resb 65536 ; Maps vreg -> phys reg ID (255 if spilled/unallocated)
    vreg_offset         resd 65536 ; Maps vreg -> stack offset (negative from RBP)
    last_use            resd 65536 ; Maps vreg -> last IR instruction index
    stack_frame_size    resd 1

section .text
    global allocate_registers

allocate_registers:
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; Initialize tables
    ; vreg_phys initialized to 255 (unallocated)
    mov rcx, 65536
    lea rdi, [vreg_phys]
    mov al, 255
    rep stosb

    ; vreg_offset, last_use initialized to 0
    mov rcx, 65536
    lea rdi, [vreg_offset]
    xor eax, eax
    rep stosd
    
    mov rcx, 65536
    lea rdi, [last_use]
    xor eax, eax
    rep stosd

    ; phys_reg_owner initialized to 0
    mov rcx, num_phys_regs
    lea rdi, [phys_reg_owner]
    xor eax, eax
    rep stosd

    mov dword [stack_frame_size], 0

    ; 1. Liveness Analysis Pass (Compute last_use for each vreg)
    extern ir_count
    extern ir_buffer
    
    mov r12d, [ir_count]
    test r12d, r12d
    jz .done_alloc
    
    xor ebx, ebx ; i = 0
.liveness_loop:
    cmp ebx, r12d
    je .liveness_done
    
    imul eax, ebx, IR_RECORD_SIZE
    lea r13, [ir_buffer + rax]
    
    ; Check src1
    movzx eax, word [r13 + 4] ; src1 vreg
    test ax, ax
    jz .check_src2
    mov [last_use + rax * 4], ebx
    
.check_src2:
    movzx eax, word [r13 + 6] ; src2 vreg
    test ax, ax
    jz .next_liveness
    mov [last_use + rax * 4], ebx

.next_liveness:
    inc ebx
    jmp .liveness_loop

.liveness_done:
    ; 2. Allocation Pass
    xor ebx, ebx ; i = 0
.alloc_loop:
    cmp ebx, r12d
    je .done_alloc
    
    imul eax, ebx, IR_RECORD_SIZE
    lea r13, [ir_buffer + rax]
    
    ; For each instruction, we allocate dst if it has one
    movzx eax, word [r13 + 2] ; dst vreg
    test ax, ax
    jz .after_dst_alloc
    
    mov r14d, eax ; r14d = dst vreg
    
    ; Check if already allocated (should not be, dst is defined here)
    movzx ecx, byte [vreg_phys + r14]
    cmp cl, 255
    jne .after_dst_alloc
    
    ; Find a free physical register
    xor r15d, r15d ; phys reg index
.find_free:
    cmp r15d, num_phys_regs
    je .no_free_reg
    
    mov ecx, [phys_reg_owner + r15 * 4]
    test ecx, ecx
    jz .found_free
    
    inc r15d
    jmp .find_free

.found_free:
    ; Assign r15d to r14d (dst)
    mov [vreg_phys + r14], r15b
    mov [phys_reg_owner + r15 * 4], r14d
    jmp .after_dst_alloc

.no_free_reg:
    ; Register pressure: Spill the register with the furthest last use
    ; We search active physical registers and find the one whose owner's last_use is max
    xor r15d, r15d ; best phys reg to spill
    mov edx, -1    ; max last use value
    
    xor ecx, ecx ; index
.spill_search:
    cmp ecx, num_phys_regs
    je .spill_found
    
    mov esi, [phys_reg_owner + ecx * 4] ; active vreg
    mov eax, [last_use + rsi * 4]
    cmp eax, edx
    jle .next_spill_search
    mov edx, eax
    mov r15d, ecx ; best candidate
.next_spill_search:
    inc ecx
    jmp .spill_search

.spill_found:
    ; Spill the owner of r15d
    mov esi, [phys_reg_owner + r15 * 4] ; vreg to spill
    
    ; Allocate spill slot
    mov eax, [stack_frame_size]
    add eax, 8
    mov [stack_frame_size], eax
    neg eax
    mov [vreg_offset + rsi * 4], eax ; Store negative offset from RBP
    
    ; Mark spilled in vreg_phys
    mov byte [vreg_phys + rsi], 255
    
    ; Assign r15d to our new dst vreg (r14d)
    mov [vreg_phys + r14], r15b
    mov [phys_reg_owner + r15 * 4], r14d

.after_dst_alloc:
    ; Now, check if the lifetime of src1 or src2 ends at this instruction
    ; If so, free their physical registers
    movzx eax, word [r13 + 4] ; src1 vreg
    test ax, ax
    jz .check_src2_free
    
    mov ecx, [last_use + rax * 4]
    cmp ecx, ebx
    jne .check_src2_free
    
    ; Free register of src1
    movzx ecx, byte [vreg_phys + rax]
    cmp cl, 255
    je .check_src2_free ; spilled, nothing to free
    mov dword [phys_reg_owner + rcx * 4], 0
    
.check_src2_free:
    movzx eax, word [r13 + 6] ; src2 vreg
    test ax, ax
    jz .next_alloc
    
    mov ecx, [last_use + rax * 4]
    cmp ecx, ebx
    jne .next_alloc
    
    ; Free register of src2
    movzx ecx, byte [vreg_phys + rax]
    cmp cl, 255
    je .next_alloc
    mov dword [phys_reg_owner + rcx * 4], 0

.next_alloc:
    inc ebx
    jmp .alloc_loop

.done_alloc:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
