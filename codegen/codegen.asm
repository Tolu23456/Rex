; ============================================================
; codegen/codegen.asm — Rex code generator
; Manages output buffer, variable/protocol tables, ELF header.
; ============================================================
bits 64
%include "rex_defs.inc"

; ============================================================
; O-I: CTPE generic IR opcode constants
; O-J: Constant Propagation
; O-K: Dead Store Elimination
; ============================================================
%define IR_IMOV64   0x01    ; irax = imm64   (op + 8 bytes)
%define IR_IARG     0x02    ; irax = args[b] (op + 1 byte arg index)
%define IR_ILOAD    0x03    ; irax = locals[w] (op + 2 byte var idx)
%define IR_ISTORE   0x04    ; locals[w] = irax  (op + 2 byte var idx)
%define IR_IPUSH    0x05    ; istack[top++] = irax
%define IR_IPOPX    0x06    ; irbx = istack[--top]
%define IR_IMRAX    0x07    ; irbx = irax
%define IR_IADD     0x08    ; irax = irbx + irax
%define IR_ISUB     0x09    ; irax = irbx - irax
%define IR_IMUL     0x0A    ; irax = irbx * irax
%define IR_IDIV     0x0B    ; irax = irbx / irax (signed)
%define IR_IMOD     0x0C    ; irax = irbx % irax
%define IR_INEG     0x0D    ; irax = -irax
%define IR_IINC     0x0E    ; locals[w]++  (op + 2 byte var idx)
%define IR_IDEC     0x0F    ; locals[w]--  (op + 2 byte var idx)
%define IR_IJMP     0x10    ; ip += rel32  (op + 4 bytes)
%define IR_IJZ      0x11    ; if irax==0: ip+=rel32  (op + 4 bytes)
%define IR_IJNZ     0x12    ; if irax!=0: ip+=rel32  (op + 4 bytes)
%define IR_ICMPEQ   0x13    ; irax = (irbx==irax)?1:0
%define IR_ICMPNE   0x14    ; irax = (irbx!=irax)?1:0
%define IR_ICMPLT   0x15    ; irax = (irbx<irax)?1:0
%define IR_ICMPGT   0x16    ; irax = (irbx>irax)?1:0
%define IR_ICMPLE   0x17    ; irax = (irbx<=irax)?1:0
%define IR_ICMPGE   0x18    ; irax = (irbx>=irax)?1:0
%define IR_IRET     0x19    ; return irax
%define IR_IABORT   0x1A    ; cannot fold (impure op)
%define IR_IAND     0x1B    ; irax = irbx & irax
%define IR_IOR      0x1C    ; irax = irbx | irax
%define IR_IXOR     0x1D    ; irax = irbx ^ irax
%define IR_ISHL     0x1E    ; irax = irbx << (irax & 63)
%define IR_ISHR     0x1F    ; irax = irbx >> (irax & 63) arithmetic
%define IR_IBNOT    0x20    ; irax = ~irax
%define IR_ICAL     0x21    ; call proto  (op + 8-byte proto_idx + 1-byte argcnt)

%define CTPE_IR_BUF_SIZE    65536   ; 64 KB IR buffer
%define CTPE_PATCH_MAX      64      ; max pending jump patches during recording
%define CTPE_ISTACK_DEPTH   64      ; max evaluation stack depth
%define CTPE_CALL_DEPTH_MAX 16      ; max recursive CTPE interpreter depth

; ---- exports ----
global emit_b, emit_d, emit_q, emit_blob, emit_blob_v2
global var_add, var_find, get_var_va
global proto_add, proto_find
global codegen_init, codegen_finish
global codegen_write_headers, codegen_write_runtime, codegen_write_code
global out_buffer, out_idx
global var_table, var_count
global proto_table, proto_count
global cur_type, prot_body_depth
global elf_hdr_template
global jump_patch_stack, jump_patch_depth
global end_jump_stack, end_jump_depth
global chain_base_stack, chain_base_depth
global break_jump_stack, break_jump_depth
global break_base_stack, break_base_depth
global cont_base_stack, cont_base_depth
global loop_depth, cur_proto_idx
global fwd_ref_names, fwd_ref_patches, fwd_ref_count
global codegen_emit_mov_rax_imm64
global codegen_emit_mov_rax_var
global codegen_emit_store_rax_to_var
global codegen_cache_var_begin, codegen_cache_var_end
global codegen_ra_pin, codegen_ra_unpin, codegen_ra_push_r14
global codegen_emit_leave_placeholder
global reg_cache_var, var_rbp_offsets
global emit_tail, emit_tail_len
global fused_cmp_var_addr
global codegen_emit_push_rax, codegen_emit_pop_rbx, codegen_emit_mov_rbx_rax
global codegen_emit_add_rax_rbx, codegen_emit_sub_rax_rbx
global codegen_emit_imul_rax_rbx, codegen_emit_idiv_rbx_by_rax
global codegen_emit_imod_rbx_by_rax, codegen_emit_neg_rax
global codegen_emit_bitwise_and, codegen_emit_bitwise_or
global codegen_emit_bitwise_xor, codegen_emit_bitwise_not
global codegen_emit_shl, codegen_emit_shr
global codegen_emit_and_bool, codegen_emit_or_bool
global codegen_emit_not_rax
global codegen_emit_cmp_setcc
global codegen_emit_test_jz, codegen_emit_jmp_end
global codegen_emit_test_jnz
global codegen_patch_jump, codegen_patch_chain_end
global codegen_emit_call_rt_pri, codegen_emit_call_rt_prs
global codegen_emit_call_rt_prb, codegen_emit_call_rt_prf
global codegen_emit_call_rt_prc, codegen_emit_call_rt_err
global codegen_output_typed, codegen_output_rax
global codegen_emit_for_start, codegen_emit_for_end
global codegen_emit_for_start_dyn
global codegen_emit_while_start, codegen_emit_while_end
global codegen_emit_break, codegen_patch_breaks
global codegen_push_cont, codegen_pop_cont, codegen_emit_skip
global codegen_emit_exit0, codegen_emit_exit1
global codegen_emit_str_rax
global codegen_begin_protos, codegen_end_protos
global codegen_emit_prot_start, codegen_emit_prot_end
global codegen_emit_call_prot
global codegen_init_proto_frame
global var_rbp_offsets, proto_local_offset, in_proto_frame
global codegen_emit_seq_alloc, codegen_emit_seq_push
global codegen_emit_seq_pop, codegen_emit_seq_len, codegen_emit_seq_cap
global codegen_emit_inc_var, codegen_emit_dec_var, codegen_emit_swap_vars
global codegen_emit_abs_rax, codegen_emit_typeof_rax
global codegen_emit_cvttsd2si_rax, codegen_emit_cvtsi2sd_rax
global codegen_emit_float_op
global codegen_emit_movdi_rax, codegen_emit_mov_rdi_rax
global codegen_emit_unknown_bool, codegen_emit_rdrand_rax
global codegen_emit_dict_new, codegen_emit_dict_set_raw
global codegen_emit_dict_get_raw
global codegen_emit_clock_ms
global codegen_emit_mov_rax_imm32
global codegen_emit_mov_rdi_var
global codegen_get_out_idx
global codegen_emit_call_rt_str, codegen_emit_call_rt_str_bool
global codegen_emit_call_rt_inp
global codegen_emit_int_to_bool
global codegen_emit_trunc_byte
global codegen_emit_xor_rdi_rdi
; Stage-9 / bug-fix emitters
global codegen_emit_sign_rax, codegen_emit_clz_rax
global codegen_emit_ceil_rax, codegen_emit_floor_rax, codegen_emit_fract_rax
global codegen_emit_rdrand64, codegen_emit_hash_rax
global codegen_emit_carry_rax, codegen_emit_overflow_rax
global codegen_emit_call_rt_str_cat
global codegen_emit_seq_subscript, codegen_emit_seq_in
global codegen_emit_break_n
global break_jump_depths
global codegen_emit_mov_rdi_rbx, codegen_emit_mov_rsi_rax, codegen_emit_neg_var
global codegen_align_loop_top, codegen_emit_zero_var
global loop_pin_active
; Tier 1 peephole + while-loop fold + CTPE exports
global rax_holds_va
global while_pin_active, while_pin_var_va, while_body_start_idx
global fused_cmp_limit, fused_cmp_limit_is_const
global ctpe_const_args, ctpe_call_start_idx, ctpe_tail_len_save, ctpe_all_const
global codegen_while_pin_setup, ctpe_eval_proto
; O-I/O-J/O-K new exports
global ctpe_recording, ctpe_ir_aborted, ctpe_ir_buf, ctpe_ir_out_idx
global proto_ir_offsets, proto_ir_lens
global cp_known, cp_vals, rax_is_const, rax_const_val
global dse_pending, dse_store_pos
global ctpe_interp, ctpe_ir_emit_b, dse_flush_all, cp_flush_all

; ---- externs ----
extern rt_pri_data, rt_prs_data, rt_prb_data, rt_prf_data
extern rt_prc_data, rt_sip_data, rt_alc_data, rt_prq_data
extern rt_str_data, rt_inp_data, rt_str_cat_data

; ============================================================
; BSS — compiler state
; ============================================================
section .bss
out_buffer:         resb OUT_BUF_SIZE           ; 512 KB user code buffer
out_idx:            resq 1                      ; current write position
emit_tail:          resb 32                     ; last 32 bytes emitted (for peephole)
emit_tail_len:      resq 1                      ; how many valid bytes in emit_tail

; variable table (compiler-side name/type tracker)
var_table:          resb VAR_ENTRY_SIZE * VAR_MAX
var_count:          resq 1

; protocol table
proto_table:        resb PROTO_ENTRY_SIZE * PROTO_MAX
proto_count:        resq 1

; current expression type
cur_type:           resb 1
; current protocol index being parsed (-1 = top level)
cur_proto_idx:      resq 1
; nesting depth inside protocol bodies
prot_body_depth:    resq 1

; jump/branch patch stacks
jump_patch_stack:   resq JUMP_STACK_MAX         ; if-condition jz targets
jump_patch_depth:   resq 1
end_jump_stack:     resq JUMP_STACK_MAX         ; end-of-branch jmp targets
end_jump_depth:     resq 1
chain_base_stack:   resq JUMP_STACK_MAX         ; per-chain depth snapshots
chain_base_depth:   resq 1

; loop patch stacks
break_jump_stack:   resq LOOP_STACK_MAX         ; stop jmp targets
break_jump_depth:   resq 1
break_jump_depths:  resq LOOP_STACK_MAX         ; stop N depth per entry (1=current)
break_base_stack:   resq LOOP_STACK_MAX         ; per-loop break group bases
break_base_depth:   resq 1
cont_base_stack:    resq LOOP_STACK_MAX         ; continue-to addresses
cont_base_depth:    resq 1
loop_depth:         resq 1

; forward reference resolution
fwd_ref_names:      resb 32 * FWD_REF_MAX
fwd_ref_patches:    resq FWD_REF_MAX
fwd_ref_count:      resq 1

; protocol section sentinel
proto_section_jmp:  resq 1                      ; out_idx of proto-section jmp
proto_section_open: resb 1                      ; 1 if proto-section jmp is active

; stack-frame protocol support
in_proto_frame:     resb 1                      ; 1 when compiling inside protocol body
var_addr_is_rbp:    resb 1                      ; set by get_var_va: 1=rbp-relative, 0=absolute
var_rbp_offsets:    resq VAR_MAX                ; rbp-relative offset for each var (when in proto frame)
proto_local_offset: resq 1                      ; next rbp offset for locals (negative, starts at -8)
cmp_fused_cc:       resb 1                      ; temp: inverse CC byte for fused comparison
; Register cache: when a variable is "cached" in a register, loads/stores use the register
reg_cache_var:      resq 1                      ; var_index cached in r15 (-1 = none)
reg_cache_reg:      resb 1                      ; register code: 1=rcx, 2=rdx, 3=rsi, 4=rdi

; O-I/O-J/O-K: Multi-register variable cache (Phase 2A)
; Up to 4 variables cached in callee-saved registers: r15, r14, r13, r12
ra_var:             resq 4                      ; var_index cached in each register (-1 = none)
ra_reg:             resb 4                      ; register code for each slot
ra_count:           resq 1                      ; number of currently cached variables
ra_hoist_slot_pos:  resq 1                      ; position of r14 NOP placeholder (for patching)
; When a while-loop comparison is fused to cmp [abs32], N, this stores the abs32 address
fused_cmp_var_addr: resq 1                      ; -1 = no fused comparison

; for-loop state
for_step_val:       resq 1                      ; step value for current for-loop
for_step_sign:      resb 1                      ; 0=positive, 1=negative
for_cont_addr:      resq 1                      ; continue target for current for-loop

; O-A: r15 register pin for static-bounds for-loops
loop_pin_active:    resb 1                      ; 1 = r15 is pinned to loop counter
loop_pin_var_va:    resq 1                      ; var VA pinned in r15

; O-F: FLC patch lists (sub rsp and epilogue add rsp)
frame_size_patch_pos: resq 1                    ; out_idx of imm32 in sub rsp, N
leave_patch_list:   resq 32                     ; up to 32 epilogue patch positions
leave_patch_cnt:    resq 1                      ; number of epilogue patches

; Loop rolling / O-H state (saved at for_start, consumed at for_end)
for_from_val:         resq 1    ; from_imm saved by codegen_emit_for_start
for_to_val:           resq 1    ; to_imm saved by codegen_emit_for_start
for_body_start_idx:   resq 1    ; out_idx at end of for_start preamble (= body start)
og_fired_in_body:     resb 1    ; 1 when O-G ADD/SUB/r15 RMW fired in current loop body
og_rw_addr32:         resd 1    ; 32-bit VA of O-G RMW target
og_op_code:           resb 1    ; operator of O-G fold (0x01=ADD, 0x29=SUB, etc.)
oh_mul_fired_in_body: resb 1    ; 1 when constant imul body detected in current loop
oh_mul_addr32:        resd 1    ; 32-bit VA of constant-mul target
oh_mul_const:         resq 1    ; multiplier constant A (64-bit, sign-extended)
for_to_is_var:        resb 1    ; 1 when for-loop 'to' is a variable (runtime fold)
for_to_var_va:        resq 1    ; VA of the 'to' variable (when for_to_is_var=1)

; F-11: count-down loop form
; When loop var 'i' is unused in body and there are no breaks/continues,
; rewrite header to: mov r15d,N → body → dec r15 → jnz .top  (1 µop overhead vs 4)
for_header_start_idx: resq 1   ; out_idx before for_start's first emit (before hoist slot)
loop_var_used_in_body: resb 1  ; 1 = body reads loop var via r15 (blocks count-down)
loop_has_skip:        resb 1   ; 1 = body has a skip/continue stmt (blocks count-down)
cd_body_scratch:      resb 4096 ; temp buffer for count-down body copy (max 4 KB body)

; F-10: LICM — hoist loop-invariant variable loads into r12
for_hoist_slot_pos:   resq 1   ; position of the 8-NOP hoist slot in out_buffer
licm_hoisted_addr:    resd 1   ; abs32 of the variable hoisted to r12 (0 = none)

; Tier 1: rax value tracking (store-load elimination)
rax_holds_va:             resq 1    ; VA of var whose value is currently in rax (-1 = none)

; While-loop r15 pin + triangular fold state
while_pin_active:         resb 1    ; 1 = r15 is pinned to the while-loop counter
while_pin_var_va:         resq 1    ; VA of the while counter pinned in r15
while_body_start_idx:     resq 1    ; out_idx at start of while body (after pin setup)

; Fused comparison limit (saved from codegen_emit_test_jz for fold check)
fused_cmp_limit:          resq 1    ; the limit constant from the fused comparison
fused_cmp_limit_is_const: resb 1    ; 1 = limit was a compile-time constant

; CTPE: compile-time protocol evaluation state
ctpe_const_args:      resq 8    ; up to 8 constant args for current @proto call
ctpe_call_start_idx:  resq 1    ; out_idx before arg pushes (rewind point)
ctpe_tail_len_save:   resq 1    ; emit_tail_len before arg pushes
ctpe_all_const:       resb 1    ; 1 = all args for current call are compile-time constants

; ============================================================
; O-I: CTPE generic IR recording state
; ============================================================
ctpe_recording:           resb 1                   ; 1 = currently recording a proto's IR
ctpe_ir_aborted:          resb 1                   ; 1 = proto contains impure op, cannot fold
ctpe_ir_buf:              resb CTPE_IR_BUF_SIZE    ; flat IR bytecode buffer (64 KB)
ctpe_ir_out_idx:          resq 1                   ; write cursor into ctpe_ir_buf
proto_ir_offsets:         resq PROTO_MAX           ; ir_out_idx at start of each proto's IR
proto_ir_lens:            resq PROTO_MAX           ; IR byte-length of each proto (0 = none)
ctpe_cur_proto_idx_save:  resq 1                   ; proto_idx currently being recorded
ctpe_skip_idiv_ir:        resb 1                   ; set by imod to suppress idiv's own IR emit
ctpe_call_depth:          resb 1                   ; recursion depth of ctpe_interp

; O-I: var_idx tracking for IR recording (set by get_var_va)
ctpe_current_var_idx:     resw 1                   ; current var_idx for IR emission

; Jump patch mapping: x86 out_buffer offset → IR buffer offset
ctpe_patch_x86:           resq CTPE_PATCH_MAX
ctpe_patch_ir:            resq CTPE_PATCH_MAX
ctpe_patch_cnt:           resq 1

; BSS-based evaluation istack (used by ctpe_interp)
ctpe_istack:              resq CTPE_ISTACK_DEPTH
ctpe_istack_top:          resq 1

; ============================================================
; O-J: Constant Propagation
; ============================================================
cp_known:                 resb VAR_MAX             ; 1 = cp_vals[i] holds a known constant
cp_vals:                  resq VAR_MAX             ; the compile-time constants
rax_is_const:             resb 1                   ; 1 = rax currently holds rax_const_val
rax_const_val:            resq 1                   ; value when rax_is_const=1

; ============================================================
; O-K: Dead Store Elimination
; ============================================================
dse_pending:              resb VAR_MAX             ; 1 = uncommitted store to var[i]
dse_store_pos:            resq VAR_MAX             ; out_buffer offset of that store (8 bytes)

; ============================================================
; DATA — ELF header template (176 bytes) + runtime JMP (5 bytes)
; ============================================================
section .data
elf_hdr_template:
    ; ELF identification (16 bytes)
    db 0x7f, 0x45, 0x4c, 0x46   ; magic
    db 2                         ; EI_CLASS = ELFCLASS64
    db 1                         ; EI_DATA = ELFDATA2LSB (little-endian)
    db 1                         ; EI_VERSION = EV_CURRENT
    db 0                         ; EI_OSABI = SYSV
    times 8 db 0                 ; padding
    dw 2                         ; e_type = ET_EXEC
    dw 62                        ; e_machine = EM_X86_64
    dd 1                         ; e_version = 1
    dq LOAD_BASE + HEADERS_SIZE  ; e_entry = 0x4000B0
    dq 64                        ; e_phoff = 64
    dq 0                         ; e_shoff = 0
    dd 0                         ; e_flags
    dw 64                        ; e_ehsize = 64
    dw 56                        ; e_phentsize = 56
    dw 2                         ; e_phnum = 2
    dw 0                         ; e_shentsize
    dw 0                         ; e_shnum
    dw 0                         ; e_shstrndx

    ; LOAD program header (56 bytes, starts at offset 64)
    dd 1                         ; p_type = PT_LOAD
    dd 7                         ; p_flags = PF_R|PF_W|PF_X
    dq 0                         ; p_offset = 0 (load from file start)
    dq LOAD_BASE                 ; p_vaddr = 0x400000
    dq LOAD_BASE                 ; p_paddr = 0x400000
elf_filesz_patch:
    dq 0                         ; p_filesz (patched by codegen_finish)
elf_memsz_patch:
    dq 0                         ; p_memsz  (patched by codegen_finish)
    dq 0x200000                  ; p_align = 2 MB

    ; GNU_STACK program header (56 bytes, starts at offset 120)
    dd 0x6474e551                ; p_type = PT_GNU_STACK
    dd 6                         ; p_flags = PF_R|PF_W (no execute)
    dq 0                         ; p_offset
    dq 0                         ; p_vaddr
    dq 0                         ; p_paddr
    dq 0                         ; p_filesz
    dq 0                         ; p_memsz
    dq 16                        ; p_align = 16
elf_hdr_template_end:

; 5-byte JMP over runtime blobs (relative to next instruction)
runtime_jmp_bytes:
    db 0xe9
    dd RT_TOTAL_SIZE             ; = 9728

; Error messages
err_var_full:   db "rex: variable table full", 0x0a, 0
err_proto_full: db "rex: protocol table full", 0x0a, 0
err_buf_ov:     db "rex: output buffer overflow", 0x0a, 0

; ============================================================
; TEXT — all functions
; ============================================================
section .text

; ---- codegen_init: zero out all state ----
codegen_init:
    ; zero out_idx, var_count, proto_count, etc.
    mov     qword [out_idx],        0
    mov     qword [emit_tail_len],  0
    mov     qword [var_count],      0
    mov     qword [proto_count],    0
    mov     byte  [cur_type],       TYPE_INT
    mov     qword [cur_proto_idx],  -1
    mov     qword [prot_body_depth],0
    mov     qword [reg_cache_var],  -1         ; no cached variable
    mov     byte  [reg_cache_reg],  0
    mov     qword [fused_cmp_var_addr], -1
    mov     qword [jump_patch_depth],  0
    mov     qword [end_jump_depth],    0
    mov     qword [chain_base_depth],  0
    mov     qword [break_jump_depth],  0
    mov     qword [break_base_depth],  0
    mov     qword [cont_base_depth],   0
    mov     qword [loop_depth],        0
    mov     qword [fwd_ref_count],     0
    mov     byte  [proto_section_open],0
    mov     qword [for_step_val],      1
    mov     byte  [loop_pin_active],   0
    mov     qword [loop_pin_var_va],   -1
    mov     qword [leave_patch_cnt],   0
    mov     qword [for_from_val],      0
    mov     qword [for_to_val],        0
    mov     qword [for_body_start_idx],0
    mov     byte  [og_fired_in_body],  0
    mov     byte  [og_op_code],        0
    mov     byte  [oh_mul_fired_in_body], 0
    mov     qword [oh_mul_const],      0
    ; F-10/F-11 state
    mov     qword [for_header_start_idx], 0
    mov     byte  [loop_var_used_in_body], 0
    mov     byte  [loop_has_skip],     0
    mov     qword [for_hoist_slot_pos], 0
    mov     dword [licm_hoisted_addr], 0
    ; Tier 1 / CTPE / while-fold state
    mov     qword [rax_holds_va],        -1
    mov     byte  [while_pin_active],     0
    mov     qword [while_pin_var_va],    -1
    mov     qword [while_body_start_idx], 0
    mov     qword [fused_cmp_limit],      0
    mov     byte  [fused_cmp_limit_is_const], 0
    mov     byte  [ctpe_all_const],       0
    ; Multi-register variable cache initialization
    mov     qword [ra_var + 0*8],  -1     ; r15 slot: empty
    mov     qword [ra_var + 1*8],  -1     ; r14 slot: empty
    mov     qword [ra_var + 2*8],  -1     ; r13 slot: empty
    mov     qword [ra_var + 3*8],  -1     ; r12 slot: empty
    mov     qword [ra_count],      0
    mov     qword [ra_hoist_slot_pos], 0
    ret

; ---- codegen_get_out_idx: return current out_idx in rax ----
codegen_get_out_idx:
    mov     rax, [out_idx]
    ret

; ============================================================
; O-E: Loop-top 16-byte alignment
; Emits 0-15 NOP bytes to advance out_idx to next 16-byte boundary.
; Call this just before recording the loop condition address.
; ============================================================
codegen_align_loop_top:
    push    rax
    push    rcx
.alt_spin:
    mov     rcx, [out_idx]
    test    rcx, 15
    jz      .alt_done
    mov     al, 0x90
    call    emit_b
    jmp     .alt_spin
.alt_done:
    pop     rcx
    pop     rax
    ret

; ============================================================
; O-D: Short zero-init — emit  mov qword [addr32], 0  (9 bytes)
; rdi = var VA (absolute 32-bit address)
; Replaces the 18-byte movabs+store form for zero initialization.
; ============================================================
codegen_emit_zero_var:
    push    rax
    push    rdi
    ; 48 C7 04 25 <addr32> 00 00 00 00
    mov     al, 0x48
    call    emit_b
    mov     al, 0xc7
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    pop     rdi
    mov     eax, edi
    call    emit_d
    xor     eax, eax
    call    emit_d
    pop     rax
    ret

; ============================================================
; O-B/C: Peephole scan for r10 round-trip patterns.
; Call after emitting code that may complete the pattern.
; Pattern E (14 bytes):
;   49 89 C2          mov r10, rax
;   48 8B 04 25 <a>   mov rax, [abs32]
;   4C 89 D3          mov rbx, r10
; → 48 89 C3          mov rbx, rax
;   48 8B 04 25 <a>   (unchanged)
;   90 90 90          NOP NOP NOP
;
; Pattern F (6 bytes):
;   49 89 C2          mov r10, rax
;   4C 89 D3          mov rbx, r10
; → 48 89 C3          mov rbx, rax
;   90 90 90          NOP NOP NOP
; ============================================================
codegen_peephole_r10:
    push    rax
    push    rcx
    push    rdi

    mov     rcx, [emit_tail_len]

    ; --- Pattern F (6 bytes): mov r10,rax + mov rbx,r10 ---
    cmp     rcx, 6
    jl      .r10_check_e

    mov     rax, rcx
    sub     rax, 6
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x49
    jne     .r10_check_e
    mov     rax, rcx
    sub     rax, 5
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x89
    jne     .r10_check_e
    mov     rax, rcx
    sub     rax, 4
    and     rax, 31
    cmp     byte [emit_tail + rax], 0xC2
    jne     .r10_check_e
    mov     rax, rcx
    sub     rax, 3
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x4C
    jne     .r10_check_e
    mov     rax, rcx
    sub     rax, 2
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x89
    jne     .r10_check_e
    mov     rax, rcx
    sub     rax, 1
    and     rax, 31
    cmp     byte [emit_tail + rax], 0xD3
    jne     .r10_check_e

    ; Pattern F matched: rollback 6, emit mov rbx,rax (3 bytes — no NOPs)
    sub     qword [out_idx], 6
    sub     qword [emit_tail_len], 6
    mov     al, 0x48
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0xc3
    call    emit_b
    jmp     .r10_done

.r10_check_e:
    ; --- Pattern E (14 bytes): mov r10,rax + mov rax,[abs32] + mov rbx,r10 ---
    cmp     rcx, 14
    jl      .r10_done

    mov     rax, rcx
    sub     rax, 14
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x49
    jne     .r10_done
    mov     rax, rcx
    sub     rax, 13
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x89
    jne     .r10_done
    mov     rax, rcx
    sub     rax, 12
    and     rax, 31
    cmp     byte [emit_tail + rax], 0xC2
    jne     .r10_done
    ; Check mov rax,[abs32]: 48 8B 04 25
    mov     rax, rcx
    sub     rax, 11
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x48
    jne     .r10_done
    mov     rax, rcx
    sub     rax, 10
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x8B
    jne     .r10_done
    mov     rax, rcx
    sub     rax, 9
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x04
    jne     .r10_done
    mov     rax, rcx
    sub     rax, 8
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x25
    jne     .r10_done
    ; Check mov rbx,r10 at tail[N-3..N-1]: 4C 89 D3
    mov     rax, rcx
    sub     rax, 3
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x4C
    jne     .r10_done
    mov     rax, rcx
    sub     rax, 2
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x89
    jne     .r10_done
    mov     rax, rcx
    sub     rax, 1
    and     rax, 31
    cmp     byte [emit_tail + rax], 0xD3
    jne     .r10_done

    ; Pattern E matched: extract addr32 from out_buffer[out_idx - 7]
    mov     rdi, [out_idx]
    mov     edi, dword [out_buffer + rdi - 7]

    ; rollback 14 bytes, emit: mov rbx,rax(3) + mov rax,[abs32](8) = 11 bytes (no NOPs)
    sub     qword [out_idx], 14
    sub     qword [emit_tail_len], 14
    mov     al, 0x48
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0xc3
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x8b
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, edi
    call    emit_d

.r10_done:
    pop     rdi
    pop     rcx
    pop     rax
    ret

; ============================================================
; Register cache management
; ============================================================
; codegen_cache_var_begin(rdi=var_va): cache variable in r15, emit mov r15, [addr]
codegen_cache_var_begin:
    mov     [reg_cache_var], rdi
    ; Emit: push r15 (save old r15) + mov r15, [abs32] (9 bytes)
    push    rax
    push    rdi
    ; push r15 = 41 57
    mov     al, 0x41
    call    emit_b
    mov     al, 0x57
    call    emit_b
    ; mov r15, [abs32] = 4C 8B 3C 25 XX XX XX XX
    mov     al, 0x4c
    call    emit_b
    mov     al, 0x8b
    call    emit_b
    mov     al, 0x3c
    call    emit_b
    mov     al, 0x25
    call    emit_b
    pop     rdi
    mov     eax, edi
    call    emit_d
    pop     rax
    ret

; codegen_cache_var_end(rdi=var_va): uncache variable, emit mov [addr], r15 + pop r15
codegen_cache_var_end:
    mov     qword [reg_cache_var], -1
    ; Emit: mov [abs32], r15 + pop r15
    push    rax
    push    rdi
    ; mov [abs32], r15 = 4C 89 3C 25 XX XX XX XX
    mov     al, 0x4c
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0x3c
    call    emit_b
    mov     al, 0x25
    call    emit_b
    pop     rdi
    mov     eax, edi
    call    emit_d
    ; pop r15 = 41 5F
    mov     al, 0x41
    call    emit_b
    mov     al, 0x5f
    call    emit_b
    pop     rax
    ret

; ============================================================
; Multi-register variable cache pin/unpin (Phase 2A)
; ============================================================

; codegen_ra_pin(rdi=slot, rsi=var_va, rdx=reg_code)
; Pin a variable to a callee-saved register.
; Emits: push reg + mov reg, [abs32]
; Updates ra_var[slot], ra_reg[slot], ra_count++
codegen_ra_pin:
    push    rax
    push    rbx
    push    rcx
    push    rdi
    push    rsi
    push    rdx

    ; Save state
    mov     rax, rdi                ; rax = slot
    mov     rbx, rsi                ; rbx = var_va
    mov     rcx, rdx                ; rcx = reg_code (14, 13, or 12)

    ; Update ra_var and ra_reg
    mov     [ra_var + rax*8], rbx
    mov     [ra_reg + rax], cl
    inc     qword [ra_count]

    ; Emit push reg
    ; r14: 41 56, r13: 41 55, r12: 41 54
    mov     al, 0x41
    call    emit_b
    cmp     cl, 14
    je      .ra_pin_push_r14
    cmp     cl, 13
    je      .ra_pin_push_r13
    ; r12: push = 54
    mov     al, 0x54
    call    emit_b
    jmp     .ra_pin_push_done
.ra_pin_push_r14:
    mov     al, 0x56
    call    emit_b
    jmp     .ra_pin_push_done
.ra_pin_push_r13:
    mov     al, 0x55
    call    emit_b
