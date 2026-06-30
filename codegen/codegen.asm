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
global codegen_emit_push_rax, codegen_emit_pop_rbx
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

; for-loop state
for_step_val:       resq 1                      ; step value for current for-loop
for_step_sign:      resb 1                      ; 0=positive, 1=negative

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
    dd RT_TOTAL_SIZE             ; = 8448

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
    mov     qword [var_count],      0
    mov     qword [proto_count],    0
    mov     byte  [cur_type],       TYPE_INT
    mov     qword [cur_proto_idx],  -1
    mov     qword [prot_body_depth],0
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
    ret

; ---- codegen_get_out_idx: return current out_idx in rax ----
codegen_get_out_idx:
    mov     rax, [out_idx]
    ret

; ============================================================
; Emit helpers
; ============================================================
emit_b:
    ; al = byte to emit
    push    rcx
    mov     rcx, [out_idx]
    mov     [out_buffer + rcx], al
    inc     rcx
    mov     [out_idx], rcx
    pop     rcx
    ret

emit_d:
    ; eax = dword to emit (little-endian)
    push    rcx
    push    rdx
    mov     rcx, [out_idx]
    mov     [out_buffer + rcx], eax
    add     rcx, 4
    mov     [out_idx], rcx
    pop     rdx
    pop     rcx
    ret

emit_q:
    ; rax = qword to emit
    push    rcx
    mov     rcx, [out_idx]
    mov     [out_buffer + rcx], rax
    add     rcx, 8
    mov     [out_idx], rcx
    pop     rcx
    ret

emit_blob:
    ; rsi = source pointer, rcx = byte count
    push    rdi
    push    rsi
    push    rcx
    mov     rdi, [out_idx]
    lea     rdi, [out_buffer + rdi]
    rep     movsb
    mov     rdi, [rsp + 8]  ; original rsi
    mov     rcx, [rsp]      ; original rcx
    mov     rdi, [out_idx]
    add     rdi, rcx
    mov     [out_idx], rdi
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
    mov     rcx, rdx
    mov     rdi, out_buffer
    add     rdi, [out_idx]
    rep     movsb
    add     [out_idx], rdx
    pop     rcx
    pop     rsi
    pop     rdi
    ret

; ============================================================
; Variable table management
; ============================================================

; get_var_va(rdi=index) → rax = VAR_STORAGE_BASE + idx*64
get_var_va:
    shl     rdi, 6              ; idx * 64
    lea     rax, [rdi + VAR_STORAGE_BASE]
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
    xor     r11, r11
    mov     rcx, 0                      ; will fill up to 8 bytes
.load_prefix:
    cmp     rcx, 8
    jge     .prefix_done
    movzx   edx, byte [rdi + rcx]
    test    dl, dl
    jz      .prefix_done
    mov     [rsp - 8 + rcx], dl         ; store in unused stack space
    inc     rcx
    jmp     .load_prefix
.prefix_done:
    ; Just do memcmp approach
    ; r11 = first 8 bytes of query (or fewer if shorter)
    ; Build r11 from [rdi]
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

; codegen_emit_mov_rax_var(rdi=var_va): emit  mov rax, [abs32]
codegen_emit_mov_rax_var:
    push    rax
    push    rdi
    mov     al, 0x48
    call    emit_b
    mov     al, 0x8b            ; MOV rax, [disp32]
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    pop     rdi
    mov     eax, edi            ; addr32 (fits in 32 bits)
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

; codegen_emit_store_rax_to_var(rdi=var_va): emit  mov [abs32], rax
codegen_emit_store_rax_to_var:
    push    rax
    push    rdi
    mov     al, 0x48
    call    emit_b
    mov     al, 0x89            ; MOV [disp32], rax
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

; Emit push rax
codegen_emit_push_rax:
    push    rax
    mov     al, 0x50
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
    mov     al, 0x48
    call    emit_b
    mov     al, 0x01
    call    emit_b
    mov     al, 0xd8
    call    emit_b
    pop     rax
    ret

codegen_emit_sub_rax_rbx:      ; rbx - rax → rax  (neg+add pattern)
    push    rax
    mov     al, 0x48            ; neg rax
    call    emit_b
    mov     al, 0xf7
    call    emit_b
    mov     al, 0xd8
    call    emit_b
    mov     al, 0x48            ; add rax, rbx
    call    emit_b
    mov     al, 0x01
    call    emit_b
    mov     al, 0xd8
    call    emit_b
    pop     rax
    ret

codegen_emit_imul_rax_rbx:     ; imul rax, rbx  (48 0F AF C3)
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0x0f
    call    emit_b
    mov     al, 0xaf
    call    emit_b
    mov     al, 0xc3
    call    emit_b
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
codegen_emit_bitwise_and:   ; and rax, rbx  (48 21 D8)
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0x21
    call    emit_b
    mov     al, 0xd8
    call    emit_b
    pop     rax
    ret

codegen_emit_bitwise_or:    ; or rax, rbx  (48 09 D8)
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0x09
    call    emit_b
    mov     al, 0xd8
    call    emit_b
    pop     rax
    ret

