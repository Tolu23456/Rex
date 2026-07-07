; ============================================================
; irgen/ir_emit_x86.asm — x86 emission pass
; Reads IR records from ir_buffer, produces x86-64 machine code
; in out_buffer.
; ============================================================
bits 64
default rel

%include "rex_defs.inc"
%include "rex_ir.inc"

; ---- externs ----
extern emit_b, emit_d, emit_q
extern ir_buffer, ir_idx
extern proto_table
extern out_idx
extern out_buffer
extern vreg_phys

; ---- register cache for hot variables ----
section .bss
global ir_cache_var, ir_cache_cnt, ir_cache_reg
ir_cache_var:   resq 4      ; var_idx cached in each slot (-1 = none)
ir_cache_reg:   resb 4      ; register code for each slot
ir_cache_cnt:   resq 1      ; number of active caches

section .data
ir_cache_regmap: db 15, 14, 13, 12

; ============================================================
; Register ID → x86 register code mapping
; My IDs: rax=0, rbx=1, rcx=2, rdx=3, rsi=4, rdi=5,
;         r8=6, r9=7, r10=8, r11=9, r12=10, r13=11, r14=12, r15=13
; x86 codes: rax=0, rcx=1, rdx=2, rbx=3, rsi=6, rdi=7,
;            r8=8, r9=9, r10=10, r11=11, r12=12, r13=13, r14=14, r15=15
; ============================================================
reg_to_x86:
    db 0, 3, 1, 2, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15

section .text

; ============================================================
; check_vreg_phys — look up physical register for a vreg
; Input:  eax = vreg ID
; Output: eax = physical register ID (0–13), or -1 if spilled/unknown
; Clobbers: rcx
; ============================================================
check_vreg_phys:
    test    ax, ax
    jz      .not_assigned
    cmp     eax, 256
    jae     .not_assigned
    movzx   eax, word [vreg_phys + rax*2]
    cmp     ax, 0xFF
    je      .not_assigned
    ret
.not_assigned:
    mov     eax, -1
    ret

; ============================================================
; emit_rex_modrm — emit REX prefix + opcode + ModRM for reg-reg op
; Input:  cl = REX byte, dl = opcode, sil = modrm byte
; ============================================================
emit_rex_modrm:
    mov     al, cl
    call    emit_b
    mov     al, dl
    call    emit_b
    mov     al, sil
    call    emit_b
    ret

section .bss
emit_label_offs: resd LABEL_MAX

section .text

global ir_emit_x86

; ============================================================
; ir_emit_x86 — main entry point
; Two-pass: pass 1 records label/proto positions, pass 2 emits.
; ============================================================
ir_emit_x86:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r15, [ir_idx]
    test    r15, r15
    jz      .done

    ; ===== Pass 1: record label positions & proto starts =====
    mov     qword [out_idx], CODE_START
    xor     r12, r12

.p1:
    cmp     r12, r15
    jge     .p1_done

    mov     rax, r12
    shl     rax, 5
    lea     r13, [ir_buffer + rax]

    movzx   eax, byte [r13 + IR_OFF_OPCODE]

    cmp     al, IR_LABEL
    je      .p1_label
    cmp     al, IR_PROTO_BEGIN
    je      .p1_proto

    call    .est_x86_size
    inc     r12
    jmp     .p1

.p1_label:
    movzx   eax, word [r13 + IR_OFF_IMM]
    mov     ecx, [out_idx]
    mov     [emit_label_offs + rax*4], ecx
    inc     r12
    jmp     .p1

.p1_proto:
    movzx   eax, word [r13 + IR_OFF_IMM]
    imul    rax, PROTO_ENTRY_SIZE
    mov     rcx, [out_idx]
    mov     [proto_table + rax + PROTO_OUTIDX_OFF], rcx
    inc     r12
    jmp     .p1

.p1_done:
    ; ===== Pass 1b: Detect loops and cache variables =====
    ; Scan for backward jumps, identify CMP variables, cache them
    xor     r12, r12

.p1b_loop:
    cmp     r12, r15
    jge     .p1b_done

    mov     rax, r12
    shl     rax, 5
    lea     r13, [ir_buffer + rax]

    movzx   eax, byte [r13 + IR_OFF_OPCODE]

    ; Check for IR_JMP, IR_JMP_TRUE, IR_JMP_FALSE (backward jump = loop)
    cmp     al, IR_JMP
    je      .p1b_check_jump
    cmp     al, IR_JMP_TRUE
    je      .p1b_check_jump
    cmp     al, IR_JMP_FALSE
    je      .p1b_check_jump
    inc     r12
    jmp     .p1b_loop

.p1b_check_jump:
    ; Get target label
    movzx   ecx, word [r13 + IR_OFF_IMM]
    ; Search backward for that label
    xor     edx, edx
.p1b_find_label:
    cmp     edx, r12d
    jge     .p1b_not_backward
    mov     rax, rdx
    shl     rax, 5
    lea     rsi, [ir_buffer]
    add     rsi, rax
    cmp     byte [rsi], IR_LABEL
    jne     .p1b_find_label_next
    movzx   edi, word [rsi + IR_OFF_IMM]
    cmp     di, cx
    je      .p1b_backward_found
.p1b_find_label_next:
    inc     edx
    jmp     .p1b_find_label

.p1b_backward_found:
    ; Save label position in r11 (before it gets clobbered)
    mov     r11d, edx
    ; Backward jump found — scan backward from jump for IR_CMP
    mov     ecx, r12d
    dec     ecx
.p1b_find_cmp:
    cmp     ecx, 0
    jl      .p1b_not_backward
    mov     rax, rcx
    shl     rax, 5
    add     rax, ir_buffer
    cmp     byte [rax], IR_CMP
    je      .p1b_cmp_found
    dec     ecx
    jmp     .p1b_find_cmp

.p1b_cmp_found:
    ; CMP found — get the variable index from src1
    movzx   edx, word [rax + IR_OFF_SRC1]
    test    dx, dx
    jz      .p1b_not_backward
    cmp     edx, 256
    jge     .p1b_not_backward
    ; Cache CMP variable in slot 0 (r15)
    mov     [ir_cache_var], edx
    mov     byte [ir_cache_reg], 15   ; r15
    mov     qword [ir_cache_cnt], 1

    ; Scan loop body to find the most frequently modified variable
    ; (the accumulator). Count STORE_VAR targets.
    ; Also find any ADD/SUB targeting the same variable as CMP.src1
    xor     esi, esi            ; best_accum_var = 0
    xor     edi, edi            ; best_accum_count = 0
    ; Temporary: count per-variable stores (use stack)
    sub     rsp, 2048           ; count_table[256] = 0
    mov     r8, rsp
    xor     eax, eax
    mov     ecx, 256
    rep stosq                   ; zero 256 qwords

    ; Loop body: from label+1 to jump position
    mov     ecx, edx            ; ecx = label position (from .p1b_find_label)
    inc     ecx
.p1b_count_stores:
    cmp     ecx, r12d
    jge     .p1b_count_done
    mov     rax, rcx
    shl     rax, 5
    add     rax, ir_buffer
    ; Check for IR_STORE_VAR or IR_ADD/IR_SUB targeting a variable
    movzx   edi, byte [rax]
    cmp     dil, IR_STORE_VAR
    je      .p1b_count_store
    cmp     dil, IR_ADD
    je      .p1b_count_add
    cmp     dil, IR_SUB
    je      .p1b_count_add
    cmp     dil, IR_INC
    je      .p1b_count_inc
    cmp     dil, IR_DEC
    je      .p1b_count_inc
    inc     ecx
    jmp     .p1b_count_stores

.p1b_count_inc:
    ; INC/DEC: var_idx is in src1
    movzx   eax, word [rax + IR_OFF_SRC1]
    cmp     eax, 256
    jge     .p1b_count_next
    inc     qword [r8 + rax*8]
    jmp     .p1b_count_next

.p1b_count_store:
    ; STORE_VAR: var_idx is in src1 (not dst which is 0)
    movzx   eax, word [rax + IR_OFF_SRC1]
    cmp     eax, 256
    jge     .p1b_count_next
    inc     qword [r8 + rax*8]
    jmp     .p1b_count_next

.p1b_count_add:
    ; ADD/SUB: dst is the accumulator
    movzx   eax, word [rax + IR_OFF_DST]
    cmp     eax, 256
    jge     .p1b_count_next
    inc     qword [r8 + rax*8]

.p1b_count_next:
    inc     ecx
    jmp     .p1b_count_stores

.p1b_count_done:
    ; Find variable with highest count (excluding CMP variable)
    xor     ecx, ecx
    xor     esi, esi            ; best_var = 0
    xor     edi, edi            ; best_count = 0
.p1b_find_best:
    cmp     ecx, 256
    jge     .p1b_best_found
    mov     rax, [r8 + rcx*8]
    test    rax, rax
    jz      .p1b_find_best_next
    cmp     ecx, edx            ; skip CMP variable
    je      .p1b_find_best_next
    cmp     rax, rdi
    jle     .p1b_find_best_next
    mov     rdi, rax
    mov     esi, ecx            ; best_var = ecx
.p1b_find_best_next:
    inc     ecx
    jmp     .p1b_find_best

.p1b_best_found:
    add     rsp, 2048           ; free count_table
    test    esi, esi
    jz      .p1b_not_backward
    ; Cache accumulator in slot 1 (r14)
    mov     [ir_cache_var + 8], esi
    mov     byte [ir_cache_reg + 1], 14  ; r14
    mov     qword [ir_cache_cnt], 2

.p1b_not_backward:
    inc     r12
    jmp     .p1b_loop

.p1b_done:
    ; Emit cache setup if loop variables were detected
    cmp     qword [ir_cache_cnt], 0
    je      .p1b_no_cache2
    ; Emit: push r15 + push r14 + mov r15, [abs32] + mov r14, [abs32]
    ; push r15 = 41 57
    mov     al, 0x41
    call    emit_b
    mov     al, 0x57
    call    emit_b
    ; push r14 = 41 56
    mov     al, 0x41
    call    emit_b
    mov     al, 0x56
    call    emit_b
    ; mov r15, [abs32] = 4C 8B 3C 25 addr32
    mov     al, 0x4C
    call    emit_b
    mov     al, 0x8B
    call    emit_b
    mov     al, 0x3C
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     rax, [ir_cache_var]
    shl     rax, 6
    add     rax, VAR_STORAGE_BASE
    call    emit_d
    ; mov r14, [abs32] = 4C 8B 34 25 addr32
    cmp     qword [ir_cache_cnt], 1
    jle     .p1b_no_cache2
    mov     al, 0x4C
    call    emit_b
    mov     al, 0x8B
    call    emit_b
    mov     al, 0x34
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     rax, [ir_cache_var + 8]
    shl     rax, 6
    add     rax, VAR_STORAGE_BASE
    call    emit_d
