; ============================================================
; IR Record Emitter, Virtual Register & Label Allocator
; irgen/irgen.asm
; ============================================================

bits 64
default rel

%include "rex_defs.inc"
%include "rex_ir.inc"

section .bss

ir_buffer:      resb IR_BUF_SIZE
ir_idx:         resq 1
vreg_counter:   resd 1
label_counter:  resd 1
label_offsets:  resd LABEL_MAX
label_used:     resb LABEL_MAX

ir_cur_type:    resb 1
ir_cur_dst:     resw 1
ir_cur_src1:    resw 1
ir_cur_src2:    resw 1
ir_cur_imm:     resq 1
ir_cur_aux:     resq 1
ir_cur_flags:   resd 1

global ir_buffer, ir_idx
global ir_cur_type, ir_cur_dst, ir_cur_src1, ir_cur_src2
global ir_cur_imm, ir_cur_aux, ir_cur_flags

section .text

global ir_reset
global ir_alloc_vreg
global ir_alloc_label
global ir_emit_record
global ir_emit_nul
global ir_emit_load_imm
global ir_emit_load_var
global ir_emit_store_var
global ir_emit_binop
global ir_emit_unop
global ir_emit_cmp
global ir_emit_label
global ir_emit_jmp
global ir_emit_jcc
global ir_emit_call
global ir_emit_ret
global ir_emit_ret_void
global ir_emit_out_int
global ir_emit_out_float
global ir_emit_out_bool
global ir_emit_out_str
global ir_emit_out_complex
global ir_emit_halt
global ir_emit_swap
global ir_emit_inc
global ir_emit_dec
global ir_emit_load_str
global ir_emit_load_bool
global ir_emit_seq_alloc
global ir_emit_seq_push
global ir_emit_seq_pop
global ir_emit_seq_len
global ir_emit_seq_cap
global ir_emit_dict_new
global ir_emit_dict_set
global ir_emit_dict_get
global ir_emit_prot_entry
global ir_emit_prot_exit
global ir_emit_loop_top
global ir_emit_skip
global ir_emit_err
global ir_emit_mm_switch
global ir_emit_tzcnt
global ir_emit_lzcnt
global ir_emit_popcnt

; ============================================================
; ir_reset — Reset IR state to initial values
; ============================================================
ir_reset:
    mov qword [ir_idx], 0
    mov dword [vreg_counter], 1
    mov dword [label_counter], 0
    xor eax, eax
    lea rdi, [label_used]
    mov ecx, LABEL_MAX
    cld
    rep stosb
    ret

; ============================================================
; ir_alloc_vreg — Allocate next virtual register
; Returns: eax = vreg ID
; ============================================================
ir_alloc_vreg:
    mov eax, [vreg_counter]
    inc dword [vreg_counter]
    ret

; ============================================================
; ir_alloc_label — Allocate next label ID
; Returns: eax = label ID
; ============================================================
ir_alloc_label:
    mov eax, [label_counter]
    inc dword [label_counter]
    ret

; ============================================================
; ir_emit_record — Write 32-byte IR record to buffer
; Input: dil = opcode
; Uses scratch globals for all other fields
; ============================================================
ir_emit_record:
    movzx r8d, dil
    mov rax, [ir_idx]
    shl rax, 5
    lea rcx, [ir_buffer + rax]
    mov byte [rcx + IR_OFF_OPCODE], r8b
    movzx eax, byte [ir_cur_type]
    mov byte [rcx + IR_OFF_TYPE], al
    movzx eax, word [ir_cur_dst]
    mov word [rcx + IR_OFF_DST], ax
    movzx eax, word [ir_cur_src1]
    mov word [rcx + IR_OFF_SRC1], ax
    movzx eax, word [ir_cur_src2]
    mov word [rcx + IR_OFF_SRC2], ax
    mov rax, [ir_cur_imm]
    mov qword [rcx + IR_OFF_IMM], rax
    mov rax, [ir_cur_aux]
    mov qword [rcx + IR_OFF_AUX], rax
    mov eax, [ir_cur_flags]
    mov dword [rcx + IR_OFF_FLAGS], eax
    mov dword [rcx + IR_OFF_PAD], 0
    inc qword [ir_idx]
    ret

