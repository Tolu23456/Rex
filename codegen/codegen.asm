; Rex Code Generator Implementation
; written in x86-64 NASM assembly

%include "include/rex_defs.inc"
%include "include/rex_ir.inc"

section .data
    elf_header:
        db 0x7F, 'E', 'L', 'F'      ; e_ident
        db 2, 1, 1, 0               ; class (64-bit), data (LSB), version, OSABI
        times 8 db 0                ; pad
        dw 2                        ; e_type (ET_EXEC)
        dw 62                       ; e_machine (AMD64)
        dd 1                        ; e_version
        dq LOAD_BASE + CODE_START   ; e_entry (start of user code)
        dq 64                       ; e_phoff (program header offset)
        dq 0                        ; e_shoff (no section headers)
        dd 0                        ; e_flags
        dw 64                       ; e_ehsize (ELF header size)
        dw 56                       ; e_phentsize (program header size)
        dw 1                        ; e_phnum (1 program header)
        dw 0                        ; e_shentsize
        dw 0                        ; e_shnum
        dw 0                        ; e_shstrndx
    elf_header_len equ $ - elf_header

    program_header:
        dd 1                        ; p_type (PT_LOAD)
        dd 7                        ; p_flags (PF_R | PF_W | PF_X)
        dq 0                        ; p_offset
        dq LOAD_BASE                ; p_vaddr
        dq LOAD_BASE                ; p_paddr
        dq 0                        ; p_filesz (patched at compile finish)
        dq 0                        ; p_memsz (patched at compile finish)
        dq 0x1000                   ; p_align
    program_header_len equ $ - program_header

    ; Lookup tables for IR_CMP_BOOL setcc selection (indexed by COND_* 0-5)
    cmp_int_setcc: db 0x94,0x95,0x9C,0x9E,0x9F,0x9D  ; sete,setne,setl,setle,setg,setge
    cmp_flt_setcc: db 0x94,0x95,0x92,0x96,0x97,0x93  ; sete,setne,setb,setbe,seta,setae
    ; roundsd mode table indexed by (opcode - IR_CEIL): ceil=2,floor=1,round=0,trunc=3
    roundsd_mode:  db 2,1,0,3
    ; 1.0 as IEEE 754 double (for float.recip())
    float_one_bits: dq 0x3FF0000000000000

    ; Embed the runtime binaries directly
    rt_pri_bin:  incbin "runtime/rt_pri.bin"
    rt_prs_bin:  incbin "runtime/rt_prs.bin"
    rt_prb_bin:  incbin "runtime/rt_prb.bin"
    rt_prf_bin:  incbin "runtime/rt_prf.bin"
    rt_prc_bin:  incbin "runtime/rt_prc.bin"
    rt_prc_bin_end:
    rt_prq_bin:  incbin "runtime/rt_prq.bin"

section .bss
    global out_buffer
    global out_idx
    out_buffer  resb OUT_BUF_MAX
    out_idx     resd 1
    dst_spilled_vreg resd 1


section .text
    global codegen_init
    global codegen_emit_all
    global codegen_finish

    extern ir_count
    extern ir_buffer
    extern vreg_phys
    extern vreg_offset
    extern stack_frame_size

; Emit 1 byte
emit_b:
    mov ecx, [out_idx]
    cmp ecx, OUT_BUF_MAX
    jae .overflow
    mov [out_buffer + rcx], dil
    inc dword [out_idx]
    ret
.overflow:
    ; Exit with overflow
    mov rax, 60
    mov rdi, 2
    syscall

; Emit 4 bytes
emit_d:
    mov ecx, [out_idx]
    cmp ecx, OUT_BUF_MAX - 4
    jae .overflow
    mov [out_buffer + rcx], edi
    add dword [out_idx], 4
    ret
.overflow:
    mov rax, 60
    mov rdi, 2
    syscall

; Emit 8 bytes
emit_q:
    mov ecx, [out_idx]
    cmp ecx, OUT_BUF_MAX - 8
    jae .overflow
    mov [out_buffer + rcx], rdi
    add dword [out_idx], 8
    ret
.overflow:
    mov rax, 60
    mov rdi, 2
    syscall

; Emit memory block
emit_block:
    push rsi
    push rdi
    push rcx
    mov eax, ecx            ; save length before rep movsb destroys rcx
    mov edi, [out_idx]      ; read 32-bit out_idx, zero-extend to rdi
    ; Bounds check: out_idx + length must not exceed buffer
    add edi, eax
    cmp edi, OUT_BUF_MAX
    jae .overflow
    sub edi, eax            ; restore original out_idx
    lea rdi, [out_buffer + rdi]
    ; rsi already points to source
    ; rcx contains length
    rep movsb               ; rcx reaches 0 after this
    add [out_idx], eax      ; advance out_idx by original length
    pop rcx
    pop rdi
    pop rsi
    ret
.overflow:
    mov rax, 60
    mov rdi, 2
    syscall

; Write ELF Headers and Runtime Blobs
codegen_init:
    mov dword [out_idx], 0

    ; 1. Write ELF Header
    lea rsi, [elf_header]
    mov rcx, elf_header_len
    call emit_block

    ; 2. Write Program Header
    lea rsi, [program_header]
    mov rcx, program_header_len
    call emit_block

    ; 3. Write JMP over runtime: E9 <RT_TOTAL_SIZE:imm32>
    ; Opcode E9
    mov dil, 0xE9
    call emit_b
    ; Offset is 8448 bytes
    mov edi, 8448
    call emit_d

    ; 4. Write rt_pri_bin (512 bytes)
    lea rsi, [rt_pri_bin]
    mov rcx, 512
    call emit_block

    ; 5. Write rt_prs_bin (512 bytes)
    lea rsi, [rt_prs_bin]
    mov rcx, 512
    call emit_block

    ; 6. Write rt_prb_bin (256 bytes)
    lea rsi, [rt_prb_bin]
    mov rcx, 256
    call emit_block

    ; 7. Write rt_prf_bin (512 bytes)
    lea rsi, [rt_prf_bin]
    mov rcx, 512
    call emit_block

    ; 8. Write rt_prc.bin (print char) then pad to 512 bytes
    lea rsi, [rt_prc_bin]
    mov ecx, rt_prc_bin_end - rt_prc_bin
    call emit_block
    xor dil, dil
    mov ecx, 512 - (rt_prc_bin_end - rt_prc_bin)
.zero_prc:
    push rcx
    call emit_b
    pop rcx
    loop .zero_prc

    ; 9. Write rt_sip slot (1024 bytes of zeroes)
    xor dil, dil
    mov ecx, 1024
.zero_sip:
    push rcx
    call emit_b
    pop rcx
    loop .zero_sip

    ; 10. Write rt_alc slot (4096 bytes of zeroes)
    xor dil, dil
    mov ecx, 4096
.zero_alc:
    push rcx
    call emit_b
    pop rcx
    loop .zero_alc

    ; 11. Write rt_prq_bin (1024 bytes)
    lea rsi, [rt_prq_bin]
    mov rcx, 1024
    call emit_block

    ; Verify we are exactly at CODE_START (8573)
    ; 120 (headers) + 5 (jmp) + 8448 (runtime) = 8573
    ret

; Emit function prologue
emit_prologue:
    ; push rbp -> 55
    mov dil, 0x55
    call emit_b
    
    ; mov rbp, rsp -> 48 89 E5
    mov dil, 0x48
    call emit_b
    mov dil, 0x89
    call emit_b
    mov dil, 0xE5
    call emit_b
    
    ; sub rsp, aligned_stack_frame
    mov eax, [stack_frame_size]
    add eax, 15
    and eax, -16
    test eax, eax
    jz .done
    
    ; sub rsp, imm32 -> 48 81 EC <imm32>
    mov dil, 0x48
    call emit_b
    mov dil, 0x81
    call emit_b
    mov dil, 0xEC
    call emit_b
    mov edi, eax
    call emit_d
.done:
    ret

; Emit function epilogue and exit
emit_epilogue_and_exit:
    ; mov rsp, rbp -> 48 89 EC
    mov dil, 0x48
    call emit_b
    mov dil, 0x89
    call emit_b
    mov dil, 0xEC
    call emit_b
    
    ; pop rbp -> 5D
    mov dil, 0x5D
    call emit_b
    
    ; sys_exit(0):
    ; mov rax, 60 -> 48 C7 C0 3C 00 00 00
    ; xor rdi, rdi -> 48 31 FF
    ; syscall -> 0F 05
    mov dil, 0x48
    call emit_b
    mov dil, 0xC7
    call emit_b
    mov dil, 0xC0
    call emit_b
    mov edi, 60
    call emit_d
    
    mov dil, 0x48
    call emit_b
    mov dil, 0x31
    call emit_b
    mov dil, 0xFF
    call emit_b
    
    mov dil, 0x0F
    call emit_b
    mov dil, 0x05
    call emit_b
    ret

; Map phys reg ID to ModRM/SIB reg fields
; 0 -> r10 (ID 2, REX.B/R)
; 1 -> r11 (ID 3, REX.B/R)
; 2 -> r12 (ID 4, REX.B/R)
; 3 -> r13 (ID 5, REX.B/R)
; 4 -> r14 (ID 6, REX.B/R)
; 5 -> r15 (ID 7, REX.B/R)

; Emit Call to Runtime helper
; Target offset in rdi
emit_runtime_call:
    ; rel32 = target - current_offset - 5
    mov eax, [out_idx]
    add eax, 5
    sub edi, eax ; edi = rel32
    push rdi     ; save rel32 before emit_b corrupts dil
    mov dil, 0xE8 ; call opcode
    call emit_b
    pop rdi      ; restore rel32
    call emit_d
    ret