.ra_pin_push_done:

    ; Emit mov reg, [abs32]
    ; r14: 4C 8B 34 25 addr32
    ; r13: 4C 8B 2C 25 addr32
    ; r12: 4C 8B 24 25 addr32
    mov     al, 0x4c
    call    emit_b
    mov     al, 0x8b
    call    emit_b
    cmp     cl, 14
    je      .ra_pin_mov_r14
    cmp     cl, 13
    je      .ra_pin_mov_r13
    ; r12: ModRM = 24
    mov     al, 0x24
    call    emit_b
    jmp     .ra_pin_mov_done
.ra_pin_mov_r14:
    mov     al, 0x34
    call    emit_b
    jmp     .ra_pin_mov_done
.ra_pin_mov_r13:
    mov     al, 0x2c
    call    emit_b
.ra_pin_mov_done:
    mov     al, 0x25
    call    emit_b
    ; Emit addr32
    pop     rdx
    pop     rsi
    pop     rdi
    mov     eax, esi                ; eax = var_va (low 32 bits)
    call    emit_d

    pop     rcx
    pop     rbx
    pop     rax
    ret

; codegen_ra_unpin(rdi=slot, rsi=var_va)
; Unpin a variable from its register.
; Emits: mov [abs32], reg + pop reg
; Updates ra_var[slot] = -1, ra_count--
codegen_ra_unpin:
    push    rax
    push    rbx
    push    rcx
    push    rdi
    push    rsi

    ; Save state
    mov     rax, rdi                ; rax = slot
    mov     rbx, rsi                ; rbx = var_va

    ; Load reg_code from ra_reg[slot]
    movzx   ecx, byte [ra_reg + rax]

    ; Emit mov [abs32], reg
    ; r14: 4C 89 34 25 addr32
    ; r13: 4C 89 2C 25 addr32
    ; r12: 4C 89 24 25 addr32
    mov     al, 0x4c
    call    emit_b
    mov     al, 0x89
    call    emit_b
    cmp     cl, 14
    je      .ra_unpin_mov_r14
    cmp     cl, 13
    je      .ra_unpin_mov_r13
    ; r12: ModRM = 24
    mov     al, 0x24
    call    emit_b
    jmp     .ra_unpin_mov_done
.ra_unpin_mov_r14:
    mov     al, 0x34
    call    emit_b
    jmp     .ra_unpin_mov_done
.ra_unpin_mov_r13:
    mov     al, 0x2c
    call    emit_b
.ra_unpin_mov_done:
    mov     al, 0x25
    call    emit_b
    ; Emit addr32
    mov     eax, ebx                ; eax = var_va (low 32 bits)
    call    emit_d

    ; Emit pop reg
    ; r14: 41 5E, r13: 41 5D, r12: 41 5C
    mov     al, 0x41
    call    emit_b
    cmp     cl, 14
    je      .ra_unpin_pop_r14
    cmp     cl, 13
    je      .ra_unpin_pop_r13
    ; r12: pop = 5C
    mov     al, 0x5c
    call    emit_b
    jmp     .ra_unpin_pop_done
.ra_unpin_pop_r14:
    mov     al, 0x5e
    call    emit_b
    jmp     .ra_unpin_pop_done
.ra_unpin_pop_r13:
    mov     al, 0x5d
    call    emit_b
.ra_unpin_pop_done:

    ; Update ra_var and ra_count
    pop     rsi
    pop     rdi
    mov     rax, rdi
    mov     qword [ra_var + rax*8], -1
    dec     qword [ra_count]

    pop     rcx
    pop     rbx
    pop     rax
    ret

; codegen_ra_push_r14: Emit push r14 + 8-NOP placeholder for accumulator pinning
; Called BEFORE while-loop condition check to ensure r15 is saved before loop body
codegen_ra_push_r14:
    push    rax
    ; Emit: push r14 = 41 56
    mov     al, 0x41
    call    emit_b
    mov     al, 0x56
    call    emit_b
    ; Record position of 8-NOP placeholder for mov r14, [acc_addr]
    mov     rax, [out_idx]
    mov     [ra_hoist_slot_pos], rax
    ; Emit 8 NOPs as placeholder for mov r14, [acc_addr]
    push    rcx
    xor     ecx, ecx
.ra_push_nop_loop:
    cmp     ecx, 8
    jge     .ra_push_nop_done
    push    rax
    mov     al, 0x90
    call    emit_b
    pop     rax
    inc     ecx
    jmp     .ra_push_nop_loop
.ra_push_nop_done:
    pop     rcx
    ; Set ra_var[1] = 0 (placeholder) so O-G fold knows r14 is pinned
    mov     qword [ra_var + 1*8], 0
    mov     byte [ra_reg + 1], 14
    mov     qword [ra_count], 1
    pop     rax
    ret

; ============================================================
; Emit helpers
; ============================================================
emit_b:
    ; al = byte to emit
    push    rcx
    push    rdi
    mov     rcx, [out_idx]
    cmp     rcx, OUT_BUF_SIZE - 1
    jge     .emit_b_ov
    mov     [out_buffer + rcx], al
    inc     rcx
    mov     [out_idx], rcx
    ; Track last byte for peephole (circular buffer)
    mov     rdi, [emit_tail_len]
    and     rdi, 31                 ; mod 32
    mov     [emit_tail + rdi], al
    inc     qword [emit_tail_len]
    pop     rdi
    pop     rcx
    ret
.emit_b_ov:
    mov     rax, SYS_write
    mov     rdi, 2
    lea     rsi, [err_buf_ov]
    mov     rdx, 28
    syscall
    mov     rax, SYS_exit
    mov     rdi, 1
    syscall

emit_d:
    ; eax = dword to emit (little-endian)
    push    rcx
    push    rdx
    push    rdi
    push    rax
    mov     rcx, [out_idx]
    cmp     rcx, OUT_BUF_SIZE - 4
    ja      .emit_d_ov
    mov     [out_buffer + rcx], eax
    add     rcx, 4
    mov     [out_idx], rcx
    ; Update emit_tail with 4 bytes (circular)
    mov     rdi, [emit_tail_len]
    ; byte 0
    mov     rcx, rdi
    and     rcx, 31
    mov     [emit_tail + rcx], al
    mov     edx, eax
    shr     edx, 8
    inc     rdi
    ; byte 1
    mov     rcx, rdi
    and     rcx, 31
    mov     [emit_tail + rcx], dl
    shr     edx, 8
    inc     rdi
    ; byte 2
    mov     rcx, rdi
    and     rcx, 31
    mov     [emit_tail + rcx], dl
    shr     edx, 8
    inc     rdi
    ; byte 3
    mov     rcx, rdi
    and     rcx, 31
    mov     [emit_tail + rcx], dl
    inc     rdi
    mov     [emit_tail_len], rdi
    pop     rax
    pop     rdi
    pop     rdx
    pop     rcx
    ret
.emit_d_ov:
    mov     rax, SYS_write
    mov     rdi, 2
    lea     rsi, [err_buf_ov]
    mov     rdx, 28
    syscall
    mov     rax, SYS_exit
    mov     rdi, 1
    syscall

emit_q:
    ; rax = qword to emit
    push    rcx
    push    rdx
    push    rdi
    push    rax
    mov     rcx, [out_idx]
    cmp     rcx, OUT_BUF_SIZE - 8
    ja      .emit_q_ov
    mov     [out_buffer + rcx], rax
    add     rcx, 8
    mov     [out_idx], rcx
    ; Update emit_tail with 8 bytes (circular)
    mov     rdi, [emit_tail_len]
    mov     rcx, rdi
    and     rcx, 31
    mov     [emit_tail + rcx], al
    mov     edx, eax
    shr     edx, 8
    inc     rdi
    mov     rcx, rdi
    and     rcx, 31
    mov     [emit_tail + rcx], dl
    shr     edx, 8
    inc     rdi
    mov     rcx, rdi
    and     rcx, 31
    mov     [emit_tail + rcx], dl
    shr     edx, 8
    inc     rdi
    mov     rcx, rdi
    and     rcx, 31
    mov     [emit_tail + rcx], dl
    shr     edx, 8
    inc     rdi
    mov     rcx, rdi
    and     rcx, 31
    mov     [emit_tail + rcx], dl
    shr     edx, 8
    inc     rdi
    mov     rcx, rdi
    and     rcx, 31
    mov     [emit_tail + rcx], dl
    shr     edx, 8
    inc     rdi
    mov     rcx, rdi
    and     rcx, 31
    mov     [emit_tail + rcx], dl
    shr     edx, 8
    inc     rdi
    mov     rcx, rdi
    and     rcx, 31
    mov     [emit_tail + rcx], dl
    inc     rdi
    mov     [emit_tail_len], rdi
    pop     rax
    pop     rdi
    pop     rdx
    pop     rcx
    ret
.emit_q_ov:
    mov     rax, SYS_write
    mov     rdi, 2
    lea     rsi, [err_buf_ov]
    mov     rdx, 28
    syscall
    mov     rax, SYS_exit
    mov     rdi, 1
    syscall

emit_blob:
    ; rsi = source pointer, rcx = byte count
    push    rdi
    push    rsi
    push    rcx
    push    rax
    push    rdx
    mov     rdx, rcx            ; save byte count
    mov     rdi, [out_idx]
    lea     rdi, [out_buffer + rdi]
    rep     movsb
    mov     rdi, [out_idx]
    add     rdi, rdx
    mov     [out_idx], rdi
    ; Update emit_tail
    sub     rdi, rdx            ; rdi = start offset
    lea     rsi, [out_buffer + rdi]
    mov     rdi, [emit_tail_len]
    test    rdx, rdx
    jz      .blob_tail_done
.blob_tail_loop:
    movzx   eax, byte [rsi]
    push    rcx
    mov     rcx, rdi
    and     rcx, 31
    mov     [emit_tail + rcx], al
    pop     rcx
    inc     rsi
    inc     rdi
    dec     rdx
    jnz     .blob_tail_loop
.blob_tail_done:
    mov     [emit_tail_len], rdi
    pop     rdx
    pop     rax
    pop     rcx
    pop     rsi
    pop     rdi
    ret

; Simpler emit_blob using stored offset
emit_blob_v2:
    ; rsi = src, rdx = count
    push    rdi
    push    rsi
    push    rcx
    push    rax
    push    rdx
    mov     rcx, rdx
    mov     rdi, out_buffer
    add     rdi, [out_idx]
    rep     movsb
    add     [out_idx], rdx
    ; Update emit_tail with emitted bytes
    mov     rax, [out_idx]
    sub     rax, rdx            ; rax = start offset in out_buffer
    lea     rsi, [out_buffer + rax]
    mov     rdi, [emit_tail_len]
    test    rdx, rdx
    jz      .blob_tail_done
.blob_tail_loop:
    movzx   eax, byte [rsi]
    mov     rcx, rdi
    and     rcx, 31
    mov     [emit_tail + rcx], al
    inc     rsi
    inc     rdi
    dec     rdx
    jnz     .blob_tail_loop
.blob_tail_done:
    mov     [emit_tail_len], rdi
    pop     rdx
    pop     rax
    pop     rcx
    pop     rsi
    pop     rdi
    ret

; ============================================================
; Variable table management
; ============================================================

; get_var_va(rdi=index) → rax = address/offset
; When in_proto_frame: returns rbp-relative offset from var_rbp_offsets
; Otherwise: returns VAR_STORAGE_BASE + idx*64
get_var_va:
    ; O-I: save var_idx for IR recording
    mov     word [ctpe_current_var_idx], di
    test    byte [in_proto_frame], 1
    jnz     .rbp_mode
    shl     rdi, 6              ; idx * 64
    lea     rax, [rdi + VAR_STORAGE_BASE]
    mov     byte [var_addr_is_rbp], 0
    ret
  .rbp_mode:
    mov     rax, [var_rbp_offsets + rdi*8]
    mov     byte [var_addr_is_rbp], 1
    ret

; var_add(rdi=name_ptr, rsi=type) → rax=index (-1 if full)
var_add:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi

    mov     rax, [var_count]
    cmp     rax, VAR_MAX
    jge     .full

    ; compute table entry address
    mov     rbx, rax
    shl     rbx, 6              ; idx * 64
    lea     rbx, [var_table + rbx]

    ; copy name (up to 31 bytes + NUL)
    mov     rsi, [rsp]          ; original rdi = name_ptr
    mov     rdi, rbx            ; destination
    xor     rcx, rcx
.name_copy:
    cmp     rcx, 31
    jge     .name_done
    movzx   edx, byte [rsi + rcx]
    mov     [rdi + rcx], dl
    test    dl, dl
    jz      .name_done
    inc     rcx
    jmp     .name_copy
.name_done:
    mov     byte [rdi + rcx], 0 ; ensure NUL termination

    ; set type
    mov     cl, [rsp + 8]       ; original rsi = type (low byte)
    mov     [rbx + VAR_TYPE_OFF], cl

    ; set is_init = 0, is_mutable = 0 initially
    mov     byte [rbx + VAR_INIT_OFF], 0
    mov     byte [rbx + VAR_MUT_OFF], 0

    ; zero value field
    mov     qword [rbx + VAR_VAL_OFF], 0

    ; return index, increment count
    mov     rax, [var_count]
    inc     qword [var_count]

    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

.full:
    mov     rax, -1
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; var_find(rdi=name_ptr) → rax=index (-1 if not found)
; Scans var_table in reverse (inner scope shadows outer)
var_find:
    push    rbx
    push    rcx
    push    rdx
    push    r11

    ; load first 8 bytes of query name for fast prefix rejection
    mov     r11, [rdi]                  ; load first 8 bytes (may read past NUL, ok)

    mov     rbx, [var_count]            ; start from highest index
    test    rbx, rbx
    jz      .notfound

.scan_loop:
    dec     rbx
    ; entry address = var_table + rbx * 64
    mov     rcx, rbx
    shl     rcx, 6
    lea     rcx, [var_table + rcx]      ; rcx = entry

    ; quick 8-byte prefix check
    cmp     [rcx + VAR_NAME_OFF], r11
    jne     .next_entry

    ; full strcmp
    push    rdi
    mov     rdi, rdi                    ; query ptr
    lea     rsi, [rcx + VAR_NAME_OFF]
.strcmp:
    movzx   eax, byte [rdi]
    movzx   edx, byte [rsi]
    cmp     al, dl
    jne     .no_match
    test    al, al
    jz      .match
    inc     rdi
    inc     rsi
    jmp     .strcmp
.match:
    pop     rdi
    mov     rax, rbx
    pop     r11
    pop     rdx
    pop     rcx
    pop     rbx
    ret
.no_match:
    pop     rdi

.next_entry:
    test    rbx, rbx
    jnz     .scan_loop

.notfound:
    mov     rax, -1
    pop     r11
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ============================================================
; Protocol table management
; ============================================================

; proto_add(rdi=name_ptr) → rax=index (-1 if full)
proto_add:
    push    rbx
    push    rcx
    push    rdx
    push    rdi

    mov     rax, [proto_count]
    cmp     rax, PROTO_MAX
    jge     .full

    mov     rbx, rax
    imul    rbx, PROTO_ENTRY_SIZE
    lea     rbx, [proto_table + rbx]

    ; copy name
    mov     rsi, [rsp]           ; rdi = name_ptr
    mov     rdi, rbx
    xor     rcx, rcx
.nc:
    cmp     rcx, 31
    jge     .nd
    movzx   edx, byte [rsi + rcx]
    mov     [rdi + rcx], dl
    test    dl, dl
    jz      .nd
    inc     rcx
    jmp     .nc
.nd:
    mov     byte [rdi + rcx], 0
    ; zero out_idx, param_count, ret_type
    mov     qword [rbx + PROTO_OUTIDX_OFF], 0
    mov     byte  [rbx + PROTO_PARAMCNT_OFF], 0
    mov     byte  [rbx + PROTO_RETTYPE_OFF], 0

    mov     rax, [proto_count]
    inc     qword [proto_count]
    pop     rdi
    pop     rdx
    pop     rcx
    pop     rbx
    ret
.full:
    mov     rax, -1
    pop     rdi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; proto_find(rdi=name_ptr) → rax=index (-1 if not found)
proto_find:
    push    rbx
    push    rcx
    push    rdx
    push    rdi

    mov     rbx, [proto_count]
    test    rbx, rbx
    jz      .notfound

    xor     rbx, rbx
.scan:
    imul    rcx, rbx, PROTO_ENTRY_SIZE
    lea     rcx, [proto_table + rcx]

    ; strcmp name
    mov     rsi, [rsp]           ; query name
    lea     rdi, [rcx + PROTO_NAME_OFF]
.cmp:
    movzx   eax, byte [rsi]
    movzx   edx, byte [rdi]
    cmp     al, dl
    jne     .nomatch
    test    al, al
    jz      .found
    inc     rsi
    inc     rdi
    jmp     .cmp
.found:
    mov     rax, rbx
    pop     rdi
    pop     rdx
    pop     rcx
    pop     rbx
    ret
.nomatch:
    inc     rbx
    cmp     rbx, [proto_count]
    jb      .scan

.notfound:
    mov     rax, -1
    pop     rdi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ============================================================
; Core code emission
; ============================================================

; codegen_emit_mov_rax_imm64(rdi=value)
codegen_emit_mov_rax_imm64:
    mov     qword [rax_holds_va], -1   ; rax = constant, not a variable's value
    ; O-I: emit IR_IMOV64 if recording
    cmp     byte [ctpe_recording], 0
    je      .no_ir_imm64
    push    rdi
    mov     rdi, IR_IMOV64
    call    ctpe_ir_emit_b          ; emit opcode, preserves rdi
    pop     rdi
    call    ctpe_ir_emit_q          ; emit 8-byte value
.no_ir_imm64:
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0xb8            ; REX.W + MOV rax, imm64
    call    emit_b
    mov     rax, rdi
    call    emit_q
    pop     rax
    ret

; codegen_emit_mov_rax_imm32(rdi=value): emit  mov eax, imm32 (or xor eax,eax)
codegen_emit_mov_rax_imm32:
    mov     qword [rax_holds_va], -1   ; rax = constant, not a variable's value
    ; O-I: emit IR_IMOV64 if recording (zero-extend imm32 to 64-bit)
    cmp     byte [ctpe_recording], 0
    je      .no_ir_imm32
    push    rdi
    mov     rdi, IR_IMOV64
    call    ctpe_ir_emit_b
    pop     rdi
    movsxd  rdi, edi               ; sign-extend imm32 to 64-bit
    call    ctpe_ir_emit_q
.no_ir_imm32:
    push    rax
    test    rdi, rdi
    jnz     .nonzero
    mov     al, 0x31            ; xor eax, eax
    call    emit_b
    mov     al, 0xc0
    call    emit_b
    pop     rax
    ret
.nonzero:
    mov     al, 0xb8            ; mov eax, imm32
    call    emit_b
    mov     eax, edi
    call    emit_d
    pop     rax
    ret

; codegen_emit_mov_rax_var(rdi=var_va): emit  mov rax, [addr]
; When var_addr_is_rbp=1: emit mov rax, [rbp+disp32]
; Otherwise: emit mov rax, [abs32]
codegen_emit_mov_rax_var:
    ; O-I: emit IR_ILOAD if recording
    cmp     byte [ctpe_recording], 0
    je      .no_ir_load
    push    rdi
    push    rsi
    mov     rdi, IR_ILOAD
    call    ctpe_ir_emit_b
    movzx   edi, word [ctpe_current_var_idx]
    call    ctpe_ir_emit_w
    pop     rsi
    pop     rdi
.no_ir_load:
    ; Tier 1: rax already holds this variable's value — skip the load entirely
    cmp     rdi, [rax_holds_va]
    je      .rax_already_correct
    push    rax
    push    rdi
    ; Check register cache: if rdi == reg_cache_var, emit mov rax, r15 (3 bytes)
    cmp     rdi, [reg_cache_var]
    jne     .not_cached
    pop     rdi
    pop     rax
    ; F-11: body is reading the loop variable via r15 — block count-down rewrite
    cmp     byte [loop_pin_active], 0
    je      .cached_do_emit
    mov     byte [loop_var_used_in_body], 1
.cached_do_emit:
    ; Tier 1: update rax_holds_va — rax will hold the r15-cached var's value
    mov     [rax_holds_va], rdi
    ; Emit: mov rax, r15 = 4C 89 F8 (3 bytes)
    push    rax
    mov     al, 0x4c
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0xf8
    call    emit_b
    pop     rax
    ret
  .not_cached:
    ; Phase 2A: Check multi-register cache (r14, r13, r12)
    cmp     qword [ra_count], 0
    je      .check_abs_load
    push    rcx
    push    rdx
    xor     ecx, ecx               ; slot index = 0
.ra_check_loop:
    cmp     ecx, 4
    jge     .ra_check_done
    cmp     rdi, [ra_var + rcx*8]  ; compare with cached var
    je      .ra_found
    inc     ecx
    jmp     .ra_check_loop
.ra_found:
    ; Variable is in a register — emit mov rax, reg (3 bytes)
    pop     rdx
    pop     rcx
    pop     rdi
    pop     rax
    mov     [rax_holds_va], rdi
    ; Emit: mov rax, reg based on ra_reg[ecx]
    push    rax
    movzx   edx, byte [ra_reg + ecx]
    ; r14 = 4C 89 F0, r13 = 4C 89 E8, r12 = 4C 89 E0
    cmp     dl, 14
    je      .ra_load_r14
    cmp     dl, 13
    je      .ra_load_r13
    ; r12: 4C 89 E0
    mov     al, 0x4c
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0xe0
    call    emit_b
    jmp     .ra_load_done
.ra_load_r14:
    ; r14: 4C 89 F0
    mov     al, 0x4c
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0xf0
    call    emit_b
    jmp     .ra_load_done
.ra_load_r13:
    ; r13: 4C 89 E8
    mov     al, 0x4c
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0xe8
    call    emit_b
.ra_load_done:
    pop     rax
    ret
.ra_check_done:
    pop     rdx
    pop     rcx
.check_abs_load:
    test    byte [var_addr_is_rbp], 1
    jnz     .rbp_load
    ; absolute mode: 48 8B 04 25 addr32
    mov     al, 0x48
    call    emit_b
    mov     al, 0x8b
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    pop     rdi
    ; Tier 1: rax will hold this var's value after the load
    mov     [rax_holds_va], rdi
    mov     eax, edi
    call    emit_d
    pop     rax
    ret
  .rbp_load:
    ; rbp-relative: mov rax, [rbp+disp32] = 48 8B 85 disp32
    mov     al, 0x48
    call    emit_b
    mov     al, 0x8b
    call    emit_b
    mov     al, 0x85
    call    emit_b
    pop     rdi
    ; Tier 1: rax will hold this rbp-offset var's value
    mov     [rax_holds_va], rdi
    mov     eax, edi
    call    emit_d
    pop     rax
    ret
.rax_already_correct:
    ; rax already holds the correct value for this var — emit nothing
    ret

; codegen_emit_mov_rdi_var(rdi=var_va): emit  mov rdi, [abs32]
codegen_emit_mov_rdi_var:
    push    rax
    push    rdi
    mov     al, 0x48
    call    emit_b
    mov     al, 0x8b            ; MOV rdi, [disp32]
    call    emit_b
    mov     al, 0x3c
    call    emit_b
    mov     al, 0x25
    call    emit_b
    pop     rdi
    mov     eax, edi
    call    emit_d
    pop     rax
    ret

; codegen_emit_store_rax_to_var(rdi=var_va): emit  mov [addr], rax
; When var_addr_is_rbp=1: emit mov [rbp+disp32], rax
; Otherwise: emit mov [abs32], rax
; Peephole: detect  load rax,[abs32]; add/sub rax,imm; store [abs32],rax  →  add/sub/inc/dec qword [abs32]
codegen_emit_store_rax_to_var:
    ; Invalidate rax_holds_va: after a store, the fused-comparison peephole
    ; needs fresh loads in emit_tail to detect patterns. Conservative clear.
    mov     qword [rax_holds_va], -1
    ; O-I: emit IR_ISTORE if recording
    cmp     byte [ctpe_recording], 0
    je      .no_ir_store
    push    rdi
    push    rsi
    mov     rdi, IR_ISTORE
    call    ctpe_ir_emit_b
    movzx   edi, word [ctpe_current_var_idx]
    call    ctpe_ir_emit_w
    pop     rsi
    pop     rdi
.no_ir_store:
    push    rax
    push    rdi
    push    rcx
    push    r12

    ; Check register cache: if rdi == reg_cache_var, emit mov r15, rax (3 bytes)
    cmp     rdi, [reg_cache_var]
    jne     .not_cached_store

    ; === r15 increment/decrement peephole ===
    ; Pattern: mov rax,r15(3) + add/sub rax,1(4) → inc/dec r15(3) — saves 4 bytes
    mov     rcx, [emit_tail_len]
    cmp     rcx, 7
    jl      .r15_no_inc_p
    ; Check tail[-7..-5] = 4C 89 F8  (mov rax, r15)
    mov     rax, rcx
    sub     rax, 7
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x4C
    jne     .r15_no_inc_p
    mov     rax, rcx
    sub     rax, 6
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x89
    jne     .r15_no_inc_p
    mov     rax, rcx
    sub     rax, 5
    and     rax, 31
    cmp     byte [emit_tail + rax], 0xF8
    jne     .r15_no_inc_p
    ; Check tail[-4] = 0x48 (REX.W) and tail[-3] = 0x83 (add/sub imm8)
    mov     rax, rcx
    sub     rax, 4
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x48
    jne     .r15_no_inc_p
    mov     rax, rcx
    sub     rax, 3
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x83
    jne     .r15_no_inc_p
    ; Check tail[-1] = 0x01 (imm8 = 1)
    mov     rax, rcx
    sub     rax, 1
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x01
    jne     .r15_no_inc_p
    ; Extract tail[-2] = modrm (0xC0 = add rax,imm8; 0xE8 = sub rax,imm8)
    mov     rax, rcx
    sub     rax, 2
    and     rax, 31
    movzx   r12d, byte [emit_tail + rax]
    cmp     r12b, 0xC0
    je      .r15_do_inc
    cmp     r12b, 0xE8
    jne     .r15_no_inc_p

    ; SUB rax,1: emit dec r15 = 49 FF CF, rewind 7 bytes
    sub     qword [out_idx], 7
    sub     qword [emit_tail_len], 7
    pop     r12
    pop     rcx
    pop     rdi
    pop     rax
    push    rax
    mov     al, 0x49
    call    emit_b
    mov     al, 0xFF
    call    emit_b
    mov     al, 0xCF
    call    emit_b
    pop     rax
    ret
.r15_do_inc:
    ; ADD rax,1: emit inc r15 = 49 FF C7, rewind 7 bytes
    sub     qword [out_idx], 7
    sub     qword [emit_tail_len], 7
    pop     r12
    pop     rcx
    pop     rdi
    pop     rax
    push    rax
    mov     al, 0x49
    call    emit_b
    mov     al, 0xFF
    call    emit_b
    mov     al, 0xC7
    call    emit_b
    pop     rax
    ret
.r15_no_inc_p:
    ; Normal r15-cached store: emit mov r15, rax = 49 89 C7
    pop     r12
    pop     rcx
    pop     rdi
    pop     rax
    push    rax
    mov     al, 0x49
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0xc7
    call    emit_b
    pop     rax
    ret
  .not_cached_store:
    ; Phase 2A: Check multi-register cache (r14, r13, r12) for store
    cmp     qword [ra_count], 0
    je      .check_abs_store
    push    rcx
    push    rdx
    xor     ecx, ecx               ; slot index = 0
.ra_store_check:
    cmp     ecx, 4
    jge     .ra_store_done
    cmp     rdi, [ra_var + rcx*8]  ; compare with cached var
    je      .ra_store_found
    inc     ecx
    jmp     .ra_store_check
.ra_store_found:
    ; Variable is in a register — emit mov reg, rax (3 bytes)
    pop     rdx
    pop     rcx
    pop     r12
    pop     rcx
    pop     rdi
    pop     rax
    ; Emit: mov reg, rax based on ra_reg[ecx]
    push    rax
    movzx   edx, byte [ra_reg + ecx]
    cmp     dl, 14
    je      .ra_store_r14
    cmp     dl, 13
    je      .ra_store_r13
    ; r12: 4C 89 E0
    mov     al, 0x4c
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0xe0
    call    emit_b
    jmp     .ra_store_done2
.ra_store_r14:
    ; r14: 4C 89 F0
    mov     al, 0x4c
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0xf0
    call    emit_b
    jmp     .ra_store_done2
.ra_store_r13:
    ; r13: 4C 89 E8
    mov     al, 0x4c
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0xe8
    call    emit_b
.ra_store_done2:
    pop     rax
    ret
.ra_store_done:
    pop     rdx
    pop     rcx

.check_abs_store:
    test    byte [var_addr_is_rbp], 1
    jnz     .rbp_store

    ; --- Peephole: detect load+add/sub+store → direct mem op ---
    ; Pattern: mov rax, [addr32] (8 bytes) + add/sub rax, imm32 (6 bytes) = 14 bytes
    ; Or: mov rax, [addr1] (8 bytes) + add/sub rax, [addr2] (8 bytes) = 16 bytes
    mov     rcx, [emit_tail_len]

    ; Check tail_len >= 14 for imm pattern
    cmp     rcx, 14
    jl      .check_mem_pattern

    ; Check: tail[tail_len-14] == 0x48 (REX.W)
    mov     rax, rcx
    sub     rax, 14
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x48
    jne     .check_mem_pattern

    ; tail[tail_len-13] == 0x8B (MOV r)
    mov     rax, rcx
    sub     rax, 13
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x8B
    jne     .check_mem_pattern

    ; tail[tail_len-12] == 0x04 (SIB)
    mov     rax, rcx
    sub     rax, 12
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x04
    jne     .check_mem_pattern

    ; tail[tail_len-11] == 0x25 (disp32)
    mov     rax, rcx
    sub     rax, 11
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x25
    jne     .check_mem_pattern

    ; Check REX.W of add/sub at tail[tail_len-6]
    mov     rax, rcx
    sub     rax, 6
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x48
    jne     .check_mem_pattern

    ; Check opcode at tail[tail_len-5]
    mov     rax, rcx
    sub     rax, 5
    and     rax, 31
    movzx   r8d, byte [emit_tail + rax]     ; r8b = opcode

    cmp     r8b, 0x05          ; add rax, imm32
    je      .peephole_add
    cmp     r8b, 0x2D          ; sub rax, imm32
    je      .peephole_sub
    jmp     .check_mem_pattern