.p1b_no_cache2:

    ; ===== Pass 2: emit x86 code =====
    ; Pre-scan: detect hot variables by counting INC/DEC/ADD/SUB targets
    mov     qword [ir_cache_cnt], 0
    ; Count modifications per variable using stack (16 qwords = 128 bytes)
    sub     rsp, 128
    xor     eax, eax
    mov     rcx, rsp
    xor     edi, edi
.count_zero:
    cmp     edi, 16
    jge     .count_zero_done
    mov     qword [rcx + rdi*8], 0
    inc     edi
    jmp     .count_zero
.count_zero_done:
    ; Scan IR for INC/DEC/ADD/SUB (these are the hot operations)
    xor     r12, r12
.pre_scan:
    cmp     r12, r15
    jge     .pre_scan_done
    mov     rax, r12
    shl     rax, 5
    add     rax, ir_buffer
    movzx   ecx, byte [rax]
    xor     edx, edx
    cmp     cl, IR_INC
    je      .pre_scan_inc
    cmp     cl, IR_DEC
    je      .pre_scan_inc
    cmp     cl, IR_ADD
    je      .pre_scan_add
    cmp     cl, IR_SUB
    je      .pre_scan_add
    inc     r12
    jmp     .pre_scan
.pre_scan_inc:
    movzx   edx, word [rax + IR_OFF_SRC1]
    jmp     .pre_scan_count
.pre_scan_add:
    movzx   edx, word [rax + IR_OFF_DST]
    jmp     .pre_scan_count
.pre_scan_count:
    cmp     edx, 16
    jge     .pre_scan_next
    inc     qword [rsp + rdx*8]
.pre_scan_next:
    inc     r12
    jmp     .pre_scan

.pre_scan_done:
    add     rsp, 128           ; free pre-scan count buffer

    ; Cache
    test    rsi, rsi
    jz      .p2_start
    mov     [ir_cache_var], rsi
    mov     byte [ir_cache_reg], 15
    mov     qword [ir_cache_cnt], 1
    test    r8, r8
    jz      .p2_emit_cache
    mov     [ir_cache_var + 8], r8
    mov     byte [ir_cache_reg + 1], 14
    mov     qword [ir_cache_cnt], 2

.p2_emit_cache:
    cmp     qword [ir_cache_cnt], 0
    je      .p2_start
    ; push r15 + push r14 + mov r15,[v1] + mov r14,[v2]
    mov     al, 0x41
    call    emit_b
    mov     al, 0x57
    call    emit_b
    mov     al, 0x41
    call    emit_b
    mov     al, 0x56
    call    emit_b
    ; mov r15, [abs32]
    mov     al, 0x4C
    call    emit_b
    mov     al, 0x8B
    call    emit_b
    mov     al, 0x3C
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     rax, [ir_cache_var]
    shl     rax, 6
    add     rax, VAR_STORAGE_BASE
    call    emit_d
    cmp     qword [ir_cache_cnt], 1
    jle     .p2_start
    ; mov r14, [abs32]
    mov     al, 0x4C
    call    emit_b
    mov     al, 0x8B
    call    emit_b
    mov     al, 0x34
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     rax, [ir_cache_var + 8]
    shl     rax, 6
    add     rax, VAR_STORAGE_BASE
    call    emit_d

.p2_start:
    ; ===== Pass 2: emit x86 code =====
    mov     qword [out_idx], CODE_START
    xor     r12, r12

.p2:
    cmp     r12, r15
    jge     .done

    mov     rax, r12
    shl     rax, 5
    lea     r13, [ir_buffer + rax]

    movzx   eax, byte [r13 + IR_OFF_OPCODE]

    cmp     al, IR_NOP
    je      .op_skip
    cmp     al, IR_LABEL
    je      .op_skip
    cmp     al, IR_PROTO_BEGIN
    je      .op_skip
    cmp     al, IR_PROTO_END
    je      .op_skip
    cmp     al, IR_MOV
    je      .op_skip
    cmp     al, IR_LOAD_IMM
    je      .op_load_imm
    cmp     al, IR_LOAD_VAR
    je      .op_load_var
    cmp     al, IR_LOAD_BOOL
    je      .op_load_imm
    cmp     al, IR_LOAD_STRING
    je      .op_load_imm
    cmp     al, IR_LOAD_NULL
    je      .op_load_null
    cmp     al, IR_STORE_VAR
    je      .op_store_var
    cmp     al, IR_ADD
    je      .op_add
    cmp     al, IR_SUB
    je      .op_sub
    cmp     al, IR_MUL
    je      .op_mul
    cmp     al, IR_DIV
    je      .op_div
    cmp     al, IR_MOD
    je      .op_mod
    cmp     al, IR_NEG
    je      .op_neg
    cmp     al, IR_CMP
    je      .op_cmp
    cmp     al, IR_LAND
    je      .op_land
    cmp     al, IR_LOR
    je      .op_lor
    cmp     al, IR_LNOT
    je      .op_lnot
    cmp     al, IR_JMP
    je      .op_jmp
    cmp     al, IR_JMP_TRUE
    je      .op_jmp_true
    cmp     al, IR_JMP_FALSE
    je      .op_jmp_false
    cmp     al, IR_JMP_CMP
    je      .op_jmp_cmp
    cmp     al, IR_CALL
    je      .op_call
    cmp     al, IR_RET
    je      .op_ret
    cmp     al, IR_OUTPUT
    je      .op_output
    cmp     al, IR_OUTPUT_STR
    je      .op_output_str
    cmp     al, IR_OUTPUT_NL
    je      .op_output_nl
    cmp     al, IR_SWAP
    je      .op_swap
    cmp     al, IR_INC
    je      .op_inc
    cmp     al, IR_DEC
    je      .op_dec
    cmp     al, IR_SEQ_NEW
    je      .op_seq_new
    cmp     al, IR_SEQ_PUSH
    je      .op_seq_push
    cmp     al, IR_SEQ_POP
    je      .op_seq_pop
    cmp     al, IR_SEQ_LEN
    je      .op_seq_len
    cmp     al, IR_SEQ_GET
    je      .op_seq_get
    cmp     al, IR_SEQ_SET
    je      .op_seq_set
    cmp     al, IR_DICT_NEW
    je      .op_dict_new
    cmp     al, IR_DICT_SET
    je      .op_dict_set
    cmp     al, IR_DICT_GET
    je      .op_dict_get
    cmp     al, IR_ABS
    je      .op_abs
    cmp     al, IR_SIGN
    je      .op_sign
    cmp     al, IR_TEST
    je      .op_test
    cmp     al, IR_RAISE
    je      .op_raise
    cmp     al, IR_RESERVE
    je      .op_reserve
    cmp     al, IR_LEN
    je      .op_len
    cmp     al, IR_CONCAT
    je      .op_concat
    cmp     al, IR_TYPEOF
    je      .op_typeof
    cmp     al, IR_INPUT
    je      .op_input
    cmp     al, IR_ASSERT
    je      .op_assert
    cmp     al, IR_CLOCK
    je      .op_clock
    cmp     al, IR_IDIV
    je      .op_idiv
    cmp     al, IR_LOAD_GLOBAL
    je      .op_load_global
    cmp     al, IR_STORE_GLOBAL
    je      .op_store_global
    cmp     al, IR_TZCNT
    je      .op_tzcnt
    cmp     al, IR_LZCNT
    je      .op_lzcnt
    cmp     al, IR_POPCOUNT
    je      .op_popcnt
    cmp     al, IR_SIMD_LOAD
    je      .op_simd_load
    cmp     al, IR_SIMD_STORE
    je      .op_simd_store
    cmp     al, IR_SIMD_ADD
    je      .op_simd_add
    cmp     al, IR_SIMD_SUB
    je      .op_simd_sub
    cmp     al, 0xA2           ; IR_SIMD_REDUCE_SUM
    je      .op_simd_reduce_sum
    cmp     al, IR_BAND
    je      .op_band
    cmp     al, IR_BOR
    je      .op_bor
    cmp     al, IR_BXOR
    je      .op_bxor
    cmp     al, IR_BNOT
    je      .op_bnot
    cmp     al, IR_BSHL
    je      .op_bshl
    cmp     al, IR_BSHR
    je      .op_bshr
    cmp     al, IR_BSHR_S
    je      .op_bshr_s
    cmp     al, IR_ABS
    je      .op_abs
    cmp     al, IR_SIGN
    je      .op_sign
    cmp     al, IR_LOAD_CHAR
    je      .op_load_imm
    cmp     al, IR_LOAD_BYTE
    je      .op_load_imm
    cmp     al, IR_FADD
    je      .op_fadd
    cmp     al, IR_FSUB
    je      .op_fsub
    cmp     al, IR_FMUL
    je      .op_fmul
    cmp     al, IR_FDIV
    je      .op_fdiv
    cmp     al, IR_FNEG
    je      .op_fneg
    cmp     al, IR_FABS
    je      .op_fabs
    cmp     al, IR_FLOOR
    je      .op_floor
    cmp     al, IR_CEIL
    je      .op_ceil
    cmp     al, IR_ROUND
    je      .op_round
    cmp     al, IR_FSQRT
    je      .op_fsqrt

    ; Unknown opcode: skip
    inc     r12
    jmp     .p2

; ============================================================
; IR_TZCNT: tzcnt rax, rax — F3 48 0F BC C0
; ============================================================
.op_tzcnt:
    mov     al, 0xF3
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0xBC
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    inc     r12
    jmp     .p2

; ============================================================
; IR_LZCNT: lzcnt rax, rax — F3 48 0F BD C0
; ============================================================
.op_lzcnt:
    mov     al, 0xF3
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0xBD
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    inc     r12
    jmp     .p2

; ============================================================
; IR_POPCOUNT: popcnt rax, rax — F3 48 0F B8 C0
; ============================================================
.op_popcnt:
    mov     al, 0xF3
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0xB8
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    inc     r12
    jmp     .p2

; ============================================================
; IR_SIMD_LOAD: movdqu xmm0, [addr]
; F3 0F 6F 04 25 addr32
; Loads 4x32-bit ints from [VAR_STORAGE_BASE + src1*64 + imm]
; ============================================================
.op_simd_load:
    movzx   eax, word [r13 + IR_OFF_SRC1]
    shl     eax, 6
    add     eax, VAR_STORAGE_BASE
    mov     r14d, eax
    mov     al, 0xF3
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x6F
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r14d
    call    emit_d
    inc     r12
    jmp     .p2