; Emit instruction selection for all IR records
codegen_emit_all:
    push r12
    push r13
    push r14
    push r15
    push rbx
    call emit_prologue

    mov r12d, [ir_count]
    xor r13d, r13d ; ir_idx = 0
.loop:
    cmp r13d, r12d
    je .done
    
    imul eax, r13d, IR_RECORD_SIZE
    lea r14, [ir_buffer + rax] ; r14 = IR record ptr
    
    movzx eax, byte [r14 + 0] ; opcode
    
    cmp al, IR_LOAD_IMM
    je .load_imm
    
    cmp al, IR_LOAD_FIMM
    je .load_fimm

    cmp al, IR_LOAD_VAR
    je .load_var

    cmp al, IR_LOAD_BOOL
    je .load_bool

    cmp al, IR_LOAD_STR
    je .load_str
    
    cmp al, IR_STORE_VAR
    je .store_var
    
    cmp al, IR_ADD
    je .arith_op
    
    cmp al, IR_SUB
    je .arith_op
    
    cmp al, IR_MUL
    je .arith_op
    
    cmp al, IR_DIV
    je .arith_op
    
    cmp al, IR_MOD
    je .arith_op
    
    cmp al, IR_AND
    je .arith_op
    
    cmp al, IR_OR
    je .arith_op
    
    cmp al, IR_XOR
    je .arith_op

    cmp al, IR_BOOL_AND
    je .bool_and_op

    cmp al, IR_BOOL_OR
    je .bool_or_op

    cmp al, IR_BOOL_NOT
    je .bool_not_op
    
    cmp al, IR_OUT_INT
    je .output_val
    cmp al, IR_OUT_FLOAT
    je .output_val
    cmp al, IR_OUT_BOOL
    je .output_val
    cmp al, IR_OUT_STR
    je .output_val
    cmp al, IR_OUT_CHAR
    je .output_val

    cmp al, IR_HALT
    je .halt

    cmp al, IR_ABS_INT
    je  cge_abs_int_op
    cmp al, IR_MIN_INT
    je  cge_min_int_op
    cmp al, IR_MAX_INT
    je  cge_max_int_op
    cmp al, IR_SHL
    je  cge_shift_op
    cmp al, IR_SHR
    je  cge_shift_op
    cmp al, IR_SIGNUM
    je  cge_signum_op
    cmp al, IR_POPCOUNT
    je  cge_popcount_op
    cmp al, IR_CLZ
    je  cge_clz_op
    cmp al, IR_CTZ
    je  cge_ctz_op
    cmp al, IR_BSWAP
    je  cge_bswap_op
    cmp al, IR_ROL
    je  cge_rot_op
    cmp al, IR_ROR
    je  cge_rot_op
    cmp al, IR_SWAP_NIB
    je  cge_swap_nib_op
    cmp al, IR_CLZ8
    je  cge_clz8_op
    cmp al, IR_ABS_FLOAT
    je  cge_abs_float_op
    cmp al, IR_MIN_FLOAT
    je  cge_min_max_float_op
    cmp al, IR_MAX_FLOAT
    je  cge_min_max_float_op
    cmp al, IR_CEIL
    je  cge_roundf_op
    cmp al, IR_FLOOR
    je  cge_roundf_op
    cmp al, IR_ROUND
    je  cge_roundf_op
    cmp al, IR_TRUNC_F
    je  cge_roundf_op
    cmp al, IR_SQRT
    je  cge_sqrt_op
    cmp al, IR_CMP_BOOL
    je  cge_cmp_bool_op
    cmp al, IR_IS_ALPHA
    je  cge_char_pred_op
    cmp al, IR_IS_DIGIT_C
    je  cge_char_pred_op
    cmp al, IR_IS_ALNUM
    je  cge_char_pred_op
    cmp al, IR_IS_SPACE
    je  cge_char_pred_op
    cmp al, IR_IS_PRINT
    je  cge_char_pred_op
    cmp al, IR_IS_UPPER
    je  cge_char_pred_op
    cmp al, IR_IS_LOWER_C
    je  cge_char_pred_op
    cmp al, IR_IS_PUNCT
    je  cge_char_pred_op
    cmp al, IR_TO_UPPER
    je  cge_char_xform_op
    cmp al, IR_TO_LOWER
    je  cge_char_xform_op
    cmp al, IR_IS_EVEN
    je  cge_is_even_odd_op
    cmp al, IR_IS_ODD
    je  cge_is_even_odd_op
    cmp al, IR_TO_DIGIT
    je  cge_to_digit_op
    cmp al, IR_IS_NAN
    je  cge_float_pred_op
    cmp al, IR_IS_INF
    je  cge_float_pred_op
    cmp al, IR_IS_FINITE
    je  cge_float_pred_op
    cmp al, IR_IS_ZERO_F
    je  cge_float_pred_op
    cmp al, IR_IS_POS_F
    je  cge_float_pred_op
    cmp al, IR_IS_NEG_F
    je  cge_float_pred_op

.next_ir:
    inc r13d
    jmp .loop

.done:
    pop rbx
    pop r15
    pop r14
    pop r13
    pop r12
    ret

.load_imm:
    ; IR_LOAD_IMM: load imm64 to dst
    movzx eax, word [r14 + 2] ; dst vreg
    call get_dst_phys ; al = phys ID
    mov r15b, al
    
    mov rdi, [r14 + 8] ; imm
    test rdi, rdi
    jnz .load_imm_nonzero
    
    ; Optimization: xor reg, reg -> 4D 31 ModRM(C0 | (reg<<3) | reg)
    mov dil, 0x4D
    call emit_b
    mov dil, 0x31
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC0
    or al, r15b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp .next_ir

.load_imm_nonzero:
    mov rdi, [r14 + 8] ; imm
    ; Check if imm fits in 32-bit signed integer
    mov rax, rdi
    sar rax, 31
    cmp rax, 0
    je .fit_32
    cmp rax, -1
    je .fit_32
    
    ; Does not fit: 64-bit mov reg, imm64 -> 49 B8+reg imm64
    mov dil, 0x49
    call emit_b
    mov al, 0xB8
    add al, r15b
    mov dil, al
    call emit_b
    mov rdi, [r14 + 8] ; imm
    call emit_q
    call store_dst_spill
    jmp .next_ir

.fit_32:
    ; Fits in 32-bit: mov reg, imm32 -> 49 C7 C0+reg imm32
    mov dil, 0x49
    call emit_b
    mov dil, 0xC7
    call emit_b
    mov al, 0xC0
    add al, r15b
    mov dil, al
    call emit_b
    mov edi, dword [r14 + 8] ; lower 32 bits
    call emit_d
    call store_dst_spill
    jmp .next_ir

.load_fimm:
    ; IR_LOAD_FIMM: load float imm64 to dst
    movzx eax, word [r14 + 2] ; dst vreg
    call get_dst_phys
    
    mov r15b, al
    mov dil, 0x49
    call emit_b
    mov al, 0xB8
    add al, r15b
    mov dil, al
    call emit_b
    mov rdi, [r14 + 8] ; float imm
    call emit_q
    call store_dst_spill
    jmp .next_ir

.load_var:
    ; IR_LOAD_VAR: load variable value to dst
    ; imm = variable offset
    movzx eax, word [r14 + 2] ; dst vreg
    call get_dst_phys
    
    ; mov reg, [addr32] -> 4C 8B (0x04 | (reg<<3)) 0x25 <addr32>
    mov r15b, al
    mov dil, 0x4C
    call emit_b
    mov dil, 0x8B
    call emit_b
    
    mov al, r15b
    shl al, 3
    or al, 0x04
    mov dil, al
    call emit_b
    
    mov dil, 0x25
    call emit_b
    
    mov edi, [r14 + 8] ; offset / addr32
    call emit_d
    call store_dst_spill
    jmp .next_ir

.load_bool:
    ; IR_LOAD_BOOL: same layout as IR_LOAD_IMM (imm = 1/0/-1 for true/neutral/false)
    jmp .load_imm

.load_str:
    ; IR_LOAD_STR: embed string inline in code stream, load address via RIP-relative LEA
    ; IR record: imm=[r14+8] = tok_str_ptr (compiler-space), aux=[r14+16] = tok_str_len
    movzx eax, word [r14 + 2] ; dst vreg
    call get_dst_phys
    mov r15b, al              ; phys reg (0-5 => r8-r13)

    ; Push string pointer and length onto stack for safe scratch access
    ; (r12/r13 are the loop counter/total and must not be clobbered)
    push qword [r14 + 16]    ; [rsp+8]  = tok_str_len (aux)
    push qword [r14 + 8]     ; [rsp]    = tok_str_ptr (imm)

    ; --- Emit: jmp over string+null ---
    ; E9 <rel32>  where rel32 = tok_str_len + 1
    mov dil, 0xE9
    call emit_b
    mov edi, [rsp + 8]        ; tok_str_len
    inc edi                   ; +1 for null terminator
    call emit_d

    ; --- Emit string bytes ---
    mov rsi, [rsp]            ; tok_str_ptr
    mov rcx, [rsp + 8]        ; tok_str_len
    call emit_block

    ; --- Emit null terminator ---
    xor dil, dil
    call emit_b

    ; --- Emit: lea r(dst), [rip + disp32] ---
    ; String starts (len+1) bytes before the LEA; LEA itself is 7 bytes.
    ; disp32 = str_start - (end_of_lea) = -(tok_str_len + 1 + 7) = -(tok_str_len + 8)
    mov dil, 0x4C             ; REX.W | REX.R
    call emit_b
    mov dil, 0x8D             ; LEA opcode
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0x05               ; ModRM: mod=00, reg=phys, rm=101 (RIP-relative)
    mov dil, al
    call emit_b
    mov edi, [rsp + 8]        ; tok_str_len
    add edi, 8                ; +1 null +7 LEA bytes
    neg edi                   ; negative displacement (backward)
    call emit_d

    add rsp, 16               ; restore stack
    call store_dst_spill
    jmp .next_ir