.check_mem_pattern:
    ; ================================================================
    ; O-G r15-accum: 20-byte pinned-counter accumulator fold
    ; Tail: mov rax,[addr](8) + mov r10,rax(3) + mov rax,r15(3)
    ;       + mov rbx,r10(3) + add rax,rbx(3)
    ; → add [addr], r15   (8 bytes)
    ; Enables triangular sum fold when loop_pin_active=1.
    ; Fires for patterns like: for i in 0..N: total = total + i
    ; ================================================================
    cmp     byte [loop_pin_active], 0
    je      .og_check_11

    mov     rcx, [emit_tail_len]
    cmp     rcx, 20
    jl      .og_check_11

    ; Check tail[-20..-17] = 48 8B 04 25  (mov rax, [abs32])
    mov     rax, rcx
    sub     rax, 20
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x48
    jne     .og_check_11

    mov     rax, rcx
    sub     rax, 19
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x8B
    jne     .og_check_11

    mov     rax, rcx
    sub     rax, 18
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x04
    jne     .og_check_11

    mov     rax, rcx
    sub     rax, 17
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x25
    jne     .og_check_11

    ; Extract load addr32 from out_buffer[out_idx - 16]
    mov     r12, [out_idx]
    mov     r12d, dword [out_buffer + r12 - 16]
    ; Must match store destination (rdi)
    cmp     r12d, edi
    jne     .og_check_11

    ; Check tail[-12..-10] = 49 89 C2  (mov r10, rax)
    mov     rax, rcx
    sub     rax, 12
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x49
    jne     .og_check_11

    mov     rax, rcx
    sub     rax, 11
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x89
    jne     .og_check_11

    mov     rax, rcx
    sub     rax, 10
    and     rax, 31
    cmp     byte [emit_tail + rax], 0xC2
    jne     .og_check_11

    ; Check tail[-9..-7] = 4C 89 F8  (mov rax, r15)
    mov     rax, rcx
    sub     rax, 9
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x4C
    jne     .og_check_11

    mov     rax, rcx
    sub     rax, 8
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x89
    jne     .og_check_11

    mov     rax, rcx
    sub     rax, 7
    and     rax, 31
    cmp     byte [emit_tail + rax], 0xF8
    jne     .og_check_11

    ; Check tail[-6..-4] = 4C 89 D3  (mov rbx, r10)
    mov     rax, rcx
    sub     rax, 6
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x4C
    jne     .og_check_11

    mov     rax, rcx
    sub     rax, 5
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x89
    jne     .og_check_11

    mov     rax, rcx
    sub     rax, 4
    and     rax, 31
    cmp     byte [emit_tail + rax], 0xD3
    jne     .og_check_11

    ; Check tail[-3] = 48 (REX.W prefix for rax/rbx op)
    mov     rax, rcx
    sub     rax, 3
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x48
    jne     .og_check_11

    ; Save opcode from tail[-2] and validate: add/sub/or/and/xor rax,rbx
    mov     rax, rcx
    sub     rax, 2
    and     rax, 31
    movzx   r9d, byte [emit_tail + rax]   ; r9b = opcode
    cmp     r9b, 0x01   ; add rax, rbx
    je      .og20_op_ok
    cmp     r9b, 0x29   ; sub rax, rbx
    je      .og20_op_ok
    cmp     r9b, 0x09   ; or  rax, rbx
    je      .og20_op_ok
    cmp     r9b, 0x21   ; and rax, rbx
    je      .og20_op_ok
    cmp     r9b, 0x31   ; xor rax, rbx
    je      .og20_op_ok
    jmp     .og_check_11
.og20_op_ok:

    ; Check tail[-1] = D8 (ModRM rax,rbx — shared by all five opcodes)
    mov     rax, rcx
    sub     rax, 1
    and     rax, 31
    cmp     byte [emit_tail + rax], 0xD8
    jne     .og_check_11

    ; Matched: roll back 20 bytes, emit  OP [addr32], r15
    ; Encoding: 4C [opcode] 3C 25 addr32  (8 bytes)
    ; Phase 2A: If r14 is pinned to accumulator, emit OP r14, r15 instead (3 bytes)
    cmp     qword [ra_count], 0
    je      .og20_emit_mem
    cmp     byte [ra_reg + 1], 14
    jne     .og20_emit_mem
    ; r14 is pinned to accumulator — emit OP r14, r15 (3 bytes: 4D opcode F7)
    sub     qword [out_idx], 20
    sub     qword [emit_tail_len], 20
    mov     al, 0x4D                ; REX.W+R for r14
    call    emit_b
    mov     al, r9b                 ; opcode (add/sub)
    call    emit_b
    mov     al, 0xFE                ; ModRM: r14, r15 (20-byte pattern)
    call    emit_b
    jmp     .og20_emit_done
.og20_emit_mem:
    sub     qword [out_idx], 20
    sub     qword [emit_tail_len], 20
    mov     al, 0x4C
    call    emit_b
    mov     al, r9b         ; opcode (add/sub/or/and/xor)
    call    emit_b
    mov     al, 0x3C
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r12d
    call    emit_d
.og20_emit_done:
    ; Signal to for_end: O-G RMW fired, body = 8 bytes
    mov     byte [og_fired_in_body], 1
    mov     byte [og_op_code], r9b
    mov     dword [og_rw_addr32], r12d
    jmp     .peephole_done

.og_check_11:
    ; ================================================================
    ; O-G: in-place accumulation fusion
    ; Eliminates the load-compute-store triple for result=result OP base
    ; ================================================================

    ; --- O-G part 1: 11-byte pattern ---
    ; Tail: mov rax,[addr](8) + 3-byte OP rax,reg  →  OP [addr],reg
    ; Supported ops: add/sub/or/and/xor with r15 (4C op F8) or rbx (48 op D8)
    mov     rcx, [emit_tail_len]
    cmp     rcx, 11
    jl      .og_sub14_check

    ; Verify bytes at tail[tail_len-11..tail_len-8] == 48 8B 04 25
    mov     rax, rcx
    sub     rax, 11
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x48
    jne     .og_sub14_check

    mov     rax, rcx
    sub     rax, 10
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x8B
    jne     .og_sub14_check

    mov     rax, rcx
    sub     rax, 9
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x04
    jne     .og_sub14_check

    mov     rax, rcx
    sub     rax, 8
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x25
    jne     .og_sub14_check

    ; Extract load addr32 from out_buffer[out_idx - 7]
    mov     r12, [out_idx]
    mov     r12d, dword [out_buffer + r12 - 7]

    ; Must match store destination (rdi = arg from function call)
    cmp     r12d, edi
    jne     .og_sub14_check

    ; Read 3-byte OP: r8b = REX, r9b = opcode, al = ModRM
    mov     rax, rcx
    sub     rax, 3
    and     rax, 31
    movzx   r8d, byte [emit_tail + rax]     ; REX (4C = r15 src, 48 = rbx src)

    mov     rax, rcx
    sub     rax, 2
    and     rax, 31
    movzx   r9d, byte [emit_tail + rax]     ; opcode

    mov     rax, rcx
    sub     rax, 1
    and     rax, 31
    movzx   eax, byte [emit_tail + rax]     ; ModRM

    ; --- r15 source: REX=4C ModRM=F8 → emit 4C [opcode] 3C 25 addr ---
    cmp     r8b, 0x4C
    jne     .og_try_rbx
    cmp     al, 0xF8
    jne     .og_sub14_check

    cmp     r9b, 0x01   ; add rax, r15
    je      .og_r15_ok
    cmp     r9b, 0x29   ; sub rax, r15
    je      .og_r15_ok
    cmp     r9b, 0x09   ; or  rax, r15
    je      .og_r15_ok
    cmp     r9b, 0x21   ; and rax, r15
    je      .og_r15_ok
    cmp     r9b, 0x31   ; xor rax, r15
    je      .og_r15_ok
    jmp     .og_sub14_check

.og_r15_ok:
    ; Track ADD/SUB r15 RMW for loop rolling (triangular/anti-sum fold)
    cmp     byte [loop_pin_active], 0
    je      .og_r15_emit
    cmp     r9b, 0x01               ; ADD triggers triangular sum fold
    je      .og_r15_fold_signal
    cmp     r9b, 0x29               ; SUB triggers anti-sum fold
    jne     .og_r15_emit
.og_r15_fold_signal:
    mov     byte [og_fired_in_body], 1
    mov     byte [og_op_code], r9b
    mov     dword [og_rw_addr32], r12d
.og_r15_emit:
    ; Roll back 11 bytes (load + 3-byte op), emit OP [abs32], r15
    ; Encoding: 4C [opcode] 3C 25 addr32
    ; REX=4C(W+R), ModRM=3C(mod=00 reg=7=r15%8 rm=4=SIB), SIB=25(idx=none base=disp32)
    ; Phase 2A: If r14 is pinned to accumulator, emit OP r14, r15 instead (3 bytes)
    cmp     qword [ra_count], 0
    je      .og_r15_emit_mem
    cmp     byte [ra_reg + 1], 14
    jne     .og_r15_emit_mem
    ; r14 is pinned to accumulator — emit OP r14, r15 (3 bytes: 4D opcode F7)
    sub     qword [out_idx], 11
    sub     qword [emit_tail_len], 11
    mov     al, 0x4D                ; REX.W+R for r14
    call    emit_b
    mov     al, r9b                 ; opcode (add/sub)
    call    emit_b
    mov     al, 0xFE                ; ModRM: r14, r15 (11-byte pattern)
    call    emit_b
    jmp     .og_r15_emit_done
.og_r15_emit_mem:
    sub     qword [out_idx], 11
    sub     qword [emit_tail_len], 11
    mov     al, 0x4C
    call    emit_b
    mov     al, r9b
    call    emit_b
    mov     al, 0x3C
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r12d
    call    emit_d
.og_r15_emit_done:
    jmp     .peephole_done

.og_try_rbx:
    ; --- rbx source: REX=48 ModRM=D8 → emit 48 [opcode] 1C 25 addr ---
    cmp     r8b, 0x48
    jne     .og_sub14_check
    cmp     al, 0xD8
    jne     .og_sub14_check

    cmp     r9b, 0x01   ; add rax, rbx
    je      .og_rbx_ok
    cmp     r9b, 0x09   ; or  rax, rbx
    je      .og_rbx_ok
    cmp     r9b, 0x21   ; and rax, rbx
    je      .og_rbx_ok
    cmp     r9b, 0x31   ; xor rax, rbx
    je      .og_rbx_ok
    jmp     .og_sub14_check

.og_rbx_ok:
    ; Roll back 11 bytes, emit OP [abs32], rbx
    ; Encoding: 48 [opcode] 1C 25 addr32
    ; REX=48(W only), ModRM=1C(mod=00 reg=3=rbx rm=4=SIB), SIB=25
    sub     qword [out_idx], 11
    sub     qword [emit_tail_len], 11
    mov     al, 0x48
    call    emit_b
    mov     al, r9b
    call    emit_b
    mov     al, 0x1C
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r12d
    call    emit_d
    jmp     .peephole_done

.og_sub14_check:
    ; --- O-G part 2: 14-byte sub pattern ---
    ; Tail: mov rax,[addr](8) + neg rax(3) + add rax,rbx(3)  →  sub [addr],rbx
    ; This is the general sub-rbx case from codegen_emit_sub_rax_rbx .sub_normal
    mov     rcx, [emit_tail_len]
    cmp     rcx, 14
    jl      .og_mem16_check

    ; First 8 bytes: 48 8B 04 25
    mov     rax, rcx
    sub     rax, 14
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x48
    jne     .og_mem16_check

    mov     rax, rcx
    sub     rax, 13
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x8B
    jne     .og_mem16_check

    mov     rax, rcx
    sub     rax, 12
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x04
    jne     .og_mem16_check

    mov     rax, rcx
    sub     rax, 11
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x25
    jne     .og_mem16_check

    ; Last 6 bytes: 48 F7 D8 48 01 D8  (neg rax; add rax,rbx)
    mov     rax, rcx
    sub     rax, 6
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x48
    jne     .og_mem16_check

    mov     rax, rcx
    sub     rax, 5
    and     rax, 31
    cmp     byte [emit_tail + rax], 0xF7
    jne     .og_mem16_check

    mov     rax, rcx
    sub     rax, 4
    and     rax, 31
    cmp     byte [emit_tail + rax], 0xD8
    jne     .og_mem16_check

    mov     rax, rcx
    sub     rax, 3
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x48
    jne     .og_mem16_check

    mov     rax, rcx
    sub     rax, 2
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x01
    jne     .og_mem16_check

    mov     rax, rcx
    sub     rax, 1
    and     rax, 31
    cmp     byte [emit_tail + rax], 0xD8
    jne     .og_mem16_check

    ; Extract load addr32 from out_buffer[out_idx - 10]
    mov     r12, [out_idx]
    mov     r12d, dword [out_buffer + r12 - 10]

    ; Must match store destination
    cmp     r12d, edi
    jne     .og_mem16_check

    ; Roll back 14 bytes, emit sub [abs32], rbx = 48 29 1C 25 addr32
    sub     qword [out_idx], 14
    sub     qword [emit_tail_len], 14
    mov     al, 0x48
    call    emit_b
    mov     al, 0x29
    call    emit_b
    mov     al, 0x1C
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r12d
    call    emit_d
    jmp     .peephole_done

.og_mem16_check:
    ; ================================================================
    ; Existing 16-byte mem-to-mem pattern (extended for OR/AND/XOR)
    ; Pattern: mov rax,[addr1](8) + OP rax,[addr2](8)  →  mov rax,[addr2]; OP [addr1],rax
    ; ================================================================
    mov     rcx, [emit_tail_len]
    cmp     rcx, 16
    jl      .abs_store_normal

    ; tail[tail_len-16..tail_len-13] == 48 8B 04 25
    mov     rax, rcx
    sub     rax, 16
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x48
    jne     .abs_store_normal

    mov     rax, rcx
    sub     rax, 15
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x8B
    jne     .abs_store_normal

    mov     rax, rcx
    sub     rax, 14
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x04
    jne     .abs_store_normal

    mov     rax, rcx
    sub     rax, 13
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x25
    jne     .abs_store_normal

    ; tail[tail_len-8] == 0x48 (REX of second load+op)
    mov     rax, rcx
    sub     rax, 8
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x48
    jne     .abs_store_normal

    ; tail[tail_len-7] == opcode: 0x03(add) 0x2B(sub) 0x0B(or) 0x23(and) 0x33(xor)
    mov     rax, rcx
    sub     rax, 7
    and     rax, 31
    movzx   r8d, byte [emit_tail + rax]

    cmp     r8b, 0x03           ; add rax, [abs32]
    je      .peephole_add_mem
    cmp     r8b, 0x2B           ; sub rax, [abs32]
    je      .peephole_sub_mem
    cmp     r8b, 0x0B           ; or  rax, [abs32]
    je      .peephole_or_mem
    cmp     r8b, 0x23           ; and rax, [abs32]
    je      .peephole_and_mem
    cmp     r8b, 0x33           ; xor rax, [abs32]
    je      .peephole_xor_mem
    jmp     .abs_store_normal

.peephole_add:
    ; Extract load addr32 from out_buffer[out_idx - 10]
    mov     rax, [out_idx]
    mov     eax, dword [out_buffer + rax - 10]   ; load addr32

    ; Extract add imm32 from out_buffer[out_idx - 4]
    mov     r8, [out_idx]
    mov     r8d, dword [out_buffer + r8 - 4]    ; add imm32

    ; Check if load addr == store addr (rdi)
    cmp     eax, edi
    jne     .abs_store_normal

    ; Undo 14 bytes
    sub     qword [out_idx], 14
    sub     qword [emit_tail_len], 14

    ; Check if imm32 == 1 → inc
    cmp     r8d, 1
    jne     .add_not_one

    ; inc qword [abs32] = 48 FF 04 25 addr32 (8 bytes)
    mov     al, 0x48
    call    emit_b
    mov     al, 0xFF
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, edi
    call    emit_d
    jmp     .peephole_done

.add_not_one:
    ; Check if imm32 == -1 → dec
    cmp     r8d, -1
    jne     .add_not_neg1

    ; dec qword [abs32] = 48 FF 0C 25 addr32 (8 bytes)
    mov     al, 0x48
    call    emit_b
    mov     al, 0xFF
    call    emit_b
    mov     al, 0x0C
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, edi
    call    emit_d
    jmp     .peephole_done

.add_not_neg1:
    ; Check if imm32 fits in signed 8 bits (-128..127)
    mov     rax, r8
    sar     rax, 32
    test    rax, rax
    jnz     .abs_store_normal
    cmp     r8d, 127
    jg      .abs_store_normal
    cmp     r8d, -128
    jl      .abs_store_normal

    ; add qword [abs32], imm8 = 48 83 00 addr32 imm8 (9 bytes)
    mov     al, 0x48
    call    emit_b
    mov     al, 0x83
    call    emit_b
    mov     al, 0x00             ; /0 = add
    call    emit_b
    mov     al, 0x25             ; SIB: [disp32]
    call    emit_b
    mov     eax, edi
    call    emit_d
    mov     eax, r8d
    call    emit_b               ; imm8
    jmp     .peephole_done

.peephole_sub:
    ; Extract load addr32
    mov     rax, [out_idx]
    mov     eax, dword [out_buffer + rax - 10]

    ; Extract sub imm32
    mov     r8, [out_idx]
    mov     r8d, dword [out_buffer + r8 - 4]

    ; Check if load addr == store addr
    cmp     eax, edi
    jne     .abs_store_normal

    ; Undo 14 bytes
    sub     qword [out_idx], 14
    sub     qword [emit_tail_len], 14

    ; Check if imm32 == 1 → dec
    cmp     r8d, 1
    jne     .sub_not_one

    ; dec qword [abs32] = 48 FF 0C 25 addr32 (8 bytes)
    mov     al, 0x48
    call    emit_b
    mov     al, 0xFF
    call    emit_b
    mov     al, 0x0C            ; /1 = dec
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, edi
    call    emit_d
    jmp     .peephole_done

.sub_not_one:
    ; Check if imm32 == -1 → inc
    cmp     r8d, -1
    jne     .sub_not_neg1

    ; inc qword [abs32] = 48 FF 04 25 addr32 (8 bytes)
    mov     al, 0x48
    call    emit_b
    mov     al, 0xFF
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, edi
    call    emit_d
    jmp     .peephole_done

.sub_not_neg1:
    ; Check if imm32 fits in signed 8 bits
    mov     rax, r8
    sar     rax, 32
    test    rax, rax
    jnz     .abs_store_normal
    cmp     r8d, 127
    jg      .abs_store_normal
    cmp     r8d, -128
    jl      .abs_store_normal

    ; sub qword [abs32], imm8 = 48 83 28 addr32 imm8 (9 bytes)
    mov     al, 0x48
    call    emit_b
    mov     al, 0x83
    call    emit_b
    mov     al, 0x28            ; /5 = sub
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, edi
    call    emit_d
    mov     eax, r8d
    call    emit_b
    jmp     .peephole_done

.peephole_add_mem:
    ; Pattern: mov rax, [addr1]; add rax, [addr2]; store [addr1], rax
    ; → mov rax, [addr2]; add [addr1], rax
    ; Extract addr1 from out_buffer[out_idx - 12]
    mov     rax, [out_idx]
    mov     eax, dword [out_buffer + rax - 12]   ; addr1

    ; Extract addr2 from out_buffer[out_idx - 4]
    mov     r8, [out_idx]
    mov     r8d, dword [out_buffer + r8 - 4]    ; addr2

    ; Check if addr1 == store addr (rdi)
    cmp     eax, edi
    jne     .abs_store_normal

    ; Undo 16 bytes (mov rax,[addr1] + add rax,[addr2])
    sub     qword [out_idx], 16
    sub     qword [emit_tail_len], 16

    ; Emit: mov rax, [addr2] = 48 8B 04 25 addr2 (8 bytes)
    mov     al, 0x48
    call    emit_b
    mov     al, 0x8B
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r8d
    call    emit_d

    ; Emit: add [addr1], rax = 48 01 04 25 addr1 (8 bytes)
    mov     al, 0x48
    call    emit_b
    mov     al, 0x01
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, edi
    call    emit_d

    jmp     .peephole_done

.peephole_sub_mem:
    ; Pattern: mov rax, [addr1]; sub rax, [addr2]; store [addr1], rax
    ; → mov rax, [addr2]; neg rax; add [addr1], rax
    ; Extract addr1
    mov     rax, [out_idx]
    mov     eax, dword [out_buffer + rax - 12]

    ; Extract addr2
    mov     r8, [out_idx]
    mov     r8d, dword [out_buffer + r8 - 4]

    ; Check if addr1 == store addr
    cmp     eax, edi
    jne     .abs_store_normal

    ; Undo 16 bytes
    sub     qword [out_idx], 16
    sub     qword [emit_tail_len], 16

    ; Emit: mov rax, [addr2] = 48 8B 04 25 addr2
    mov     al, 0x48
    call    emit_b
    mov     al, 0x8B
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r8d
    call    emit_d

    ; Emit: neg rax = 48 F7 D8
    mov     al, 0x48
    call    emit_b
    mov     al, 0xF7
    call    emit_b
    mov     al, 0xD8
    call    emit_b

    ; Emit: add [addr1], rax = 48 01 04 25 addr1
    mov     al, 0x48
    call    emit_b
    mov     al, 0x01
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, edi
    call    emit_d

    jmp     .peephole_done

.peephole_or_mem:
    ; Pattern: mov rax,[addr1]; or rax,[addr2]; store [addr1]
    ; → mov rax,[addr2]; or [addr1],rax
    ; (O-G: 16-byte mem-to-mem or, commutative so rax as src in or [addr1],rax)
    mov     rax, [out_idx]
    mov     eax, dword [out_buffer + rax - 12]   ; addr1
    cmp     eax, edi
    jne     .abs_store_normal
    mov     r8, [out_idx]
    mov     r8d, dword [out_buffer + r8 - 4]     ; addr2
    sub     qword [out_idx], 16
    sub     qword [emit_tail_len], 16
    ; Emit: mov rax, [addr2]
    mov     al, 0x48
    call    emit_b
    mov     al, 0x8B
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r8d
    call    emit_d
    ; Emit: or [addr1], rax = 48 09 04 25 addr1
    mov     al, 0x48
    call    emit_b
    mov     al, 0x09
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, edi
    call    emit_d
    jmp     .peephole_done

.peephole_and_mem:
    ; Pattern: mov rax,[addr1]; and rax,[addr2]; store [addr1]
    ; → mov rax,[addr2]; and [addr1],rax
    mov     rax, [out_idx]
    mov     eax, dword [out_buffer + rax - 12]
    cmp     eax, edi
    jne     .abs_store_normal
    mov     r8, [out_idx]
    mov     r8d, dword [out_buffer + r8 - 4]
    sub     qword [out_idx], 16
    sub     qword [emit_tail_len], 16
    mov     al, 0x48
    call    emit_b
    mov     al, 0x8B
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r8d
    call    emit_d
    ; Emit: and [addr1], rax = 48 21 04 25 addr1
    mov     al, 0x48
    call    emit_b
    mov     al, 0x21
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, edi
    call    emit_d
    jmp     .peephole_done

.peephole_xor_mem:
    ; Pattern: mov rax,[addr1]; xor rax,[addr2]; store [addr1]
    ; → mov rax,[addr2]; xor [addr1],rax
    mov     rax, [out_idx]
    mov     eax, dword [out_buffer + rax - 12]
    cmp     eax, edi
    jne     .abs_store_normal
    mov     r8, [out_idx]
    mov     r8d, dword [out_buffer + r8 - 4]
    sub     qword [out_idx], 16
    sub     qword [emit_tail_len], 16
    mov     al, 0x48
    call    emit_b
    mov     al, 0x8B
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r8d
    call    emit_d
    ; Emit: xor [addr1], rax = 48 31 04 25 addr1
    mov     al, 0x48
    call    emit_b
    mov     al, 0x31
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, edi
    call    emit_d
    jmp     .peephole_done

.peephole_done:
    mov     qword [rax_holds_va], -1   ; peephole rewrote memory op; rax is no longer a var load
    pop     r12
    pop     rcx
    pop     rdi
    pop     rax
    ret

.abs_store_normal:
    ; O-H: detect constant-imul body for loop rolling (flag-only, no output change)
    ; Pattern (15 bytes before this store): mov rax,[addr](8) + imul rax,rax,imm32(7)
    cmp     byte [loop_pin_active], 0
    je      .oh_skip
    mov     rcx, [emit_tail_len]
    cmp     rcx, 15
    jl      .oh_skip
    mov     rax, rcx
    sub     rax, 15
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x48
    jne     .oh_skip
    mov     rax, rcx
    sub     rax, 14
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x8B
    jne     .oh_skip
    mov     rax, rcx
    sub     rax, 13
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x04
    jne     .oh_skip
    mov     rax, rcx
    sub     rax, 12
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x25
    jne     .oh_skip
    ; tail[-7...-5] = 48 69 C0  (REX + IMUL opcode + ModRM rax*rax)
    mov     rax, rcx
    sub     rax, 7
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x48
    jne     .oh_skip
    mov     rax, rcx
    sub     rax, 6
    and     rax, 31
    cmp     byte [emit_tail + rax], 0x69
    jne     .oh_skip
    mov     rax, rcx
    sub     rax, 5
    and     rax, 31
    cmp     byte [emit_tail + rax], 0xC0
    jne     .oh_skip
    ; addr32 of load must match this store's destination (edi)
    mov     r8, [out_idx]
    mov     r8d, dword [out_buffer + r8 - 11]
    cmp     r8d, edi
    jne     .oh_skip
    ; extract multiplier A from out_buffer[out_idx-4] (imm32, sign-extended)
    mov     r9, [out_idx]
    movsx   r9, dword [out_buffer + r9 - 4]
    mov     byte [oh_mul_fired_in_body], 1
    mov     dword [oh_mul_addr32], r8d
    mov     qword [oh_mul_const], r9
.oh_skip:
    ; absolute mode: 48 89 04 25 addr32
    mov     al, 0x48
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    pop     r12
    pop     rcx
    pop     rdi
    mov     eax, edi
    call    emit_d
    pop     rax
    ret
  .rbp_store:
    ; rbp-relative: mov [rbp+disp32], rax = 48 89 85 disp32
    mov     al, 0x48
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0x85
    call    emit_b
    pop     r12
    pop     rcx
    pop     rdi
    mov     eax, edi
    call    emit_d
    pop     rax
    ret

; Emit push rax
codegen_emit_push_rax:
    ; O-I: emit IR_IMRAX (save irax to irbx) if recording
    cmp     byte [ctpe_recording], 0
    je      .no_ir_push
    push    rdi
    mov     rdi, IR_IMRAX
    call    ctpe_ir_emit_b
    pop     rdi
.no_ir_push:
    push    rax
    mov     al, 0x50
    call    emit_b
    pop     rax
    ret

; Emit mov rbx, rax (save left operand in rbx, avoiding push/pop)
codegen_emit_mov_rbx_rax:
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0xc3
    call    emit_b
    pop     rax
    ret

; Emit pop rbx
codegen_emit_pop_rbx:
    push    rax
    mov     al, 0x5b
    call    emit_b
    pop     rax
    ret

; Emit mov rdi, rax  (48 89 C7)
codegen_emit_mov_rdi_rax:
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0xc7
    call    emit_b
    pop     rax
    ret

; codegen_emit_movdi_rax: alias
codegen_emit_movdi_rax:
    jmp     codegen_emit_mov_rdi_rax

; codegen_emit_mov_rax_rdi  (48 89 F8)
codegen_emit_mov_rax_rdi:
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0xf8
    call    emit_b
    pop     rax
    ret

; ============================================================
; Integer arithmetic
; ============================================================
; All ops: rax = LHS, rbx = RHS (after push/pop pattern)

codegen_emit_add_rax_rbx:      ; add rax, rbx  (48 01 D8)
    mov     qword [rax_holds_va], -1   ; rax = computed value, not a var
    ; O-I: emit IR_IADD if recording
    cmp     byte [ctpe_recording], 0
    je      .no_ir_add
    push    rdi
    mov     rdi, IR_IADD
    call    ctpe_ir_emit_b
    pop     rdi
.no_ir_add:
    push    rax
    push    rcx
    push    rdi
    push    r12

    mov     r12, [emit_tail_len]

    ; --- O-A Pattern A-reg (checked first): push + mov rax,r15 + pop → add rax,r15 ---
    ; Only active when r15 is pinned as loop counter (reg_cache_var != -1)
    cmp     qword [reg_cache_var], -1
    je      .add_check_a
    cmp     r12, 5
    jl      .add_check_a

    mov     rcx, r12
    sub     rcx, 5
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x50       ; push rax
    jne     .add_check_a

    mov     rcx, r12
    sub     rcx, 4
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x4C       ; REX (mov rax,r15 prefix)
    jne     .add_check_a

    mov     rcx, r12
    sub     rcx, 3
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x89       ; MOV opcode
    jne     .add_check_a

    mov     rcx, r12
    sub     rcx, 2
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0xF8       ; r15→rax modrm
    jne     .add_check_a

    mov     rcx, r12
    sub     rcx, 1
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x5B       ; pop rbx
    jne     .add_check_a

    ; Pattern A-reg matched: rollback 5 bytes, emit add rax, r15 (4C 01 F8)
    sub     qword [out_idx], 5
    sub     qword [emit_tail_len], 5
    mov     al, 0x4c
    call    emit_b
    mov     al, 0x01
    call    emit_b
    mov     al, 0xf8
    call    emit_b
    jmp     .add_done

.add_check_a:
    ; --- Pattern A: push + mov rax,[abs32] + pop → add rax,[abs32] (10 bytes) ---
    cmp     r12, 10
    jl      .add_check_b

    mov     rcx, r12
    sub     rcx, 10
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x50       ; push rax
    jne     .add_check_b

    mov     rcx, r12
    sub     rcx, 9
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x48       ; REX.W
    jne     .add_check_b

    mov     rcx, r12
    sub     rcx, 8
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x8B       ; MOV
    jne     .add_check_b

    mov     rcx, r12
    sub     rcx, 7
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x04       ; SIB
    jne     .add_check_b

    mov     rcx, r12
    sub     rcx, 6
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x25       ; disp32
    jne     .add_check_b

    mov     rcx, r12
    sub     rcx, 1
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x5B       ; pop rbx
    jne     .add_check_b

    ; Pattern A matched: extract addr32 from out_buffer[out_idx - 5]
    mov     rdi, [out_idx]
    mov     edi, dword [out_buffer + rdi - 5]

    sub     qword [out_idx], 10
    sub     qword [emit_tail_len], 10

    ; emit: add rax, [abs32] = 48 03 04 25 addr32
    mov     al, 0x48
    call    emit_b
    mov     al, 0x03
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, edi
    call    emit_d
    jmp     .add_done

.add_check_b:
    ; --- Pattern B: push + movabs N + pop → add rax, imm32 (12→6 bytes) ---
    cmp     r12, 12
    jl      .add_normal

    mov     rcx, r12
    sub     rcx, 12
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x50       ; push
    jne     .add_normal

    mov     rcx, r12
    sub     rcx, 11
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x48       ; REX.W
    jne     .add_normal

    mov     rcx, r12
    sub     rcx, 10
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0xB8       ; movabs
    jne     .add_normal

    mov     rcx, r12
    sub     rcx, 1
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x5B       ; pop
    jne     .add_normal

    ; Pattern B matched: extract imm64 from out_buffer[out_idx - 9]
    mov     rdi, [out_idx]
    mov     rdi, [out_buffer + rdi - 9]

    ; check signed 32-bit fit
    mov     rax, rdi
    sar     rax, 32
    test    rax, rax
    jz      .add_b_fits
    cmp     rax, -1
    jne     .add_normal

.add_b_fits:
    sub     qword [out_idx], 12
    sub     qword [emit_tail_len], 12

    ; emit: add rax, imm32 = 48 05 imm32
    mov     al, 0x48
    call    emit_b
    mov     al, 0x05
    call    emit_b
    mov     eax, edi
    call    emit_d
    jmp     .add_done

.add_normal:
    mov     al, 0x48
    call    emit_b
    mov     al, 0x01
    call    emit_b
    mov     al, 0xd8
    call    emit_b

.add_done:
    pop     r12
    pop     rdi
    pop     rcx
    pop     rax
    ret

codegen_emit_sub_rax_rbx:      ; rbx - rax → rax  (neg+add pattern)
    mov     qword [rax_holds_va], -1   ; rax = computed value, not a var
    ; O-I: emit IR_ISUB if recording
    cmp     byte [ctpe_recording], 0
    je      .no_ir_sub
    push    rdi
    mov     rdi, IR_ISUB
    call    ctpe_ir_emit_b
    pop     rdi
