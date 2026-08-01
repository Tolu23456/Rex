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
        dq LOAD_BASE          ; e_entry (placeholder — patched at runtime)
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
    ; Inverted jump opcodes for comparison fusion (indexed by COND_* 0-5).
    ; Used when IR_CMP_BOOL feeds a JCC with COND_NE (jump-if-not-true):
    ; we emit `cmp; j<inverse>` and skip bool materialization entirely.
    cmp_int_fused_jcc:  db 0x85,0x84,0x8D,0x8F,0x8E,0x8C  ; jne,je,jge,jg,jle,jl
    cmp_int_fused_jcc8: db 0x75,0x74,0x7D,0x7F,0x7E,0x7C  ; short forms
    cmp_flt_fused_jcc:  db 0x85,0x84,0x83,0x87,0x86,0x82  ; jne,je,jae,ja,jbe,jb (unsigned)
    cmp_flt_fused_jcc8: db 0x75,0x74,0x73,0x77,0x76,0x72  ; short forms
    ; roundsd mode table indexed by (opcode - IR_CEIL): ceil=2,floor=1,round=0,trunc=3
    roundsd_mode:  db 2,1,0,3
    ; 1.0 as IEEE 754 double (for float.recip())
    float_one_bits: dq 0x3FF0000000000000

    ; Runtime binaries — embedded in .rodata, copied selectively to output
    ; Sizes are auto-calculated from incbin — never hardcode!
    rt_pri_bin:  incbin "runtime/rt_pri.bin"
    rt_pri_bin_size equ $ - rt_pri_bin
    rt_prs_bin:  incbin "runtime/rt_prs.bin"
    rt_prs_bin_size equ $ - rt_prs_bin
    rt_prb_bin:  incbin "runtime/rt_prb.bin"
    rt_prb_bin_size equ $ - rt_prb_bin
    rt_prf_bin:  incbin "runtime/rt_prf.bin"
    rt_prf_bin_size equ $ - rt_prf_bin
    rt_alloc_bin: incbin "runtime/rt_alloc.bin"
    rt_alloc_bin_size equ $ - rt_alloc_bin
    rt_seq_bin:   incbin "runtime/rt_seq.bin"
    rt_seq_bin_size equ $ - rt_seq_bin
    rt_str_bin:   incbin "runtime/rt_str.bin"
    rt_str_bin_size equ $ - rt_str_bin
    rt_dict_bin:  incbin "runtime/rt_dict.bin"
    rt_dict_bin_size equ $ - rt_dict_bin
    rt_math_bin:  incbin "runtime/rt_math.bin"
    rt_math_bin_size equ $ - rt_math_bin
    rt_conv_bin:  incbin "runtime/rt_conv.bin"
    rt_conv_bin_size equ $ - rt_conv_bin
    rt_err_bin:   incbin "runtime/rt_err.bin"
    rt_err_bin_size equ $ - rt_err_bin

    ; Protocol call argument registers (SysV ABI) for arg indices 0-5
    ; Values are x86 register numbers (rdi=7, rsi=6, rdx=2, rcx=1, r8=8, r9=9)
    arg_reg_phys    db 7, 6, 2, 1, 8, 9

section .bss
    global out_buffer
    global out_idx
    out_buffer  resb OUT_BUF_MAX
    out_idx     resd 1
    dst_spilled_vreg resd 1
    fused_jcc_target resd 1 ; label ID for fused CMP_BOOL→JCC
    fuse_pending resb 1     ; 1 if current CMP_BOOL is being fused with JCC

    ; Label resolution table: label_id → output_offset
    label_table     resd 256    ; 256 labels max
    ; Jump patch table: (patch_offset, target_label_id)
    jump_patches    resq 128    ; 128 patches max (8 bytes each: 4 offset + 4 label)
    jump_patch_count resd 1

    ; Protocol call patch table: (patch_offset, proto_id)
    proto_patches   resq 128    ; 128 patches max (8 bytes each: 4 offset + 4 proto)
    proto_patch_count resd 1
    ; Protocol body offset table: proto_id → output offset of prologue
    proto_addr_table resd 256

    ; Modular runtime tracking
    need_rt_pri resb 1    ; 1 if program uses output(int)
    need_rt_prs resb 1    ; 1 if program uses output(str)
    need_rt_prb resb 1    ; 1 if program uses output(bool)
    need_rt_prf resb 1    ; 1 if program uses output(float)
    need_rt_alloc resb 1  ; 1 if program uses heap allocation
    need_rt_seq resb 1    ; 1 if program uses seq operations
    need_rt_str resb 1    ; 1 if program uses string operations
    need_rt_dict resb 1   ; 1 if program uses dict operations
    need_rt_math resb 1   ; 1 if program uses math ops (sin/cos/tan/pow/cbrt/gcd/lcm)
    need_rt_conv resb 1   ; 1 if program uses int→str conversions (to_bin/hex/oct)
    need_rt_err resb 1    ; 1 if program uses assert/unreachable (abort)
    rt_pri_off  resd 1    ; file offset of rt_pri in output
    rt_prs_off  resd 1    ; file offset of rt_prs in output
    rt_prb_off  resd 1    ; file offset of rt_prb in output
    rt_prf_off  resd 1    ; file offset of rt_prf in output
    rt_alloc_off resd 1   ; file offset of rt_alloc in output
    rt_seq_off  resd 1    ; file offset of rt_seq in output
    rt_str_off  resd 1    ; file offset of rt_str in output
    rt_dict_off resd 1    ; file offset of rt_dict in output
    rt_math_off resd 1    ; file offset of rt_math in output
    rt_conv_off resd 1    ; file offset of rt_conv in output
    rt_err_off  resd 1    ; file offset of rt_err in output
    rt_total_size resd 1  ; total runtime size embedded in output


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

scan_needed_runtime:
    push r12
    push r13
    push r14
    ; Clear all need flags
    mov byte [need_rt_pri], 0
    mov byte [need_rt_prs], 0
    mov byte [need_rt_prb], 0
    mov byte [need_rt_prf], 0
    mov byte [need_rt_alloc], 0
    mov byte [need_rt_seq], 0
    mov byte [need_rt_str], 0
    mov byte [need_rt_dict], 0
    mov byte [need_rt_math], 0
    mov byte [need_rt_conv], 0
    mov byte [need_rt_err], 0

    mov r12d, [ir_count]
    test r12d, r12d
    jz .scan_done

    xor r13d, r13d        ; ir_idx = 0
.scan_loop:
    cmp r13d, r12d
    je .scan_done

    imul eax, r13d, IR_RECORD_SIZE
    lea r14, [ir_buffer + rax]

    movzx eax, byte [r14]  ; opcode
    cmp al, IR_OUT_INT
    je .check_int_const
    cmp al, IR_OUT_FLOAT
    je .set_prf
    cmp al, IR_OUT_BOOL
    je .set_prb
    cmp al, IR_OUT_STR
    je .set_prs
    cmp al, IR_SEQ_NEW
    je .set_seq_alloc
    cmp al, IR_SEQ_PUSH
    je .set_seq_alloc
    cmp al, IR_ARR_NEW
    je .set_alloc
    cmp al, IR_SEQ_LOAD
    je .set_seq
    cmp al, IR_SEQ_STORE
    je .set_seq
    cmp al, IR_SEQ_LEN
    je .set_seq
    cmp al, IR_SEQ_POP
    je .set_seq_alloc
    cmp al, IR_SEQ_INSERT
    je .set_seq_alloc
    cmp al, IR_SEQ_REMOVE
    je .set_seq
    cmp al, IR_SEQ_COUNT_OF
    je .set_seq
    cmp al, IR_DICT_NEW
    je .set_dict_alloc
    cmp al, IR_DICT_LOAD
    je .set_dict
    cmp al, IR_DICT_STORE
    je .set_dict_alloc
    cmp al, IR_DICT_LEN
    je .set_dict
    cmp al, IR_STR_CONCAT
    je .set_str
    cmp al, IR_STR_LEN
    je .set_str
    cmp al, IR_STR_CMP
    je .set_str
    cmp al, IR_LOAD_DEREF_BYTE
    je .set_str
    ; Extended seq operations
    cmp al, IR_SEQ_FIRST
    je .set_seq
    cmp al, IR_SEQ_LAST
    je .set_seq
    cmp al, IR_SEQ_CONTAINS
    je .set_seq
    cmp al, IR_SEQ_INDEX_OF
    je .set_seq
    cmp al, IR_SEQ_COPY
    je .set_seq_alloc
    cmp al, IR_SEQ_REVERSE
    je .set_seq
    cmp al, IR_SEQ_SUM
    je .set_seq
    cmp al, IR_SEQ_MIN
    je .set_seq
    cmp al, IR_SEQ_MAX
    je .set_seq
    cmp al, IR_SEQ_CLEAR
    je .set_seq
    cmp al, IR_SEQ_RESERVE
    je .set_seq_alloc
    cmp al, IR_SEQ_CAP
    je .set_seq
    ; Math runtime opcodes
    cmp al, IR_SIN
    je .set_math
    cmp al, IR_COS
    je .set_math
    cmp al, IR_TAN
    je .set_math
    cmp al, IR_POW_F
    je .set_math
    cmp al, IR_CBRT
    je .set_math
    cmp al, IR_GCD
    je .set_math
    cmp al, IR_LCM
    je .set_math
    ; Conv runtime opcodes
    cmp al, IR_TO_BIN_STR
    je .set_conv
    cmp al, IR_TO_HEX_STR
    je .set_conv
    cmp al, IR_TO_OCT_STR
    je .set_conv
    cmp al, IR_ABORT
    je .set_err
    jmp .scan_next

.check_int_const:
    ; Check if IR_OUT_INT's source is a constant LOAD_IMM.
    ; If so, the inline path will be used and rt_pri is not needed.
    push rbx
    push rcx
    push rdx
    movzx ebx, word [r14 + 4] ; src1 vreg of OUT_INT
    mov ecx, r13d              ; start from current record index
    dec ecx                    ; check the record before OUT_INT
.cic_scan:
    cmp ecx, 0
    jl .cic_not_const
    imul edx, ecx, IR_RECORD_SIZE
    lea rdx, [ir_buffer + rdx]
    movzx eax, word [rdx + 2]  ; dst vreg of this record
    cmp eax, ebx
    jne .cic_next
    cmp byte [rdx], IR_LOAD_IMM
    jne .cic_not_const
    test dword [rdx + 24], IR_FLAG_CONST
    jz .cic_not_const
    ; Constant found — inline path will handle it, skip rt_pri
    pop rdx
    pop rcx
    pop rbx
    jmp .scan_next
.cic_next:
    dec ecx
    jmp .cic_scan
.cic_not_const:
    pop rdx
    pop rcx
    pop rbx
    jmp .set_pri

.set_pri:
    mov byte [need_rt_pri], 1
    jmp .scan_next
.set_prs:
    mov byte [need_rt_prs], 1
    jmp .scan_next
.set_prb:
    mov byte [need_rt_prb], 1
    jmp .scan_next
.set_prf:
    mov byte [need_rt_prf], 1
    jmp .scan_next
.set_alloc:
    mov byte [need_rt_alloc], 1
    jmp .scan_next
.set_seq:
    mov byte [need_rt_seq], 1
    jmp .scan_next
.set_seq_alloc:
    mov byte [need_rt_seq], 1
    mov byte [need_rt_alloc], 1
    jmp .scan_next
.set_dict:
    mov byte [need_rt_dict], 1
    jmp .scan_next
.set_dict_alloc:
    mov byte [need_rt_dict], 1
    mov byte [need_rt_alloc], 1
    jmp .scan_next
.set_str:
    mov byte [need_rt_str], 1
    jmp .scan_next
.set_math:
    mov byte [need_rt_math], 1
    jmp .scan_next
.set_conv:
    mov byte [need_rt_conv], 1
    jmp .scan_next
.set_err:
    mov byte [need_rt_err], 1
.scan_next:
    inc r13d
    jmp .scan_loop

.scan_done:
    pop r14
    pop r13
    pop r12
    ret

; Write ELF Headers and Runtime Blobs (modular — only needed functions)
codegen_init:
    mov dword [out_idx], 0
    mov dword [jump_patch_count], 0
    mov dword [proto_patch_count], 0

    ; Initialize label table to 0xFFFFFFFF (unresolved)
    mov ecx, 256
    lea rdi, [label_table]
    mov eax, 0xFFFFFFFF
    rep stosd

    ; Initialize protocol address table to 0xFFFFFFFF (unresolved)
    mov ecx, 256
    lea rdi, [proto_addr_table]
    mov eax, 0xFFFFFFFF
    rep stosd

    ; Scan IR first to determine which runtime functions are needed
    call scan_needed_runtime

    ; 1. Write ELF Header (placeholder — entry point patched later)
    lea rsi, [elf_header]
    mov rcx, elf_header_len
    call emit_block

    ; 2. Write Program Header (placeholder — filesz/memsz patched later)
    lea rsi, [program_header]
    mov rcx, program_header_len
    call emit_block

    ; 3. Track current offset as start of runtime (may be same as code start)
    mov eax, [out_idx]
    mov [rt_total_size], eax

    ; 4. Check if any runtime is needed
    cmp byte [need_rt_pri], 0
    jne .need_jmp
    cmp byte [need_rt_prs], 0
    jne .need_jmp
    cmp byte [need_rt_prb], 0
    jne .need_jmp
    cmp byte [need_rt_prf], 0
    jne .need_jmp
    cmp byte [need_rt_alloc], 0
    jne .need_jmp
    cmp byte [need_rt_seq], 0
    jne .need_jmp
    cmp byte [need_rt_str], 0
    jne .need_jmp
    cmp byte [need_rt_dict], 0
    jne .need_jmp
    cmp byte [need_rt_math], 0
    jne .need_jmp
    cmp byte [need_rt_conv], 0
    jne .need_jmp
    ; No runtime needed — skip JMP, code starts here
    mov eax, LOAD_BASE
    add rax, [out_idx]
    mov [out_buffer + 24], rax  ; patch entry point
    jmp .skip_jmp

