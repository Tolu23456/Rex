; ============================================================
; IR Codegen Wrappers — irgen/ir_codegen_wrap.asm
; Presents the same API as old codegen_emit_* functions.
; Emits IR records to ir_buffer AND delegates to old codegen
; for x86 emission to out_buffer.
; ============================================================
bits 64
default rel

%include "rex_defs.inc"
%include "rex_ir.inc"

; ---- externs: IR infrastructure ----
extern ir_alloc_vreg, ir_alloc_label
extern ir_emit_record
extern ir_buffer, ir_idx

; ---- externs: IR emit helpers ----
extern ir_cur_type, ir_cur_dst, ir_cur_src1, ir_cur_src2
extern ir_cur_imm, ir_cur_aux, ir_cur_flags

; ---- externs: old codegen (renamed) ----
extern codegen_emit_orig_mov_rax_imm64
extern codegen_emit_orig_mov_rax_imm32
extern codegen_emit_orig_mov_rax_var
extern codegen_emit_orig_store_rax_to_var
extern codegen_emit_orig_push_rax
extern codegen_emit_orig_pop_rbx
extern codegen_emit_orig_mov_rbx_rax
extern codegen_emit_orig_mov_rdi_rax
extern codegen_emit_orig_movdi_rax
extern codegen_emit_orig_mov_rax_rdi
extern codegen_emit_orig_mov_rdi_rbx
extern codegen_emit_orig_mov_rsi_rax
extern codegen_emit_orig_xor_rdi_rdi
extern codegen_emit_orig_add_rax_rbx
extern codegen_emit_orig_sub_rax_rbx
extern codegen_emit_orig_imul_rax_rbx
extern codegen_emit_orig_idiv_rbx_by_rax
extern codegen_emit_orig_imod_rbx_by_rax
extern codegen_emit_orig_neg_rax
extern codegen_emit_orig_bitwise_and
extern codegen_emit_orig_bitwise_or
extern codegen_emit_orig_bitwise_xor
extern codegen_emit_orig_bitwise_not
extern codegen_emit_orig_shl
extern codegen_emit_orig_shr
extern codegen_emit_orig_and_bool
extern codegen_emit_orig_or_bool
extern codegen_emit_orig_not_rax
extern codegen_emit_orig_cmp_setcc
extern codegen_emit_orig_test_jz
extern codegen_emit_orig_jmp_end
extern codegen_emit_orig_test_jnz
extern codegen_emit_orig_call_rt_pri
extern codegen_emit_orig_call_rt_prs
extern codegen_emit_orig_call_rt_prb
extern codegen_emit_orig_call_rt_prf
extern codegen_emit_orig_call_rt_prc
extern codegen_emit_orig_call_rt_err
extern codegen_output_orig_typed
extern codegen_output_orig_rax
extern codegen_emit_orig_for_start
extern codegen_emit_orig_for_end
extern codegen_emit_orig_for_start_dyn
extern codegen_emit_orig_while_start
extern codegen_emit_orig_while_end
extern codegen_emit_orig_break
extern codegen_emit_orig_break_n
extern codegen_emit_orig_skip
extern codegen_emit_orig_exit0
extern codegen_emit_orig_exit1
extern codegen_emit_orig_str_rax
extern codegen_emit_orig_call_prot
extern codegen_emit_orig_prot_start
extern codegen_emit_orig_prot_end
extern codegen_emit_orig_leave_placeholder
extern codegen_emit_orig_seq_alloc
extern codegen_emit_orig_seq_push
extern codegen_emit_orig_seq_pop
extern codegen_emit_orig_seq_len
extern codegen_emit_orig_seq_cap
extern codegen_emit_orig_seq_subscript
extern codegen_emit_orig_seq_in
extern codegen_emit_orig_seq_contains
extern codegen_emit_orig_seq_sum
extern codegen_emit_orig_seq_min
extern codegen_emit_orig_seq_max
extern codegen_emit_orig_seq_sort
extern codegen_emit_orig_seq_reverse
extern codegen_emit_orig_inc_var
extern codegen_emit_orig_dec_var
extern codegen_emit_orig_swap_vars
extern codegen_emit_orig_neg_var
extern codegen_emit_orig_abs_rax
extern codegen_emit_orig_typeof_rax
extern codegen_emit_orig_cvttsd2si_rax
extern codegen_emit_orig_cvtsi2sd_rax
extern codegen_emit_orig_float_op
extern codegen_emit_orig_mov_rdi_var
extern codegen_emit_orig_unknown_bool
extern codegen_emit_orig_rdrand_rax
extern codegen_emit_orig_clock_ms
extern codegen_emit_orig_call_rt_str
extern codegen_emit_orig_call_rt_str_bool
extern codegen_emit_orig_call_rt_inp
extern codegen_emit_orig_int_to_bool
extern codegen_emit_orig_trunc_byte
extern codegen_emit_orig_int_min
extern codegen_emit_orig_int_max
extern codegen_emit_orig_int_pow
extern codegen_emit_orig_int_popcount
extern codegen_emit_orig_int_to_bin
extern codegen_emit_orig_int_to_hex
extern codegen_emit_orig_int_to_oct
extern codegen_emit_orig_float_sqrt
; float_abs not defined in codegen — stub only
extern codegen_emit_orig_bool_is_true
extern codegen_emit_orig_bool_is_false
extern codegen_emit_orig_bool_is_neutral
extern codegen_emit_orig_bool_is_decided
extern codegen_emit_orig_bool_flip
extern codegen_emit_orig_char_is_alpha
extern codegen_emit_orig_char_is_digit
extern codegen_emit_orig_char_is_upper
extern codegen_emit_orig_char_is_lower
extern codegen_emit_orig_char_to_upper
extern codegen_emit_orig_char_to_lower
extern codegen_emit_orig_char_to_int
extern codegen_emit_orig_char_to_str
extern codegen_emit_orig_byte_popcount
extern codegen_emit_orig_byte_to_int
extern codegen_emit_orig_byte_to_hex
extern codegen_emit_orig_byte_to_bin
extern codegen_emit_orig_byte_is_zero
extern codegen_emit_orig_byte_is_ascii
extern codegen_emit_orig_file_open
extern codegen_emit_orig_file_read
extern codegen_emit_orig_file_write
extern codegen_emit_orig_file_close
extern codegen_emit_orig_str_upper
extern codegen_emit_orig_str_lower
extern codegen_emit_orig_str_trim
extern codegen_emit_orig_str_contains
extern codegen_emit_orig_call_rt_str_len
extern codegen_emit_orig_call_rt_str_cat
extern codegen_emit_orig_sign_rax
extern codegen_emit_orig_clz_rax
extern codegen_emit_orig_ceil_rax
extern codegen_emit_orig_floor_rax
extern codegen_emit_orig_fract_rax
extern codegen_emit_orig_rdrand64
extern codegen_emit_orig_hash_rax
extern codegen_emit_orig_carry_rax
extern codegen_emit_orig_overflow_rax