; ============================================================
; ir_emit_nul — Emit NOP
; ============================================================
ir_emit_nul:
    mov byte [ir_cur_type], 0
    mov word [ir_cur_dst], 0
    mov word [ir_cur_src1], 0
    mov word [ir_cur_src2], 0
    mov qword [ir_cur_imm], 0
    mov qword [ir_cur_aux], 0
    mov dword [ir_cur_flags], 0
    mov dil, IR_NOP
    jmp ir_emit_record

; ============================================================
; ir_emit_load_imm — dst = imm64
; Input: eax = dst, rdi = imm64
; ============================================================
ir_emit_load_imm:
    mov word [ir_cur_dst], ax
    mov [ir_cur_imm], rdi
    xor eax, eax
    mov byte [ir_cur_type], al
    mov word [ir_cur_src1], ax
    mov word [ir_cur_src2], ax
    mov [ir_cur_aux], rax
    mov [ir_cur_flags], eax
    mov dil, IR_LOAD_IMM
    jmp ir_emit_record

; ============================================================
; ir_emit_load_var — dst = var[var_idx]
; Input: eax = dst, edi = var_idx
; ============================================================
ir_emit_load_var:
    mov word [ir_cur_dst], ax
    mov word [ir_cur_src1], di
    xor eax, eax
    mov byte [ir_cur_type], al
    mov word [ir_cur_src2], ax
    mov [ir_cur_imm], rax
    mov [ir_cur_aux], rax
    mov [ir_cur_flags], eax
    mov dil, IR_LOAD_VAR
    jmp ir_emit_record

; ============================================================
; ir_emit_store_var — var[var_idx] = src1
; Input: esi = src1 (value), edi = var_idx
; ============================================================
ir_emit_store_var:
    mov word [ir_cur_src1], di
    mov word [ir_cur_src2], si
    xor eax, eax
    mov byte [ir_cur_type], al
    mov word [ir_cur_dst], ax
    mov [ir_cur_imm], rax
    mov [ir_cur_aux], rax
    mov [ir_cur_flags], eax
    mov dil, IR_STORE_VAR
    jmp ir_emit_record

; ============================================================
; ir_emit_binop — dst = src1 op src2
; Input: dil = opcode, eax = dst, esi = src1, edi = src2
; ============================================================
ir_emit_binop:
    movzx r8d, dil
    mov word [ir_cur_dst], ax
    mov word [ir_cur_src1], si
    mov word [ir_cur_src2], di
    xor eax, eax
    mov byte [ir_cur_type], al
    mov [ir_cur_imm], rax
    mov [ir_cur_aux], rax
    mov [ir_cur_flags], eax
    mov dil, r8b
    jmp ir_emit_record

; ============================================================
; ir_emit_unop — dst = op(src1)
; Input: dil = opcode, eax = dst, edi = src1
; ============================================================
ir_emit_unop:
    movzx r8d, dil
    mov word [ir_cur_dst], ax
    mov word [ir_cur_src1], di
    xor eax, eax
    mov byte [ir_cur_type], al
    mov word [ir_cur_src2], ax
    mov [ir_cur_imm], rax
    mov [ir_cur_aux], rax
    mov [ir_cur_flags], eax
    mov dil, r8b
    jmp ir_emit_record

; ============================================================
; ir_emit_cmp — Compare src1 vs src2
; Input: eax = dst, esi = src1, edi = src2, edx = cond_code
; ============================================================
ir_emit_cmp:
    mov word [ir_cur_dst], ax
    mov word [ir_cur_src1], si
    mov word [ir_cur_src2], di
    mov [ir_cur_aux], rdx
    xor eax, eax
    mov byte [ir_cur_type], al
    mov [ir_cur_imm], rax
    mov [ir_cur_flags], eax
    mov dil, IR_CMP
    jmp ir_emit_record

; ============================================================
; ir_emit_label — Define label
; Input: eax = label_id
; ============================================================
ir_emit_label:
    mov [ir_cur_imm], rax
    xor eax, eax
    mov byte [ir_cur_type], al
    mov word [ir_cur_dst], ax
    mov word [ir_cur_src1], ax
    mov word [ir_cur_src2], ax
    mov [ir_cur_aux], rax
    mov [ir_cur_flags], eax
    mov dil, IR_LABEL
    jmp ir_emit_record

