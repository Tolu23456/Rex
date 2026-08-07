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

LP_VMAX equ 1024   ; max vregs tracked by allocator (GRAPHCOL_VMAX)

section .bss
    extern ir_buffer
    extern ir_count
    extern sym_find_by_offset
    extern alloc_vreg
    extern gc_force_callee

    vreg_is_const   resb VREG_MAX
    vreg_const_val  resq VREG_MAX
    
    var_is_const    resb VAR_MAX
    var_const_val   resq VAR_MAX

    var_is_read     resb VAR_MAX
    
    var_cached_vreg resw VAR_MAX
    global vreg_alias
    vreg_alias      resw VREG_MAX

    global prom_debug
    prom_debug      resb 1          ; debug: stage reached in loop promotion (0=none)

    ; ---- loop-promotion state ----
    opt_label_index resd 256        ; label id → IR record index (0xFFFFFFFF = none)
    prom_internal   resb 256        ; 1 = label defined inside current loop region
    prom_i_sym      resq 1          ; induction-variable symbol offset
    prom_end_sym    resq 1          ; loop-bound symbol offset
    prom_iv_dst     resw 1          ; dst vreg of the induction-variable header load
    prom_v_iv       resw 1          ; dedicated vreg for the induction variable
    prom_v_end      resw 1          ; dedicated vreg for the loop bound
    prom_l0         resd 1          ; loop header label id
    prom_l1         resd 1          ; loop exit label id
    prom_dst_a      resw 1          ; dst of header LOAD at h+1
    prom_dst_b      resw 1          ; dst of header LOAD at h+2
    prom_off_a      resq 1          ; offset of header LOAD at h+1
    prom_off_b      resq 1          ; offset of header LOAD at h+2
    prom_dst_c      resw 1          ; dst of header CMP_BOOL
    prom_cmp_idx    resd 1          ; index of header CMP_BOOL
    prom_sym_off    resq 32         ; promoted symbol offsets
    prom_sym_vr     resw 32         ; dedicated vreg per promoted symbol
    prom_sym_cnt    resd 1          ; number of promoted symbols
    prom_h_bytes    resq 1          ; h * IR_RECORD_SIZE
    prom_hs_bytes   resq 1          ; (h + N) * IR_RECORD_SIZE
    prom_shift      resd 1          ; N+H = 2 + sym_cnt + hoisted (header insert count)
    mb_bytes        resd 1          ; memmove byte count
    mb_idx_bytes    resq 1          ; memmove byte offset base
    mb_wb_bytes     resd 1          ; write-back byte count
    prom_rd_cnt     resd 1          ; number of registered promoted reads (body)
    prom_rd_vr      resw 128        ; read vreg (vR) per registered promoted read
    prom_rd_sym     resw 128        ; promoted vreg (vS) per registered promoted read
    prom_span_beg   resd 1          ; body span start index (inclusive)
    prom_span_end   resd 1          ; body span end index (inclusive)
    prom_store_vreg resw 1          ; target vreg of the promoted store being handled
    prom_hoist_cnt  resd 1          ; number of hoisted loop-invariant LOAD_IMMs
    prom_hoist_idx  resw 64         ; original record index per hoisted LOAD_IMM
    prom_hoist_typ  resb 64         ; type byte per hoisted LOAD_IMM
    prom_hoist_dst  resw 64         ; dst vreg per hoisted LOAD_IMM
    prom_hoist_imm  resq 64         ; immediate value per hoisted LOAD_IMM
    nest_h2         resd 1          ; nested-loop header index
    nest_j2         resd 1          ; nested-loop back-edge index

    fold_iv_dst     resw 1          ; loop-var header load dst (h+1)
    fold_iv_off     resq 1          ; loop-var offset
    fold_end_dst    resw 1          ; end header load dst (h+2)
    fold_end_off    resq 1          ; end variable offset
    fold_cmp_dst    resw 1          ; header CMP_BOOL dst
    fold_l0         resd 1          ; loop-back label id
    fold_l1         resd 1          ; exit label id
    fold_cond       resd 1          ; COND_LT (exclusive '..') / COND_LE (inclusive '..=')
    fold_step_src   resd 1          ; 0 = LOAD_IMM step, 1 = hidden __for_step var
    fold_step_off   resq 1          ; hidden step-var offset (when step_src == 1)
    fold_step_val   resq 1          ; static step value S (> 0, < 2^63)
    fold_n_val      resq 1          ; static iteration bound N
    fold_k_val      resq 1          ; iteration count K
    fold_c_val      resq 1          ; closed-form constant C = S*(K-1)*K/2
    fold_i_post     resq 1          ; post-loop i value = S*K
    fold_acc_cnt    resd 1          ; number of accumulator groups in the body
    fold_acc_off    resq 32         ; accumulator symbol offsets
    fold_acc_op     resb 32         ; per-acc opcode (IR_ADD / IR_SUB)
    fold_acc_va     resw 32         ; body: acc LOAD_VAR dst
    fold_acc_vc     resw 32         ; body: acc op dst
    fold_acc_vt     resw 32         ; rewrite: acc load dst
    fold_acc_vc2    resw 32         ; rewrite: const load dst
    fold_acc_vd2    resw 32         ; rewrite: op dst
    fold_inc_vf     resw 1          ; body: increment ADD dst
    fold_vi         resw 1          ; rewrite: post-loop i load dst

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
    call pass_sum_fold        ; <-- closed-form accumulation fold (static N)
    call pass_loop_promote    ; <-- register promotion for canonical loops

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

pass_constant_folding:
    ; Fold constant expressions. vreg constants are SSA-sound (a vreg is
    ; defined exactly once), so they can be tracked across branches safely.
    ; var_is_const is only sound within a branch-free linear region, so it is
    ; invalidated at every branch opcode (IR_JCC/JMP/LABEL/CALL/…): a store
    ; followed by a branch may be bypassed, so later loads must not fold.
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
    
    ; Branch or call — invalidate var constants, skip this instruction
    cmp eax, IR_JCC
    je .invalidate_and_next
    cmp eax, IR_JMP
    je .invalidate_and_next
    cmp eax, IR_LABEL
    je .invalidate_and_next
    cmp eax, IR_CALL
    je .invalidate_and_next
    cmp eax, IR_CALL_ARG
    je .invalidate_and_next
    cmp eax, IR_PROTO_BEGIN
    je .invalidate_and_next
    cmp eax, IR_SAVE_ARG
    je .invalidate_and_next
    cmp eax, IR_SAVE_LOCAL_VAR
    je .invalidate_and_next
    cmp eax, IR_RESTORE_LOCAL_VAR
    je .invalidate_and_next
    cmp eax, IR_WHEN
    je .invalidate_and_next
    cmp eax, IR_ABORT
    je .invalidate_and_next

    cmp eax, IR_LOAD_IMM
    je .handle_load_imm

    ; Bug 7 fix: track float immediate loads just like integer ones.
    cmp eax, IR_LOAD_FIMM
    je .handle_load_fimm
    
    cmp eax, IR_STORE_VAR
    je .handle_store_var
    
    cmp eax, IR_LOAD_VAR
    je .handle_load_var

    cmp eax, IR_SWAP_VARS
    je .handle_swap_vars
    
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

.handle_swap_vars:
    ; IR_SWAP_VARS invalidates constant tracking for both swapped offsets
    mov rdi, [r13 + 8] ; imm = offset_a
    call sym_find_by_offset
    cmp rax, -1
    je .swap_vars_b
    mov byte [var_is_const + rax], 0
.swap_vars_b:
    mov rdi, [r13 + 16] ; aux = offset_b
    call sym_find_by_offset
    cmp rax, -1
    je .next
    mov byte [var_is_const + rax], 0
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
    ; Guard against INT64_MIN / -1 (signed overflow fault)
    cmp r9, -1
    jne .div_safe
    test r8, r8
    jns .div_safe
    ; r9 == -1 and r8 < 0: only INT64_MIN is fatal. r8 << 1 == 0 ⇔ r8 == INT64_MIN
    mov rax, r8
    shl rax, 1
    test rax, rax
    jnz .div_safe
    jmp .next
.div_safe:
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
    ; Guard against INT64_MIN % -1 (signed overflow fault)
    cmp r9, -1
    jne .mod_safe
    test r8, r8
    jns .mod_safe
    ; r9 == -1 and r8 < 0: only INT64_MIN is fatal. r8 << 1 == 0 ⇔ r8 == INT64_MIN
    mov rax, r8
    shl rax, 1
    test rax, rax
    jnz .mod_safe
    jmp .next
.mod_safe:
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

.invalidate_and_next:
    ; A branch/call may bypass a prior const store — drop all var constants.
    mov rcx, VAR_MAX
    lea rdi, [var_is_const]
    xor eax, eax
    rep stosb
    jmp .next

.next:
    inc ebx
    jmp .loop

.done:
    ret


pass_dead_store_elimination:
    ; Scan for branching IR opcodes. If any exist, skip this pass entirely
    ; because reverse-scan DSE is unsound across branches.
    call has_branching_ir
    test rax, rax
    jnz .done
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
    
    ; IR_SWAP_VARS reads both memory operands (imm=offset_a, aux=offset_b) even
    ; though neither is expressed as a vreg — without marking them read, a store
    ; feeding the swap is killed as dead and the swap exchanges with garbage.
    cmp eax, IR_SWAP_VARS
    je .dse_swap_vars
    
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
    
.dse_swap_vars:
    mov rdi, [r13 + 8] ; imm = offset_a
    call sym_find_by_offset
    cmp rax, -1
    je .dse_swap_b
    mov r8, rax
    mov byte [var_is_read + r8], 1