.store_var:
    ; IR_STORE_VAR: store src1 register to variable.
    ; This instruction has NO dst vreg, so we must clear dst_spilled_vreg
    ; before returning.  Calling store_dst_spill without first calling
    ; get_dst_phys left a stale value that caused spurious spill writes
    ; (Bug 3 fix: reset dst_spilled_vreg here, not via store_dst_spill).
    mov dword [dst_spilled_vreg], 0   ; <-- Bug 3 fix
    movzx eax, word [r14 + 4] ; src1 vreg
    call load_src1_phys
    
    ; mov [addr32], reg -> 4C 89 (0x04 | (reg<<3)) 0x25 <addr32>
    mov r15b, al
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    
    mov al, r15b
    shl al, 3
    or al, 0x04
    mov dil, al
    call emit_b
    
    mov dil, 0x25
    call emit_b
    
    mov edi, [r14 + 8] ; offset / addr32
    call emit_d
    ; No store_dst_spill — dst_spilled_vreg is already 0 (cleared above)
    jmp .next_ir

.arith_op:
    ; IR_ADD / IR_SUB / IR_MUL / etc: dst = src1 op src2
    movzx eax, word [r14 + 4] ; src1 vreg
    call load_src1_phys
    mov r15b, al ; src1 phys
    
    movzx eax, word [r14 + 6] ; src2 vreg
    call load_src2_phys
    mov r9b, al ; src2 phys
    
    movzx eax, word [r14 + 2] ; dst vreg
    call get_dst_phys
    mov r8b, al ; dst phys
    
    ; Move src1 to dst first (if not already there)
    cmp r8b, r15b
    je .op_emit
    
    ; mov r8, r15 -> 4D 89 ModRM(C0 | (r15<<3) | r8)
    mov dil, 0x4D
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b

.op_emit:
    ; If float type, use SSE scalar double instructions instead of integer ops
    movzx eax, byte [r14 + 1] ; type
    cmp al, TYPE_FLOAT
    je .op_emit_float

    ; --- Integer arithmetic ---
    movzx eax, byte [r14 + 0] ; opcode
    cmp al, IR_ADD
    je .emit_add
    cmp al, IR_SUB
    je .emit_sub
    cmp al, IR_MUL
    je .emit_mul
    cmp al, IR_DIV
    je .emit_div
    cmp al, IR_MOD
    je .emit_mod
    cmp al, IR_AND
    je .emit_and
    cmp al, IR_OR
    je .emit_or
    cmp al, IR_XOR
    je .emit_xor
    call store_dst_spill
    jmp .next_ir

.emit_add:
    ; add dst, src2 -> 4D 01 ModRM(C0 | (src2<<3) | dst)
    mov dil, 0x4D
    call emit_b
    mov dil, 0x01
    call emit_b
    mov al, r9b
    shl al, 3
    or al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp .next_ir

.emit_sub:
    ; sub dst, src2 -> 4D 29 ModRM(C0 | (src2<<3) | dst)
    mov dil, 0x4D
    call emit_b
    mov dil, 0x29
    call emit_b
    mov al, r9b
    shl al, 3
    or al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp .next_ir

.emit_mul:
    ; imul dst, src2 -> 4D 0F AF ModRM(C0 | (dst<<3) | src2)
    mov dil, 0x4D
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0xAF
    call emit_b
    mov al, r8b
    shl al, 3
    or al, 0xC0
    or al, r9b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp .next_ir

.emit_div:
.emit_mod:
    ; idiv src2 -> divides rdx:rax by src2
    ; 1. mov rax, r(8+dst) -> 49 8B C0 + dst
    ; REX.W + REX.B (extends rm), opcode 8B = MOV r64,r/m64: rax <- r(8+dst)
    mov dil, 0x49
    call emit_b
    mov dil, 0x8B
    call emit_b
    mov al, 0xC0
    add al, r8b
    mov dil, al
    call emit_b
    
    ; 2. cqo -> 48 99
    mov dil, 0x48
    call emit_b
    mov dil, 0x99
    call emit_b
    
    ; 3. idiv r(8+src2) -> 49 F7 ModRM(F8 | src2)
    mov dil, 0x49
    call emit_b
    mov dil, 0xF7
    call emit_b
    mov al, 0xF8
    add al, r9b
    mov dil, al
    call emit_b
    
    movzx eax, byte [r14 + 0] ; opcode
    cmp al, IR_MOD
    je .emit_mod_store
    
    ; 4. mov r(8+dst), rax -> 49 89 C0 + dst
    ; REX.W + REX.B, opcode 89 = MOV r/m64,r64: r(8+dst) <- rax (reg=0=rax)
    mov dil, 0x49
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, 0xC0
    add al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp .next_ir

.emit_mod_store:
    ; 4. mov r(8+dst), rdx -> 49 89 D0 + dst
    ; REX.W + REX.B, opcode 89 = MOV r/m64,r64: r(8+dst) <- rdx (reg=2=rdx)
    mov dil, 0x49
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, 0xD0
    add al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp .next_ir

.emit_and:
    movzx eax, byte [r14 + 1] ; type
    cmp al, 3 ; TYPE_BOOL
    je .emit_bool_and
    ; and dst, src2 -> 4D 21 ModRM(C0 | (src2<<3) | dst)
    mov dil, 0x4D
    call emit_b
    mov dil, 0x21
    call emit_b
    mov al, r9b
    shl al, 3
    or al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp .next_ir

.emit_bool_and:
    ; min(dst, src2)
    ; cmp dst, src2 -> 4D 39 ModRM(C0 | (src2<<3) | dst)
    mov dil, 0x4D
    call emit_b
    mov dil, 0x39
    call emit_b
    mov al, r9b
    shl al, 3
    or al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    ; cmovg dst, src2 -> 4D 0F 4F ModRM(C0 | (dst<<3) | src2)
    mov dil, 0x4D
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x4F
    call emit_b
    mov al, r8b
    shl al, 3
    or al, 0xC0
    or al, r9b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp .next_ir

.emit_or:
    movzx eax, byte [r14 + 1] ; type
    cmp al, 3 ; TYPE_BOOL
    je .emit_bool_or
    ; or dst, src2 -> 4D 09 ModRM(C0 | (src2<<3) | dst)
    mov dil, 0x4D
    call emit_b
    mov dil, 0x09
    call emit_b
    mov al, r9b
    shl al, 3
    or al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp .next_ir

.emit_bool_or:
    ; max(dst, src2)
    ; cmp dst, src2 -> 4D 39 ModRM(C0 | (src2<<3) | dst)
    mov dil, 0x4D
    call emit_b
    mov dil, 0x39
    call emit_b
    mov al, r9b
    shl al, 3
    or al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    ; cmovl dst, src2 -> 4D 0F 4C ModRM(C0 | (dst<<3) | src2)
    mov dil, 0x4D
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x4C
    call emit_b
    mov al, r8b
    shl al, 3
    or al, 0xC0
    or al, r9b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp .next_ir

.emit_xor:
    ; xor dst, src2 -> 4D 31 ModRM(C0 | (src2<<3) | dst)
    mov dil, 0x4D
    call emit_b
    mov dil, 0x31
    call emit_b
    mov al, r9b
    shl al, 3
    or al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp .next_ir

; -------- Bool keyword op handlers --------
; IR_BOOL_AND: dst = min(src1, src2) — Łukasiewicz AND
.bool_and_op:
    movzx eax, word [r14 + 4]   ; src1 vreg
    call load_src1_phys
    mov r15b, al                 ; src1 phys
    movzx eax, word [r14 + 6]   ; src2 vreg
    call load_src2_phys
    mov r9b, al                  ; src2 phys
    movzx eax, word [r14 + 2]   ; dst vreg
    call get_dst_phys
    mov r8b, al                  ; dst phys
    ; mov dst, src1
    mov dil, 0x4D
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    jmp .emit_bool_and

; IR_BOOL_OR: dst = max(src1, src2) — Łukasiewicz OR
.bool_or_op:
    movzx eax, word [r14 + 4]   ; src1 vreg
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 6]   ; src2 vreg
    call load_src2_phys
    mov r9b, al
    movzx eax, word [r14 + 2]   ; dst vreg
    call get_dst_phys
    mov r8b, al
    ; mov dst, src1
    mov dil, 0x4D
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    jmp .emit_bool_or

; IR_BOOL_NOT: dst = -src1 — bool not (negate signed value)
.bool_not_op:
    movzx eax, word [r14 + 4]   ; src1 vreg
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 2]   ; dst vreg
    call get_dst_phys
    mov r8b, al
    ; mov dst, src1
    mov dil, 0x4D
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    ; neg dst -> 49 F7 D8+dst
    mov dil, 0x49
    call emit_b
    mov dil, 0xF7
    call emit_b
    mov al, 0xD8
    add al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp .next_ir

.op_emit_float:
    ; Float arithmetic: move values through XMM0/XMM1, use SSE scalar double ops
    ; r8b=dst_phys, r9b=src2_phys; dst already holds src1 value (moved above)
    ;
    ; Step 1: movq xmm0, r(8+dst)   [66 49 0F 6E (0xC0|dst)]
    mov dil, 0x66
    call emit_b
    mov dil, 0x49
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x6E
    call emit_b
    mov al, r8b
    or al, 0xC0         ; mod=11, xmm0 reg=0, rm=dst_phys
    mov dil, al
    call emit_b
    ;
    ; Step 2: movq xmm1, r(8+src2)  [66 49 0F 6E (0xC8|src2)]
    mov dil, 0x66
    call emit_b
    mov dil, 0x49
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x6E
    call emit_b
    mov al, r9b
    or al, 0xC8         ; mod=11, xmm1 reg=1, rm=src2_phys
    mov dil, al
    call emit_b
    ;
    ; Step 3: F2 0F <op> C1   (xmm0 = xmm0 op xmm1)
    mov dil, 0xF2
    call emit_b
    mov dil, 0x0F
    call emit_b
    movzx eax, byte [r14 + 0] ; opcode
    cmp al, IR_ADD
    je .fop_add
    cmp al, IR_SUB
    je .fop_sub
    cmp al, IR_MUL
    je .fop_mul
    cmp al, IR_DIV
    je .fop_div
