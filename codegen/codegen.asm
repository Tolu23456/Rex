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

    ; Embed the runtime binaries directly
    rt_pri_bin:  incbin "runtime/rt_pri.bin"
    rt_prs_bin:  incbin "runtime/rt_prs.bin"
    rt_prb_bin:  incbin "runtime/rt_prb.bin"
    rt_prf_bin:  incbin "runtime/rt_prf.bin"
    rt_prq_bin:  incbin "runtime/rt_prq.bin"

section .bss
    global out_buffer
    global out_idx
    out_buffer  resb 131072
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
    cmp ecx, 131072
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
    push rbx
    mov ecx, [out_idx]
    cmp ecx, 131072 - 4
    jae .overflow
    mov [out_buffer + rcx], edi
    add dword [out_idx], 4
    pop rbx
    ret
.overflow:
    mov rax, 60
    mov rdi, 2
    syscall

; Emit 8 bytes
emit_q:
    push rbx
    mov ecx, [out_idx]
    cmp ecx, 131072 - 8
    jae .overflow
    mov [out_buffer + rcx], rdi
    add dword [out_idx], 8
    pop rbx
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
    mov rdi, [out_idx]
    lea rdi, [out_buffer + rdi]
    ; rsi already points to source
    ; rcx contains length
    rep movsb
    add [out_idx], rcx
    pop rcx
    pop rdi
    pop rsi
    ret

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

    ; 8. Write rt_prc slot (512 bytes of zeroes)
    xor dil, dil
    mov ecx, 512
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
    sub edi, eax ; rel32
    
    mov dil, 0xE8 ; call
    call emit_b
    mov edi, eax
    call emit_d
    ret

; Emit instruction selection for all IR records
codegen_emit_all:
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
    
    cmp al, IR_OUT_INT
    je .output_val
    cmp al, IR_OUT_FLOAT
    je .output_val
    cmp al, IR_OUT_BOOL
    je .output_val
    cmp al, IR_OUT_STR
    je .output_val
    
    cmp al, IR_HALT
    je .halt

.next_ir:
    inc r13d
    jmp .loop

.done:
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

.store_var:
    ; IR_STORE_VAR: store src1 register to variable
    ; imm = variable offset
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
    call store_dst_spill
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
    ; Emit operation: dst = dst op src2
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
    ; 1. mov rax, dst -> 49 89 C0 + dst
    mov dil, 0x49
    call emit_b
    mov dil, 0x89
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
    
    ; 3. idiv src2 -> 49 F7 ModRM(F8 | src2)
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
    
    ; 4. mov dst, rax -> 49 89 C0 + (0<<3) + dst? Wait.
    ; mov dst, rax -> 4C 89 C0 | (0<<3) | dst -> 4C 89 C0 + dst
    mov dil, 0x4C
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
    ; 4. mov dst, rdx -> 4C 89 D0 + dst
    mov dil, 0x4C
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

.output_val:
    ; output: prints value in src1
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
    call store_dst_spill
    jmp .next_ir

.call_pri:
    mov edi, 125
    call emit_runtime_call
    call store_dst_spill
    jmp .next_ir
.call_prs:
    mov edi, 637
    call emit_runtime_call
    call store_dst_spill
    jmp .next_ir
.call_prb:
    mov edi, 1149
    call emit_runtime_call
    call store_dst_spill
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
    
    mov edi, 1405
    call emit_runtime_call
    call store_dst_spill
    jmp .next_ir

.halt:
    call emit_epilogue_and_exit
    call store_dst_spill
    jmp .next_ir


; Helper to load src1 into a physical register (or r14 if spilled)
load_src1_phys:
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
    ret

; Helper to load src2 into a physical register (or r15 if spilled)
load_src2_phys:
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
    ret

; Helper to get dst register (or r14 if spilled). Sets dst_spilled_vreg.
get_dst_phys:
    movzx rbx, ax
    movzx rax, byte [vreg_phys + rbx]
    cmp al, 255
    jne .done
    ; Spilled! We will use r14 (ID 6)
    mov [dst_spilled_vreg], ebx
    mov al, 6
    ret
.done:
    mov dword [dst_spilled_vreg], 0
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
codegen_finish:
    mov ecx, [out_idx]
    
    ; Patch ELF program header filesz at offset 64 + 32 = 96
    mov [out_buffer + 96], ecx
    
    ; Patch memsz at offset 64 + 40 = 104
    ; memsz covers code size + variables storage (0x44000)
    add ecx, 0x44000
    mov [out_buffer + 104], ecx
    ret