.dse_swap_b:
    mov rdi, [r13 + 16] ; aux = offset_b
    call sym_find_by_offset
    cmp rax, -1
    je .next_dse
    mov r8, rax
    mov byte [var_is_read + r8], 1
    
.next_dse:
    test ebx, ebx
    jnz .dse_loop

.done:
    ret


pass_load_store_coalescing:
    ; Scan for branching IR opcodes. If any exist, skip this pass entirely
    ; because forward-scan coalescing is unsound across branches/loops.
    call has_branching_ir
    test rax, rax
    jnz .done
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
    cmp eax, IR_SWAP_VARS
    je .swap_coalesce
    
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
    jmp .next

.swap_coalesce:
    ; IR_SWAP_VARS invalidates cached vreg for both swapped offsets
    mov rdi, [r13 + 8] ; imm = offset_a
    call sym_find_by_offset
    cmp rax, -1
    je .swap_coalesce_b
    mov word [var_cached_vreg + rax * 2], 0
.swap_coalesce_b:
    mov rdi, [r13 + 16] ; aux = offset_b
    call sym_find_by_offset
    cmp rax, -1
    je .next
    mov word [var_cached_vreg + rax * 2], 0

.next:
    inc ebx
    jmp .loop
.done:
    ret


pass_peephole:
    ; Simplifies algebraic identities (+0, *1, *0, *2).
    ; vreg_is_const[] is populated by pass_constant_folding (which always runs),
    ; so peephole reads correct data.  All rewrites here operate on vregs,
    ; which are SSA (defined exactly once), so they remain sound across
    ; branches/loops.  New aliases written here are consumed by
    ; pass_apply_aliases which runs immediately after.
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
    cmp eax, IR_MOD
    je .arith
    cmp eax, IR_XOR
    je .arith
    cmp eax, IR_AND
    je .arith
    cmp eax, IR_OR
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
    ; Check if src1 == src2 (x op x patterns)
    cmp cx, dx
    jne .check_src1
    cmp eax, IR_XOR      ; x ^ x = 0
    je .zero_out
    cmp eax, IR_SUB      ; x - x = 0
    je .zero_out
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
    cmp eax, IR_XOR      ; x ^ 0 = x
    je .alias_src1
    cmp eax, IR_AND      ; x & 0 = 0
    je .zero_out
    cmp eax, IR_OR       ; x | 0 = x
    je .alias_src1
    jmp .next

.src2_one:
    cmp eax, IR_MUL
    je .alias_src1
    cmp eax, IR_DIV
    je .alias_src1
    cmp eax, IR_MOD      ; x % 1 = 0 (for int only)
    jne .next
    cmp byte [r13 + 1], TYPE_FLOAT
    je .next
    jmp .zero_out

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
    cmp eax, IR_SUB      ; 0 - x = -x
    je .neg_src2
    cmp eax, IR_MUL
    je .zero_out
    cmp eax, IR_DIV
    jne .check_src1_mod
    ; For float: 0.0 / 0.0 = NaN, so don't fold
    cmp byte [r13 + 1], TYPE_FLOAT
    je .next
    jmp .zero_out
.check_src1_mod:
    cmp eax, IR_MOD      ; 0 % x = 0
    jne .next
    cmp byte [r13 + 1], TYPE_FLOAT
    je .next
    jmp .zero_out

.neg_src2:
    ; 0 - x = NEG x: transform SUB into NEG
    mov byte [r13 + 0], IR_NEG
    ; src1 becomes src2 (the value to negate)
    movzx eax, word [r13 + 6]
    mov [r13 + 4], ax
    mov word [r13 + 6], 0
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
    ; Use IR_LOAD_FIMM for float types, IR_LOAD_IMM for others
    movzx eax, byte [r13 + 1]  ; type byte
    cmp al, TYPE_FLOAT
    je .zero_out_float
    mov byte [r13 + 0], IR_LOAD_IMM
    jmp .zero_out_common
.zero_out_float:
    mov byte [r13 + 0], IR_LOAD_FIMM
.zero_out_common:
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
;  pass_load_store_coalescing (straight-line code only) and pass_peephole.
;  Aliases are SSA facts (each dst vreg is defined exactly once), so
;  propagation remains sound across branches/loops.
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
    mov r9d, VREG_MAX       ; iteration limit for cycle detection
.follow:
    dec r9d
    jz .chain_end           ; cycle or depth limit — stop
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


; ============================================================
;  pass_loop_promote
;  Rewrites canonical for-loops so the induction variable, loop
;  bound and body-accumulators flow through physical registers
;  (r12-r15) instead of absolute-memory round-trips each iteration.
;
;  Detects the shape emitted by the for/while parser:
;      STORE_VAR end_sym <- X        (before loop)
;      STORE_VAR i_sym  <- Y         (before loop)
;    L0:
;      LOAD_VAR i_sym   -> va
;      LOAD_VAR end_sym -> vb
;      CMP_BOOL va <cond> vb -> vc
;      JCC vc COND_NE -> L1
;      [body]
;      LOAD_VAR i_sym -> v4
;      LOAD_IMM 1 -> v5
;      ADD v4 v5 -> v6
;      STORE_VAR i_sym <- v6
;      JMP L0
;    L1:
;
;  and rewrites it to keep i_sym/end_sym (and any symbol whose
;  accesses lie entirely within the loop) in dedicated vregs that
;  the allocator pins to callee-saved colours:
;      LOAD_VAR i_sym  -> v_iv      (once, before L0)
;      LOAD_VAR end_sym -> v_end    (once, before L0)
;    L0:
;      CMP_BOOL v_iv <cond> v_end -> vc
;      JCC vc COND_NE -> L1
;      [body; in-loop LOAD_VAR S / STORE_VAR S become IR_MOV on v_S]
;      JMP L0
;    L1:
;      STORE_VAR i_sym  <- v_iv     (write-back, once)
;      STORE_VAR end_sym <- v_end   (write-back, once)
;      ...
;
;  Returns rax = 1 if a loop was promoted, 0 otherwise.
; ============================================================
pass_loop_promote:
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; Clear force-callee flags from a previous run
    mov ecx, LP_VMAX
    lea rdi, [gc_force_callee]
    xor eax, eax
    rep stosb
    mov byte [prom_debug], 5

.scan_again:
    call opt_build_label_index
    mov r12d, [ir_count]
    test r12d, r12d
    jz .done
    xor ebx, ebx                ; i = 0
.loop:
    cmp ebx, r12d
    jae .done
    imul eax, ebx, IR_RECORD_SIZE
    lea r13, [ir_buffer + rax]
    movzx eax, byte [r13]
    cmp al, IR_JMP
    jne .next_i
    mov byte [prom_debug], 6
    mov ecx, [r13 + 8]          ; target label id
    cmp ecx, 256
    jae .next_i
    mov edx, [opt_label_index + rcx * 4]
    cmp edx, 0xFFFFFFFF
    je .next_i
    cmp edx, ebx                ; header must precede back-edge
    jae .next_i
    mov edi, edx                ; h = header index
    mov esi, ebx                ; j = back-edge index
    call opt_try_promote_loop
    test rax, rax
    jnz .scan_again             ; promoted → rebuild label map, rescan
.next_i:
    inc ebx
    jmp .loop
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret


; ============================================================
; pass_sum_fold — closed-form accumulation fold
;
;   Detects the canonical static-bound loop (start == 0, exclusive '..'
;   or inclusive '..=', optional static step):
;       STORE_VAR i_sym <- 0            (pre-loop)
;       STORE_VAR end_sym <- N          (pre-loop, N constant)
;       [STORE_VAR step_sym <- S]       (pre-loop, only for explicit 'step')
;     L0: LOAD_VAR i_sym  -> vi
;         LOAD_VAR end_sym -> ve
;         CMP_BOOL (vi < ve) -> vc       (COND_LT for '..', COND_LE for '..=')
;         JCC vc COND_NE -> L1
;         <body: N accumulator groups, each>         4 records / accumulator
;           LOAD_VAR acc_sym  -> va
;           LOAD_VAR i_sym    -> vx
;           ADD/SUB vd <- va (+|-) vx
;           STORE_VAR acc_sym <- vd
;         <increment group>                          4 records (last)
;           LOAD_VAR i_sym   -> vi2
;           LOAD_IMM S / LOAD_VAR step_sym -> v1
;           ADD vi3 <- vi2 + v1
;           STORE_VAR i_sym  <- vi3
;         JMP L0
;     L1:
;
;   K = iteration count: ceil(N/S) for '..', floor(N/S)+1 for '..='.
;   The region is rewritten in place to the closed form
;   (C = S*(K-1)*K/2 is added to every accumulator, i ends at S*K):
;       LOAD_VAR acc_sym -> vt2            (per accumulator)
;       LOAD_IMM C      -> vc2
;       ADD/SUB vd2 <- vt2 (+|-) vc2
;       STORE_VAR acc_sym <- vd2
;       LOAD_IMM S*K    -> vi
;       STORE_VAR i_sym  <- vi             (preserve post-loop i == S*K)
;   For K == 0 the loop never runs: the region is NOPed (i stays 0).
;   For K == 1 the accumulation is a no-op: only i is set to S*K.
;   The fold is exact only when K <= 2^32, 0 < S < 2^63, and both C and
;   S*K fit in a non-negative i64; otherwise it falls back to the loop.
;
;   Returns rax = 1 if folded, 0 otherwise.
; ============================================================
pass_sum_fold:
    push rbx
    push r12
    push r13
    push r14
    push r15

.scan_again:
    call opt_build_label_index
    mov r12d, [ir_count]
    test r12d, r12d
    jz .done
    xor ebx, ebx
