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

    ; Unknown opcode: skip
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
; ============================================================
.op_load_imm:
    mov     rdi, [r13 + IR_OFF_IMM]
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
    inc     r12
    jmp     .p2

; ============================================================
; IR_STORE_VAR: mov [VAR_STORAGE_BASE + var_idx*64], rax
; 48 89 04 25 <addr32>
; ============================================================
.op_store_var:
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
    inc     r12
    jmp     .p2

; ============================================================
; IR_ADD: pop rbx; add rax, rbx (5B 48 01 D8)
; ============================================================
.op_add:
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
; IR_MUL: pop rbx; imul rax, rbx (5B 48 0F AF C3)
; ============================================================
.op_mul:
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
; Stub: treat same as DIV for now
; ============================================================
.op_idiv:
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
    mov     r11d, eax

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
    mov     eax, r11d
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
; IR_SEQ_PUSH / IR_SEQ_POP / IR_SEQ_GET / IR_SEQ_SET — stubs
; ============================================================
.op_seq_push:
.op_seq_pop:
.op_seq_get:
.op_seq_set:
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
; IR_DICT_SET / IR_DICT_GET — stubs
; ============================================================
.op_dict_set:
.op_dict_get:
    inc     r12
    jmp     .p2

; ============================================================
; IR_ABS / IR_SIGN / IR_RAISE — stubs
; ============================================================
.op_abs:
.op_sign:
.op_raise:
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
; IR_LEN: stub
; ============================================================
.op_len:
    inc     r12
    jmp     .p2

; ============================================================
; IR_CONCAT: stub
; ============================================================
.op_concat:
    inc     r12
    jmp     .p2

; ============================================================
; IR_TYPEOF: stub
; ============================================================
.op_typeof:
    inc     r12
    jmp     .p2

; ============================================================
; IR_INPUT: stub
; ============================================================
.op_input:
    inc     r12
    jmp     .p2

; ============================================================
; IR_ASSERT: stub
; ============================================================
.op_assert:
    inc     r12
    jmp     .p2

; ============================================================
; IR_CLOCK: stub
; ============================================================
.op_clock:
    inc     r12
    jmp     .p2

; ============================================================
; IR_LOAD_GLOBAL / IR_STORE_GLOBAL — stubs
; ============================================================
.op_load_global:
.op_store_global:
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
    je      .est_5
    cmp     al, IR_DIV
    je      .est_6
    cmp     al, IR_MOD
    je      .est_9
    cmp     al, IR_IDIV
    je      .est_6
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
.est_13:
    add     qword [out_idx], 13
    ret
.est_15:
    add     qword [out_idx], 15
    ret
.est_24:
    add     qword [out_idx], 24
    ret
.est_25:
    add     qword [out_idx], 25
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