; ============================================================
; IR_SIMD_STORE: movdqu [addr], xmm0
; F3 0F 7F 04 25 addr32
; Stores 4x32-bit ints from xmm0 to [VAR_STORAGE_BASE + dst*64 + imm]
; ============================================================
.op_simd_store:
    movzx   eax, word [r13 + IR_OFF_DST]
    shl     eax, 6
    add     eax, VAR_STORAGE_BASE
    mov     r14d, eax
    mov     al, 0xF3
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x7F
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r14d
    call    emit_d
    inc     r12
    jmp     .p2

; ============================================================
; IR_SIMD_ADD: paddd xmm0, xmm1
; 66 0F FE C1
; ============================================================
.op_simd_add:
    mov     al, 0x66
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0xFE
    call    emit_b
    mov     al, 0xC1
    call    emit_b
    inc     r12
    jmp     .p2

; ============================================================
; IR_SIMD_SUB: psubd xmm0, xmm1
; 66 0F FA C1
; ============================================================
.op_simd_sub:
    mov     al, 0x66
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0xFA
    call    emit_b
    mov     al, 0xC1
    call    emit_b
    inc     r12
    jmp     .p2

; ============================================================
; IR_SIMD_REDUCE_SUM: horizontal sum of xmm0 → rax
; pshufd xmm1,xmm0,0x4E; paddd xmm0,xmm1;
; pshufd xmm1,xmm0,0xB1; paddd xmm0,xmm1; movd eax,xmm0
; 5 + 4 + 5 + 4 + 4 = 22 bytes
; ============================================================
.op_simd_reduce_sum:
    ; pshufd xmm1, xmm0, 0x4E = 66 0F 70 C8 4E
    mov     al, 0x66
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x70
    call    emit_b
    mov     al, 0xC8
    call    emit_b
    mov     al, 0x4E
    call    emit_b
    ; paddd xmm0, xmm1 = 66 0F FE C1
    mov     al, 0x66
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0xFE
    call    emit_b
    mov     al, 0xC1
    call    emit_b
    ; pshufd xmm1, xmm0, 0xB1 = 66 0F 70 C8 B1
    mov     al, 0x66
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x70
    call    emit_b
    mov     al, 0xC8
    call    emit_b
    mov     al, 0xB1
    call    emit_b
    ; paddd xmm0, xmm1 = 66 0F FE C1
    mov     al, 0x66
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0xFE
    call    emit_b
    mov     al, 0xC1
    call    emit_b
    ; movd eax, xmm0 = 66 0F 7E C0
    mov     al, 0x66
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x7E
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    inc     r12
    jmp     .p2

; ============================================================
; Skip (label, proto marker, mov, nop)
; ============================================================
.op_skip:
    inc     r12
    jmp     .p2

; ============================================================
; IR_LOAD_IMM / IR_LOAD_BOOL / IR_LOAD_STRING
; mov rax, imm64: 48 B8 <8 bytes>
; With register allocation: mov <phys_reg>, imm64
; ============================================================
.op_load_imm:
    mov     rdi, [r13 + IR_OFF_IMM]

    ; Check if dst has a physical register assignment
    movzx   eax, word [r13 + IR_OFF_DST]
    call    check_vreg_phys
    cmp     eax, -1
    je      .op_load_imm_stack

    ; Register-based: mov <phys_reg>, imm64
    ; Look up x86 register code
    push    rdi
    lea     rcx, [rel reg_to_x86]
    movzx   edx, byte [rcx + rax]

    ; Build REX prefix: 0x48 | (REX.B if reg >= 8)
    mov     cl, 0x48
    cmp     edx, 8
    jb      .op_load_imm_no_rexb
    or      cl, 0x01
.op_load_imm_no_rexb:
    mov     al, cl
    call    emit_b

    ; Opcode: 0xB8 + (x86_code & 7)
    mov     al, 0xB8
    mov     cl, dl
    and     cl, 7
    or      al, cl
    call    emit_b

    ; 8-byte immediate
    pop     rax
    call    emit_q
    inc     r12
    jmp     .p2

.op_load_imm_stack:
    ; Stack-based: mov rax, imm64
    mov     al, 0x48
    call    emit_b
    mov     al, 0xB8
    call    emit_b
    mov     rax, rdi
    call    emit_q
    inc     r12
    jmp     .p2

; ============================================================
; IR_LOAD_NULL: xor eax, eax (31 C0)
; ============================================================
.op_load_null:
    mov     al, 0x31
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    inc     r12
    jmp     .p2

; ============================================================
; IR_LOAD_VAR: mov rax, [VAR_STORAGE_BASE + var_idx*64]
; 48 8B 04 25 <addr32>
; ============================================================
.op_load_var:
    ; Check register cache first
    movzx   eax, word [r13 + IR_OFF_SRC1]    ; var_idx
    ; Search cache for this var
    xor     ecx, ecx
.cache_search:
    cmp     ecx, 4
    jge     .cache_miss
    cmp     rax, [ir_cache_var + rcx*8]
    je      .cache_hit
    inc     ecx
    jmp     .cache_search
.cache_hit:
    ; Emit: mov rax, reg (3 bytes)
    ; reg code from ir_cache_regmap
    movzx   edx, byte [ir_cache_regmap + rcx]
    ; REX prefix: 0x48 for rax-rdi, 0x4C for r8-r15 (REX.W + REX.R)
    cmp     dl, 8
    jb      .cache_hit_no_rex
    mov     al, 0x4C            ; REX.W + REX.R
    call    emit_b
    mov     al, 0x89            ; mov rax, reg
    call    emit_b
    ; ModRM: mod=11, reg=reg_code-8, rm=0(rax)
    mov     al, 0xC0
    movzx   ecx, dl
    sub     ecx, 8              ; r8=0, r9=1, ..., r15=7
    or      al, cl
    shl     al, 3               ; reg field in bits 5:3
    call    emit_b
    jmp     .op_load_var_done
.cache_hit_no_rex:
    mov     al, 0x48            ; REX.W
    call    emit_b
    mov     al, 0x89            ; mov rax, reg
    call    emit_b
    mov     al, 0xC0
    or      al, dl
    call    emit_b
    jmp     .op_load_var_done

.cache_miss:
    ; Emit: mov rax, [VAR_STORAGE_BASE + var_idx*64]
    movzx   eax, word [r13 + IR_OFF_SRC1]
    shl     eax, 6
    add     eax, VAR_STORAGE_BASE
    mov     r14d, eax
    mov     al, 0x48
    call    emit_b
    mov     al, 0x8B
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r14d
    call    emit_d

.op_load_var_done:
    inc     r12
    jmp     .p2

; ============================================================
; IR_STORE_VAR: mov [VAR_STORAGE_BASE + var_idx*64], rax
; 48 89 04 25 <addr32>
; ============================================================
.op_store_var:
    movzx   eax, word [r13 + IR_OFF_SRC1]    ; var_idx
    ; Check if this variable is cached
    xor     ecx, ecx
.store_cache_search:
    cmp     ecx, 4
    jge     .store_cache_miss
    cmp     rax, [ir_cache_var + rcx*8]
    je      .store_cache_hit
    inc     ecx
    jmp     .store_cache_search
.store_cache_hit:
    ; Emit: mov reg, rax (3 bytes)
    movzx   edx, byte [ir_cache_regmap + rcx]
    cmp     dl, 8
    jb      .store_hit_no_rex
    mov     al, 0x4C            ; REX.W + REX.R
    call    emit_b
    mov     al, 0x89            ; mov reg, rax
    call    emit_b
    ; ModRM: mod=11, reg=0(rax), rm=reg_code-8
    mov     al, 0xC0
    movzx   ecx, dl
    sub     ecx, 8
    or      al, cl              ; rm field in bits 2:0
    call    emit_b
    jmp     .op_store_var_done
.store_hit_no_rex:
    mov     al, 0x48
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0xC0
    or      al, dl
    call    emit_b
    jmp     .op_store_var_done

.store_cache_miss:
    ; Emit: mov [abs32], rax (8 bytes)
    movzx   eax, word [r13 + IR_OFF_SRC1]
    shl     eax, 6
    add     eax, VAR_STORAGE_BASE
    mov     r14d, eax
    mov     al, 0x48
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r14d
    call    emit_d

.op_store_var_done:
    inc     r12
    jmp     .p2

; ============================================================
; IR_ADD: pop rbx; add rax, rbx (5B 48 01 D8)
; With register allocation: add <dst>, <src2>
; ============================================================
.op_add:
    ; Check if all three vregs have physical register assignments
    movzx   eax, word [r13 + IR_OFF_DST]
    call    check_vreg_phys
    cmp     eax, -1
    je      .op_add_stack
    push    rax                 ; save dst phys reg

    movzx   eax, word [r13 + IR_OFF_SRC1]
    call    check_vreg_phys
    cmp     eax, -1
    pop     rcx                 ; rcx = dst phys reg
    je      .op_add_stack
    push    rcx                 ; re-save dst

    movzx   eax, word [r13 + IR_OFF_SRC2]
    call    check_vreg_phys
    cmp     eax, -1
    pop     rcx                 ; rcx = dst phys reg
    je      .op_add_stack

    ; All vregs in physical registers
    ; NOTE: Assumes src1 already lives in dst — missing mov src1→dst must be
    ; emitted when register allocation is enabled (currently disabled: wrappers
    ; zero vreg IDs).  Also, this path emits 3 bytes (REX+op+ModRM) but the
    ; size estimator assumes 4 — must be fixed when register path is enabled.
    ; Emit: add <dst>, <src2>  (assumes src1 already lives in dst)
    ; eax = src2 phys reg, rcx = dst phys reg
    push    rax
    lea     rsi, [rel reg_to_x86]
    movzx   edi, byte [rsi + rcx]   ; edi = dst x86 code
    pop     rax
    movzx   esi, byte [rsi + rax]   ; esi = src2 x86 code

    ; Build REX: 0x48 | REX.R(src2>=8) | REX.B(dst>=8)
    mov     cl, 0x48
    cmp     esi, 8
    jb      .op_add_no_rexr
    or      cl, 0x04
.op_add_no_rexr:
    cmp     edi, 8
    jb      .op_add_no_rexb
    or      cl, 0x01
.op_add_no_rexb:
    ; REX in cl, opcode=0x01
    ; ModRM: mod=11, reg=src2_code, r/m=dst_code
    mov     dl, 0x01           ; opcode ADD r/m64, r64
    mov     al, 0xC0
    mov     r8b, sil
    and     r8b, 7
    shl     r8b, 3
    or      al, r8b
    mov     r8b, dil
    and     r8b, 7
    or      al, r8b
    mov     sil, al            ; sil = modrm
    call    emit_rex_modrm

    inc     r12
    jmp     .p2

.op_add_stack:
    ; Stack-based: pop rbx; add rax, rbx
    mov     al, 0x5B
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x01
    call    emit_b
    mov     al, 0xD8
    call    emit_b
    inc     r12
    jmp     .p2