section .text

; ============================================================
; Helper: emit_ir_nul — emit IR_NOP record to ir_buffer
; ============================================================
emit_ir_nul:
    push    rdi
    mov     byte [ir_cur_type], 0
    xor     eax, eax
    mov     word [ir_cur_dst], ax
    mov     word [ir_cur_src1], ax
    mov     word [ir_cur_src2], ax
    mov     qword [ir_cur_imm], rax
    mov     qword [ir_cur_aux], rax
    mov     dword [ir_cur_flags], eax
    mov     dil, IR_NOP
    call    ir_emit_record
    pop     rdi
    ret

; ============================================================
; CORE OPERATIONS — emit IR record + delegate to old codegen
; ============================================================

; --- codegen_emit_mov_rax_imm64(rdi=imm64) ---
global codegen_emit_mov_rax_imm64
codegen_emit_mov_rax_imm64:
    push    rdi
    mov     byte [ir_cur_type], 0
    xor     eax, eax
    mov     word [ir_cur_dst], ax
    mov     word [ir_cur_src1], ax
    mov     word [ir_cur_src2], ax
    mov     [ir_cur_imm], rdi
    mov     qword [ir_cur_aux], rax
    mov     dword [ir_cur_flags], eax
    mov     dil, IR_LOAD_IMM
    call    ir_emit_record
    pop     rdi
    jmp     codegen_emit_orig_mov_rax_imm64