.loop:
    cmp ebx, r12d
    jae .done
    imul eax, ebx, IR_RECORD_SIZE
    lea r13, [ir_buffer + rax]
    movzx eax, byte [r13]
    cmp al, IR_JMP
    jne .next_i
    mov ecx, [r13 + 8]          ; target label id
    cmp ecx, 256
    jae .next_i
    mov edx, [opt_label_index + rcx * 4]
    cmp edx, 0xFFFFFFFF
    je .next_i
    cmp edx, ebx                ; header must precede back-edge
    jae .next_i
    mov edi, edx                ; h = header index
    mov esi, ebx                ; j = back-edge index
    call opt_try_sum_fold
    test rax, rax
    jnz .scan_again             ; folded → rebuild label map, rescan
.next_i:
    inc ebx
    jmp .loop
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; fold_last_store_src: edi = limit, rsi = offset
;   find the last STORE_VAR of `offset` at index < limit.
;   Returns: edx = store index (or -1), eax = src vreg.
;   Preserves rbx, r12-r15.
fold_last_store_src:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov edx, -1
    dec edi                     ; start at limit-1
.fscan:
    test edi, edi
    js .fscan_done
    imul eax, edi, IR_RECORD_SIZE
    lea rcx, [ir_buffer + rax]
    movzx eax, byte [rcx]
    cmp al, IR_STORE_VAR
    jne .fscan_next
    mov rax, [rcx + 8]
    cmp rax, rsi
    jne .fscan_next
    movzx eax, word [rcx + 4]
    mov edx, edi
    jmp .fscan_done
.fscan_next:
    dec edi
    jmp .fscan
.fscan_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; fold_imm_of: edi = limit, esi = vreg
;   find the last def of `vreg` at index < limit; if it is a LOAD_IMM,
;   return eax = 1 and the value in rdx, else eax = 0.
fold_imm_of:
    push rbx
    push r12
    push r13
    push r14
    push r15
    dec edi
.imscan:
    test edi, edi
    js .imm_not
    imul eax, edi, IR_RECORD_SIZE
    lea rcx, [ir_buffer + rax]
    movzx eax, word [rcx + 2]
    cmp eax, esi
    jne .imnext
    movzx eax, byte [rcx]
    cmp al, IR_LOAD_IMM
    jne .imm_not
    mov rdx, [rcx + 8]
    mov eax, 1
    jmp .imm_done
.imnext:
    dec edi
    jmp .imscan
.imm_not:
    xor eax, eax
.imm_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; opt_try_sum_fold: edi = h, esi = j  (in/out registers preserved)
opt_try_sum_fold:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12d, edi               ; h
    mov r13d, esi               ; j

    ; [h] = LABEL L0
    imul eax, r12d, IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    movzx eax, byte [r15]
    cmp al, IR_LABEL
    jne .fail
    mov rax, [r15 + 8]
    cmp rax, 256
    jae .fail
    mov [fold_l0], eax

    ; [h+1] = LOAD_VAR -> da, off_a  (loop variable)
    lea edx, [r12 + 1]
    imul eax, edx, IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    movzx eax, byte [r15]
    cmp al, IR_LOAD_VAR
    jne .fail
    movzx eax, word [r15 + 2]
    mov [fold_iv_dst], ax
    mov rax, [r15 + 8]
    mov [fold_iv_off], rax

    ; [h+2] = LOAD_VAR -> db, off_b  (end variable)
    lea edx, [r12 + 2]
    imul eax, edx, IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    movzx eax, byte [r15]
    cmp al, IR_LOAD_VAR
    jne .fail
    movzx eax, word [r15 + 2]
    mov [fold_end_dst], ax
    mov rax, [r15 + 8]
    mov [fold_end_off], rax

    ; dst_a and dst_b must differ
    movzx eax, word [fold_iv_dst]
    movzx ecx, word [fold_end_dst]
    cmp eax, ecx
    je .fail

    ; [h+3] = CMP_BOOL dc = (da, db), aux == COND_LT or COND_LE
    lea edx, [r12 + 3]
    imul eax, edx, IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    movzx eax, byte [r15]
    cmp al, IR_CMP_BOOL
    jne .fail
    movzx eax, word [r15 + 2]
    mov [fold_cmp_dst], ax
    movzx eax, word [r15 + 4]
    movzx ecx, word [r15 + 6]
    movzx edx, word [fold_iv_dst]
    movzx edi, word [fold_end_dst]
    cmp eax, edx                ; src1 must be da
    jne .fail
    cmp ecx, edi                ; src2 must be db
    jne .fail
    mov rax, [r15 + 16]         ; aux
    cmp rax, COND_LT
    je .cond_ok
    cmp rax, COND_LE
    jne .fail
.cond_ok:
    mov [fold_cond], eax

    ; [h+4] = JCC: src1 == dc, aux == COND_NE, target L1
    lea edx, [r12 + 4]
    imul eax, edx, IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    movzx eax, byte [r15]
    cmp al, IR_JCC
    jne .fail
    movzx eax, word [r15 + 4]
    movzx ecx, word [fold_cmp_dst]
    cmp eax, ecx
    jne .fail
    movzx eax, byte [r15 + 16]
    cmp al, COND_NE
    jne .fail
    mov rax, [r15 + 8]
    cmp rax, 256
    jae .fail
    mov [fold_l1], eax
    ; label_index[L1] must equal j+1, [j+1] = LABEL L1, [j] = JMP L0
    mov eax, [opt_label_index + rax * 4]
    lea edx, [r13 + 1]
    cmp eax, edx
    jne .fail
    imul eax, edx, IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    movzx eax, byte [r15]
    cmp al, IR_LABEL
    jne .fail
    mov rax, [r15 + 8]
    cmp eax, [fold_l1]
    jne .fail
    imul eax, r13d, IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    movzx eax, byte [r15]
    cmp al, IR_JMP
    jne .fail
    mov rax, [r15 + 8]
    cmp eax, [fold_l0]
    jne .fail


    ; ---- Body scan: groups of 4 records starting at h+5 ----
    ; Each group is either an accumulator (LOAD_VAR acc; LOAD_VAR i;
    ; ADD/SUB; STORE_VAR acc) or, as the last group, the increment
    ; (LOAD_VAR i; LOAD_IMM S / LOAD_VAR step; ADD; STORE_VAR i).
    xor r14d, r14d              ; accumulator count
    lea r15d, [r12 + 5]         ; p = body start
    lea ebx, [r13 - 4]          ; increment group must start at j-4
.grp_loop:
    cmp r15d, ebx
    jae .grp_inc
    cmp r14d, 32
    jae .fail
    imul eax, r15d, IR_RECORD_SIZE
    lea rdi, [ir_buffer + rax]
    ; [p] = LOAD_VAR -> va_k, off_x
    movzx eax, byte [rdi]
    cmp al, IR_LOAD_VAR
    jne .fail
    movzx eax, word [rdi + 2]
    mov [fold_acc_va + r14*2], ax
    mov rax, [rdi + 8]
    mov [fold_acc_off + r14*8], rax
    ; accumulator must differ from loop var and end var
    cmp rax, [fold_iv_off]
    je .fail
    cmp rax, [fold_end_off]
    je .fail
    ; [p+1] = LOAD_VAR iv_off -> r8 (do not clobber rbx = boundary)
    add rdi, IR_RECORD_SIZE
    movzx eax, byte [rdi]
    cmp al, IR_LOAD_VAR
    jne .fail
    movzx r8d, word [rdi + 2]
    mov rax, [rdi + 8]
    cmp rax, [fold_iv_off]
    jne .fail
    ; [p+2] = ADD/SUB vc_k = va_k (+|-) iv
    add rdi, IR_RECORD_SIZE
    movzx eax, byte [rdi]
    cmp al, IR_ADD
    je .acc_add
    cmp al, IR_SUB
    jne .fail
    ; SUB: src1 = va_k, src2 = iv
    movzx eax, word [rdi + 4]
    cmp ax, [fold_acc_va + r14*2]
    jne .fail
    movzx eax, word [rdi + 6]
    cmp ax, r8w
    jne .fail
    jmp .acc_op_done
.acc_add:
    ; ADD: srcs {va_k, iv} in either order
    movzx eax, word [rdi + 4]
    movzx ecx, word [rdi + 6]
    cmp ax, [fold_acc_va + r14*2]
    jne .add_swapped
    cmp cx, r8w
    jne .fail
    jmp .acc_op_done
.add_swapped:
    cmp ax, r8w
    jne .fail
    movzx edx, word [fold_acc_va + r14*2]
    cmp cx, dx
    jne .fail
.acc_op_done:
    movzx eax, byte [rdi]
    mov [fold_acc_op + r14], al
    movzx eax, word [rdi + 2]
    mov [fold_acc_vc + r14*2], ax
    ; [p+3] = STORE_VAR acc_off <- vc_k
    add rdi, IR_RECORD_SIZE
    movzx eax, byte [rdi]
    cmp al, IR_STORE_VAR
    jne .fail
    movzx eax, word [rdi + 4]
    cmp ax, [fold_acc_vc + r14*2]
    jne .fail
    mov rax, [rdi + 8]
    cmp rax, [fold_acc_off + r14*8]
    jne .fail
    inc r14d
    add r15d, 4
    jmp .grp_loop

    ; ---- Increment group (last) ----
.grp_inc:
    cmp r15d, ebx
    jne .fail                   ; must be exactly at j-4
    imul eax, r15d, IR_RECORD_SIZE
    lea rdi, [ir_buffer + rax]
    ; [p] = LOAD_VAR iv_off -> rbx
    movzx eax, byte [rdi]
    cmp al, IR_LOAD_VAR
    jne .fail
    movzx ebx, word [rdi + 2]
    mov rax, [rdi + 8]
    cmp rax, [fold_iv_off]
    jne .fail
    ; [p+1] = LOAD_IMM S or LOAD_VAR step_off -> rcx
    add rdi, IR_RECORD_SIZE
    movzx eax, byte [rdi]
    cmp al, IR_LOAD_IMM
    je .inc_imm
    cmp al, IR_LOAD_VAR
    jne .fail
    mov rax, [rdi + 8]          ; hidden step-var offset
    mov [fold_step_off], rax
    mov dword [fold_step_src], 1
    jmp .inc_src_done
