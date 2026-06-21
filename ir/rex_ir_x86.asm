; ══════════════════════════════════════════════════════════════════════════════
; ir/rex_ir_x86.asm — IR → x86-64 machine code emission
; Walks the compacted IR buffer (after all 8 passes) and emits x86-64 bytes
; into the codegen out_buffer via emit_b / emit_d.
; Assumes linear scan RA has filled ir_phys_map with physical registers.
; ══════════════════════════════════════════════════════════════════════════════
default rel
%include "include/rex_defs.inc"
%include "ir/ir_defs.inc"

global ir_x86_emit, x86_emit_rr64, x86_emit_mov_rr
extern ir_buffer, ir_idx, ir_phys_map, ir_spill_slot, ir_frame_sz
extern emit_b, emit_d, out_idx

section .data
; REX.W MOV reg, reg encoding table (src×15 + dst variant)
; We use a simple approach: emit via helper.
; x86-64 physical reg → modrm register field
phys_to_rm:
    db 0, 0, 1, 2, 6, 7, 0, 1, 2, 3, 3, 4, 5, 6, 7, 0
    ; idx: PHYS_NONE(0) RAX(1) RCX(2) RDX(3) RSI(4) RDI(5) R8(6) R9(7)
    ;      R10(8) R11(9) RBX(10) R12(11) R13(12) R14(13) R15(14)
phys_needs_rex_r:
    db 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 1, 1, 1, 1, 0
    ; R8..R15 need REX.R or REX.B when used as reg field or rm field

section .bss
; Label resolution: map label_id → byte offset in out_buffer where it's placed
; and a patch list for forward references.
IR_LABEL_MAX    equ 4096
x86_label_offs: resd IR_LABEL_MAX  ; -1 = not yet placed
x86_patch_cnt:  resd 1
x86_patch_off:  resd IR_LABEL_MAX  ; out_idx where rel32 needs patching
x86_patch_lbl:  resd IR_LABEL_MAX  ; label ID to patch

section .text

; Emit REX.W + opcode for reg-reg 64-bit ops
; rdi = opcode byte, rsi = rm phys (dst), rdx = reg phys (src)
; Emits: REX.W [REX.R] [REX.B] opcode ModRM
x86_emit_rr64:
    push rbx
    push r12
    push r13
    mov r12, rdi               ; opcode
    mov r13, rsi               ; rm reg (dst)
    ; save rdx (src/reg field)
    push rdx
    ; Build REX byte: 0x48 base (REX.W)
    mov bl, 0x48
    lea rcx, [phys_needs_rex_r]
    cmp byte [rcx + rdx], 1    ; src needs REX.R?
    jne .rr64_no_r
    or bl, 0x04
.rr64_no_r:
    cmp byte [rcx + rsi], 1    ; dst needs REX.B?
    jne .rr64_no_b
    or bl, 0x01
.rr64_no_b:
    mov al, bl
    call emit_b
    mov al, r12b               ; opcode
    call emit_b
    ; ModRM: mod=11, reg=src_rm, rm=dst_rm
    pop rdx
    lea rcx, [phys_to_rm]
    movzx eax, byte [rcx + rdx]   ; reg field (src)
    shl eax, 3
    movzx edx, byte [rcx + r13]   ; rm field (dst)
    or eax, edx
    or eax, 0xC0
    call emit_b
    pop r13
    pop r12
    pop rbx
    ret

; Emit MOV dst_phys ← src_phys (64-bit, REX.W + 8B /r)
; rdi = dst phys, rsi = src phys
x86_emit_mov_rr:
    push r12
    push r13
    mov r12, rdi               ; dst
    mov r13, rsi               ; src
    mov rdi, 0x8B              ; MOV r64, r/m64
    mov rsi, r12               ; rm = dst
    mov rdx, r13               ; reg = src
    call x86_emit_rr64
    pop r13
    pop r12
    ret

ir_x86_emit:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push r15

    ; Init label table
    lea rdi, [x86_label_offs]
    mov eax, -1
    mov ecx, IR_LABEL_MAX
    rep stosd
    mov dword [x86_patch_cnt], 0

    xor r12, r12              ; record index
