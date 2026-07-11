; Rex IR Optimization Passes
; written in x86-64 NASM assembly
;
; Bug fixes applied:
;   Bug 2: pass_apply_aliases now runs after pass_peephole, propagating
;          all aliases (including peephole identity aliases) through the IR.
;   Bug 7: pass_constant_folding now tracks IR_LOAD_FIMM (float immediates)
;          and folds float arithmetic using SSE2 when both operands are constant.
; Cache improvement:
;   pass_apply_aliases follows full alias chains, not just one level.

%include "include/rex_defs.inc"
%include "include/rex_ir.inc"

section .bss
    extern ir_buffer
    extern ir_count
    extern sym_find_by_offset

    vreg_is_const   resb VREG_MAX
    vreg_const_val  resq VREG_MAX
    
    var_is_const    resb VAR_MAX
    var_const_val   resq VAR_MAX

    var_is_read     resb VAR_MAX
    
    var_cached_vreg resw VAR_MAX
    global vreg_alias
    vreg_alias      resw VREG_MAX

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
    call pass_apply_aliases   ; <-- Bug 2 fix: apply all accumulated aliases

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

pass_constant_folding:
    ; Initialize state
    mov rcx, VREG_MAX
    lea rdi, [vreg_is_const]
    xor eax, eax
    rep stosb
    
    mov rcx, VREG_MAX
    lea rdi, [vreg_const_val]
    xor eax, eax
    rep stosq

    mov rcx, VAR_MAX
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

    ; Bug 7 fix: track float immediate loads just like integer ones.
    cmp eax, IR_LOAD_FIMM
    je .handle_load_fimm
    
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

; Bug 7 fix: IR_LOAD_FIMM — treat bit pattern as constant value.
; This enables float constant folding in the arithmetic handler.
.handle_load_fimm:
    movzx ecx, word [r13 + 2] ; dst vreg
    mov rdx, [r13 + 8]        ; float bit pattern (IEEE-754 doubles)
    mov byte [vreg_is_const + rcx], 1
    mov [vreg_const_val + rcx * 8], rdx
    jmp .next

.handle_store_var:
    movzx ecx, word [r13 + 4] ; src1 vreg
    mov rdi, [r13 + 8] ; var offset
    call sym_find_by_offset
    mov r8, rax
    cmp rax, -1
    je .next
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
    mov rdi, [r13 + 8] ; var offset
    call sym_find_by_offset
    mov r8, rax
    cmp rax, -1
    je .next
    cmp byte [var_is_const + r8], 1
    jne .next
    ; Replace with LOAD_IMM (or LOAD_FIMM if float)
    movzx eax, byte [r13 + 1]  ; type
    cmp al, TYPE_FLOAT
    je .load_fimm_const
    mov byte [r13 + 0], IR_LOAD_IMM
    jmp .load_const_common
.load_fimm_const:
    mov byte [r13 + 0], IR_LOAD_FIMM
.load_const_common:
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
    
    ; Both constant!
    ; Check if this is float arithmetic
    movzx ecx, byte [r13 + 1] ; type byte
    cmp cl, TYPE_FLOAT
    je .arith_float

    ; --- Integer folding ---
    mov r8, [vreg_const_val + r14 * 8]
    mov r9, [vreg_const_val + r15 * 8]
    
    movzx eax, byte [r13 + 0] ; opcode
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
    test r9, r9
    jz .next
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
    mov byte [r13 + 0], IR_LOAD_IMM
    mov [r13 + 8], r8
    mov word [r13 + 4], 0
    mov word [r13 + 6], 0
    movzx ecx, word [r13 + 2]
    mov byte [vreg_is_const + rcx], 1
    mov [vreg_const_val + rcx * 8], r8
    jmp .next

; Bug 7 fix: float constant folding using SSE2 instructions.
; The optimizer itself is NASM code so we CAN use SSE here.
.arith_float:
    movq xmm0, [vreg_const_val + r14 * 8]  ; src1 as double
    movq xmm1, [vreg_const_val + r15 * 8]  ; src2 as double
    movzx eax, byte [r13 + 0]               ; opcode
    cmp eax, IR_ADD
    jne .f_sub
    addsd xmm0, xmm1
    jmp .f_done