.need_jmp:
    ; Emit JMP over runtime (patched after runtime is written)
    mov dil, 0xE9
    call emit_b
    xor edi, edi
    call emit_d    ; placeholder offset (will be patched)

.skip_jmp:

    ; 5. Conditionally embed needed runtime functions (packed, no padding)
    mov dword [rt_pri_off], 0
    mov dword [rt_prs_off], 0
    mov dword [rt_prb_off], 0
    mov dword [rt_prf_off], 0

    cmp byte [need_rt_pri], 0
    je .skip_pri
    mov eax, [out_idx]
    mov [rt_pri_off], eax
    lea rsi, [rt_pri_bin]
    mov rcx, rt_pri_bin_size
    call emit_block
.skip_pri:

    cmp byte [need_rt_prs], 0
    je .skip_prs
    mov eax, [out_idx]
    mov [rt_prs_off], eax
    lea rsi, [rt_prs_bin]
    mov rcx, rt_prs_bin_size
    call emit_block
.skip_prs:

    cmp byte [need_rt_prb], 0
    je .skip_prb
    mov eax, [out_idx]
    mov [rt_prb_off], eax
    lea rsi, [rt_prb_bin]
    mov rcx, rt_prb_bin_size
    call emit_block
.skip_prb:

    cmp byte [need_rt_prf], 0
    je .skip_prf
    mov eax, [out_idx]
    mov [rt_prf_off], eax
    lea rsi, [rt_prf_bin]
    mov rcx, rt_prf_bin_size
    call emit_block
.skip_prf:

    cmp byte [need_rt_alloc], 0
    je .skip_alloc
    mov eax, [out_idx]
    mov [rt_alloc_off], eax
    lea rsi, [rt_alloc_bin]
    mov rcx, rt_alloc_bin_size
    call emit_block
.skip_alloc:

    cmp byte [need_rt_seq], 0
    je .skip_seq
    mov eax, [out_idx]
    mov [rt_seq_off], eax
    lea rsi, [rt_seq_bin]
    mov rcx, rt_seq_bin_size
    call emit_block
.skip_seq:

    cmp byte [need_rt_str], 0
    je .skip_str
    mov eax, [out_idx]
    mov [rt_str_off], eax
    lea rsi, [rt_str_bin]
    mov rcx, rt_str_bin_size
    call emit_block
.skip_str:

    cmp byte [need_rt_dict], 0
    je .skip_dict
    mov eax, [out_idx]
    mov [rt_dict_off], eax
    lea rsi, [rt_dict_bin]
    mov rcx, rt_dict_bin_size
    call emit_block
.skip_dict:

    cmp byte [need_rt_math], 0
    je .skip_math
    mov eax, [out_idx]
    mov [rt_math_off], eax
    lea rsi, [rt_math_bin]
    mov rcx, rt_math_bin_size
    call emit_block
.skip_math:

    cmp byte [need_rt_conv], 0
    je .skip_conv
    mov eax, [out_idx]
    mov [rt_conv_off], eax
    lea rsi, [rt_conv_bin]
    mov rcx, rt_conv_bin_size
    call emit_block
.skip_conv:

    cmp byte [need_rt_err], 0
    je .skip_err
    mov eax, [out_idx]
    mov [rt_err_off], eax
    lea rsi, [rt_err_bin]
    mov rcx, rt_err_bin_size
    call emit_block
.skip_err:

    ; 6. Patch the JMP offset (skip over embedded runtime)
    ; Only patch if a JMP was actually emitted
    cmp byte [need_rt_pri], 0
    jne .patch_jmp
    cmp byte [need_rt_prs], 0
    jne .patch_jmp
    cmp byte [need_rt_prb], 0
    jne .patch_jmp
    cmp byte [need_rt_prf], 0
    jne .patch_jmp
    cmp byte [need_rt_alloc], 0
    jne .patch_jmp
    cmp byte [need_rt_seq], 0
    jne .patch_jmp
    cmp byte [need_rt_str], 0
    jne .patch_jmp
    cmp byte [need_rt_dict], 0
    jne .patch_jmp
    cmp byte [need_rt_math], 0
    jne .patch_jmp
    cmp byte [need_rt_conv], 0
    jne .patch_jmp
    cmp byte [need_rt_err], 0
    jne .patch_jmp
    ; No runtime — entry point already patched, skip JMP patching
    jmp .skip_jmp_patch

.patch_jmp:
    ; JMP rel32: target = out_idx (after runtime), offset = target - current_pos - 5
    mov eax, [out_idx]
    mov edi, eax
    sub edi, HEADERS_SIZE
    ; Patch the JMP offset at offset 121 (right after E9 opcode)
    mov dword [out_buffer + 121], edi

    ; Patch entry point: code starts after runtime
    mov eax, [out_idx]
    add eax, LOAD_BASE
    mov [out_buffer + 24], rax

.skip_jmp_patch:
    ; 7. Compute total runtime size
    mov eax, [out_idx]
    sub eax, HEADERS_SIZE
    mov [rt_total_size], eax

    ; 8. Patch program header filesz/memsz
    mov eax, [out_idx]
    mov [out_buffer + 96], rax
    mov [out_buffer + 104], rax

    ret

; Emit function prologue (frame pointer only when spills need it)
emit_prologue:
    ; sub rsp, aligned_stack_frame (if needed)
    mov eax, [stack_frame_size]
    add eax, 15
    and eax, -16
    test eax, eax
    jz .done
    
    ; Spill slots are RBP-relative ([rbp + negative offset]), so set up a
    ; frame pointer: push rbp; mov rbp, rsp
    mov dil, 0x55
    call emit_b
    mov dil, 0x48
    call emit_b
    mov dil, 0x89
    call emit_b
    mov dil, 0xE5
    call emit_b
    
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
    ; sys_exit(0):
    ; push 60; pop rax (3 bytes instead of 7)
    mov dil, 0x6A
    call emit_b
    mov dil, 60
    call emit_b
    mov dil, 0x58
    call emit_b
    
    ; xor edi, edi (2 bytes instead of 3)
    mov dil, 0x31
    call emit_b
    mov dil, 0xFF
    call emit_b
    
    ; syscall (2 bytes)
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
    ; Runtime blobs and syscalls clobber caller-saved r8-r11, which is exactly
    ; where colours 0-3 live. Preserve all four across the call.
    push rdi
    mov dil, 0x41 ; push r8 = 41 50
    call emit_b
    mov dil, 0x50
    call emit_b
    mov dil, 0x41 ; push r9 = 41 51
    call emit_b
    mov dil, 0x51
    call emit_b
    mov dil, 0x41 ; push r10 = 41 52
    call emit_b
    mov dil, 0x52
    call emit_b
    mov dil, 0x41 ; push r11 = 41 53
    call emit_b
    mov dil, 0x53
    call emit_b
    pop rdi
    ; rel32 = target - current_offset - 5
    mov eax, [out_idx]
    add eax, 5
    sub edi, eax ; edi = rel32
    push rdi     ; save rel32 before emit_b corrupts dil
    mov dil, 0xE8 ; call opcode
    call emit_b
    pop rdi      ; restore rel32
    call emit_d
    ; restore r11-r8
    push rdi
    mov dil, 0x41 ; pop r11 = 41 5B
    call emit_b
    mov dil, 0x5B
    call emit_b
    mov dil, 0x41 ; pop r10 = 41 5A
    call emit_b
    mov dil, 0x5A
    call emit_b
    mov dil, 0x41 ; pop r9 = 41 59
    call emit_b
    mov dil, 0x59
    call emit_b
    mov dil, 0x41 ; pop r8 = 41 58
    call emit_b
    mov dil, 0x58
    call emit_b
    pop rdi
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

    cmp al, IR_MOV
    je cge_mov_op

    cmp al, IR_LOAD_STR
    je .load_str

    cmp al, IR_LOAD_DEREF_BYTE
    je cge_load_deref_byte

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

    cmp al, IR_NEG
    je cge_neg_op

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

    ; Collection operations
    cmp al, IR_SEQ_NEW
    je  cge_seq_new
    cmp al, IR_SEQ_PUSH
    je  cge_seq_push
    cmp al, IR_SEQ_LOAD
    je  cge_seq_load
    cmp al, IR_SEQ_STORE
    je  cge_seq_store
    cmp al, IR_SEQ_LEN
    je  cge_seq_len
    cmp al, IR_SEQ_POP
    je  cge_seq_pop
    cmp al, IR_SEQ_INSERT
    je  cge_seq_insert
    cmp al, IR_SEQ_REMOVE
    je  cge_seq_remove
    cmp al, IR_ARR_NEW
    je  cge_arr_new
    cmp al, IR_ARR_LOAD
    je  cge_arr_load
    cmp al, IR_ARR_STORE
    je  cge_arr_store
    cmp al, IR_DICT_NEW
    je  cge_dict_new
    cmp al, IR_DICT_LOAD
    je  cge_dict_load
    cmp al, IR_DICT_STORE
    je  cge_dict_store
    cmp al, IR_DICT_LEN
    je  cge_dict_len
    cmp al, IR_STR_CONCAT
    je  cge_str_concat
    cmp al, IR_STR_LEN
    je  cge_str_len
    cmp al, IR_STR_CMP
    je  cge_str_cmp

    ; Extended seq operations
    cmp al, IR_SEQ_FIRST
    je  cge_seq_first
    cmp al, IR_SEQ_LAST
    je  cge_seq_last
    cmp al, IR_SEQ_CONTAINS
    je  cge_seq_contains
    cmp al, IR_SEQ_INDEX_OF
    je  cge_seq_index_of
    cmp al, IR_SEQ_COPY
    je  cge_seq_copy
    cmp al, IR_SEQ_REVERSE
    je  cge_seq_reverse
    cmp al, IR_SEQ_SUM
    je  cge_seq_sum
    cmp al, IR_SEQ_MIN
    je  cge_seq_min
    cmp al, IR_SEQ_MAX
    je  cge_seq_max
    cmp al, IR_SEQ_CLEAR
    je  cge_seq_clear
    cmp al, IR_SEQ_CAP
    je  cge_seq_cap
    cmp al, IR_SEQ_COUNT_OF
    je  cge_seq_count_of

    ; Control flow
    cmp al, IR_LABEL
    je  cge_label
    cmp al, IR_JMP
    je  cge_jmp
    cmp al, IR_JCC
    je  cge_jcc
    cmp al, IR_RET
    je  cge_ret

    ; Type casts
    cmp al, IR_CAST_ITF
    je  cge_cast_itf
    cmp al, IR_CAST_FTI
    je  cge_cast_fti
    cmp al, IR_CAST_BTI
    je  cge_cast_bti
    cmp al, IR_CAST_CTI
    je  cge_cast_nop     ; char→int: same register, no-op
    cmp al, IR_CAST_CTB
    je  cge_cast_nop     ; char→byte: same register, no-op
    cmp al, IR_CAST_BCI
    je  cge_cast_nop     ; byte→int: same register, no-op
    cmp al, IR_CAST_BTC
    je  cge_cast_nop     ; byte→char: same register, no-op
    cmp al, IR_NULL_COALESCE
    je  cge_null_coalesce

    ; Extended math
    cmp al, IR_SIN
    je  cge_math_trig_op
    cmp al, IR_COS
    je  cge_math_trig_op
    cmp al, IR_TAN
    je  cge_math_trig_op
    cmp al, IR_POW_F
    je  cge_math_pow_op
    cmp al, IR_CBRT
    je  cge_math_trig_op
    cmp al, IR_SIGNUM_F
    je  cge_signum_f_op
    cmp al, IR_GCD
    je  cge_gcd_op
    cmp al, IR_LCM
    je  cge_lcm_op
    cmp al, IR_TO_BIN_STR
    je  cge_to_bin_str_op
    cmp al, IR_TO_HEX_STR
    je  cge_to_hex_str_op
    cmp al, IR_TO_OCT_STR
    je  cge_to_oct_str_op
    cmp al, IR_SWAP_VARS
    je  cge_swap_vars_op

    ; Protocol subsystem
    cmp al, IR_CALL_ARG
    je  cge_call_arg
    cmp al, IR_CALL
    je  cge_call
    cmp al, IR_PROTO_BEGIN
    je  cge_proto_begin
    cmp al, IR_SAVE_ARG
    je  cge_save_arg
    cmp al, IR_SAVE_LOCAL_VAR
    je  cge_save_local_var
    cmp al, IR_RESTORE_LOCAL_VAR
    je  cge_restore_local_var

    ; Control-flow extensions
    cmp al, IR_WHEN
    je  cge_when
    cmp al, IR_ABORT
    je  cge_abort