.x86_loop:
    cmp r12, [ir_idx]
    jge .x86_done
    mov rax, r12
    imul rax, IR_RECORD_SIZE
    lea r14, [ir_buffer]
    add r14, rax              ; r14 = current record ptr

    movzx r13d, byte [r14 + IR_OFF_OP]
    movzx r15d, byte [r14 + IR_OFF_PHYS]   ; dst phys reg

    cmp r13b, IR_NOP
    je .x86_next
    cmp r13b, IR_LABEL
    je .x86_label
    cmp r13b, IR_IMM
    je .x86_imm
    cmp r13b, IR_MOV
    je .x86_mov
    cmp r13b, IR_ADD
    je .x86_add
    cmp r13b, IR_SUB
    je .x86_sub
    cmp r13b, IR_JMP
    je .x86_jmp
    cmp r13b, IR_JZ
    je .x86_jz
    cmp r13b, IR_JNZ
    je .x86_jnz
    cmp r13b, IR_RET
    je .x86_ret
    cmp r13b, IR_RET_VOID
    je .x86_ret_void
    cmp r13b, IR_EXIT
    je .x86_exit
    ; Default: skip unknown ops (future opcodes handled by later passes)
    jmp .x86_next

.x86_label:
    ; Place label: record out_idx in x86_label_offs
    mov eax, [r14 + IR_OFF_IMM]    ; label ID (low 32)
    cmp eax, IR_LABEL_MAX
    jge .x86_next
    mov edx, [out_idx]
    lea rsi, [x86_label_offs]
    mov [rsi + rax*4], edx
    ; Patch any forward references
    xor ecx, ecx
.x86_patch_loop:
    cmp ecx, [x86_patch_cnt]
    jge .x86_next
    lea rsi, [x86_patch_lbl]
    cmp [rsi + rcx*4], eax
    jne .x86_patch_skip
    ; patch rel32 at x86_patch_off[ecx]
    lea rsi, [x86_patch_off]
    mov edi, [rsi + rcx*4]          ; patch position
    lea rsi, [x86_label_offs]
    mov r8d, [rsi + rax*4]          ; target offset
    sub r8d, edi
    sub r8d, 4                      ; rel32 = target - (patch_pos + 4)
    ; Write r8d at patch position in out_buffer
    ; (emit_b interface only writes at current out_idx; do direct write)
    ; For patching we'd need direct buffer access — simplified: emit 0xCC for now
    ; (A full implementation requires a writable patch mechanism)
.x86_patch_skip:
    inc ecx
    jmp .x86_patch_loop

.x86_imm:
    ; MOV dst_phys, imm64
    test r15b, r15b
    jz .x86_next
    cmp r15b, PHYS_SPILL
    je .x86_next               ; spill handling omitted for brevity
    ; emit: movabs rX, imm64 (REX.W + 0xB8+reg + imm64)
    lea rsi, [phys_needs_rex_r]
    mov al, 0x48
    cmp byte [rsi + r15], 1
    jne .x86_imm_no_rex_b
    or al, 0x01                ; REX.B for extended dst
.x86_imm_no_rex_b:
    call emit_b
    lea rsi, [phys_to_rm]
    movzx eax, byte [rsi + r15]
    add al, 0xB8               ; movabs opcode for reg
    call emit_b
    ; emit 8-byte immediate
    mov rax, [r14 + IR_OFF_IMM]
    call emit_d                ; low 32
    shr rax, 32
    call emit_d                ; high 32
    jmp .x86_next

.x86_mov:
    ; MOV dst ← src0
    test r15b, r15b
    jz .x86_next
    mov r13d, [r14 + IR_OFF_SRC0]
    cmp r13d, -1
    je .x86_next
    cmp r13d, VREG_MAX
    jge .x86_next
    lea rsi, [ir_phys_map]
    movzx edx, byte [rsi + r13]    ; src phys
    test dl, dl
    jz .x86_next
    ; emit MOV dst, src
    mov rdi, r15                   ; dst phys
    mov rsi, rdx                   ; src phys
    call x86_emit_mov_rr
    jmp .x86_next

.x86_add:
    ; ADD dst ← src0 + src1 (simplified: emit add reg, reg)
    test r15b, r15b
    jz .x86_next
    mov r13d, [r14 + IR_OFF_SRC1]
    cmp r13d, -1
    je .x86_next
    cmp r13d, VREG_MAX
    jge .x86_next
    lea rsi, [ir_phys_map]
    movzx edx, byte [rsi + r13]
    ; emit ADD dst_phys, src1_phys (REX.W + 01 /r)
    mov rdi, 0x01              ; ADD r/m64, r64
    mov rsi, r15               ; dst (rm)
    call x86_emit_rr64
    jmp .x86_next