; ============================================================
; ir_emit_jmp — Unconditional jump to label
; Input: eax = label_id
; ============================================================
ir_emit_jmp:
    mov [ir_cur_imm], rax
    xor eax, eax
    mov byte [ir_cur_type], al
    mov word [ir_cur_dst], ax
    mov word [ir_cur_src1], ax
    mov word [ir_cur_src2], ax
    mov [ir_cur_aux], rax
    mov [ir_cur_flags], eax
    mov dil, IR_JMP
    jmp ir_emit_record

; ============================================================
; ir_emit_jcc — Jump if src1_vreg is true
; Input: edi = src1_vreg, eax = label_id
; ============================================================
ir_emit_jcc:
    mov word [ir_cur_src1], di
    mov [ir_cur_imm], rax
    xor eax, eax
    mov byte [ir_cur_type], al
    mov word [ir_cur_dst], ax
    mov word [ir_cur_src2], ax
    mov [ir_cur_aux], rax
    mov [ir_cur_flags], eax
    mov dil, IR_JMP_TRUE
    jmp ir_emit_record

; ============================================================
; ir_emit_call — Call protocol
; Input: eax = dst, edi = proto_idx, esi = argcnt
; ============================================================
ir_emit_call:
    mov word [ir_cur_dst], ax
    mov word [ir_cur_src1], di
    mov [ir_cur_imm], rsi
    xor eax, eax
    mov byte [ir_cur_type], al
    mov word [ir_cur_src2], ax
    mov [ir_cur_aux], rax
    mov [ir_cur_flags], eax
    mov dil, IR_CALL
    jmp ir_emit_record

; ============================================================
; ir_emit_ret — Return src1_vreg
; Input: edi = src1_vreg
; ============================================================
ir_emit_ret:
    mov word [ir_cur_src1], di
    xor eax, eax
    mov byte [ir_cur_type], al
    mov word [ir_cur_dst], ax
    mov word [ir_cur_src2], ax
    mov [ir_cur_imm], rax
    mov [ir_cur_aux], rax
    mov [ir_cur_flags], eax
    mov dil, IR_RET
    jmp ir_emit_record

; ============================================================
; ir_emit_ret_void — Return void
; ============================================================
ir_emit_ret_void:
    mov byte [ir_cur_type], 0
    mov word [ir_cur_dst], 0
    mov word [ir_cur_src1], 0
    mov word [ir_cur_src2], 0
    mov qword [ir_cur_imm], 0
    mov qword [ir_cur_aux], 0
    mov dword [ir_cur_flags], 0
    mov dil, IR_RET
    jmp ir_emit_record

; ============================================================
; ir_emit_out_int — Output integer value
; Input: edi = src1_vreg
; ============================================================
ir_emit_out_int:
    mov word [ir_cur_src1], di
    mov byte [ir_cur_type], TYPE_INT
    xor eax, eax
    mov word [ir_cur_dst], ax
    mov word [ir_cur_src2], ax
    mov [ir_cur_imm], rax
    mov [ir_cur_aux], rax
    mov [ir_cur_flags], eax
    mov dil, IR_OUTPUT
    jmp ir_emit_record

; ============================================================
; ir_emit_out_float — Output float value
; Input: edi = src1_vreg
; ============================================================
ir_emit_out_float:
    mov word [ir_cur_src1], di
    mov byte [ir_cur_type], TYPE_FLOAT
    xor eax, eax
    mov word [ir_cur_dst], ax
    mov word [ir_cur_src2], ax
    mov [ir_cur_imm], rax
    mov [ir_cur_aux], rax
    mov [ir_cur_flags], eax
    mov dil, IR_OUTPUT
    jmp ir_emit_record

; ============================================================
; ir_emit_out_bool — Output boolean value
; Input: edi = src1_vreg
; ============================================================
ir_emit_out_bool:
    mov word [ir_cur_src1], di
    mov byte [ir_cur_type], TYPE_BOOL
    xor eax, eax
    mov word [ir_cur_dst], ax
    mov word [ir_cur_src2], ax
    mov [ir_cur_imm], rax
    mov [ir_cur_aux], rax
    mov [ir_cur_flags], eax
    mov dil, IR_OUTPUT
    jmp ir_emit_record

; ============================================================
; ir_emit_out_str — Output string value
; Input: edi = src1_vreg
; ============================================================
ir_emit_out_str:
    mov word [ir_cur_src1], di
    xor eax, eax
    mov byte [ir_cur_type], al
    mov word [ir_cur_dst], ax
    mov word [ir_cur_src2], ax
    mov [ir_cur_imm], rax
    mov [ir_cur_aux], rax
    mov [ir_cur_flags], eax
    mov dil, IR_OUTPUT_STR
    jmp ir_emit_record