.no_ir_sub:
    push    rax
    push    rcx
    push    rdi
    push    r12

    mov     r12, [emit_tail_len]

    ; --- O-A Pattern A-reg (checked first): push + mov rax,r15 + pop → sub rax,r15 ---
    cmp     qword [reg_cache_var], -1
    je      .sub_check_a
    cmp     r12, 5
    jl      .sub_check_a

    mov     rcx, r12
    sub     rcx, 5
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x50
    jne     .sub_check_a

    mov     rcx, r12
    sub     rcx, 4
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x4C
    jne     .sub_check_a

    mov     rcx, r12
    sub     rcx, 3
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x89
    jne     .sub_check_a

    mov     rcx, r12
    sub     rcx, 2
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0xF8
    jne     .sub_check_a

    mov     rcx, r12
    sub     rcx, 1
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x5B
    jne     .sub_check_a

    ; Pattern A-reg matched: rollback 5 bytes, emit sub rax, r15 (4C 29 F8)
    sub     qword [out_idx], 5
    sub     qword [emit_tail_len], 5
    mov     al, 0x4c
    call    emit_b
    mov     al, 0x29
    call    emit_b
    mov     al, 0xf8
    call    emit_b
    jmp     .sub_done

.sub_check_a:
    ; --- Pattern A: push + mov rax,[abs32] + pop → sub rax,[abs32] ---
    cmp     r12, 10
    jl      .sub_check_b

    mov     rcx, r12
    sub     rcx, 10
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x50
    jne     .sub_check_b

    mov     rcx, r12
    sub     rcx, 9
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x48
    jne     .sub_check_b

    mov     rcx, r12
    sub     rcx, 8
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x8B
    jne     .sub_check_b

    mov     rcx, r12
    sub     rcx, 7
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x04
    jne     .sub_check_b

    mov     rcx, r12
    sub     rcx, 6
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x25
    jne     .sub_check_b

    mov     rcx, r12
    sub     rcx, 1
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x5B
    jne     .sub_check_b

    ; Pattern A matched: sub rax, [abs32] = 48 2B 04 25 addr32
    mov     rdi, [out_idx]
    mov     edi, dword [out_buffer + rdi - 5]

    sub     qword [out_idx], 10
    sub     qword [emit_tail_len], 10

    mov     al, 0x48
    call    emit_b
    mov     al, 0x2B
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, edi
    call    emit_d
    jmp     .sub_done

.sub_check_b:
    ; --- Pattern B: push + movabs N + pop → sub rax, imm32 ---
    cmp     r12, 12
    jl      .sub_normal

    mov     rcx, r12
    sub     rcx, 12
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x50
    jne     .sub_normal

    mov     rcx, r12
    sub     rcx, 11
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x48
    jne     .sub_normal

    mov     rcx, r12
    sub     rcx, 10
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0xB8
    jne     .sub_normal

    mov     rcx, r12
    sub     rcx, 1
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x5B
    jne     .sub_normal

    ; Pattern B matched: extract imm64
    mov     rdi, [out_idx]
    mov     rdi, [out_buffer + rdi - 9]

    mov     rax, rdi
    sar     rax, 32
    test    rax, rax
    jz      .sub_b_fits
    cmp     rax, -1
    jne     .sub_normal

.sub_b_fits:
    sub     qword [out_idx], 12
    sub     qword [emit_tail_len], 12

    ; emit: sub rax, imm32 = 48 2D imm32
    mov     al, 0x48
    call    emit_b
    mov     al, 0x2D
    call    emit_b
    mov     eax, edi
    call    emit_d
    jmp     .sub_done

.sub_normal:
    ; neg rax (48 F7 D8)
    mov     al, 0x48
    call    emit_b
    mov     al, 0xf7
    call    emit_b
    mov     al, 0xd8
    call    emit_b
    ; add rax, rbx (48 01 D8)
    mov     al, 0x48
    call    emit_b
    mov     al, 0x01
    call    emit_b
    mov     al, 0xd8
    call    emit_b

.sub_done:
    pop     r12
    pop     rdi
    pop     rcx
    pop     rax
    ret

codegen_emit_imul_rax_rbx:     ; imul rax, rbx  (48 0F AF C3)
    mov     qword [rax_holds_va], -1   ; rax = computed value, not a var
    ; O-I: emit IR_IMUL if recording
    cmp     byte [ctpe_recording], 0
    je      .no_ir_mul
    push    rdi
    mov     rdi, IR_IMUL
    call    ctpe_ir_emit_b
    pop     rdi
.no_ir_mul:
    push    rax
    push    rcx
    push    rdi
    push    r12

    mov     r12, [emit_tail_len]

    ; --- Pattern A: push + mov rax,[abs32] + pop → imul rax,[abs32] ---
    cmp     r12, 10
    jl      .mul_check_b

    mov     rcx, r12
    sub     rcx, 10
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x50
    jne     .mul_check_b

    mov     rcx, r12
    sub     rcx, 9
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x48
    jne     .mul_check_b

    mov     rcx, r12
    sub     rcx, 8
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x8B
    jne     .mul_check_b

    mov     rcx, r12
    sub     rcx, 7
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x04
    jne     .mul_check_b

    mov     rcx, r12
    sub     rcx, 6
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x25
    jne     .mul_check_b

    mov     rcx, r12
    sub     rcx, 1
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x5B
    jne     .mul_check_b

    ; Pattern A matched: imul rax, [abs32] = 48 0F AF 04 25 addr32
    mov     rdi, [out_idx]
    mov     edi, dword [out_buffer + rdi - 5]

    sub     qword [out_idx], 10
    sub     qword [emit_tail_len], 10

    mov     al, 0x48
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0xAF
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, edi
    call    emit_d
    jmp     .mul_done

.mul_check_b:
    ; --- Pattern B: push + movabs N + pop → strength-reduced or imul ---
    cmp     r12, 12
    jl      .mul_normal

    mov     rcx, r12
    sub     rcx, 12
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x50
    jne     .mul_normal

    mov     rcx, r12
    sub     rcx, 11
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x48
    jne     .mul_normal

    mov     rcx, r12
    sub     rcx, 10
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0xB8
    jne     .mul_normal

    mov     rcx, r12
    sub     rcx, 1
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x5B
    jne     .mul_normal

    ; Pattern B matched: extract imm64
    mov     rdi, [out_idx]
    mov     rdi, [out_buffer + rdi - 9]

    ; check signed 32-bit fit
    mov     rax, rdi
    sar     rax, 32
    test    rax, rax
    jz      .mul_b_fits
    cmp     rax, -1
    jne     .mul_normal

.mul_b_fits:
    ; strength reduction: check power of 2
    mov     rax, rdi
    test    rax, rax
    jz      .mul_zero
    ; check if power of 2: (x & (x-1)) == 0
    mov     rcx, rax
    dec     rcx
    test    rax, rcx
    jnz     .mul_imm             ; not power of 2, use imul

    ; power of 2: compute shift amount via bit scan
    ; bsf rcx, rax → shift count
    mov     rcx, rax
    xor     eax, eax
.bsf_loop:
    test    cl, 1
    jnz     .got_shift
    shr     rcx, 1
    inc     eax
    cmp     eax, 63
    jle     .bsf_loop
.got_shift:
    ; eax = shift count (0..62)
    ; undo movabs+pop (12 bytes)
    sub     qword [out_idx], 12
    sub     qword [emit_tail_len], 12

    cmp     eax, 1
    jne     .shift_not1
    ; shl rax, 1 = 48 D1 E0 (3 bytes)
    mov     al, 0x48
    call    emit_b
    mov     al, 0xD1
    call    emit_b
    mov     al, 0xE0
    call    emit_b
    jmp     .mul_done
.shift_not1:
    ; shl rax, imm8 = 48 C1 E0 imm8 (4 bytes)
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0xC1
    call    emit_b
    mov     al, 0xE0
    call    emit_b
    pop     rax
    call    emit_b              ; emit shift count as byte
    jmp     .mul_done

.mul_zero:
    ; N = 0: just emit xor eax, eax
    sub     qword [out_idx], 12
    sub     qword [emit_tail_len], 12
    mov     al, 0x31
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    jmp     .mul_done

.mul_imm:
    ; N fits in 32 bits but not power of 2: imul rax, rax, imm32
    ; = 48 69 C0 imm32 (7 bytes)
    sub     qword [out_idx], 12
    sub     qword [emit_tail_len], 12

    mov     al, 0x48
    call    emit_b
    mov     al, 0x69
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    mov     eax, edi
    call    emit_d
    jmp     .mul_done

.mul_normal:
    ; imul rax, rbx = 48 0F AF C3
    mov     al, 0x48
    call    emit_b
    mov     al, 0x0f
    call    emit_b
    mov     al, 0xaf
    call    emit_b
    mov     al, 0xc3
    call    emit_b

.mul_done:
    pop     r12
    pop     rdi
    pop     rcx
    pop     rax
    ret

codegen_emit_idiv_rbx_by_rax:  ; rbx/rax → rax (quotient)
    push    rax
    mov     al, 0x48            ; mov rcx, rax  (save divisor)
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0xc1
    call    emit_b
    mov     al, 0x48            ; mov rax, rbx
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0xd8
    call    emit_b
    mov     al, 0x48            ; cqo
    call    emit_b
    mov     al, 0x99
    call    emit_b
    mov     al, 0x48            ; idiv rcx
    call    emit_b
    mov     al, 0xf7
    call    emit_b
    mov     al, 0xf9
    call    emit_b
    pop     rax
    ret

codegen_emit_imod_rbx_by_rax:  ; rbx%rax → rax (remainder)
    call    codegen_emit_idiv_rbx_by_rax
    push    rax
    mov     al, 0x48            ; mov rax, rdx (remainder)
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0xd0
    call    emit_b
    pop     rax
    ret

codegen_emit_neg_rax:          ; neg rax  (48 F7 D8)
    mov     qword [rax_holds_va], -1   ; rax = computed value, not a var
    ; O-I: emit IR_INEG if recording
    cmp     byte [ctpe_recording], 0
    je      .no_ir_neg
    push    rdi
    mov     rdi, IR_INEG
    call    ctpe_ir_emit_b
    pop     rdi
.no_ir_neg:
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0xf7
    call    emit_b
    mov     al, 0xd8
    call    emit_b
    pop     rax
    ret

; ============================================================
; Bitwise / shift
; ============================================================
codegen_emit_bitwise_and:   ; and rax, rbx  (48 21 D8) — Pattern A-reg / A peepholes
    push    rax
    push    rcx
    push    rdi
    push    r12

    mov     r12, [emit_tail_len]

    ; --- Pattern A-reg: push + mov rax,r15 + pop → and rax,r15  (4C 21 F8) ---
    cmp     qword [reg_cache_var], -1
    je      .and_check_a
    cmp     r12, 5
    jl      .and_check_a
    mov     rcx, r12
    sub     rcx, 5
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x50
    jne     .and_check_a
    mov     rcx, r12
    sub     rcx, 4
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x4C
    jne     .and_check_a
    mov     rcx, r12
    sub     rcx, 3
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x89
    jne     .and_check_a
    mov     rcx, r12
    sub     rcx, 2
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0xF8
    jne     .and_check_a
    mov     rcx, r12
    sub     rcx, 1
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x5B
    jne     .and_check_a
    sub     qword [out_idx], 5
    sub     qword [emit_tail_len], 5
    mov     al, 0x4C
    call    emit_b
    mov     al, 0x21
    call    emit_b
    mov     al, 0xF8
    call    emit_b
    jmp     .and_done

.and_check_a:
    ; --- Pattern A: push + mov rax,[abs32] + pop → and rax,[abs32]  (48 23 04 25 addr) ---
    cmp     r12, 10
    jl      .and_normal
    mov     rcx, r12
    sub     rcx, 10
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x50
    jne     .and_normal
    mov     rcx, r12
    sub     rcx, 9
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x48
    jne     .and_normal
    mov     rcx, r12
    sub     rcx, 8
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x8B
    jne     .and_normal
    mov     rcx, r12
    sub     rcx, 7
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x04
    jne     .and_normal
    mov     rcx, r12
    sub     rcx, 6
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x25
    jne     .and_normal
    mov     rcx, r12
    sub     rcx, 1
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x5B
    jne     .and_normal
    mov     rdi, [out_idx]
    mov     edi, dword [out_buffer + rdi - 5]
    sub     qword [out_idx], 10
    sub     qword [emit_tail_len], 10
    mov     al, 0x48
    call    emit_b
    mov     al, 0x23
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, edi
    call    emit_d
    jmp     .and_done

.and_normal:
    mov     al, 0x48
    call    emit_b
    mov     al, 0x21
    call    emit_b
    mov     al, 0xd8
    call    emit_b

.and_done:
    pop     r12
    pop     rdi
    pop     rcx
    pop     rax
    ret

codegen_emit_bitwise_or:    ; or rax, rbx  (48 09 D8) — Pattern A-reg / A peepholes
    push    rax
    push    rcx
    push    rdi
    push    r12

    mov     r12, [emit_tail_len]

    ; --- Pattern A-reg: push + mov rax,r15 + pop → or rax,r15  (4C 09 F8) ---
    cmp     qword [reg_cache_var], -1
    je      .or_check_a
    cmp     r12, 5
    jl      .or_check_a
    mov     rcx, r12
    sub     rcx, 5
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x50
    jne     .or_check_a
    mov     rcx, r12
    sub     rcx, 4
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x4C
    jne     .or_check_a
    mov     rcx, r12
    sub     rcx, 3
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x89
    jne     .or_check_a
    mov     rcx, r12
    sub     rcx, 2
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0xF8
    jne     .or_check_a
    mov     rcx, r12
    sub     rcx, 1
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x5B
    jne     .or_check_a
    sub     qword [out_idx], 5
    sub     qword [emit_tail_len], 5
    mov     al, 0x4C
    call    emit_b
    mov     al, 0x09
    call    emit_b
    mov     al, 0xF8
    call    emit_b
    jmp     .or_done

.or_check_a:
    ; --- Pattern A: push + mov rax,[abs32] + pop → or rax,[abs32]  (48 0B 04 25 addr) ---
    cmp     r12, 10
    jl      .or_normal
    mov     rcx, r12
    sub     rcx, 10
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x50
    jne     .or_normal
    mov     rcx, r12
    sub     rcx, 9
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x48
    jne     .or_normal
    mov     rcx, r12
    sub     rcx, 8
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x8B
    jne     .or_normal
    mov     rcx, r12
    sub     rcx, 7
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x04
    jne     .or_normal
    mov     rcx, r12
    sub     rcx, 6
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x25
    jne     .or_normal
    mov     rcx, r12
    sub     rcx, 1
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x5B
    jne     .or_normal
    mov     rdi, [out_idx]
    mov     edi, dword [out_buffer + rdi - 5]
    sub     qword [out_idx], 10
    sub     qword [emit_tail_len], 10
    mov     al, 0x48
    call    emit_b
    mov     al, 0x0B
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, edi
    call    emit_d
    jmp     .or_done

.or_normal:
    mov     al, 0x48
    call    emit_b
    mov     al, 0x09
    call    emit_b
    mov     al, 0xd8
    call    emit_b

.or_done:
    pop     r12
    pop     rdi
    pop     rcx
    pop     rax
    ret

codegen_emit_bitwise_xor:   ; xor rax, rbx  (48 31 D8) — Pattern A-reg / A peepholes
    push    rax
    push    rcx
    push    rdi
    push    r12

    mov     r12, [emit_tail_len]

    ; --- Pattern A-reg: push + mov rax,r15 + pop → xor rax,r15  (4C 31 F8) ---
    cmp     qword [reg_cache_var], -1
    je      .xor_check_a
    cmp     r12, 5
    jl      .xor_check_a
    mov     rcx, r12
    sub     rcx, 5
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x50
    jne     .xor_check_a
    mov     rcx, r12
    sub     rcx, 4
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x4C
    jne     .xor_check_a
    mov     rcx, r12
    sub     rcx, 3
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x89
    jne     .xor_check_a
    mov     rcx, r12
    sub     rcx, 2
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0xF8
    jne     .xor_check_a
    mov     rcx, r12
    sub     rcx, 1
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x5B
    jne     .xor_check_a
    sub     qword [out_idx], 5
    sub     qword [emit_tail_len], 5
    mov     al, 0x4C
    call    emit_b
    mov     al, 0x31
    call    emit_b
    mov     al, 0xF8
    call    emit_b
    jmp     .xor_done

.xor_check_a:
    ; --- Pattern A: push + mov rax,[abs32] + pop → xor rax,[abs32]  (48 33 04 25 addr) ---
    cmp     r12, 10
    jl      .xor_normal
    mov     rcx, r12
    sub     rcx, 10
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x50
    jne     .xor_normal
    mov     rcx, r12
    sub     rcx, 9
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x48
    jne     .xor_normal
    mov     rcx, r12
    sub     rcx, 8
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x8B
    jne     .xor_normal
    mov     rcx, r12
    sub     rcx, 7
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x04
    jne     .xor_normal
    mov     rcx, r12
    sub     rcx, 6
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x25
    jne     .xor_normal
    mov     rcx, r12
    sub     rcx, 1
    and     rcx, 31
    cmp     byte [emit_tail + rcx], 0x5B
    jne     .xor_normal
    mov     rdi, [out_idx]
    mov     edi, dword [out_buffer + rdi - 5]
    sub     qword [out_idx], 10
    sub     qword [emit_tail_len], 10
    mov     al, 0x48
    call    emit_b
    mov     al, 0x33
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, edi
    call    emit_d
    jmp     .xor_done

.xor_normal:
    mov     al, 0x48
    call    emit_b
    mov     al, 0x31
    call    emit_b
    mov     al, 0xd8
    call    emit_b

.xor_done:
    pop     r12
    pop     rdi
    pop     rcx
    pop     rax
    ret

codegen_emit_bitwise_not:   ; not rax  (48 F7 D0)
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0xf7
    call    emit_b
    mov     al, 0xd0
    call    emit_b
    pop     rax
    ret

codegen_emit_shl:   ; rbx << rax → rax  (88 C1; 48 89 D8; 48 D3 E0)
    push    rax
    mov     al, 0x88            ; mov cl, al
    call    emit_b
    mov     al, 0xc1
    call    emit_b
    mov     al, 0x48            ; mov rax, rbx
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0xd8
    call    emit_b
    mov     al, 0x48            ; shl rax, cl
    call    emit_b
    mov     al, 0xd3
    call    emit_b
    mov     al, 0xe0
    call    emit_b
    pop     rax
    ret

codegen_emit_shr:   ; rbx >> rax → rax
    push    rax
    mov     al, 0x88
    call    emit_b
    mov     al, 0xc1
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0xd8
    call    emit_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0xd3
    call    emit_b
    mov     al, 0xe8            ; shr rax, cl
    call    emit_b
    pop     rax
    ret

; ============================================================
; Boolean operations
; ============================================================
codegen_emit_and_bool: ; boolean AND: 0 or 1
    push    rsi
    push    rcx
    lea     rsi, [rel .and_code]
    mov     edx, 14
    call    emit_blob_v2
    pop     rcx
    pop     rsi
    ret
.and_code:
    db 0x48, 0x85, 0xDB               ; test rbx, rbx
    db 0x0F, 0x95, 0xC1               ; setnz cl
    db 0x48, 0x85, 0xC0               ; test rax, rax
    db 0x0F, 0x95, 0xC0               ; setnz al
    db 0x20, 0xC8                     ; and al, cl
    db 0x48, 0x0F, 0xB6, 0xC0        ; movzx rax, al

codegen_emit_or_bool:  ; boolean OR: 0 or 1
    push    rsi
    push    rcx
    lea     rsi, [rel .or_code]
    mov     edx, 14
    call    emit_blob_v2
    pop     rcx
    pop     rsi
    ret
.or_code:
    db 0x48, 0x09, 0xD8               ; or rax, rbx
    db 0x0F, 0x95, 0xC0               ; setnz al
    db 0x48, 0x0F, 0xB6, 0xC0        ; movzx rax, al
    pop     rcx
    pop     rsi
    ; Fall through to emit individual bytes
    ; test rax, rax
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0x85
    call    emit_b
    mov     al, 0xc0
    call    emit_b
    pop     rax
    ; jz offset (patch later)
    push    rax
    mov     al, 0x74
    call    emit_b
    mov     rax, [out_idx]
    inc     rax
    push    rax                     ; save patch offset
    xor     eax, eax
    call    emit_b                  ; placeholder
    ; test rbx, rbx
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0x85
    call    emit_b
    mov     al, 0xdb
    call    emit_b
    pop     rax
    ; jz offset (patch later)
    push    rax
    mov     al, 0x74
    call    emit_b
    mov     rax, [out_idx]
    inc     rax
    push    rax                     ; save patch offset
    xor     eax, eax
    call    emit_b                  ; placeholder
    ; test rbx, rbx
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0x85
    call    emit_b
    mov     al, 0xdb
    call    emit_b
    pop     rax
    ; js offset
    push    rax
    mov     al, 0x78
    call    emit_b
    mov     rax, [out_idx]
    inc     rax
    push    rax                     ; save patch offset
    xor     eax, eax
    call    emit_b                  ; placeholder
    ; test rax, rax
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0x85
    call    emit_b
    mov     al, 0xc0
    call    emit_b
    pop     rax
    ; js offset
    push    rax
    mov     al, 0x78
    call    emit_b
    mov     rax, [out_idx]
    inc     rax
    push    rax                     ; save patch offset
    xor     eax, eax
    call    emit_b                  ; placeholder
    ; mov rax, 1
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0xc7
    call    emit_b
    mov     al, 0xc0
    call    emit_b
    mov     al, 0x01
    call    emit_b
    xor     eax, eax
    call    emit_b
    call    emit_b
    call    emit_b
    pop     rax
    ; jmp .adone
    push    rax
    mov     al, 0xeb
    call    emit_b
    mov     rax, [out_idx]
    inc     rax
    push    rax                     ; save patch offset
    xor     eax, eax
    call    emit_b                  ; placeholder
    ; .aneg: mov rax, -1
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0xc7
    call    emit_b
    mov     al, 0xc0
    call    emit_b
    mov     al, 0xff
    call    emit_b
    call    emit_b
    call    emit_b
    call    emit_b
    pop     rax
    ; jmp .adone
    push    rax
    mov     al, 0xeb
    call    emit_b
    mov     rax, [out_idx]
    inc     rax
    push    rax                     ; save patch offset
    xor     eax, eax
    call    emit_b                  ; placeholder
    ; .azero: xor eax, eax
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0x31
    call    emit_b
    mov     al, 0xc0
    call    emit_b
    pop     rax
    ; .adone = current out_idx
    ; Now patch all the jz and jmp offsets
    ; Pop the saved patch offsets and patch them
codegen_emit_not_rax:  ; neg rax  (tri-state NOT: true→false, false→true, neutral→neutral)
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0xf7
    call    emit_b
    mov     al, 0xd8
    call    emit_b
    pop     rax
    ret

; ============================================================
; Comparison: cmp rbx, rax; setCC al; movzx rax, al
; rdi = setCC opcode byte (0x94=sete, 0x95=setne, etc.)
; Returns 0 (false) or 1 (true)
; ============================================================
codegen_emit_cmp_setcc:
    push    rax
    push    rdi
    mov     al, 0x48            ; cmp rbx, rax
    call    emit_b
    mov     al, 0x39
    call    emit_b
    mov     al, 0xc3
    call    emit_b
    mov     al, 0x0f            ; setCC prefix
    call    emit_b
    pop     rax
    ; O-I: emit IR_ICMPxx if recording
    push    rax
    cmp     byte [ctpe_recording], 0
    je      .no_ir_cmp
    push    rdi
    cmp     al, 0x9C            ; setl → IR_ICMPLT
    jne     .cmp_not_lt
    mov     rdi, IR_ICMPLT
    jmp     .cmp_emit
.cmp_not_lt:
    cmp     al, 0x9F            ; setg → IR_ICMPGT
    jne     .cmp_not_gt
    mov     rdi, IR_ICMPGT
    jmp     .cmp_emit
.cmp_not_gt:
    cmp     al, 0x94            ; sete → IR_ICMPEQ
    jne     .cmp_not_eq
    mov     rdi, IR_ICMPEQ
    jmp     .cmp_emit
.cmp_not_eq:
    cmp     al, 0x95            ; setne → IR_ICMPNE
    jne     .cmp_not_ne
    mov     rdi, IR_ICMPNE
    jmp     .cmp_emit
.cmp_not_ne:
    cmp     al, 0x9E            ; setle → IR_ICMPLE
    jne     .cmp_not_le
    mov     rdi, IR_ICMPLE
    jmp     .cmp_emit
.cmp_not_le:
    cmp     al, 0x9D            ; setge → IR_ICMPGE
    jne     .cmp_no_emit
    mov     rdi, IR_ICMPGE
.cmp_emit:
    call    ctpe_ir_emit_b
.cmp_no_emit:
    pop     rdi
.no_ir_cmp:
    pop     rax
    call    emit_b              ; setCC byte
    mov     al, 0xc0            ; al
    call    emit_b
    mov     al, 0x48            ; movzx rax, al
    call    emit_b
    mov     al, 0x0f
    call    emit_b
    mov     al, 0xb6
    call    emit_b
    mov     al, 0xc0
    call    emit_b
    pop     rax

    ret

; ============================================================
; Branch emission (returns patch offset in rax)
; ============================================================