; ============================================================
; IR_SUB: pop rbx; sub rax,rbx
; 5B 48 29 D8
; ============================================================
.op_sub:
    mov     al, 0x5B
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x29
    call    emit_b
    mov     al, 0xD8
    call    emit_b
    inc     r12
    jmp     .p2

; ============================================================
; IR_MUL: IMUL3 form (src2==0, const in IMM) or stack-based
; ============================================================
.op_mul:
    cmp     word [r13 + IR_OFF_SRC2], 0
    jne     .op_mul_stack
    ; IMUL3 form: imul rax, rax, imm32
    ; 48 69 C0 imm32
    mov     al, 0x48
    call    emit_b
    mov     al, 0x69
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    mov     eax, dword [r13 + IR_OFF_IMM]
    call    emit_d
    inc     r12
    jmp     .p2

.op_mul_stack:
    mov     al, 0x5B
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0xAF
    call    emit_b
    mov     al, 0xC3
    call    emit_b
    inc     r12
    jmp     .p2

; ============================================================
; IR_DIV: pop rbx; cqo; idiv rbx
; 5B 48 99 48 F7 FB
; ============================================================
.op_div:
    mov     al, 0x5B
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x99
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0xF7
    call    emit_b
    mov     al, 0xFB
    call    emit_b
    inc     r12
    jmp     .p2

; ============================================================
; IR_MOD: same as DIV + mov rax,rdx
; 5B 48 99 48 F7 FB 48 89 D0
; ============================================================
.op_mod:
    mov     al, 0x5B
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x99
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0xF7
    call    emit_b
    mov     al, 0xFB
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0xD0
    call    emit_b
    inc     r12
    jmp     .p2

; ============================================================
; IR_IDIV: floor division — same as DIV for positive, adjust for negative
; Floor division: differs from truncating division for negative operands
; ============================================================
.op_idiv:
    ; Pop divisor into rbx
    mov     al, 0x5B
    call    emit_b
    ; cqo: sign-extend rax into rdx:rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0x99
    call    emit_b
    ; idiv rbx: rax = quotient, rdx = remainder
    mov     al, 0x48
    call    emit_b
    mov     al, 0xF7
    call    emit_b
    mov     al, 0xFB
    call    emit_b
    ; Floor correction: if remainder != 0 and signs of remainder and divisor differ, dec rax
    ; test rdx, rdx
    mov     al, 0x48
    call    emit_b
    mov     al, 0x85
    call    emit_b
    mov     al, 0xD2
    call    emit_b
    ; jz .idiv_done (skip if remainder is 0)
    mov     al, 0x74
    call    emit_b
    mov     al, 0x09
    call    emit_b
    ; xor rdx, rbx (check if remainder and divisor signs differ)
    mov     al, 0x48
    call    emit_b
    mov     al, 0x31
    call    emit_b
    mov     al, 0xDA
    call    emit_b
    ; jns .idiv_done (same sign → no correction needed)
    mov     al, 0x79
    call    emit_b
    mov     al, 0x03
    call    emit_b
    ; dec rax (floor = trunc - 1 when signs differ)
    mov     al, 0x48
    call    emit_b
    mov     al, 0xFF
    call    emit_b
    mov     al, 0xC8
    call    emit_b
    inc     r12
    jmp     .p2

; ============================================================
; IR_NEG: neg rax (48 F7 D8)
; ============================================================
.op_neg:
    mov     al, 0x48
    call    emit_b
    mov     al, 0xF7
    call    emit_b
    mov     al, 0xD8
    call    emit_b
    inc     r12
    jmp     .p2

; ============================================================
; IR_CMP: pop rbx; cmp rax,rbx; setCC al; movzx rax,al
; 5B 48 39 D8 0F 9x C0 0F B6 C0
; ============================================================
.op_cmp:
    mov     al, 0x5B
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x39
    call    emit_b
    mov     al, 0xD8
    call    emit_b

    mov     al, 0x0F
    call    emit_b
    movzx   eax, word [r13 + IR_OFF_AUX]
    lea     rcx, [rel .setcc_table]
    movzx   eax, byte [rcx + rax]
    call    emit_b
    mov     al, 0xC0
    call    emit_b

    mov     al, 0x0F
    call    emit_b
    mov     al, 0xB6
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    inc     r12
    jmp     .p2

.setcc_table:
    db 0x94, 0x95, 0x9C, 0x9F, 0x9E, 0x9D, 0x92, 0x97, 0x96, 0x93

; ============================================================
; IR_LAND: pop rbx; and rax,rbx; test;setnz;movzx
; 5B 48 21 D8 48 85 C0 0F 95 C0 0F B6 C0
; ============================================================
.op_land:
    mov     al, 0x5B
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x21
    call    emit_b
    mov     al, 0xD8
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x85
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x95
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0xB6
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    inc     r12
    jmp     .p2

; ============================================================
; IR_LOR: pop rbx; or rax,rbx; test;setnz;movzx
; 5B 48 09 D8 48 85 C0 0F 95 C0 0F B6 C0
; ============================================================
.op_lor:
    mov     al, 0x5B
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x09
    call    emit_b
    mov     al, 0xD8
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x85
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x95
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0xB6
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    inc     r12
    jmp     .p2

; ============================================================
; IR_LNOT: test rax,rax; setz al; movzx rax,al
; 48 85 C0 0F 94 C0 0F B6 C0
; ============================================================
.op_lnot:
    mov     al, 0x48
    call    emit_b
    mov     al, 0x85
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x94
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0xB6
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    inc     r12
    jmp     .p2

; ============================================================
; IR_TEST: test rax, rax (48 85 C0)
; ============================================================
.op_test:
    mov     al, 0x48
    call    emit_b
    mov     al, 0x85
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    inc     r12
    jmp     .p2

; ============================================================
; IR_JMP: E9 rel32
; ============================================================
.op_jmp:
    ; Flush register cache before jump (loop back-edge)
    cmp     qword [ir_cache_cnt], 0
    je      .op_jmp_no_flush
    ; Flush slot 0 (r15) → memory
    mov     al, 0x4C
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0x3C
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     rax, [ir_cache_var]
    shl     rax, 6
    add     rax, VAR_STORAGE_BASE
    call    emit_d
    ; Flush slot 1 (r14) → memory
    cmp     qword [ir_cache_cnt], 1
    jle     .op_jmp_flush_pop
    mov     al, 0x4C
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0x34
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     rax, [ir_cache_var + 8]
    shl     rax, 6
    add     rax, VAR_STORAGE_BASE
    call    emit_d
.op_jmp_flush_pop:
    ; pop r14 + pop r15
    mov     al, 0x41
    call    emit_b
    mov     al, 0x5E
    call    emit_b
    mov     al, 0x41
    call    emit_b
    mov     al, 0x5F
    call    emit_b
    mov     qword [ir_cache_cnt], 0
.op_jmp_no_flush:
    movzx   eax, word [r13 + IR_OFF_IMM]
    mov     eax, [emit_label_offs + rax*4]
    mov     rcx, [out_idx]
    add     rcx, 5
    sub     eax, ecx
    mov     r14d, eax
    mov     al, 0xE9
    call    emit_b
    mov     eax, r14d
    call    emit_d
    inc     r12
    jmp     .p2

; ============================================================
; IR_JMP_TRUE: test rax,rax; jnz rel32
; 48 85 C0 0F 85 rel32
; ============================================================
.op_jmp_true:
    ; Flush register cache before conditional jump
    cmp     qword [ir_cache_cnt], 0
    je      .op_jmp_true_no_flush
    ; Flush slot 0 (r15)
    mov     al, 0x4C
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0x3C
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     rax, [ir_cache_var]
    shl     rax, 6
    add     rax, VAR_STORAGE_BASE
    call    emit_d
    ; Flush slot 1 (r14)
    cmp     qword [ir_cache_cnt], 1
    jle     .op_jt_flush_pop
    mov     al, 0x4C
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0x34
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     rax, [ir_cache_var + 8]
    shl     rax, 6
    add     rax, VAR_STORAGE_BASE
    call    emit_d
.op_jt_flush_pop:
    mov     al, 0x41
    call    emit_b
    mov     al, 0x5E
    call    emit_b
    mov     al, 0x41
    call    emit_b
    mov     al, 0x5F
    call    emit_b
    mov     qword [ir_cache_cnt], 0
.op_jmp_true_no_flush:
    movzx   eax, word [r13 + IR_OFF_IMM]
    mov     eax, [emit_label_offs + rax*4]
    mov     rcx, [out_idx]
    add     rcx, 9
    sub     eax, ecx
    mov     r14d, eax
    mov     al, 0x48
    call    emit_b
    mov     al, 0x85
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x85
    call    emit_b
    mov     eax, r14d
    call    emit_d
    inc     r12
    jmp     .p2

; ============================================================
; IR_JMP_FALSE: test rax,rax; jz rel32
; 48 85 C0 0F 84 rel32
; ============================================================
.op_jmp_false:
    ; Flush register cache before conditional jump
    cmp     qword [ir_cache_cnt], 0
    je      .op_jmp_false_no_flush
    ; Flush slot 0 (r15)
    mov     al, 0x4C
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0x3C
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     rax, [ir_cache_var]
    shl     rax, 6
    add     rax, VAR_STORAGE_BASE
    call    emit_d
    ; Flush slot 1 (r14)
    cmp     qword [ir_cache_cnt], 1
    jle     .op_jf_flush_pop
    mov     al, 0x4C
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0x34
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     rax, [ir_cache_var + 8]
    shl     rax, 6
    add     rax, VAR_STORAGE_BASE
    call    emit_d
.op_jf_flush_pop:
    mov     al, 0x41
    call    emit_b
    mov     al, 0x5E
    call    emit_b
    mov     al, 0x41
    call    emit_b
    mov     al, 0x5F
    call    emit_b
    mov     qword [ir_cache_cnt], 0
.op_jmp_false_no_flush:
    movzx   eax, word [r13 + IR_OFF_IMM]
    mov     eax, [emit_label_offs + rax*4]
    mov     rcx, [out_idx]
    add     rcx, 9
    sub     eax, ecx
    mov     r14d, eax
    mov     al, 0x48
    call    emit_b
    mov     al, 0x85
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x84
    call    emit_b
    mov     eax, r14d
    call    emit_d
    inc     r12
    jmp     .p2