.next_ir:
    inc r13d
    jmp .loop

.done:
    ; Resolve all forward jump references
    call resolve_jumps
    ; Resolve protocol call targets
    call resolve_proto_patches
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
    ; Check if imm fits in signed byte (-128 to 127)
    mov rax, [r14 + 8]
    cmp rax, 127
    jg .fit_32_only
    cmp rax, -128
    jl .fit_32_only
    ; Fits in byte: push imm8; pop reg -> 6A xx 41 58+reg
    mov dil, 0x6A
    call emit_b
    mov dil, [r14 + 8]      ; low byte of immediate
    call emit_b
    ; pop reg: 41 58+reg for r8-r15
    mov dil, 0x41
    call emit_b
    mov al, 0x58
    add al, r15b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp .next_ir

.fit_32_only:
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
    cmp al, TYPE_BOOL
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
    cmp al, TYPE_BOOL
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
    ; IR_OUT_*: prints value in src1.
    mov dword [dst_spilled_vreg], 0
    movzx eax, byte [r14 + 1] ; type
    cmp al, TYPE_INT
    jne .output_val_runtime
    ; Check if src1 is defined by IR_LOAD_IMM with constant flag
    movzx eax, word [r14 + 4] ; src1 vreg
    ; Scan backwards through IR to find definition
    push rbx
    push rcx
    push rdx
    mov ebx, eax
    mov ecx, [ir_count]
    test ecx, ecx
    jz .output_inline_miss
    dec ecx
.fc_scan:
    cmp ecx, 0
    jl .output_inline_miss
    imul edx, ecx, IR_RECORD_SIZE
    lea rdx, [ir_buffer + rdx]
    movzx eax, word [rdx + 2]
    cmp eax, ebx
    jne .fc_next
    cmp byte [rdx], IR_LOAD_IMM
    jne .output_inline_miss
    test dword [rdx + 24], IR_FLAG_CONST
    jz .output_inline_miss
    mov rax, [rdx + 8]      ; constant value
    pop rdx
    pop rcx
    pop rbx
    ; rax = constant integer. Emit inline sys_write.
    push rax                ; save constant value
    ; Convert int to string on stack
    sub rsp, 24             ; space for string (21 bytes)
    lea rdi, [rsp]
    ; int_to_str: rax=value, rdi=buffer -> rax=len, rdi=start
    push rbx
    push rcx
    push rdx
    push rsi
    mov rsi, rdi
    add rsi, 20
    mov byte [rsi], 10      ; newline
    mov rcx, 1
    test rax, rax
    jnz .its_go
    dec rsi
    mov byte [rsi], '0'
    inc rcx
    jmp .its_end
.its_go:
    mov rbx, rax
    test rax, rax
    jns .its_pos
    neg rax
.its_pos:
.its_dig:
    xor rdx, rdx
    mov r10, 10
    div r10
    add dl, '0'
    dec rsi
    mov [rsi], dl
    inc rcx
    test rax, rax
    jnz .its_dig
    test rbx, rbx
    jns .its_end
    dec rsi
    mov byte [rsi], '-'
    inc rcx
.its_end:
    mov rax, rcx            ; length
    mov rdi, rsi            ; string start
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ; rax = string length, rdi = string start
    mov r8, rax             ; r8 = length
    mov r9, rdi             ; r9 = string start (on stack)
    
    ; Build the syscall sequence + string in a fixed 64-byte stack buffer
    sub rsp, 64
    mov r10, rsp            ; r10 = buffer
    
    ; Start with JMP rel32 over string (5 bytes)
    mov byte [r10], 0xE9
    mov eax, r8d            ; displacement = string length
    mov [r10 + 1], eax
    lea rdi, [r10 + 5]     ; destination after JMP
    
    ; Copy string bytes to buffer after JMP
    mov rsi, r9
    mov rcx, r8
    rep movsb
    
    ; Append LEA RSI, [RIP - (len+7)]
    mov byte [rdi], 0x48
    mov byte [rdi+1], 0x8D
    mov byte [rdi+2], 0x35
    mov eax, r8d
    add eax, 7
    neg eax
    mov [rdi+3], eax
    add rdi, 7
    
    ; Append MOV RDX, len (optimized: push imm8; pop rdx for small values)
    mov byte [rdi], 0x6A
    mov al, r8b             ; low byte of length
    mov [rdi+1], al
    mov byte [rdi+2], 0x5A
    add rdi, 3
    
    ; Append MOV RAX, 1 (optimized: push 1; pop rax)
    mov byte [rdi], 0x6A
    mov byte [rdi+1], 0x01
    mov byte [rdi+2], 0x58
    add rdi, 3
    
    ; Append MOV RDI, 1 (optimized: push 1; pop rdi)
    mov byte [rdi], 0x6A
    mov byte [rdi+1], 0x01
    mov byte [rdi+2], 0x5F
    add rdi, 3
    
    ; Append SYSCALL
    mov byte [rdi], 0x0F
    mov byte [rdi+1], 0x05
    
    ; Emit the entire block
    mov rsi, r10
    lea rcx, [r8 + 23]     ; 5 JMP + string_len + 18 bytes of instructions
    call emit_block
    
    ; Cleanup: restore buffer + saved rax
    add rsp, 64
    add rsp, 24             ; cleanup string buffer
    pop rax
    jmp .next_ir

.fc_next:
    dec ecx
    jmp .fc_scan
.output_inline_miss:
    pop rdx
    pop rcx
    pop rbx
    ; Fall through to runtime path

.output_val_runtime:
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
    mov edi, [rt_pri_off]
    call emit_runtime_call
    jmp .next_ir     ; dst_spilled_vreg already cleared in .output_val
.call_prs:
    mov edi, [rt_prs_off]
    call emit_runtime_call
    jmp .next_ir
.call_prb:
    mov edi, [rt_prb_off]
    call emit_runtime_call
    jmp .next_ir
.call_prc:
    ; Inline syscall: write(1, &rsp, 1) — no runtime blob needed
    ; push rdi (save char on stack for write buffer)
    mov dil, 0x57
    call emit_b
    ; mov eax, 1 (SYS_write)
    mov dil, 0xB8
    call emit_b
    xor edi, edi
    inc edi             ; edi = 1
    call emit_d
    ; mov edi, 1 (fd = stdout)
    mov dil, 0xBF
    call emit_b
    xor edi, edi
    inc edi
    call emit_d
    ; mov rsi, rsp (buf = &char on stack)
    mov dil, 0x48
    call emit_b
    mov dil, 0x89
    call emit_b
    mov dil, 0xE6
    call emit_b
    ; mov edx, 1 (count = 1)
    mov dil, 0xBA
    call emit_b
    xor edi, edi
    inc edi
    call emit_d
    ; syscall
    mov dil, 0x0F
    call emit_b
    mov dil, 0x05
    call emit_b
    ; pop rdi (restore stack)
    mov dil, 0x5F
    call emit_b
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
    
    mov edi, [rt_prf_off]
    call emit_runtime_call
    jmp .next_ir     ; dst_spilled_vreg already cleared in .output_val

.halt:
    ; IR_HALT: no dst vreg — clear dst_spilled_vreg (Bug 3 fix)
    mov dword [dst_spilled_vreg], 0   ; <-- Bug 3 fix
    call emit_epilogue_and_exit
    jmp codegen_emit_all.next_ir

; ============ New handler functions (outside codegen_emit_all for label scoping) ============

cge_mov_op:
    ; IR_MOV: dst = src1 (register copy). If both resolve to the same
    ; physical register, emit nothing (the allocator's copy-coalescing
    ; usually assigns the same colour, eliminating the move entirely).
    movzx eax, word [r14 + 2] ; dst vreg
    call get_dst_phys         ; al = dst phys (sets dst_spilled_vreg if spilled)
    mov r15b, al              ; dst phys
    movzx eax, word [r14 + 4] ; src1 vreg
    call load_src1_phys       ; al = src1 phys (r14 if spilled)
    cmp r15b, al
    je .skip                  ; same register — nothing to emit
    ; mov r_dst, r_src with phys values 0-7 mapping to r8-r15:
    ; 4D 89 /r, ModRM = 0xC0 | (src&7)<<3 | (dst&7)
    ; (REX.W|R|B: phys n -> r8+n, so 6 -> r14 and 7 -> r15 spill temps)
    mov dil, 0x4D
    call emit_b
    mov dil, 0x89
    call emit_b
    movzx ebx, al             ; src phys
    movzx edx, r15b           ; dst phys
    mov al, bl
    and al, 7
    shl al, 3
    mov dl, dl
    and dl, 7
    or al, dl
    or al, 0xC0
    mov dil, al
    call emit_b
.skip:
    call store_dst_spill
    jmp codegen_emit_all.next_ir

cge_load_deref_byte:
    ; IR_LOAD_DEREF_BYTE: dst = byte at [src1 + imm]
    ; src1 = pointer vreg, imm = offset
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]  ; src1 vreg (pointer)
    call load_src1_phys
    mov r15b, al                ; pointer phys
    movzx eax, word [r14 + 2]  ; dst vreg
    call get_dst_phys
    mov r8b, al                 ; dst phys

    ; Move pointer to rdi
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b

    ; Move offset to rsi
    movzx eax, word [r14 + 8]  ; imm = offset
    mov dil, 0x48
    call emit_b
    mov dil, 0xC7
    call emit_b
    mov dil, 0xC6
    call emit_b
    mov edi, eax
    call emit_d

    ; Call rt_deref_byte
    mov edi, [rt_str_off]
    add edi, 0xBE  ; rt_deref_byte offset
    call emit_runtime_call

    ; Store result (rax) to dst
    mov dil, 0x49
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp codegen_emit_all.next_ir

cge_str_cmp:
    ; IR_STR_CMP: dst = strcmp(str1, str2)
    ; src1 = str1 pointer, src2 = str2 pointer
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]  ; src1 vreg (str1)
    call load_src1_phys
    mov r15b, al                ; src1 phys
    movzx eax, word [r14 + 6]  ; src2 vreg (str2)
    call load_src2_phys
    mov r9b, al                 ; src2 phys
    movzx eax, word [r14 + 2]  ; dst vreg
    call get_dst_phys
    mov r8b, al                 ; dst phys

    ; Move str1 to rdi
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b

    ; Move str2 to rsi
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r9b
    shl al, 3
    or al, 0xC6
    mov dil, al
    call emit_b

    ; Call rt_str_compare
    mov edi, [rt_str_off]
    add edi, 0x9D  ; rt_str_compare offset
    call emit_runtime_call

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
    jmp codegen_emit_all.next_ir

cge_seq_count_of:
    ; IR_SEQ_COUNT_OF: dst = count of value in seq
    ; src1 = seq pointer, src2 = value, imm = element size
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]  ; src1 vreg (seq pointer)
    call load_src1_phys
    mov r15b, al                ; src1 phys
    movzx eax, word [r14 + 6]  ; src2 vreg (value to count)
    call load_src2_phys
    mov r9b, al                 ; src2 phys
    movzx eax, word [r14 + 2]  ; dst vreg
    call get_dst_phys
    mov r8b, al                 ; dst phys

    ; Move seq pointer to rdi
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b

    ; Move value to rsi
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r9b
    shl al, 3
    or al, 0xC6
    mov dil, al
    call emit_b

    ; Move element size to rdx (imm field)
    movzx eax, word [r14 + 8]
    mov dil, 0x48
    call emit_b
    mov dil, 0xC7
    call emit_b
    mov dil, 0xC2
    call emit_b
    mov edi, eax
    call emit_d

    ; Call rt_seq_count_of
    mov edi, [rt_seq_off]
    add edi, 0x4D3  ; rt_seq_count_of offset
    call emit_runtime_call

    ; Store result (rax) to dst
    mov dil, 0x49
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp codegen_emit_all.next_ir

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

; ── IR_NEG ──────────────────────────────────────────────
cge_neg_op:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]  ; src1 vreg
    call load_src1_phys
    mov r15b, al                ; src1 phys
    movzx eax, word [r14 + 2]  ; dst vreg
    call get_dst_phys
    mov r8b, al                 ; dst phys
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
    ; neg r(dst): 49 F7 D8+dst
    mov dil, 0x49
    call emit_b
    mov dil, 0xF7
    call emit_b
    mov al, 0xD8
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp codegen_emit_all.next_ir

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
; Fusion: if the next IR record is IR_JCC(src1==this.dst, COND_NE),
; emit `cmp; j<inverse>` and skip bool materialization entirely.
cge_cmp_bool_op:
    ; ── Peek next record for comparison fusion ──
    mov eax, r13d
    inc eax
    cmp eax, r12d
    jae .no_fusion
    imul ecx, eax, IR_RECORD_SIZE
    lea rbx, [ir_buffer + rcx]      ; rbx = next record ptr
    movzx ecx, byte [rbx]
    cmp cl, IR_JCC
    jne .no_fusion
    ; next.src1 must equal this.dst
    movzx ecx, word [rbx + 4]
    movzx edx, word [r14 + 2]
    cmp cx, dx
    jne .no_fusion
    ; next.aux must be COND_NE (jump when bool != true)
    movzx ecx, byte [rbx + 16]
    cmp cl, COND_NE
    jne .no_fusion
    ; dst vreg must not be used by any record AFTER the JCC
    movzx edx, word [r14 + 2]
    mov r15d, r13d
    add r15d, 2