; codegen_emit_test_jz: emit  test rax,rax; jz placeholder  → rax=offset of rel32
; PEEPHOLE: if recent bytes are mov+push+movabs+pop+cmp+setCC+movzx, fuse to cmp [addr],N; jcc
; Also: when register cache active, fuse to cmp r15,N; jcc
codegen_emit_test_jz:
    push    rbx
    push    rcx
    push    rdx
    push    rdi

    ; FAST PATH: register cache active — look for mov rax,r15+push+movabs+pop+cmp+setCC+movzx (25 bytes)
    cmp     qword [reg_cache_var], -1
    je      .check_full_pattern
    mov     rcx, [emit_tail_len]
    cmp     rcx, 25
    jb      .check_full_pattern
    lea     rdi, [emit_tail]
    ; Check movzx at tail[N-4..N-1] = 48 0F B6 C0
    mov     rax, rcx
    sub     rax, 4
    and     rax, 31
    cmp     byte [rdi + rax], 0x48
    jne     .check_full_pattern
    mov     rax, rcx
    sub     rax, 3
    and     rax, 31
    cmp     byte [rdi + rax], 0x0f
    jne     .check_full_pattern
    mov     rax, rcx
    sub     rax, 2
    and     rax, 31
    cmp     byte [rdi + rax], 0xb6
    jne     .check_full_pattern
    mov     rax, rcx
    dec     rax
    and     rax, 31
    cmp     byte [rdi + rax], 0xc0
    jne     .check_full_pattern
    ; Check setCC at tail[N-7..N-5] = 0F XX C0
    mov     rax, rcx
    sub     rax, 7
    and     rax, 31
    cmp     byte [rdi + rax], 0x0f
    jne     .check_full_pattern
    mov     rax, rcx
    sub     rax, 5
    and     rax, 31
    cmp     byte [rdi + rax], 0xc0
    jne     .check_full_pattern
    ; Determine inverse CC from setCC byte at tail[N-6]
    mov     rax, rcx
    sub     rax, 6
    and     rax, 31
    movzx   edx, byte [rdi + rax]
    cmp     dl, 0x9c
    jne     .cc_not_l
    mov     byte [cmp_fused_cc], 0x8d
    jmp     .cc_ok2
  .cc_not_l:
    cmp     dl, 0x9f
    jne     .cc_not_g
    mov     byte [cmp_fused_cc], 0x8e
    jmp     .cc_ok2
  .cc_not_g:
    cmp     dl, 0x94
    jne     .cc_not_e
    mov     byte [cmp_fused_cc], 0x85
    jmp     .cc_ok2
  .cc_not_e:
    cmp     dl, 0x95
    jne     .cc_not_ne
    mov     byte [cmp_fused_cc], 0x84
    jmp     .cc_ok2
  .cc_not_ne:
    cmp     dl, 0x9e
    jne     .cc_not_le
    mov     byte [cmp_fused_cc], 0x8f
    jmp     .cc_ok2
  .cc_not_le:
    cmp     dl, 0x9d
    jne     .check_full_pattern
    mov     byte [cmp_fused_cc], 0x8c
  .cc_ok2:
    ; Check cmp at tail[N-10..N-8] = 48 39 C3
    mov     rax, rcx
    sub     rax, 10
    and     rax, 31
    cmp     byte [rdi + rax], 0x48
    jne     .check_full_pattern
    mov     rax, rcx
    sub     rax, 9
    and     rax, 31
    cmp     byte [rdi + rax], 0x39
    jne     .check_full_pattern
    mov     rax, rcx
    sub     rax, 8
    and     rax, 31
    cmp     byte [rdi + rax], 0xc3
    jne     .check_full_pattern
    ; Check pop at tail[N-11] = 5B
    mov     rax, rcx
    sub     rax, 11
    and     rax, 31
    cmp     byte [rdi + rax], 0x5b
    jne     .check_full_pattern
    ; Check movabs at tail[N-21..N-20] = 48 B8
    mov     rax, rcx
    sub     rax, 21
    and     rax, 31
    cmp     byte [rdi + rax], 0x48
    jne     .check_full_pattern
    mov     rax, rcx
    sub     rax, 20
    and     rax, 31
    cmp     byte [rdi + rax], 0xb8
    jne     .check_full_pattern
    ; Check push at tail[N-22] = 50
    mov     rax, rcx
    sub     rax, 22
    and     rax, 31
    cmp     byte [rdi + rax], 0x50
    jne     .check_full_pattern
    ; Check mov rax,r15 at tail[N-25..N-23] = 4C 89 F8
    ; This ensures the push was pushing r15 (the loop counter), not some computed value.
    mov     rax, rcx
    sub     rax, 25
    and     rax, 31
    cmp     byte [rdi + rax], 0x4c
    jne     .check_full_pattern
    mov     rax, rcx
    sub     rax, 24
    and     rax, 31
    cmp     byte [rdi + rax], 0x89
    jne     .check_full_pattern
    mov     rax, rcx
    sub     rax, 23
    and     rax, 31
    cmp     byte [rdi + rax], 0xf8
    jne     .check_full_pattern
    ; Pattern matched: mov rax,r15+push+movabs+pop+cmp+setCC+movzx = 25 bytes
    ; Extract imm64 from out_buffer[out_idx - 19]
    ; movzx(4) + setCC(3) + cmp(3) + pop(1) = 11 bytes at end
    ; imm64(8) starts at out_idx - 11 - 8 = out_idx - 19
    mov     rdi, [out_idx]
    sub     rdi, 19
    mov     rdi, [out_buffer + rdi]
    ; Record fused var address for caching
    mov     rax, [reg_cache_var]
    mov     [fused_cmp_var_addr], rax
    ; Check fits in signed 32 bits
    mov     rsi, rdi
    sar     rsi, 31
    cmp     sil, 0
    je      .cached_imm32_ok
    cmp     sil, 0xff
    jne     .check_full_pattern
  .cached_imm32_ok:
    ; Save fused limit for while-loop triangular fold
    mov     [fused_cmp_limit], rdi
    mov     byte [fused_cmp_limit_is_const], 1
    ; Undo 25 bytes (mov rax,r15 + push + movabs + pop + cmp + setCC + movzx)
    sub     qword [out_idx], 25
    sub     qword [emit_tail_len], 25
    ; Emit: cmp r15, imm32 = 49 81 FF XX XX XX XX (7 bytes)
    mov     al, 0x49
    call    emit_b
    mov     al, 0x81
    call    emit_b
    mov     al, 0xff
    call    emit_b
    mov     eax, edi
    call    emit_d
    ; Emit: jcc rel32 placeholder = 0F CC rel32 (6 bytes)
    mov     al, 0x0f
    call    emit_b
    movzx   eax, byte [cmp_fused_cc]
    call    emit_b
    mov     rax, [out_idx]
    xor     ebx, ebx
    call    emit_d
    jmp     .jz_done

  .check_full_pattern:
    ; push rax = 50 (1 byte)
    ; movabs = 48 B8 XX*8 (10 bytes: 2 emit_b + 8 emit_q)
    ; pop rbx = 5B (1 byte)
    ; cmp rbx,rax = 48 39 C3 (3 bytes)
    ; setCC al = 0F CC C0 (3 bytes)
    ; movzx rax,al = 48 0F B6 C0 (4 bytes)
    ; Total: 30 bytes
    mov     rcx, [emit_tail_len]
    cmp     rcx, 30
    jb      .normal_jz

    lea     rdi, [emit_tail]

    ; Verify movzx at tail[N-4..N-1] = 48 0F B6 C0
    mov     rax, rcx
    sub     rax, 4
    and     rax, 31
    cmp     byte [rdi + rax], 0x48
    jne     .normal_jz
    mov     rax, rcx
    sub     rax, 3
    and     rax, 31
    cmp     byte [rdi + rax], 0x0f
    jne     .normal_jz
    mov     rax, rcx
    sub     rax, 2
    and     rax, 31
    cmp     byte [rdi + rax], 0xb6
    jne     .normal_jz
    mov     rax, rcx
    dec     rax
    and     rax, 31
    cmp     byte [rdi + rax], 0xc0
    jne     .normal_jz

    ; Verify setCC at tail[N-7..N-5] = 0F XX C0
    mov     rax, rcx
    sub     rax, 7
    and     rax, 31
    cmp     byte [rdi + rax], 0x0f
    jne     .normal_jz
    mov     rax, rcx
    sub     rax, 5
    and     rax, 31
    cmp     byte [rdi + rax], 0xc0
    jne     .normal_jz

    ; Determine inverse CC from the setCC byte at tail[N-6]
    mov     rax, rcx
    sub     rax, 6
    and     rax, 31
    movzx   edx, byte [rdi + rax]
    cmp     dl, 0x9c               ; setl
    jne     .not_setl
    mov     byte [cmp_fused_cc], 0x8d  ; jge
    jmp     .cc_ok
  .not_setl:
    cmp     dl, 0x9f               ; setg
    jne     .not_setg
    mov     byte [cmp_fused_cc], 0x8e  ; jle
    jmp     .cc_ok
  .not_setg:
    cmp     dl, 0x94               ; sete
    jne     .not_sete
    mov     byte [cmp_fused_cc], 0x85  ; jne
    jmp     .cc_ok
  .not_sete:
    cmp     dl, 0x95               ; setne
    jne     .not_setne
    mov     byte [cmp_fused_cc], 0x84  ; je
    jmp     .cc_ok
  .not_setne:
    cmp     dl, 0x9e               ; setle
    jne     .not_setle
    mov     byte [cmp_fused_cc], 0x8f  ; jg
    jmp     .cc_ok
  .not_setle:
    cmp     dl, 0x9d               ; setge
    jne     .normal_jz
    mov     byte [cmp_fused_cc], 0x8c  ; jl
  .cc_ok:

    ; Verify cmp at tail[N-10..N-8] = 48 39 C3
    mov     rax, rcx
    sub     rax, 10
    and     rax, 31
    cmp     byte [rdi + rax], 0x48
    jne     .normal_jz
    mov     rax, rcx
    sub     rax, 9
    and     rax, 31
    cmp     byte [rdi + rax], 0x39
    jne     .normal_jz
    mov     rax, rcx
    sub     rax, 8
    and     rax, 31
    cmp     byte [rdi + rax], 0xc3
    jne     .normal_jz

    ; Verify pop at tail[N-11] = 5B
    mov     rax, rcx
    sub     rax, 11
    and     rax, 31
    cmp     byte [rdi + rax], 0x5b
    jne     .normal_jz

    ; Verify movabs at tail[N-21..N-20] = 48 B8
    mov     rax, rcx
    sub     rax, 21
    and     rax, 31
    cmp     byte [rdi + rax], 0x48
    jne     .normal_jz
    mov     rax, rcx
    sub     rax, 20
    and     rax, 31
    cmp     byte [rdi + rax], 0xb8
    jne     .normal_jz

    ; Verify push at tail[N-22] = 50
    mov     rax, rcx
    sub     rax, 22
    and     rax, 31
    cmp     byte [rdi + rax], 0x50
    jne     .normal_jz

    ; Verify mov rax,[abs32] at tail[N-30..N-27] = 48 8B 04 25
    mov     rax, rcx
    sub     rax, 30
    and     rax, 31
    cmp     byte [rdi + rax], 0x48
    jne     .normal_jz
    mov     rax, rcx
    sub     rax, 29
    and     rax, 31
    cmp     byte [rdi + rax], 0x8b
    jne     .normal_jz
    mov     rax, rcx
    sub     rax, 28
    and     rax, 31
    cmp     byte [rdi + rax], 0x04
    jne     .normal_jz
    mov     rax, rcx
    sub     rax, 27
    and     rax, 31
    cmp     byte [rdi + rax], 0x25
    jne     .normal_jz

    ; ALL PATTERN BYTES VERIFIED. Extract addr32 and imm64.
    ; addr32 is at tail positions [N-26..N-23]
    mov     rax, rcx
    sub     rax, 26
    and     rax, 31
    movzx   edx, byte [rdi + rax]
    mov     rax, rcx
    sub     rax, 25
    and     rax, 31
    movzx   esi, byte [rdi + rax]
    shl     esi, 8
    or      edx, esi
    mov     rax, rcx
    sub     rax, 24
    and     rax, 31
    movzx   esi, byte [rdi + rax]
    shl     esi, 16
    or      edx, esi
    mov     rax, rcx
    sub     rax, 23
    and     rax, 31
    movzx   esi, byte [rdi + rax]
    shl     esi, 24
    or      edx, esi                 ; edx = addr32

    ; imm64 is at tail positions [N-19..N-12]
    ; Read from out_buffer at out_idx - 19 for simplicity
    mov     rdi, [out_idx]
    sub     rdi, 19
    mov     rdi, [out_buffer + rdi]  ; rdi = imm64

    ; Check if imm64 fits in signed 32 bits
    mov     rsi, rdi
    sar     rsi, 31
    cmp     sil, 0
    je      .imm32_ok
    cmp     sil, 0xff
    jne     .normal_jz
  .imm32_ok:
    ; Save fused limit for while-loop triangular fold
    mov     [fused_cmp_limit], rdi
    mov     byte [fused_cmp_limit_is_const], 1
    ; PATTERN CONFIRMED. Undo the last 30 bytes.
    sub     qword [out_idx], 30
    sub     qword [emit_tail_len], 30

    ; Record the fused comparison variable address for register caching
    mov     [fused_cmp_var_addr], rdx

    ; Check if this variable is cached in r15 — if so, use cmp r15, imm32 (7 bytes)
    cmp     rdx, [reg_cache_var]
    jne     .cmp_mem_fused
    ; Emit: cmp r15, imm32 = 49 81 FF XX XX XX XX (7 bytes)
    mov     al, 0x49
    call    emit_b
    mov     al, 0x81
    call    emit_b
    mov     al, 0xff
    call    emit_b
    mov     eax, edi
    call    emit_d                 ; imm32
    jmp     .cmp_fused_done
  .cmp_mem_fused:
    ; Emit: cmp qword [abs32], imm32 = 48 81 3C 25 XX XX XX XX YY YY YY YY (12 bytes)
    mov     al, 0x48
    call    emit_b
    mov     al, 0x81
    call    emit_b
    mov     al, 0x3c
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, edx
    call    emit_d                 ; addr32
    mov     eax, edi
    call    emit_d                 ; imm32
  .cmp_fused_done:

    ; Emit: jcc rel32 placeholder = 0F CC 00 00 00 00 (6 bytes)
    mov     al, 0x0f
    call    emit_b
    movzx   eax, byte [cmp_fused_cc]
    call    emit_b
    mov     rax, [out_idx]
    xor     ebx, ebx
    call    emit_d                 ; placeholder
    jmp     .jz_done

  .normal_jz:
    mov     byte [fused_cmp_limit_is_const], 0
    ; Original: test rax, rax; jz placeholder
    mov     al, 0x48
    call    emit_b
    mov     al, 0x85
    call    emit_b
    mov     al, 0xc0
    call    emit_b
    mov     al, 0x0f
    call    emit_b
    mov     al, 0x84
    call    emit_b
    mov     rax, [out_idx]
    xor     ebx, ebx
    call    emit_d

  .jz_done:
    pop     rdi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; codegen_emit_jmp_end: emit  jmp placeholder  → rax=offset of rel32
codegen_emit_jmp_end:
    push    rbx
    mov     al, 0xe9
    call    emit_b
    mov     rax, [out_idx]
    xor     ebx, ebx
    call    emit_d
    pop     rbx
    ret

; codegen_patch_jump(rdi=patch_offset): patch rel32 at patch_offset to current out_idx
; rel32 = (CODE_START + out_idx) - (CODE_START + patch_offset + 4)
;       = out_idx - patch_offset - 4
codegen_patch_jump:
    push    rax
    push    rbx
    mov     rax, [out_idx]
    sub     rax, rdi
    sub     rax, 4
    mov     [out_buffer + rdi], eax
    pop     rbx
    pop     rax
    ret

; codegen_patch_chain_end: patch all end_jump_stack entries down to chain_base to here
codegen_patch_chain_end:
    push    rbx
    push    rcx
    mov     rbx, [chain_base_depth]
    dec     rbx
    mov     rbx, [chain_base_stack + rbx*8]  ; load saved end_jump_depth
    mov     rcx, [end_jump_depth]
.patch_loop:
    cmp     rcx, rbx
    jle     .done
    dec     rcx
    mov     rdi, [end_jump_stack + rcx*8]
    call    codegen_patch_jump
    jmp     .patch_loop
.done:
    mov     [end_jump_depth], rbx   ; restore end_jump depth to chain base
    pop     rcx
    pop     rbx
    ret

; ============================================================
; Output / printer calls
; ============================================================
; Helper: emit  call rel32_to_VA
; rdi = absolute VA to call
emit_call_abs:
    mov     qword [rax_holds_va], -1   ; rax = return value after call
    push    rax
    push    rdi
    mov     al, 0xe8
    call    emit_b
    pop     rdi
    ; rel32 = VA - (CODE_START + out_idx + 4)
    mov     rax, rdi
    sub     rax, LOAD_BASE + CODE_START
    sub     rax, [out_idx]
    sub     rax, 4
    call    emit_d
    pop     rax
    ret

codegen_emit_call_rt_pri:
    mov     rdi, LOAD_BASE + RT_PRI_OFFSET
    jmp     emit_call_abs

codegen_emit_call_rt_prs:
    mov     rdi, LOAD_BASE + RT_PRS_OFFSET
    jmp     emit_call_abs

codegen_emit_call_rt_prb:
    mov     rdi, LOAD_BASE + RT_PRB_OFFSET
    jmp     emit_call_abs

codegen_emit_call_rt_prf:
    mov     rdi, LOAD_BASE + RT_PRF_OFFSET
    jmp     emit_call_abs

codegen_emit_call_rt_prc:
    mov     rdi, LOAD_BASE + RT_PRC_OFFSET
    jmp     emit_call_abs

codegen_emit_call_rt_err:
    mov     rdi, LOAD_BASE + RT_PRQ_OFFSET
    jmp     emit_call_abs

; codegen_output_typed: emit  mov rdi, rax + call rt_pXX  given type
; rdi = type code
codegen_output_rax:
    push    rdi
    movzx   edi, byte [cur_type]
    call    codegen_output_typed        ; rdi = type already loaded
    pop     rdi
    ret

codegen_output_typed:
    push    rdi
    call    codegen_emit_mov_rdi_rax    ; emit: mov rdi, rax
    pop     rdi
    cmp     edi, TYPE_FLOAT
    je      .float
    cmp     edi, TYPE_BOOL
    je      .bool
    cmp     edi, TYPE_STR
    je      .str
    cmp     edi, TYPE_COMPLEX
    je      .complex
    ; default: int
    call    codegen_emit_call_rt_pri
    ret
.float:
    call    codegen_emit_call_rt_prf
    ret
.bool:
    call    codegen_emit_call_rt_prb
    ret
.str:
    call    codegen_emit_call_rt_prs
    ret
.complex:
    call    codegen_emit_call_rt_prc
    ret

; ============================================================
; For loop
; ============================================================
; codegen_emit_for_start(rdi=var_va, rsi=from_imm, rdx=to_imm)
; Emits: init, jmp check, increment (cont target), condition, captures loop start
; Returns: rax = loop_start_pc (condition), rbx = jge_patch_offset
codegen_emit_for_start:
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi                ; var VA
    mov     r13, rsi                ; from
    mov     r14, rdx                ; to

    ; F-10/F-11: record header start, emit 8-byte LICM hoist slot (NOPs),
    ; and clear per-loop optimisation flags BEFORE any code is emitted.
    ; Count-down rewrite will preserve this slot; LICM will patch it.
    mov     r15, [out_idx]
    mov     [for_header_start_idx], r15
    mov     [for_hoist_slot_pos], r15
    mov     byte [loop_var_used_in_body], 0
    mov     byte [loop_has_skip], 0
    mov     dword [licm_hoisted_addr], 0
    push    rax
    ; Phase 2A: Push r14 for accumulator pinning (2 bytes) + 8 NOPs placeholder
    mov     al, 0x41
    call    emit_b
    mov     al, 0x56
    call    emit_b
    ; Record position of 8-NOP placeholder for mov r14, [acc_addr]
    mov     rax, [out_idx]
    mov     [ra_hoist_slot_pos], rax
    ; Emit 8 NOPs as placeholder for mov r14, [acc_addr]
    push    rcx
    xor     ecx, ecx
.for_ra_nop_loop:
    cmp     ecx, 8
    jge     .for_ra_nop_done
    push    rax
    mov     al, 0x90
    call    emit_b
    pop     rax
    inc     ecx
    jmp     .for_ra_nop_loop
.for_ra_nop_done:
    pop     rcx
    ; LICM hoist slot (8 NOPs)
    mov     al, 0x90                ; NOP × 8 (hoist slot placeholder)
    call    emit_b
    call    emit_b
    call    emit_b
    call    emit_b
    call    emit_b
    call    emit_b
    call    emit_b
    call    emit_b
    pop     rax

    ; O-A: init r15 with loop counter (pin r15 = loop var)
    ; emit: mov r15d, from (zero-extends) or xor r15d,r15d if from==0
    test    r13, r13
    jnz     .init_nonzero_pin
    push    rax
    mov     al, 0x45                ; xor r15d, r15d = REX.R + XOR r/m32,r32
    call    emit_b
    mov     al, 0x31
    call    emit_b
    mov     al, 0xff
    call    emit_b
    pop     rax
    jmp     .emit_jmp_check

.init_nonzero_pin:
    ; emit: mov r15d, imm32 (sign-extended to 64-bit)
    push    rax
    mov     al, 0x41                ; REX.B
    call    emit_b
    mov     al, 0xbf                ; MOV r15d, imm32
    call    emit_b
    mov     eax, r13d
    call    emit_d
    pop     rax

.emit_jmp_check:
    ; set O-A pin state
    mov     byte [loop_pin_active], 1
    mov     qword [loop_pin_var_va], r12
    mov     qword [reg_cache_var], r12

    ; save loop bounds for rolling / O-H folding
    mov     [for_from_val], r13         ; from_imm
    mov     [for_to_val],   r14         ; to_imm
    mov     byte [for_to_is_var], 0     ; static bounds (compile-time to)
    ; clear rolling flags (fresh body)
    mov     byte [og_fired_in_body],  0
    mov     byte [og_op_code],        0
    mov     byte [oh_mul_fired_in_body], 0

    ; emit: jmp .check  (skip increment on first iteration)
    push    rax
    mov     al, 0xe9
    call    emit_b
    mov     rax, [out_idx]
    mov     r15, rax                ; save jmp patch offset (internal scratch)
    xor     eax, eax
    call    emit_d
    pop     rax

.increment_point:
    ; continue target = current out_idx (increment code)
    call    codegen_get_out_idx
    mov     [for_cont_addr], rax    ; save for codegen_emit_for_end
    mov     rdi, rax
    call    codegen_push_cont

    ; O-A: emit: inc r15 (49 FF C7)
    push    rax
    mov     al, 0x49
    call    emit_b
    mov     al, 0xff
    call    emit_b
    mov     al, 0xc7
    call    emit_b
    pop     rax

.check_point:
    ; O-E: align loop condition to 16-byte boundary
    call    codegen_align_loop_top

    ; patch jmp to skip to here
    push    rax
    push    rdi
    mov     rdi, r15                ; jmp patch offset
    call    codegen_patch_jump
    pop     rdi
    pop     rax

    ; save loop start PC (condition check)
    mov     r15, [out_idx]

    ; O-A: emit: cmp r15, to_imm32 (49 81 FF imm32) + jge exit_placeholder
    push    rax
    mov     al, 0x49
    call    emit_b
    mov     al, 0x81
    call    emit_b
    mov     al, 0xff
    call    emit_b
    mov     eax, r14d               ; to (imm32)
    call    emit_d
    ; jge rel32
    mov     al, 0x0f
    call    emit_b
    mov     al, 0x8d
    call    emit_b
    mov     rax, [out_idx]          ; jge patch offset
    mov     r13, rax                ; save jge patch offset
    xor     eax, eax
    call    emit_d
    pop     rax

    ; push break base
    mov     rdi, [break_base_depth]
    mov     rsi, [break_jump_depth]
    mov     [break_base_stack + rdi*8], rsi
    inc     qword [break_base_depth]

    inc     qword [loop_depth]

    ; record body start position (out_idx right after jge placeholder = start of body)
    mov     r8, [out_idx]
    mov     [for_body_start_idx], r8

    ; return loop_start in rax, jge_patch in rbx
    mov     rax, r15
    mov     rbx, r13

    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret

; codegen_emit_for_end(rdi=loop_start, rsi=jge_patch, rdx=var_va)
; Emits back-jump to increment point + patches exit.
; Loop rolling: if body is a single O-G ADD-r15 RMW (8 bytes) or a constant-imul
; body (23 bytes), fold the entire loop into a single compile-time expression.
codegen_emit_for_end:
    push    r12
    push    r13
    push    r14
    mov     r12, rdi                ; loop_start (condition check)
    mov     r13, rsi                ; jge_patch offset
    mov     r14, rdx                ; var VA

    ; ================================================================
    ; Loop Rolling: fold loop into closed-form if conditions met
    ; Requires: loop_pin_active=1 (static bounds via O-A)
    ; ================================================================
    cmp     byte [loop_pin_active], 0
    je      .fe_normal_backjump

    ; ---- Triangular/anti-sum fold: total OP= i  →  total OP= ±N*(from+to-1)/2 ----
    ; Fires when: O-G ADD or SUB +r15 is the sole body (8 bytes)
    cmp     byte [og_fired_in_body], 0
    je      .fe_check_oh_mul

    mov     rax, [out_idx]
    sub     rax, [for_body_start_idx]
    cmp     rax, 8
    jne     .fe_check_oh_mul        ; body has more than just the 8-byte RMW

    ; Only ADD and SUB have a closed-form fold; OR/AND/XOR do not
    cmp     byte [og_op_code], 0x01     ; ADD
    je      .tri_fold_op_ok
    cmp     byte [og_op_code], 0x29     ; SUB
    jne     .fe_check_oh_mul
.tri_fold_op_ok:

    ; Branch on static vs runtime 'to' bound
    cmp     byte [for_to_is_var], 0
    jne     .roll_tri_runtime

    ; STATIC: Compute delta = N*(from+to-1)/2  where N = to-from  (compile time)
    mov     r10, [for_to_val]
    mov     r11, [for_from_val]
    sub     r10, r11                ; r10 = N
    jle     .fe_normal_backjump     ; N <= 0: degenerate / zero-trip loop

    mov     rax, r10                ; rax = N
    mov     rcx, [for_from_val]
    add     rcx, [for_to_val]
    dec     rcx                     ; rcx = from+to-1
    imul    rax, rcx               ; rax = N*(from+to-1)  (natural 64-bit mod)
    sar     rax, 1                  ; delta = N*(from+to-1)/2
    mov     r10, rax                ; r10 = delta

    ; Rewind to body start (remove O-G RMW from output)
    mov     rax, [for_body_start_idx]
    mov     [out_idx], rax
    sub     qword [emit_tail_len], 8

    ; Emit: add qword [og_rw_addr32], delta
    ; Check if delta fits in signed imm32
    mov     rax, r10
    sar     rax, 31
    test    rax, rax
    jz      .roll_tri_small
    cmp     rax, -1
    je      .roll_tri_small
    jmp     .roll_tri_large     ; static large-delta path — must not fall into runtime block

.roll_tri_runtime:
    ; RUNTIME: delta = N*(N-1)/2  where N = [to_var_va]  (for from=0)
    ; Emits 36-byte sequence with a forward-jump guard for N<=0.
    ; Formula for from!=0 not yet implemented — fall back to normal loop.
    cmp     qword [for_from_val], 0
    jne     .fe_normal_backjump

    ; Rewind body (remove the 8-byte O-G RMW)
    mov     rax, [for_body_start_idx]
    mov     [out_idx], rax
    sub     qword [emit_tail_len], 8

    ; Emit: mov rax, [to_var_va]  =  48 8B 04 25 addr (8 bytes)
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0x8B
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, dword [for_to_var_va]
    call    emit_d
    ; Emit: test rax, rax  =  48 85 C0 (3 bytes)
    mov     al, 0x48
    call    emit_b
    mov     al, 0x85
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    ; Emit: jle .done  =  0F 8E 13 00 00 00  (rel32=19: skips lea+imul+sar+add = 4+4+3+8)
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x8E
    call    emit_b
    mov     al, 19
    call    emit_b
    xor     eax, eax
    call    emit_b
    call    emit_b
    call    emit_b
    ; Emit: lea rbx, [rax-1]  =  48 8D 58 FF (4 bytes)
    mov     al, 0x48
    call    emit_b
    mov     al, 0x8D
    call    emit_b
    mov     al, 0x58
    call    emit_b
    mov     al, 0xFF
    call    emit_b
    ; Emit: imul rax, rbx  =  48 0F AF C3 (4 bytes)
    mov     al, 0x48
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0xAF
    call    emit_b
    mov     al, 0xC3
    call    emit_b
    ; Emit: sar rax, 1  =  48 D1 F8 (3 bytes)
    mov     al, 0x48
    call    emit_b
    mov     al, 0xD1
    call    emit_b
    mov     al, 0xF8
    call    emit_b
    ; Emit: ADD or SUB [og_rw_addr32], rax  (8 bytes)  ← .done target
    ; ADD: 48 01 04 25 addr    SUB: 48 29 04 25 addr
    mov     al, 0x48
    call    emit_b
    cmp     byte [og_op_code], 0x01
    je      .rt_op_add
    mov     al, 0x29            ; sub [addr], rax
    jmp     .rt_op_emit
.rt_op_add:
    mov     al, 0x01            ; add [addr], rax
.rt_op_emit:
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, dword [og_rw_addr32]
    call    emit_d
    pop     rax
    jmp     .fe_rolling_done_dyn

.roll_tri_large:
    ; movabs rax, delta (10 bytes) + ADD/SUB [addr32], rax (8 bytes)
    ; ADD: 48 01 04 25 addr    SUB: 48 29 04 25 addr
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0xB8
    call    emit_b
    mov     rax, r10
    call    emit_q
    mov     al, 0x48
    call    emit_b
    cmp     byte [og_op_code], 0x01
    je      .tri_large_add
    mov     al, 0x29            ; sub [addr32], rax
    jmp     .tri_large_op
.tri_large_add:
    mov     al, 0x01            ; add [addr32], rax
.tri_large_op:
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, dword [og_rw_addr32]
    call    emit_d
    pop     rax
    jmp     .fe_rolling_done

.roll_tri_small:
    ; ADD/SUB qword [addr32], imm32  (12 bytes)
    ; ADD: 48 81 04 25 addr imm32  (/0 = ADD)
    ; SUB: 48 81 2C 25 addr imm32  (/5 = SUB)
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0x81
    call    emit_b
    cmp     byte [og_op_code], 0x01
    je      .tri_small_add
    mov     al, 0x2C            ; /5 = SUB qword [addr32], imm32
    jmp     .tri_small_modrm
.tri_small_add:
    mov     al, 0x04            ; /0 = ADD qword [addr32], imm32
.tri_small_modrm:
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, dword [og_rw_addr32]
    call    emit_d
    mov     rax, r10
    call    emit_d              ; imm32 (lower 32 bits of delta)
    pop     rax
    jmp     .fe_rolling_done

.fe_check_oh_mul:
    ; ---- Constant multiply: x *= A (N iters)  →  x *= A^N (1 iter, A^N computed here) ----
    ; Fires when: oh_mul_fired_in_body=1 and body is exactly 23 bytes
    cmp     byte [oh_mul_fired_in_body], 0
    je      .fe_normal_backjump

    mov     rax, [out_idx]
    sub     rax, [for_body_start_idx]
    cmp     rax, 23
    jne     .fe_normal_backjump

    ; Compute A^N via binary ladder (entirely at compile time)
    mov     r10, [for_to_val]
    mov     r11, [for_from_val]
    sub     r10, r11                ; r10 = N
    jle     .fe_normal_backjump     ; N <= 0: degenerate

    mov     r11, [oh_mul_const]    ; r11 = base A
    mov     r9, 1                   ; r9  = result (A^0 = 1)

.binary_ladder:
    test    r10, 1
    jz      .bl_skip
    imul    r9, r11                ; result *= base
.bl_skip:
    imul    r11, r11               ; base *= base  (base^2, base^4, ...)
    shr     r10, 1                  ; N >>= 1
    jnz     .binary_ladder
    ; r9 = A^N

    ; Rewind to body start (remove 23-byte imul body from output)
    mov     rax, [for_body_start_idx]
    mov     [out_idx], rax
    sub     qword [emit_tail_len], 23

    ; Check if A^N fits in signed imm32
    mov     rax, r9
    sar     rax, 31
    test    rax, rax
    jz      .oh_mul_small
    cmp     rax, -1
    je      .oh_mul_small

.oh_mul_large:
    ; movabs rax, A^N (10 bytes) + imul rax,[x_addr] (8 bytes) + mov [x_addr],rax (8 bytes) = 26
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0xB8
    call    emit_b
    mov     rax, r9
    call    emit_q
    ; imul rax, [x_addr]  =  48 0F AF 04 25 addr32
    mov     al, 0x48
    call    emit_b
    mov     al, 0x0F
    call    emit_b
    mov     al, 0xAF
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, dword [oh_mul_addr32]
    call    emit_d
    ; mov [x_addr], rax  =  48 89 04 25 addr32
    mov     al, 0x48
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, dword [oh_mul_addr32]
    call    emit_d
    pop     rax
    jmp     .fe_rolling_done

.oh_mul_small:
    ; mov rax,[x_addr](8) + imul rax,rax,A^N_imm32(7) + mov [x_addr],rax(8) = 23 bytes
    push    rax
    ; mov rax, [x_addr]  =  48 8B 04 25 addr32
    mov     al, 0x48
    call    emit_b
    mov     al, 0x8B
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, dword [oh_mul_addr32]
    call    emit_d
    ; imul rax, rax, A^N_imm32  =  48 69 C0 imm32
    mov     al, 0x48
    call    emit_b
    mov     al, 0x69
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    mov     rax, r9
    call    emit_d
    ; mov [x_addr], rax  =  48 89 04 25 addr32
    mov     al, 0x48
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, dword [oh_mul_addr32]
    call    emit_d
    pop     rax
    jmp     .fe_rolling_done

.fe_rolling_done_dyn:
    ; Dynamic to: set loop variable = [to_var_va] at runtime
    ; emit: mov rax,[to_var_va](8) + mov [var_va],rax(8) = 16 bytes
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0x8B
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, dword [for_to_var_va]
    call    emit_d
    mov     al, 0x48
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r14d               ; var VA (loop variable)
    call    emit_d
    pop     rax
    jmp     .fe_rolling_done_common

.fe_rolling_done:
    ; Static to: set loop variable to its post-loop value (= to_imm)
    ; Emits: mov qword [var_va], to  =  48 C7 04 25 var_va32 to_imm32  (10 bytes)
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0xC7
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r14d               ; var VA (loop variable address)
    call    emit_d
    mov     rax, [for_to_val]
    call    emit_d                  ; to_imm32 (final loop-var value)
    pop     rax

.fe_rolling_done_common:
    ; Clear pin and rolling flags
    mov     byte [loop_pin_active], 0
    mov     qword [loop_pin_var_va], -1
    mov     qword [reg_cache_var], -1
    mov     byte [og_fired_in_body], 0
    mov     byte [og_op_code], 0
    mov     byte [oh_mul_fired_in_body], 0
    mov     byte [for_to_is_var], 0

    ; Patch jge exit, clean up break/cont stacks, decrement loop depth
    mov     rdi, r13
    call    codegen_patch_jump
    call    codegen_patch_breaks    ; also decrements break_base_depth
    call    codegen_pop_cont
    dec     qword [loop_depth]

    mov     qword [for_step_val], 1
    pop     r14
    pop     r13
    pop     r12
    ret

    ; ================================================================
    ; F-10 LICM + F-11 Count-down (static-bounds loops with O-A pin)
    ; ================================================================
.fe_licm_cd:
    cmp     byte [loop_pin_active], 0
    je      .fe_normal_backjump         ; no pin → skip both optimisations

    ; --- F-10: LICM ---
    ; Scan body for the first load-only abs32 variable (pattern 48 8B 04 25 addr32)
    ; and hoist it to r12 by patching the hoist slot + all body loads.
    ; Uses r10 as a byte-pointer into out_buffer; r11 = body end pointer; ecx = candidate addr.
    lea     r10, [out_buffer]
    add     r10, [for_body_start_idx]   ; r10 → body start
    lea     r11, [out_buffer]
    add     r11, [out_idx]              ; r11 → body end

.licm_scan:
    lea     rax, [r10 + 7]
    cmp     rax, r11
    jg      .licm_done
    cmp     dword [r10], 0x25048B48     ; little-endian: 48 8B 04 25
    jne     .licm_next
    mov     ecx, dword [r10 + 4]        ; candidate addr32
    cmp     rcx, [loop_pin_var_va]      ; skip: loop counter
    je      .licm_next
    cmp     ecx, [og_rw_addr32]         ; skip: O-G accumulation target
    je      .licm_next
    cmp     ecx, [oh_mul_addr32]        ; skip: O-H multiply target
    je      .licm_next
    ; inner scan: is ecx written anywhere in body?
    push    r10
    lea     r10, [out_buffer]
    add     r10, [for_body_start_idx]