.fop_add:
    mov dil, 0x58       ; addsd
    call emit_b
    jmp .fop_modrm
.fop_sub:
    mov dil, 0x5C       ; subsd
    call emit_b
    jmp .fop_modrm
.fop_mul:
    mov dil, 0x59       ; mulsd
    call emit_b
    jmp .fop_modrm
.fop_div:
    mov dil, 0x5E       ; divsd
    call emit_b
.fop_modrm:
    mov dil, 0xC1       ; mod=11, reg=xmm0, rm=xmm1
    call emit_b
    ;
    ; Step 4: movq r(8+dst), xmm0   [66 49 0F 7E (0xC0|dst)]
    mov dil, 0x66
    call emit_b
    mov dil, 0x49
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x7E
    call emit_b
    mov al, r8b
    or al, 0xC0         ; mod=11, xmm0 reg=0, rm=dst_phys
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp .next_ir

.output_val:
    ; IR_OUT_*: prints value in src1.  No dst vreg — clear dst_spilled_vreg
    ; so a stale value from a previous instruction isn't written (Bug 3 fix).
    mov dword [dst_spilled_vreg], 0   ; <-- Bug 3 fix
    movzx eax, word [r14 + 4] ; src1 vreg
    call load_src1_phys
    mov r15b, al ; phys
    
    ; 1. Move to rdi: mov rdi, reg -> 4C 89 ModRM(C0 | (reg<<3) | 7)
    ; (rdi ID is 7)
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b
    
    ; 2. Call correct printer depending on type
    movzx eax, byte [r14 + 1] ; type
    cmp al, TYPE_INT
    je .call_pri
    cmp al, TYPE_FLOAT
    je .call_prf
    cmp al, TYPE_BOOL
    je .call_prb
    cmp al, TYPE_STR
    je .call_prs
    cmp al, TYPE_CHAR
    je .call_prc
    cmp al, TYPE_BYTE
    je .call_pri    ; print byte as integer
    call store_dst_spill
    jmp .next_ir

.call_pri:
    mov edi, 125
    call emit_runtime_call
    jmp .next_ir     ; dst_spilled_vreg already cleared in .output_val
.call_prs:
    mov edi, 637
    call emit_runtime_call
    jmp .next_ir
.call_prb:
    mov edi, 1149
    call emit_runtime_call
    jmp .next_ir
.call_prc:
    mov edi, 1917
    call emit_runtime_call
    jmp .next_ir

.call_prf:
    ; Float printer expects argument in XMM0 (according to SysV ABI)!
    ; So we must move the value from rdi to XMM0!
    ; movq xmm0, rdi -> 66 48 0F 6E C7
    mov dil, 0x66
    call emit_b
    mov dil, 0x48
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x6E
    call emit_b
    mov dil, 0xC7
    call emit_b
    
    ; Load precision from IR record (imm field)
    mov rax, [r14 + 8]
    test rax, rax
    jnz .use_custom_prec
    mov rax, 16         ; Default precision
.use_custom_prec:
    
    ; Pass precision in rdi (edi) according to SysV ABI
    ; mov edi, eax -> BF <eax>
    mov dil, 0xBF
    call emit_b
    mov edi, eax
    call emit_d
    
    mov edi, 1405
    call emit_runtime_call
    jmp .next_ir     ; dst_spilled_vreg already cleared in .output_val

.halt:
    ; IR_HALT: no dst vreg — clear dst_spilled_vreg (Bug 3 fix)
    mov dword [dst_spilled_vreg], 0   ; <-- Bug 3 fix
    call emit_epilogue_and_exit
    jmp .next_ir


; Helper to load src1 into a physical register (or r14 if spilled)
; Bug 9 fix: rbx is callee-saved (SysV ABI); save/restore it.
load_src1_phys:
    push rbx
    movzx rbx, ax ; save vreg id
    movzx rax, byte [vreg_phys + rbx]
    cmp al, 255
    jne .done
    ; Spilled! Reload into r14 (ID 6)
    ; mov r14, [rbp + offset]
    mov dil, 0x4C
    call emit_b
    mov dil, 0x8B
    call emit_b
    mov dil, 0xB5
    call emit_b
    mov edi, dword [vreg_offset + rbx * 4]
    call emit_d
    mov al, 6 ; return r14
.done:
    pop rbx
    ret

; Helper to load src2 into a physical register (or r15 if spilled)
; Bug 9 fix: rbx is callee-saved (SysV ABI); save/restore it.
load_src2_phys:
    push rbx
    movzx rbx, ax ; save vreg id
    movzx rax, byte [vreg_phys + rbx]
    cmp al, 255
    jne .done
    ; Spilled! Reload into r15 (ID 7)
    mov dil, 0x4C
    call emit_b
    mov dil, 0x8B
    call emit_b
    mov dil, 0xBD
    call emit_b
    mov edi, dword [vreg_offset + rbx * 4]
    call emit_d
    mov al, 7 ; return r15
.done:
    pop rbx
    ret

; Helper to get dst register (or r14 if spilled). Sets dst_spilled_vreg.
; Bug 9 fix: rbx is callee-saved (SysV ABI); save/restore it.
get_dst_phys:
    push rbx
    movzx rbx, ax
    movzx rax, byte [vreg_phys + rbx]
    cmp al, 255
    jne .done
    ; Spilled! We will use r14 (ID 6)
    mov [dst_spilled_vreg], ebx
    mov al, 6
    pop rbx
    ret
.done:
    mov dword [dst_spilled_vreg], 0
    pop rbx
    ret

; Helper to store dst back if it was spilled
store_dst_spill:
    mov eax, [dst_spilled_vreg]
    test eax, eax
    jz .done
    ; Store r14 (ID 6) back to spill slot
    ; mov [rbp + offset], r14
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov dil, 0xB5
    call emit_b
    mov edi, dword [vreg_offset + rax * 4]
    call emit_d
.done:
    ret

get_phys_reg:
    movzx rax, ax
    movzx rax, byte [vreg_phys + rax]
    ret
; Finalize ELF file headers and size patch
; ======================================================
; NEW OPCODE HANDLERS (methods + new IR opcodes)
; ======================================================

; Helper macro: load src1 into r15b, dst into r8b
; (used by many unary handlers below)
; These are inline helpers, not actual macro calls.

; ── IR_ABS_INT ─────────────────────────────────────────
cge_abs_int_op:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al
    ; mov r(dst), r(src1): 4D 89 (0xC0|(src1<<3)|dst)
    mov dil, 0x4D
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    ; mov rax, r(dst): 49 8B (0xC0|dst)
    mov dil, 0x49
    call emit_b
    mov dil, 0x8B
    call emit_b
    mov al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    ; neg rax: 48 F7 D8
    mov dil, 0x48
    call emit_b
    mov dil, 0xF7
    call emit_b
    mov dil, 0xD8
    call emit_b
    ; test r(dst), r(dst): 4D 85 (0xC0|(dst<<3)|dst)
    mov dil, 0x4D
    call emit_b
    mov dil, 0x85
    call emit_b
    mov al, r8b
    shl al, 3
    or al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    ; cmovl r(dst), rax: 4C 0F 4C (0xC0|(dst<<3))
    mov dil, 0x4C
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x4C
    call emit_b
    mov al, r8b
    shl al, 3
    or al, 0xC0
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp  codegen_emit_all.next_ir

; ── IR_MIN_INT ─────────────────────────────────────────
cge_min_int_op:
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 6]
    call load_src2_phys
    mov r9b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al
    ; mov dst, src1
    mov dil, 0x4D
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    jmp  codegen_emit_all.emit_bool_and  ; min = cmp + cmovg (same as bool AND)

; ── IR_MAX_INT ─────────────────────────────────────────
cge_max_int_op:
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 6]
    call load_src2_phys
    mov r9b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al
    ; mov dst, src1
    mov dil, 0x4D
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    jmp  codegen_emit_all.emit_bool_or   ; max = cmp + cmovl (same as bool OR)

; ── IR_SHL / IR_SHR ────────────────────────────────────
cge_shift_op:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 6]
    call load_src2_phys
    mov r9b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al
    ; mov dst, src1
    mov dil, 0x4D
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    ; mov rcx, r(src2): 4C 89 (0xC0|(src2<<3)|1) where rcx=1
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r9b
    shl al, 3
    or al, 0xC1
    mov dil, al
    call emit_b
    ; Check opcode: SHL vs SHR
    movzx eax, byte [r14 + 0]
    cmp al, IR_SHL
    je  cge_shift_shl
    ; SAR r(dst), CL: 49 D3 (0xF8|dst)
    mov dil, 0x49
    call emit_b
    mov dil, 0xD3
    call emit_b
    mov al, 0xF8
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp  codegen_emit_all.next_ir
cge_shift_shl:
    ; SHL r(dst), CL: 49 D3 (0xE0|dst)
    mov dil, 0x49
    call emit_b
    mov dil, 0xD3
    call emit_b
    mov al, 0xE0
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp  codegen_emit_all.next_ir