.inc_imm:
    mov rax, [rdi + 8]
    mov [fold_step_val], rax
    mov dword [fold_step_src], 0
.inc_src_done:
    movzx ecx, word [rdi + 2]
    ; [p+2] = ADD vf = rbx + rcx (either order)
    add rdi, IR_RECORD_SIZE
    movzx eax, byte [rdi]
    cmp al, IR_ADD
    jne .fail
    movzx eax, word [rdi + 4]
    movzx edx, word [rdi + 6]
    cmp ax, bx
    jne .inc_add_swapped
    cmp dx, cx
    jne .fail
    jmp .inc_add_done
.inc_add_swapped:
    cmp ax, cx
    jne .fail
    cmp dx, bx
    jne .fail
.inc_add_done:
    movzx eax, word [rdi + 2]
    mov [fold_inc_vf], ax
    ; [p+3] = STORE_VAR iv_off <- vf
    add rdi, IR_RECORD_SIZE
    movzx eax, byte [rdi]
    cmp al, IR_STORE_VAR
    jne .fail
    movzx eax, word [rdi + 4]
    cmp ax, [fold_inc_vf]
    jne .fail
    mov rax, [rdi + 8]
    cmp rax, [fold_iv_off]
    jne .fail

    ; Resolve the static step value
    cmp dword [fold_step_src], 0
    je .step_resolved
    mov edi, r12d               ; limit = h
    mov rsi, [fold_step_off]
    call fold_last_store_src
    cmp edx, -1
    je .fail
    mov edi, edx
    mov esi, eax
    call fold_imm_of
    test eax, eax
    jz .fail
    mov [fold_step_val], rdx
.step_resolved:
    ; require 1 <= S < 2^63 (positive i64 step)
    mov rax, [fold_step_val]
    test rax, rax
    jz .fail
    mov rdx, 0x8000000000000000
    cmp rax, rdx
    jae .fail

    ; --- Resolve pre-loop end value N and start == 0 ---
    mov edi, r12d
    mov rsi, [fold_end_off]
    call fold_last_store_src
    cmp edx, -1
    je .fail
    mov edi, edx
    mov esi, eax
    call fold_imm_of
    test eax, eax
    jz .fail                    ; runtime bound → not a static fold
    mov [fold_n_val], rdx
    mov edi, r12d
    mov rsi, [fold_iv_off]
    call fold_last_store_src
    cmp edx, -1
    je .fail
    mov edi, edx
    mov esi, eax
    call fold_imm_of
    test eax, eax
    jz .fail
    cmp rdx, 0
    jne .fail                   ; only fold start == 0 loops

    ; --- Compute K = iteration count ---
    ;   exclusive (COND_LT): K = N/S + (N%S != 0)
    ;   inclusive (COND_LE): K = N/S + 1
    mov rax, [fold_n_val]
    xor edx, edx
    div qword [fold_step_val]   ; rax = q = N/S, rdx = r = N%S
    mov [fold_k_val], rax
    cmp dword [fold_cond], COND_LE
    je .k_inclusive
    test rdx, rdx
    jz .k_done
    inc qword [fold_k_val]
    jmp .k_done
.k_inclusive:
    inc qword [fold_k_val]
.k_done:

    ; --- Decide the rewrite based on K ---
    mov rax, [fold_k_val]
    test rax, rax
    jz .k_zero                  ; K == 0 → loop never runs
    cmp rax, 2
    jb .k_one                   ; K == 1 → only set i = S*K
    mov rdx, 0x100000000
    cmp rax, rdx
    ja .fail                    ; K > 2^32 → (K-1)*K/2 overflows i64
    ; T = (K-1)*K/2
    lea rdx, [rax - 1]
    imul rdx, rax
    shr rdx, 1
    ; C = S*T must fit u64 and be non-negative i64
    mov rax, [fold_step_val]
    mul rdx                     ; rdx:rax = S*T
    test rdx, rdx
    jnz .fail
    test rax, rax
    js .fail
    mov [fold_c_val], rax
    ; i_post = S*K must fit u64 and be non-negative i64
    mov rax, [fold_step_val]
    mul qword [fold_k_val]      ; rdx:rax = S*K
    test rdx, rdx
    jnz .fail
    test rax, rax
    js .fail
    mov [fold_i_post], rax
    ; allocate rewrite vregs (3 per accumulator + 1 for i)
    xor ebx, ebx
.alloc_loop:
    cmp ebx, r14d
    jae .alloc_done
    call alloc_vreg
    mov [fold_acc_vt + rbx*2], ax
    call alloc_vreg
    mov [fold_acc_vc2 + rbx*2], ax
    call alloc_vreg
    mov [fold_acc_vd2 + rbx*2], ax
    inc ebx
    jmp .alloc_loop
.alloc_done:
    call alloc_vreg
    mov [fold_vi], ax
    jmp .rewrite_full

.k_one:
    ; K == 1: accumulation is a no-op, i must end at S*K == S
    mov rax, [fold_step_val]
    mov [fold_i_post], rax
    call alloc_vreg
    mov [fold_vi], ax
    jmp .rewrite_set_i
.k_zero:
    ; K == 0: loop never runs, region becomes NOPs (i stays 0)
    lea ebx, [r12]
    jmp .nop_loop

.rewrite_full:
    ; [h .. h+4*acc-1]: per-accumulator closed-form add
    imul eax, r12d, IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    xor ebx, ebx
.acc_rw_loop:
    cmp ebx, r14d
    jae .acc_rw_done
    ; LOAD_VAR acc_off -> vt
    mov byte [r15], IR_LOAD_VAR
    mov byte [r15 + 1], TYPE_INT
    movzx eax, word [fold_acc_vt + rbx*2]
    mov [r15 + 2], ax
    mov word [r15 + 4], 0
    mov word [r15 + 6], 0
    mov rax, [fold_acc_off + rbx*8]
    mov [r15 + 8], rax
    mov qword [r15 + 16], 0
    mov dword [r15 + 24], 0
    mov dword [r15 + 28], 0
    add r15, IR_RECORD_SIZE
    ; LOAD_IMM C -> vc2
    mov byte [r15], IR_LOAD_IMM
    mov byte [r15 + 1], TYPE_INT
    movzx eax, word [fold_acc_vc2 + rbx*2]
    mov [r15 + 2], ax
    mov word [r15 + 4], 0
    mov word [r15 + 6], 0
    mov rax, [fold_c_val]
    mov [r15 + 8], rax
    mov qword [r15 + 16], 0
    mov dword [r15 + 24], 0
    mov dword [r15 + 28], 0
    add r15, IR_RECORD_SIZE
    ; ADD/SUB vd2 <- vt (+|-) vc2
    movzx eax, byte [fold_acc_op + rbx]
    mov byte [r15], al
    mov byte [r15 + 1], TYPE_INT
    movzx eax, word [fold_acc_vd2 + rbx*2]
    mov [r15 + 2], ax
    movzx eax, word [fold_acc_vt + rbx*2]
    mov [r15 + 4], ax
    movzx eax, word [fold_acc_vc2 + rbx*2]
    mov [r15 + 6], ax
    mov qword [r15 + 8], 0
    mov qword [r15 + 16], 0
    mov dword [r15 + 24], 0
    mov dword [r15 + 28], 0
    add r15, IR_RECORD_SIZE
    ; STORE_VAR acc_off <- vd2
    mov byte [r15], IR_STORE_VAR
    mov byte [r15 + 1], TYPE_INT
    mov word [r15 + 2], 0
    movzx eax, word [fold_acc_vd2 + rbx*2]
    mov [r15 + 4], ax
    mov word [r15 + 6], 0
    mov rax, [fold_acc_off + rbx*8]
    mov [r15 + 8], rax
    mov qword [r15 + 16], 0
    mov dword [r15 + 24], 0
    mov dword [r15 + 28], 0
    add r15, IR_RECORD_SIZE
    inc ebx
    jmp .acc_rw_loop
.acc_rw_done:
    ; LOAD_IMM i_post -> vi
    mov byte [r15], IR_LOAD_IMM
    mov byte [r15 + 1], TYPE_INT
    movzx eax, word [fold_vi]
    mov [r15 + 2], ax
    mov word [r15 + 4], 0
    mov word [r15 + 6], 0
    mov rax, [fold_i_post]
    mov [r15 + 8], rax
    mov qword [r15 + 16], 0
    mov dword [r15 + 24], 0
    mov dword [r15 + 28], 0
    add r15, IR_RECORD_SIZE
    ; STORE_VAR iv_off <- vi
    mov byte [r15], IR_STORE_VAR
    mov byte [r15 + 1], TYPE_INT
    mov word [r15 + 2], 0
    movzx eax, word [fold_vi]
    mov [r15 + 4], ax
    mov word [r15 + 6], 0
    mov rax, [fold_iv_off]
    mov [r15 + 8], rax
    mov qword [r15 + 16], 0
    mov dword [r15 + 24], 0
    mov dword [r15 + 28], 0
    ; NOP from h + 4*acc + 2 .. j+1
    mov eax, r14d
    lea ebx, [r12 + rax*4]
    add ebx, 2
    jmp .nop_loop