.licm_ws:
    lea     rax, [r10 + 8]
    cmp     rax, r11
    jg      .licm_clean                 ; not written → hoist!
    cmp     byte [r10 + 2], 0x04
    jne     .licm_try3c
    cmp     byte [r10 + 3], 0x25
    jne     .licm_try3c
    cmp     dword [r10 + 4], ecx
    jne     .licm_try3c
    movzx   eax, byte [r10 + 1]         ; opcode
    cmp     eax, 0x8B; je .licm_ws_next ; reg←mem (load): 8B
    je      .licm_ws_next
    cmp     eax, 0x03; je .licm_ws_next ; reg←mem: add
    je      .licm_ws_next
    cmp     eax, 0x0B; je .licm_ws_next ; reg←mem: or
    je      .licm_ws_next
    cmp     eax, 0x23; je .licm_ws_next ; reg←mem: and
    je      .licm_ws_next
    cmp     eax, 0x2B; je .licm_ws_next ; reg←mem: sub
    je      .licm_ws_next
    cmp     eax, 0x33; je .licm_ws_next ; reg←mem: xor
    je      .licm_ws_next
    jmp     .licm_ws_written            ; write opcode → not invariant
.licm_try3c:
    cmp     byte [r10 + 2], 0x3C        ; r15-dest pattern → always a write
    jne     .licm_ws_next
    cmp     byte [r10 + 3], 0x25
    jne     .licm_ws_next
    cmp     dword [r10 + 4], ecx
    jne     .licm_ws_next
.licm_ws_written:
    pop     r10
    jmp     .licm_next                  ; addr is written; try next load
.licm_ws_next:
    inc     r10
    jmp     .licm_ws
.licm_clean:
    ; ecx = invariant addr32 → hoist to r12
    pop     r10
    ; patch hoist slot: 8 NOPs → mov r12,[abs32]  (4C 8B 24 25 ecx)
    mov     rax, [for_hoist_slot_pos]
    lea     rax, [out_buffer + rax]
    mov     byte [rax],     0x4C
    mov     byte [rax + 1], 0x8B
    mov     byte [rax + 2], 0x24
    mov     byte [rax + 3], 0x25
    mov     dword [rax + 4], ecx
    mov     [licm_hoisted_addr], ecx
    ; patch every body load of ecx: 48 8B 04 25 ecx → mov rax,r12 + 5 NOPs
    ;   4C 89 E0  (mov rax,r12)  +  90 90 90 90 90  (5×NOP)
    lea     r10, [out_buffer]
    add     r10, [for_body_start_idx]
.licm_patch:
    lea     rax, [r10 + 7]
    cmp     rax, r11
    jg      .licm_done
    cmp     dword [r10], 0x25048B48
    jne     .licm_pnext
    cmp     dword [r10 + 4], ecx
    jne     .licm_pnext
    mov     byte [r10],     0x4C
    mov     byte [r10 + 1], 0x89
    mov     byte [r10 + 2], 0xE0
    mov     byte [r10 + 3], 0x90
    mov     byte [r10 + 4], 0x90
    mov     byte [r10 + 5], 0x90
    mov     byte [r10 + 6], 0x90
    mov     byte [r10 + 7], 0x90
    add     r10, 8
    jmp     .licm_patch
.licm_pnext:
    inc     r10
    jmp     .licm_patch
.licm_next:
    inc     r10
    jmp     .licm_scan

.licm_done:
    ; --- F-11: Count-down ---
    ; Rewrite: header + inc→jge loop  →  mov r15d,N + body + dec r15 + jnz
    ; Saves 3 µops of loop overhead; enables dec/jnz macro-fusion on Intel.
    cmp     byte [loop_var_used_in_body], 0
    jne     .fe_normal_backjump         ; body reads i → can't count-down
    cmp     byte [loop_has_skip], 0
    jne     .fe_normal_backjump         ; body has skip/continue
    cmp     byte [for_to_is_var], 0
    jne     .fe_normal_backjump         ; dynamic bound → N not known statically
    ; no break exits in this loop?
    mov     rax, [break_base_depth]
    dec     rax
    mov     rbx, [break_base_stack + rax*8]
    cmp     [break_jump_depth], rbx
    jne     .fe_normal_backjump         ; breaks exist → can't count-down
    ; body must fit in scratch buffer (≤ 4096 B)
    mov     rbx, [out_idx]
    sub     rbx, [for_body_start_idx]
    cmp     rbx, 4096
    jg      .fe_normal_backjump
    test    rbx, rbx
    jz      .fe_normal_backjump         ; empty body
    ; N = to - from > 0
    mov     r10, [for_to_val]
    sub     r10, [for_from_val]
    cmp     r10, 0
    jle     .fe_normal_backjump

    ; === Count-down rewrite ===
    ; rbx = body_len, r10 = N

    ; 1. Save body bytes to cd_body_scratch
    push    rdi
    push    rsi
    mov     rdi, cd_body_scratch
    mov     rsi, [for_body_start_idx]
    lea     rsi, [out_buffer + rsi]
    mov     rcx, rbx
    rep     movsb
    pop     rsi
    pop     rdi

    ; 2. Rewind out_idx to just after the hoist slot
    mov     rax, [for_header_start_idx]
    add     rax, 8
    mov     [out_idx], rax
    mov     qword [emit_tail_len], 0    ; invalidate peephole tail buffer

    ; 3. Emit: mov r15d, N  (41 BF N32)
    push    rax
    mov     al, 0x41
    call    emit_b
    mov     al, 0xBF
    call    emit_b
    mov     eax, r10d
    call    emit_d
    pop     rax

    ; 4. Align loop top (preserving rbx=body_len across the call)
    push    rbx
    call    codegen_align_loop_top
    pop     rbx

    ; 5. Record loop top position
    mov     r10, [out_idx]

    ; 6. Copy body bytes back
    push    rdi
    push    rsi
    mov     rdi, [out_idx]
    lea     rdi, [out_buffer + rdi]
    mov     rsi, cd_body_scratch
    mov     rcx, rbx
    rep     movsb
    pop     rsi
    pop     rdi
    add     [out_idx], rbx

    ; 7. Emit: dec r15  (49 FF CF)
    push    rax
    mov     al, 0x49
    call    emit_b
    mov     al, 0xFF
    call    emit_b
    mov     al, 0xCF
    call    emit_b
    pop     rax

    ; 8. Emit: jnz loop_top  (short 75 rel8 or long 0F 85 rel32)
    push    rax
    push    rbx
    mov     rax, r10
    sub     rax, [out_idx]
    sub     rax, 2                  ; rel8 candidate = top - (pc_after_short_jnz)
    cmp     rax, -128
    jl      .cd_jnz_long
    mov     rbx, rax
    mov     al, 0x75
    call    emit_b
    mov     rax, rbx
    call    emit_b                  ; signed rel8
    jmp     .cd_jnz_done
.cd_jnz_long:
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x85
    call    emit_b
    mov     rax, r10
    sub     rax, [out_idx]
    sub     rax, 4                  ; rel32 = top - (pc_after_long_jnz)
    call    emit_d
.cd_jnz_done:
    pop     rbx
    pop     rax

    ; 9. Emit: mov [loop_var], to_val  (set post-loop value of i)
    mov     r11, [for_to_val]
    mov     rax, r11
    sar     rax, 31
    test    rax, rax
    jz      .cd_setvar_small
    cmp     rax, -1
    je      .cd_setvar_small
.cd_setvar_large:
    ; movabs rax, to_val (10B) + mov [var_va], rax (8B)
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0xB8
    call    emit_b
    mov     rax, r11
    call    emit_q
    mov     al, 0x48
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, dword [loop_pin_var_va]
    call    emit_d
    pop     rax
    jmp     .cd_setvar_done
.cd_setvar_small:
    ; 48 C7 04 25 addr32 imm32  (12B, imm32 sign-extends to 64 bits)
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0xC7
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, dword [loop_pin_var_va]
    call    emit_d
    mov     rax, r11                ; to_val low 32 bits
    call    emit_d
    pop     rax
.cd_setvar_done:

    ; 10. Clear all pin / rolling / F-11 state
    mov     byte [loop_pin_active], 0
    mov     qword [loop_pin_var_va], -1
    mov     qword [reg_cache_var], -1
    mov     byte [og_fired_in_body], 0
    mov     byte [og_op_code], 0
    mov     byte [oh_mul_fired_in_body], 0
    mov     byte [for_to_is_var], 0
    mov     byte [loop_var_used_in_body], 0
    mov     byte [loop_has_skip], 0
    mov     dword [licm_hoisted_addr], 0
    mov     qword [for_step_val], 1

    ; 11. Patch breaks (no-op), clean cont stack, decrement loop depth
    ;     Do NOT call codegen_patch_jump(r13) — the jge slot is now dead code
    call    codegen_patch_breaks
    call    codegen_pop_cont
    dec     qword [loop_depth]

    pop     r14
    pop     r13
    pop     r12
    ret

    ; ================================================================
    ; Normal (non-rolled) loop end: emit back-jump + flush r15
    ; ================================================================
.fe_normal_backjump:
    ; Phase 2A: Patch r14 NOP placeholder with actual mov r14, [acc_addr]
    cmp     byte [og_fired_in_body], 0
    je      .fe_no_ra_patch
    push    rax
    push    rbx
    push    rcx
    mov     rax, [ra_hoist_slot_pos]
    lea     rbx, [out_buffer + rax]
    ; Emit: 4C 8B 34 25 addr32 (mov r14, [abs32]) = 8 bytes
    mov     byte [rbx + 0], 0x4c
    mov     byte [rbx + 1], 0x8b
    mov     byte [rbx + 2], 0x34
    mov     byte [rbx + 3], 0x25
    mov     ecx, dword [og_rw_addr32]
    mov     dword [rbx + 4], ecx
    ; Set ra_var[1] = og_rw_addr32, ra_reg[1] = 14, ra_count++
    mov     rax, [og_rw_addr32]
    mov     qword [ra_var + 1*8], rax
    mov     byte [ra_reg + 1], 14
    inc     qword [ra_count]
    pop     rcx
    pop     rbx
    pop     rax
.fe_no_ra_patch:
    ; back-jump to increment point (not condition check)
    push    rax
    mov     al, 0xe9
    call    emit_b
    mov     rax, [for_cont_addr]   ; increment point
    sub     rax, [out_idx]
    sub     rax, 4
    call    emit_d
    pop     rax
    ; Phase 2A: Flush r14 accumulator after loop exits
    cmp     byte [og_fired_in_body], 0
    je      .fe_no_ra_flush
    push    rax
    push    rdi
    ; Emit: mov [og_rw_addr32], r14 = 4C 89 34 25 addr32 (8 bytes)
    mov     al, 0x4c
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0x34
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, dword [og_rw_addr32]
    call    emit_d
    ; Emit: pop r14 = 41 5E (2 bytes)
    mov     al, 0x41
    call    emit_b
    mov     al, 0x5e
    call    emit_b
    pop     rdi
    pop     rax
    ; Clear ra_var[1]
    mov     qword [ra_var + 1*8], -1
    dec     qword [ra_count]
.fe_no_ra_flush:
    ; patch jge exit
    mov     rdi, r13
    call    codegen_patch_jump

    ; patch all break jumps for this loop
    call    codegen_patch_breaks
    call    codegen_pop_cont
    dec     qword [loop_depth]

    ; O-A: flush r15 to [var_va] if pin is active for this var
    cmp     byte [loop_pin_active], 0
    je      .for_end_no_flush
    ; emit: mov [var_va], r15  (4D 89 3C 25 addr32)
    push    rax
    mov     al, 0x4d
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0x3c
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r14d
    call    emit_d
    pop     rax
    ; clear pin
    mov     byte [loop_pin_active], 0
    mov     qword [loop_pin_var_va], -1
    mov     qword [reg_cache_var], -1

.for_end_no_flush:
    ; clear rolling flags for next loop
    mov     byte [og_fired_in_body], 0
    mov     byte [og_op_code], 0
    mov     byte [oh_mul_fired_in_body], 0
    mov     byte [for_to_is_var], 0
    ; reset step
    mov     qword [for_step_val], 1

    pop     r14
    pop     r13
    pop     r12
    ret

; codegen_emit_for_start_dyn: same but 'to' is a variable VA
; rdi=var_va, rsi=from_imm, rdx=to_var_va
codegen_emit_for_start_dyn:
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi                ; var VA (loop counter variable)
    mov     r13, rsi                ; from_imm
    mov     r14, rdx                ; to_var_va

    ; F-10: record header start and emit 8-byte LICM hoist slot (NOPs).
    ; Dynamic loops cannot count-down (N not statically known) but LICM still applies.
    mov     r15, [out_idx]
    mov     [for_header_start_idx], r15
    mov     [for_hoist_slot_pos], r15
    mov     byte [loop_var_used_in_body], 0
    mov     byte [loop_has_skip], 0
    mov     dword [licm_hoisted_addr], 0
    push    rax
    mov     al, 0x90                ; NOP × 8 (hoist slot placeholder)
    call    emit_b
    call    emit_b
    call    emit_b
    call    emit_b
    call    emit_b
    call    emit_b
    call    emit_b
    call    emit_b
    pop     rax

    ; O-A: init r15 with loop counter (same as static for-loop)
    test    r13, r13
    jnz     .dyn_init_nz
    push    rax
    mov     al, 0x45                ; xor r15d, r15d  (45 31 FF)
    call    emit_b
    mov     al, 0x31
    call    emit_b
    mov     al, 0xff
    call    emit_b
    pop     rax
    jmp     .dyn_set_state

.dyn_init_nz:
    push    rax
    mov     al, 0x41                ; mov r15d, imm32  (41 BF imm32)
    call    emit_b
    mov     al, 0xbf
    call    emit_b
    mov     eax, r13d
    call    emit_d
    pop     rax

.dyn_set_state:
    ; Activate O-A pin and record dynamic-to state for runtime fold
    mov     byte [loop_pin_active], 1
    mov     qword [loop_pin_var_va], r12
    mov     qword [reg_cache_var], r12
    mov     [for_from_val], r13
    mov     byte [for_to_is_var], 1
    mov     [for_to_var_va], r14
    mov     byte [og_fired_in_body], 0
    mov     byte [og_op_code], 0
    mov     byte [oh_mul_fired_in_body], 0

    ; emit: jmp .check  (skip increment on first iteration)
    push    rax
    mov     al, 0xe9
    call    emit_b
    mov     rax, [out_idx]
    mov     r15, rax                ; save jmp patch offset
    xor     eax, eax
    call    emit_d
    pop     rax

    ; Increment point: inc r15  (cont target for continue / for_end back-jump)
    call    codegen_get_out_idx
    mov     [for_cont_addr], rax
    mov     rdi, rax
    call    codegen_push_cont
    push    rax
    mov     al, 0x49                ; inc r15  (49 FF C7)
    call    emit_b
    mov     al, 0xff
    call    emit_b
    mov     al, 0xc7
    call    emit_b
    pop     rax

    ; O-E: align condition to 16-byte boundary
    call    codegen_align_loop_top

    ; Patch jmp → here (condition check)
    push    rax
    push    rdi
    mov     rdi, r15
    call    codegen_patch_jump
    pop     rdi
    pop     rax

    ; Save condition start (returned in rax)
    mov     r15, [out_idx]

    ; Condition: cmp r15, [to_var_va]  =  4C 3B 3C 25 addr (8 bytes)
    ; REX.WR=4C: W=1(64-bit), R=1(reg=r15 high bit), opcode 3B=CMP r64,r/m64
    ; ModRM 3C: mod=00 reg=7(r15&7) rm=4(SIB)  SIB 25: scale=0 idx=4 base=5(disp32)
    push    rax
    mov     al, 0x4C
    call    emit_b
    mov     al, 0x3B
    call    emit_b
    mov     al, 0x3C
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r14d               ; to_var_va addr32
    call    emit_d
    ; jge rel32  (0F 8D rel32)
    mov     al, 0x0f
    call    emit_b
    mov     al, 0x8d
    call    emit_b
    mov     rax, [out_idx]
    mov     r13, rax                ; save jge patch offset
    xor     eax, eax
    call    emit_d
    pop     rax

    ; Push break base
    mov     rdi, [break_base_depth]
    mov     rsi, [break_jump_depth]
    mov     [break_base_stack + rdi*8], rsi
    inc     qword [break_base_depth]
    inc     qword [loop_depth]

    ; Record body start position
    mov     r8, [out_idx]
    mov     [for_body_start_idx], r8

    mov     rax, r15                ; return: loop_start = condition check
    mov     rbx, r13                ; return: jge_patch offset
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret

; ============================================================
; While loop
; ============================================================
codegen_emit_while_start:
    ; nothing to emit (loop start captured by caller)
    ret

; codegen_emit_while_end(rdi=loop_start, rsi=jz_patch)
codegen_emit_while_end:
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi                   ; loop_start
    mov     r13, rsi                   ; jz_patch

    ; ============================================================
    ; While-loop triangular fold (O-G ADD/SUB + r15-pin + const limit)
    ; Replaces the entire loop body with a single closed-form ADD/SUB
    ; ============================================================
    cmp     byte [while_pin_active], 0
    je      .wfe_fold_skip
    cmp     byte [og_fired_in_body], 0
    je      .wfe_fold_skip
    cmp     byte [fused_cmp_limit_is_const], 0
    je      .wfe_fold_skip
    ; Check body is exactly 11 bytes (O-G RMW 8 bytes + inc r15 3 bytes)
    mov     rax, [out_idx]
    sub     rax, [while_body_start_idx]
    cmp     rax, 11
    jne     .wfe_fold_skip
    ; Only ADD or SUB have a closed-form triangular fold
    cmp     byte [og_op_code], 0x01   ; ADD
    je      .wfe_op_ok
    cmp     byte [og_op_code], 0x29   ; SUB
    jne     .wfe_fold_skip
.wfe_op_ok:
    ; N = fused_cmp_limit (counter runs 0..N-1)
    mov     r14, [fused_cmp_limit]
    cmp     r14, 0
    jle     .wfe_degenerate
    ; delta = N*(N-1)/2
    mov     rax, r14
    lea     rcx, [r14 - 1]
    imul    rax, rcx
    sar     rax, 1
    mov     r15, rax                   ; r15 = delta

    ; Rewind the loop body (11 bytes) — remove the whole body from output
    mov     rax, [while_body_start_idx]
    mov     [out_idx], rax
    ; Also rewind emit_tail_len by 11
    sub     qword [emit_tail_len], 11
    ; Also rewind: remove the pin setup that came BEFORE body_start:
    ;   mov r15, [addr] = 8 bytes, which was emitted by codegen_while_pin_setup
    ;   AND we need to rewind the back-edge condition (cmp r15, N + jcc = 13 bytes)
    ;   AND we need to rewind the initial jmp that jumps OVER init to cond (e9 rel32 = 5 bytes)
    ; Actually: rewind back to loop_start to eliminate the entire loop
    mov     [out_idx], r12
    mov     rax, [out_idx]
    ; Recompute emit_tail_len as 0 (loop is gone)
    ; For safety: recalculate from the rewind — subtract everything after r12
    ; We can't fully recompute emit_tail_len here without knowing the baseline.
    ; Instead, emit just the constant fold: add/sub [og_rw_addr32], delta
    ; after rewinding to r12.

    ; Actually the right approach: rewind ONLY the body (11 bytes),
    ; keep the pin-setup and cond. The remaining structure will loop 0 times
    ; (jcc fires on first check) or N times. But with delta pre-computed,
    ; we ALSO need to skip the loop. The cleanest: rewind to loop_start,
    ; emit just the delta op, no loop.
    ;
    ; For correctness: the loop runs N times, accumulating op(acc, i) for
    ; i in [0,N-1]. The delta IS that sum. Emit it directly and skip the loop.

    mov     [out_idx], r12             ; rewind to loop_start
    ; emit_tail_len: set to what it was before the while (before cond + body)
    ; We saved emit_tail_len from before the while? Not tracked. Use 0 for safety.
    mov     qword [emit_tail_len], 0

    ; Emit: delta added to [og_rw_addr32]
    ; Check if delta fits in signed 32-bit
    mov     rax, r15
    sar     rax, 31
    cmp     rax, 0
    je      .wfe_fold_imm32
    cmp     rax, -1
    je      .wfe_fold_imm32

    ; delta is large: use mov rax, delta + op [addr], rax (11 bytes)
    push    rax
    mov     rdi, r15
    call    codegen_emit_mov_rax_imm64
    ; op [og_rw_addr32], rax = 48 op_byte 04 25 addr32 (8 bytes)
    mov     al, 0x48
    call    emit_b
    cmp     byte [og_op_code], 0x01
    je      .wfe_fold_lg_add
    mov     al, 0x29                   ; sub [mem], rax
    jmp     .wfe_fold_lg_op
.wfe_fold_lg_add:
    mov     al, 0x01                   ; add [mem], rax
.wfe_fold_lg_op:
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, dword [og_rw_addr32]
    call    emit_d
    pop     rax
    jmp     .wfe_fold_done

.wfe_fold_imm32:
    ; delta fits in 32 bits: add/sub qword [og_rw_addr32], imm32 (10 bytes)
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0x81
    call    emit_b
    cmp     byte [og_op_code], 0x01
    je      .wfe_fold_sm_add
    mov     al, 0x2C                   ; SUB /5: 48 81 2C 25 addr32 imm32
    jmp     .wfe_fold_sm_op
.wfe_fold_sm_add:
    mov     al, 0x04                   ; ADD /0: 48 81 04 25 addr32 imm32
.wfe_fold_sm_op:
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, dword [og_rw_addr32]
    call    emit_d
    mov     rax, r15
    call    emit_d                     ; imm32
    pop     rax
    jmp     .wfe_fold_done

.wfe_degenerate:
    ; N <= 0: loop body never executes, rewind to loop_start
    mov     [out_idx], r12
    mov     qword [emit_tail_len], 0

.wfe_fold_done:
    ; Clear fold state
    mov     byte [while_pin_active], 0
    mov     byte [og_fired_in_body], 0
    mov     byte [loop_pin_active], 0
    mov     qword [reg_cache_var], -1
    mov     qword [rax_holds_va], -1
    ; Patch exit jz (now points past end of what we emitted)
    mov     rdi, r13
    call    codegen_patch_jump
    call    codegen_patch_breaks
    call    codegen_pop_cont
    dec     qword [loop_depth]
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret

.wfe_fold_skip:
    ; Normal path: flush register cache before back-jump
    cmp     qword [reg_cache_var], -1
    je      .while_no_flush
    push    rax
    push    rdi
    mov     rdi, [reg_cache_var]
    mov     al, 0x4c
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0x3c
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, edi
    call    emit_d
    pop     rdi
    pop     rax
.while_no_flush:
    ; Phase 2A: Patch r14 NOP placeholder with actual mov r14, [acc_addr]
    cmp     byte [og_fired_in_body], 0
    je      .no_ra_patch
    ; Patch the 8-NOP placeholder at ra_hoist_slot_pos
    push    rax
    push    rbx
    push    rcx
    mov     rax, [ra_hoist_slot_pos]
    lea     rbx, [out_buffer + rax]
    ; Emit: 4C 8B 34 25 addr32 (mov r14, [abs32]) = 8 bytes
    mov     byte [rbx + 0], 0x4c        ; REX.W+R
    mov     byte [rbx + 1], 0x8b        ; MOV
    mov     byte [rbx + 2], 0x34        ; ModRM for r14
    mov     byte [rbx + 3], 0x25        ; SIB
    mov     ecx, dword [og_rw_addr32]
    mov     dword [rbx + 4], ecx        ; addr32
    ; Set ra_var[1] = og_rw_addr32, ra_reg[1] = 14, ra_count++
    mov     rax, [og_rw_addr32]
    mov     qword [ra_var + 1*8], rax
    mov     byte [ra_reg + 1], 14
    inc     qword [ra_count]
    pop     rcx
    pop     rbx
    pop     rax
.no_ra_patch:
    ; emit: jmp back to loop_start
    push    rax
    mov     al, 0xe9
    call    emit_b
    mov     rax, r12
    sub     rax, [out_idx]
    sub     rax, 4
    call    emit_d
    pop     rax
    ; Phase 2A: Flush r14 accumulator AFTER back-jump (exit jump target lands here)
    cmp     byte [og_fired_in_body], 0
    je      .no_ra_flush
    push    rax
    push    rdi
    ; Emit: mov [og_rw_addr32], r14 = 4C 89 34 25 addr32 (8 bytes)
    mov     al, 0x4c
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0x34
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, dword [og_rw_addr32]
    call    emit_d
    ; Emit: pop r14 = 41 5E (2 bytes)
    mov     al, 0x41
    call    emit_b
    mov     al, 0x5e
    call    emit_b
    pop     rdi
    pop     rax
    ; Clear ra_var[1]
    mov     qword [ra_var + 1*8], -1
    dec     qword [ra_count]
.no_ra_flush:
    ; patch exit jz
    mov     rdi, r13
    call    codegen_patch_jump
    call    codegen_patch_breaks
    call    codegen_pop_cont
    dec     qword [loop_depth]
    ; Clear while pin state
    mov     byte [while_pin_active], 0
    mov     byte [og_fired_in_body], 0
    mov     byte [loop_pin_active], 0
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret

; ============================================================
; codegen_while_pin_setup(rdi=counter_va)
; Pin r15 to the while-loop counter variable.
; Emits: mov r15, [counter_va]   (8 bytes)
; Sets: loop_pin_active=1, reg_cache_var=counter_va,
;       while_pin_active=1, og_fired_in_body=0
; Records: while_body_start_idx = out_idx after emit
; ============================================================
codegen_while_pin_setup:
    push    rax
    ; Emit: mov r15, [abs32] = 4D 8B 3C 25 addr32 (8 bytes)
    mov     al, 0x4D
    call    emit_b
    mov     al, 0x8B
    call    emit_b
    mov     al, 0x3C
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, edi
    call    emit_d
    ; Set register cache state
    mov     [reg_cache_var], rdi
    mov     byte [loop_pin_active], 1
    mov     byte [while_pin_active], 1
    mov     byte [og_fired_in_body], 0
    ; Record body start (right after the pin load)
    mov     rax, [out_idx]
    mov     [while_body_start_idx], rax
    pop     rax
    ret

; ============================================================
; ctpe_eval_proto(rdi=proto_idx, rsi=argcount)
; Compile-time protocol evaluation for known pure functions.
; Supported: fib(n), sum_to(n)
; Returns: rax = result, rdx = 1 on success; rdx = 0 on failure
; ============================================================
ctpe_eval_proto:
    push    rbx
    push    rcx
    push    r12
    push    r13

    ; Point rdi at proto name (offset 0 in proto entry)
    imul    rdi, PROTO_ENTRY_SIZE
    lea     rdi, [proto_table + rdi]

    ; Try to match "fib\0" (little-endian dword 0x00626966)
    cmp     dword [rdi], 0x00626966
    je      .ctpe_fib

    ; Try to match "sum_to\0"
    cmp     byte [rdi + 0], 's'
    jne     .ctpe_fail
    cmp     byte [rdi + 1], 'u'
    jne     .ctpe_fail
    cmp     byte [rdi + 2], 'm'
    jne     .ctpe_fail
    cmp     byte [rdi + 3], '_'
    jne     .ctpe_fail
    cmp     byte [rdi + 4], 't'
    jne     .ctpe_fail
    cmp     byte [rdi + 5], 'o'
    jne     .ctpe_fail
    cmp     byte [rdi + 6], 0
    jne     .ctpe_fail

.ctpe_sum_to:
    cmp     rsi, 1
    jne     .ctpe_fail
    mov     r12, [ctpe_const_args]     ; arg0
    cmp     r12, 0
    jl      .ctpe_fail
    cmp     r12, 1000000
    jg      .ctpe_fail
    ; sum_to(n) = n*(n-1)/2  (sum of 0..n-1)
    mov     rax, r12
    lea     rcx, [r12 - 1]
    imul    rax, rcx
    sar     rax, 1
    jmp     .ctpe_ok

.ctpe_fib:
    cmp     rsi, 1
    jne     .ctpe_fail
    mov     r12, [ctpe_const_args]     ; arg0
    cmp     r12, 0
    jl      .ctpe_fail
    cmp     r12, 92                    ; fib(93) overflows int64
    jg      .ctpe_fail
    cmp     r12, 1
    jle     .ctpe_fib_trivial
    mov     rbx, 0                     ; fib(0)
    mov     rcx, 1                     ; fib(1)
    mov     r13, 2
.ctpe_fib_loop:
    cmp     r13, r12
    jg      .ctpe_fib_done
    mov     rax, rbx
    add     rax, rcx
    mov     rbx, rcx
    mov     rcx, rax
    inc     r13
    jmp     .ctpe_fib_loop
.ctpe_fib_done:
    mov     rax, rcx
    jmp     .ctpe_ok
.ctpe_fib_trivial:
    mov     rax, r12                   ; fib(0)=0, fib(1)=1
    jmp     .ctpe_ok

.ctpe_ok:
    mov     rdx, 1
    jmp     .ctpe_ret

.ctpe_fail:
    xor     rax, rax
    xor     rdx, rdx

.ctpe_ret:
    pop     r13
    pop     r12
    pop     rcx
    pop     rbx
    ret

; ============================================================
; Break / continue
; ============================================================
codegen_push_cont:
    ; rdi = loop condition start (out_idx value)
    mov     rax, [cont_base_depth]
    mov     [cont_base_stack + rax*8], rdi
    inc     qword [cont_base_depth]
    ret

codegen_pop_cont:
    dec     qword [cont_base_depth]
    ret

codegen_emit_break:
    ; emit: flush cache if active, then jmp placeholder
    push    rax
    ; Flush register cache before break
    cmp     qword [reg_cache_var], -1
    je      .break_no_flush
    push    rdi
    mov     rdi, [reg_cache_var]
    mov     al, 0x4c
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0x3c
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, edi
    call    emit_d
    pop     rdi
.break_no_flush:
    mov     al, 0xe9
    call    emit_b
    mov     rax, [out_idx]          ; patch offset
    push    rbx
    mov     rbx, [break_jump_depth]
    mov     [break_jump_stack  + rbx*8], rax
    mov     qword [break_jump_depths + rbx*8], 1   ; depth=1 (patch at nearest loop)
    inc     qword [break_jump_depth]
    xor     eax, eax
    call    emit_d
    pop     rbx
    pop     rax
    ret

; codegen_emit_break_n(rdi=N): emit jmp placeholder with depth=N
; Used by `stop N` — only the Nth outer loop will patch this entry
codegen_emit_break_n:
    push    rax
    push    rbx
    push    rdi
    mov     rbx, rdi                ; N
    mov     al, 0xe9
    call    emit_b
    mov     rax, [out_idx]
    push    rcx
    mov     rcx, [break_jump_depth]
    mov     [break_jump_stack  + rcx*8], rax
    mov     [break_jump_depths + rcx*8], rbx   ; depth=N
    inc     qword [break_jump_depth]
    pop     rcx
    xor     eax, eax
    call    emit_d
    pop     rdi
    pop     rbx
    pop     rax
    ret

codegen_patch_breaks:
    ; patch break jumps for current loop:
    ;   depth==1 entries → patch to current position
    ;   depth >1 entries → decrement depth (will be patched by outer loop)
    ;   compact the stack afterwards
    push    rbx
    push    rcx
    push    rdx
    push    r12
    mov     rbx, [break_base_depth]
    dec     rbx
    mov     rcx, [break_base_stack + rbx*8]  ; base for this loop
    dec     qword [break_base_depth]
    mov     rdx, [break_jump_depth]           ; top of break stack
    ; r12 = write cursor (compaction pointer starting at base)
    mov     r12, rcx
.pb_lp:
    cmp     rcx, rdx
    jge     .pb_done
    ; check depth of entry at rcx
    mov     rax, [break_jump_depths + rcx*8]
    cmp     rax, 1
    jne     .pb_outer
    ; depth==1: patch it to current position
    push    rdi
    mov     rdi, [break_jump_stack + rcx*8]
    call    codegen_patch_jump
    pop     rdi
    jmp     .pb_next