; ============================================================
; ir_emit_out_complex — Output complex value
; Input: edi = src1_vreg
; ============================================================
ir_emit_out_complex:
    mov word [ir_cur_src1], di
    mov byte [ir_cur_type], TYPE_COMPLEX
    xor eax, eax
    mov word [ir_cur_dst], ax
    mov word [ir_cur_src2], ax
    mov [ir_cur_imm], rax
    mov [ir_cur_aux], rax
    mov [ir_cur_flags], eax
    mov dil, IR_OUTPUT
    jmp ir_emit_record

; ============================================================
; ir_emit_halt — Halt execution (placeholder)
; ============================================================
ir_emit_halt:
    mov byte [ir_cur_type], 0
    mov word [ir_cur_dst], 0
    mov word [ir_cur_src1], 0
    mov word [ir_cur_src2], 0
    mov qword [ir_cur_imm], 0
    mov qword [ir_cur_aux], 0
    mov dword [ir_cur_flags], 0
    mov dil, IR_NOP
    jmp ir_emit_record

; ============================================================
; ir_emit_swap — Swap two variables
; Input: edi = var1, esi = var2
; ============================================================
ir_emit_swap:
    mov word [ir_cur_src1], di
    mov word [ir_cur_src2], si
    xor eax, eax
    mov byte [ir_cur_type], al
    mov word [ir_cur_dst], ax
    mov [ir_cur_imm], rax
    mov [ir_cur_aux], rax
    mov [ir_cur_flags], eax
    mov dil, IR_SWAP
    jmp ir_emit_record

; ============================================================
; ir_emit_inc — dst = src1 + 1
; Input: eax = dst, edi = src1
; ============================================================
ir_emit_inc:
    mov word [ir_cur_dst], ax
    mov word [ir_cur_src1], di
    xor eax, eax
    mov byte [ir_cur_type], al
    mov word [ir_cur_src2], ax
    mov [ir_cur_imm], rax
    mov [ir_cur_aux], rax
    mov [ir_cur_flags], eax
    mov dil, IR_INC
    jmp ir_emit_record

; ============================================================
; ir_emit_dec — dst = src1 - 1
; Input: eax = dst, edi = src1
; ============================================================
ir_emit_dec:
    mov word [ir_cur_dst], ax
    mov word [ir_cur_src1], di
    xor eax, eax
    mov byte [ir_cur_type], al
    mov word [ir_cur_src2], ax
    mov [ir_cur_imm], rax
    mov [ir_cur_aux], rax
    mov [ir_cur_flags], eax
    mov dil, IR_DEC
    jmp ir_emit_record

; ============================================================
; ir_emit_load_str — Load string constant
; Input: eax = dst, rdi = str_ptr, rsi = str_len
; ============================================================
ir_emit_load_str:
    mov word [ir_cur_dst], ax
    mov [ir_cur_imm], rdi
    mov [ir_cur_aux], rsi
    xor eax, eax
    mov byte [ir_cur_type], al
    mov word [ir_cur_src1], ax
    mov word [ir_cur_src2], ax
    mov [ir_cur_flags], eax
    mov dil, IR_LOAD_STRING
    jmp ir_emit_record

; ============================================================
; ir_emit_load_bool — Load boolean value
; Input: eax = dst, edi = value (0 or 1)
; ============================================================
ir_emit_load_bool:
    mov word [ir_cur_dst], ax
    mov [ir_cur_imm], rdi
    xor eax, eax
    mov byte [ir_cur_type], al
    mov word [ir_cur_src1], ax
    mov word [ir_cur_src2], ax
    mov [ir_cur_aux], rax
    mov [ir_cur_flags], eax
    mov dil, IR_LOAD_BOOL
    jmp ir_emit_record

; ============================================================
; ir_emit_seq_alloc — Allocate new empty sequence
; ============================================================
ir_emit_seq_alloc:
    mov byte [ir_cur_type], 0
    mov word [ir_cur_dst], 0
    mov word [ir_cur_src1], 0
    mov word [ir_cur_src2], 0
    mov qword [ir_cur_imm], 0
    mov qword [ir_cur_aux], 0
    mov dword [ir_cur_flags], 0
    mov dil, IR_SEQ_NEW
    jmp ir_emit_record