; ── IR_SIGNUM ──────────────────────────────────────────
cge_signum_op:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al
    ; mov dst, src1
    mov dil, 0x4D
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    ; test dst, dst: 4D 85 (0xC0|(dst<<3)|dst)
    mov dil, 0x4D
    call emit_b
    mov dil, 0x85
    call emit_b
    mov al, r8b
    shl al, 3
    or al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    ; setg al: 0F 9F C0
    mov dil, 0x0F
    call emit_b
    mov dil, 0x9F
    call emit_b
    mov dil, 0xC0
    call emit_b
    ; setl cl: 0F 9C C1
    mov dil, 0x0F
    call emit_b
    mov dil, 0x9C
    call emit_b
    mov dil, 0xC1
    call emit_b
    ; movzx rax, al: 48 0F B6 C0
    mov dil, 0x48
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0xB6
    call emit_b
    mov dil, 0xC0
    call emit_b
    ; movzx rcx, cl: 48 0F B6 C9
    mov dil, 0x48
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0xB6
    call emit_b
    mov dil, 0xC9
    call emit_b
    ; sub rax, rcx: 48 29 C8
    mov dil, 0x48
    call emit_b
    mov dil, 0x29
    call emit_b
    mov dil, 0xC8
    call emit_b
    ; mov r(dst), rax: 49 89 (0xC0|dst)
    mov dil, 0x49
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp  codegen_emit_all.next_ir

; ── IR_POPCOUNT ────────────────────────────────────────
cge_popcount_op:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al
    ; For TYPE_BYTE: AND src with 0xFF first (in rax), then popcnt
    movzx eax, byte [r14 + 1]
    cmp al, TYPE_BYTE
    je  cge_popcount_byte
    ; popcnt r(dst), r(src1): F3 4D 0F B8 (0xC0|(dst<<3)|src1)
    mov dil, 0xF3
    call emit_b
    mov dil, 0x4D
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0xB8
    call emit_b
    mov al, r8b
    shl al, 3
    or al, 0xC0
    or al, r15b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp  codegen_emit_all.next_ir
cge_popcount_byte:
    ; mov rax, r(src1): 4C 8B (0xC0|(src1<<3))  → rax
    mov dil, 0x4C
    call emit_b
    mov dil, 0x8B
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC0
    mov dil, al
    call emit_b
    ; and rax, 0xFF: 48 25 FF 00 00 00
    mov dil, 0x48
    call emit_b
    mov dil, 0x25
    call emit_b
    mov edi, 0xFF
    call emit_d
    ; popcnt rax, rax: F3 48 0F B8 C0
    mov dil, 0xF3
    call emit_b
    mov dil, 0x48
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0xB8
    call emit_b
    mov dil, 0xC0
    call emit_b
    ; mov r(dst), rax: 49 89 (0xC0|dst)
    mov dil, 0x49
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp  codegen_emit_all.next_ir

; ── IR_CLZ ─────────────────────────────────────────────
cge_clz_op:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al
    ; lzcnt r(dst), r(src1): F3 4D 0F BD (0xC0|(dst<<3)|src1)
    mov dil, 0xF3
    call emit_b
    mov dil, 0x4D
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0xBD
    call emit_b
    mov al, r8b
    shl al, 3
    or al, 0xC0
    or al, r15b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp  codegen_emit_all.next_ir

; ── IR_CTZ ─────────────────────────────────────────────
cge_ctz_op:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al
    movzx eax, byte [r14 + 1]
    cmp al, TYPE_BYTE
    je  cge_ctz_byte
    ; tzcnt r(dst), r(src1): F3 4D 0F BC (0xC0|(dst<<3)|src1)
    mov dil, 0xF3
    call emit_b
    mov dil, 0x4D
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0xBC
    call emit_b
    mov al, r8b
    shl al, 3
    or al, 0xC0
    or al, r15b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp  codegen_emit_all.next_ir
cge_ctz_byte:
    ; OR with sentinel 0x100 so tzcnt gives correct result for 8-bit value
    ; mov rax, r(src1)
    mov dil, 0x4C
    call emit_b
    mov dil, 0x8B
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC0
    mov dil, al
    call emit_b
    ; or rax, 0x100: 48 81 C8 00 01 00 00
    mov dil, 0x48
    call emit_b
    mov dil, 0x81
    call emit_b
    mov dil, 0xC8
    call emit_b
    mov edi, 0x100
    call emit_d
    ; tzcnt rax, rax: F3 48 0F BC C0
    mov dil, 0xF3
    call emit_b
    mov dil, 0x48
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0xBC
    call emit_b
    mov dil, 0xC0
    call emit_b
    ; mov r(dst), rax
    mov dil, 0x49
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp  codegen_emit_all.next_ir

; ── IR_BSWAP ───────────────────────────────────────────
cge_bswap_op:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al
    ; mov dst, src1
    mov dil, 0x4D
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    ; bswap r(dst): 49 0F (0xC8+dst)
    mov dil, 0x49
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov al, 0xC8
    add al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp  codegen_emit_all.next_ir

; ── IR_ROL / IR_ROR ────────────────────────────────────
cge_rot_op:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 6]
    call load_src2_phys
    mov r9b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al
    ; mov dst, src1
    mov dil, 0x4D
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    ; mov rcx, r(src2): load shift count into CL
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r9b
    shl al, 3
    or al, 0xC1
    mov dil, al
    call emit_b
    movzx eax, byte [r14 + 0]
    cmp al, IR_ROL
    je  cge_rot_left
    ; ROR r(dst), CL: 49 D3 (0xC8|dst)
    mov dil, 0x49
    call emit_b
    mov dil, 0xD3
    call emit_b
    mov al, 0xC8
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp  codegen_emit_all.next_ir
cge_rot_left:
    ; ROL r(dst), CL: 49 D3 (0xC0|dst)
    mov dil, 0x49
    call emit_b
    mov dil, 0xD3
    call emit_b
    mov al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp  codegen_emit_all.next_ir

; ── IR_SWAP_NIB ────────────────────────────────────────
cge_swap_nib_op:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al
    ; mov rax, r(src1): 4C 89 (0xC0|(src1<<3))
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC0
    mov dil, al
    call emit_b
    ; and rax, 0xFF: 48 25 FF 00 00 00
    mov dil, 0x48
    call emit_b
    mov dil, 0x25
    call emit_b
    mov edi, 0xFF
    call emit_d
    ; ror al, 4: C0 C8 04
    mov dil, 0xC0
    call emit_b
    mov dil, 0xC8
    call emit_b
    mov dil, 0x04
    call emit_b
    ; movzx r(dst), al: 4C 0F B6 (0xC0|(dst<<3))
    mov dil, 0x4C
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0xB6
    call emit_b
    mov al, r8b
    shl al, 3
    or al, 0xC0
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp  codegen_emit_all.next_ir

; ── IR_CLZ8 ────────────────────────────────────────────
cge_clz8_op:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al
    ; mov rax, r(src1)
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC0
    mov dil, al
    call emit_b
    ; and rax, 0xFF: 48 25 FF 00 00 00
    mov dil, 0x48
    call emit_b
    mov dil, 0x25
    call emit_b
    mov edi, 0xFF
    call emit_d
    ; lzcnt rax, rax: F3 48 0F BD C0
    mov dil, 0xF3
    call emit_b
    mov dil, 0x48
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0xBD
    call emit_b
    mov dil, 0xC0
    call emit_b
    ; sub rax, 56: 48 83 E8 38
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xE8
    call emit_b
    mov dil, 56
    call emit_b
    ; mov r(dst), rax
    mov dil, 0x49
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp  codegen_emit_all.next_ir

; ── IR_ABS_FLOAT ───────────────────────────────────────
cge_abs_float_op:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al
    ; movq xmm0, r(src1): 66 49 0F 6E (0xC0|src1)
    mov dil, 0x66
    call emit_b
    mov dil, 0x49
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x6E
    call emit_b
    mov al, r15b
    or al, 0xC0
    mov dil, al
    call emit_b
    ; mov rax, 0x7FFFFFFFFFFFFFFF: 48 B8 FF FF FF FF FF FF FF 7F
    mov dil, 0x48
    call emit_b
    mov dil, 0xB8
    call emit_b
    mov rdi, 0x7FFFFFFFFFFFFFFF
    call emit_q
    ; movq xmm1, rax: 66 48 0F 6E C8
    mov dil, 0x66
    call emit_b
    mov dil, 0x48
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x6E
    call emit_b
    mov dil, 0xC8
    call emit_b
    ; andpd xmm0, xmm1: 66 0F 54 C1
    mov dil, 0x66
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x54
    call emit_b
    mov dil, 0xC1
    call emit_b
    ; movq r(dst), xmm0: 66 49 0F 7E (0xC0|dst)
    mov dil, 0x66
    call emit_b
    mov dil, 0x49
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x7E
    call emit_b
    mov al, r8b
    or al, 0xC0
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp  codegen_emit_all.next_ir

; ── IR_MIN_FLOAT / IR_MAX_FLOAT ────────────────────────
cge_min_max_float_op:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 6]
    call load_src2_phys
    mov r9b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al
    ; movq xmm0, r(src1): 66 49 0F 6E (0xC0|src1)
    mov dil, 0x66
    call emit_b
    mov dil, 0x49
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x6E
    call emit_b
    mov al, r15b
    or al, 0xC0
    mov dil, al
    call emit_b
    ; movq xmm1, r(src2): 66 49 0F 6E (0xC8|src2)
    mov dil, 0x66
    call emit_b
    mov dil, 0x49
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x6E
    call emit_b
    mov al, r9b
    or al, 0xC8
    mov dil, al
    call emit_b
    ; F2 0F 5D/5F C1 (minsd/maxsd xmm0, xmm1)
    mov dil, 0xF2
    call emit_b
    mov dil, 0x0F
    call emit_b
    movzx eax, byte [r14 + 0]
    cmp al, IR_MIN_FLOAT
    je  cge_mmf_min
    mov dil, 0x5F
    call emit_b
    jmp  cge_mmf_modrm
    ; (maxsd opcode byte 0x5F emitted above)