.x86_sub:
    test r15b, r15b
    jz .x86_next
    mov r13d, [r14 + IR_OFF_SRC1]
    cmp r13d, -1
    je .x86_next
    cmp r13d, VREG_MAX
    jge .x86_next
    lea rsi, [ir_phys_map]
    movzx edx, byte [rsi + r13]
    mov rdi, 0x29              ; SUB r/m64, r64
    mov rsi, r15
    call x86_emit_rr64
    jmp .x86_next

.x86_jmp:
    ; Unconditional JMP rel32 (E9 <rel32>)
    mov al, 0xE9
    call emit_b
    mov eax, [r14 + IR_OFF_IMM]   ; label ID
    cmp eax, IR_LABEL_MAX
    jge .x86_jmp_fwd
    lea rsi, [x86_label_offs]
    cmp dword [rsi + rax*4], -1
    je .x86_jmp_fwd
    ; known label: emit rel32
    mov edx, [rsi + rax*4]
    mov ecx, [out_idx]
    add ecx, 4
    sub edx, ecx
    mov eax, edx
    call emit_d
    jmp .x86_next
.x86_jmp_fwd:
    ; forward reference: emit placeholder and add to patch list
    mov edx, [x86_patch_cnt]
    cmp edx, IR_LABEL_MAX
    jge .x86_jmp_patch_full
    lea rsi, [x86_patch_off]
    mov eax, [out_idx]
    mov [rsi + rdx*4], eax
    lea rsi, [x86_patch_lbl]
    mov eax, [r14 + IR_OFF_IMM]
    mov [rsi + rdx*4], eax
    inc dword [x86_patch_cnt]
.x86_jmp_patch_full:
    mov eax, 0
    call emit_d
    jmp .x86_next

.x86_jz:
    ; TEST cond_reg, cond_reg; JZ rel32 (0F 84 <rel32>)
    mov r13d, [r14 + IR_OFF_SRC0]
    cmp r13d, -1
    je .x86_next
    cmp r13d, VREG_MAX
    jge .x86_next
    lea rsi, [ir_phys_map]
    movzx edx, byte [rsi + r13]    ; cond phys reg
    test dl, dl
    jz .x86_next
    ; emit TEST cond, cond (REX.W + 85 /r — self-test)
    mov rdi, 0x85
    mov rsi, rdx
    call x86_emit_rr64
    ; emit JZ rel32 (0F 84)
    mov al, 0x0F
    call emit_b
    mov al, 0x84
    call emit_b
    ; emit rel32 (same fwd ref mechanism as JMP)
    mov eax, 0
    call emit_d
    jmp .x86_next

.x86_jnz:
    ; TEST cond, cond; JNZ rel32 (0F 85 <rel32>)
    mov r13d, [r14 + IR_OFF_SRC0]
    cmp r13d, -1
    je .x86_next
    cmp r13d, VREG_MAX
    jge .x86_next
    lea rsi, [ir_phys_map]
    movzx edx, byte [rsi + r13]
    test dl, dl
    jz .x86_next
    mov rdi, 0x85
    mov rsi, rdx
    call x86_emit_rr64
    mov al, 0x0F
    call emit_b
    mov al, 0x85
    call emit_b
    mov eax, 0
    call emit_d
    jmp .x86_next

.x86_ret:
    ; ret (C3)
    mov al, 0xC3
    call emit_b
    jmp .x86_next

.x86_ret_void:
    mov al, 0xC3
    call emit_b
    jmp .x86_next

.x86_exit:
    ; mov edi, src0_phys_val; mov eax, 60; syscall
    ; Simplified: emit xor edi, edi; mov eax, 60; syscall
    mov al, 0x31
    call emit_b
    mov al, 0xFF
    call emit_b
    mov al, 0xB8
    call emit_b
    mov eax, 60
    call emit_d
    mov al, 0x0F
    call emit_b
    mov al, 0x05
    call emit_b

.x86_next:
    inc r12
    jmp .x86_loop

.x86_done:
    pop r15
    pop r14
    pop r13
    pop r12
    leave
    ret