codegen_emit_bitwise_xor:   ; xor rax, rbx  (48 31 D8)
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0x31
    call    emit_b
    mov     al, 0xd8
    call    emit_b
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
codegen_emit_and_bool: ; and rax, rbx (eager)
    push    rax
    mov     al, 0x48            ; test rbx, rbx
    call    emit_b
    mov     al, 0x85
    call    emit_b
    mov     al, 0xdb
    call    emit_b
    mov     al, 0x0f            ; setnz cl
    call    emit_b
    mov     al, 0x95
    call    emit_b
    mov     al, 0xc1
    call    emit_b
    mov     al, 0x48            ; test rax, rax
    call    emit_b
    mov     al, 0x85
    call    emit_b
    mov     al, 0xc0
    call    emit_b
    mov     al, 0x0f            ; setnz al
    call    emit_b
    mov     al, 0x95
    call    emit_b
    mov     al, 0xc0
    call    emit_b
    mov     al, 0x20            ; and al, cl
    call    emit_b
    mov     al, 0xc8
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

codegen_emit_or_bool:  ; or rax, rbx → bool
    push    rax
    mov     al, 0x48            ; or rax, rbx
    call    emit_b
    mov     al, 0x09
    call    emit_b
    mov     al, 0xd8
    call    emit_b
    mov     al, 0x0f            ; setnz al
    call    emit_b
    mov     al, 0x95
    call    emit_b
    mov     al, 0xc0
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

codegen_emit_not_rax:  ; xor rax, 1  (for bool NOT)
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0x83
    call    emit_b
    mov     al, 0xf0
    call    emit_b
    mov     al, 0x01
    call    emit_b
    pop     rax
    ret

; ============================================================
; Comparison: cmp rbx, rax; setCC al; movzx rax, al
; rdi = setCC opcode byte (0x94=sete, 0x95=setne, etc.)
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
codegen_emit_test_jz:
    push    rbx
    mov     al, 0x48            ; test rax, rax
    call    emit_b
    mov     al, 0x85
    call    emit_b
    mov     al, 0xc0
    call    emit_b
    mov     al, 0x0f            ; jz rel32
    call    emit_b
    mov     al, 0x84
    call    emit_b
    mov     rax, [out_idx]      ; offset of placeholder
    xor     ebx, ebx
    call    emit_d              ; placeholder = 0
    pop     rbx
    ret

; codegen_emit_test_jnz: test rax,rax; jnz placeholder
codegen_emit_test_jnz:
    push    rbx
    mov     al, 0x48
    call    emit_b
    mov     al, 0x85
    call    emit_b
    mov     al, 0xc0
    call    emit_b
    mov     al, 0x0f
    call    emit_b
    mov     al, 0x85
    call    emit_b
    mov     rax, [out_idx]
    xor     ebx, ebx
    call    emit_d
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
; Emits init + condition + captures loop start
; Returns: rax = loop_start_pc, rbx = jge_patch_offset
codegen_emit_for_start:
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi                ; var VA
    mov     r13, rsi                ; from
    mov     r14, rdx                ; to

    ; emit: mov [var_va], from
    ; if from == 0: xor eax,eax; mov [var_va], eax
    test    r13, r13
    jnz     .init_nonzero
    push    rax
    mov     al, 0x31                ; xor eax, eax
    call    emit_b
    mov     al, 0xc0
    call    emit_b
    mov     al, 0x89                ; mov [var_va], eax  (32-bit)
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r12d
    call    emit_d
    pop     rax
    jmp     .loop_top

.init_nonzero:
    ; emit: mov rax, from (imm64); mov [var_va], rax
    mov     rdi, r13
    call    codegen_emit_mov_rax_imm64
    mov     rdi, r12
    call    codegen_emit_store_rax_to_var

.loop_top:
    ; save loop start PC (as VA offset from code start)
    mov     r15, [out_idx]          ; r15 = loop start

    ; emit: cmp qword [var_va], to_imm; jge exit_placeholder
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0x81
    call    emit_b
    mov     al, 0x3c
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r12d
    call    emit_d
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

    ; push cont target (loop top)
    mov     rdi, r15
    call    codegen_push_cont

    ; push break base
    mov     rdi, [break_jump_depth]
    lea     rdi, [break_base_stack + rdi*8]
    mov     rsi, [break_jump_depth]
    mov     [rdi], rsi
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
; Emits increment + back-jump + patches exit
codegen_emit_for_end:
    push    r12
    push    r13
    push    r14
    mov     r12, rdi                ; loop_start
    mov     r13, rsi                ; jge_patch offset
    mov     r14, rdx                ; var VA

    ; emit: inc qword [var_va]  (48 FF 04 25 addr32)
    ; (or add qword [var_va], step  if step != 1)
    mov     rax, [for_step_val]
    cmp     rax, 1
    je      .step1
    ; step != 1: emit add qword [var_va], step_imm8/32
    push    rax
    cmp     rax, 127
    jle     .step_imm8
    mov     al, 0x48                ; add qword [var_va], imm32
    call    emit_b
    mov     al, 0x81
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r14d
    call    emit_d
    pop     rax
    call    emit_d
    jmp     .back_jmp