cge_mmf_min:
    mov dil, 0x5D
    call emit_b
    ; (minsd opcode byte 0x5D emitted above)
cge_mmf_modrm:
    mov dil, 0xC1
    call emit_b
    ; movq r(dst), xmm0: 66 49 0F 7E (0xC0|dst)
    mov dil, 0x66
    call emit_b
    mov dil, 0x49
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x7E
    call emit_b
    mov al, r8b
    or al, 0xC0
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp  codegen_emit_all.next_ir

; ── IR_CEIL / IR_FLOOR / IR_ROUND / IR_TRUNC_F ─────────
cge_roundf_op:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al
    ; movq xmm0, r(src1): 66 49 0F 6E (0xC0|src1)
    mov dil, 0x66
    call emit_b
    mov dil, 0x49
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x6E
    call emit_b
    mov al, r15b
    or al, 0xC0
    mov dil, al
    call emit_b
    ; Determine roundsd mode from opcode
    movzx ebx, byte [r14 + 0]
    cmp bl, IR_TRUNC_F
    je  cge_roundf_trunc_mode
    ; mode = 0x3E - opcode (CEIL=2, FLOOR=1, ROUND=0)
    mov al, 0x3E
    sub al, bl
    mov bl, al
    jmp  cge_roundf_emit
cge_roundf_trunc_mode:
    mov bl, 3
cge_roundf_emit:
    ; roundsd xmm0, xmm0, imm8: 66 0F 3A 0B C0 bl
    mov dil, 0x66
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x3A
    call emit_b
    mov dil, 0x0B
    call emit_b
    mov dil, 0xC0
    call emit_b
    mov dil, bl
    call emit_b
    ; For TRUNC_F: keep as float (movq back). For CEIL/FLOOR/ROUND: cvttsd2si → int
    movzx eax, byte [r14 + 0]
    cmp al, IR_TRUNC_F
    je  cge_roundf_to_float
    ; cvttsd2si r(dst), xmm0: F2 4C 0F 2C (0xC0|(dst<<3))
    mov dil, 0xF2
    call emit_b
    mov dil, 0x4C
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x2C
    call emit_b
    mov al, r8b
    shl al, 3
    or al, 0xC0
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp  codegen_emit_all.next_ir
cge_roundf_to_float:
    ; movq r(dst), xmm0: 66 49 0F 7E (0xC0|dst)
    mov dil, 0x66
    call emit_b
    mov dil, 0x49
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x7E
    call emit_b
    mov al, r8b
    or al, 0xC0
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp  codegen_emit_all.next_ir

; ── IR_SQRT ────────────────────────────────────────────
cge_sqrt_op:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al
    ; movq xmm0, r(src1): 66 49 0F 6E (0xC0|src1)
    mov dil, 0x66
    call emit_b
    mov dil, 0x49
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x6E
    call emit_b
    mov al, r15b
    or al, 0xC0
    mov dil, al
    call emit_b
    ; sqrtsd xmm0, xmm0: F2 0F 51 C0
    mov dil, 0xF2
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x51
    call emit_b
    mov dil, 0xC0
    call emit_b
    ; movq r(dst), xmm0: 66 49 0F 7E (0xC0|dst)
    mov dil, 0x66
    call emit_b
    mov dil, 0x49
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x7E
    call emit_b
    mov al, r8b
    or al, 0xC0
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp  codegen_emit_all.next_ir

; ── IR_CMP_BOOL ────────────────────────────────────────
; Produces Rex bool result: setcc→0/1 → 2x-1 → -1/1
cge_cmp_bool_op:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al          ; src1 phys
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al           ; dst phys

    movzx eax, byte [r14 + 1]  ; type
    cmp al, TYPE_FLOAT
    je  cge_cmp_bool_float

    ; ── Integer/Bool comparison ──
    movzx eax, word [r14 + 6]  ; src2 vreg
    test ax, ax
    jnz  cge_cmp_int_reg
    ; cmp r(src1), imm32: 49 81 (0xF8|src1) imm32
    mov dil, 0x49
    call emit_b
    mov dil, 0x81
    call emit_b
    mov al, 0xF8
    or al, r15b
    mov dil, al
    call emit_b
    mov edi, [r14 + 8]
    call emit_d
    jmp  cge_cmp_bool_setcc_int
cge_cmp_int_reg:
    movzx eax, word [r14 + 6]
    call load_src2_phys
    mov r9b, al
    ; cmp r(src1), r(src2): 4D 39 (0xC0|(src2<<3)|src1)
    mov dil, 0x4D
    call emit_b
    mov dil, 0x39
    call emit_b
    mov al, r9b
    shl al, 3
    or al, 0xC0
    or al, r15b
    mov dil, al
    call emit_b
cge_cmp_bool_setcc_int:
    ; setcc from cmp_int_setcc table
    movzx ebx, byte [r14 + 16]   ; aux = cond code (0-5)
    cmp rbx, 5
    ja  cge_cmp_bool_finish           ; out of range: skip setcc
    mov dil, 0x0F
    call emit_b
    lea rax, [cmp_int_setcc]
    movzx eax, byte [rax + rbx]
    mov dil, al
    call emit_b
    mov dil, 0xC0
    call emit_b   ; setcc al
    jmp  cge_cmp_bool_finish

cge_cmp_bool_float:
    ; movq xmm0, r(src1): 66 49 0F 6E (0xC0|src1)
    mov dil, 0x66
    call emit_b
    mov dil, 0x49
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x6E
    call emit_b
    mov al, r15b
    or al, 0xC0
    mov dil, al
    call emit_b
    movzx eax, word [r14 + 6]    ; src2 vreg
    test ax, ax
    jnz  cge_cmp_float_reg
    ; xorpd xmm1, xmm1 → 0.0: 66 0F 57 C9
    mov dil, 0x66
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x57
    call emit_b
    mov dil, 0xC9
    call emit_b
    jmp  cge_cmp_ucomisd
cge_cmp_float_reg:
    movzx eax, word [r14 + 6]
    call load_src2_phys
    mov r9b, al
    ; movq xmm1, r(src2): 66 49 0F 6E (0xC8|src2)
    mov dil, 0x66
    call emit_b
    mov dil, 0x49
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x6E
    call emit_b
    mov al, r9b
    or al, 0xC8
    mov dil, al
    call emit_b
cge_cmp_ucomisd:
    ; ucomisd xmm0, xmm1: 66 0F 2E C1
    mov dil, 0x66
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x2E
    call emit_b
    mov dil, 0xC1
    call emit_b
    ; setcc from cmp_flt_setcc table
    movzx ebx, byte [r14 + 16]
    cmp rbx, 5
    ja  cge_cmp_bool_finish
    mov dil, 0x0F
    call emit_b
    lea rax, [cmp_flt_setcc]
    movzx eax, byte [rax + rbx]
    mov dil, al
    call emit_b
    mov dil, 0xC0
    call emit_b

cge_cmp_bool_finish:
    ; Convert 0/1 → Rex bool -1/1: 2*x - 1
    ; movzx rax, al: 48 0F B6 C0
    mov dil, 0x48
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0xB6
    call emit_b
    mov dil, 0xC0
    call emit_b
    ; add rax, rax: 48 01 C0
    mov dil, 0x48
    call emit_b
    mov dil, 0x01
    call emit_b
    mov dil, 0xC0
    call emit_b
    ; dec rax: 48 FF C8
    mov dil, 0x48
    call emit_b
    mov dil, 0xFF
    call emit_b
    mov dil, 0xC8
    call emit_b
    ; mov r(dst), rax: 49 89 (0xC0|dst)
    mov dil, 0x49
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp  codegen_emit_all.next_ir

; ── CHAR PREDICATES ────────────────────────────────────
; All use same structure: load src1 into rax, test condition,
; produce 0/1 in al, convert to Rex bool, store to dst
; Helper shared epilogue: converts al (0 or 1) → Rex bool in r(dst)
; Expects: r8b = dst phys (already set by caller)
; Uses: rax (scratch)

cge_char_bool_finish:
    ; al = 0 or 1 from setcc
    ; movzx rax, al: 48 0F B6 C0
    mov dil, 0x48
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0xB6
    call emit_b
    mov dil, 0xC0
    call emit_b
    ; add rax, rax: 48 01 C0
    mov dil, 0x48
    call emit_b
    mov dil, 0x01
    call emit_b
    mov dil, 0xC0
    call emit_b
    ; dec rax: 48 FF C8
    mov dil, 0x48
    call emit_b
    mov dil, 0xFF
    call emit_b
    mov dil, 0xC8
    call emit_b
    ; mov r(dst), rax: 49 89 (0xC0|dst)
    mov dil, 0x49
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp  codegen_emit_all.next_ir

; Helper: emit "mov rax, r(src1)" where r15b = src1 phys
; (inline helper referenced by char pred ops below)

cge_char_pred_op:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al
    ; Load opcode to dispatch to specific predicate
    movzx eax, byte [r14 + 0]
    cmp al, IR_IS_ALPHA
    je  cge_cpred_alpha
    cmp al, IR_IS_DIGIT_C
    je  cge_cpred_digit
    cmp al, IR_IS_ALNUM
    je  cge_cpred_alnum
    cmp al, IR_IS_SPACE
    je  cge_cpred_space
    cmp al, IR_IS_PRINT
    je  cge_cpred_print
    cmp al, IR_IS_UPPER
    je  cge_cpred_upper
    cmp al, IR_IS_LOWER_C
    je  cge_cpred_lower
    cmp al, IR_IS_PUNCT
    je  cge_cpred_punct
    call store_dst_spill
    jmp  codegen_emit_all.next_ir

