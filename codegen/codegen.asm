; codegen.asm - Machine-code emission subsystem
;
; Exports:
;   codegen_write_headers  — copy ELF+PH+padding into out_buffer, set out_idx=128
;   codegen_init           — write JMP + rt_pri blob + rt_prs blob
;   codegen_output_const   — emit "mov edi, V ; call rt_pri" for a known value
;   codegen_finish         — emit "mov eax,60 ; xor edi,edi ; syscall"
;   out_buffer             — 4096-byte output file buffer
;   out_idx                — current write position (= total bytes queued so far)

global codegen_write_headers
global codegen_init
global codegen_output_const
global codegen_finish
global codegen_emit_cmp_jne
global codegen_patch_jump
global codegen_save_chain_base
global codegen_emit_jmp_end
global codegen_patch_chain_end
global out_buffer
global out_idx

extern elf_header
extern program_header
extern rt_pri_blob, rt_pri_blob_end
extern rt_prs_blob, rt_prs_blob_end

%include "rex_defs.inc"

; ─── BSS ────────────────────────────────────────────────────────────────────
section .bss
    out_buffer:        resb 4096
    out_idx:           resq 1

    ; ── Conditional-fail (JNE) patch stack ───────────────────────────────────
    jump_patch_stack:  resq 64   ; buffer offsets of cond-fail JNE rel32 fields
    jump_stack_depth:  resq 1    ; live entries

    ; ── Taken-branch exit (JMP) patch stack ──────────────────────────────────
    end_jump_stack:    resq 64   ; buffer offsets of "jmp to chain end" rel32 fields
    end_jump_depth:    resq 1    ; live entries

    ; ── Per-chain base snapshot (for nested if chains) ────────────────────────
    chain_base_stack:  resq 32   ; saved end_jump_depth at each chain's entry
    chain_base_depth:  resq 1    ; live entries in chain_base_stack

; ─── TEXT ───────────────────────────────────────────────────────────────────
section .text

; ── emit helpers ─────────────────────────────────────────────────────────────

; emit_b : emit byte in al  (preserves all registers)
emit_b:
    push rcx
    push rdx
    lea  rcx, [rel out_buffer]
    mov  rdx, [rel out_idx]
    mov  [rcx + rdx], al
    inc  qword [rel out_idx]
    pop  rdx
    pop  rcx
    ret

; emit_d : emit dword in eax  (preserves all registers)
emit_d:
    push rcx
    push rdx
    lea  rcx, [rel out_buffer]
    mov  rdx, [rel out_idx]
    mov  [rcx + rdx], eax
    add  qword [rel out_idx], 4
    pop  rdx
    pop  rcx
    ret

; emit_blob : copy rcx bytes from rsi into out_buffer  (rsi, rcx preserved by caller convention)
emit_blob:
    push rdi
    push rsi
    push rcx
    push rax
    push rbx

    mov  rbx, rcx                   ; save count
    mov  rax, [rel out_idx]
    lea  rdi, [rel out_buffer]
    add  rdi, rax                   ; dest = &out_buffer[out_idx]
    rep  movsb
    add  qword [rel out_idx], rbx

    pop  rbx
    pop  rax
    pop  rcx
    pop  rsi
    pop  rdi
    ret

; ── codegen_write_headers ────────────────────────────────────────────────────
; Writes ELF header (64) + program header (56) + 8 zero-padding bytes
; into out_buffer[0..127], sets out_idx = 128.
codegen_write_headers:
    ; Reset write cursor
    mov  qword [rel out_idx], 0

    ; ELF header – 64 bytes
    lea  rsi, [rel elf_header]
    mov  rcx, 64
    call emit_blob

    ; Program header – 56 bytes
    lea  rsi, [rel program_header]
    mov  rcx, 56
    call emit_blob

    ; 8 padding bytes (zero)
    xor  eax, eax
    mov  ecx, 8
.pad:
    call emit_b
    dec  ecx
    jnz  .pad

    ret