; --- codegen_emit_mov_rax_imm32(rdi=imm32) ---
global codegen_emit_mov_rax_imm32
codegen_emit_mov_rax_imm32:
    push    rdi
    mov     byte [ir_cur_type], 0
    xor     eax, eax
    mov     word [ir_cur_dst], ax
    mov     word [ir_cur_src1], ax
    mov     word [ir_cur_src2], ax
    mov     [ir_cur_imm], rdi
    mov     qword [ir_cur_aux], rax
    mov     dword [ir_cur_flags], eax
    mov     dil, IR_LOAD_IMM
    call    ir_emit_record
    pop     rdi
    jmp     codegen_emit_orig_mov_rax_imm32

; --- codegen_emit_mov_rax_var(rdi=var_va) ---
global codegen_emit_mov_rax_var
codegen_emit_mov_rax_var:
    push    rdi
    mov     byte [ir_cur_type], 0
    xor     eax, eax
    mov     word [ir_cur_dst], ax
    mov     word [ir_cur_src1], ax
    mov     word [ir_cur_src2], ax
    mov     [ir_cur_imm], rdi
    mov     qword [ir_cur_aux], rax
    mov     dword [ir_cur_flags], eax
    mov     dil, IR_LOAD_VAR
    call    ir_emit_record
    pop     rdi
    jmp     codegen_emit_orig_mov_rax_var

; --- codegen_emit_store_rax_to_var(rdi=var_va) ---
global codegen_emit_store_rax_to_var
codegen_emit_store_rax_to_var:
    push    rdi
    mov     byte [ir_cur_type], 0
    xor     eax, eax
    mov     word [ir_cur_dst], ax
    mov     word [ir_cur_src1], ax
    mov     word [ir_cur_src2], ax
    mov     [ir_cur_imm], rdi
    mov     qword [ir_cur_aux], rax
    mov     dword [ir_cur_flags], eax
    mov     dil, IR_STORE_VAR
    call    ir_emit_record
    pop     rdi
    jmp     codegen_emit_orig_store_rax_to_var

; --- codegen_emit_push_rax() ---
global codegen_emit_push_rax
codegen_emit_push_rax:
    call    emit_ir_nul
    jmp     codegen_emit_orig_push_rax

; --- codegen_emit_pop_rbx() ---
global codegen_emit_pop_rbx
codegen_emit_pop_rbx:
    call    emit_ir_nul
    jmp     codegen_emit_orig_pop_rbx

; --- codegen_emit_mov_rbx_rax() ---
global codegen_emit_mov_rbx_rax
codegen_emit_mov_rbx_rax:
    call    emit_ir_nul
    jmp     codegen_emit_orig_mov_rbx_rax

; --- codegen_emit_add_rax_rbx() ---
global codegen_emit_add_rax_rbx
codegen_emit_add_rax_rbx:
    push    rdi
    mov     byte [ir_cur_type], 0
    xor     eax, eax
    mov     word [ir_cur_dst], ax
    mov     word [ir_cur_src1], ax
    mov     word [ir_cur_src2], ax
    mov     qword [ir_cur_imm], rax
    mov     qword [ir_cur_aux], rax
    mov     dword [ir_cur_flags], eax
    mov     dil, IR_ADD
    call    ir_emit_record
    pop     rdi
    jmp     codegen_emit_orig_add_rax_rbx