cge_cpred_emit_load_rax:
    ; mov rax, r(src1): 4C 8B (0xC0|(src1<<3))
    mov dil, 0x4C
    call emit_b
    mov dil, 0x8B
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC0
    mov dil, al
    call emit_b
    ret

cge_cpred_alpha:
    ; is_alpha: (c-'A')<=25 || (c-'a')<=25
    call  cge_cpred_emit_load_rax
    ; sub rax, 'A': 48 83 E8 41
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xE8
    call emit_b
    mov dil, 0x41
    call emit_b
    ; cmp rax, 25: 48 83 F8 19
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xF8
    call emit_b
    mov dil, 25
    call emit_b
    ; setbe cl: 0F 96 C1
    mov dil, 0x0F
    call emit_b
    mov dil, 0x96
    call emit_b
    mov dil, 0xC1
    call emit_b
    ; reload src1 into rax
    call  cge_cpred_emit_load_rax
    ; sub rax, 'a': 48 83 E8 61
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xE8
    call emit_b
    mov dil, 0x61
    call emit_b
    ; cmp rax, 25: 48 83 F8 19
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xF8
    call emit_b
    mov dil, 25
    call emit_b
    ; setbe al: 0F 96 C0
    mov dil, 0x0F
    call emit_b
    mov dil, 0x96
    call emit_b
    mov dil, 0xC0
    call emit_b
    ; or al, cl: 08 C8
    mov dil, 0x08
    call emit_b
    mov dil, 0xC8
    call emit_b
    jmp  cge_char_bool_finish

cge_cpred_digit:
    ; is_digit: (c-'0')<=9
    call  cge_cpred_emit_load_rax
    ; sub rax, '0': 48 83 E8 30
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xE8
    call emit_b
    mov dil, 0x30
    call emit_b
    ; cmp rax, 9: 48 83 F8 09
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xF8
    call emit_b
    mov dil, 9
    call emit_b
    ; setbe al: 0F 96 C0
    mov dil, 0x0F
    call emit_b
    mov dil, 0x96
    call emit_b
    mov dil, 0xC0
    call emit_b
    jmp  cge_char_bool_finish

cge_cpred_alnum:
    ; is_alnum: is_alpha || is_digit
    call  cge_cpred_emit_load_rax
    ; Check digit: sub rax,'0'
    cmp rax,9; setbe dl
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xE8
    call emit_b
    mov dil, 0x30
    call emit_b
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xF8
    call emit_b
    mov dil, 9
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x96
    call emit_b
    mov dil, 0xC2
    call emit_b  ; setbe dl
    ; Check upper alpha
    call  cge_cpred_emit_load_rax
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xE8
    call emit_b
    mov dil, 0x41
    call emit_b
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xF8
    call emit_b
    mov dil, 25
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x96
    call emit_b
    mov dil, 0xC1
    call emit_b  ; setbe cl
    ; Check lower alpha
    call  cge_cpred_emit_load_rax
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xE8
    call emit_b
    mov dil, 0x61
    call emit_b
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xF8
    call emit_b
    mov dil, 25
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x96
    call emit_b
    mov dil, 0xC0
    call emit_b  ; setbe al
    or al, cl
    or al, dl
    mov dil, 0x08
    call emit_b
    mov dil, 0xC8
    call emit_b
    mov dil, 0x08
    call emit_b
    mov dil, 0xD0
    call emit_b
    jmp  cge_char_bool_finish

cge_cpred_space:
    ; is_whitespace: (c-9)<=4 || c==0x20
    call  cge_cpred_emit_load_rax
    ; sub rax, 9: 48 83 E8 09
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xE8
    call emit_b
    mov dil, 9
    call emit_b
    ; cmp rax, 4: 48 83 F8 04
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xF8
    call emit_b
    mov dil, 4
    call emit_b
    ; setbe cl: 0F 96 C1
    mov dil, 0x0F
    call emit_b
    mov dil, 0x96
    call emit_b
    mov dil, 0xC1
    call emit_b
    ; reload and check space (0x20)
    call  cge_cpred_emit_load_rax
    ; cmp rax, 0x20: 48 83 F8 20
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xF8
    call emit_b
    mov dil, 0x20
    call emit_b
    ; sete al: 0F 94 C0
    mov dil, 0x0F
    call emit_b
    mov dil, 0x94
    call emit_b
    mov dil, 0xC0
    call emit_b
    ; or al, cl: 08 C8
    mov dil, 0x08
    call emit_b
    mov dil, 0xC8
    call emit_b
    jmp  cge_char_bool_finish

cge_cpred_print:
    ; is_printable: (c-0x20)<=0x5E (0x20..0x7E)
    call  cge_cpred_emit_load_rax
    ; sub rax, 0x20: 48 83 E8 20
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xE8
    call emit_b
    mov dil, 0x20
    call emit_b
    ; cmp rax, 0x5E: 48 83 F8 5E
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xF8
    call emit_b
    mov dil, 0x5E
    call emit_b
    ; setbe al: 0F 96 C0
    mov dil, 0x0F
    call emit_b
    mov dil, 0x96
    call emit_b
    mov dil, 0xC0
    call emit_b
    jmp  cge_char_bool_finish

cge_cpred_upper:
    ; is_upper: (c-'A')<=25
    call  cge_cpred_emit_load_rax
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xE8
    call emit_b
    mov dil, 0x41
    call emit_b
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xF8
    call emit_b
    mov dil, 25
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x96
    call emit_b
    mov dil, 0xC0
    call emit_b
    jmp  cge_char_bool_finish

cge_cpred_lower:
    ; is_lower: (c-'a')<=25
    call  cge_cpred_emit_load_rax
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xE8
    call emit_b
    mov dil, 0x61
    call emit_b
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xF8
    call emit_b
    mov dil, 25
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x96
    call emit_b
    mov dil, 0xC0
    call emit_b
    jmp  cge_char_bool_finish

cge_cpred_punct:
    ; is_punct: is_print && !is_space && !is_alnum
    ; = (c-0x21)<=0x5D excluding alnum
    ; Simpler: is_print(c) && !is_alnum(c) && c!=0x20
    ; Use: (c-0x21)<=0x5D → printable non-space; then AND NOT alnum
    call  cge_cpred_emit_load_rax
    ; sub rax, 0x21: 48 83 E8 21
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xE8
    call emit_b
    mov dil, 0x21
    call emit_b
    ; cmp rax, 0x5D: 48 83 F8 5D
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xF8
    call emit_b
    mov dil, 0x5D
    call emit_b
    ; setbe cl (print non-space): 0F 96 C1
    mov dil, 0x0F
    call emit_b
    mov dil, 0x96
    call emit_b
    mov dil, 0xC1
    call emit_b
    ; Check digit: (c-'0')<=9 → setbe al
    call  cge_cpred_emit_load_rax
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xE8
    call emit_b
    mov dil, 0x30
    call emit_b
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xF8
    call emit_b
    mov dil, 9
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x96
    call emit_b
    mov dil, 0xC0
    call emit_b
    ; Check alpha upper: (c-'A')<=25 → setbe dl
    call  cge_cpred_emit_load_rax
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xE8
    call emit_b
    mov dil, 0x41
    call emit_b
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xF8
    call emit_b
    mov dil, 25
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x96
    call emit_b
    mov dil, 0xC2
    call emit_b  ; setbe dl
    ; Check alpha lower: (c-'a')<=25 → setbe r9b
    call  cge_cpred_emit_load_rax
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xE8
    call emit_b
    mov dil, 0x61
    call emit_b
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xF8
    call emit_b
    mov dil, 25
    call emit_b
    ; Use sil (rsi lower byte) for 4th bool - but we don't want to clobber rsi
    ; Use movzx into rax after we combine al/dl/cl approach:
    ; Actually: is_alnum = al | dl | r9b - combine first 3
    ; or al, dl: 08 D0
    mov dil, 0x08
    call emit_b
    mov dil, 0xD0
    call emit_b
    ; The lower-alpha setbe:
    mov dil, 0x0F
    call emit_b
    mov dil, 0x96
    call emit_b
    mov dil, 0xC2
    call emit_b  ; setbe dl
    ; or al, dl: combine lower alpha into is_alnum
    mov dil, 0x08
    call emit_b
    mov dil, 0xD0
    call emit_b
    ; NOT al: is_not_alnum = (not is_alnum) & 1
    ; xor al, 1: 34 01 (XOR AL, imm8)
    mov dil, 0x34
    call emit_b
    mov dil, 0x01
    call emit_b
    ; and al, cl: AND with is_print_nonspace
    mov dil, 0x20
    call emit_b
    mov dil, 0xC8
    call emit_b  ; AND AL, CL
    jmp  cge_char_bool_finish

; ── CHAR TRANSFORMS (TO_UPPER / TO_LOWER) ──────────────
cge_char_xform_op:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al
    movzx eax, byte [r14 + 0]
    cmp al, IR_TO_UPPER
    je  cge_xform_upper
    ; TO_LOWER: if (c-'A')<=25, add 0x20
    ; mov rax, r(src1)
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC0
    mov dil, al
    call emit_b
    ; mov rcx, rax: 48 89 C1
    mov dil, 0x48
    call emit_b
    mov dil, 0x89
    call emit_b
    mov dil, 0xC1
    call emit_b
    ; sub rcx, 'A': 48 83 E9 41
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xE9
    call emit_b
    mov dil, 0x41
    call emit_b
    ; cmp rcx, 25: 48 83 F9 19
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xF9
    call emit_b
    mov dil, 25
    call emit_b
    ; setbe cl: 0F 96 C1
    mov dil, 0x0F
    call emit_b
    mov dil, 0x96
    call emit_b
    mov dil, 0xC1
    call emit_b
    ; movzx rcx, cl: 48 0F B6 C9
    mov dil, 0x48
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0xB6
    call emit_b
    mov dil, 0xC9
    call emit_b
    ; shl rcx, 5: 48 C1 E1 05 (shift by 5 gives 0 or 32=0x20)
    mov dil, 0x48
    call emit_b
    mov dil, 0xC1
    call emit_b
    mov dil, 0xE1
    call emit_b
    mov dil, 5
    call emit_b
    ; add rax, rcx: 48 01 C8
    mov dil, 0x48
    call emit_b
    mov dil, 0x01
    call emit_b
    mov dil, 0xC8
    call emit_b
    jmp  cge_xform_store