; ── codegen_init ─────────────────────────────────────────────────────────────
; Writes (at out_idx = 128):
;   E9 <RT_TOTAL_SIZE as LE dword>    JMP over runtime (5 bytes)
;   <rt_pri blob>                     63 bytes
;   <rt_prs blob>                     13 bytes
; After this, out_idx = CODE_START = 209.
codegen_init:
    ; JMP rel32 opcode
    mov  al, 0xE9
    call emit_b

    ; displacement = RT_TOTAL_SIZE (jumps over rt_pri + rt_prs)
    mov  eax, RT_TOTAL_SIZE         ; = 76 = 0x4C
    call emit_d

    ; rt_pri blob (63 bytes)
    lea  rsi, [rel rt_pri_blob]
    lea  rcx, [rel rt_pri_blob_end]
    sub  rcx, rsi
    call emit_blob

    ; rt_prs blob (13 bytes)
    lea  rsi, [rel rt_prs_blob]
    lea  rcx, [rel rt_prs_blob_end]
    sub  rcx, rsi
    call emit_blob

    ret

; ── codegen_output_const ─────────────────────────────────────────────────────
; Emits code to call rt_pri with a compile-time constant value.
;   rdi = value (64-bit, treated as unsigned for printing)
;
; Emitted bytes:
;   BF <value:LE32>          mov edi, <value>   (5 bytes)
;   E8 <disp:LE32>           call rt_pri        (5 bytes)
;
; displacement = RT_PRI_OFFSET - (out_idx_of_E8 + 5)
codegen_output_const:
    push rdi

    ; mov edi, value   (opcode 0xBF + imm32)
    mov  al, 0xBF
    call emit_b
    pop  rdi
    mov  eax, edi                   ; lower 32 bits
    call emit_d

    ; call rt_pri  (0xE8 + rel32 displacement)
    mov  al, 0xE8
    call emit_b

    ; disp = RT_PRI_OFFSET - (out_idx + 4)
    ;   out_idx currently points to the 4-byte displacement field
    ;   end of call instruction = out_idx + 4
    mov  rax, RT_PRI_OFFSET         ; = 133
    mov  rcx, [rel out_idx]
    add  rcx, 4
    sub  rax, rcx                   ; rax = signed displacement
    call emit_d                     ; writes lower 32 bits (correct for negative too)

    ret

; ── codegen_emit_cmp_jne ─────────────────────────────────────────────────────
; Emits a compile-time compare + conditional JNE with a 0x00000000 placeholder.
; The address of that placeholder inside out_buffer is pushed onto jump_patch_stack
; so that codegen_patch_jump can back-fill the correct displacement later.
;
; rdi = var_value   (loaded into edi at runtime)
; rsi = cmp_value   (compared against edi at runtime)
;
; Emitted code (17 bytes total):
;   BF vv vv vv vv           mov edi, var_value     (5)
;   81 FF cc cc cc cc        cmp edi, cmp_value     (6)
;   0F 85 00 00 00 00        jne <placeholder>      (6)
codegen_emit_cmp_jne:
    push r12
    push r13
    mov  r12d, edi              ; var_value (clamped to 32 bits)
    mov  r13d, esi              ; cmp_value (clamped to 32 bits)

    ; mov edi, var_value  (opcode BF + imm32)
    mov  al, 0xBF
    call emit_b
    mov  eax, r12d
    call emit_d

    ; cmp edi, cmp_value  (81 FF + imm32)
    mov  al, 0x81
    call emit_b
    mov  al, 0xFF
    call emit_b
    mov  eax, r13d
    call emit_d

    ; jne rel32  (0F 85)
    mov  al, 0x0F
    call emit_b
    mov  al, 0x85
    call emit_b

    ; Record current out_idx as the offset of the rel32 placeholder
    mov  rax, [rel out_idx]
    mov  rcx, [rel jump_stack_depth]
    lea  rdx, [rel jump_patch_stack]
    mov  [rdx + rcx*8], rax
    inc  qword [rel jump_stack_depth]

    ; Emit the 4-byte placeholder (0x00000000)
    xor  eax, eax
    call emit_d

    pop  r13
    pop  r12
    ret

; ── codegen_patch_jump ────────────────────────────────────────────────────────
; Pops the topmost entry from jump_patch_stack and back-fills the rel32 field
; inside out_buffer with the correct forward displacement.
;
; Displacement formula:
;   disp = out_idx - placeholder_off - 4
;   (out_idx = current write cursor = first byte after the body that was emitted)
codegen_patch_jump:
    ; Pop placeholder offset
    dec  qword [rel jump_stack_depth]
    mov  rcx, [rel jump_stack_depth]
    lea  rdx, [rel jump_patch_stack]
    mov  r8, [rdx + rcx*8]             ; r8  = placeholder_off

    ; disp = out_idx - placeholder_off - 4
    mov  rax, [rel out_idx]
    sub  rax, r8
    sub  rax, 4                         ; eax now holds the signed rel32 displacement

    ; Write displacement into out_buffer at placeholder_off
    lea  rdx, [rel out_buffer]
    mov  [rdx + r8], eax

    ret