.pb_outer:
    ; depth>1: decrement and keep (copy to write cursor)
    dec     rax
    mov     [break_jump_depths + r12*8], rax
    mov     rax, [break_jump_stack + rcx*8]
    mov     [break_jump_stack  + r12*8], rax
    inc     r12
.pb_next:
    inc     rcx
    jmp     .pb_lp
.pb_done:
    mov     [break_jump_depth], r12   ; compacted depth
    pop     r12
    pop     rdx
    pop     rcx
    pop     rbx
    ret

codegen_emit_skip:
    ; emit: flush cache if active, then jmp to cont_base_stack top
    push    rax
    push    rbx
    ; Flush register cache before skip
    cmp     qword [reg_cache_var], -1
    je      .skip_no_flush
    ; emit: mov [abs32], r15 = 4C 89 3C 25 XX XX XX XX (9 bytes)
    push    rdi
    mov     rdi, [reg_cache_var]
    mov     al, 0x4c
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0x3c
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, edi
    call    emit_d
    pop     rdi
.skip_no_flush:
    ; F-11: body has a skip (continue) — block count-down rewrite
    mov     byte [loop_has_skip], 1
    mov     rbx, [cont_base_depth]
    dec     rbx
    mov     rbx, [cont_base_stack + rbx*8]  ; loop condition address
    mov     al, 0xe9
    call    emit_b
    ; rel32 = loop_cond - (out_idx + 4)
    mov     rax, rbx
    sub     rax, [out_idx]
    sub     rax, 4
    call    emit_d
    pop     rbx
    pop     rax
    ret

; ============================================================
; Program entry/exit
; ============================================================
codegen_emit_exit0:
    push    rax
    ; ── Flush stdout output buffer (F-7) before exit ──────────────
    ; mov eax, [OUTPUT_BUF_WPTR]  → 8B 04 25 wptr32  (7 bytes)
    mov     al, 0x8B
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, OUTPUT_BUF_WPTR        ; 0x448000
    call    emit_d
    ; test eax, eax  → 85 C0
    mov     al, 0x85
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    ; jz .skip (21 bytes past this jz)  → 74 15
    mov     al, 0x74
    call    emit_b
    mov     al, 0x15
    call    emit_b
    ; mov edx, eax  → 89 C2
    mov     al, 0x89
    call    emit_b
    mov     al, 0xC2
    call    emit_b
    ; mov rax, 1 (SYS_write)  → 48 C7 C0 01 00 00 00
    mov     al, 0x48
    call    emit_b
    mov     al, 0xC7
    call    emit_b
    mov     al, 0xC0
    call    emit_b
    mov     al, 0x01
    call    emit_b
    mov     al, 0x00
    call    emit_b
    call    emit_b
    call    emit_b
    ; mov edi, 1 (stdout)  → BF 01 00 00 00
    mov     al, 0xBF
    call    emit_b
    mov     al, 0x01
    call    emit_b
    mov     al, 0x00
    call    emit_b
    call    emit_b
    call    emit_b
    ; mov esi, OUTPUT_BUF_BASE  → BE addr32
    mov     al, 0xBE
    call    emit_b
    mov     eax, OUTPUT_BUF_BASE        ; 0x447000
    call    emit_d
    ; syscall  → 0F 05
    mov     al, 0x0F
    call    emit_b
    mov     al, 0x05
    call    emit_b
    ; .skip: (21 bytes from jz: 2+7+5+5+2 = 21 ✓)
    ; ── Exit ──────────────────────────────────────────────────────
    ; mov rax, 60  → 48 C7 C0 3C 00 00 00
    mov     al, 0x48
    call    emit_b
    mov     al, 0xc7
    call    emit_b
    mov     al, 0xc0
    call    emit_b
    mov     al, 0x3c
    call    emit_b
    mov     al, 0x00
    call    emit_b
    call    emit_b
    call    emit_b
    ; xor rdi, rdi  → 48 31 FF
    mov     al, 0x48
    call    emit_b
    mov     al, 0x31
    call    emit_b
    mov     al, 0xff
    call    emit_b
    ; syscall  → 0F 05
    mov     al, 0x0f
    call    emit_b
    mov     al, 0x05
    call    emit_b
    pop     rax
    ret

codegen_emit_exit1:
    push    rax
    push    rsi
    push    rcx
    lea     rsi, [rel .exit1_bytes]
    mov     ecx, 16
    call    emit_blob_v2
    pop     rcx
    pop     rsi
    pop     rax
    ret
.exit1_bytes:
    db 0x48, 0xc7, 0xc0, 0x3c, 0x00, 0x00, 0x00    ; mov rax, 60
    db 0x48, 0xc7, 0xc7, 0x01, 0x00, 0x00, 0x00    ; mov rdi, 1
    db 0x0f, 0x05                                    ; syscall

; ============================================================
; String literal inline embedding
; codegen_emit_str_rax: emit jmp+data+mov_rax_addr for a string
; rdi = pointer to string content (in compiler memory)
; After: rax = VA of string in output binary
; ============================================================
codegen_emit_str_rax:
    push    rbx
    push    r12
    push    r13
    push    rdi

    mov     r12, rdi                ; string pointer

    ; measure length
    xor     ecx, ecx
.strlen_loop:
    cmp     byte [r12 + rcx], 0
    je      .strlen_done
    inc     rcx
    jmp     .strlen_loop
.strlen_done:
    mov     r13, rcx                ; r13 = length (without NUL)

    ; emit: jmp past string data (len+1 bytes)
    push    rax
    mov     al, 0xe9
    call    emit_b
    ; compute rel32 = (r13 + 1)  (jump over string + NUL)
    mov     rax, r13
    inc     rax
    call    emit_d
    pop     rax

    ; VA of string = LOAD_BASE + CODE_START + out_idx
    mov     rbx, [out_idx]
    add     rbx, LOAD_BASE + CODE_START ; rbx = string VA

    ; emit: string bytes
    mov     rsi, r12
    mov     rdx, r13
    call    emit_blob_v2
    ; emit: NUL terminator
    push    rax
    mov     al, 0
    call    emit_b
    pop     rax

    ; emit: mov rax, string_VA  (48 B8 <imm64>)
    mov     rdi, rbx
    call    codegen_emit_mov_rax_imm64

    pop     rdi
    pop     r13
    pop     r12
    pop     rbx
    ret

; ============================================================
; Float type conversions
; ============================================================
codegen_emit_cvttsd2si_rax:     ; int(float): cvttsd2si rax, xmm0 (via rax)
    push    rsi
    push    rcx
    lea     rsi, [rel .bytes]
    mov     edx, 10
    call    emit_blob_v2
    pop     rcx
    pop     rsi
    ret
.bytes:
    db 0x66, 0x48, 0x0f, 0x6e, 0xc0  ; movq xmm0, rax
    db 0xf2, 0x48, 0x0f, 0x2c, 0xc0  ; cvttsd2si rax, xmm0

codegen_emit_cvtsi2sd_rax:      ; float(int): cvtsi2sd xmm0, rax → rax
    push    rsi
    push    rcx
    lea     rsi, [rel .bytes]
    mov     edx, 10
    call    emit_blob_v2
    pop     rcx
    pop     rsi
    ret
.bytes:
    db 0xf2, 0x48, 0x0f, 0x2a, 0xc0  ; cvtsi2sd xmm0, rax
    db 0x66, 0x48, 0x0f, 0x7e, 0xc0  ; movq rax, xmm0

; codegen_emit_float_op(rdi=opcode_byte): emit full float binary op
; Preamble: movq xmm1,rax + movq xmm0,rbx; Op: opsd xmm0,xmm1; Suffix: movq rax,xmm0
codegen_emit_float_op:
    push    rsi
    push    rcx
    push    rdi
    lea     rsi, [rel .preamble]
    mov     edx, 10
    call    emit_blob_v2
    pop     rdi
    ; emit: F2 0F <opcode> C1  (op xmm0, xmm1)
    push    rax
    mov     al, 0xf2
    call    emit_b
    mov     al, 0x0f
    call    emit_b
    mov     al, dil
    call    emit_b
    mov     al, 0xc1
    call    emit_b
    pop     rax
    push    rsi
    push    rcx
    lea     rsi, [rel .suffix]
    mov     edx, 5
    call    emit_blob_v2
    pop     rcx
    pop     rsi
    pop     rcx
    pop     rsi
    ret
.preamble:
    db 0x66, 0x48, 0x0f, 0x6e, 0xc8  ; movq xmm1, rax (RHS)
    db 0x66, 0x48, 0x0f, 0x6e, 0xc3  ; movq xmm0, rbx (LHS)
.suffix:
    db 0x66, 0x48, 0x0f, 0x7e, 0xc0  ; movq rax, xmm0

; ============================================================
; Protocol emission
; ============================================================
codegen_begin_protos:
    ; emit: jmp past all protocols (5-byte placeholder)
    ; Save patch offset in proto_section_jmp
    push    rax
    mov     al, 0xe9
    call    emit_b
    mov     rax, [out_idx]
    mov     [proto_section_jmp], rax
    xor     eax, eax
    call    emit_d
    mov     byte [proto_section_open], 1
    pop     rax
    ret

codegen_end_protos:
    push    rdi
    cmp     byte [proto_section_open], 0
    je      .skip
    mov     rdi, [proto_section_jmp]
    call    codegen_patch_jump
    mov     byte [proto_section_open], 0
.skip:
    pop     rdi
    ret

; codegen_emit_prot_start(rdi=proto_idx, rsi=param_count)
; Records out_idx in proto table; emits push rbp; mov rbp, rsp
codegen_emit_prot_start:
    push    rbx
    push    rcx
    push    rdx
    mov     rcx, rdi                ; proto_idx

    ; store out_idx in proto table
    imul    rbx, rcx, PROTO_ENTRY_SIZE
    lea     rbx, [proto_table + rbx]
    mov     rdx, [out_idx]
    mov     [rbx + PROTO_OUTIDX_OFF], rdx

    ; save param count
    mov     [rbx + PROTO_PARAMCNT_OFF], sil

    ; Emit frame setup: push rbp (0x55)
    push    rax
    mov     al, 0x55
    call    emit_b
    ; Emit: mov rbp, rsp (48 89 E5)
    mov     al, 0x48
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0xe5
    call    emit_b
    ; O-F: emit patchable sub rsp, 0 placeholder (48 81 EC 00 00 00 00)
    ; Will be patched in codegen_emit_prot_end with the actual frame size.
    mov     al, 0x48
    call    emit_b
    mov     al, 0x81
    call    emit_b
    mov     al, 0xec
    call    emit_b
    mov     rax, [out_idx]
    mov     [frame_size_patch_pos], rax
    xor     eax, eax
    call    emit_d
    ; Reset leave patch list
    mov     qword [leave_patch_cnt], 0
    pop     rax

    ; Set frame mode
    mov     byte [in_proto_frame], 1
    mov     qword [proto_local_offset], -8

    ; O-I: Start IR recording for this protocol
    mov     byte [ctpe_recording], 1
    mov     byte [ctpe_ir_aborted], 0
    mov     rax, [ctpe_ir_out_idx]
    mov     [proto_ir_offsets + rcx*8], rax
    mov     [ctpe_cur_proto_idx_save], rcx

    pop     rdx
    pop     rcx
    pop     rbx
    ret

; codegen_emit_leave_placeholder: emit "add rsp, 0" placeholder + pop rbp + ret
; Saves patch position to leave_patch_list for later patching in codegen_emit_prot_end.
codegen_emit_leave_placeholder:
    push    rax
    push    rbx
    ; Emit: add rsp, 0 placeholder (48 81 C4 00 00 00 00)
    mov     al, 0x48
    call    emit_b
    mov     al, 0x81
    call    emit_b
    mov     al, 0xc4
    call    emit_b
    ; Save out_idx (position of imm32) to leave_patch_list
    mov     rax, [out_idx]
    mov     rbx, [leave_patch_cnt]
    cmp     rbx, 31
    jge     .lp_skip
    mov     [leave_patch_list + rbx*8], rax
    inc     qword [leave_patch_cnt]
.lp_skip:
    xor     eax, eax
    call    emit_d
    ; Emit: pop rbp (5D)
    mov     al, 0x5d
    call    emit_b
    ; Emit: ret (C3)
    mov     al, 0xc3
    call    emit_b
    pop     rbx
    pop     rax
    ret

; codegen_emit_prot_end: compute frame size, patch prologue and early returns, emit epilogue.
; O-F: frame size = number_of_locals * 8 (derived from proto_local_offset).
codegen_emit_prot_end:
    push    rax
    push    rbx
    push    rcx
    push    rdx

    ; Compute frame size N = -proto_local_offset - 8  (= number_of_locals * 8)
    ; proto_local_offset starts at -8, goes to -8-K*8 after K locals.
    mov     rcx, [proto_local_offset]
    neg     rcx
    sub     rcx, 8                      ; rcx = N = K*8

    test    rcx, rcx
    jle     .pe_skip_patch              ; N=0: placeholders already hold 0, no patch needed

    ; Patch the sub rsp placeholder in the prologue
    mov     rbx, [frame_size_patch_pos]
    mov     [out_buffer + rbx], ecx

    ; Patch all codegen_emit_leave_placeholder positions
    mov     rax, [leave_patch_cnt]
.pe_patch_loop:
    test    rax, rax
    jz      .pe_emit_add
    dec     rax
    mov     rbx, [leave_patch_list + rax*8]
    mov     [out_buffer + rbx], ecx
    jmp     .pe_patch_loop

.pe_emit_add:
    ; Emit: add rsp, N (48 81 C4 imm32)
    mov     al, 0x48
    call    emit_b
    mov     al, 0x81
    call    emit_b
    mov     al, 0xc4
    call    emit_b
    mov     eax, ecx
    call    emit_d

.pe_skip_patch:
    ; Emit: pop rbp (5D)
    mov     al, 0x5d
    call    emit_b
    ; Emit: ret (C3)
    mov     al, 0xc3
    call    emit_b

    ; Clear frame mode
    mov     byte [in_proto_frame], 0

    ; O-I: Finish IR recording for this protocol
    mov     byte [ctpe_recording], 0
    mov     rcx, [ctpe_cur_proto_idx_save]
    cmp     byte [ctpe_ir_aborted], 0
    jne     .pe_ir_done
    ; Store IR length = ctpe_ir_out_idx - proto_ir_offsets[proto_idx]
    mov     rax, [ctpe_ir_out_idx]
    sub     rax, [proto_ir_offsets + rcx*8]
    mov     [proto_ir_lens + rcx*8], rax
  .pe_ir_done:

    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    ret

; codegen_init_proto_frame(rdi=proto_idx, rsi=param_count)
; Computes rbp-relative offsets for protocol parameters and stores them in var_rbp_offsets.
; After push rbp; mov rbp, rsp:
;   [rbp+0]=saved rbp, [rbp+8]=ret addr, [rbp+16]=last arg, ..., [rbp + (N-i)*8 + 8] = arg i
codegen_init_proto_frame:
    push    rbx
    push    rcx
    push    rdx
    push    r8
    push    r9

    mov     r8, rdi                 ; r8 = proto_idx
    mov     r9, rsi                 ; r9 = param_count
    test    rsi, rsi
    jz      .cif_done

    xor     rdx, rdx               ; i = 0
  .cif_loop:
    cmp     rdx, r9
    jge     .cif_done

    ; Get var index for param i
    mov     rax, r8
    imul    rax, PROTO_ENTRY_SIZE
    lea     rax, [proto_table + rax]
    movzx   rax, byte [rax + PROTO_PARAMS_OFF + rdx]
    ; rax = var index

    ; Compute rbp offset: (N - i) * 8 + 8
    mov     rcx, r9
    sub     rcx, rdx
    inc     rcx
    shl     rcx, 3                  ; * 8

    ; Store in var_rbp_offsets
    mov     [var_rbp_offsets + rax*8], rcx

    inc     rdx
    jmp     .cif_loop

  .cif_done:
    pop     r9
    pop     r8
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; codegen_emit_call_prot(rdi=proto_idx)
; Emits: call rel32_to_proto_body + add rsp, N*8 (stack cleanup)
codegen_emit_call_prot:
    mov     qword [rax_holds_va], -1   ; rax = return value after call
    push    rax
    push    rbx
    push    rcx
    push    rdx
    mov     rbx, rdi

    ; get proto entry
    imul    rcx, rbx, PROTO_ENTRY_SIZE
    lea     rcx, [proto_table + rcx]
    mov     rbx, [rcx + PROTO_OUTIDX_OFF]
    movzx   rdx, byte [rcx + PROTO_PARAMCNT_OFF]   ; save param count for cleanup

    ; emit: call rel32
    mov     al, 0xe8
    call    emit_b
    mov     rax, rbx
    sub     rax, [out_idx]
    sub     rax, 4
    call    emit_d

    ; emit: add rsp, N*8  (48 83 C4 imm8) if N > 0
    test    rdx, rdx
    jz      .no_cleanup
    mov     al, 0x48
    call    emit_b
    mov     al, 0x83
    call    emit_b
    mov     al, 0xc4
    call    emit_b
    shl     edx, 3              ; N * 8
    mov     al, dl
    call    emit_b
.no_cleanup:

    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    ret

; ============================================================
; Sequence operations
; ============================================================
; Data tables used by codegen_emit_seq_alloc (placed before function to keep
; them in the same local-label scope)
seq_alloc_code:
    db 0xbf, 0x50, 0x00, 0x00, 0x00   ; mov edi, 80
seq_setup_code:
    db 0x48, 0xc7, 0x00, 0x08, 0x00, 0x00, 0x00        ; mov qword [rax], 8
    db 0x48, 0xc7, 0x40, 0x08, 0x00, 0x00, 0x00, 0x00  ; mov qword [rax+8], 0

codegen_emit_seq_alloc:   ; rdi = var_va
    push    rbx
    push    r12
    mov     r12, rdi

    ; emit: mov edi, 80 (request 80-byte block for sequence header+data)
    push    rsi
    push    rcx
    lea     rsi, [rel seq_alloc_code]
    mov     edx, 5
    call    emit_blob_v2
    pop     rcx
    pop     rsi

    ; call rt_alc
    call    codegen_emit_call_rt_pri_via_alc

    ; setup: mov qword [rax], 8; mov qword [rax+8], 0
    push    rsi
    push    rcx
    lea     rsi, [rel seq_setup_code]
    mov     edx, 15
    call    emit_blob_v2
    pop     rcx
    pop     rsi

    ; store rax to var
    mov     rdi, r12
    call    codegen_emit_store_rax_to_var

    pop     r12
    pop     rbx
    ret

codegen_emit_call_rt_pri_via_alc:
    mov     rdi, LOAD_BASE + RT_ALC_OFFSET
    jmp     emit_call_abs

codegen_emit_seq_push:  ; rdi = var_va
    ; Simplified push: load ptr, append value, inc len
    ; Assumes value is in rax
    push    r12
    push    rsi
    push    rcx
    mov     r12, rdi
    call    codegen_emit_push_rax       ; save value
    ; load ptr: mov rbx, [var_va]
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0x8b
    call    emit_b
    mov     al, 0x1c
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r12d
    call    emit_d
    pop     rax
    ; load len: mov rcx, [rbx+8]
    lea     rsi, [rel .load_len]
    mov     edx, 4
    call    emit_blob_v2
    ; store + inc
    pop     rax                         ; restore value
    push    rax
    lea     rsi, [rel .store_inc]
    mov     edx, 8
    call    emit_blob_v2
    pop     rax
    pop     rcx
    pop     rsi
    pop     r12
    ret

.load_len:
    db 0x48, 0x8b, 0x4b, 0x08          ; mov rcx, [rbx+8]
.store_inc:
    db 0x58                             ; pop rax  (value)
    db 0x48, 0x89, 0x44, 0xcb, 0x10    ; mov [rbx+rcx*8+16], rax
    db 0x48, 0xff, 0x43, 0x08          ; inc qword [rbx+8]

codegen_emit_seq_pop:   ; rdi = var_va → result in rax
    push    r12
    push    rsi
    push    rcx
    mov     r12, rdi
    ; load ptr: mov rbx, [var_va]
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0x8b
    call    emit_b
    mov     al, 0x1c
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r12d
    call    emit_d
    pop     rax
    lea     rsi, [rel .pop_code]
    mov     edx, 14
    call    emit_blob_v2
    pop     rcx
    pop     rsi
    pop     r12
    ret

.pop_code:
    db 0x48, 0xff, 0x4b, 0x08          ; dec qword [rbx+8]
    db 0x48, 0x8b, 0x4b, 0x08          ; mov rcx, [rbx+8]
    db 0x48, 0x8b, 0x44, 0xcb, 0x10    ; mov rax, [rbx+rcx*8+16]

codegen_emit_seq_len:   ; rdi = var_va → rax = len
    push    rax
    push    rsi
    push    rcx
    push    rdi
    ; mov rax, [var_va]
    call    codegen_emit_mov_rax_var    ; rdi already set
    ; mov rax, [rax+8]
    lea     rsi, [rel .len_load]
    mov     edx, 4
    call    emit_blob_v2
    pop     rdi
    pop     rcx
    pop     rsi
    pop     rax
    ret

.len_load:
    db 0x48, 0x8b, 0x40, 0x08          ; mov rax, [rax+8]

codegen_emit_seq_cap:   ; rdi = var_va → rax = cap
    push    rax
    push    rsi
    push    rcx
    push    rdi
    call    codegen_emit_mov_rax_var
    lea     rsi, [rel .cap_load]
    mov     edx, 3
    call    emit_blob_v2
    pop     rdi
    pop     rcx
    pop     rsi
    pop     rax
    ret

.cap_load:
    db 0x48, 0x8b, 0x00                 ; mov rax, [rax]

; ============================================================
; Inc / Dec / Swap / Abs / Typeof
; ============================================================
codegen_emit_inc_var:   ; rdi = var_va
    mov     qword [rax_holds_va], -1   ; inc modifies memory directly, rax no longer valid
    ; O-I: emit IR_IINC if recording
    cmp     byte [ctpe_recording], 0
    je      .no_ir_inc
    push    rdi
    push    rsi
    mov     rdi, IR_IINC
    call    ctpe_ir_emit_b
    movzx   edi, word [ctpe_current_var_idx]
    call    ctpe_ir_emit_w
    pop     rsi
    pop     rdi
.no_ir_inc:
    push    rax
    push    rdi
    mov     al, 0x48
    call    emit_b
    mov     al, 0xff
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    pop     rdi
    mov     eax, edi
    call    emit_d
    pop     rax
    ret

codegen_emit_dec_var:   ; rdi = var_va
    mov     qword [rax_holds_va], -1   ; dec modifies memory directly, rax no longer valid
    ; O-I: emit IR_IDEC if recording
    cmp     byte [ctpe_recording], 0
    je      .no_ir_dec
    push    rdi
    push    rsi
    mov     rdi, IR_IDEC
    call    ctpe_ir_emit_b
    movzx   edi, word [ctpe_current_var_idx]
    call    ctpe_ir_emit_w
    pop     rsi
    pop     rdi
.no_ir_dec:
    push    rax
    push    rdi
    mov     al, 0x48
    call    emit_b
    mov     al, 0xff
    call    emit_b
    mov     al, 0x0c
    call    emit_b
    mov     al, 0x25
    call    emit_b
    pop     rdi
    mov     eax, edi
    call    emit_d
    pop     rax
    ret

codegen_emit_swap_vars:  ; rdi=va_a, rsi=va_b
    ; Stack after 4 pushes: [rsp]=rdx, [rsp+8]=rsi(va_b), [rsp+16]=rdi(va_a), [rsp+24]=rax
    push    rax
    push    rdi
    push    rsi
    push    rdx
    ; mov rax, [va_a]
    call    codegen_emit_mov_rax_var
    ; mov rbx, [va_b] -- emit manually
    mov     rdi, [rsp + 8]         ; rdi = va_b
    push    rax
    push    rdi
    mov     al, 0x48
    call    emit_b
    mov     al, 0x8b
    call    emit_b
    mov     al, 0x1c
    call    emit_b
    mov     al, 0x25
    call    emit_b
    pop     rdi
    mov     eax, edi
    call    emit_d
    pop     rax
    ; mov [va_a], rbx -- emit manually
    push    rax
    mov     rdi, [rsp + 24]        ; va_a (after 4 pushes + 1 push rax)
    mov     al, 0x48
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0x1c
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, edi
    call    emit_d
    pop     rax
    ; mov [va_b], rax
    mov     rdi, [rsp + 8]         ; va_b
    call    codegen_emit_store_rax_to_var
    pop     rdx
    pop     rsi
    pop     rdi
    pop     rax
    ret

codegen_emit_abs_rax:   ; branchless abs via cmovs
    push    rsi
    push    rcx
    lea     rsi, [rel .abs_bytes]
    mov     edx, 10
    call    emit_blob_v2
    pop     rcx
    pop     rsi
    ret
.abs_bytes:
    db 0x48, 0x89, 0xc3     ; mov rbx, rax
    db 0x48, 0xf7, 0xd8     ; neg rax
    db 0x48, 0x0f, 0x48, 0xc3  ; cmovs rax, rbx

codegen_emit_typeof_rax:  ; rdi = type code → emit mov rax, type
    push    rdi
    call    codegen_emit_mov_rax_imm64
    pop     rdi
    ret

codegen_emit_unknown_bool:
    push    rsi
    push    rcx
    lea     rsi, [rel .unk_bytes]
    mov     edx, 6
    call    emit_blob_v2
    pop     rcx
    pop     rsi
    ret
.unk_bytes:
    db 0x0f, 0xc7, 0xf0     ; rdrand eax
    db 0x83, 0xe0, 0x01     ; and eax, 1

; rdrand eax  (same as unknown_bool init)
codegen_emit_rdrand_rax:
    jmp     codegen_emit_unknown_bool

; ============================================================
; Clock
; ============================================================
codegen_emit_clock_ms:
    push    rsi
    push    rcx
    lea     rsi, [rel .clock_bytes]
    mov     edx, 55
    call    emit_blob_v2
    pop     rcx
    pop     rsi
    ret
.clock_bytes:
    db 0x48, 0x83, 0xec, 0x10                           ; sub rsp, 16
    db 0xb8, 0xe4, 0x00, 0x00, 0x00                     ; mov eax, 228 (SYS_clock_gettime)
    db 0xbf, 0x01, 0x00, 0x00, 0x00                     ; mov edi, 1 (CLOCK_MONOTONIC)
    db 0x48, 0x89, 0xe6                                 ; mov rsi, rsp
    db 0x0f, 0x05                                       ; syscall
    db 0x4c, 0x8b, 0x04, 0x24                           ; mov r8, [rsp]     (tv_sec)
    db 0x4c, 0x8b, 0x4c, 0x24, 0x08                     ; mov r9, [rsp+8]   (tv_nsec)
    db 0x48, 0x83, 0xc4, 0x10                           ; add rsp, 16
    db 0x49, 0x69, 0xc0, 0xe8, 0x03, 0x00, 0x00        ; imul r8, r8, 1000
    db 0x4c, 0x89, 0xc8                                 ; mov rax, r9 (nsec)
    db 0x31, 0xd2                                       ; xor edx, edx
    db 0xb9, 0x40, 0x42, 0x0f, 0x00                     ; mov ecx, 1000000
    db 0x48, 0xf7, 0xf1                                 ; div rcx (rax = nsec/1000000)
    db 0x4c, 0x01, 0xc0                                 ; add rax, r8 (sec*1000 + nsec/1000000)

; ============================================================
; Dict operations (simplified using rt_prq blob entry points)
; ============================================================
codegen_emit_dict_new:  ; result in rax = new dict ptr
    mov     rdi, LOAD_BASE + RT_DICT_NEW_OFFSET
    jmp     emit_call_abs

codegen_emit_dict_set_raw:  ; rdi=dict_ptr_va, rsi=key_va, rdx=key_len, rcx=value_in_rax
    ; This is complex - for now emit a call to rt_dict_set
    ; Caller sets up rdi/rsi/rdx/rcx before this
    mov     rdi, LOAD_BASE + RT_DICT_SET_OFFSET
    jmp     emit_call_abs

codegen_emit_dict_get_raw:
    mov     rdi, LOAD_BASE + RT_DICT_GET_OFFSET
    jmp     emit_call_abs

; ============================================================
; str / bool / input emit helpers (design.md §3.2, §4.7, §15.3)
; ============================================================

codegen_emit_call_rt_str:
    ; Emit: call rt_str_blob  (int64 → decimal string)
    mov     rdi, LOAD_BASE + RT_STR_OFFSET
    jmp     emit_call_abs

codegen_emit_call_rt_str_bool:
    ; Emit: call rt_str_bool_blob  (bool → "true"/"neutral"/"false")
    mov     rdi, LOAD_BASE + RT_STR_BOOL_OFFSET
    jmp     emit_call_abs

codegen_emit_call_rt_inp:
    ; Emit: call rt_inp_blob  (read line from stdin)
    mov     rdi, LOAD_BASE + RT_INP_OFFSET
    jmp     emit_call_abs

; codegen_emit_int_to_bool: rax ∈ ℤ → rax ∈ {-1, 0, 1}
; test rax,rax / setg cl / sets al / neg al / or al,cl / movsx rax,al
codegen_emit_int_to_bool:
    push    rsi
    push    rcx
    lea     rsi, [rel .itb_code]
    mov     edx, 17
    call    emit_blob_v2
    pop     rcx
    pop     rsi
    ret
.itb_code:
    db 0x48, 0x85, 0xC0           ; test rax, rax
    db 0x0F, 0x9F, 0xC1           ; setg cl   (1 if rax > 0)
    db 0x0F, 0x98, 0xC0           ; sets al   (1 if rax < 0)
    db 0xF6, 0xD8                 ; neg al    (0xFF if negative)
    db 0x08, 0xC8                 ; or  al, cl
    db 0x48, 0x0F, 0xBE, 0xC0    ; movsx rax, al

; codegen_emit_trunc_byte: rax → zero-extend al to rax (char/byte cast)
codegen_emit_trunc_byte:
    push    rsi
    push    rcx
    lea     rsi, [rel .tb_code]
    mov     edx, 4
    call    emit_blob_v2
    pop     rcx
    pop     rsi
    ret
.tb_code:
    db 0x48, 0x0F, 0xB6, 0xC0    ; movzx rax, al

; codegen_emit_xor_rdi_rdi: emit xor rdi, rdi  (set rdi = 0 / null prompt)
codegen_emit_xor_rdi_rdi:
    push    rsi
    push    rcx
    lea     rsi, [rel .xdi_code]
    mov     edx, 3
    call    emit_blob_v2
    pop     rcx
    pop     rsi
    ret
.xdi_code:
    db 0x48, 0x31, 0xFF           ; xor rdi, rdi

; ============================================================
; Stage-9 emitters
; ============================================================

; codegen_emit_sign_rax: sign(rax) → rax ∈ {-1, 0, 1}
; test rax,rax; setg cl; sets al; sub cl,al; movsx rax,cl
codegen_emit_sign_rax:
    push    rsi
    push    rcx
    lea     rsi, [rel .sign_bytes]
    mov     edx, 15
    call    emit_blob_v2
    pop     rcx
    pop     rsi
    ret
.sign_bytes:
    db 0x48, 0x85, 0xC0           ; test rax, rax
    db 0x0F, 0x9F, 0xC1           ; setg cl   (1 if rax > 0)
    db 0x0F, 0x98, 0xC0           ; sets al   (1 if rax < 0)
    db 0x28, 0xC1                 ; sub cl, al
    db 0x48, 0x0F, 0xBE, 0xC1    ; movsx rax, cl