.rewrite_set_i:
    ; [h] LOAD_IMM i_post -> vi
    imul eax, r12d, IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    mov byte [r15], IR_LOAD_IMM
    mov byte [r15 + 1], TYPE_INT
    movzx eax, word [fold_vi]
    mov [r15 + 2], ax
    mov word [r15 + 4], 0
    mov word [r15 + 6], 0
    mov rax, [fold_i_post]
    mov [r15 + 8], rax
    mov qword [r15 + 16], 0
    mov dword [r15 + 24], 0
    mov dword [r15 + 28], 0
    ; [h+1] STORE_VAR iv_off <- vi
    add r15, IR_RECORD_SIZE
    mov byte [r15], IR_STORE_VAR
    mov byte [r15 + 1], TYPE_INT
    mov word [r15 + 2], 0
    movzx eax, word [fold_vi]
    mov [r15 + 4], ax
    mov word [r15 + 6], 0
    mov rax, [fold_iv_off]
    mov [r15 + 8], rax
    mov qword [r15 + 16], 0
    mov dword [r15 + 24], 0
    mov dword [r15 + 28], 0
    ; NOP h+2 .. j+1
    lea ebx, [r12 + 2]
    jmp .nop_loop

.nop_loop:
    lea edx, [r13 + 1]          ; NOP through the exit label j+1
    cmp ebx, edx
    ja .nop_done
    imul eax, ebx, IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    mov byte [r15], IR_NOP
    inc ebx
    jmp .nop_loop
.nop_done:
    mov eax, 1
    jmp .ret

.fail:
    xor eax, eax
.ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
opt_build_label_index:
    mov ecx, 256
    lea rdi, [opt_label_index]
    mov eax, 0xFFFFFFFF
    rep stosd
    mov ecx, [ir_count]
    test ecx, ecx
    jz .done
    xor edx, edx
.loop:
    cmp edx, ecx
    jae .done
    imul eax, edx, IR_RECORD_SIZE
    movzx eax, byte [ir_buffer + rax]
    cmp al, IR_LABEL
    jne .next
    imul eax, edx, IR_RECORD_SIZE
    mov edi, [ir_buffer + eax + 8]   ; label id
    cmp edi, 256
    jae .next
    mov [opt_label_index + rdi * 4], edx
.next:
    inc edx
    jmp .loop
.done:
    ret


; opt_try_promote_loop(h = edi, j = esi)
; Returns rax = 1 on success, 0 on failure.
opt_try_promote_loop:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12d, edi               ; h
    mov r13d, esi               ; j
    mov byte [prom_debug], 1

    ; Validate capacity for the inserts we may perform
    mov eax, [ir_count]
    add eax, 2 * 32 + 4
    cmp eax, IR_MAX_RECORDS
    ja .fail

    ; L0 id from record at h (must be a LABEL)
    imul eax, r12d, IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    movzx eax, byte [r15]
    cmp al, IR_LABEL
    jne .fail
    mov byte [prom_debug], 0x10
    mov rax, [r15 + 8]
    cmp rax, 256
    jae .fail
    mov [prom_l0], eax

    ; [h+1] must be IR_LOAD_VAR
    lea edx, [r12 + 1]
    imul eax, edx, IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    movzx eax, byte [r15]
    cmp al, IR_LOAD_VAR
    jne .fail
    movzx eax, word [r15 + 2]
    mov [prom_dst_a], ax
    mov rax, [r15 + 8]
    mov [prom_off_a], rax
    mov byte [prom_debug], 0x11

    ; [h+2] must be IR_LOAD_VAR
    lea edx, [r12 + 2]
    imul eax, edx, IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    movzx eax, byte [r15]
    cmp al, IR_LOAD_VAR
    jne .fail
    movzx eax, word [r15 + 2]
    mov [prom_dst_b], ax
    mov rax, [r15 + 8]
    mov [prom_off_b], rax
    ; dst_a and dst_b must differ
    movzx eax, word [prom_dst_a]
    movzx edx, word [prom_dst_b]
    cmp eax, edx
    je .fail
    mov byte [prom_debug], 0x12

    ; [h+3] must be IR_CMP_BOOL with src1/src2 == {dst_a, dst_b}
    lea edx, [r12 + 3]
    imul eax, edx, IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    movzx eax, byte [r15]
    cmp al, IR_CMP_BOOL
    jne .fail
    mov [prom_cmp_idx], edx
    movzx eax, word [r15 + 2]
    mov [prom_dst_c], ax
    movzx ebx, word [r15 + 4]   ; src1
    movzx ecx, word [r15 + 6]   ; src2
    movzx edx, word [prom_dst_a]
    movzx edi, word [prom_dst_b]
    cmp ebx, edx
    je .s1_is_a
    cmp ebx, edi
    jne .fail
    ; src1 == db, src2 must be da
    cmp ecx, edx
    jne .fail
    jmp .header_ok
.s1_is_a:
    ; src1 == da, src2 must be db
    cmp ecx, edi
    jne .fail
.header_ok:
    mov byte [prom_debug], 0x13

    ; [h+4] must be IR_JCC: src1 == dst_c, aux == COND_NE, target L1
    lea edx, [r12 + 4]
    imul eax, edx, IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    movzx eax, byte [r15]
    cmp al, IR_JCC
    jne .fail
    mov byte [prom_debug], 0x20
    movzx eax, word [r15 + 4]
    movzx ecx, word [prom_dst_c]
    cmp eax, ecx
    jne .fail
    mov byte [prom_debug], 0x21
    mov rax, [r15 + 16]         ; aux
    cmp rax, COND_NE
    jne .fail
    mov byte [prom_debug], 0x22
    mov rax, [r15 + 8]          ; L1
    cmp rax, 256
    jae .fail
    mov byte [prom_debug], 0x23
    mov [prom_l1], eax
    ; label_index[L1] must equal j+1 and record at j+1 must be LABEL L1
    mov eax, [opt_label_index + rax * 4]
    lea edx, [r13 + 1]
    cmp eax, edx
    jne .fail
    mov byte [prom_debug], 0x24
    imul eax, edx, IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    movzx eax, byte [r15]
    cmp al, IR_LABEL
    jne .fail
    mov byte [prom_debug], 0x25
    mov rax, [r15 + 8]
    cmp eax, [prom_l1]
    jne .fail
    mov byte [prom_debug], 0x14

    ; Find the increment store (i_sym): last STORE_VAR in (h, j) of
    ; either header symbol offset
    mov ebx, r13d
    dec ebx
.find_inc:
    lea eax, [r12 + 5]
    cmp ebx, eax
    jle .fail                   ; not found below h+5
    imul eax, ebx, IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    movzx eax, byte [r15]
    cmp al, IR_STORE_VAR
    jne .inc_next
    mov rax, [r15 + 8]
    cmp rax, [prom_off_a]
    je .inc_found_a
    cmp rax, [prom_off_b]
    je .inc_found_b
.inc_next:
    dec ebx
    jmp .find_inc
.inc_found_a:
    mov rax, [prom_off_a]
    mov [prom_i_sym], rax
    mov rax, [prom_off_b]
    mov [prom_end_sym], rax
    movzx eax, word [prom_dst_a]
    mov [prom_iv_dst], ax
    jmp .inc_done
.inc_found_b:
    mov rax, [prom_off_b]
    mov [prom_i_sym], rax
    mov rax, [prom_off_a]
    mov [prom_end_sym], rax
    movzx eax, word [prom_dst_b]
    mov [prom_iv_dst], ax
.inc_done:

    ; Region validation: no IR_RET / IR_HALT in [h, j]
    mov byte [prom_debug], 0x15
    mov ebx, r12d
.chk_ret:
    cmp ebx, r13d
    jae .chk_ret_done
    imul eax, ebx, IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    movzx eax, byte [r15]
    cmp al, IR_RET
    je .fail
    cmp al, IR_HALT
    je .fail
    inc ebx
    jmp .chk_ret
.chk_ret_done:

    ; Mark labels defined strictly inside (h, j)
    mov ecx, 256
    lea rdi, [prom_internal]
    xor eax, eax
    rep stosb
    lea ebx, [r12 + 1]
.mark_internal:
    cmp ebx, r13d
    jae .mark_done
    imul eax, ebx, IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    movzx eax, byte [r15]
    cmp al, IR_LABEL
    jne .mark_next
    mov rax, [r15 + 8]
    cmp rax, 256
    jae .fail
    mov byte [prom_internal + rax], 1
.mark_next:
    inc ebx
    jmp .mark_internal
.mark_done:

    ; Every JMP/JCC inside [h, j] must target L0, L1, or an internal label
    mov ebx, r12d
.chk_jumps:
    cmp ebx, r13d
    jae .chk_jumps_done
    imul eax, ebx, IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    movzx eax, byte [r15]
    cmp al, IR_JMP
    je .chk_tgt
    cmp al, IR_JCC
    je .chk_tgt
    jmp .chk_jumps_next
.chk_tgt:
    mov rax, [r15 + 8]
    cmp rax, 256
    jae .fail
    cmp eax, [prom_l0]
    je .chk_jumps_next
    cmp eax, [prom_l1]
    je .chk_jumps_next
    cmp byte [prom_internal + rax], 1
    jne .fail
.chk_jumps_next:
    inc ebx
    jmp .chk_jumps
.chk_jumps_done:

    ; No JMP/JCC outside [h, j] may target L0, L1, or an internal label
    xor ebx, ebx
.chk_outside:
    cmp ebx, [ir_count]
    jae .chk_outside_done
    cmp ebx, r12d
    jb .chk_outside_scan
    cmp ebx, r13d
    jbe .chk_outside_next        ; inside region — skip
.chk_outside_scan:
    imul eax, ebx, IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    movzx eax, byte [r15]
    cmp al, IR_JMP
    je .chk_out_tgt
    cmp al, IR_JCC
    je .chk_out_tgt
    jmp .chk_outside_next