.fuse_scan:
    cmp r15d, r12d
    jae .fuse_ok
    imul ecx, r15d, IR_RECORD_SIZE
    lea rdi, [ir_buffer + rcx]
    movzx ecx, word [rdi + 4]
    cmp cx, dx
    je .no_fusion
    movzx ecx, word [rdi + 6]
    cmp cx, dx
    je .no_fusion
    inc r15d
    jmp .fuse_scan
.fuse_ok:
    mov ecx, [rbx + 8]              ; JCC imm = target label
    mov [fused_jcc_target], ecx
    mov byte [fuse_pending], 1
    jmp .fuse_shared
.no_fusion:
    mov byte [fuse_pending], 0
.fuse_shared:
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
    ; If fused with a following JCC, skip setcc + bool conversion entirely
    ; and emit the inverted jump directly (cmp was already emitted above).
    cmp byte [fuse_pending], 1
    je  cge_cmp_fused_jcc_int
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
    ; If fused with a following JCC, emit the inverted jump directly.
    cmp byte [fuse_pending], 1
    je  cge_cmp_fused_jcc_flt
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

; ── FUSED CMP→JCC ──────────────────────────────────────
; The `cmp` (int) or `ucomisd` (float) instruction was already emitted by
; the caller. Here we emit `j<inverse>` using the inverted-opcode tables,
; targeting fused_jcc_target. We also must skip the following IR_JCC record.
cge_cmp_fused_jcc_int:
    movzx eax, byte [r14 + 16]  ; aux = cond code (0-5)
    cmp eax, 5
    ja  cge_cmp_fused_jcc_done  ; out of range: nothing to emit
    ; Select inverted long opcode (0F 8x) or short (7x) form
    mov ecx, [fused_jcc_target]
    cmp ecx, 256
    jae .fused_long
    mov edx, [label_table + rcx * 4]
    cmp edx, 0xFFFFFFFF
    je .fused_long
    ; Resolved — try short Jcc: 7x rel8
    mov ebx, [out_idx]
    add ebx, 2
    sub edx, ebx
    cmp edx, -128
    jl .fused_long
    cmp edx, 127
    jg .fused_long
    ; short Jcc
    lea rsi, [rel cmp_int_fused_jcc8]
    movzx eax, byte [rsi + rax]
    mov dil, al
    call emit_b
    mov dil, dl
    call emit_b
    jmp cge_cmp_fused_jcc_done
.fused_long:
    ; 0F 8x rel32
    lea rsi, [rel cmp_int_fused_jcc]
    movzx eax, byte [rsi + rax]
    push rax
    mov dil, 0x0F
    call emit_b
    pop rax
    mov dil, al
    call emit_b
    ; Record patch: out_idx, target label
    mov ecx, [out_idx]
    mov edx, [jump_patch_count]
    cmp edx, 128
    jae .fused_nopatch
    mov [jump_patches + rdx * 8], ecx
    mov eax, [fused_jcc_target]
    mov [jump_patches + rdx * 8 + 4], eax
    inc dword [jump_patch_count]
.fused_nopatch:
    xor edi, edi
    call emit_d
cge_cmp_fused_jcc_done:
    ; Skip the following IR_JCC record (fusion consumed it)
    inc r13d
    jmp codegen_emit_all.next_ir

cge_cmp_fused_jcc_flt:
    movzx eax, byte [r14 + 16]
    cmp eax, 5
    ja  cge_cmp_fused_jcc_done
    mov ecx, [fused_jcc_target]
    cmp ecx, 256
    jae .ff_long
    mov edx, [label_table + rcx * 4]
    cmp edx, 0xFFFFFFFF
    je .ff_long
    mov ebx, [out_idx]
    add ebx, 2
    sub edx, ebx
    cmp edx, -128
    jl .ff_long
    cmp edx, 127
    jg .ff_long
    lea rsi, [rel cmp_flt_fused_jcc8]
    movzx eax, byte [rsi + rax]
    mov dil, al
    call emit_b
    mov dil, dl
    call emit_b
    jmp cge_cmp_fused_jcc_done
.ff_long:
    lea rsi, [rel cmp_flt_fused_jcc]
    movzx eax, byte [rsi + rax]
    push rax
    mov dil, 0x0F
    call emit_b
    pop rax
    mov dil, al
    call emit_b
    mov ecx, [out_idx]
    mov edx, [jump_patch_count]
    cmp edx, 128
    jae .ff_nopatch
    mov [jump_patches + rdx * 8], ecx
    mov eax, [fused_jcc_target]
    mov [jump_patches + rdx * 8 + 4], eax
    inc dword [jump_patch_count]
.ff_nopatch:
    xor edi, edi
    call emit_d
    jmp cge_cmp_fused_jcc_done

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
    mov rcx, [out_idx]
    mov [out_buffer + 96], rcx

    ; Patch memsz at offset 64 + 40 = 104
    ; memsz covers code size + variables storage (VAR_MEM_OFFSET)
    add rcx, VAR_MEM_OFFSET
    mov [out_buffer + 104], rcx
    ret

; ============ Type Cast Codegen ============

; IR_CAST_ITF: int → float (cvtsi2sd)
cge_cast_itf:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]  ; src1 vreg
    call load_src1_phys
    mov r15b, al                ; src1 phys
    movzx eax, word [r14 + 2]  ; dst vreg
    call get_dst_phys
    mov r8b, al                 ; dst phys
    ; cvtsi2sd xmm0, r(src1)
    mov dil, 0xF2
    call emit_b
    mov dil, 0x49              ; REX.WB (src1 may be r8-r15)
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x2A
    call emit_b
    mov al, 0xC0
    or al, r15b
    mov dil, al
    call emit_b
    ; movq r(dst), xmm0
    mov dil, 0x66
    call emit_b
    mov dil, 0x49              ; REX.WB (dst may be r8-r15)
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x7E
    call emit_b
    mov al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp codegen_emit_all.next_ir

; IR_CAST_FTI: float → int (cvttsd2si, truncate toward zero)
cge_cast_fti:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]  ; src1 vreg
    call load_src1_phys
    mov r15b, al                ; src1 phys
    movzx eax, word [r14 + 2]  ; dst vreg
    call get_dst_phys
    mov r8b, al                 ; dst phys
    ; movq xmm0, r(src1) — needs REX.WB since src1 may be r8-r15
    mov dil, 0x66
    call emit_b
    mov dil, 0x49              ; REX.WB (src1 may be r8-r15)
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x6E
    call emit_b
    mov al, 0xC0
    or al, r15b
    mov dil, al
    call emit_b
    ; cvttsd2si rax, xmm0 — REX.W only (xmm0 doesn't need REX.B)
    mov dil, 0xF2
    call emit_b
    mov dil, 0x48              ; REX.W only
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x2C
    call emit_b
    mov dil, 0xC0              ; rax, xmm0
    call emit_b
    ; mov r(dst), rax: 49 89 C0 + dst
    mov dil, 0x49
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp codegen_emit_all.next_ir

; IR_CAST_BTI: bool → int (sign-extend: positive→1, zero→0, negative→-1)
cge_cast_bti:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]  ; src1 vreg
    call load_src1_phys
    mov r15b, al                ; src1 phys
    movzx eax, word [r14 + 2]  ; dst vreg
    call get_dst_phys
    mov r8b, al                 ; dst phys
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
    jmp codegen_emit_all.next_ir

; Cast no-op: same register, just copy to dst if needed
cge_cast_nop:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]  ; src1 vreg
    call load_src1_phys
    mov r15b, al                ; src1 phys
    movzx eax, word [r14 + 2]  ; dst vreg
    call get_dst_phys
    mov r8b, al                 ; dst phys
    cmp r8b, r15b
    je .nop_done
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
.nop_done:
    call store_dst_spill
    jmp codegen_emit_all.next_ir

; ============ Collection Operations ============

; IR_SEQ_NEW: allocate seq, dst = pointer to seq header
; imm = capacity (number of elements), aux = element size
cge_seq_new:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 2]  ; dst vreg
    call get_dst_phys
    mov r8b, al                 ; dst phys

    ; Emit: mov rdi, element_size
    movzx eax, word [r14 + 16] ; aux = element size
    mov dil, 0x48
    call emit_b
    mov dil, 0xC7
    call emit_b
    mov dil, 0xC7
    call emit_b
    mov edi, eax
    call emit_d

    ; Emit: mov rsi, capacity
    mov rax, [r14 + 8]          ; imm = capacity
    mov dil, 0x48
    call emit_b
    mov dil, 0xC7
    call emit_b
    mov dil, 0xC6
    call emit_b
    mov edi, eax
    call emit_d

    ; Call rt_seq_new
    mov edi, [rt_seq_off]
    call emit_runtime_call

    ; mov r(dst), rax (result)
    mov dil, 0x49
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp codegen_emit_all.next_ir

; IR_SEQ_PUSH: seq_push(seq, value) — void operation
; src1 = seq pointer, src2 = value, imm = element size
cge_seq_push:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]  ; src1 vreg (seq pointer)
    call load_src1_phys
    mov r15b, al                ; src1 phys
    movzx eax, word [r14 + 6]  ; src2 vreg (value)
    call load_src2_phys
    mov r9b, al                 ; src2 phys

    ; Move seq pointer to rdi
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b

    ; Move value to rsi
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r9b
    shl al, 3
    or al, 0xC6
    mov dil, al
    call emit_b

    ; Move element size to rdx
    movzx rax, word [r14 + 8]  ; imm = element size
    mov dil, 0x48
    call emit_b
    mov dil, 0xC7
    call emit_b
    mov dil, 0xC2
    call emit_b
    mov edi, eax
    call emit_d

    ; Call rt_seq_push
    mov edi, [rt_seq_off]
    add edi, 0x4C   ; offset to rt_seq_push
    call emit_runtime_call
    jmp codegen_emit_all.next_ir

; IR_SEQ_LOAD: dst = seq[index]
; src1 = seq pointer, src2 = index, aux = element size
cge_seq_load:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]  ; src1 vreg (seq pointer)
    call load_src1_phys
    mov r15b, al                ; src1 phys
    movzx eax, word [r14 + 6]  ; src2 vreg (index)
    call load_src2_phys
    mov r9b, al                 ; src2 phys
    movzx eax, word [r14 + 2]  ; dst vreg
    call get_dst_phys
    mov r8b, al                 ; dst phys

    ; Move seq pointer to rdi
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b

    ; Move index to rsi
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r9b
    shl al, 3
    or al, 0xC6
    mov dil, al
    call emit_b

    ; Move element size to rdx
    movzx rax, word [r14 + 8]  ; imm = element size
    mov dil, 0x48
    call emit_b
    mov dil, 0xC7
    call emit_b
    mov dil, 0xC2
    call emit_b
    mov edi, eax
    call emit_d

    ; Call rt_seq_get
    mov edi, [rt_seq_off]
    add edi, 0xD7  ; offset to rt_seq_get
    call emit_runtime_call

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
    jmp codegen_emit_all.next_ir

; IR_SEQ_STORE: seq[index] = value
; src1 = seq pointer, src2 = index, aux = value vreg, imm = element size
cge_seq_store:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]  ; src1 vreg (seq pointer)
    call load_src1_phys
    mov r15b, al                ; src1 phys
    movzx eax, word [r14 + 6]  ; src2 vreg (index)
    call load_src2_phys
    mov r9b, al                 ; src2 phys

    ; Move seq pointer to rdi
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b

    ; Move index to rsi
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r9b
    shl al, 3
    or al, 0xC6
    mov dil, al
    call emit_b

    ; Load aux vreg (value) — inline vreg_phys lookup
    movzx rax, word [r14 + 16]  ; aux = value vreg number
    movzx rax, byte [vreg_phys + rax]
    cmp al, 255
    jne .cge_seq_store_val_ok
    ; Spilled — reload into r14 (safe: seq already moved to rdi)
    mov dil, 0x4C
    call emit_b
    mov dil, 0x8B
    call emit_b
    mov dil, 0xB5
    call emit_b
    push r9
    movzx rbx, word [r14 + 16]
    mov edi, dword [vreg_offset + rbx * 4]
    call emit_d
    pop r9
    mov al, 6  ; r14
.cge_seq_store_val_ok:
    mov r10b, al                ; value phys

    ; Move value to rdx
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r10b
    shl al, 3
    or al, 0xC2
    mov dil, al
    call emit_b

    ; Move element size to rcx
    movzx rax, word [r14 + 8]  ; imm = element size
    mov dil, 0x48
    call emit_b
    mov dil, 0xC7
    call emit_b
    mov dil, 0xC1
    call emit_b
    mov edi, eax
    call emit_d

    ; Call rt_seq_set
    mov edi, [rt_seq_off]
    add edi, 0xEE ; offset to rt_seq_set
    call emit_runtime_call
    jmp codegen_emit_all.next_ir