; --- codegen_emit_sub_rax_rbx() ---
global codegen_emit_sub_rax_rbx
codegen_emit_sub_rax_rbx:
    push    rdi
    mov     byte [ir_cur_type], 0
    xor     eax, eax
    mov     word [ir_cur_dst], ax
    mov     word [ir_cur_src1], ax
    mov     word [ir_cur_src2], ax
    mov     qword [ir_cur_imm], rax
    mov     qword [ir_cur_aux], rax
    mov     dword [ir_cur_flags], eax
    mov     dil, IR_SUB
    call    ir_emit_record
    pop     rdi
    jmp     codegen_emit_orig_sub_rax_rbx

; --- codegen_emit_imul_rax_rbx() ---
global codegen_emit_imul_rax_rbx
codegen_emit_imul_rax_rbx:
    push    rdi
    mov     byte [ir_cur_type], 0
    xor     eax, eax
    mov     word [ir_cur_dst], ax
    mov     word [ir_cur_src1], ax
    mov     word [ir_cur_src2], ax
    mov     qword [ir_cur_imm], rax
    mov     qword [ir_cur_aux], rax
    mov     dword [ir_cur_flags], eax
    mov     dil, IR_MUL
    call    ir_emit_record
    pop     rdi
    jmp     codegen_emit_orig_imul_rax_rbx

; --- codegen_emit_neg_rax() ---
global codegen_emit_neg_rax
codegen_emit_neg_rax:
    push    rdi
    mov     byte [ir_cur_type], 0
    xor     eax, eax
    mov     word [ir_cur_dst], ax
    mov     word [ir_cur_src1], ax
    mov     word [ir_cur_src2], ax
    mov     qword [ir_cur_imm], rax
    mov     qword [ir_cur_aux], rax
    mov     dword [ir_cur_flags], eax
    mov     dil, IR_NEG
    call    ir_emit_record
    pop     rdi
    jmp     codegen_emit_orig_neg_rax

; --- codegen_emit_cmp_setcc(rdi=setcc_byte) ---
global codegen_emit_cmp_setcc
codegen_emit_cmp_setcc:
    push    rdi
    mov     byte [ir_cur_type], 0
    xor     eax, eax
    mov     word [ir_cur_dst], ax
    mov     word [ir_cur_src1], ax
    mov     word [ir_cur_src2], ax
    mov     qword [ir_cur_imm], rax
    mov     [ir_cur_aux], rdi
    mov     dword [ir_cur_flags], eax
    mov     dil, IR_CMP
    call    ir_emit_record
    pop     rdi
    jmp     codegen_emit_orig_cmp_setcc

; --- codegen_output_typed(rdi=type, rax=value) ---
global codegen_output_typed
codegen_output_typed:
    push    rdi
    push    rax
    mov     [ir_cur_type], dil
    xor     eax, eax
    mov     word [ir_cur_dst], ax
    mov     word [ir_cur_src1], ax
    mov     word [ir_cur_src2], ax
    mov     qword [ir_cur_imm], rax
    mov     qword [ir_cur_aux], rax
    mov     dword [ir_cur_flags], eax
    mov     dil, IR_OUTPUT
    call    ir_emit_record
    pop     rax
    pop     rdi
    jmp     codegen_output_orig_typed

; --- codegen_output_rax() ---
global codegen_output_rax
codegen_output_rax:
    push    rdi
    push    rax
    mov     byte [ir_cur_type], 0
    xor     eax, eax
    mov     word [ir_cur_dst], ax
    mov     word [ir_cur_src1], ax
    mov     word [ir_cur_src2], ax
    mov     qword [ir_cur_imm], rax
    mov     qword [ir_cur_aux], rax
    mov     dword [ir_cur_flags], eax
    mov     dil, IR_OUTPUT
    call    ir_emit_record
    pop     rax
    pop     rdi
    jmp     codegen_output_orig_rax