.chk_out_tgt:
    mov rax, [r15 + 8]
    cmp rax, 256
    jae .chk_outside_next
    cmp eax, [prom_l0]
    je .fail
    cmp eax, [prom_l1]
    je .fail
    cmp byte [prom_internal + rax], 1
    je .fail
.chk_outside_next:
    inc ebx
    jmp .chk_outside
.chk_outside_done:

    ; Collect distinct symbol offsets accessed inside (h, j)
    mov dword [prom_sym_cnt], 0
    lea ebx, [r12 + 1]
.collect:
    cmp ebx, r13d
    jae .collect_done
    imul eax, ebx, IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    movzx eax, byte [r15]
    cmp al, IR_LOAD_VAR
    je .collect_off
    cmp al, IR_STORE_VAR
    je .collect_off
    jmp .collect_next
.collect_off:
    mov rax, [r15 + 8]
    ; i_sym/end_sym get dedicated vregs (v_iv/v_end) and are handled
    ; separately — skip them here.
    cmp rax, [prom_off_a]
    je .collect_next
    cmp rax, [prom_off_b]
    je .collect_next
    mov ecx, [prom_sym_cnt]
    xor edx, edx
.collect_find:
    cmp edx, ecx
    jae .collect_add
    cmp rax, [prom_sym_off + rdx * 8]
    je .collect_next
    inc edx
    jmp .collect_find
.collect_add:
    cmp ecx, 32
    jae .fail
    mov [prom_sym_off + rcx * 8], rax
    inc dword [prom_sym_cnt]
.collect_next:
    inc ebx
    jmp .collect
.collect_done:

    ; Remove symbols that are LEA'd inside (h, j)
    lea ebx, [r12 + 1]
.lea_scan:
    cmp ebx, r13d
    jae .lea_done
    imul eax, ebx, IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    movzx eax, byte [r15]
    cmp al, IR_LEA_VAR
    jne .lea_next
    mov rax, [r15 + 8]
    call prom_remove_sym
.lea_next:
    inc ebx
    jmp .lea_scan
.lea_done:

    ; Remove symbols accessed by any nested loop inside (h, j)
    lea ebx, [r12 + 1]
.nest_scan:
    cmp ebx, r13d
    jae .nest_done
    imul eax, ebx, IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    movzx eax, byte [r15]
    cmp al, IR_JMP
    jne .nest_next
    mov rax, [r15 + 8]
    cmp rax, 256
    jae .nest_next
    mov eax, [opt_label_index + rax * 4]
    cmp eax, 0xFFFFFFFF
    je .nest_next
    cmp eax, r12d
    jbe .nest_next
    cmp eax, ebx
    jae .nest_next
    mov [nest_h2], eax
    mov [nest_j2], ebx
    ; A nested loop that was already promoted has its original header loads
    ; NOPed ([h2+1]/[h2+2] are IR_NOP) and its symbol accesses moved outside
    ; this region (hoisted header loads, post-loop write-backs), so
    ; prom_nested_conflict cannot see or exclude them. Promoting this outer
    ; loop would then hoist and corrupt the inner loop's symbols — abort.
    mov edx, [nest_h2]
    add edx, 1
    imul eax, edx, IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    movzx eax, byte [r15]
    test al, al
    jz .nested_promoted
    mov edx, [nest_h2]
    add edx, 2
    imul eax, edx, IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    movzx eax, byte [r15]
    test al, al
    jnz .nested_unpromoted
.nested_promoted:
    mov byte [prom_debug], 0x30
    jmp .fail
.nested_unpromoted:
    call prom_nested_conflict
.nest_next:
    inc ebx
    jmp .nest_scan
.nest_done:

    ; Sanity: header symbols must differ from every collected symbol
    ; (guaranteed by the collect-skip above, but double-check)
    mov eax, [prom_sym_cnt]
    xor edx, edx
.sym_no_clash:
    cmp edx, eax
    jae .sym_no_clash_done
    mov rcx, [prom_sym_off + rdx * 8]
    cmp rcx, [prom_off_a]
    je .fail
    cmp rcx, [prom_off_b]
    je .fail
    inc edx
    jmp .sym_no_clash
.sym_no_clash_done:

    ; Collect loop-invariant LOAD_IMMs from the body (original coords h+5..j-1).
    ; Temp vregs are globally unique (monotonic alloc_vreg), so a body LOAD_IMM
    ; dst is never redefined — hoisting its def before L0 is always safe.
    mov dword [prom_hoist_cnt], 0
    lea ebx, [r12 + 5]
.hist_loop:
    cmp ebx, r13d
    jae .hist_done
    imul eax, ebx, IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    movzx eax, byte [r15]
    cmp al, IR_LOAD_IMM
    jne .hist_next
    mov ecx, [prom_hoist_cnt]
    cmp ecx, 64
    jae .hist_done
    mov [prom_hoist_idx + rcx * 2], bx
    movzx eax, byte [r15 + 1]
    mov [prom_hoist_typ + rcx], al
    movzx eax, word [r15 + 2]
    mov [prom_hoist_dst + rcx * 2], ax
    mov rax, [r15 + 8]
    mov [prom_hoist_imm + rcx * 8], rax
    inc dword [prom_hoist_cnt]
.hist_next:
    inc ebx
    jmp .hist_loop
.hist_done:

    ; Precise capacity check: inserts = N + H (header) + (2 + sym_cnt) (write-backs)
    mov eax, [prom_hoist_cnt]
    mov ecx, [prom_sym_cnt]
    add ecx, 2
    lea eax, [eax + ecx * 2]
    add eax, 4                      ; safety margin
    add eax, [ir_count]
    cmp eax, IR_MAX_RECORDS
    ja .fail

    mov byte [prom_debug], 3

    ; ----------------------------------------------------------
    ; Rewrite
    ; ----------------------------------------------------------
    imul eax, r12d, IR_RECORD_SIZE
    mov [prom_h_bytes], rax
    mov eax, [prom_sym_cnt]
    add eax, 2
    add eax, [prom_hoist_cnt]
    mov [prom_shift], eax           ; N+H = 2 + sym_cnt + hoisted
    mov rax, [prom_h_bytes]         ; h * 32
    mov edx, [prom_shift]
    imul edx, edx, IR_RECORD_SIZE   ; (N+H) * 32
    movsxd rdx, edx
    add rax, rdx
    mov [prom_hs_bytes], rax        ; (h + N + H) * 32

    ; Allocate dedicated vregs
    call alloc_vreg
    mov [prom_v_iv], ax
    call alloc_vreg
    mov [prom_v_end], ax
    mov ecx, [prom_sym_cnt]
    xor edx, edx
.alloc_sym:
    cmp edx, ecx
    jae .alloc_done
    call alloc_vreg
    mov [prom_sym_vr + rdx * 2], ax
    inc edx
    jmp .alloc_sym
.alloc_done:

    ; Mark promoted vregs force-callee (only those the allocator tracks)
    movzx eax, word [prom_v_iv]
    cmp eax, LP_VMAX
    jae .fc1_skip
    mov byte [gc_force_callee + rax], 1
.fc1_skip:
    movzx eax, word [prom_v_end]
    cmp eax, LP_VMAX
    jae .fc2_skip
    mov byte [gc_force_callee + rax], 1
.fc2_skip:
    mov ecx, [prom_sym_cnt]
    xor edx, edx
.fc_sym:
    cmp edx, ecx
    jae .fc_done
    movzx eax, word [prom_sym_vr + rdx * 2]
    cmp eax, LP_VMAX
    jae .fc_sym_next
    mov byte [gc_force_callee + rax], 1
.fc_sym_next:
    inc edx
    jmp .fc_sym
.fc_done:

    ; Insert N records (pre-loop loads) at index h
    mov eax, [ir_count]
    sub eax, r12d
    imul eax, eax, IR_RECORD_SIZE
    mov [mb_bytes], eax
    mov rax, [prom_h_bytes]
    lea rdi, [rel ir_buffer]
    mov rsi, rdi
    add rsi, rax
    add rdi, rax
    mov eax, [prom_shift]
    imul eax, eax, IR_RECORD_SIZE
    add rdi, rax
    mov ecx, [mb_bytes]
.ins_back:
    test ecx, ecx
    jz .ins_back_done
    dec ecx
    mov al, [rsi + rcx]
    mov [rdi + rcx], al
    jmp .ins_back
.ins_back_done:
    ; write LOAD_VAR i -> v_iv at [h]
    mov rax, [prom_h_bytes]
    lea r15, [ir_buffer + rax]
    mov byte [r15], IR_LOAD_VAR
    mov byte [r15 + 1], TYPE_INT
    movzx eax, word [prom_v_iv]
    mov [r15 + 2], ax
    mov word [r15 + 4], 0
    mov word [r15 + 6], 0
    mov rax, [prom_i_sym]
    mov [r15 + 8], rax
    mov qword [r15 + 16], 0
    mov dword [r15 + 24], 0
    mov dword [r15 + 28], 0
    ; write LOAD_VAR end -> v_end at [h+1]
    add r15, IR_RECORD_SIZE
    mov byte [r15], IR_LOAD_VAR
    mov byte [r15 + 1], TYPE_INT
    movzx eax, word [prom_v_end]
    mov [r15 + 2], ax
    mov word [r15 + 4], 0
    mov word [r15 + 6], 0
    mov rax, [prom_end_sym]
    mov [r15 + 8], rax
    mov qword [r15 + 16], 0
    mov dword [r15 + 24], 0
    mov dword [r15 + 28], 0
    ; write LOAD_VAR sym[k] -> prom_sym_vr[k] at [h+2+k]
    mov ecx, [prom_sym_cnt]
    xor edx, edx