; IR_SEQ_LEN: dst = len(seq)
; src1 = seq pointer
cge_seq_len:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]  ; src1 vreg (seq pointer)
    call load_src1_phys
    mov r15b, al                ; src1 phys
    movzx eax, word [r14 + 2]  ; dst vreg
    call get_dst_phys
    mov r8b, al                 ; dst phys

    ; Move seq pointer to rdi
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b

    ; Call rt_seq_len
    mov edi, [rt_seq_off]
    add edi, 0x105 ; offset to rt_seq_len
    call emit_runtime_call

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
    jmp codegen_emit_all.next_ir

; IR_SEQ_POP: dst = pop(seq)
; src1 = seq pointer, imm = element size
cge_seq_pop:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]  ; src1 vreg (seq pointer)
    call load_src1_phys
    mov r15b, al                ; src1 phys
    movzx eax, word [r14 + 2]  ; dst vreg
    call get_dst_phys
    mov r8b, al                 ; dst phys

    ; Move seq pointer to rdi
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b

    ; Move element size to rsi
    movzx rax, word [r14 + 8]  ; imm = element size
    mov dil, 0x48
    call emit_b
    mov dil, 0xC7
    call emit_b
    mov dil, 0xC6
    call emit_b
    mov edi, eax
    call emit_d

    ; Call rt_seq_pop
    mov edi, [rt_seq_off]
    add edi, 0x10B ; offset to rt_seq_pop
    call emit_runtime_call

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
    jmp codegen_emit_all.next_ir

; IR_SEQ_INSERT: seq.insert(index, value) — void
; src1 = seq pointer, src2 = index, aux = value vreg, imm = element size
cge_seq_insert:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]  ; src1 vreg (seq pointer)
    call load_src1_phys
    mov r15b, al                ; src1 phys
    movzx eax, word [r14 + 6]  ; src2 vreg (index)
    call load_src2_phys
    mov r9b, al                 ; src2 phys

    ; Move seq pointer to rdi
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b

    ; Move index to rsi
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r9b
    shl al, 3
    or al, 0xC6
    mov dil, al
    call emit_b

    ; Load aux vreg (value) — inline vreg_phys lookup
    movzx rax, word [r14 + 16]  ; aux = value vreg number
    movzx rax, byte [vreg_phys + rax]
    cmp al, 255
    jne .cge_seq_insert_val_ok
    mov dil, 0x4C
    call emit_b
    mov dil, 0x8B
    call emit_b
    mov dil, 0xB5
    call emit_b
    push r9
    movzx rbx, word [r14 + 16]
    mov edi, dword [vreg_offset + rbx * 4]
    call emit_d
    pop r9
    mov al, 6
.cge_seq_insert_val_ok:
    mov r10b, al                ; value phys

    ; Move value to rdx
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r10b
    shl al, 3
    or al, 0xC2
    mov dil, al
    call emit_b

    ; Move element size to rcx
    movzx rax, word [r14 + 8]  ; imm = element size
    mov dil, 0x48
    call emit_b
    mov dil, 0xC7
    call emit_b
    mov dil, 0xC1
    call emit_b
    mov edi, eax
    call emit_d

    ; Call rt_seq_insert
    mov edi, [rt_seq_off]
    add edi, 0x134  ; offset to rt_seq_insert
    call emit_runtime_call
    jmp codegen_emit_all.next_ir

; IR_SEQ_REMOVE: dst = seq.remove(index)
; src1 = seq pointer, src2 = index, imm = element size
cge_seq_remove:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]  ; src1 vreg (seq pointer)
    call load_src1_phys
    mov r15b, al                ; src1 phys
    movzx eax, word [r14 + 6]  ; src2 vreg (index)
    call load_src2_phys
    mov r9b, al                 ; src2 phys
    movzx eax, word [r14 + 2]  ; dst vreg
    call get_dst_phys
    mov r8b, al                 ; dst phys

    ; Move seq pointer to rdi
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b

    ; Move index to rsi
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r9b
    shl al, 3
    or al, 0xC6
    mov dil, al
    call emit_b

    ; Move element size to rdx
    movzx rax, word [r14 + 8]  ; imm = element size
    mov dil, 0x48
    call emit_b
    mov dil, 0xC7
    call emit_b
    mov dil, 0xC2
    call emit_b
    mov edi, eax
    call emit_d

    ; Call rt_seq_remove
    mov edi, [rt_seq_off]
    add edi, 0x202  ; offset to rt_seq_remove
    call emit_runtime_call

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
    jmp codegen_emit_all.next_ir

; ============ Array Operations ============

; IR_ARR_NEW: dst = stack-allocated array of N elements
; imm = total size in bytes (N * elem_size), aux = element size
cge_arr_new:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 2]  ; dst vreg
    call get_dst_phys
    mov r8b, al                 ; dst phys
    ; Allocate space: SUB RSP, imm
    movzx eax, word [r14 + 8]  ; imm = total size
    ; emit: sub rsp, size (48 83 EC xx for small, 48 81 EC xx xx xx xx for large)
    cmp eax, 127
    ja .arr_new_large
    ; Small: sub rsp, imm8
    mov dil, 0x48; call emit_b
    mov dil, 0x83; call emit_b
    mov dil, 0xEC; call emit_b
    mov dil, al; call emit_b
    jmp .arr_new_set_ptr
.arr_new_large:
    ; Large: sub rsp, imm32
    mov dil, 0x48; call emit_b
    mov dil, 0x81; call emit_b
    mov dil, 0xEC; call emit_b
    mov edi, eax; call emit_d
.arr_new_set_ptr:
    ; dst = RSP (lea r(dst), [rsp])
    mov dil, 0x4C; call emit_b
    mov dil, 0x8D; call emit_b
    mov al, r8b
    shl al, 3
    or al, 0x04  ; SIB byte follows
    mov dil, al; call emit_b
    mov dil, 0x24; call emit_b  ; SIB: base=RSP
    call store_dst_spill
    jmp codegen_emit_all.next_ir

; IR_ARR_LOAD: dst = arr[index]
; src1 = array base vreg, src2 = index vreg, aux = element size
cge_arr_load:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]  ; src1 vreg (array base)
    call load_src1_phys
    mov r15b, al                ; array base phys
    movzx eax, word [r14 + 6]  ; src2 vreg (index)
    call load_src2_phys
    mov r9b, al                 ; index phys
    movzx eax, word [r14 + 2]  ; dst vreg
    call get_dst_phys
    mov r8b, al                 ; dst phys
    ; emit: mov r(dst), [r(base) + r(index) * elem_size]
    ; REX.W + 8B + ModRM(mod=00, reg=dst, rm=100) + SIB(scale, index, base)
    mov dil, 0x4C; call emit_b
    mov dil, 0x8B; call emit_b
    ; ModRM: mod=00, reg=dst, rm=100 (SIB follows)
    mov al, r8b
    shl al, 3
    or al, 0x04
    mov dil, al; call emit_b
    ; SIB: scale = log2(elem_size), index, base
    movzx eax, word [r14 + 16] ; aux = element size
    ; Compute scale: 1->0, 2->1, 4->2, 8->3
    xor ecx, ecx
    cmp eax, 2
    jl .arr_load_scale_0
    je .arr_load_scale_1
    cmp eax, 4
    je .arr_load_scale_2
    mov cl, 3  ; scale 8
    jmp .arr_load_scale_done
.arr_load_scale_2:
    mov cl, 2
    jmp .arr_load_scale_done
.arr_load_scale_1:
    mov cl, 1
.arr_load_scale_0:
.arr_load_scale_done:
    shl cl, 6  ; scale in bits 7-6
    mov al, r9b ; index reg
    shl al, 3
    or cl, al
    or cl, r15b ; base reg
    mov dil, cl; call emit_b
    call store_dst_spill
    jmp codegen_emit_all.next_ir

; IR_ARR_STORE: arr[index] = value
; src1 = array base vreg, src2 = index vreg, aux = (elem_size | (value_vreg << 16))
; For store, we use the aux field differently: lower 16 = elem_size, upper 16 = value vreg
cge_arr_store:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]  ; src1 vreg (array base)
    call load_src1_phys
    mov r15b, al                ; base phys
    movzx eax, word [r14 + 6]  ; src2 vreg (index)
    call load_src2_phys
    mov r9b, al                 ; index phys
    ; Load value vreg from aux high word
    movzx rax, word [r14 + 18] ; aux high 16 bits = value vreg
    movzx rax, byte [vreg_phys + rax]
    cmp al, 255
    jne .arr_store_val_ok
    ; Value is spilled — load from stack into r10
    movzx r10, word [r14 + 18]
    mov dil, 0x4C; call emit_b
    mov dil, 0x8B; call emit_b
    mov dil, 0x95; call emit_b  ; ModRM: mod=10, reg=r10, rm=rbp
    movzx rbx, word [r14 + 18]
    mov edi, dword [vreg_offset + rbx * 4]
    call emit_d
    mov r10b, 2  ; r10 is phys reg 2
    jmp .arr_store_emit
.arr_store_val_ok:
    mov r10b, al                ; value phys
.arr_store_emit:
    ; emit: mov [r(base) + r(index) * elem_size], r(value)
    mov dil, 0x4C; call emit_b
    mov dil, 0x89; call emit_b
    mov al, r10b
    shl al, 3
    or al, 0x04
    mov dil, al; call emit_b
    ; SIB
    movzx eax, word [r14 + 16] ; elem_size
    xor ecx, ecx
    cmp eax, 2
    jl .arr_store_scale_0
    je .arr_store_scale_1
    cmp eax, 4
    je .arr_store_scale_2
    mov cl, 3
    jmp .arr_store_scale_done
.arr_store_scale_2:
    mov cl, 2
    jmp .arr_store_scale_done
.arr_store_scale_1:
    mov cl, 1
.arr_store_scale_0:
.arr_store_scale_done:
    shl cl, 6
    mov al, r9b
    shl al, 3
    or cl, al
    or cl, r15b
    mov dil, cl; call emit_b
    jmp codegen_emit_all.next_ir

; ============ Dict Operations ============

; IR_DICT_NEW: allocate dict, dst = pointer to dict header
; imm = initial capacity, aux = element type (unused for now)
cge_dict_new:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 2]  ; dst vreg
    call get_dst_phys
    mov r8b, al                 ; dst phys

    ; Emit: mov rdi, capacity
    mov rax, [r14 + 8]          ; imm = capacity
    mov dil, 0x48
    call emit_b
    mov dil, 0xC7
    call emit_b
    mov dil, 0xC7
    call emit_b
    mov edi, eax
    call emit_d

    ; Call rt_dict_new
    mov edi, [rt_dict_off]
    call emit_runtime_call

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
    jmp codegen_emit_all.next_ir

; IR_DICT_LOAD: dst = dict[key]
; src1 = dict pointer, src2 = key vreg
cge_dict_load:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]  ; src1 vreg (dict pointer)
    call load_src1_phys
    mov r15b, al                ; src1 phys
    movzx eax, word [r14 + 6]  ; src2 vreg (key)
    call load_src2_phys
    mov r9b, al                 ; src2 phys
    movzx eax, word [r14 + 2]  ; dst vreg
    call get_dst_phys
    mov r8b, al                 ; dst phys

    ; Push caller-saved regs that the register allocator may have assigned
    mov dil, 0x51               ; push rcx
    call emit_b
    mov dil, 0x52               ; push rdx
    call emit_b
    mov dil, 0x41
    call emit_b
    mov dil, 0x50               ; push r8
    call emit_b
    mov dil, 0x41
    call emit_b
    mov dil, 0x51               ; push r9
    call emit_b
    mov dil, 0x41
    call emit_b
    mov dil, 0x52               ; push r10
    call emit_b
    mov dil, 0x41
    call emit_b
    mov dil, 0x53               ; push r11
    call emit_b

    ; Move dict pointer to rdi
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b

    ; Move key to rsi
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r9b
    shl al, 3
    or al, 0xC6
    mov dil, al
    call emit_b

    ; Call rt_dict_get
    mov edi, [rt_dict_off]
    add edi, 0x8C  ; offset to rt_dict_get
    call emit_runtime_call

    ; Pop caller-saved regs (reverse order)
    mov dil, 0x41
    call emit_b
    mov dil, 0x5B               ; pop r11
    call emit_b
    mov dil, 0x41
    call emit_b
    mov dil, 0x5A               ; pop r10
    call emit_b
    mov dil, 0x41
    call emit_b
    mov dil, 0x59               ; pop r9
    call emit_b
    mov dil, 0x41
    call emit_b
    mov dil, 0x58               ; pop r8
    call emit_b
    mov dil, 0x5A               ; pop rdx
    call emit_b
    mov dil, 0x59               ; pop rcx
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
    jmp codegen_emit_all.next_ir

