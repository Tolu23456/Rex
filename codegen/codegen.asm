; ============================================================
; codegen/codegen.asm — Rex code generator
; Manages output buffer, variable/protocol tables, ELF header.
; ============================================================
bits 64
%include "rex_defs.inc"

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
reg_cache_var:      resq 1                      ; var_index of cached variable (-1 = none)
reg_cache_reg:      resb 1                      ; register code: 1=rcx, 2=rdx, 3=rsi, 4=rdi
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
leave_patch_list:   resq 16                     ; up to 16 epilogue patch positions
leave_patch_cnt:    resq 1                      ; number of epilogue patches

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

    ; Pattern F matched: rollback 6, emit mov rbx,rax + 3 NOPs
    sub     qword [out_idx], 6
    sub     qword [emit_tail_len], 6
    mov     al, 0x48
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0xc3
    call    emit_b
    mov     al, 0x90
    call    emit_b
    call    emit_b
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

    ; rollback 14 bytes, emit: mov rbx,rax + mov rax,[abs32] + 3 NOPs
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
    mov     al, 0x90
    call    emit_b
    call    emit_b
    call    emit_b

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
; Emit helpers
; ============================================================
emit_b:
    ; al = byte to emit
    push    rcx
    push    rdi
    mov     rcx, [out_idx]
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

emit_d:
    ; eax = dword to emit (little-endian)
    push    rcx
    push    rdx
    push    rdi
    push    rax
    mov     rcx, [out_idx]
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

emit_q:
    ; rax = qword to emit
    push    rcx
    push    rdx
    push    rdi
    push    rax
    mov     rcx, [out_idx]
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
    push    rax
    push    rdi
    ; Check register cache: if rdi == reg_cache_var, emit mov rax, r15 (3 bytes)
    cmp     rdi, [reg_cache_var]
    jne     .not_cached
    pop     rdi
    pop     rax
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
    mov     eax, edi
    call    emit_d
    pop     rax
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
    push    rax
    push    rdi
    push    rcx
    push    r12

    ; Check register cache: if rdi == reg_cache_var, emit mov r15, rax (3 bytes)
    cmp     rdi, [reg_cache_var]
    jne     .not_cached_store
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
    ; Roll back 11 bytes (load + 3-byte op), emit OP [abs32], r15
    ; Encoding: 4C [opcode] 3C 25 addr32
    ; REX=4C(W+R), ModRM=3C(mod=00 reg=7=r15%8 rm=4=SIB), SIB=25(idx=none base=disp32)
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
    pop     r12
    pop     rcx
    pop     rdi
    pop     rax
    ret

.abs_store_normal:
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

    ; return loop_start in rax, jge_patch in rbx
    mov     rax, r15
    mov     rbx, r13

    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret

; codegen_emit_for_end(rdi=loop_start, rsi=jge_patch, rdx=var_va)
; Emits back-jump to increment point + patches exit
codegen_emit_for_end:
    push    r12
    push    r13
    push    r14
    mov     r12, rdi                ; loop_start (condition check)
    mov     r13, rsi                ; jge_patch offset
    mov     r14, rdx                ; var VA

    ; back-jump to increment point (not condition check)
    push    rax
    mov     al, 0xe9
    call    emit_b
    mov     rax, [for_cont_addr]   ; increment point
    sub     rax, [out_idx]
    sub     rax, 4
    call    emit_d
    pop     rax

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
    mov     r12, rdi
    mov     r13, rsi
    mov     r14, rdx                ; to_var_va

    ; init counter
    test    r13, r13
    jnz     .di_nz
    push    rax
    mov     al, 0x31
    call    emit_b
    mov     al, 0xc0
    call    emit_b
    mov     al, 0x89
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r12d
    call    emit_d
    pop     rax
    jmp     .di_top
.di_nz:
    mov     rdi, r13
    call    codegen_emit_mov_rax_imm64
    mov     rdi, r12
    call    codegen_emit_store_rax_to_var

.di_top:
    ; O-E: align loop condition to 16-byte boundary
    call    codegen_align_loop_top

    mov     r15, [out_idx]

    ; cmp [var_va], [to_var_va]: load both, compare
    ; emit: mov rax, [var_va]; cmp rax, [to_var_va]; jge exit
    push    rax
    mov     al, 0x48                ; mov rax, [var_va]
    call    emit_b
    mov     al, 0x8b
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r12d
    call    emit_d
    mov     al, 0x48                ; cmp rax, [to_var_va]
    call    emit_b
    mov     al, 0x3b
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r14d
    call    emit_d
    mov     al, 0x0f                ; jge rel32
    call    emit_b
    mov     al, 0x8d
    call    emit_b
    mov     rax, [out_idx]
    mov     r13, rax
    xor     eax, eax
    call    emit_d
    pop     rax

    mov     rdi, r15
    call    codegen_push_cont
    mov     rdi, [break_base_depth]
    mov     rsi, [break_jump_depth]
    mov     [break_base_stack + rdi*8], rsi
    inc     qword [break_base_depth]
    inc     qword [loop_depth]

    mov     rax, r15
    mov     rbx, r13
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
    mov     r12, rdi
    mov     r13, rsi
    ; Flush register cache before back-jump
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
    ; emit: jmp back to loop_start
    push    rax
    mov     al, 0xe9
    call    emit_b
    mov     rax, r12
    sub     rax, [out_idx]
    sub     rax, 4
    call    emit_d
    pop     rax
    ; patch exit jz
    mov     rdi, r13
    call    codegen_patch_jump
    call    codegen_patch_breaks
    call    codegen_pop_cont
    dec     qword [loop_depth]
    pop     r13
    pop     r12
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
    ; mov rax, 60
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
    mov     al, 0x00
    call    emit_b
    mov     al, 0x00
    call    emit_b
    ; xor rdi, rdi
    mov     al, 0x48
    call    emit_b
    mov     al, 0x31
    call    emit_b
    mov     al, 0xff
    call    emit_b
    ; syscall
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
    cmp     rbx, 15
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