; ============================================================
; IR_JMP_CMP: jcc rel32 based on aux condition code
; 0F 8x rel32
; ============================================================
.op_jmp_cmp:
    movzx   eax, word [r13 + IR_OFF_IMM]
    mov     eax, [emit_label_offs + rax*4]
    mov     rcx, [out_idx]
    add     rcx, 6
    sub     eax, ecx
    mov     r14d, eax

    movzx   ecx, word [r13 + IR_OFF_AUX]
    lea     rdx, [rel .jcc_table]
    movzx   edx, byte [rdx + rcx]

    mov     al, 0x0F
    call    emit_b
    mov     al, dl
    call    emit_b
    mov     eax, r14d
    call    emit_d
    inc     r12
    jmp     .p2

.jcc_table:
    db 0x84, 0x85, 0x8C, 0x8F, 0x8E, 0x8D, 0x82, 0x87, 0x86, 0x83

; ============================================================
; IR_CALL: E8 rel32 to proto body, then add rsp if args > 0
; ============================================================
.op_call:
    movzx   eax, word [r13 + IR_OFF_SRC1]
    imul    rax, PROTO_ENTRY_SIZE
    mov     eax, dword [proto_table + rax + PROTO_OUTIDX_OFF]
    mov     rcx, [out_idx]
    add     rcx, 5
    sub     eax, ecx
    mov     r14d, eax
    mov     al, 0xE8
    call    emit_b
    mov     eax, r14d
    call    emit_d

    movzx   eax, word [r13 + IR_OFF_IMM]
    test    eax, eax
    jz      .call_done
    shl     eax, 3
    mov     r14d, eax
    mov     al, 0x48
    call    emit_b
    mov     al, 0x83
    call    emit_b
    mov     al, 0xC4
    call    emit_b
    mov     eax, r14d
    call    emit_b
.call_done:
    inc     r12
    jmp     .p2

; ============================================================
; IR_RET: mov rax, rdi; ret (48 89 F8 C3)
; ============================================================
.op_ret:
    mov     al, 0x48
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0xF8
    call    emit_b
    mov     al, 0xC3
    call    emit_b
    inc     r12
    jmp     .p2

; ============================================================
; IR_OUTPUT: mov rdi, rax; call rt_pri/prs/prb/prf/prc by type
; ============================================================
.op_output:
    mov     al, 0x48
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0xC7
    call    emit_b

    movzx   eax, byte [r13 + IR_OFF_TYPE]
    cmp     al, TYPE_FLOAT
    je      .output_float
    cmp     al, TYPE_BOOL
    je      .output_bool
    cmp     al, TYPE_STR
    je      .output_str
    cmp     al, TYPE_COMPLEX
    je      .output_complex
    mov     eax, LOAD_BASE + RT_PRI_OFFSET
    jmp     .output_call
.output_float:
    mov     eax, LOAD_BASE + RT_PRF_OFFSET
    jmp     .output_call
.output_bool:
    mov     eax, LOAD_BASE + RT_PRB_OFFSET
    jmp     .output_call
.output_str:
    mov     eax, LOAD_BASE + RT_PRS_OFFSET
    jmp     .output_call
.output_complex:
    mov     eax, LOAD_BASE + RT_PRC_OFFSET
.output_call:
    mov     rcx, [out_idx]
    add     rcx, 5
    sub     eax, ecx
    mov     r14d, eax
    mov     al, 0xE8
    call    emit_b
    mov     eax, r14d
    call    emit_d
    inc     r12
    jmp     .p2

; ============================================================
; IR_OUTPUT_STR: mov rdi, rax; call rt_prs
; ============================================================
.op_output_str:
    mov     al, 0x48
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0xC7
    call    emit_b
    mov     eax, LOAD_BASE + RT_PRS_OFFSET
    mov     rcx, [out_idx]
    add     rcx, 5
    sub     eax, ecx
    mov     r14d, eax
    mov     al, 0xE8
    call    emit_b
    mov     eax, r14d
    call    emit_d
    inc     r12
    jmp     .p2

; ============================================================
; IR_OUTPUT_NL: write syscall with inline newline byte
; mov eax,1; mov edi,1; lea rsi,[rip+7]; mov edx,1; syscall; db 0A
; ============================================================
.op_output_nl:
    mov     al, 0xB8
    call    emit_b
    mov     eax, 1
    call    emit_d

    mov     al, 0xBF
    call    emit_b
    mov     eax, 1
    call    emit_d

    mov     al, 0x48
    call    emit_b
    mov     al, 0x8D
    call    emit_b
    mov     al, 0x35
    call    emit_b
    mov     eax, 7
    call    emit_d

    mov     al, 0xBA
    call    emit_b
    mov     eax, 1
    call    emit_d

    mov     al, 0x0F
    call    emit_b
    mov     al, 0x05
    call    emit_b

    mov     al, 0x0A
    call    emit_b

    inc     r12
    jmp     .p2

; ============================================================
; IR_SWAP: mov rax,[a]; xchg rax,[b]; mov [a],raxon
; ============================================================
.op_swap:
    movzx   eax, word [r13 + IR_OFF_SRC1]
    shl     eax, 6
    add     eax, VAR_STORAGE_BASE
    mov     r14d, eax

    movzx   eax, word [r13 + IR_OFF_SRC2]
    shl     eax, 6
    add     eax, VAR_STORAGE_BASE
    mov     ebx, eax

    mov     al, 0x48
    call    emit_b
    mov     al, 0x8B
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r14d
    call    emit_d

    mov     al, 0x48
    call    emit_b
    mov     al, 0x87
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, ebx
    call    emit_d

    mov     al, 0x48
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r14d
    call    emit_d

    inc     r12
    jmp     .p2

; ============================================================
; IR_INC: inc qword [VAR_STORAGE_BASE + var_idx*64]
; 48 FF 04 25 addr32
; ============================================================
.op_inc:
    ; Check register cache first
    movzx   eax, word [r13 + IR_OFF_SRC1]    ; var_idx
    ; Search cache
    xor     ecx, ecx
.inc_cache_search:
    cmp     ecx, 4
    jge     .inc_cache_miss
    cmp     rax, [ir_cache_var + rcx*8]
    je      .inc_cache_hit
    inc     ecx
    jmp     .inc_cache_search
.inc_cache_hit:
    ; Emit: inc reg (2-3 bytes)
    cmp     ecx, 0
    je      .inc_r15
    cmp     ecx, 1
    je      .inc_r14
    jmp     .inc_cache_miss
.inc_r15:
    ; inc r15 = 49 FF C7
    mov     al, 0x49
    call    emit_b
    mov     al, 0xFF
    call    emit_b
    mov     al, 0xC7
    call    emit_b
    inc     r12
    jmp     .p2
.inc_r14:
    ; inc r14 = 49 FF C6
    mov     al, 0x49
    call    emit_b
    mov     al, 0xFF
    call    emit_b
    mov     al, 0xC6
    call    emit_b
    inc     r12
    jmp     .p2

.inc_cache_miss:
    movzx   eax, word [r13 + IR_OFF_SRC1]
    shl     eax, 6
    add     eax, VAR_STORAGE_BASE
    mov     r14d, eax
    mov     al, 0x48
    call    emit_b
    mov     al, 0xFF
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r14d
    call    emit_d
    inc     r12
    jmp     .p2

; ============================================================
; IR_DEC: dec qword [VAR_STORAGE_BASE + var_idx*64]
; 48 FF 0C 25 addr32
; ============================================================
.op_dec:
    movzx   eax, word [r13 + IR_OFF_SRC1]
    shl     eax, 6
    add     eax, VAR_STORAGE_BASE
    mov     r14d, eax
    mov     al, 0x48
    call    emit_b
    mov     al, 0xFF
    call    emit_b
    mov     al, 0x0C
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r14d
    call    emit_d
    inc     r12
    jmp     .p2

; ============================================================
; IR_SEQ_NEW: allocate sequence header via rt_alc
; mov edi,80; call rt_alc; init header
; ============================================================
.op_seq_new:
    mov     al, 0xBF
    call    emit_b
    mov     al, 0x50
    call    emit_b
    xor     eax, eax
    call    emit_d

    mov     eax, LOAD_BASE + RT_ALC_OFFSET
    mov     rcx, [out_idx]
    add     rcx, 5
    sub     eax, ecx
    mov     r14d, eax
    mov     al, 0xE8
    call    emit_b
    mov     eax, r14d
    call    emit_d

    mov     al, 0x48
    call    emit_b
    mov     al, 0xC7
    call    emit_b
    mov     al, 0x00
    call    emit_b
    xor     eax, eax
    call    emit_d

    mov     al, 0x48
    call    emit_b
    mov     al, 0xC7
    call    emit_b
    mov     al, 0x40
    call    emit_b
    mov     al, 0x08
    call    emit_b
    xor     eax, eax
    call    emit_d

    inc     r12
    jmp     .p2

; ============================================================
; IR_SEQ_PUSH
; ============================================================
.op_seq_push:
    pop     rsi
    pop     rbx
    mov     rcx, [rbx + 4]
    cmp     dword [rbx], ecx
    jbe     .seq_push_grow
    mov     [rbx + rcx*8 + 20], rsi
    inc     qword [rbx + 4]
    inc     r12
    jmp     .p2
.seq_push_grow:
    mov     [rbx + rcx*8 + 20], rsi
    inc     qword [rbx + 4]
    inc     r12
    jmp     .p2

; ============================================================
; IR_SEQ_POP
; ============================================================
.op_seq_pop:
    pop     rbx
    mov     rcx, [rbx + 4]
    dec     rcx
    mov     [rbx + 4], rcx
    mov     rax, [rbx + rcx*8 + 20]
    push    rax
    inc     r12
    jmp     .p2

; ============================================================
; IR_SEQ_GET
; ============================================================
.op_seq_get:
    pop     rcx
    pop     rbx
    mov     rax, [rbx + rcx*8 + 20]
    push    rax
    inc     r12
    jmp     .p2

; ============================================================
; IR_SEQ_SET
; ============================================================
.op_seq_set:
    pop     rdx
    pop     rcx
    pop     rbx
    mov     [rbx + rcx*8 + 20], rdx
    inc     r12
    jmp     .p2

; ============================================================
; IR_SEQ_LEN: mov rax, [rax] (48 8B 00)
; ============================================================
.op_seq_len:
    mov     al, 0x48
    call    emit_b
    mov     al, 0x8B
    call    emit_b
    mov     al, 0x00
    call    emit_b
    inc     r12
    jmp     .p2

; ============================================================
; IR_DICT_NEW: allocate via rt_alc
; ============================================================
.op_dict_new:
    mov     al, 0xBF
    call    emit_b
    mov     eax, 256
    call    emit_d

    mov     eax, LOAD_BASE + RT_ALC_OFFSET
    mov     rcx, [out_idx]
    add     rcx, 5
    sub     eax, ecx
    mov     r14d, eax
    mov     al, 0xE8
    call    emit_b
    mov     eax, r14d
    call    emit_d
    inc     r12
    jmp     .p2

