; Rex IR Optimization Passes
; written in x86-64 NASM assembly

%include "include/rex_defs.inc"
%include "include/rex_ir.inc"

section .bss
    extern ir_buffer
    extern ir_count

    vreg_is_const   resb 65536
    vreg_const_val  resq 65536
    
    var_is_const    resb 256
    var_const_val   resq 256

    var_is_read     resb 256
    
    var_cached_vreg resw 256
    vreg_alias      resw 65536

section .text
    global run_optimizations

run_optimizations:
    push rbx
    push r12
    push r13
    push r14
    push r15

    call pass_constant_folding
    call pass_dead_store_elimination
    call pass_load_store_coalescing
    call pass_peephole

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

pass_constant_folding:
    ; Initialize state
    mov rcx, 65536
    lea rdi, [vreg_is_const]
    xor eax, eax
    rep stosb
    
    mov rcx, 256
    lea rdi, [var_is_const]
    xor eax, eax
    rep stosb

    mov r12d, [ir_count]
    test r12d, r12d
    jz .done
    
    xor ebx, ebx ; index = 0
.loop:
    cmp ebx, r12d
    je .done
    
    imul eax, ebx, IR_RECORD_SIZE
    lea r13, [ir_buffer + rax]
    
    movzx eax, byte [r13 + 0] ; opcode
    
    cmp eax, IR_LOAD_IMM
    je .handle_load_imm
    
    cmp eax, IR_STORE_VAR
    je .handle_store_var
    
    cmp eax, IR_LOAD_VAR
    je .handle_load_var
    
    ; Arithmetic checks
    cmp eax, IR_ADD
    je .handle_arith
    cmp eax, IR_SUB
    je .handle_arith
    cmp eax, IR_MUL
    je .handle_arith
    cmp eax, IR_DIV
    je .handle_arith
    cmp eax, IR_MOD
    je .handle_arith
    cmp eax, IR_AND
    je .handle_arith
    cmp eax, IR_OR
    je .handle_arith
    cmp eax, IR_XOR
    je .handle_arith

    jmp .next

.handle_load_imm:
    movzx ecx, word [r13 + 2] ; dst vreg
    mov rdx, [r13 + 8] ; imm
    mov byte [vreg_is_const + rcx], 1
    mov [vreg_const_val + rcx * 8], rdx
    jmp .next

.handle_store_var:
    movzx ecx, word [r13 + 4] ; src1 vreg
    mov r8, [r13 + 8] ; var offset/idx
    sub r8, 0x00440000
    shr r8, 6
    cmp byte [vreg_is_const + rcx], 1
    jne .not_const_store
    mov byte [var_is_const + r8], 1
    mov rdx, [vreg_const_val + rcx * 8]
    mov [var_const_val + r8 * 8], rdx
    jmp .next
.not_const_store:
    mov byte [var_is_const + r8], 0
    jmp .next

.handle_load_var:
    movzx ecx, word [r13 + 2] ; dst vreg
    mov r8, [r13 + 8] ; var offset/idx
    sub r8, 0x00440000
    shr r8, 6
    cmp byte [var_is_const + r8], 1
    jne .next
    ; Replace with LOAD_IMM
    mov byte [r13 + 0], IR_LOAD_IMM
    mov rdx, [var_const_val + r8 * 8]
    mov [r13 + 8], rdx
    mov byte [vreg_is_const + rcx], 1
    mov [vreg_const_val + rcx * 8], rdx
    jmp .next

.handle_arith:
    movzx r14, word [r13 + 4] ; src1
    movzx r15, word [r13 + 6] ; src2
    
    cmp byte [vreg_is_const + r14], 1
    jne .next
    cmp byte [vreg_is_const + r15], 1
    jne .next
    
    ; Both constant! Compute!
    mov r8, [vreg_const_val + r14 * 8]
    mov r9, [vreg_const_val + r15 * 8]
    
    cmp eax, IR_ADD
    jne .chk_sub
    add r8, r9
    jmp .arith_done
.chk_sub:
    cmp eax, IR_SUB
    jne .chk_mul
    sub r8, r9
    jmp .arith_done
.chk_mul:
    cmp eax, IR_MUL
    jne .chk_div
    imul r8, r9
    jmp .arith_done
.chk_div:
    cmp eax, IR_DIV
    jne .chk_mod
    ; r8 / r9
    test r9, r9
    jz .next ; Div by zero, ignore optimization
    mov rax, r8
    cqo
    idiv r9
    mov r8, rax
    jmp .arith_done