; IR_DICT_STORE: dict[key] = value — void
; src1 = dict pointer, src2 = key vreg, aux = value vreg
cge_dict_store:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]  ; src1 vreg (dict pointer)
    call load_src1_phys
    mov r15b, al                ; src1 phys
    movzx eax, word [r14 + 6]  ; src2 vreg (key)
    call load_src2_phys
    mov r9b, al                 ; src2 phys

    ; Push caller-saved regs
    mov dil, 0x51               ; push rcx
    call emit_b
    mov dil, 0x52               ; push rdx
    call emit_b
    mov dil, 0x41
    call emit_b
    mov dil, 0x50               ; push r8
    call emit_b
    mov dil, 0x41
    call emit_b
    mov dil, 0x51               ; push r9
    call emit_b
    mov dil, 0x41
    call emit_b
    mov dil, 0x52               ; push r10
    call emit_b
    mov dil, 0x41
    call emit_b
    mov dil, 0x53               ; push r11
    call emit_b

    ; Move dict pointer to rdi
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b

    ; Move key to rsi
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r9b
    shl al, 3
    or al, 0xC6
    mov dil, al
    call emit_b

    ; Load aux vreg (value) — inline vreg_phys lookup
    movzx rax, word [r14 + 16]  ; aux = value vreg number
    movzx rax, byte [vreg_phys + rax]
    cmp al, 255
    jne .cge_dict_store_val_ok
    mov dil, 0x4C
    call emit_b
    mov dil, 0x8B
    call emit_b
    mov dil, 0xB5
    call emit_b
    push r9
    movzx rbx, word [r14 + 16]
    mov edi, dword [vreg_offset + rbx * 4]
    call emit_d
    pop r9
    mov al, 6
.cge_dict_store_val_ok:
    mov r10b, al                ; value phys

    ; Move value to rdx
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r10b
    shl al, 3
    or al, 0xC2
    mov dil, al
    call emit_b

    ; Call rt_dict_set
    mov edi, [rt_dict_off]
    add edi, 0x119  ; offset to rt_dict_set
    call emit_runtime_call

    ; Pop caller-saved regs (reverse order)
    mov dil, 0x41
    call emit_b
    mov dil, 0x5B               ; pop r11
    call emit_b
    mov dil, 0x41
    call emit_b
    mov dil, 0x5A               ; pop r10
    call emit_b
    mov dil, 0x41
    call emit_b
    mov dil, 0x59               ; pop r9
    call emit_b
    mov dil, 0x41
    call emit_b
    mov dil, 0x58               ; pop r8
    call emit_b
    mov dil, 0x5A               ; pop rdx
    call emit_b
    mov dil, 0x59               ; pop rcx
    call emit_b

    jmp codegen_emit_all.next_ir

; IR_DICT_LEN: dst = len(dict)
; src1 = dict pointer
cge_dict_len:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]  ; src1 vreg (dict pointer)
    call load_src1_phys
    mov r15b, al                ; src1 phys
    movzx eax, word [r14 + 2]  ; dst vreg
    call get_dst_phys
    mov r8b, al                 ; dst phys

    ; Move dict pointer to rdi
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b

    ; Call rt_dict_len
    mov edi, [rt_dict_off]
    add edi, 0x1F3  ; offset to rt_dict_len
    call emit_runtime_call

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
    jmp codegen_emit_all.next_ir

; ============ String Operations ============

; IR_STR_CONCAT: dst = str1 + str2
; src1 = str1 pointer, src2 = str2 pointer
cge_str_concat:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]  ; src1 vreg (str1)
    call load_src1_phys
    mov r15b, al                ; src1 phys
    movzx eax, word [r14 + 6]  ; src2 vreg (str2)
    call load_src2_phys
    mov r9b, al                 ; src2 phys
    movzx eax, word [r14 + 2]  ; dst vreg
    call get_dst_phys
    mov r8b, al                 ; dst phys

    ; Move str1 to rdi
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b

    ; Move str2 to rsi
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r9b
    shl al, 3
    or al, 0xC6
    mov dil, al
    call emit_b

    ; Call rt_str_concat
    mov edi, [rt_str_off]
    call emit_runtime_call

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
    jmp codegen_emit_all.next_ir

; IR_STR_LEN: dst = len(str)
; src1 = str pointer
cge_str_len:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]  ; src1 vreg (str)
    call load_src1_phys
    mov r15b, al                ; src1 phys
    movzx eax, word [r14 + 2]  ; dst vreg
    call get_dst_phys
    mov r8b, al                 ; dst phys

    ; Move str to rdi
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b

    ; Call rt_str_len
    mov edi, [rt_str_off]
    add edi, 64  ; offset to rt_str_len
    call emit_runtime_call

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
    jmp codegen_emit_all.next_ir

; IR_NULL_COALESCE: dst = src1 != 0 ? src1 : src2
cge_null_coalesce:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]  ; src1 vreg
    call load_src1_phys
    mov r15b, al                ; src1 phys
    movzx eax, word [r14 + 6]  ; src2 vreg
    call load_src2_phys
    mov r9b, al                 ; src2 phys
    movzx eax, word [r14 + 2]  ; dst vreg
    call get_dst_phys
    mov r8b, al                 ; dst phys
    ; mov r(dst), r(src2): default to src2
    mov dil, 0x4D
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r9b
    shl al, 3
    or al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    ; test r(src1), r(src1)
    mov dil, 0x4D
    call emit_b
    mov dil, 0x85
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC0
    or al, r15b
    mov dil, al
    call emit_b
    ; cmovnz r(dst), r(src1): 4D 0F 45 (0xC0|(dst<<3)|src1)
    mov dil, 0x4D
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x45
    call emit_b
    mov al, r8b
    shl al, 3
    or al, 0xC0
    or al, r15b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp codegen_emit_all.next_ir

; ============ Control Flow Codegen ============

; IR_LABEL: record current out_idx in label_table[imm]
cge_label:
    movzx eax, word [r14 + 8]  ; label ID from imm field
    cmp eax, 256
    jae .label_skip
    mov ecx, [out_idx]
    mov [label_table + rax * 4], ecx
.label_skip:
    jmp codegen_emit_all.next_ir

; IR_JMP: emit JMP, use short form if target already resolved
cge_jmp:
    movzx eax, word [r14 + 8]  ; target label ID
    cmp eax, 256
    jae .jmp_long
    mov ecx, [label_table + rax * 4]
    cmp ecx, 0xFFFFFFFF
    je .jmp_long
    ; Label already resolved — compute displacement
    mov edx, [out_idx]
    add edx, 2                  ; short JMP is 2 bytes
    sub ecx, edx                ; displacement = target - (pos + 2)
    cmp ecx, -128
    jl .jmp_long
    cmp ecx, 127
    jg .jmp_long
    ; Use short JMP: EB rel8 (preserve displacement — emit_b clobbers ecx)
    mov r15b, cl
    mov dil, 0xEB
    call emit_b
    mov dil, r15b
    call emit_b
    jmp codegen_emit_all.next_ir
.jmp_long:
    ; Forward jump — use rel32 with patching
    mov dil, 0xE9
    call emit_b
    mov ecx, [out_idx]
    movzx eax, word [r14 + 8]
    mov edx, [jump_patch_count]
    cmp edx, 128
    jae .jmp_no_patch
    mov [jump_patches + rdx * 8], ecx
    mov [jump_patches + rdx * 8 + 4], eax
    inc dword [jump_patch_count]
.jmp_no_patch:
    xor edi, edi
    call emit_d
    jmp codegen_emit_all.next_ir

; IR_JCC: emit CMP + Jcc, use short form if target already resolved
cge_jcc:
    movzx eax, word [r14 + 4]  ; src1 vreg (bool to test)
    call load_src1_phys
    mov r15b, al
    ; cmp r(src1), 1
    mov dil, 0x49
    call emit_b
    mov dil, 0x81
    call emit_b
    mov al, 0xF8
    or al, r15b
    mov dil, al
    call emit_b
    mov edi, 1
    call emit_d
    ; Check if target label is already resolved
    movzx eax, word [r14 + 8]  ; target label ID
    cmp eax, 256
    jae .jcc_long
    mov ecx, [label_table + rax * 4]
    cmp ecx, 0xFFFFFFFF
    je .jcc_long
    ; Label resolved — try short Jcc
    mov edx, [out_idx]
    add edx, 2                  ; short Jcc is 2 bytes
    sub ecx, edx
    cmp ecx, -128
    jl .jcc_long
    cmp ecx, 127
    jg .jcc_long
    ; Use short Jcc: 7x rel8 (preserve displacement — emit_b clobbers ecx)
    movzx eax, word [r14 + 16] ; aux = condition code
    lea rsi, [rel .jcc8_table]
    movzx eax, byte [rsi + rax]
    mov r15b, cl
    mov dil, al
    call emit_b
    mov dil, r15b
    call emit_b
    jmp codegen_emit_all.next_ir
.jcc_long:
    ; Forward jump — use rel32
    movzx eax, word [r14 + 16]
    lea rsi, [rel .jcc_table]
    movzx ecx, byte [rsi + rax] ; second byte of 0F 8x opcode
    push rcx ; save second byte (emit_b clobbers ecx)
    mov dil, 0x0F
    call emit_b
    pop rcx
    mov dil, cl
    call emit_b
    ; Record patch
    mov ecx, [out_idx]
    movzx eax, word [r14 + 8]  ; target label ID
    mov edx, [jump_patch_count]
    cmp edx, 128
    jae .jcc_no_patch
    mov [jump_patches + rdx * 8], ecx
    mov [jump_patches + rdx * 8 + 4], eax
    inc dword [jump_patch_count]
.jcc_no_patch:
    xor edi, edi
    call emit_d
    jmp codegen_emit_all.next_ir

.jcc_table: db 0x84, 0x85, 0x8C, 0x8E, 0x8F, 0x8D  ; JE, JNE, JL, JLE, JG, JGE
.jcc8_table: db 0x74, 0x75, 0x7C, 0x7E, 0x7F, 0x7D  ; short JE, JNE, JL, JLE, JG, JGE

; ── IR_WHEN ────────────────────────────────────────────────
; dst:bool = state monitor of cond. Stores last-seen truth in an
; inline per-call-site 1-byte cell embedded in the code stream.
; Cell states: 0=neutral, 1=true, -1=false.
; Returns tri-state bool: became-true→1, currently-false→-1, no change→0.
; Scratch regs used (all non-colour: vregs live only in r8-r13):
;   rsi = cond value, rdi = cell ptr, cl = old, dl = cur, rax = result.
cge_when:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]  ; src1 vreg (cond)
    call load_src1_phys
    mov r15b, al               ; cond phys (ID)
    movzx eax, word [r14 + 2]  ; dst vreg
    call get_dst_phys
    mov r8b, al                ; dst phys

    ; mov rsi, r(src1)          (4C 89 C6|src1<<3) — capture cond value
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC6
    mov dil, al
    call emit_b
    ; lea rdi, [rip + 0x1D]    (cell lives 29 bytes after lea end)
    mov dil, 0x48
    call emit_b
    mov dil, 0x8D
    call emit_b
    mov dil, 0x3D
    call emit_b
    mov edi, 0x1D
    call emit_d
    ; mov cl, [rdi]            ; old = cell
    mov dil, 0x8A
    call emit_b
    mov dil, 0x0F
    call emit_b
    ; mov dl, -1               ; cur = false
    mov dil, 0xB2
    call emit_b
    mov dil, 0xFF
    call emit_b
    ; cmp rsi, 1
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xFE
    call emit_b
    mov dil, 1
    call emit_b
    ; jne Lf                   (rel8 = 0x02)
    mov dil, 0x75
    call emit_b
    mov dil, 0x02
    call emit_b
    ; mov dl, 1                ; cur = true
    mov dil, 0xB2
    call emit_b
    mov dil, 1
    call emit_b
    ; Lf: mov [rdi], dl        ; cell = cur
    mov dil, 0x88
    call emit_b
    mov dil, 0x17
    call emit_b
    ; cmp cl, dl               ; old == cur?
    mov dil, 0x38
    call emit_b
    mov dil, 0xD1
    call emit_b
    ; je Lstable               (rel8 = 0x04 → return 0)
    mov dil, 0x74
    call emit_b
    mov dil, 0x04
    call emit_b
    ; mov al, dl               ; return cur (88 D0)
    mov dil, 0x88
    call emit_b
    mov dil, 0xD0
    call emit_b
    ; jmp Ldone                (rel8 = 0x02)
    mov dil, 0xEB
    call emit_b
    mov dil, 0x02
    call emit_b
    ; Lstable: xor eax, eax    ; unchanged → neutral
    mov dil, 0x31
    call emit_b
    mov dil, 0xC0
    call emit_b
    ; Ldone: mov r(dst), rax
    mov dil, 0x49
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    ; jmp over the inline cell  (EB 01)
    mov dil, 0xEB
    call emit_b
    mov dil, 0x01
    call emit_b
    ; cell (initial 0 = neutral) — skipped by the jmp above
    xor dil, dil
    call emit_b
    call store_dst_spill
    jmp codegen_emit_all.next_ir

; ── IR_ABORT ───────────────────────────────────────────────
; abort with message: src1 = null-terminated str ptr (IR_LOAD_STR result)
cge_abort:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]  ; src1 vreg (msg ptr)
    call load_src1_phys
    mov r15b, al
    ; mov rdi, r(src1): 4C 89 (0xC7 | src1<<3)
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b
    ; call rt_abort
    mov edi, [rt_err_off]
    call emit_runtime_call
    jmp codegen_emit_all.next_ir

; IR_RET: emit return, optionally moving src1 to rax
cge_ret:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4] ; src1 vreg (return value)
    test ax, ax
    jz .ret_no_val
    ; Move return value to rax
    call load_src1_phys
    mov r15b, al
    ; emit: mov rax, phys_reg
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC0
    mov dil, al
    call emit_b