.f_sub:
    cmp eax, IR_SUB
    jne .f_mul
    subsd xmm0, xmm1
    jmp .f_done
.f_mul:
    cmp eax, IR_MUL
    jne .f_div
    mulsd xmm0, xmm1
    jmp .f_done
.f_div:
    ; Guard against zero divisor
    xorpd xmm2, xmm2
    ucomisd xmm1, xmm2
    je .next   ; div by 0.0 — leave unfolded
    divsd xmm0, xmm1
.f_done:
    ; Store result as LOAD_FIMM
    movq r8, xmm0
    mov byte [r13 + 0], IR_LOAD_FIMM
    mov [r13 + 8], r8
    mov word [r13 + 4], 0
    mov word [r13 + 6], 0
    movzx ecx, word [r13 + 2]
    mov byte [vreg_is_const + rcx], 1
    mov [vreg_const_val + rcx * 8], r8
    jmp .next

.next:
    inc ebx
    jmp .loop

.done:
    ret


pass_dead_store_elimination:
    mov rcx, VAR_MAX
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
    
    movzx eax, byte [r13 + 0]
    
    cmp eax, IR_LOAD_VAR
    je .dse_load_var
    
    cmp eax, IR_STORE_VAR
    je .dse_store_var
    
    jmp .next_dse

.dse_load_var:
    mov rdi, [r13 + 8]
    call sym_find_by_offset
    cmp rax, -1
    je .next_dse
    mov r8, rax
    mov byte [var_is_read + r8], 1
    jmp .next_dse

.dse_store_var:
    mov rdi, [r13 + 8]
    call sym_find_by_offset
    cmp rax, -1
    je .next_dse
    mov r8, rax
    cmp byte [var_is_read + r8], 0
    je .kill_store
    mov byte [var_is_read + r8], 0
    jmp .next_dse
    
.kill_store:
    mov byte [r13 + 0], IR_NOP
    
.next_dse:
    test ebx, ebx
    jnz .dse_loop

.done:
    ret


pass_load_store_coalescing:
    ; Initialize
    mov rcx, VAR_MAX
    lea rdi, [var_cached_vreg]
    xor eax, eax
    rep stosw
    
    ; vreg_alias IS cleared here at the start of this pass.
    ; Constant folding (pass_constant_folding) does NOT write to vreg_alias,
    ; so there are no entries to preserve.  This pass and pass_peephole
    ; build all alias entries; pass_apply_aliases (run last) consumes them.
    ; Clearing here prevents stale entries from a previous compiler invocation
    ; from corrupting subsequent compilations.
    mov rcx, VREG_MAX
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
    call opt_follow_alias    ; rcx=vreg, returns rax=canonical (0=no change)
    test rax, rax
    jz .skip_src1
    mov [r13 + 4], ax
.skip_src1:
    movzx ecx, word [r13 + 6]
    test cx, cx
    jz .next
    call opt_follow_alias
    test rax, rax
    jz .next
    mov [r13 + 6], ax
    jmp .next

.store:
    mov rdi, [r13 + 8]
    call sym_find_by_offset
    cmp rax, -1
    je .next
    mov r8, rax
    movzx ecx, word [r13 + 4]  ; src1 vreg
    ; Follow alias chain for src1
    call opt_follow_alias
    test rax, rax
    jz .store_no_alias
    mov cx, ax
    mov [r13 + 4], cx
.store_no_alias:
    ; Cache: var -> src1 vreg (canonical)
    mov [var_cached_vreg + r8 * 2], cx
    jmp .next