; --- codegen_emit_test_jz() ---
global codegen_emit_test_jz
codegen_emit_test_jz:
    push    rdi
    mov     byte [ir_cur_type], 0
    xor     eax, eax
    mov     word [ir_cur_dst], ax
    mov     word [ir_cur_src1], ax
    mov     word [ir_cur_src2], ax
    mov     qword [ir_cur_imm], rax
    mov     qword [ir_cur_aux], rax
    mov     dword [ir_cur_flags], eax
    mov     dil, IR_TEST
    call    ir_emit_record
    pop     rdi
    jmp     codegen_emit_orig_test_jz

; --- codegen_emit_jmp_end() ---
global codegen_emit_jmp_end
codegen_emit_jmp_end:
    call    emit_ir_nul
    jmp     codegen_emit_orig_jmp_end

; --- codegen_emit_test_jnz() ---
global codegen_emit_test_jnz
codegen_emit_test_jnz:
    push    rdi
    mov     byte [ir_cur_type], 0
    xor     eax, eax
    mov     word [ir_cur_dst], ax
    mov     word [ir_cur_src1], ax
    mov     word [ir_cur_src2], ax
    mov     qword [ir_cur_imm], rax
    mov     qword [ir_cur_aux], rax
    mov     dword [ir_cur_flags], eax
    mov     dil, IR_TEST
    call    ir_emit_record
    pop     rdi
    jmp     codegen_emit_orig_test_jnz

; --- codegen_emit_exit0() ---
global codegen_emit_exit0
codegen_emit_exit0:
    push    rdi
    mov     byte [ir_cur_type], 0
    xor     eax, eax
    mov     word [ir_cur_dst], ax
    mov     word [ir_cur_src1], ax
    mov     word [ir_cur_src2], ax
    mov     qword [ir_cur_imm], rax
    mov     qword [ir_cur_aux], rax
    mov     dword [ir_cur_flags], eax
    mov     dil, IR_NOP
    call    ir_emit_record
    pop     rdi
    jmp     codegen_emit_orig_exit0

; --- codegen_emit_exit1() ---
global codegen_emit_exit1
codegen_emit_exit1:
    call    emit_ir_nul
    jmp     codegen_emit_orig_exit1

; --- codegen_emit_for_start(rdi, rsi, rdx) ---
global codegen_emit_for_start
codegen_emit_for_start:
    call    emit_ir_nul
    jmp     codegen_emit_orig_for_start

; --- codegen_emit_for_end(rdi, rsi, rdx) ---
global codegen_emit_for_end
codegen_emit_for_end:
    call    emit_ir_nul
    jmp     codegen_emit_orig_for_end

; --- codegen_emit_for_start_dyn(rdi, rsi, rdx) ---
global codegen_emit_for_start_dyn
codegen_emit_for_start_dyn:
    call    emit_ir_nul
    jmp     codegen_emit_orig_for_start_dyn

; --- codegen_emit_while_start() ---
global codegen_emit_while_start
codegen_emit_while_start:
    call    emit_ir_nul
    jmp     codegen_emit_orig_while_start

; --- codegen_emit_while_end(rdi, rsi) ---
global codegen_emit_while_end
codegen_emit_while_end:
    call    emit_ir_nul
    jmp     codegen_emit_orig_while_end

; --- codegen_emit_break() ---
global codegen_emit_break
codegen_emit_break:
    push    rdi
    mov     byte [ir_cur_type], 0
    xor     eax, eax
    mov     word [ir_cur_dst], ax
    mov     word [ir_cur_src1], ax
    mov     word [ir_cur_src2], ax
    mov     qword [ir_cur_imm], rax
    mov     qword [ir_cur_aux], rax
    mov     dword [ir_cur_flags], eax
    mov     dil, IR_JMP
    call    ir_emit_record
    pop     rdi
    jmp     codegen_emit_orig_break