.ret_no_val:
    ; Multi-return: src2 → rdx (hi return value)
    movzx eax, word [r14 + 6] ; src2 vreg (hi return)
    test ax, ax
    jz .ret_no_hi
    call load_src2_phys
    mov r15b, al
    ; emit: mov rdx, phys_reg  (4C 89 (low3(phys)<<3)|0x02|0xC0)
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC2
    mov dil, al
    call emit_b
.ret_no_hi:
    ; emit: ret (C3)
    mov dil, 0xC3
    call emit_b
    jmp codegen_emit_all.next_ir

; ============ Protocol Subsystem Codegen ============

; IR_CALL_ARG: move/push an argument vreg into its ABI slot
; src1 = arg vreg, imm = arg index (0-5 = register, 6+ = stack)
cge_call_arg:
    movzx eax, word [r14 + 4] ; src1 vreg
    call load_src1_phys
    mov r15b, al ; phys (r10-r15)
    movzx ecx, word [r14 + 8] ; imm = arg index
    cmp ecx, 6
    jae .ca_push
    lea rbx, [arg_reg_phys + rcx]
    movzx ebx, byte [rbx] ; arg reg number (rdi..r9)
    ; emit: mov argreg, phys  (opcode 89, reg=src=phys, rm=dest=argreg)
    ; prefix: REX.W + REX.R (src always r10-r15); + REX.B if argreg is r8/r9
    cmp ebx, 8
    jb .ca_no_b
    mov dil, 0x4D
    jmp .ca_emit
.ca_no_b:
    mov dil, 0x4C
.ca_emit:
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    and al, 7
    shl al, 3
    mov r8b, bl
    and r8b, 7
    or al, r8b
    or al, 0xC0
    mov dil, al
    call emit_b
    jmp codegen_emit_all.next_ir
.ca_push:
    ; emit: push phys  (41 50+low3 for r10-r15)
    mov dil, 0x41
    call emit_b
    mov al, r15b
    and al, 7
    or al, 0x50
    mov dil, al
    call emit_b
    jmp codegen_emit_all.next_ir

; IR_CALL: emit a near CALL to a protocol body
; dst = lo vreg, src2 = hi vreg, imm = proto_id, aux = arg_count
cge_call:
    ; Emit E8 rel32 (patched later via resolve_proto_patches)
    mov dil, 0xE8
    call emit_b
    mov ecx, [out_idx]       ; patch_offset (position of rel32 field)
    movzx eax, word [r14 + 8] ; proto_id
    mov edx, [proto_patch_count]
    cmp edx, 128
    jae .call_no_patch
    mov [proto_patches + rdx * 8], ecx
    mov [proto_patches + rdx * 8 + 4], eax
    inc dword [proto_patch_count]
.call_no_patch:
    xor edi, edi
    call emit_d
    ; Clean up stack-passed args (caller cleanup)
    movzx ecx, word [r14 + 16] ; aux = arg_count
    cmp ecx, 6
    jbe .call_no_cleanup
    sub ecx, 6
    shl ecx, 3
    ; add rsp, N: 48 81 C4 imm32
    mov dil, 0x48
    call emit_b
    mov dil, 0x81
    call emit_b
    mov dil, 0xC4
    call emit_b
    mov edi, ecx
    call emit_d
.call_no_cleanup:
    ; dst ← rax (lo result)
    movzx eax, word [r14 + 2]
    test ax, ax
    jz .call_no_lo
    call get_dst_phys
    mov r15b, al
    ; emit: mov phys, rax  (49 89 C0|low3)
    mov dil, 0x49
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    and al, 7
    or al, 0xC0
    mov dil, al
    call emit_b
    call store_dst_spill
.call_no_lo:
    ; src2 ← rdx (hi result)
    movzx eax, word [r14 + 6]
    test ax, ax
    jz .call_no_hi
    call get_dst_phys
    mov r15b, al
    ; emit: mov phys, rdx  (49 89 D0|low3)
    mov dil, 0x49
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    and al, 7
    or al, 0xD0
    mov dil, al
    call emit_b
    call store_dst_spill
.call_no_hi:
    jmp codegen_emit_all.next_ir

; IR_PROTO_BEGIN: record the protocol body offset (prologue position)
; imm = proto_id
cge_proto_begin:
    movzx eax, word [r14 + 8] ; proto_id
    cmp eax, 256
    jae .pb_skip
    mov ecx, [out_idx]
    mov [proto_addr_table + rax * 4], ecx
.pb_skip:
    jmp codegen_emit_all.next_ir

; IR_SAVE_ARG: store a received argument into the callee's param var slot
; imm = arg index, aux = var ABSOLUTE offset
cge_save_arg:
    movzx eax, word [r14 + 8]  ; imm = arg index
    mov rbx, [r14 + 16]        ; aux = var abs offset
    cmp eax, 6
    jae .sa_stack
    lea rcx, [arg_reg_phys + rax]
    movzx ecx, byte [rcx]      ; arg reg number
    ; emit: mov [abs], argreg  (48/4C 89 (low3<<3)|0x04 25 disp32)
    ; NOTE: emit_b clobbers ecx, so compute prefix+ModRM first.
    mov r8b, cl
    and r8b, 7
    shl r8b, 3
    or r8b, 0x04
    cmp ecx, 8
    jb .sa_no_r
    mov r15b, 0x4C
    jmp .sa_emit
.sa_no_r:
    mov r15b, 0x48
.sa_emit:
    mov dil, r15b
    call emit_b
    mov dil, 0x89
    call emit_b
    mov dil, r8b
    call emit_b
    mov dil, 0x25
    call emit_b
    mov edi, ebx
    call emit_d
    jmp codegen_emit_all.next_ir
.sa_stack:
    ; mov rax, [rsp + (idx-5)*8]; mov [abs], rax
    ; disp32 = (idx - 5) * 8  (param 7 at [rsp+8])
    sub eax, 5
    shl eax, 3
    mov r15d, eax
    ; mov rax, [rsp + disp32]: 48 8B 84 24 disp32
    mov dil, 0x48
    call emit_b
    mov dil, 0x8B
    call emit_b
    mov dil, 0x84
    call emit_b
    mov dil, 0x24
    call emit_b
    mov edi, r15d
    call emit_d
    ; mov [abs], rax: 48 89 04 25 disp32
    mov dil, 0x48
    call emit_b
    mov dil, 0x89
    call emit_b
    mov dil, 0x04
    call emit_b
    mov dil, 0x25
    call emit_b
    mov edi, ebx
    call emit_d
    jmp codegen_emit_all.next_ir

; IR_SAVE_LOCAL_VAR: push the caller's local var onto the stack
; imm = var ABSOLUTE offset
cge_save_local_var:
    mov rbx, [r14 + 8] ; imm = var abs offset
    ; mov rax, [abs]: 48 8B 04 25 disp32
    mov dil, 0x48
    call emit_b
    mov dil, 0x8B
    call emit_b
    mov dil, 0x04
    call emit_b
    mov dil, 0x25
    call emit_b
    mov edi, ebx
    call emit_d
    ; push rax: 50
    mov dil, 0x50
    call emit_b
    jmp codegen_emit_all.next_ir

; IR_RESTORE_LOCAL_VAR: pop the caller's local var back from the stack
; imm = var ABSOLUTE offset
cge_restore_local_var:
    ; pop rax: 58
    mov dil, 0x58
    call emit_b
    mov rbx, [r14 + 8] ; imm = var abs offset
    ; mov [abs], rax: 48 89 04 25 disp32
    mov dil, 0x48
    call emit_b
    mov dil, 0x89
    call emit_b
    mov dil, 0x04
    call emit_b
    mov dil, 0x25
    call emit_b
    mov edi, ebx
    call emit_d
    jmp codegen_emit_all.next_ir

; ─────────── EXTENDED SEQ OPERATIONS ──────────────────

cge_seq_first:
    ; IR_SEQ_FIRST: dst = seq[0] — emit seq_get(seq, 0, elem_size)
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]  ; src1 vreg (seq)
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 2]  ; dst vreg
    call get_dst_phys
    mov r8b, al

    ; rdi = seq
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b

    ; rsi = 0 (index)
    mov dil, 0x48
    call emit_b
    mov dil, 0xC7
    call emit_b
    mov dil, 0xC6
    call emit_b
    xor edi, edi
    call emit_d

    ; rdx = element_size
    movzx eax, word [r14 + 8]
    mov dil, 0x48
    call emit_b
    mov dil, 0xC7
    call emit_b
    mov dil, 0xC2
    call emit_b
    mov edi, eax
    call emit_d

    mov edi, [rt_seq_off]
    add edi, 0xD7   ; rt_seq_get offset
    call emit_runtime_call

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
    jmp codegen_emit_all.next_ir

cge_seq_last:
    ; IR_SEQ_LAST: dst = seq[len-1]
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al

    ; Call rt_seq_len first
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b

    mov edi, [rt_seq_off]
    add edi, 0x105   ; rt_seq_len offset
    call emit_runtime_call
    ; rax = length

    ; dec rax (index = len - 1)
    mov dil, 0x48
    call emit_b
    mov dil, 0xFF
    call emit_b
    mov dil, 0xC8
    call emit_b

    ; mov rsi, rax
    mov dil, 0x48
    call emit_b
    mov dil, 0x89
    call emit_b
    mov dil, 0xC6
    call emit_b

    ; Reload seq into rdi
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b

    ; rdx = element_size
    movzx eax, word [r14 + 8]
    mov dil, 0x48
    call emit_b
    mov dil, 0xC7
    call emit_b
    mov dil, 0xC2
    call emit_b
    mov edi, eax
    call emit_d

    mov edi, [rt_seq_off]
    add edi, 0xD7   ; rt_seq_get offset
    call emit_runtime_call

    mov dil, 0x49
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp codegen_emit_all.next_ir

cge_seq_contains:
    ; IR_SEQ_CONTAINS: dst = bool(seq contains value)
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

    ; rdi = seq
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b

    ; rsi = value
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r9b
    shl al, 3
    or al, 0xC6
    mov dil, al
    call emit_b

    ; rdx = element_size
    movzx eax, word [r14 + 8]
    mov dil, 0x48
    call emit_b
    mov dil, 0xC7
    call emit_b
    mov dil, 0xC2
    call emit_b
    mov edi, eax
    call emit_d

    mov edi, [rt_seq_off]
    add edi, 0x27E  ; rt_seq_contains offset
    call emit_runtime_call

    ; Convert 0/1 to Rex bool: movzx rax,al; add rax,rax; dec rax
    mov dil, 0x48
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0xB6
    call emit_b
    mov dil, 0xC0
    call emit_b
    mov dil, 0x48
    call emit_b
    mov dil, 0x01
    call emit_b
    mov dil, 0xC0
    call emit_b
    mov dil, 0x48
    call emit_b
    mov dil, 0xFF
    call emit_b
    mov dil, 0xC8
    call emit_b

    mov dil, 0x49
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp codegen_emit_all.next_ir

cge_seq_index_of:
    ; IR_SEQ_INDEX_OF: dst = index of value (-1 if not found)
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

    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b

    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r9b
    shl al, 3
    or al, 0xC6
    mov dil, al
    call emit_b

    movzx eax, word [r14 + 8]
    mov dil, 0x48
    call emit_b
    mov dil, 0xC7
    call emit_b
    mov dil, 0xC2
    call emit_b
    mov edi, eax
    call emit_d

    mov edi, [rt_seq_off]
    add edi, 0x2CB  ; rt_seq_index_of offset
    call emit_runtime_call

    mov dil, 0x49
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp codegen_emit_all.next_ir

cge_seq_copy:
    ; IR_SEQ_COPY: dst = copy of seq
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al

    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b

    movzx eax, word [r14 + 8]
    mov dil, 0x48
    call emit_b
    mov dil, 0xC7
    call emit_b
    mov dil, 0xC6
    call emit_b
    mov edi, eax
    call emit_d

    mov edi, [rt_seq_off]
    add edi, 0x31A  ; rt_seq_copy offset
    call emit_runtime_call

    mov dil, 0x49
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp codegen_emit_all.next_ir

cge_seq_reverse:
    ; IR_SEQ_REVERSE: reverse in place (void)
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al

    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b

    movzx eax, word [r14 + 8]
    mov dil, 0x48
    call emit_b
    mov dil, 0xC7
    call emit_b
    mov dil, 0xC6
    call emit_b
    mov edi, eax
    call emit_d

    mov edi, [rt_seq_off]
    add edi, 0x38F  ; rt_seq_reverse offset
    call emit_runtime_call
    jmp codegen_emit_all.next_ir

cge_seq_sum:
    ; IR_SEQ_SUM: dst = sum of elements
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al

    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b

    movzx eax, word [r14 + 8]
    mov dil, 0x48
    call emit_b
    mov dil, 0xC7
    call emit_b
    mov dil, 0xC6
    call emit_b
    mov edi, eax
    call emit_d

    mov edi, [rt_seq_off]
    add edi, 0x3EC  ; rt_seq_sum offset
    call emit_runtime_call

    mov dil, 0x49
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp codegen_emit_all.next_ir