; ============================================================
; ir_emit_seq_push — Append item to sequence
; Input: edi = seq_vreg, esi = item_vreg
; ============================================================
ir_emit_seq_push:
    mov word [ir_cur_src1], di
    mov word [ir_cur_src2], si
    xor eax, eax
    mov byte [ir_cur_type], al
    mov word [ir_cur_dst], ax
    mov [ir_cur_imm], rax
    mov [ir_cur_aux], rax
    mov [ir_cur_flags], eax
    mov dil, IR_SEQ_PUSH
    jmp ir_emit_record

; ============================================================
; ir_emit_seq_pop — Pop last item from sequence
; Input: eax = dst, edi = seq_vreg
; ============================================================
ir_emit_seq_pop:
    mov word [ir_cur_dst], ax
    mov word [ir_cur_src1], di
    xor eax, eax
    mov byte [ir_cur_type], al
    mov word [ir_cur_src2], ax
    mov [ir_cur_imm], rax
    mov [ir_cur_aux], rax
    mov [ir_cur_flags], eax
    mov dil, IR_SEQ_POP
    jmp ir_emit_record

; ============================================================
; ir_emit_seq_len — Get sequence length
; Input: eax = dst, edi = seq_vreg
; ============================================================
ir_emit_seq_len:
    mov word [ir_cur_dst], ax
    mov word [ir_cur_src1], di
    xor eax, eax
    mov byte [ir_cur_type], al
    mov word [ir_cur_src2], ax
    mov [ir_cur_imm], rax
    mov [ir_cur_aux], rax
    mov [ir_cur_flags], eax
    mov dil, IR_SEQ_LEN
    jmp ir_emit_record

; ============================================================
; ir_emit_seq_cap — Get sequence capacity (placeholder)
; ============================================================
ir_emit_seq_cap:
    mov byte [ir_cur_type], 0
    mov word [ir_cur_dst], 0
    mov word [ir_cur_src1], 0
    mov word [ir_cur_src2], 0
    mov qword [ir_cur_imm], 0
    mov qword [ir_cur_aux], 0
    mov dword [ir_cur_flags], 0
    mov dil, IR_NOP
    jmp ir_emit_record

; ============================================================
; ir_emit_dict_new — Allocate new empty dictionary
; ============================================================
ir_emit_dict_new:
    mov byte [ir_cur_type], 0
    mov word [ir_cur_dst], 0
    mov word [ir_cur_src1], 0
    mov word [ir_cur_src2], 0
    mov qword [ir_cur_imm], 0
    mov qword [ir_cur_aux], 0
    mov dword [ir_cur_flags], 0
    mov dil, IR_DICT_NEW
    jmp ir_emit_record

; ============================================================
; ir_emit_dict_set — Set dictionary key-value pair
; Input: edi = dict_vreg, esi = key_vreg, edx = val_vreg
; ============================================================
ir_emit_dict_set:
    mov word [ir_cur_src1], di
    mov word [ir_cur_src2], si
    mov [ir_cur_aux], rdx
    xor eax, eax
    mov byte [ir_cur_type], al
    mov word [ir_cur_dst], ax
    mov [ir_cur_imm], rax
    mov [ir_cur_flags], eax
    mov dil, IR_DICT_SET
    jmp ir_emit_record

; ============================================================
; ir_emit_dict_get — Get dictionary value by key
; Input: eax = dst, edi = dict_vreg, esi = key_vreg
; ============================================================
ir_emit_dict_get:
    mov word [ir_cur_dst], ax
    mov word [ir_cur_src1], di
    mov word [ir_cur_src2], si
    xor eax, eax
    mov byte [ir_cur_type], al
    mov [ir_cur_imm], rax
    mov [ir_cur_aux], rax
    mov [ir_cur_flags], eax
    mov dil, IR_DICT_GET
    jmp ir_emit_record

; ============================================================
; ir_emit_prot_entry — Begin protocol definition
; Input: edi = proto_idx
; ============================================================
ir_emit_prot_entry:
    mov [ir_cur_imm], rdi
    xor eax, eax
    mov byte [ir_cur_type], al
    mov word [ir_cur_dst], ax
    mov word [ir_cur_src1], ax
    mov word [ir_cur_src2], ax
    mov [ir_cur_aux], rax
    mov [ir_cur_flags], eax
    mov dil, IR_PROTO_BEGIN
    jmp ir_emit_record