; --- codegen_emit_break_n(rdi=N) ---
global codegen_emit_break_n
codegen_emit_break_n:
    push    rdi
    mov     byte [ir_cur_type], 0
    xor     eax, eax
    mov     word [ir_cur_dst], ax
    mov     word [ir_cur_src1], ax
    mov     word [ir_cur_src2], ax
    mov     qword [ir_cur_imm], rax
    mov     qword [ir_cur_aux], rax
    mov     dword [ir_cur_flags], eax
    mov     dil, IR_JMP
    call    ir_emit_record
    pop     rdi
    jmp     codegen_emit_orig_break_n

; --- codegen_emit_skip() ---
global codegen_emit_skip
codegen_emit_skip:
    call    emit_ir_nul
    jmp     codegen_emit_orig_skip

; --- codegen_emit_call_prot(rdi=proto_idx) ---
global codegen_emit_call_prot
codegen_emit_call_prot:
    push    rdi
    mov     byte [ir_cur_type], 0
    xor     eax, eax
    mov     word [ir_cur_dst], ax
    mov     word [ir_cur_src1], di
    mov     word [ir_cur_src2], ax
    mov     qword [ir_cur_imm], rax
    mov     qword [ir_cur_aux], rax
    mov     dword [ir_cur_flags], eax
    mov     dil, IR_CALL
    call    ir_emit_record
    pop     rdi
    jmp     codegen_emit_orig_call_prot

; --- codegen_emit_prot_start(rdi, rsi) ---
global codegen_emit_prot_start
codegen_emit_prot_start:
    push    rdi
    mov     byte [ir_cur_type], 0
    xor     eax, eax
    mov     word [ir_cur_dst], ax
    mov     word [ir_cur_src1], ax
    mov     word [ir_cur_src2], ax
    mov     [ir_cur_imm], rdi
    mov     qword [ir_cur_aux], rax
    mov     dword [ir_cur_flags], eax
    mov     dil, IR_PROTO_BEGIN
    call    ir_emit_record
    pop     rdi
    jmp     codegen_emit_orig_prot_start

; --- codegen_emit_prot_end() ---
global codegen_emit_prot_end
codegen_emit_prot_end:
    push    rdi
    mov     byte [ir_cur_type], 0
    xor     eax, eax
    mov     word [ir_cur_dst], ax
    mov     word [ir_cur_src1], ax
    mov     word [ir_cur_src2], ax
    mov     qword [ir_cur_imm], rax
    mov     qword [ir_cur_aux], rax
    mov     dword [ir_cur_flags], eax
    mov     dil, IR_PROTO_END
    call    ir_emit_record
    pop     rdi
    jmp     codegen_emit_orig_prot_end

; --- codegen_emit_leave_placeholder() ---
global codegen_emit_leave_placeholder
codegen_emit_leave_placeholder:
    call    emit_ir_nul
    jmp     codegen_emit_orig_leave_placeholder

; --- codegen_emit_str_rax(rdi=string_ptr) ---
global codegen_emit_str_rax
codegen_emit_str_rax:
    push    rdi
    mov     byte [ir_cur_type], 0
    xor     eax, eax
    mov     word [ir_cur_dst], ax
    mov     word [ir_cur_src1], ax
    mov     word [ir_cur_src2], ax
    mov     [ir_cur_imm], rdi
    mov     qword [ir_cur_aux], rax
    mov     dword [ir_cur_flags], eax
    mov     dil, IR_LOAD_STRING
    call    ir_emit_record
    pop     rdi
    jmp     codegen_emit_orig_str_rax

; --- codegen_emit_neg_var(rdi=var_va) ---
global codegen_emit_neg_var
codegen_emit_neg_var:
    call    emit_ir_nul
    jmp     codegen_emit_orig_neg_var

; ============================================================
; PASS-THROUGH WRAPPERS — emit IR_NOP + delegate to old codegen
; For operations without specific IR equivalents
; ============================================================
%macro WRAP_PASS 1
global codegen_emit_%1
codegen_emit_%1:
    push    rdi
    call    emit_ir_nul
    pop     rdi
    jmp     codegen_emit_orig_%1
%endmacro