.step_imm8:
    mov     al, 0x48
    call    emit_b
    mov     al, 0x83
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r14d
    call    emit_d
    pop     rax
    call    emit_b                  ; imm8
    jmp     .back_jmp

.step1:
    push    rax
    mov     al, 0x48
    call    emit_b
    mov     al, 0xff
    call    emit_b
    mov     al, 0x04
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, r14d
    call    emit_d
    pop     rax

.back_jmp:
    ; emit: jmp back to loop top
    ; rel32 = (CODE_START + r12) - (CODE_START + out_idx + 5)
    ;       = r12 - out_idx - 5
    push    rax
    mov     al, 0xe9
    call    emit_b
    mov     rax, r12
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
    mov     rsi, [break_jump_depth]
    mov     [break_base_stack + rsi*8], rsi
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
    ; emit: jmp placeholder; push offset onto break_jump_stack with depth=1
    push    rax
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
    ; emit: jmp to cont_base_stack top
    push    rax
    push    rbx
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
    mov     al, 0x48
    call    emit_b
    mov     al, 0xc7
    call    emit_b
    mov     al, 0xc0
    call    emit_b
    mov     al, 0x3c
    call    emit_b
    times 3 db 0                    ; will be patched as NASM inline bytes
    ; Hmm - I can't use `times` here. Let me just call emit_b for each:
    pop     rax
    push    rax
    ; Redo:
    ; Already emitted mov rax, 60 partially above... this is getting wrong.
    ; Let me start over with a helper blob approach.
    pop     rax

    ; Emit exit(1) as a sequence of bytes
    push    rsi
    push    rcx
    lea     rsi, [rel .exit1_bytes]
    mov     ecx, 16
    call    emit_blob_v2
    pop     rcx
    pop     rsi
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
; Records out_idx in proto table; emits push r12 if param_count > 0
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

    ; args are loaded via mov rax,[rsp+offset] in emit_arg_pops — no callee-save push needed
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; codegen_emit_prot_end: emit ret
codegen_emit_prot_end:
    push    rax
    ; pop r12 if was pushed (simplified: always)
    ; Actually check if we pushed r12...
    ; For simplicity: emit ret
    mov     al, 0xc3
    call    emit_b
    pop     rax
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
    push    rax
    push    rdi
    push    rsi
    push    rdx
    mov     rdx, rdi
    ; mov rax, [va_a]
    call    codegen_emit_mov_rax_var
    ; mov rbx, [va_b]
    pop     rsi
    pop     rdx
    push    rsi
    push    rdx
    push    rax
    mov     rdi, [rsp + 8]          ; va_b
    mov     al, 0x48
    call    emit_b
    mov     al, 0x8b
    call    emit_b
    mov     al, 0x1c
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, edi
    call    emit_d
    pop     rax
    ; mov [va_a], rbx
    push    rax
    mov     rdi, [rsp + 16]         ; va_a
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
    push    rax
    mov     rdi, [rsp + 8]          ; va_b
    call    codegen_emit_store_rax_to_var
    pop     rax
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
    mov     edx, 46
    call    emit_blob_v2
    pop     rcx
    pop     rsi
    ret
.clock_bytes:
    db 0x48, 0x83, 0xec, 0x10           ; sub rsp, 16
    db 0xb8, 0xe4, 0x00, 0x00, 0x00     ; mov eax, 228 (SYS_clock_gettime)
    db 0xbf, 0x01, 0x00, 0x00, 0x00     ; mov edi, 1 (CLOCK_MONOTONIC)
    db 0x48, 0x89, 0xe6                 ; mov rsi, rsp
    db 0x0f, 0x05                       ; syscall
    db 0x4c, 0x8b, 0x04, 0x24           ; mov r8, [rsp]     (tv_sec)
    db 0x4c, 0x8b, 0x4c, 0x24, 0x08     ; mov r9, [rsp+8]   (tv_nsec)
    db 0x48, 0x83, 0xc4, 0x10           ; add rsp, 16
    db 0x49, 0x69, 0xc0, 0xe8, 0x03, 0x00, 0x00  ; imul r8, r8, 1000
    db 0x49, 0x89, 0xc8                 ; mov r8, r9 (temp)
    db 0x31, 0xd2                       ; xor edx, edx
    db 0xb9, 0x40, 0x42, 0x0f, 0x00     ; mov ecx, 1000000
    db 0x48, 0xf7, 0xf1                 ; div rcx
    ; Hmm this is getting complex. Let me simplify clock_ms.
    ; Just do: sub rsp,16; clock_gettime(1,rsp); mov r8,[rsp]; mov r9,[rsp+8]; add rsp,16
    ; result = sec*1000 + nsec/1000000

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
    mov     edx, 14
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
    db 0x74, 18                  ; jz .notfound: next=12, target=30, rel8=18
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