; ── codegen_save_chain_base ──────────────────────────────────────────────────
; Snapshot the current end_jump_depth onto chain_base_stack.
; Must be called once per if-chain entry so codegen_patch_chain_end knows
; which end_jump entries belong to this chain vs an outer/inner chain.
; Preserves all registers.
codegen_save_chain_base:
    mov  rax, [rel end_jump_depth]          ; current top of end_jump_stack
    mov  rcx, [rel chain_base_depth]        ; current nesting level
    lea  rdx, [rel chain_base_stack]
    mov  [rdx + rcx*8], rax                 ; push snapshot
    inc  qword [rel chain_base_depth]
    ret

; ── codegen_emit_jmp_end ─────────────────────────────────────────────────────
; Emit an unconditional JMP (E9) with a 0x00000000 placeholder and record the
; placeholder's buffer offset in end_jump_stack.
; Called at the end of each taken if/elif branch so that all such jumps can be
; bulk-patched to the chain exit by codegen_patch_chain_end.
; Preserves all registers (uses only caller-saved rax, rcx, rdx internally).
codegen_emit_jmp_end:
    ; Emit opcode E9  (unconditional near jump)
    mov  al, 0xE9
    call emit_b                             ; out_idx now points at rel32 field

    ; Save the rel32 field offset onto end_jump_stack before writing placeholder
    mov  rax, [rel out_idx]                 ; rax = start of rel32 in out_buffer
    mov  rcx, [rel end_jump_depth]
    lea  rdx, [rel end_jump_stack]
    mov  [rdx + rcx*8], rax                 ; push placeholder offset
    inc  qword [rel end_jump_depth]

    ; Emit 4-byte placeholder (0x00000000)
    xor  eax, eax
    call emit_d
    ret

; ── codegen_patch_chain_end ──────────────────────────────────────────────────
; Pop the chain base from chain_base_stack, then patch every end_jump entry
; from that base index up to the current end_jump_depth so each one jumps to
; the current out_idx (= chain exit / fall-through point).
; Resets end_jump_depth to the base so that outer chains are unaffected.
codegen_patch_chain_end:
    push r12
    push r13

    ; Pop chain base snapshot
    dec  qword [rel chain_base_depth]
    mov  rcx, [rel chain_base_depth]
    lea  rdx, [rel chain_base_stack]
    mov  r12, [rdx + rcx*8]                 ; r12 = base index (first entry to patch)

    ; Walk every end_jump entry from base to current depth and patch it
    mov  r13, r12                           ; r13 = loop cursor
.pce_loop:
    cmp  r13, [rel end_jump_depth]
    jge  .pce_done

    ; Load placeholder offset from end_jump_stack[r13]
    lea  rdx, [rel end_jump_stack]
    mov  rax, [rdx + r13*8]                 ; rax = placeholder buffer offset

    ; disp = out_idx - placeholder_off - 4   (signed rel32 from end-of-JMP)
    mov  rcx, [rel out_idx]
    sub  rcx, rax
    sub  rcx, 4                             ; rcx = signed rel32 displacement

    ; Write displacement into out_buffer[placeholder_off]
    lea  rdx, [rel out_buffer]
    mov  [rdx + rax], ecx                   ; 4-byte patch (ecx = low 32 bits of rcx)

    inc  r13
    jmp  .pce_loop

.pce_done:
    ; Restore end_jump_depth to base — discards all entries used by this chain
    mov  [rel end_jump_depth], r12

    pop  r13
    pop  r12
    ret

; ── codegen_finish ───────────────────────────────────────────────────────────
; Appends exit syscall sequence:
;   B8 3C 00 00 00    mov eax, 60
;   31 FF             xor edi, edi
;   0F 05             syscall
codegen_finish:
    ; mov eax, 60
    mov  al, 0xB8
    call emit_b
    mov  eax, 60
    call emit_d

    ; xor edi, edi  (31 FF — clears edi, zero-extends to rdi)
    mov  al, 0x31
    call emit_b
    mov  al, 0xFF
    call emit_b

    ; syscall
    mov  al, 0x0F
    call emit_b
    mov  al, 0x05
    call emit_b

    ret