.ins_sym:
    cmp edx, ecx
    jae .ins_sym_done
    add r15, IR_RECORD_SIZE
    mov byte [r15], IR_LOAD_VAR
    mov byte [r15 + 1], TYPE_INT
    movzx eax, word [prom_sym_vr + rdx * 2]
    mov [r15 + 2], ax
    mov word [r15 + 4], 0
    mov word [r15 + 6], 0
    mov rax, [prom_sym_off + rdx * 8]
    mov [r15 + 8], rax
    mov qword [r15 + 16], 0
    mov dword [r15 + 24], 0
    mov dword [r15 + 28], 0
    inc edx
    jmp .ins_sym
.ins_sym_done:
    ; write hoisted LOAD_IMMs at [h+N .. h+N+H-1] (r15 now at h+N-1)
    mov ecx, [prom_hoist_cnt]
    xor edx, edx
.ins_hoist:
    cmp edx, ecx
    jae .ins_hoist_done
    add r15, IR_RECORD_SIZE
    mov byte [r15], IR_LOAD_IMM
    mov al, [prom_hoist_typ + rdx]
    mov [r15 + 1], al
    movzx eax, word [prom_hoist_dst + rdx * 2]
    mov [r15 + 2], ax
    mov word [r15 + 4], 0
    mov word [r15 + 6], 0
    mov rax, [prom_hoist_imm + rdx * 8]
    mov [r15 + 8], rax
    mov qword [r15 + 16], 0
    mov dword [r15 + 24], 0
    mov dword [r15 + 28], 0
    inc edx
    jmp .ins_hoist
.ins_hoist_done:
    mov eax, [prom_shift]
    add [ir_count], eax

    ; NOP out the old in-loop header loads (now at h+N+1, h+N+2)
    mov rax, [prom_hs_bytes]
    lea r15, [ir_buffer + rax]
    add r15, IR_RECORD_SIZE
    mov byte [r15], IR_NOP
    add r15, IR_RECORD_SIZE
    mov byte [r15], IR_NOP

    ; Rewrite CMP srcs (now at h+N+3): map iv-load dst → v_iv, end-load dst → v_end
    mov rax, [prom_hs_bytes]
    add rax, 3 * IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    movzx eax, word [r15 + 4]
    cmp ax, [prom_iv_dst]
    jne .src1_is_end
    movzx eax, word [prom_v_iv]
    mov [r15 + 4], ax
    jmp .src2_set
.src1_is_end:
    movzx eax, word [prom_v_end]
    mov [r15 + 4], ax
.src2_set:
    movzx eax, word [r15 + 6]
    cmp ax, [prom_iv_dst]
    jne .src2_is_end
    movzx eax, word [prom_v_iv]
    mov [r15 + 6], ax
    jmp .cmp_done
.src2_is_end:
    movzx eax, word [prom_v_end]
    mov [r15 + 6], ax
.cmp_done:

    ; ------------------------------------------------------------------
    ; Rewrite in-loop LOAD_VAR / STORE_VAR of promoted symbols in place.
    ; Reads are redirected to the promoted vreg; stores become in-place
    ; (RMW) updates of the promoted vreg or register copies.
    ; (body now spans h+N+5 .. j+N-1)
    ; ------------------------------------------------------------------
    mov dword [prom_rd_cnt], 0

    mov edi, [prom_shift]
    add edi, r12d
    add edi, 5                  ; edi = body start index
    mov esi, [prom_shift]
    add esi, r13d
    sub esi, 1                  ; esi = body end index
    mov [prom_span_beg], edi
    mov [prom_span_end], esi

    mov ebx, edi                ; current body index
.rew_loop:
    cmp ebx, esi
    ja .rew_done
    imul eax, ebx, IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    movzx eax, byte [r15]
    cmp al, IR_LOAD_VAR
    je .rew_load
    cmp al, IR_STORE_VAR
    je .rew_store
    jmp .rew_redirect           ; generic: redirect src1/src2 reads

.rew_load:
    ; promoted symbol load? register the read (vR -> vS) for redirection
    mov rax, [r15 + 8]
    call prom_sym_vreg
    test ax, ax
    jz .rew_next                ; non-promoted load: leave untouched
    mov ecx, [prom_rd_cnt]
    cmp ecx, 127
    jae .rew_next
    movzx edx, word [r15 + 2]   ; vR
    mov [prom_rd_vr + rcx * 2], dx
    mov [prom_rd_sym + rcx * 2], ax   ; vS
    inc dword [prom_rd_cnt]
    jmp .rew_next

.rew_store:
    mov rax, [r15 + 8]
    call prom_sym_vreg
    test ax, ax
    jz .rew_store_nonprom       ; store to non-promoted symbol
    mov [prom_store_vreg], ax   ; vS
    movzx ecx, word [r15 + 4]   ; vW = store src vreg
    ; find producer: nearest record below ebx (within span) with dst == vW
    mov eax, ebx
    dec eax
    xor edx, edx                ; producer index (0 = none)
.prod_scan:
    cmp eax, edi
    jb .prod_scan_done
    imul r8d, eax, IR_RECORD_SIZE
    lea r9, [ir_buffer + r8]
    movzx r8d, byte [r9]
    test r8d, r8d
    jz .prod_scan_next          ; skip NOP records
    movzx r8d, word [r9 + 2]
    cmp r8d, ecx
    je .prod_scan_found
.prod_scan_next:
    dec eax
    jmp .prod_scan
.prod_scan_found:
    mov edx, eax
.prod_scan_done:
    test edx, edx
    jz .rew_store_copy          ; no producer in span -> copy mode
    ; single-use check: vW must not be used by any other record in the span
    mov eax, ecx
    call prom_span_ref          ; args: ax=vW, edi=start, esi=end, ebx=skip
    test al, al
    jnz .rew_store_copy         ; used elsewhere -> copy mode
    ; RMW mode: retarget producer (index edx) dst -> vS
    imul eax, edx, IR_RECORD_SIZE
    lea r9, [ir_buffer + rax]
    movzx eax, byte [r9]
    cmp al, IR_LOAD_VAR
    je .prod_is_load
    ; ordinary computation op: just retarget dst
    movzx ecx, word [prom_store_vreg]
    mov [r9 + 2], cx
    jmp .rew_store_nop
.prod_is_load:
    ; producer is a LOAD_VAR: value comes from that symbol
    mov rax, [r9 + 8]
    call prom_sym_vreg
    test ax, ax
    jz .prod_load_nonprom
    ; load of a promoted symbol X: MOV vS <- vX
    mov byte [r9], IR_MOV
    movzx ecx, word [prom_store_vreg]
    mov [r9 + 2], cx
    mov [r9 + 4], ax            ; src1 = vX
    mov word [r9 + 6], 0
    mov qword [r9 + 8], 0
    mov qword [r9 + 16], 0
    jmp .rew_store_nop
.prod_load_nonprom:
    ; load of a non-promoted symbol: keep the load, retarget dst -> vS
    movzx ecx, word [prom_store_vreg]
    mov [r9 + 2], cx
    jmp .rew_store_nop
.rew_store_nop:
    mov byte [r15], IR_NOP
    jmp .rew_next
.rew_store_copy:
    ; convert STORE -> MOV vS <- src, where src is vW (or its promoted
    ; source vX when vW is a registered promoted read)
    movzx eax, word [r15 + 4]
    call prom_read_sym
    test ax, ax
    jz .copy_src_vw
    jmp .copy_emit
.copy_src_vw:
    movzx eax, word [r15 + 4]
.copy_emit:
    mov byte [r15], IR_MOV
    movzx ecx, word [prom_store_vreg]
    mov [r15 + 2], cx
    mov [r15 + 4], ax           ; src1
    mov word [r15 + 6], 0
    mov qword [r15 + 8], 0
    mov qword [r15 + 16], 0
    jmp .rew_next
.rew_store_nonprom:
    ; store to a non-promoted symbol: redirect src1 if it is a promoted read
    movzx eax, word [r15 + 4]
    call prom_read_sym
    test ax, ax
    jz .rew_next
    mov [r15 + 4], ax
    jmp .rew_next

.rew_redirect:
    ; generic record: redirect src1/src2 operands that are promoted reads
    movzx eax, word [r15 + 4]
    call prom_read_sym
    test ax, ax
    jz .rd_s2
    mov [r15 + 4], ax
.rd_s2:
    movzx eax, word [r15 + 6]
    call prom_read_sym
    test ax, ax
    jz .rew_next
    mov [r15 + 6], ax
    jmp .rew_next
.rew_next:
    inc ebx
    jmp .rew_loop
.rew_done:

    ; NOP any remaining promoted LOAD_VAR whose dst is no longer referenced
    mov ebx, edi
.clean_loop:
    cmp ebx, esi
    ja .clean_done
    imul eax, ebx, IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    movzx eax, byte [r15]
    cmp al, IR_LOAD_VAR
    jne .clean_next
    mov rax, [r15 + 8]
    call prom_sym_vreg
    test ax, ax
    jz .clean_next
    movzx eax, word [r15 + 2]
    mov ecx, ebx
    push rbx
    mov ebx, ecx
    call prom_span_ref
    pop rbx
    test al, al
    jnz .clean_next
    mov byte [r15], IR_NOP
.clean_next:
    inc ebx
    jmp .clean_loop
.clean_done:

    ; NOP the in-body copies of hoisted LOAD_IMMs (positions shifted by N+H)
    mov ecx, [prom_hoist_cnt]
    xor edx, edx