; ============================================================
; ir_emit_prot_exit — End protocol definition
; ============================================================
ir_emit_prot_exit:
    mov byte [ir_cur_type], 0
    mov word [ir_cur_dst], 0
    mov word [ir_cur_src1], 0
    mov word [ir_cur_src2], 0
    mov qword [ir_cur_imm], 0
    mov qword [ir_cur_aux], 0
    mov dword [ir_cur_flags], 0
    mov dil, IR_PROTO_END
    jmp ir_emit_record

; ============================================================
; ir_emit_loop_top — Define loop top label
; Input: eax = label_id
; ============================================================
ir_emit_loop_top:
    mov [ir_cur_imm], rax
    xor eax, eax
    mov byte [ir_cur_type], al
    mov word [ir_cur_dst], ax
    mov word [ir_cur_src1], ax
    mov word [ir_cur_src2], ax
    mov [ir_cur_aux], rax
    mov [ir_cur_flags], eax
    mov dil, IR_LABEL
    jmp ir_emit_record

; ============================================================
; ir_emit_skip — Skip (jump forward by depth)
; Input: edi = depth
; ============================================================
ir_emit_skip:
    mov [ir_cur_imm], rdi
    xor eax, eax
    mov byte [ir_cur_type], al
    mov word [ir_cur_dst], ax
    mov word [ir_cur_src1], ax
    mov word [ir_cur_src2], ax
    mov [ir_cur_aux], rax
    mov [ir_cur_flags], eax
    mov dil, IR_JMP
    jmp ir_emit_record

; ============================================================
; ir_emit_err — Raise error
; Input: edi = src1_vreg
; ============================================================
ir_emit_err:
    mov word [ir_cur_src1], di
    xor eax, eax
    mov byte [ir_cur_type], al
    mov word [ir_cur_dst], ax
    mov word [ir_cur_src2], ax
    mov [ir_cur_imm], rax
    mov [ir_cur_aux], rax
    mov [ir_cur_flags], eax
    mov dil, IR_RAISE
    jmp ir_emit_record

; ============================================================
; ir_emit_mm_switch — Memory management mode switch
; Input: edi = mode
; ============================================================
ir_emit_mm_switch:
    mov word [ir_cur_src1], di
    xor eax, eax
    mov byte [ir_cur_type], al
    mov word [ir_cur_dst], ax
    mov word [ir_cur_src2], ax
    mov [ir_cur_imm], rax
    mov [ir_cur_aux], rax
    mov [ir_cur_flags], eax
    mov dil, IR_NOP
    jmp ir_emit_record

; ============================================================
; ir_emit_tzcnt — dst = tzcnt(src1)
; Input: eax = dst, edi = src1
; ============================================================
ir_emit_tzcnt:
    mov word [ir_cur_dst], ax
    mov word [ir_cur_src1], di
    xor eax, eax
    mov byte [ir_cur_type], al
    mov word [ir_cur_src2], ax
    mov [ir_cur_imm], rax
    mov [ir_cur_aux], rax
    mov [ir_cur_flags], eax
    mov dil, IR_TZCNT
    jmp ir_emit_record

; ============================================================
; ir_emit_lzcnt — dst = lzcnt(src1)
; Input: eax = dst, edi = src1
; ============================================================
ir_emit_lzcnt:
    mov word [ir_cur_dst], ax
    mov word [ir_cur_src1], di
    xor eax, eax
    mov byte [ir_cur_type], al
    mov word [ir_cur_src2], ax
    mov [ir_cur_imm], rax
    mov [ir_cur_aux], rax
    mov [ir_cur_flags], eax
    mov dil, IR_LZCNT
    jmp ir_emit_record

; ============================================================
; ir_emit_popcnt — dst = popcount(src1)
; Input: eax = dst, edi = src1
; ============================================================
ir_emit_popcnt:
    mov word [ir_cur_dst], ax
    mov word [ir_cur_src1], di
    xor eax, eax
    mov byte [ir_cur_type], al
    mov word [ir_cur_src2], ax
    mov [ir_cur_imm], rax
    mov [ir_cur_aux], rax
    mov [ir_cur_flags], eax
    mov dil, IR_POPCOUNT
    jmp ir_emit_record