; ============================================================
; IR_DICT_SET: pop val, key, dict_ptr — simplified
; ============================================================
.op_dict_set:
    add     rsp, 24
    inc     r12
    jmp     .p2

; ============================================================
; IR_DICT_GET: pop key, dict_ptr — simplified: push 0
; ============================================================
.op_dict_get:
    add     rsp, 16
    xor     eax, eax
    push    rax
    inc     r12
    jmp     .p2

; ============================================================
; IR_RAISE: pop error message pointer, call rt_err_blob
; ============================================================
.op_raise:
    pop     rdi
    mov     eax, LOAD_BASE + RT_PRQ_OFFSET
    mov     rcx, [out_idx]
    add     rcx, 5
    sub     eax, ecx
    mov     r14d, eax
    mov     al, 0xE8
    call    emit_b
    mov     eax, r14d
    call    emit_d
    inc     r12
    jmp     .p2

; ============================================================
; IR_RESERVE: mov rdi, imm64; call rt_alc
; ============================================================
.op_reserve:
    mov     rdi, [r13 + IR_OFF_IMM]
    mov     al, 0x48
    call    emit_b
    mov     al, 0xBF
    call    emit_b
    mov     rax, rdi
    call    emit_q
    mov     eax, LOAD_BASE + RT_ALC_OFFSET
    mov     rcx, [out_idx]
    add     rcx, 5
    sub     eax, ecx
    mov     r14d, eax
    mov     al, 0xE8
    call    emit_b
    mov     eax, r14d
    call    emit_d
    inc     r12
    jmp     .p2

; ============================================================
; IR_LEN: pop pointer, read length from hidden header at [rax+8]
; ============================================================
.op_len:
    pop     rax
    mov     rax, [rax + 8]
    push    rax
    inc     r12
    jmp     .p2

; ============================================================
; IR_CONCAT: pop two string pointers, call rt_str_cat
; ============================================================
.op_concat:
    pop     rsi
    pop     rdi
    mov     eax, LOAD_BASE + RT_STR_CAT_OFFSET
    mov     rcx, [out_idx]
    add     rcx, 5
    sub     eax, ecx
    mov     r14d, eax
    mov     al, 0xE8
    call    emit_b
    mov     eax, r14d
    call    emit_d
    push    rax
    inc     r12
    jmp     .p2

; ============================================================
; IR_TYPEOF: push type code of the expression onto runtime stack
; ============================================================
.op_typeof:
    movzx   eax, byte [r13 + IR_OFF_TYPE]
    mov     r14d, eax
    mov     al, 0x48
    call    emit_b
    mov     al, 0xB8
    call    emit_b
    mov     eax, r14d
    call    emit_q
    mov     al, 0x50
    call    emit_b
    inc     r12
    jmp     .p2

; ============================================================
; IR_INPUT: call rt_inp runtime blob
; ============================================================
.op_input:
    mov     eax, LOAD_BASE + RT_INP_OFFSET
    mov     rcx, [out_idx]
    add     rcx, 5
    sub     eax, ecx
    mov     r14d, eax
    mov     al, 0xE8
    call    emit_b
    mov     eax, r14d
    call    emit_d
    push    rax
    inc     r12
    jmp     .p2

; ============================================================
; IR_ASSERT: pop value; if zero, trap with ud2
; ============================================================
.op_assert:
    pop     rax
    test    rax, rax
    jnz     .op_assert_ok
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x0B
    call    emit_b
.op_assert_ok:
    inc     r12
    jmp     .p2

; ============================================================
; IR_CLOCK: clock_gettime syscall, return milliseconds
; ============================================================
.op_clock:
    sub     rsp, 16
    mov     rdi, 1
    mov     rsi, rsp
    mov     eax, 228
    syscall
    mov     rax, [rsp]
    mov     rcx, 1000
    imul    rax, rcx
    add     rsp, 16
    push    rax
    inc     r12
    jmp     .p2

; ============================================================
; IR_LOAD_GLOBAL: load from global address in imm field
; ============================================================
.op_load_global:
    mov     rax, [r13 + IR_OFF_IMM]
    mov     rax, [rax]
    push    rax
    inc     r12
    jmp     .p2

; ============================================================
; IR_STORE_GLOBAL: store to global address in imm field
; ============================================================
.op_store_global:
    pop     rax
    mov     rcx, [r13 + IR_OFF_IMM]
    mov     [rcx], rax
    inc     r12
    jmp     .p2

; ============================================================
; IR_BAND: and rax, rbx (48 21 D8)
; ============================================================
.op_band:
    pop     rbx
    and     rax, rbx
    push    rax
    inc     r12
    jmp     .p2

; ============================================================
; IR_BOR: or rax, rbx (48 09 D8)
; ============================================================
.op_bor:
    pop     rbx
    or      rax, rbx
    push    rax
    inc     r12
    jmp     .p2

; ============================================================
; IR_BXOR: xor rax, rbx (48 31 D8)
; ============================================================
.op_bxor:
    pop     rbx
    xor     rax, rbx
    push    rax
    inc     r12
    jmp     .p2

; ============================================================
; IR_BNOT: not rax (48 F7 D0)
; ============================================================
.op_bnot:
    not     rax
    push    rax
    inc     r12
    jmp     .p2

; ============================================================
; IR_BSHL: shl rax, cl (48 D3 E0)
; ============================================================
.op_bshl:
    pop     rcx
    shl     rax, cl
    push    rax
    inc     r12
    jmp     .p2

; ============================================================
; IR_BSHR: shr rax, cl (48 D3 E8) — logical shift right
; ============================================================
.op_bshr:
    pop     rcx
    shr     rax, cl
    push    rax
    inc     r12
    jmp     .p2

; ============================================================
; IR_BSHR_S: sar rax, cl (48 D3 F8) — arithmetic shift right
; ============================================================
.op_bshr_s:
    pop     rcx
    sar     rax, cl
    push    rax
    inc     r12
    jmp     .p2

; ============================================================
; IR_ABS: integer absolute value
; test rax, rax; jns .skip; neg rax; .skip:
; ============================================================
.op_abs:
    pop     rbx
    mov     rax, rbx
    test    rax, rax
    jns     .op_abs_done
    neg     rax
.op_abs_done:
    push    rax
    inc     r12
    jmp     .p2

; ============================================================
; IR_SIGN: sign function (-1, 0, or 1)
; ============================================================
.op_sign:
    pop     rbx
    mov     rax, rbx
    cmp     rax, 0
    setl    cl
    setg    dl
    movzx   ecx, cl
    movzx   edx, dl
    sub     ecx, edx
    movsxd  rax, ecx
    push    rax
    inc     r12
    jmp     .p2

; ============================================================
; Float binary ops: emit x86 for xmm0 = xmm0 op xmm1
; Pattern: pop rax; movq xmm1,rax; opsd xmm0,xmm1; movq rax,xmm0; push rax
; ============================================================
.op_fadd:
    ; pop rax (5B)
    mov     al, 0x5B
    call    emit_b
    ; movq xmm1, rax (F3 48 0F 7E C8)
    mov     al, 0xF3
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x7E
    call    emit_b
    mov     al, 0xC8
    call    emit_b
    ; addsd xmm0, xmm1 (F2 0F 58 C1)
    mov     al, 0xF2
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x58
    call    emit_b
    mov     al, 0xC1
    call    emit_b
    ; movq rax, xmm0 (F3 48 0F 7E C0)
    mov     al, 0xF3
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x7E
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    ; push rax (50)
    mov     al, 0x50
    call    emit_b
    inc     r12
    jmp     .p2

.op_fsub:
    ; pop rax
    mov     al, 0x5B
    call    emit_b
    ; movq xmm1, rax
    mov     al, 0xF3
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x7E
    call    emit_b
    mov     al, 0xC8
    call    emit_b
    ; subsd xmm0, xmm1 (F2 0F 5C C1)
    mov     al, 0xF2
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x5C
    call    emit_b
    mov     al, 0xC1
    call    emit_b
    ; movq rax, xmm0
    mov     al, 0xF3
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x7E
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    ; push rax
    mov     al, 0x50
    call    emit_b
    inc     r12
    jmp     .p2

.op_fmul:
    ; pop rax
    mov     al, 0x5B
    call    emit_b
    ; movq xmm1, rax
    mov     al, 0xF3
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x7E
    call    emit_b
    mov     al, 0xC8
    call    emit_b
    ; mulsd xmm0, xmm1 (F2 0F 59 C1)
    mov     al, 0xF2
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x59
    call    emit_b
    mov     al, 0xC1
    call    emit_b
    ; movq rax, xmm0
    mov     al, 0xF3
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x7E
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    ; push rax
    mov     al, 0x50
    call    emit_b
    inc     r12
    jmp     .p2

.op_fdiv:
    ; pop rax
    mov     al, 0x5B
    call    emit_b
    ; movq xmm1, rax
    mov     al, 0xF3
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x7E
    call    emit_b
    mov     al, 0xC8
    call    emit_b
    ; divsd xmm0, xmm1 (F2 0F 5E C1)
    mov     al, 0xF2
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x5E
    call    emit_b
    mov     al, 0xC1
    call    emit_b
    ; movq rax, xmm0
    mov     al, 0xF3
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x7E
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    ; push rax
    mov     al, 0x50
    call    emit_b
    inc     r12
    jmp     .p2

.op_fneg:
    ; Float negate: flip sign bit using xorps with [sign_mask]
    ; Actually, use: movq rax,xmm0; btc rax,63; movq xmm0,rax
    ; movq rax, xmm0 (F3 48 0F 7E C0)
    mov     al, 0xF3
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x7E
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    ; btc rax, 63 (48 0F BA F8 3F)
    mov     al, 0x48
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0xBA
    call    emit_b
    mov     al, 0xF8
    call    emit_b
    mov     al, 0x3F
    call    emit_b
    ; movq xmm0, rax (F3 48 0F 6E C0)
    mov     al, 0xF3
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x6E
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    ; push rax
    mov     al, 0x50
    call    emit_b
    inc     r12
    jmp     .p2

.op_fabs:
    ; Float abs: clear sign bit using btr rax,63
    ; movq rax, xmm0
    mov     al, 0xF3
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x7E
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    ; btr rax, 63 (48 0F BA F0 3F)
    mov     al, 0x48
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0xBA
    call    emit_b
    mov     al, 0xF0
    call    emit_b
    mov     al, 0x3F
    call    emit_b
    ; movq xmm0, rax
    mov     al, 0xF3
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x6E
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    ; push rax
    mov     al, 0x50
    call    emit_b
    inc     r12
    jmp     .p2