.hist_nop:
    cmp edx, ecx
    jae .hist_nop_done
    movzx eax, word [prom_hoist_idx + rdx * 2]
    add eax, [prom_shift]
    imul eax, eax, IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    ; The RMW rewrite may have retargeted this LOAD_IMM's dst to a promoted
    ; vreg (in-loop const mutation, e.g. `:b = 7`). Such a record must stay
    ; live — only pure hoist copies (dst unchanged) become NOPs.
    movzx eax, word [r15 + 2]
    movzx ebx, word [prom_hoist_dst + rdx * 2]
    cmp ax, bx
    jne .hist_nop_next
    mov byte [r15], IR_NOP
.hist_nop_next:
    inc edx
    jmp .hist_nop
.hist_nop_done:

    ; Insert write-back STORE_VARs after L1 (L1 at j+N+H+1, insert at j+N+H+2)
    mov eax, [prom_shift]
    add eax, r13d
    add eax, 2
    imul eax, eax, IR_RECORD_SIZE
    mov [mb_idx_bytes], rax
    mov eax, [ir_count]
    sub eax, r13d
    sub eax, [prom_shift]
    sub eax, 2
    imul eax, eax, IR_RECORD_SIZE
    mov [mb_bytes], eax
    mov eax, [prom_sym_cnt]
    add eax, 2
    imul eax, eax, IR_RECORD_SIZE
    mov [mb_wb_bytes], eax
    lea rdi, [rel ir_buffer]
    mov rsi, rdi
    add rsi, [mb_idx_bytes]
    add rdi, [mb_idx_bytes]
    mov ecx, [mb_wb_bytes]      ; 32-bit: mb_wb_bytes is resd
    add rdi, rcx
    mov ecx, [mb_bytes]
.wb_back:
    test ecx, ecx
    jz .wb_back_done
    dec ecx
    mov al, [rsi + rcx]
    mov [rdi + rcx], al
    jmp .wb_back
.wb_back_done:
    ; write STORE_VAR records: v_iv->i_sym, v_end->end_sym, sym[k]
    mov rax, [mb_idx_bytes]
    lea r15, [ir_buffer + rax]
    mov byte [r15], IR_STORE_VAR
    mov byte [r15 + 1], TYPE_INT
    mov word [r15 + 2], 0
    movzx eax, word [prom_v_iv]
    mov [r15 + 4], ax
    mov word [r15 + 6], 0
    mov rax, [prom_i_sym]
    mov [r15 + 8], rax
    mov qword [r15 + 16], 0
    mov dword [r15 + 24], 0
    mov dword [r15 + 28], 0
    add r15, IR_RECORD_SIZE
    mov byte [r15], IR_STORE_VAR
    mov byte [r15 + 1], TYPE_INT
    mov word [r15 + 2], 0
    movzx eax, word [prom_v_end]
    mov [r15 + 4], ax
    mov word [r15 + 6], 0
    mov rax, [prom_end_sym]
    mov [r15 + 8], rax
    mov qword [r15 + 16], 0
    mov dword [r15 + 24], 0
    mov dword [r15 + 28], 0
    add r15, IR_RECORD_SIZE
    mov ecx, [prom_sym_cnt]
    xor edx, edx
.wb_sym:
    cmp edx, ecx
    jae .wb_sym_done
    mov byte [r15], IR_STORE_VAR
    mov byte [r15 + 1], TYPE_INT
    mov word [r15 + 2], 0
    movzx eax, word [prom_sym_vr + rdx * 2]
    mov [r15 + 4], ax
    mov word [r15 + 6], 0
    mov rax, [prom_sym_off + rdx * 8]
    mov [r15 + 8], rax
    mov qword [r15 + 16], 0
    mov dword [r15 + 24], 0
    mov dword [r15 + 28], 0
    add r15, IR_RECORD_SIZE
    inc edx
    jmp .wb_sym
.wb_sym_done:
    mov eax, [prom_sym_cnt]
    add eax, 2
    add [ir_count], eax
.wb_done:

    mov byte [prom_debug], 4
    mov eax, 1
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.fail:
    xor eax, eax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret


; prom_sym_vreg(offset in rax) → ax = dedicated vreg, or 0 if not promoted
prom_sym_vreg:
    cmp rax, [prom_i_sym]
    je .iv
    cmp rax, [prom_end_sym]
    je .end
    mov ecx, [prom_sym_cnt]
    xor edx, edx
.loop:
    cmp edx, ecx
    jae .no
    cmp rax, [prom_sym_off + rdx * 8]
    je .found
    inc edx
    jmp .loop
.found:
    mov ax, [prom_sym_vr + rdx * 2]
    ret
.iv:
    mov ax, [prom_v_iv]
    ret
.end:
    mov ax, [prom_v_end]
    ret
.no:
    xor eax, eax
    ret


; prom_read_sym(vR in ax) → ax = promoted vreg vS, or 0 if vR is not a
; registered body read of a promoted symbol (i.e. vR is the dst of an in-loop
; LOAD_VAR that we are redirecting to the promoted vreg).
prom_read_sym:
    push rbx
    movzx ebx, ax              ; vR
    mov ecx, [prom_rd_cnt]
    xor edx, edx
.loop:
    cmp edx, ecx
    jae .no
    movzx eax, word [prom_rd_vr + rdx * 2]
    cmp eax, ebx
    je .found
    inc edx
    jmp .loop
.found:
    mov ax, [prom_rd_sym + rdx * 2]
    pop rbx
    ret
.no:
    xor eax, eax
    pop rbx
    ret

; prom_span_ref(vreg in ax, start idx in edi, end idx in esi, skip idx in ebx)
; → al = 1 if any non-NOP record in [start,end] (except the skip index) uses
; vreg as src1/src2; else al = 0. Preserves all non-argument registers.
prom_span_ref:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    movzx ecx, ax              ; vreg to search for
    mov r8d, edi               ; loop index
    mov r9d, esi               ; end index
.loop:
    cmp r8d, r9d
    ja .not_used
    cmp r8d, ebx
    je .next                    ; skip the excluded record
    imul eax, r8d, IR_RECORD_SIZE
    lea rdx, [ir_buffer + rax]
    movzx eax, byte [rdx]
    test al, al
    jz .next                    ; skip NOP records
    movzx eax, word [rdx + 4]
    cmp eax, ecx
    je .used
    movzx eax, word [rdx + 6]
    cmp eax, ecx
    je .used
.next:
    inc r8d
    jmp .loop
.used:
    mov al, 1
    jmp .done
.not_used:
    xor eax, eax
.done:
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret


; prom_has_sym(offset in rax) → al = 1 if in list
prom_has_sym:
    mov ecx, [prom_sym_cnt]
    xor edx, edx
.loop:
    cmp edx, ecx
    jae .no
    cmp rax, [prom_sym_off + rdx * 8]
    je .yes
    inc edx
    jmp .loop
.yes:
    mov al, 1
    ret
.no:
    xor eax, eax
    ret


; prom_remove_sym(offset in rax): remove offset from list if present
prom_remove_sym:
    mov ecx, [prom_sym_cnt]
    test ecx, ecx
    jz .done
    xor edx, edx
.loop:
    cmp edx, ecx
    jae .done
    cmp rax, [prom_sym_off + rdx * 8]
    je .found
    inc edx
    jmp .loop
.found:
    ; shift entries [edx+1 .. cnt) down by one
    lea rsi, [prom_sym_off + rdx * 8 + 8]
    lea rdi, [prom_sym_off + rdx * 8]
    mov eax, ecx
    sub eax, edx
    dec eax
    test eax, eax
    jz .done_shift
    imul ecx, eax, 8
.shift_loop:
    test ecx, ecx
    jz .done_shift
    dec ecx
    mov al, [rsi + rcx]
    mov [rdi + rcx], al
    jmp .shift_loop
.done_shift:
    dec dword [prom_sym_cnt]
.done:
    ret


; prom_nested_conflict: nested loop [nest_h2, nest_j2]; remove any
; candidate symbol accessed there
prom_nested_conflict:
    mov ebx, [nest_h2]
.conflict_loop:
    cmp ebx, [nest_j2]
    jae .done
    imul eax, ebx, IR_RECORD_SIZE
    lea r15, [ir_buffer + rax]
    movzx eax, byte [r15]
    cmp al, IR_LOAD_VAR
    je .conflict_off
    cmp al, IR_STORE_VAR
    je .conflict_off
    jmp .conflict_next
.conflict_off:
    mov rax, [r15 + 8]
    push rbx
    call prom_remove_sym
    pop rbx
.conflict_next:
    inc ebx
    jmp .conflict_loop
.done:
    ret


; ============================================================
;  Helper: has_branching_ir
;  Scans IR buffer for IR_JCC, IR_JMP, or IR_LABEL opcodes.
;  Returns rax = 1 if branching IR found, 0 otherwise.
; ============================================================
has_branching_ir:
    mov ecx, [ir_count]
    test ecx, ecx
    jz .no_branches
    xor edx, edx            ; index = 0
.scan:
    imul eax, edx, IR_RECORD_SIZE
    movzx eax, byte [ir_buffer + rax]
    cmp eax, IR_JCC
    je .found
    cmp eax, IR_JMP
    je .found
    cmp eax, IR_LABEL
    je .found
    cmp eax, IR_CALL
    je .found
    cmp eax, IR_CALL_ARG
    je .found
    cmp eax, IR_PROTO_BEGIN
    je .found
    cmp eax, IR_SAVE_ARG
    je .found
    cmp eax, IR_SAVE_LOCAL_VAR
    je .found
    cmp eax, IR_RESTORE_LOCAL_VAR
    je .found
    cmp eax, IR_WHEN
    je .found
    cmp eax, IR_ABORT
    je .found
    inc edx
    cmp edx, ecx
    jb .scan
.no_branches:
    xor eax, eax
    ret
.found:
    mov eax, 1
    ret