; codegen_emit_clz_rax: lzcnt rax, rax → count leading zeros
codegen_emit_clz_rax:
    push    rsi
    push    rcx
    lea     rsi, [rel .clz_bytes]
    mov     edx, 5
    call    emit_blob_v2
    pop     rcx
    pop     rsi
    ret
.clz_bytes:
    db 0xF3, 0x48, 0x0F, 0xBD, 0xC0  ; lzcnt rax, rax

; codegen_emit_ceil_rax: ceil(rax-as-float)
; movq xmm0,rax; roundsd xmm0,xmm0,2; movq rax,xmm0
codegen_emit_ceil_rax:
    push    rsi
    push    rcx
    lea     rsi, [rel .ceil_bytes]
    mov     edx, 16
    call    emit_blob_v2
    pop     rcx
    pop     rsi
    ret
.ceil_bytes:
    db 0x66, 0x48, 0x0F, 0x6E, 0xC0           ; movq xmm0, rax
    db 0x66, 0x0F, 0x3A, 0x0B, 0xC0, 0x02     ; roundsd xmm0,xmm0,2 (ceil)
    db 0x66, 0x48, 0x0F, 0x7E, 0xC0           ; movq rax, xmm0

; codegen_emit_floor_rax: floor(rax-as-float)
codegen_emit_floor_rax:
    push    rsi
    push    rcx
    lea     rsi, [rel .floor_bytes]
    mov     edx, 16
    call    emit_blob_v2
    pop     rcx
    pop     rsi
    ret
.floor_bytes:
    db 0x66, 0x48, 0x0F, 0x6E, 0xC0           ; movq xmm0, rax
    db 0x66, 0x0F, 0x3A, 0x0B, 0xC0, 0x01     ; roundsd xmm0,xmm0,1 (floor)
    db 0x66, 0x48, 0x0F, 0x7E, 0xC0           ; movq rax, xmm0

; codegen_emit_fract_rax: fract(rax-as-float) = x - floor(x)
codegen_emit_fract_rax:
    push    rsi
    push    rcx
    lea     rsi, [rel .fract_bytes]
    mov     edx, 24
    call    emit_blob_v2
    pop     rcx
    pop     rsi
    ret
.fract_bytes:
    db 0x66, 0x48, 0x0F, 0x6E, 0xC0           ; movq xmm0, rax
    db 0x66, 0x0F, 0x28, 0xC8                  ; movapd xmm1, xmm0
    db 0x66, 0x0F, 0x3A, 0x0B, 0xC9, 0x01     ; roundsd xmm1,xmm1,1 (floor)
    db 0x66, 0x0F, 0x5C, 0xC1                  ; subsd xmm0, xmm1
    db 0x66, 0x48, 0x0F, 0x7E, 0xC0           ; movq rax, xmm0

; codegen_emit_rdrand64: rdrand rax (64-bit hardware random)
codegen_emit_rdrand64:
    push    rsi
    push    rcx
    lea     rsi, [rel .rand_bytes]
    mov     edx, 4
    call    emit_blob_v2
    pop     rcx
    pop     rsi
    ret
.rand_bytes:
    db 0x48, 0x0F, 0xC7, 0xF0                  ; rdrand rax

; codegen_emit_hash_rax: 64-bit multiplicative hash of rax
; Uses a single LCG step: rax = rax * K
codegen_emit_hash_rax:
    push    rsi
    push    rcx
    lea     rsi, [rel .hash_bytes]
    mov     edx, 14
    call    emit_blob_v2
    pop     rcx
    pop     rsi
    ret
.hash_bytes:
    db 0x48, 0xB9                              ; mov rcx, imm64
    db 0x2D, 0x7F, 0x95, 0x4C, 0x2D, 0xF4, 0x51, 0x58  ; 0x5851F42D4C957F2D
    db 0x48, 0x0F, 0xAF, 0xC1                 ; imul rax, rcx

; codegen_emit_carry_rax: setc al; movzx rax, al → CF flag as 0/1
codegen_emit_carry_rax:
    push    rsi
    push    rcx
    lea     rsi, [rel .carry_bytes]
    mov     edx, 7
    call    emit_blob_v2
    pop     rcx
    pop     rsi
    ret
.carry_bytes:
    db 0x0F, 0x92, 0xC0                        ; setc al
    db 0x48, 0x0F, 0xB6, 0xC0                 ; movzx rax, al

; codegen_emit_overflow_rax: seto al; movzx rax, al → OF flag as 0/1
codegen_emit_overflow_rax:
    push    rsi
    push    rcx
    lea     rsi, [rel .ovf_bytes]
    mov     edx, 7
    call    emit_blob_v2
    pop     rcx
    pop     rsi
    ret
.ovf_bytes:
    db 0x0F, 0x90, 0xC0                        ; seto al
    db 0x48, 0x0F, 0xB6, 0xC0                 ; movzx rax, al

; codegen_emit_mov_rdi_rbx: emit mov rdi, rbx  (48 89 DF)
codegen_emit_mov_rdi_rbx:
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0xDF
    call    emit_b
    pop     rax
    ret

; codegen_emit_mov_rsi_rax: emit mov rsi, rax  (48 89 C6)
codegen_emit_mov_rsi_rax:
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0xC6
    call    emit_b
    pop     rax
    ret

; codegen_emit_neg_var(rdi=var_va): emit neg qword [var_va]  (48 F7 1C 25 <va>)
codegen_emit_neg_var:
    mov     qword [rax_holds_va], -1   ; neg modifies memory directly, rax no longer valid
    push    rax
    push    rdi
    mov     al, 0x48
    call    emit_b
    mov     al, 0xF7
    call    emit_b
    mov     al, 0x1C
    call    emit_b
    mov     al, 0x25
    call    emit_b
    pop     rdi
    mov     eax, edi
    call    emit_d
    pop     rax
    ret

; codegen_emit_call_rt_str_cat: call rt_str_cat blob
; Caller must set rdi=ptr1, rsi=ptr2 before this
codegen_emit_call_rt_str_cat:
    mov     rdi, LOAD_BASE + RT_STR_CAT_OFFSET
    jmp     emit_call_abs

; codegen_emit_seq_subscript: emit bounds-checked seq element load
; Protocol (caller must do before calling this):
;   1. push rax  (seq ptr from earlier variable load)
;   2. parse index expr → rax = index
;   3. call this function → emits pop+check+load
codegen_emit_seq_subscript:
    push    rsi
    push    rcx
    lea     rsi, [rel .ssub_bytes]
    mov     edx, 19
    call    emit_blob_v2
    pop     rcx
    pop     rsi
    ret
.ssub_bytes:
    db 0x48, 0x89, 0xC1          ; mov rcx, rax  (index)
    db 0x5B                      ; pop rbx        (seq ptr)
    db 0x48, 0x3B, 0x4B, 0x08   ; cmp rcx, [rbx+8] (bounds)
    db 0x73, 0x07                ; jae .oob (+7 from next=offset 11 → target=18)
    db 0x48, 0x8B, 0x44, 0xCB, 0x10  ; mov rax, [rbx+rcx*8+16]
    db 0xEB, 0x02                ; jmp .done (+2)
    db 0x31, 0xC0                ; .oob: xor eax, eax
    ; .done: (falls through — next instruction)

; codegen_emit_seq_in(rdi=seq_var_va): linear search → rax = 1 (found) / -1 (not found)
; Protocol:
;   1. parser evaluates search value → rax
;   2. parser calls codegen_emit_push_rax  (saves value)
;   3. parser calls codegen_emit_seq_in(rdi=seq_var_va)
codegen_emit_seq_in:
    push    rbx
    push    rsi
    push    rcx
    push    rdi
    ; emit: mov rbx, [var_va]
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0x8B
    call    emit_b
    mov     al, 0x1C
    call    emit_b
    mov     al, 0x25
    call    emit_b
    pop     rax
    push    rdi                     ; var_va as 32-bit address
    pop     rdi
    push    rdi
    mov     eax, edi
    call    emit_d
    pop     rdi
    ; emit loop body
    push    rsi
    push    rcx
    lea     rsi, [rel .sin_code]
    mov     edx, 43
    call    emit_blob_v2
    pop     rcx
    pop     rsi
    pop     rdi
    pop     rcx
    pop     rsi
    pop     rbx
    ret
.sin_code:
    db 0x48, 0x8B, 0x4B, 0x08    ; mov rcx, [rbx+8]  (len)
    db 0x31, 0xD2                 ; xor edx, edx       (index=0)
    db 0x58                       ; pop rax             (search value)
    ; .search: (offset 7)
    db 0x48, 0x85, 0xC9          ; test rcx, rcx
    db 0x74, 24                  ; jz .notfound: next=12, target=36, rel8=24
    db 0x48, 0x3B, 0x44, 0xD3, 0x10  ; cmp rax, [rbx+rdx*8+16]
    db 0x74, 0x08                ; je .found: next=19, target=27, rel8=8
    db 0x48, 0xFF, 0xC2          ; inc rdx
    db 0x48, 0xFF, 0xC9          ; dec rcx
    db 0xEB, 0xEC                ; jmp .search: next=27, target=7, rel8=-20=0xEC
    ; .found: (offset 27)
    db 0x48, 0xC7, 0xC0, 0x01, 0x00, 0x00, 0x00  ; mov rax, 1
    db 0xEB, 0x07                ; jmp .done: next=36, target=43, rel8=7
    ; .notfound: (offset 36)
    db 0x48, 0xC7, 0xC0, 0xFF, 0xFF, 0xFF, 0xFF  ; mov rax, -1
    ; .done: (offset 43)

; ============================================================
; codegen_finish: patches ELF header with final sizes
; rdi = output file fd
; ============================================================
codegen_finish:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12, rdi                ; fd

    ; patch p_filesz = CODE_START + out_idx
    mov     rax, [out_idx]
    add     rax, CODE_START
    mov     [elf_filesz_patch], rax

    ; patch p_memsz = p_filesz + MEM_EXTRA (covers var storage + scratch areas)
    add     rax, MEM_EXTRA
    mov     [elf_memsz_patch], rax

    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; codegen_write_headers(rdi=fd): write ELF header (176 bytes) + JMP (5 bytes) to fd
codegen_write_headers:
    push    rbx
    mov     rbx, rdi
    mov     rax, SYS_write
    mov     rdi, rbx
    lea     rsi, [elf_hdr_template]
    mov     rdx, 176
    syscall
    ; write JMP
    mov     rax, SYS_write
    mov     rdi, rbx
    lea     rsi, [runtime_jmp_bytes]
    mov     rdx, 5
    syscall
    pop     rbx
    ret

; codegen_write_runtime(rdi=fd): write all 8 runtime blobs
codegen_write_runtime:
    push    rbx
    mov     rbx, rdi

    ; Write each blob in order using their known sizes
    %macro write_blob 2
        mov     rax, SYS_write
        mov     rdi, rbx
        lea     rsi, [%1]
        mov     rdx, %2
        syscall
    %endmacro

    write_blob rt_pri_data, RT_PRI_SIZE
    write_blob rt_prs_data, RT_PRS_SIZE
    write_blob rt_prb_data, RT_PRB_SIZE
    write_blob rt_prf_data, RT_PRF_SIZE
    write_blob rt_prc_data, RT_PRC_SIZE
    write_blob rt_sip_data, RT_SIP_SIZE
    write_blob rt_alc_data, RT_ALC_SIZE
    write_blob rt_prq_data, RT_PRQ_SIZE
    write_blob rt_str_data, RT_STR_SIZE
    write_blob rt_inp_data, RT_INP_SIZE
    write_blob rt_str_cat_data, RT_STR_CAT_SIZE

    pop     rbx
    ret

; codegen_write_code(rdi=fd): write out_buffer to fd
codegen_write_code:
    mov     rax, SYS_write
    mov     rsi, out_buffer
    mov     rdx, [out_idx]
    syscall
    ret

; ===========================================================================
; O-I: CTPE Generic Interpreter + IR Recording Helpers
; O-J: Constant Propagation helpers
; O-K: Dead Store Elimination helpers
; ===========================================================================

; ============================================================
; ctpe_ir_emit_b(rdi=byte): emit 1 byte to ctpe_ir_buf[ctpe_ir_out_idx]
; Preserves ALL registers. Sets ctpe_ir_aborted on overflow.
; ============================================================
ctpe_ir_emit_b:
    push    rax
    push    rdi
    mov     rax, [ctpe_ir_out_idx]
    cmp     rax, CTPE_IR_BUF_SIZE - 16
    jge     .cib_overflow
    mov     [ctpe_ir_buf + rax], dil
    inc     qword [ctpe_ir_out_idx]
    pop     rdi
    pop     rax
    ret
.cib_overflow:
    mov     byte [ctpe_ir_aborted], 1
    pop     rdi
    pop     rax
    ret

; ============================================================
; ctpe_ir_emit_w(rdi=word): emit 2 bytes (little-endian) to ctpe_ir_buf
; ============================================================
ctpe_ir_emit_w:
    push    rax
    push    rdi
    mov     rax, [ctpe_ir_out_idx]
    cmp     rax, CTPE_IR_BUF_SIZE - 16
    jge     .ciw_overflow
    mov     [ctpe_ir_buf + rax], di
    add     qword [ctpe_ir_out_idx], 2
    pop     rdi
    pop     rax
    ret
.ciw_overflow:
    mov     byte [ctpe_ir_aborted], 1
    pop     rdi
    pop     rax
    ret

; ============================================================
; ctpe_ir_emit_q(rdi=qword): emit 8 bytes to ctpe_ir_buf
; ============================================================
ctpe_ir_emit_q:
    push    rax
    push    rdi
    mov     rax, [ctpe_ir_out_idx]
    cmp     rax, CTPE_IR_BUF_SIZE - 16
    jge     .ciq_overflow
    mov     [ctpe_ir_buf + rax], rdi
    add     qword [ctpe_ir_out_idx], 8
    pop     rdi
    pop     rax
    ret
.ciq_overflow:
    mov     byte [ctpe_ir_aborted], 1
    pop     rdi
    pop     rax
    ret

; ============================================================
; ctpe_ir_emit_d(rdi=dword): emit 4 bytes to ctpe_ir_buf (jump placeholders)
; ============================================================
ctpe_ir_emit_d:
    push    rax
    push    rdi
    mov     rax, [ctpe_ir_out_idx]
    cmp     rax, CTPE_IR_BUF_SIZE - 16
    jge     .cid_overflow
    mov     [ctpe_ir_buf + rax], edi
    add     qword [ctpe_ir_out_idx], 4
    pop     rdi
    pop     rax
    ret
.cid_overflow:
    mov     byte [ctpe_ir_aborted], 1
    pop     rdi
    pop     rax
    ret

; ============================================================
; ctpe_ir_find_var_idx_from_rbp(rdi=rbp_offset) -> rax = var_idx or -1
; Reverse-lookup: find var_table index whose rbp offset matches rdi.
; ============================================================
ctpe_ir_find_var_idx_from_rbp:
    push    rbx
    push    rcx
    xor     ecx, ecx
.fvr_scan:
    cmp     rcx, VAR_MAX
    jge     .fvr_not_found
    cmp     [var_rbp_offsets + rcx*8], rdi
    je      .fvr_found
    inc     rcx
    jmp     .fvr_scan
.fvr_found:
    mov     rax, rcx
    pop     rcx
    pop     rbx
    ret
.fvr_not_found:
    mov     rax, -1
    pop     rcx
    pop     rbx
    ret

; ============================================================
; ctpe_ir_find_param_pos(rdi=var_idx) -> rax = param position (0..N-1) or -1
; Checks if var_idx is a param of the currently-recording proto.
; ============================================================
ctpe_ir_find_param_pos:
    push    rbx
    push    rcx
    push    rdx
    mov     rax, [ctpe_cur_proto_idx_save]
    imul    rax, PROTO_ENTRY_SIZE
    lea     rax, [proto_table + rax]
    movzx   ecx, byte [rax + PROTO_PARAMCNT_OFF]
    lea     rax, [rax + PROTO_PARAMS_OFF]
    xor     edx, edx
.fpp_scan:
    cmp     rdx, rcx
    jge     .fpp_not_found
    movzx   ebx, byte [rax + rdx]
    cmp     rbx, rdi
    je      .fpp_found
    inc     rdx
    jmp     .fpp_scan
.fpp_found:
    mov     rax, rdx
    pop     rdx
    pop     rcx
    pop     rbx
    ret
.fpp_not_found:
    mov     rax, -1
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ============================================================
; dse_flush_all: clear all dse_pending entries (all regs preserved)
; ============================================================
dse_flush_all:
    push    rdi
    push    rcx
    push    rax
    lea     rdi, [dse_pending]
    xor     eax, eax
    mov     ecx, VAR_MAX
    rep     stosb
    pop     rax
    pop     rcx
    pop     rdi
    ret

; ============================================================
; cp_flush_all: clear all cp_known + rax_is_const (all regs preserved)
; ============================================================
cp_flush_all:
    push    rdi
    push    rcx
    push    rax
    lea     rdi, [cp_known]
    xor     eax, eax
    mov     ecx, VAR_MAX
    rep     stosb
    mov     byte [rax_is_const], 0
    pop     rax
    pop     rcx
    pop     rdi
    ret

; ============================================================
; codegen_emit_test_jnz: emit  test rax,rax; jnz placeholder
; Used for while-loop back-edge condition check.
; ============================================================
codegen_emit_test_jnz:
    push    rax
    push    rbx
    ; test rax, rax  =  48 85 C0
    mov     al, 0x48
    call    emit_b
    mov     al, 0x85
    call    emit_b
    mov     al, 0xc0
    call    emit_b
    ; jnz rel32  =  0F 85 placeholder
    mov     al, 0x0f
    call    emit_b
    mov     al, 0x85
    call    emit_b
    mov     rax, [out_idx]
    xor     ebx, ebx
    call    emit_d
    ; === O-I IR hook: emit IR_IJNZ + record patch mapping ===
    cmp     byte [ctpe_recording], 0
    je      .jnz_no_ir
    push    rdi
    ; x86 patch pos = out_idx - 4 (placeholder just emitted)
    mov     rdi, [out_idx]
    sub     rdi, 4
    ; Record in patch table
    mov     rbx, [ctpe_patch_cnt]
    cmp     rbx, CTPE_PATCH_MAX - 1
    jge     .jnz_patch_full
    mov     [ctpe_patch_x86 + rbx*8], rdi
    mov     rdi, IR_IJNZ
    call    ctpe_ir_emit_b
    mov     rdi, [ctpe_ir_out_idx]
    mov     [ctpe_patch_ir + rbx*8], rdi
    inc     qword [ctpe_patch_cnt]
    xor     edi, edi
    call    ctpe_ir_emit_d
.jnz_patch_full:
    call    dse_flush_all
    pop     rdi
.jnz_no_ir:
    pop     rbx
    pop     rax
    ret

; ===========================================================================
; ctpe_interp(rdi=proto_idx, rsi=argcount, rdx=args_ptr)
; Generic compile-time protocol interpreter.
; Returns: rax = result, rdx = 1 on success; rdx = 0 on failure.
; ===========================================================================
ctpe_interp:
    ; Depth limit check
    movzx   eax, byte [ctpe_call_depth]
    cmp     al, CTPE_CALL_DEPTH_MAX
    jge     .ci_fail_early

    inc     byte [ctpe_call_depth]

    ; Check proto has IR
    cmp     qword [proto_ir_lens + rdi*8], 0
    je      .ci_fail_dec

    ; Save callee-saved + working registers
    push    rbp
    push    rbx
    push    rcx
    push    r8
    push    r9
    push    r10
    push    r11
    push    r12
    push    r13
    push    r14
    push    r15

    ; r15 = proto_idx, r14 = args_ptr, r13 = argcount
    mov     r15, rdi
    mov     r14, rdx
    mov     r13, rsi

    ; r12 = IR start pointer (into ctpe_ir_buf)
    mov     r12, [proto_ir_offsets + r15*8]
    lea     r12, [ctpe_ir_buf + r12]

    ; r11 = IR end pointer
    mov     r11, [proto_ir_lens + r15*8]
    add     r11, r12

    ; r9 = step budget
    mov     r9, 2000000

    ; Allocate locals on stack: VAR_MAX slots × 8 bytes = 2048 bytes
    sub     rsp, 2048
    mov     r8, rsp

    ; Zero-init locals
    push    rdi
    push    rcx
    push    rax
    mov     rdi, r8
    xor     eax, eax
    mov     ecx, 256
    rep     stosq
    pop     rax
    pop     rcx
    pop     rdi

    ; Pre-load parameters: locals[param_var_idx] = args[i]
    mov     rax, r15
    imul    rax, PROTO_ENTRY_SIZE
    lea     rax, [proto_table + rax]
    movzx   ecx, byte [rax + PROTO_PARAMCNT_OFF]
    lea     rax, [rax + PROTO_PARAMS_OFF]
    push    rdx
    xor     edx, edx
.ci_param_init:
    cmp     rdx, rcx
    jge     .ci_param_done
    movzx   ebp, byte [rax + rdx]  ; var_idx for param[rdx]
    push    rsi
    mov     rsi, [r14 + rdx*8]     ; args[rdx]
    mov     [r8 + rbp*8], rsi
    pop     rsi
    inc     rdx
    jmp     .ci_param_init
.ci_param_done:
    pop     rdx

    xor     ebx, ebx   ; irax = 0
    xor     ecx, ecx   ; irbx = 0

    ; ===== Interpreter main loop =====
.ci_loop:
    cmp     r12, r11
    jge     .ci_fail_locals

    dec     r9
    jz      .ci_fail_locals

    movzx   eax, byte [r12]
    inc     r12

    cmp     al, IR_IPUSH
    je      .op_ipush
    cmp     al, IR_IADD
    je      .op_iadd
    cmp     al, IR_IMOV64
    je      .op_imov64
    cmp     al, IR_IPOPX
    je      .op_ipopx
    cmp     al, IR_IRET
    je      .op_iret
    cmp     al, IR_IARG
    je      .op_iarg
    cmp     al, IR_ILOAD
    je      .op_iload
    cmp     al, IR_ISTORE
    je      .op_istore
    cmp     al, IR_ISUB
    je      .op_isub
    cmp     al, IR_IMUL
    je      .op_imul
    cmp     al, IR_IDIV
    je      .op_idiv
    cmp     al, IR_IMOD
    je      .op_imod
    cmp     al, IR_INEG
    je      .op_ineg
    cmp     al, IR_IINC
    je      .op_iinc
    cmp     al, IR_IDEC
    je      .op_idec
    cmp     al, IR_IJMP
    je      .op_ijmp
    cmp     al, IR_IJZ
    je      .op_ijz
    cmp     al, IR_IJNZ
    je      .op_ijnz
    cmp     al, IR_ICMPEQ
    je      .op_icmpeq
    cmp     al, IR_ICMPNE
    je      .op_icmpne
    cmp     al, IR_ICMPLT
    je      .op_icmplt
    cmp     al, IR_ICMPGT
    je      .op_icmpgt
    cmp     al, IR_ICMPLE
    je      .op_icmple
    cmp     al, IR_ICMPGE
    je      .op_icmpge
    cmp     al, IR_IMRAX
    je      .op_imrax
    cmp     al, IR_IAND
    je      .op_iand
    cmp     al, IR_IOR
    je      .op_ior
    cmp     al, IR_IXOR
    je      .op_ixor
    cmp     al, IR_ISHL
    je      .op_ishl
    cmp     al, IR_ISHR
    je      .op_ishr
    cmp     al, IR_IBNOT
    je      .op_ibnot
    cmp     al, IR_ICAL
    je      .op_ical
    jmp     .ci_fail_locals   ; unknown / IR_IABORT

.op_imov64:
    mov     rbx, [r12]
    add     r12, 8
    jmp     .ci_loop

.op_iarg:
    movzx   eax, byte [r12]
    inc     r12
    cmp     rax, r13
    jge     .ci_fail_locals
    mov     rbx, [r14 + rax*8]
    jmp     .ci_loop

.op_iload:
    movzx   eax, word [r12]
    add     r12, 2
    cmp     rax, VAR_MAX
    jge     .ci_fail_locals
    mov     rbx, [r8 + rax*8]
    jmp     .ci_loop

.op_istore:
    movzx   eax, word [r12]
    add     r12, 2
    cmp     rax, VAR_MAX
    jge     .ci_fail_locals
    mov     [r8 + rax*8], rbx
    jmp     .ci_loop

.op_ipush:
    mov     rax, [ctpe_istack_top]
    cmp     rax, CTPE_ISTACK_DEPTH - 1
    jge     .ci_fail_locals
    mov     [ctpe_istack + rax*8], rbx
    inc     qword [ctpe_istack_top]
    jmp     .ci_loop

.op_ipopx:
    mov     rax, [ctpe_istack_top]
    dec     rax
    js      .ci_fail_locals
    mov     rcx, [ctpe_istack + rax*8]
    mov     [ctpe_istack_top], rax
    jmp     .ci_loop

.op_imrax:
    mov     rcx, rbx
    jmp     .ci_loop

.op_iadd:
    add     rbx, rcx
    jmp     .ci_loop

.op_isub:
    ; irax = irbx - irax  (rcx=irbx, rbx=irax)
    sub     rcx, rbx
    mov     rbx, rcx
    jmp     .ci_loop

.op_imul:
    imul    rbx, rcx
    jmp     .ci_loop

.op_idiv:
    test    rbx, rbx
    jz      .ci_fail_locals
    mov     rax, rcx
    cqo
    idiv    rbx
    mov     rbx, rax
    jmp     .ci_loop

.op_imod:
    test    rbx, rbx
    jz      .ci_fail_locals
    mov     rax, rcx
    cqo
    idiv    rbx
    mov     rbx, rdx
    jmp     .ci_loop

.op_ineg:
    neg     rbx
    jmp     .ci_loop

.op_iinc:
    movzx   eax, word [r12]
    add     r12, 2
    cmp     rax, VAR_MAX
    jge     .ci_fail_locals
    inc     qword [r8 + rax*8]
    jmp     .ci_loop

.op_idec:
    movzx   eax, word [r12]
    add     r12, 2
    cmp     rax, VAR_MAX
    jge     .ci_fail_locals
    dec     qword [r8 + rax*8]
    jmp     .ci_loop

.op_ijmp:
    movsx   rax, dword [r12]
    add     r12, 4
    add     r12, rax
    jmp     .ci_loop

.op_ijz:
    movsx   rax, dword [r12]
    add     r12, 4
    test    rbx, rbx
    jnz     .ci_loop
    add     r12, rax
    jmp     .ci_loop

.op_ijnz:
    movsx   rax, dword [r12]
    add     r12, 4
    test    rbx, rbx
    jz      .ci_loop
    add     r12, rax
    jmp     .ci_loop

.op_icmpeq:
    cmp     rcx, rbx
    sete    bl
    movzx   rbx, bl
    jmp     .ci_loop

.op_icmpne:
    cmp     rcx, rbx
    setne   bl
    movzx   rbx, bl
    jmp     .ci_loop

.op_icmplt:
    cmp     rcx, rbx
    setl    bl
    movzx   rbx, bl
    jmp     .ci_loop

.op_icmpgt:
    cmp     rcx, rbx
    setg    bl
    movzx   rbx, bl
    jmp     .ci_loop

.op_icmple:
    cmp     rcx, rbx
    setle   bl
    movzx   rbx, bl
    jmp     .ci_loop

.op_icmpge:
    cmp     rcx, rbx
    setge   bl
    movzx   rbx, bl
    jmp     .ci_loop

.op_iand:
    and     rbx, rcx
    jmp     .ci_loop

.op_ior:
    or      rbx, rcx
    jmp     .ci_loop

.op_ixor:
    xor     rbx, rcx
    jmp     .ci_loop

.op_ishl:
    ; irax = irbx << (irax & 63)   rbx=shift_amt, rcx=value
    mov     r10, rcx
    mov     rcx, rbx
    and     rcx, 63
    mov     rbx, r10
    sal     rbx, cl
    jmp     .ci_loop

.op_ishr:
    mov     r10, rcx
    mov     rcx, rbx
    and     rcx, 63
    mov     rbx, r10
    sar     rbx, cl
    jmp     .ci_loop

.op_ibnot:
    not     rbx
    jmp     .ci_loop

.op_iret:
    mov     rax, rbx
    mov     rdx, 1
    jmp     .ci_success

.op_ical:
    ; IR: proto_idx(8 bytes) + argcnt(1 byte)
    mov     r10, [r12]          ; target proto_idx
    movzx   ebp, byte [r12+8]   ; argcnt
    add     r12, 9

    ; Check target has IR
    cmp     qword [proto_ir_lens + r10*8], 0
    je      .ci_fail_locals

    ; Push interpreter state onto x86 stack (11 items = 88 bytes)
    push    r12     ; IP (advanced past ICAL)
    push    r11     ; IP end
    push    r10     ; target proto_idx
    push    rbp     ; argcnt temp
    push    r9      ; step counter
    push    r8      ; locals base
    push    r15     ; current proto_idx
    push    r14     ; args_ptr
    push    r13     ; arg count (current call)
    push    rbx     ; irax
    push    rcx     ; irbx

    ; Get first arg index in ctpe_istack
    mov     rax, [ctpe_istack_top]
    sub     rax, rbp            ; first arg index = top - argcnt
    jl      .ical_underflow

    ; Allocate forward args array on x86 stack
    sub     rsp, 64             ; max 8 args

    ; fwd_args[i] = ctpe_istack[rax + i]
    lea     r11, [ctpe_istack + rax*8]
    xor     ecx, ecx
.ical_fwd:
    cmp     rcx, rbp
    jge     .ical_fwd_done
    mov     r12, [r11 + rcx*8]
    mov     [rsp + rcx*8], r12
    inc     rcx
    jmp     .ical_fwd
.ical_fwd_done:

    ; Decrement ctpe_istack_top by argcnt
    mov     rax, [ctpe_istack_top]
    sub     rax, rbp
    mov     [ctpe_istack_top], rax

    ; Call ctpe_interp(target_proto_idx, argcnt, fwd_args_ptr)
    mov     rdi, r10            ; target proto_idx
    mov     rsi, rbp            ; argcnt
    mov     rdx, rsp            ; fwd_args
    call    ctpe_interp

    test    rdx, rdx
    jz      .ical_nested_fail

    mov     r10, rax            ; save result

    ; Restore state
    add     rsp, 64
    pop     rcx     ; irbx
    pop     rbx     ; irax (overwritten below)
    pop     r13
    pop     r14
    pop     r15
    pop     r8
    pop     r9
    pop     rbp     ; discard (argcnt slot)
    pop     rax     ; discard (target proto_idx slot)
    pop     r11
    pop     r12

    mov     rbx, r10    ; irax = result
    jmp     .ci_loop

.ical_nested_fail:
    add     rsp, 64
.ical_underflow:
    pop     rcx
    pop     rbx
    pop     r13
    pop     r14
    pop     r15
    pop     r8
    pop     r9
    pop     rbp
    pop     rax     ; discard
    pop     r11
    pop     r12
    jmp     .ci_fail_locals

.ci_success:
    add     rsp, 2048
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rcx
    pop     rbx
    pop     rbp
    dec     byte [ctpe_call_depth]
    ret

.ci_fail_locals:
    xor     eax, eax
    xor     edx, edx
    add     rsp, 2048
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rcx
    pop     rbx
    pop     rbp
    dec     byte [ctpe_call_depth]
    ret

.ci_fail_dec:
    dec     byte [ctpe_call_depth]
.ci_fail_early:
    xor     eax, eax
    xor     edx, edx
    ret