.chk_mod:
    cmp eax, IR_MOD
    jne .chk_and
    test r9, r9
    jz .next
    mov rax, r8
    cqo
    idiv r9
    mov r8, rdx
    jmp .arith_done
.chk_and:
    cmp eax, IR_AND
    jne .chk_or
    and r8, r9
    jmp .arith_done
.chk_or:
    cmp eax, IR_OR
    jne .chk_xor
    or r8, r9
    jmp .arith_done
.chk_xor:
    xor r8, r9

.arith_done:
    ; Convert this instruction to LOAD_IMM
    mov byte [r13 + 0], IR_LOAD_IMM
    mov [r13 + 8], r8
    mov word [r13 + 4], 0 ; src1 = 0
    mov word [r13 + 6], 0 ; src2 = 0
    
    movzx ecx, word [r13 + 2] ; dst vreg
    mov byte [vreg_is_const + rcx], 1
    mov [vreg_const_val + rcx * 8], r8

.next:
    inc ebx
    jmp .loop

.done:
    ret


pass_dead_store_elimination:
    ; Scan backwards from ir_count-1 down to 0
    mov rcx, 256
    lea rdi, [var_is_read]
    xor eax, eax
    rep stosb

    mov ebx, [ir_count]
    test ebx, ebx
    jz .done
    
.dse_loop:
    dec ebx
    imul eax, ebx, IR_RECORD_SIZE
    lea r13, [ir_buffer + rax]
    
    movzx eax, byte [r13 + 0] ; opcode
    
    cmp eax, IR_LOAD_VAR
    je .dse_load_var
    
    cmp eax, IR_STORE_VAR
    je .dse_store_var
    
    jmp .next_dse

.dse_load_var:
    mov r8, [r13 + 8] ; imm = offset
    sub r8, 0x00440000
    shr r8, 6
    mov byte [var_is_read + r8], 1
    jmp .next_dse

.dse_store_var:
    mov r8, [r13 + 8] ; imm = offset
    sub r8, 0x00440000
    shr r8, 6
    cmp byte [var_is_read + r8], 0
    je .kill_store
    ; It was read! But this store overwrites earlier stores, so reset read flag for earlier code.
    mov byte [var_is_read + r8], 0
    jmp .next_dse
    
.kill_store:
    ; Dead store! Set opcode to NOP
    mov byte [r13 + 0], IR_NOP
    
.next_dse:
    test ebx, ebx
    jnz .dse_loop

.done:
    ret


pass_load_store_coalescing:
    ; Initialize state
    mov rcx, 256
    lea rdi, [var_cached_vreg]
    xor eax, eax
    rep stosw
    
    mov rcx, 65536
    lea rdi, [vreg_alias]
    xor eax, eax
    rep stosw

    mov r12d, [ir_count]
    test r12d, r12d
    jz .done
    
    xor ebx, ebx
.loop:
    cmp ebx, r12d
    je .done
    
    imul eax, ebx, IR_RECORD_SIZE
    lea r13, [ir_buffer + rax]
    movzx eax, byte [r13 + 0]
    
    cmp eax, IR_STORE_VAR
    je .store
    cmp eax, IR_LOAD_VAR
    je .load
    
    ; For all other ops, apply vreg aliases to src1 and src2
    movzx ecx, word [r13 + 4]
    test cx, cx
    jz .skip_src1
    mov dx, [vreg_alias + rcx * 2]
    test dx, dx
    jz .skip_src1
    mov [r13 + 4], dx
.skip_src1:
    movzx ecx, word [r13 + 6]
    test cx, cx
    jz .next
    mov dx, [vreg_alias + rcx * 2]
    test dx, dx
    jz .next
    mov [r13 + 6], dx
    jmp .next

.store:
    mov r8, [r13 + 8] ; var offset
    sub r8, 0x00440000
    shr r8, 6
    mov cx, [r13 + 4] ; src1 vreg
    ; apply alias to src1 if any
    mov dx, [vreg_alias + rcx * 2]
    test dx, dx
    jz .store_no_alias
    mov cx, dx
    mov [r13 + 4], cx
.store_no_alias:
    mov [var_cached_vreg + r8 * 2], cx
    jmp .next

.load:
    mov r8, [r13 + 8] ; var offset
    sub r8, 0x00440000
    shr r8, 6
    mov cx, [var_cached_vreg + r8 * 2]
    test cx, cx
    jz .load_miss
    ; Coalesce! We have the value already in vreg 'cx'
    mov dx, [r13 + 2] ; dst vreg of this load
    mov [vreg_alias + rdx * 2], cx
    mov byte [r13 + 0], IR_NOP ; eliminate this load entirely
    jmp .next