WRAP_PASS mov_rdi_rax
WRAP_PASS movdi_rax
WRAP_PASS mov_rdi_rbx
WRAP_PASS mov_rsi_rax
WRAP_PASS xor_rdi_rdi
WRAP_PASS idiv_rbx_by_rax
WRAP_PASS imod_rbx_by_rax
WRAP_PASS bitwise_and
WRAP_PASS bitwise_or
WRAP_PASS bitwise_xor
WRAP_PASS bitwise_not
WRAP_PASS shl
WRAP_PASS shr
WRAP_PASS and_bool
WRAP_PASS or_bool
WRAP_PASS not_rax
WRAP_PASS call_rt_pri
WRAP_PASS call_rt_prs
WRAP_PASS call_rt_prb
WRAP_PASS call_rt_prf
WRAP_PASS call_rt_prc
WRAP_PASS call_rt_err
WRAP_PASS abs_rax
WRAP_PASS typeof_rax
WRAP_PASS cvttsd2si_rax
WRAP_PASS cvtsi2sd_rax
WRAP_PASS float_op
WRAP_PASS mov_rdi_var
WRAP_PASS unknown_bool
WRAP_PASS rdrand_rax
WRAP_PASS clock_ms
WRAP_PASS call_rt_str
WRAP_PASS call_rt_str_bool
WRAP_PASS call_rt_inp
WRAP_PASS int_to_bool
WRAP_PASS trunc_byte
WRAP_PASS int_min
WRAP_PASS int_max
WRAP_PASS int_pow
WRAP_PASS int_popcount
WRAP_PASS int_to_bin
WRAP_PASS int_to_hex
WRAP_PASS int_to_oct
WRAP_PASS float_sqrt
; WRAP_PASS float_abs — not defined in codegen
WRAP_PASS bool_is_true
WRAP_PASS bool_is_false
WRAP_PASS bool_is_neutral
WRAP_PASS bool_is_decided
WRAP_PASS bool_flip
WRAP_PASS char_is_alpha
WRAP_PASS char_is_digit
WRAP_PASS char_is_upper
WRAP_PASS char_is_lower
WRAP_PASS char_to_upper
WRAP_PASS char_to_lower
WRAP_PASS char_to_int
WRAP_PASS char_to_str
WRAP_PASS byte_popcount
WRAP_PASS byte_to_int
WRAP_PASS byte_to_hex
WRAP_PASS byte_to_bin
WRAP_PASS byte_is_zero
WRAP_PASS byte_is_ascii
WRAP_PASS file_open
WRAP_PASS file_read
WRAP_PASS file_write
WRAP_PASS file_close
WRAP_PASS str_upper
WRAP_PASS str_lower
WRAP_PASS str_trim
WRAP_PASS str_contains
WRAP_PASS call_rt_str_len
WRAP_PASS call_rt_str_cat
WRAP_PASS sign_rax
WRAP_PASS clz_rax
WRAP_PASS ceil_rax
WRAP_PASS floor_rax
WRAP_PASS fract_rax
WRAP_PASS rdrand64
WRAP_PASS hash_rax
WRAP_PASS carry_rax
WRAP_PASS overflow_rax
WRAP_PASS seq_alloc
WRAP_PASS seq_push
WRAP_PASS seq_pop
WRAP_PASS seq_len
WRAP_PASS seq_cap
WRAP_PASS seq_subscript
WRAP_PASS seq_in
WRAP_PASS seq_contains
WRAP_PASS seq_sum
WRAP_PASS seq_min
WRAP_PASS seq_max
WRAP_PASS seq_sort
WRAP_PASS seq_reverse
WRAP_PASS inc_var
WRAP_PASS dec_var
WRAP_PASS swap_vars

; codegen_output_typed and codegen_output_rax are defined manually above
; with IR_OUTPUT emission

; --- codegen_emit_float_abs (stub — not defined in codegen) ---
global codegen_emit_float_abs
codegen_emit_float_abs:
    jmp     emit_ir_nul