cge_seq_min:
    ; IR_SEQ_MIN: dst = min element
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al

    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b

    movzx eax, word [r14 + 8]
    mov dil, 0x48
    call emit_b
    mov dil, 0xC7
    call emit_b
    mov dil, 0xC6
    call emit_b
    mov edi, eax
    call emit_d

    mov edi, [rt_seq_off]
    add edi, 0x420  ; rt_seq_min offset
    call emit_runtime_call

    mov dil, 0x49
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp codegen_emit_all.next_ir

cge_seq_max:
    ; IR_SEQ_MAX: dst = max element
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al

    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b

    movzx eax, word [r14 + 8]
    mov dil, 0x48
    call emit_b
    mov dil, 0xC7
    call emit_b
    mov dil, 0xC6
    call emit_b
    mov edi, eax
    call emit_d

    mov edi, [rt_seq_off]
    add edi, 0x473  ; rt_seq_max offset
    call emit_runtime_call

    mov dil, 0x49
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp codegen_emit_all.next_ir

cge_seq_clear:
    ; IR_SEQ_CLEAR: set length to 0 (void)
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al

    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b

    mov edi, [rt_seq_off]
    add edi, 0x4C6  ; rt_seq_clear offset
    call emit_runtime_call
    jmp codegen_emit_all.next_ir

cge_seq_cap:
    ; IR_SEQ_CAP: dst = capacity
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al

    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b

    mov edi, [rt_seq_off]
    add edi, 0x4CF  ; rt_seq_cap offset
    call emit_runtime_call

    mov dil, 0x49
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp codegen_emit_all.next_ir

; ── IR_SIGNUM_F ────────────────────────────────────────
; dst:float = signum(src1:float) → -1.0, 0.0, or 1.0
; Strategy: load xmm0, store to stack, use x87 fcomi to compare with 0.0,
; then load appropriate constant (-1.0, 0.0, or 1.0) into xmm0.
cge_signum_f_op:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al
    ; movq xmm0, r(src1)
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
    ; sub rsp, 8:  48 83 EC 08
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xEC
    call emit_b
    mov dil, 0x08
    call emit_b
    ; movq [rsp], xmm0:  66 0F D6 04 24
    mov dil, 0x66
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0xD6
    call emit_b
    mov dil, 0x04
    call emit_b
    mov dil, 0x24
    call emit_b
    ; fld qword [rsp]:  DD 04 24
    mov dil, 0xDD
    call emit_b
    mov dil, 0x04
    call emit_b
    mov dil, 0x24
    call emit_b
    ; fldz:  D9 EE
    mov dil, 0xD9
    call emit_b
    mov dil, 0xEE
    call emit_b
    ; fcomip st0, st1: DF F1
    mov dil, 0xDF
    call emit_b
    mov dil, 0xF1
    call emit_b
    ; fstp st0: DD D8
    mov dil, 0xDD
    call emit_b
    mov dil, 0xD8
    call emit_b
    ; ja .positive (CF=0,ZF=0 → src > 0.0)
    mov dil, 0x77
    call emit_b
    mov eax, [out_idx]
    push rax                    ; save pos of displacement byte
    mov dil, 0
    call emit_b                 ; placeholder
    ; je .zero (ZF=1 → src == 0.0 or NaN)
    mov dil, 0x74
    call emit_b
    mov eax, [out_idx]
    push rax
    mov dil, 0
    call emit_b                 ; placeholder
    ; Fall through → negative case
    ; Load -1.0: mov rax, 0xBFF0000000000000; movq xmm0, rax
    mov dil, 0x48
    call emit_b
    mov dil, 0xB8
    call emit_b
    mov rdi, 0xBFF0000000000000  ; -1.0 IEEE 754
    call emit_q
    mov dil, 0x66
    call emit_b
    mov dil, 0x48
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x6E
    call emit_b
    mov dil, 0xC0
    call emit_b
    ; jmp .done
    mov dil, 0xEB
    call emit_b
    mov eax, [out_idx]
    push rax
    mov dil, 0
    call emit_b                 ; placeholder

    ; .positive: patch ja target here
    pop rcx                     ; displacement byte offset
    mov eax, [out_idx]
    sub eax, ecx
    dec eax                     ; rel8 = target - (disp_pos + 1)
    mov [out_buffer + rcx], al
    ; Load 1.0: mov rax, 0x3FF0000000000000; movq xmm0, rax
    mov dil, 0x48
    call emit_b
    mov dil, 0xB8
    call emit_b
    mov rdi, 0x3FF0000000000000  ; 1.0 IEEE 754
    call emit_q
    mov dil, 0x66
    call emit_b
    mov dil, 0x48
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x6E
    call emit_b
    mov dil, 0xC0
    call emit_b
    ; fall through to .zero

    ; .zero: patch je target here
    pop rcx
    mov eax, [out_idx]
    sub eax, ecx
    dec eax
    mov [out_buffer + rcx], al
    ; Load 0.0: pxor xmm0, xmm0
    mov dil, 0x66
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0xEF
    call emit_b
    mov dil, 0xC0
    call emit_b

    ; .done: patch jmp target here
    pop rcx
    mov eax, [out_idx]
    sub eax, ecx
    dec eax
    mov [out_buffer + rcx], al

    ; movq r(dst), xmm0
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
    ; add rsp, 8
    mov dil, 0x48
    call emit_b
    mov dil, 0x83
    call emit_b
    mov dil, 0xC4
    call emit_b
    mov dil, 0x08
    call emit_b
    call store_dst_spill
    jmp codegen_emit_all.next_ir

; ── IR_SIN / IR_COS / IR_TAN / IR_CBRT ────────────────
; All use the same pattern: load xmm0, call runtime function, store result
cge_math_trig_op:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al
    ; movq xmm0, r(src1)
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
    ; Call runtime function based on opcode
    movzx eax, byte [r14 + 0]
    cmp al, IR_SIN
    je .call_sin
    cmp al, IR_COS
    je .call_cos
    cmp al, IR_TAN
    je .call_tan
    ; IR_CBRT
    mov edi, [rt_math_off]
    add edi, 0xA3  ; rt_math_cbrt offset
    jmp .do_trig_call
.call_sin:
    mov edi, [rt_math_off]
    add edi, 0x00  ; rt_math_sin offset
    jmp .do_trig_call
.call_cos:
    mov edi, [rt_math_off]
    add edi, 0x1B  ; rt_math_cos offset
    jmp .do_trig_call
.call_tan:
    mov edi, [rt_math_off]
    add edi, 0x36  ; rt_math_tan offset
.do_trig_call:
    call emit_runtime_call
    ; movq r(dst), xmm0
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
    jmp codegen_emit_all.next_ir

; ── IR_POW_F ──────────────────────────────────────────
cge_math_pow_op:
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
    ; movq xmm0, r(src1) — base
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
    ; movq xmm1, r(src2) — exponent
    mov dil, 0x66
    call emit_b
    mov dil, 0x49
    call emit_b
    mov dil, 0x0F
    call emit_b
    mov dil, 0x6E
    call emit_b
    mov al, r9b
    or al, 0xC0
    mov dil, al
    call emit_b
    ; call rt_math_pow
    mov edi, [rt_math_off]
    add edi, 0x53  ; rt_math_pow offset
    call emit_runtime_call
    ; movq r(dst), xmm0
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
    jmp codegen_emit_all.next_ir

; ── IR_GCD ────────────────────────────────────────────
cge_gcd_op:
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
    ; mov rdi, r(src1)
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b
    ; mov rsi, r(src2)
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r9b
    shl al, 3
    or al, 0xC6
    mov dil, al
    call emit_b
    ; call rt_math_gcd
    mov edi, [rt_math_off]
    add edi, 0x112  ; rt_math_gcd offset
    call emit_runtime_call
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
    jmp codegen_emit_all.next_ir

; ── IR_LCM ────────────────────────────────────────────
cge_lcm_op:
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
    ; mov rdi, r(src1)
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b
    ; mov rsi, r(src2)
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r9b
    shl al, 3
    or al, 0xC6
    mov dil, al
    call emit_b
    ; call rt_math_lcm
    mov edi, [rt_math_off]
    add edi, 0x158  ; rt_math_lcm offset
    call emit_runtime_call
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
    jmp codegen_emit_all.next_ir

; ── IR_TO_BIN_STR ─────────────────────────────────────
cge_to_bin_str_op:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al
    ; mov rdi, r(src1)
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b
    ; call rt_conv_to_bin
    mov edi, [rt_conv_off]
    add edi, 0x48  ; rt_conv_to_bin offset
    call emit_runtime_call
    ; mov r(dst), rax  (rax = string pointer)
    mov dil, 0x49
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, 0xC0
    or al, r8b
    mov dil, al
    call emit_b
    call store_dst_spill
    jmp codegen_emit_all.next_ir

; ── IR_TO_HEX_STR ─────────────────────────────────────
cge_to_hex_str_op:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al
    ; mov rdi, r(src1)
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b
    ; call rt_conv_to_hex
    mov edi, [rt_conv_off]
    add edi, 0x97  ; rt_conv_to_hex offset
    call emit_runtime_call
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
    jmp codegen_emit_all.next_ir

; ── IR_TO_OCT_STR ─────────────────────────────────────
cge_to_oct_str_op:
    mov dword [dst_spilled_vreg], 0
    movzx eax, word [r14 + 4]
    call load_src1_phys
    mov r15b, al
    movzx eax, word [r14 + 2]
    call get_dst_phys
    mov r8b, al
    ; mov rdi, r(src1)
    mov dil, 0x4C
    call emit_b
    mov dil, 0x89
    call emit_b
    mov al, r15b
    shl al, 3
    or al, 0xC7
    mov dil, al
    call emit_b
    ; call rt_conv_to_oct
    mov edi, [rt_conv_off]
    add edi, 0xF1  ; rt_conv_to_oct offset
    call emit_runtime_call
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
    jmp codegen_emit_all.next_ir

; ── IR_SWAP_VARS ─────────────────────────────────────
; swap values at two stack slots: [imm] <-> [aux]
; Uses rax + rbx temporaries (not in register allocator)
cge_swap_vars_op:
    mov dword [dst_spilled_vreg], 0
    ; mov rax, [offset_a]  →  48 8B 04 25 <imm32>
    mov dil, 0x48
    call emit_b
    mov dil, 0x8B
    call emit_b
    mov dil, 0x04
    call emit_b
    mov dil, 0x25
    call emit_b
    mov edi, [r14 + 8]  ; imm = offset_a
    call emit_d
    ; mov rbx, [offset_b]  →  48 8B 1C 25 <aux32>
    mov dil, 0x48
    call emit_b
    mov dil, 0x8B
    call emit_b
    mov dil, 0x1C
    call emit_b
    mov dil, 0x25
    call emit_b
    mov edi, [r14 + 16]  ; aux = offset_b
    call emit_d
    ; mov [offset_a], rbx  →  48 89 1C 25 <imm32>
    mov dil, 0x48
    call emit_b
    mov dil, 0x89
    call emit_b
    mov dil, 0x1C
    call emit_b
    mov dil, 0x25
    call emit_b
    mov edi, [r14 + 8]  ; imm = offset_a
    call emit_d
    ; mov [offset_b], rax  →  48 89 04 25 <aux32>
    mov dil, 0x48
    call emit_b
    mov dil, 0x89
    call emit_b
    mov dil, 0x04
    call emit_b
    mov dil, 0x25
    call emit_b
    mov edi, [r14 + 16]  ; aux = offset_b
    call emit_d
    jmp codegen_emit_all.next_ir

; resolve_jumps: patch all recorded jump offsets using label_table
resolve_jumps:
    push rbx
    push r12
    push r13
    mov r12d, [jump_patch_count]
    test r12d, r12d
    jz .done
    xor r13d, r13d
.loop:
    cmp r13d, r12d
    jae .done
    mov eax, [jump_patches + r13 * 8]      ; patch_offset (position of rel32 field)
    mov ecx, [jump_patches + r13 * 8 + 4]  ; target label ID
    cmp ecx, 256
    jae .skip
    mov edx, [label_table + rcx * 4]       ; target output offset
    cmp edx, 0xFFFFFFFF
    je .skip
    ; rel32 = target - (patch_offset + 4)
    sub edx, eax
    sub edx, 4
    mov [out_buffer + rax], edx            ; write rel32 at patch_offset
.skip:
    inc r13d
    jmp .loop
.done:
    pop r13
    pop r12
    pop rbx
    ret

; resolve_proto_patches: patch all recorded protocol call rel32 offsets
; using proto_addr_table (proto_id → prologue output offset)
resolve_proto_patches:
    push rbx
    push r12
    push r13
    mov r12d, [proto_patch_count]
    test r12d, r12d
    jz .done
    xor r13d, r13d
.loop:
    cmp r13d, r12d
    jae .done
    mov eax, [proto_patches + r13 * 8]      ; patch_offset (position of rel32 field)
    mov ecx, [proto_patches + r13 * 8 + 4]  ; proto_id
    cmp ecx, 256
    jae .skip
    mov edx, [proto_addr_table + rcx * 4]   ; target proto body offset
    cmp edx, 0xFFFFFFFF
    je .skip
    ; rel32 = target - (patch_offset + 4)
    sub edx, eax
    sub edx, 4
    mov [out_buffer + rax], edx             ; write rel32 at patch_offset
.skip:
    inc r13d
    jmp .loop
.done:
    pop r13
    pop r12
    pop rbx
    ret