.op_floor:
    ; x87 floor: set RC=01 (floor), frndint
    ; sub rsp, 16
    mov     al, 0x48
    call    emit_b
    mov     al, 0x83
    call    emit_b
    mov     al, 0xEC
    call    emit_b
    mov     al, 0x10
    call    emit_b
    ; movsd [rsp+8], xmm0 (F2 0F 11 44 24 08)
    mov     al, 0xF2
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x11
    call    emit_b
    mov     al, 0x44
    call    emit_b
    mov     al, 0x24
    call    emit_b
    mov     al, 0x08
    call    emit_b
    ; fld qword [rsp+8] (DD 44 24 08)
    mov     al, 0xDD
    call    emit_b
    mov     al, 0x44
    call    emit_b
    mov     al, 0x24
    call    emit_b
    mov     al, 0x08
    call    emit_b
    ; fnstcw [rsp] (9B D7 34 24)
    mov     al, 0x9B
    call    emit_b
    mov     al, 0xD7
    call    emit_b
    mov     al, 0x34
    call    emit_b
    mov     al, 0x24
    call    emit_b
    ; movzx eax, word [rsp] (0F B7 04 24)
    mov     al, 0x0F
    call    emit_b
    mov     al, 0xB7
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x24
    call    emit_b
    ; and ax, 0xF3FF (66 25 FF F3)
    mov     al, 0x66
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     al, 0xFF
    call    emit_b
    mov     al, 0xF3
    call    emit_b
    ; or ax, 0x0400 (66 0D 00 04)
    mov     al, 0x66
    call    emit_b
    mov     al, 0x0D
    call    emit_b
    mov     al, 0x00
    call    emit_b
    mov     al, 0x04
    call    emit_b
    ; mov [rsp+2], ax (66 89 44 24 02)
    mov     al, 0x66
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0x44
    call    emit_b
    mov     al, 0x24
    call    emit_b
    mov     al, 0x02
    call    emit_b
    ; fldcw [rsp+2] (D7 6C 24 02)
    mov     al, 0xD7
    call    emit_b
    mov     al, 0x6C
    call    emit_b
    mov     al, 0x24
    call    emit_b
    mov     al, 0x02
    call    emit_b
    ; frndint (D9 FC)
    mov     al, 0xD9
    call    emit_b
    mov     al, 0xFC
    call    emit_b
    ; fldcw [rsp] (D7 34 24)
    mov     al, 0xD7
    call    emit_b
    mov     al, 0x34
    call    emit_b
    mov     al, 0x24
    call    emit_b
    ; fstp qword [rsp+8] (DD 5C 24 08)
    mov     al, 0xDD
    call    emit_b
    mov     al, 0x5C
    call    emit_b
    mov     al, 0x24
    call    emit_b
    mov     al, 0x08
    call    emit_b
    ; movsd xmm0, [rsp+8] (F2 0F 10 44 24 08)
    mov     al, 0xF2
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x10
    call    emit_b
    mov     al, 0x44
    call    emit_b
    mov     al, 0x24
    call    emit_b
    mov     al, 0x08
    call    emit_b
    ; add rsp, 16 (48 83 C4 10)
    mov     al, 0x48
    call    emit_b
    mov     al, 0x83
    call    emit_b
    mov     al, 0xC4
    call    emit_b
    mov     al, 0x10
    call    emit_b
    ; movq rax, xmm0 (F3 48 0F 7E C0)
    mov     al, 0xF3
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x7E
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    ; push rax (50)
    mov     al, 0x50
    call    emit_b
    inc     r12
    jmp     .p2

.op_ceil:
    ; x87 ceil: set RC=10 (ceil), frndint
    ; Same as floor but OR with 0x0800 instead of 0x0400
    ; sub rsp, 16
    mov     al, 0x48
    call    emit_b
    mov     al, 0x83
    call    emit_b
    mov     al, 0xEC
    call    emit_b
    mov     al, 0x10
    call    emit_b
    ; movsd [rsp+8], xmm0
    mov     al, 0xF2
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x11
    call    emit_b
    mov     al, 0x44
    call    emit_b
    mov     al, 0x24
    call    emit_b
    mov     al, 0x08
    call    emit_b
    ; fld qword [rsp+8]
    mov     al, 0xDD
    call    emit_b
    mov     al, 0x44
    call    emit_b
    mov     al, 0x24
    call    emit_b
    mov     al, 0x08
    call    emit_b
    ; fnstcw [rsp]
    mov     al, 0x9B
    call    emit_b
    mov     al, 0xD7
    call    emit_b
    mov     al, 0x34
    call    emit_b
    mov     al, 0x24
    call    emit_b
    ; movzx eax, word [rsp]
    mov     al, 0x0F
    call    emit_b
    mov     al, 0xB7
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x24
    call    emit_b
    ; and ax, 0xF3FF
    mov     al, 0x66
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     al, 0xFF
    call    emit_b
    mov     al, 0xF3
    call    emit_b
    ; or ax, 0x0800 (ceil mode)
    mov     al, 0x66
    call    emit_b
    mov     al, 0x0D
    call    emit_b
    mov     al, 0x00
    call    emit_b
    mov     al, 0x08
    call    emit_b
    ; mov [rsp+2], ax
    mov     al, 0x66
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0x44
    call    emit_b
    mov     al, 0x24
    call    emit_b
    mov     al, 0x02
    call    emit_b
    ; fldcw [rsp+2]
    mov     al, 0xD7
    call    emit_b
    mov     al, 0x6C
    call    emit_b
    mov     al, 0x24
    call    emit_b
    mov     al, 0x02
    call    emit_b
    ; frndint
    mov     al, 0xD9
    call    emit_b
    mov     al, 0xFC
    call    emit_b
    ; fldcw [rsp]
    mov     al, 0xD7
    call    emit_b
    mov     al, 0x34
    call    emit_b
    mov     al, 0x24
    call    emit_b
    ; fstp qword [rsp+8]
    mov     al, 0xDD
    call    emit_b
    mov     al, 0x5C
    call    emit_b
    mov     al, 0x24
    call    emit_b
    mov     al, 0x08
    call    emit_b
    ; movsd xmm0, [rsp+8]
    mov     al, 0xF2
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x10
    call    emit_b
    mov     al, 0x44
    call    emit_b
    mov     al, 0x24
    call    emit_b
    mov     al, 0x08
    call    emit_b
    ; add rsp, 16
    mov     al, 0x48
    call    emit_b
    mov     al, 0x83
    call    emit_b
    mov     al, 0xC4
    call    emit_b
    mov     al, 0x10
    call    emit_b
    ; movq rax, xmm0
    mov     al, 0xF3
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x7E
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    ; push rax
    mov     al, 0x50
    call    emit_b
    inc     r12
    jmp     .p2

.op_round:
    ; x87 round: RC=00 (round to nearest), frndint
    ; Same as floor but no OR (RC stays 00)
    ; sub rsp, 16
    mov     al, 0x48
    call    emit_b
    mov     al, 0x83
    call    emit_b
    mov     al, 0xEC
    call    emit_b
    mov     al, 0x10
    call    emit_b
    ; movsd [rsp+8], xmm0
    mov     al, 0xF2
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x11
    call    emit_b
    mov     al, 0x44
    call    emit_b
    mov     al, 0x24
    call    emit_b
    mov     al, 0x08
    call    emit_b
    ; fld qword [rsp+8]
    mov     al, 0xDD
    call    emit_b
    mov     al, 0x44
    call    emit_b
    mov     al, 0x24
    call    emit_b
    mov     al, 0x08
    call    emit_b
    ; fnstcw [rsp]
    mov     al, 0x9B
    call    emit_b
    mov     al, 0xD7
    call    emit_b
    mov     al, 0x34
    call    emit_b
    mov     al, 0x24
    call    emit_b
    ; movzx eax, word [rsp]
    mov     al, 0x0F
    call    emit_b
    mov     al, 0xB7
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x24
    call    emit_b
    ; and ax, 0xF3FF (clear RC bits to 00)
    mov     al, 0x66
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     al, 0xFF
    call    emit_b
    mov     al, 0xF3
    call    emit_b
    ; mov [rsp+2], ax (no OR needed, RC=00)
    mov     al, 0x66
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0x44
    call    emit_b
    mov     al, 0x24
    call    emit_b
    mov     al, 0x02
    call    emit_b
    ; fldcw [rsp+2]
    mov     al, 0xD7
    call    emit_b
    mov     al, 0x6C
    call    emit_b
    mov     al, 0x24
    call    emit_b
    mov     al, 0x02
    call    emit_b
    ; frndint
    mov     al, 0xD9
    call    emit_b
    mov     al, 0xFC
    call    emit_b
    ; fldcw [rsp]
    mov     al, 0xD7
    call    emit_b
    mov     al, 0x34
    call    emit_b
    mov     al, 0x24
    call    emit_b
    ; fstp qword [rsp+8]
    mov     al, 0xDD
    call    emit_b
    mov     al, 0x5C
    call    emit_b
    mov     al, 0x24
    call    emit_b
    mov     al, 0x08
    call    emit_b
    ; movsd xmm0, [rsp+8]
    mov     al, 0xF2
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x10
    call    emit_b
    mov     al, 0x44
    call    emit_b
    mov     al, 0x24
    call    emit_b
    mov     al, 0x08
    call    emit_b
    ; add rsp, 16
    mov     al, 0x48
    call    emit_b
    mov     al, 0x83
    call    emit_b
    mov     al, 0xC4
    call    emit_b
    mov     al, 0x10
    call    emit_b
    ; movq rax, xmm0
    mov     al, 0xF3
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x7E
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    ; push rax
    mov     al, 0x50
    call    emit_b
    inc     r12
    jmp     .p2

.op_fsqrt:
    ; sqrtsd xmm0, xmm0 (F2 0F 51 C0)
    mov     al, 0xF2
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x51
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    ; movq rax, xmm0
    mov     al, 0xF3
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x7E
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    ; push rax
    mov     al, 0x50
    call    emit_b
    inc     r12
    jmp     .p2