.load_miss:
    mov dx, [r13 + 2] ; dst vreg
    mov [var_cached_vreg + r8 * 2], dx
    
.next:
    inc ebx
    jmp .loop
.done:
    ret

pass_peephole:
    ; Simplifies algebraic identities (+0, *1, *0)
    mov r12d, [ir_count]
    test r12d, r12d
    jz .done
    
    xor ebx, ebx
.loop:
    cmp ebx, r12d
    je .done
    
    imul eax, ebx, IR_RECORD_SIZE
    lea r13, [ir_buffer + rax]
    movzx eax, byte [r13 + 0] ; opcode
    
    cmp eax, IR_ADD
    je .arith
    cmp eax, IR_SUB
    je .arith
    cmp eax, IR_MUL
    je .arith
    cmp eax, IR_DIV
    je .arith
    jmp .next

.arith:
    movzx rcx, word [r13 + 4] ; src1 vreg
    movzx rdx, word [r13 + 6] ; src2 vreg
    
    ; Check if src2 is constant 0
    cmp byte [vreg_is_const + rdx], 1
    jne .check_src1
    cmp qword [vreg_const_val + rdx * 8], 0
    je .src2_zero
    ; Check if src2 is constant 1
    cmp qword [vreg_const_val + rdx * 8], 1
    je .src2_one
    ; Check if src2 is constant 2 (for strength reduction)
    cmp qword [vreg_const_val + rdx * 8], 2
    je .src2_two
    jmp .check_src1

.src2_two:
    cmp eax, IR_MUL
    je .reduce_mul_src2
    jmp .check_src1

.reduce_mul_src2:
    ; x * 2 -> x + x
    mov byte [r13 + 0], IR_ADD
    mov [r13 + 6], cx ; src2 = src1
    jmp .next

.src2_zero:
    cmp eax, IR_ADD
    je .alias_src1
    cmp eax, IR_SUB
    je .alias_src1
    cmp eax, IR_MUL
    je .zero_out
    jmp .next

.src2_one:
    cmp eax, IR_MUL
    je .alias_src1
    cmp eax, IR_DIV
    je .alias_src1
    jmp .next

.check_src1:
    ; Check if src1 is constant 0
    cmp byte [vreg_is_const + rcx], 1
    jne .next
    cmp qword [vreg_const_val + rcx * 8], 0
    je .src1_zero
    ; Check if src1 is constant 1
    cmp qword [vreg_const_val + rcx * 8], 1
    je .src1_one
    ; Check if src1 is constant 2 (for strength reduction)
    cmp qword [vreg_const_val + rcx * 8], 2
    je .src1_two
    jmp .next

.src1_two:
    cmp eax, IR_MUL
    je .reduce_mul_src1
    jmp .next

.reduce_mul_src1:
    ; 2 * x -> x + x
    mov byte [r13 + 0], IR_ADD
    mov [r13 + 4], dx ; src1 = src2
    jmp .next

.src1_zero:
    cmp eax, IR_ADD
    je .alias_src2
    cmp eax, IR_MUL
    je .zero_out
    cmp eax, IR_DIV
    je .zero_out
    jmp .next

.src1_one:
    cmp eax, IR_MUL
    je .alias_src2
    jmp .next

.alias_src1:
    ; Result is just src1. We can set vreg_alias of dst to src1.
    movzx rax, word [r13 + 2] ; dst
    mov [vreg_alias + rax * 2], cx
    mov byte [r13 + 0], IR_NOP
    jmp .next

.alias_src2:
    ; Result is just src2. We can set vreg_alias of dst to src2.
    movzx rax, word [r13 + 2] ; dst
    mov [vreg_alias + rax * 2], dx
    mov byte [r13 + 0], IR_NOP
    jmp .next

.zero_out:
    ; Result is 0. Convert to LOAD_IMM 0
    mov byte [r13 + 0], IR_LOAD_IMM
    mov qword [r13 + 8], 0
    mov word [r13 + 4], 0
    mov word [r13 + 6], 0
    movzx rax, word [r13 + 2]
    mov byte [vreg_is_const + rax], 1
    mov qword [vreg_const_val + rax * 8], 0
    jmp .next

.next:
    inc ebx
    jmp .loop
.done:
    ret