.load:
    mov rdi, [r13 + 8]
    call sym_find_by_offset
    cmp rax, -1
    je .next                    ; symbol not found — skip (guard against bad offset)
    mov r8, rax                 ; r8 = valid symbol index
    movzx ecx, word [var_cached_vreg + r8 * 2]
    test cx, cx
    jz .load_miss               ; cache miss — record dst as cache entry
    ; Cache hit — alias dst to the cached vreg and NOP this load
    movzx eax, word [r13 + 2]  ; dst vreg of this load
    mov [vreg_alias + rax * 2], cx
    mov byte [r13 + 0], IR_NOP
    jmp .next
.load_miss:
    ; r8 is a valid symbol index here (checked above)
    movzx ecx, word [r13 + 2]  ; dst vreg
    mov [var_cached_vreg + r8 * 2], cx

.next:
    inc ebx
    jmp .loop
.done:
    ret


pass_peephole:
    ; Simplifies algebraic identities (+0, *1, *0, *2).
    ; NOTE: vreg_is_const[] is still populated from pass_constant_folding,
    ; so peephole reads correct data.  New aliases written here are consumed
    ; by pass_apply_aliases which runs immediately after.
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
    ; Check if src2 is constant 2 (strength reduction)
    cmp qword [vreg_const_val + rdx * 8], 2
    je .src2_two
    jmp .check_src1

.src2_two:
    cmp eax, IR_MUL
    je .reduce_mul_src2
    jmp .check_src1

.reduce_mul_src2:
    mov byte [r13 + 0], IR_ADD
    mov [r13 + 6], cx   ; src2 = src1 (x * 2 => x + x)
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
    cmp byte [vreg_is_const + rcx], 1
    jne .next
    cmp qword [vreg_const_val + rcx * 8], 0
    je .src1_zero
    cmp qword [vreg_const_val + rcx * 8], 1
    je .src1_one
    cmp qword [vreg_const_val + rcx * 8], 2
    je .src1_two
    jmp .next

.src1_two:
    cmp eax, IR_MUL
    je .reduce_mul_src1
    jmp .next

.reduce_mul_src1:
    mov byte [r13 + 0], IR_ADD
    mov [r13 + 4], dx   ; src1 = src2 (2 * x => x + x)
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
    ; dst = src1; record alias and NOP the instruction
    movzx rax, word [r13 + 2]
    mov [vreg_alias + rax * 2], cx
    mov byte [r13 + 0], IR_NOP
    jmp .next

.alias_src2:
    movzx rax, word [r13 + 2]
    mov [vreg_alias + rax * 2], dx
    mov byte [r13 + 0], IR_NOP
    jmp .next

.zero_out:
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


; ============================================================
;  Bug 2 fix: pass_apply_aliases
;  Propagates ALL accumulated vreg_alias entries through the IR.
;  Runs after pass_peephole to catch aliases created by both
;  pass_load_store_coalescing and pass_peephole.
; ============================================================
pass_apply_aliases:
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
    cmp eax, IR_NOP
    je .next   ; skip already-eliminated instructions

    ; Apply alias to src1
    movzx ecx, word [r13 + 4]
    test cx, cx
    jz .check_src2
    call opt_follow_alias
    test rax, rax
    jz .check_src2
    mov [r13 + 4], ax

.check_src2:
    movzx ecx, word [r13 + 6]
    test cx, cx
    jz .next
    call opt_follow_alias
    test rax, rax
    jz .next
    mov [r13 + 6], ax

.next:
    inc ebx
    jmp .loop
.done:
    ret


; ============================================================
;  Helper: opt_follow_alias(vreg in rcx)
;  Follows the vreg_alias chain from rcx to its canonical target.
;  Returns rax = canonical vreg if it differs from rcx, else 0.
; ============================================================
opt_follow_alias:
    movzx rax, cx           ; current = input
.follow:
    movzx rdx, word [vreg_alias + rax * 2]
    test dx, dx
    jz .chain_end           ; no further alias
    movzx rax, dx
    jmp .follow
.chain_end:
    ; rax = canonical end; check if it differs from input
    movzx rcx, cx           ; re-zero-extend input
    cmp rax, rcx
    je .no_change
    ret                     ; rax = canonical (non-zero, different)
.no_change:
    xor eax, eax            ; 0 = "no alias applied"
    ret