; ============================================================
; .est_x86_size: estimate x86 byte count for pass 1
; Advances out_idx by the estimated size.
; ============================================================
.est_x86_size:
    movzx   eax, byte [r13 + IR_OFF_OPCODE]

    cmp     al, IR_NOP
    je      .est_0
    cmp     al, IR_LABEL
    je      .est_0
    cmp     al, IR_PROTO_BEGIN
    je      .est_0
    cmp     al, IR_PROTO_END
    je      .est_0
    cmp     al, IR_MOV
    je      .est_0
    cmp     al, IR_LOAD_IMM
    je      .est_10
    cmp     al, IR_LOAD_BOOL
    je      .est_10
    cmp     al, IR_LOAD_STRING
    je      .est_10
    cmp     al, IR_LOAD_NULL
    je      .est_2
    cmp     al, IR_LOAD_VAR
    je      .est_8
    cmp     al, IR_STORE_VAR
    je      .est_8
    cmp     al, IR_ADD
    je      .est_4
    cmp     al, IR_SUB
    je      .est_4
    cmp     al, IR_MUL
    je      .est_mul
    cmp     al, IR_DIV
    je      .est_6
    cmp     al, IR_MOD
    je      .est_9
    cmp     al, IR_IDIV
    je      .est_19
    cmp     al, IR_NEG
    je      .est_3
    cmp     al, IR_CMP
    je      .est_10
    cmp     al, IR_LAND
    je      .est_13
    cmp     al, IR_LOR
    je      .est_13
    cmp     al, IR_LNOT
    je      .est_9
    cmp     al, IR_TEST
    je      .est_3
    cmp     al, IR_JMP
    je      .est_5
    cmp     al, IR_JMP_TRUE
    je      .est_9
    cmp     al, IR_JMP_FALSE
    je      .est_9
    cmp     al, IR_JMP_CMP
    je      .est_6
    cmp     al, IR_CALL
    je      .est_call
    cmp     al, IR_RET
    je      .est_4
    cmp     al, IR_OUTPUT
    je      .est_8
    cmp     al, IR_OUTPUT_STR
    je      .est_8
    cmp     al, IR_OUTPUT_NL
    je      .est_25
    cmp     al, IR_SWAP
    je      .est_24
    cmp     al, IR_INC
    je      .est_8
    cmp     al, IR_DEC
    je      .est_8
    cmp     al, IR_SEQ_NEW
    je      .est_25
    cmp     al, IR_SEQ_LEN
    je      .est_3
    cmp     al, IR_DICT_NEW
    je      .est_10
    cmp     al, IR_RESERVE
    je      .est_15
    cmp     al, IR_TZCNT
    je      .est_5b
    cmp     al, IR_LZCNT
    je      .est_5b
    cmp     al, IR_POPCOUNT
    je      .est_5b
    cmp     al, IR_SIMD_LOAD
    je      .est_8
    cmp     al, IR_SIMD_STORE
    je      .est_8
    cmp     al, IR_SIMD_ADD
    je      .est_4
    cmp     al, IR_SIMD_SUB
    je      .est_4
    cmp     al, 0xA2           ; IR_SIMD_REDUCE_SUM
    je      .est_22
    cmp     al, IR_BAND
    je      .est_4
    cmp     al, IR_BOR
    je      .est_4
    cmp     al, IR_BXOR
    je      .est_4
    cmp     al, IR_BNOT
    je      .est_3
    cmp     al, IR_BSHL
    je      .est_4
    cmp     al, IR_BSHR
    je      .est_4
    cmp     al, IR_BSHR_S
    je      .est_4
    cmp     al, IR_ABS
    je      .est_8
    cmp     al, IR_SIGN
    je      .est_12
    cmp     al, IR_LOAD_CHAR
    je      .est_10
    cmp     al, IR_LOAD_BYTE
    je      .est_10
    cmp     al, IR_FADD
    je      .est_10
    cmp     al, IR_FSUB
    je      .est_10
    cmp     al, IR_FMUL
    je      .est_10
    cmp     al, IR_FDIV
    je      .est_10
    cmp     al, IR_FNEG
    je      .est_8
    cmp     al, IR_FABS
    je      .est_8
    cmp     al, IR_FLOOR
    je      .est_60
    cmp     al, IR_CEIL
    je      .est_60
    cmp     al, IR_ROUND
    je      .est_60
    cmp     al, IR_FSQRT
    je      .est_10
    cmp     al, IR_RAISE
    je      .est_5
    cmp     al, IR_CONCAT
    je      .est_5
    cmp     al, IR_INPUT
    je      .est_5
    cmp     al, IR_TYPEOF
    je      .est_11
    ret

.est_0:
    ret
.est_2:
    add     qword [out_idx], 2
    ret
.est_3:
    add     qword [out_idx], 3
    ret
.est_4:
    add     qword [out_idx], 4
    ret
.est_5:
    add     qword [out_idx], 5
    ret
.est_6:
    add     qword [out_idx], 6
    ret
.est_8:
    add     qword [out_idx], 8
    ret
.est_9:
    add     qword [out_idx], 9
    ret
.est_10:
    add     qword [out_idx], 10
    ret
.est_11:
    add     qword [out_idx], 11
    ret
.est_12:
    add     qword [out_idx], 12
    ret
.est_13:
    add     qword [out_idx], 13
    ret
.est_15:
    add     qword [out_idx], 15
    ret
.est_19:
    add     qword [out_idx], 19
    ret
.est_22:
    add     qword [out_idx], 22
    ret
.est_24:
    add     qword [out_idx], 24
    ret
.est_25:
    add     qword [out_idx], 25
    ret
.est_60:
    add     qword [out_idx], 60
    ret

.est_mul:
    cmp     word [r13 + IR_OFF_SRC2], 0
    jne     .est_5
    add     qword [out_idx], 7
    ret

.est_5b:
    add     qword [out_idx], 5
    ret

.est_call:
    movzx   eax, word [r13 + IR_OFF_IMM]
    test    eax, eax
    jz      .est_call_no_args
    add     qword [out_idx], 9
    ret
.est_call_no_args:
    add     qword [out_idx], 5
    ret

; ============================================================
; Done
; ============================================================
.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ============================================================
; ir_rewrite_cached_ops — post-pass to rewrite memory ops for cached vars
; Scans output buffer for incl/addq targeting cached variables,
; replaces with register operations.
; ============================================================
global ir_rewrite_cached_ops
ir_rewrite_cached_ops:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    cmp     qword [ir_cache_cnt], 0
    je      .rw_done

    mov     r12, CODE_START
    mov     r13, [out_idx]

.rw_loop:
    cmp     r12, r13
    jge     .rw_done

    ; Check for incl [abs32]: 48 FF 04 25 addr32 (7 bytes)
    cmp     r12, 7
    jb      .rw_next
    lea     rdi, [out_buffer + r12]
    cmp     byte [rdi], 0x48
    jne     .rw_check_addq
    cmp     byte [rdi+1], 0xFF
    jne     .rw_check_addq
    cmp     byte [rdi+2], 0x04
    jne     .rw_check_addq
    cmp     byte [rdi+3], 0x25
    jne     .rw_check_addq
    ; Found incl [abs32] — extract addr32
    mov     eax, [rdi+4]
    ; Check if addr matches a cached variable
    sub     rax, VAR_STORAGE_BASE
    shr     rax, 6              ; var_idx
    ; Search cache
    xor     ecx, ecx
.rw_incl_search:
    cmp     ecx, 4
    jge     .rw_check_addq
    cmp     rax, [ir_cache_var + rcx*8]
    je      .rw_incl_hit
    inc     ecx
    jmp     .rw_incl_search
.rw_incl_hit:
    ; Replace incl [abs32] (7 bytes) with inc reg (2-3 bytes)
    ; Rewrite: overwrite with inc reg + NOPs
    cmp     ecx, 0
    je      .rw_incl_r15
    cmp     ecx, 1
    je      .rw_incl_r14
    jmp     .rw_check_addq
.rw_incl_r15:
    ; inc r15 = 49 FF C7
    mov     byte [rdi], 0x49
    mov     byte [rdi+1], 0xFF
    mov     byte [rdi+2], 0xC7
    ; NOP remaining 4 bytes
    mov     byte [rdi+3], 0x90
    mov     byte [rdi+4], 0x90
    mov     byte [rdi+5], 0x90
    mov     byte [rdi+6], 0x90
    add     r12, 7
    jmp     .rw_loop
.rw_incl_r14:
    ; inc r14 = 49 FF C6
    mov     byte [rdi], 0x49
    mov     byte [rdi+1], 0xFF
    mov     byte [rdi+2], 0xC6
    mov     byte [rdi+3], 0x90
    mov     byte [rdi+4], 0x90
    mov     byte [rdi+5], 0x90
    mov     byte [rdi+6], 0x90
    add     r12, 7
    jmp     .rw_loop

.rw_check_addq:
    ; Check for addq $N, [abs32]: 48 83 04 25 addr32 imm8 (9 bytes)
    lea     rdi, [out_buffer + r12]
    cmp     r13, r12
    sub     r13, r12
    cmp     r13, 9
    add     r13, r12
    jl      .rw_next
    cmp     byte [rdi], 0x48
    jne     .rw_next
    cmp     byte [rdi+1], 0x83
    jne     .rw_next
    cmp     byte [rdi+2], 0x04
    jne     .rw_next
    cmp     byte [rdi+3], 0x25
    jne     .rw_next
    ; Found addq $imm8, [abs32] — extract addr32 and imm8
    mov     eax, [rdi+4]       ; addr32
    movzx   r14d, byte [rdi+8] ; imm8 (sign-extended later)
    ; Check cache
    sub     rax, VAR_STORAGE_BASE
    shr     rax, 6
    xor     ecx, ecx
.rw_addq_search:
    cmp     ecx, 4
    jge     .rw_next
    cmp     rax, [ir_cache_var + rcx*8]
    je      .rw_addq_hit
    inc     ecx
    jmp     .rw_addq_search
.rw_addq_hit:
    ; Replace addq $imm8, [abs32] (9 bytes) with add reg, imm8 (4 bytes)
    cmp     ecx, 0
    je      .rw_addq_r15
    cmp     ecx, 1
    je      .rw_addq_r14
    jmp     .rw_next
.rw_addq_r15:
    ; add r15, imm8 = 49 81 C7 imm32 (7 bytes) or 49 83 C7 imm8 (4 bytes)
    ; Use 49 83 C7 imm8 for small values
    mov     byte [rdi], 0x49
    mov     byte [rdi+1], 0x83
    mov     byte [rdi+2], 0xC7
    mov     al, r14b
    mov     [rdi+3], al
    ; NOP remaining 5 bytes
    mov     byte [rdi+4], 0x90
    mov     byte [rdi+5], 0x90
    mov     byte [rdi+6], 0x90
    mov     byte [rdi+7], 0x90
    mov     byte [rdi+8], 0x90
    add     r12, 9
    jmp     .rw_loop
.rw_addq_r14:
    ; add r14, imm8 = 49 83 C6 imm8
    mov     byte [rdi], 0x49
    mov     byte [rdi+1], 0x83
    mov     byte [rdi+2], 0xC6
    mov     al, r14b
    mov     [rdi+3], al
    mov     byte [rdi+4], 0x90
    mov     byte [rdi+5], 0x90
    mov     byte [rdi+6], 0x90
    mov     byte [rdi+7], 0x90
    mov     byte [rdi+8], 0x90
    add     r12, 9
    jmp     .rw_loop

.rw_next:
    inc     r12
    jmp     .rw_loop

.rw_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