cge_xform_upper:
    ; TO_UPPER: if (c-'a')<=25, sub 0x20
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC0
    mov dil, al
    call emit_b
    ; mov rcx, rax
    mov dil, 0x48
    call emit_b
    mov dil, 0x89
    call emit_b
    mov dil, 0xC1
    call emit_b
    ; sub rcx, 'a': 48 83 E9 61
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xE9
    call emit_b
    mov dil, 0x61
    call emit_b
    ; cmp rcx, 25
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xF9
    call emit_b
    mov dil, 25
    call emit_b
    ; setbe cl
    mov dil, 0x0F
    call emit_b
    mov dil, 0x96
    call emit_b
    mov dil, 0xC1
    call emit_b
    ; movzx rcx, cl
    mov dil, 0x48
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0xB6
    call emit_b
    mov dil, 0xC9
    call emit_b
    ; shl rcx, 5
    mov dil, 0x48
    call emit_b
    mov dil, 0xC1
    call emit_b
    mov dil, 0xE1
    call emit_b
    mov dil, 5
    call emit_b
    ; sub rax, rcx: 48 29 C8
    mov dil, 0x48
    call emit_b
    mov dil, 0x29
    call emit_b
    mov dil, 0xC8
    call emit_b
cge_xform_store:
    ; mov r(dst), rax: 49 89 (0xC0|dst)
    mov dil, 0x49
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp  codegen_emit_all.next_ir

; ── IR_IS_EVEN / IR_IS_ODD ─────────────────────────────
cge_is_even_odd_op:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al
    ; test r(src1), 1: 49 F7 (0xC0|src1) imm32=1
    mov dil, 0x49
    call emit_b
    mov dil, 0xF7
    call emit_b
    mov al, 0xC0
    or al, r15b
    mov dil, al
    call emit_b
    mov edi, 1
    call emit_d
    movzx eax, byte [r14 + 0]
    cmp al, IR_IS_ODD
    je  cge_ieo_odd
    ; IS_EVEN: setz al (ZF=1 when bit 0 is 0)
    mov dil, 0x0F
    call emit_b
    mov dil, 0x94
    call emit_b
    mov dil, 0xC0
    call emit_b
    jmp  cge_char_bool_finish
cge_ieo_odd:
    ; IS_ODD: setnz al
    mov dil, 0x0F
    call emit_b
    mov dil, 0x95
    call emit_b
    mov dil, 0xC0
    call emit_b
    jmp  cge_char_bool_finish

; ── IR_TO_DIGIT ────────────────────────────────────────
cge_to_digit_op:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al
    ; mov rcx, r(src1)
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC1
    mov dil, al
    call emit_b
    ; sub rcx, '0' (0x30): 48 83 E9 30
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xE9
    call emit_b
    mov dil, 0x30
    call emit_b
    ; cmp rcx, 9: 48 83 F9 09
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xF9
    call emit_b
    mov dil, 9
    call emit_b
    ; mov rax, -1: 48 C7 C0 FF FF FF FF
    mov dil, 0x48
    call emit_b
    mov dil, 0xC7
    call emit_b
    mov dil, 0xC0
    call emit_b
    mov edi, -1
    call emit_d
    ; cmovbe rax, rcx: 48 0F 46 C1 (if <=9: rax=digit value)
    mov dil, 0x48
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x46
    call emit_b
    mov dil, 0xC1
    call emit_b
    ; mov r(dst), rax: 49 89 (0xC0|dst)
    mov dil, 0x49
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp  codegen_emit_all.next_ir

; ── FLOAT PREDICATES ───────────────────────────────────
cge_float_pred_op:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al
    movzx eax, byte [r14 + 0]

    cmp al, IR_IS_NAN
    je  cge_fpred_nan
    cmp al, IR_IS_INF
    je  cge_fpred_inf
    cmp al, IR_IS_FINITE
    je  cge_fpred_finite
    cmp al, IR_IS_ZERO_F
    je  cge_fpred_zero
    cmp al, IR_IS_POS_F
    je  cge_fpred_pos
    cmp al, IR_IS_NEG_F
    je  cge_fpred_neg
    call store_dst_spill
    jmp  codegen_emit_all.next_ir

cge_fpred_nan:
    ; ucomisd xmm0, xmm0 (NaN if PF=1)
    mov dil, 0x66
    call emit_b
    mov dil, 0x49
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x6E
    call emit_b
    mov al, r15b
    or al, 0xC0
    mov dil, al
    call emit_b
    ; ucomisd xmm0, xmm0: 66 0F 2E C0
    mov dil, 0x66
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x2E
    call emit_b
    mov dil, 0xC0
    call emit_b
    ; setp al: 0F 9A C0
    mov dil, 0x0F
    call emit_b
    mov dil, 0x9A
    call emit_b
    mov dil, 0xC0
    call emit_b
    jmp  cge_char_bool_finish

cge_fpred_inf:
    ; (x & 0x7FFFFFFFFFFFFFFF) == 0x7FF0000000000000
    ; mov rax, r(src1)
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC0
    mov dil, al
    call emit_b
    ; mov rcx, 0x7FFFFFFFFFFFFFFF: 48 B9 FF FF FF FF FF FF FF 7F
    mov dil, 0x48
    call emit_b
    mov dil, 0xB9
    call emit_b
    mov rdi, 0x7FFFFFFFFFFFFFFF
    call emit_q
    ; and rax, rcx: 48 21 C8
    mov dil, 0x48
    call emit_b
    mov dil, 0x21
    call emit_b
    mov dil, 0xC8
    call emit_b
    ; mov rdx, 0x7FF0000000000000: 48 BA 00 00 F0 FF FF FF FF 7F
    mov dil, 0x48
    call emit_b
    mov dil, 0xBA
    call emit_b
    mov rdi, 0x7FF0000000000000
    call emit_q
    ; cmp rax, rdx: 48 39 D0
    mov dil, 0x48
    call emit_b
    mov dil, 0x39
    call emit_b
    mov dil, 0xD0
    call emit_b
    ; sete al
    mov dil, 0x0F
    call emit_b
    mov dil, 0x94
    call emit_b
    mov dil, 0xC0
    call emit_b
    jmp  cge_char_bool_finish

cge_fpred_finite:
    ; (x & 0x7FF0000000000000) != 0x7FF0000000000000
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC0
    mov dil, al
    call emit_b
    ; mov rcx, 0x7FF0000000000000
    mov dil, 0x48
    call emit_b
    mov dil, 0xB9
    call emit_b
    mov rdi, 0x7FF0000000000000
    call emit_q
    ; and rax, rcx: 48 21 C8
    mov dil, 0x48
    call emit_b
    mov dil, 0x21
    call emit_b
    mov dil, 0xC8
    call emit_b
    ; cmp rax, rcx: 48 39 C8
    mov dil, 0x48
    call emit_b
    mov dil, 0x39
    call emit_b
    mov dil, 0xC8
    call emit_b
    ; setne al
    mov dil, 0x0F
    call emit_b
    mov dil, 0x95
    call emit_b
    mov dil, 0xC0
    call emit_b
    jmp  cge_char_bool_finish

cge_fpred_zero:
cge_fpred_pos:
cge_fpred_neg:
    ; Load src1 into xmm0, compare with 0.0 (xmm1)
    mov dil, 0x66
    call emit_b
    mov dil, 0x49
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x6E
    call emit_b
    mov al, r15b
    or al, 0xC0
    mov dil, al
    call emit_b
    ; xorpd xmm1, xmm1 (= 0.0): 66 0F 57 C9
    mov dil, 0x66
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x57
    call emit_b
    mov dil, 0xC9
    call emit_b
    ; ucomisd xmm0, xmm1: 66 0F 2E C1
    mov dil, 0x66
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x2E
    call emit_b
    mov dil, 0xC1
    call emit_b
    movzx eax, byte [r14 + 0]
    cmp al, IR_IS_ZERO_F
    je  cge_fpred_sete
    cmp al, IR_IS_POS_F
    je  cge_fpred_seta
    ; IS_NEG_F: setb (CF=1 when xmm0 < xmm1 = below 0.0)
    mov dil, 0x0F
    call emit_b
    mov dil, 0x92
    call emit_b
    mov dil, 0xC0
    call emit_b
    jmp  cge_char_bool_finish
cge_fpred_sete:
    mov dil, 0x0F
    call emit_b
    mov dil, 0x94
    call emit_b
    mov dil, 0xC0
    call emit_b
    jmp  cge_char_bool_finish
cge_fpred_seta:
    mov dil, 0x0F
    call emit_b
    mov dil, 0x97
    call emit_b
    mov dil, 0xC0
    call emit_b
    jmp  cge_char_bool_finish

codegen_finish:
    mov ecx, [out_idx]

    ; Patch ELF program header filesz at offset 64 + 32 = 96
    mov [out_buffer + 96], ecx

    ; Patch memsz at offset 64 + 40 = 104
    ; memsz covers code size + variables storage (VAR_MEM_OFFSET)
    add ecx, VAR_MEM_OFFSET
    mov [out_buffer + 104], ecx
    ret

