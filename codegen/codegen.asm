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
global codegen_output_loop_var
global codegen_begin_protos
global codegen_end_protos
global codegen_emit_for_start
global codegen_emit_for_end
global codegen_emit_while_start
global codegen_emit_while_end
global codegen_save_break_base
global codegen_emit_break
global codegen_patch_breaks
global codegen_emit_ret
global codegen_emit_mov_eax_imm32
global codegen_emit_call_prot
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

    ; ── Protocol skip-jump ────────────────────────────────────────────────────
    prot_jmp_off:      resq 1    ; out_buffer offset of the "jmp main_code" rel32
    prot_jmp_live:     resq 1    ; 1 = placeholder is live (not yet patched)

    ; ── Loop break (stop) patch stack ─────────────────────────────────────────
    break_jump_stack:  resq 64   ; buffer offsets of pending break jmp rel32 fields
    break_jump_depth:  resq 1
    break_base_stack:  resq 32   ; saved break_jump_depth per loop nesting level
    break_base_depth:  resq 1

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
; ── codegen_emit_cmp_jne ─────────────────────────────────────────────────────
; rdi = var_value   — loaded into edi unless rdx != 0
; rsi = cmp_value   — compared against edi
; rdx = skip_mov_edi — 0: emit "mov edi, var_value" first; 1: edi already live (loop var)
;
; Emitted bytes (rdx==0, full form, 17 bytes):
;   BF vv vv vv vv           mov edi, var_value     (5)
;   81 FF cc cc cc cc        cmp edi, cmp_value     (6)
;   0F 85 00 00 00 00        jne <placeholder>      (6)
;
; Emitted bytes (rdx!=0, no-mov form, 12 bytes):
;   81 FF cc cc cc cc        cmp edi, cmp_value     (6)
;   0F 85 00 00 00 00        jne <placeholder>      (6)
codegen_emit_cmp_jne:
    push r12
    push r13
    push r14
    mov  r12d, edi              ; var_value (clamped to 32 bits)
    mov  r13d, esi              ; cmp_value (clamped to 32 bits)
    mov  r14,  rdx              ; skip_mov_edi flag (1 = skip, edi already live)

    ; Conditionally emit: mov edi, var_value  (BF + imm32)
    test r14, r14
    jnz  .cmp_skip_mov
    mov  al, 0xBF
    call emit_b
    mov  eax, r12d
    call emit_d
.cmp_skip_mov:

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

    ; Emit 4-byte placeholder
    xor  eax, eax
    call emit_d

    pop  r14
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

; ── codegen_output_loop_var ──────────────────────────────────────────────────
; Emits a rt_pri call for a loop variable whose value is already live in edi.
; The call is wrapped in push rdi / pop rdi so the loop counter survives.
;
; Emitted bytes (7 bytes total):
;   57                push rdi        ; save loop counter
;   E8 <disp:LE32>    call rt_pri     ; print and newline
;   5F                pop rdi         ; restore loop counter
codegen_output_loop_var:
    ; push rdi  (57 — preserves loop counter across rt_pri which clobbers edi)
    mov  al, 0x57
    call emit_b

    ; call rt_pri  (E8 + rel32)
    mov  al, 0xE8
    call emit_b
    ; disp = RT_PRI_OFFSET - (out_idx + 4)
    mov  rax, RT_PRI_OFFSET
    mov  rcx, [rel out_idx]
    add  rcx, 4
    sub  rax, rcx               ; signed displacement
    call emit_d

    ; pop rdi  (5F — restores loop counter after rt_pri returns)
    mov  al, 0x5F
    call emit_b

    ret

; ── codegen_begin_protos ─────────────────────────────────────────────────────
; Emits one "jmp skip_protos" placeholder (E9 + 4 zero bytes) the FIRST time
; it is called.  All subsequent calls are no-ops (guarded by prot_jmp_live).
;
; The jmp skips over all protocol body code so that prot definitions do not
; execute during normal top-level evaluation.
codegen_begin_protos:
    ; Guard: already emitted?
    cmp  qword [rel prot_jmp_live], 0
    jne  .bprot_done

    ; Emit E9 (jmp rel32 opcode)
    mov  al, 0xE9
    call emit_b

    ; Record where the rel32 field starts (for patching later)
    mov  rax, [rel out_idx]
    mov  [rel prot_jmp_off], rax

    ; Mark live
    mov  qword [rel prot_jmp_live], 1

    ; Emit 4-byte placeholder
    xor  eax, eax
    call emit_d

.bprot_done:
    ret

; ── codegen_end_protos ───────────────────────────────────────────────────────
; Patches the "jmp skip_protos" placeholder so it jumps to the current out_idx
; (the start of main non-prot code).  Idempotent: cleared by prot_jmp_live.
codegen_end_protos:
    ; Guard: nothing live to patch
    cmp  qword [rel prot_jmp_live], 0
    je   .eprot_done

    ; disp = out_idx - (prot_jmp_off + 4)
    mov  rax, [rel out_idx]
    mov  rcx, [rel prot_jmp_off]
    add  rcx, 4
    sub  rax, rcx               ; rax = forward displacement

    ; Patch out_buffer[prot_jmp_off..+4]
    mov  rcx, [rel prot_jmp_off]
    lea  rdi, [rel out_buffer]
    add  rdi, rcx
    mov  [rdi], eax             ; lower 32 bits = displacement

    ; Clear live flag so subsequent calls are no-ops
    mov  qword [rel prot_jmp_live], 0

.eprot_done:
    ret

; ── codegen_emit_for_start ───────────────────────────────────────────────────
; rdi = start value (loop counter initialiser, e.g. 0)
; rsi = end   value (exclusive upper bound,   e.g. 5)
;
; Emits:
;   BF <start:LE32>          mov edi, start      (5)
;   <loop_top:>
;   81 FF <end:LE32>         cmp edi, end        (6)
;   0F 8D 00 00 00 00        jge <placeholder>   (6)   ← pushed onto jump_patch_stack
;
; Returns: rax = loop_top  (buffer offset of the cmp instruction)
codegen_emit_for_start:
    push r12
    push r13
    mov  r12d, edi              ; r12d = start value
    mov  r13d, esi              ; r13d = end value

    ; Emit: mov edi, start  (BF + imm32)
    mov  al, 0xBF
    call emit_b
    mov  eax, r12d
    call emit_d

    ; Record loop_top = out_idx (this is where the cmp instruction will be)
    mov  r12, [rel out_idx]     ; r12 now = loop_top

    ; Emit: cmp edi, end  (81 FF + imm32)
    mov  al, 0x81
    call emit_b
    mov  al, 0xFF
    call emit_b
    mov  eax, r13d
    call emit_d

    ; Emit: jge rel32  (0F 8D + 4-byte placeholder)
    mov  al, 0x0F
    call emit_b
    mov  al, 0x8D
    call emit_b

    ; Push rel32 offset onto jump_patch_stack
    mov  rax, [rel out_idx]
    mov  rcx, [rel jump_stack_depth]
    lea  rdx, [rel jump_patch_stack]
    mov  [rdx + rcx*8], rax
    inc  qword [rel jump_stack_depth]

    ; Emit 4-byte placeholder
    xor  eax, eax
    call emit_d

    ; Return loop_top in rax
    mov  rax, r12

    pop  r13
    pop  r12
    ret

; ── codegen_emit_for_end ─────────────────────────────────────────────────────
; rdi = loop_top  (buffer offset returned by codegen_emit_for_start)
;
; Emits:
;   FF C7            inc edi             (2)
;   E9 <disp:LE32>   jmp <loop_top>      (5, backward)
;
; Then patches:
;   - jge placeholder (top of jump_patch_stack) → here (after_loop)
;   - all break (stop) jmps for this loop      → here (after_loop)
codegen_emit_for_end:
    push r12
    mov  r12, rdi               ; r12 = loop_top

    ; Emit: inc edi  (FF C7)
    mov  al, 0xFF
    call emit_b
    mov  al, 0xC7
    call emit_b

    ; Emit: jmp backward  (E9 + rel32)
    mov  al, 0xE9
    call emit_b
    ; disp = loop_top - (out_idx + 4)
    mov  rax, r12
    mov  rcx, [rel out_idx]
    add  rcx, 4
    sub  rax, rcx               ; negative signed displacement
    call emit_d

    ; Patch jge placeholder → current out_idx (after-loop target)
    call codegen_patch_jump

    ; Patch all break (stop) jmps → current out_idx
    call codegen_patch_breaks

    pop  r12
    ret

; ── codegen_emit_while_start ─────────────────────────────────────────────────
; rdi = var_value     — compare LHS (the variable's current value)
; rsi = cmp_value     — compare RHS (the literal to match)
; rdx = skip_mov_edi  — 1 if var is a loop var (edi already live), 0 otherwise
;
; Records loop_top BEFORE emitting the cmp, then delegates to
; codegen_emit_cmp_jne (which pushes the jne onto jump_patch_stack).
;
; Returns: rax = loop_top
codegen_emit_while_start:
    push r12
    push r13
    push r14
    push rbx
    mov  r13d, edi              ; r13d = var_value
    mov  r14d, esi              ; r14d = cmp_value
    movzx rbx, dl               ; rbx = skip_mov_edi flag

    ; Record loop_top = out_idx (before the cmp instruction)
    mov  r12, [rel out_idx]

    ; Emit cmp+jne via shared helper (also pushes jne placeholder)
    mov  edi, r13d
    mov  esi, r14d
    mov  rdx, rbx
    call codegen_emit_cmp_jne

    ; Return loop_top
    mov  rax, r12

    pop  rbx
    pop  r14
    pop  r13
    pop  r12
    ret

; ── codegen_emit_while_end ───────────────────────────────────────────────────
; rdi = loop_top  (buffer offset returned by codegen_emit_while_start)
;
; Emits backward jmp, patches jne → after_loop, patches all breaks.
codegen_emit_while_end:
    push r12
    mov  r12, rdi               ; r12 = loop_top

    ; Emit: jmp backward  (E9 + rel32)
    mov  al, 0xE9
    call emit_b
    ; disp = loop_top - (out_idx + 4)
    mov  rax, r12
    mov  rcx, [rel out_idx]
    add  rcx, 4
    sub  rax, rcx               ; negative displacement
    call emit_d

    ; Patch jne → after_loop
    call codegen_patch_jump

    ; Patch all break jmps → after_loop
    call codegen_patch_breaks

    pop  r12
    ret

; ── codegen_save_break_base ──────────────────────────────────────────────────
; Snapshots the current break_jump_depth onto break_base_stack.
; Called once at the start of every loop (for/while).
codegen_save_break_base:
    mov  rax, [rel break_jump_depth]    ; current depth
    mov  rcx, [rel break_base_depth]    ; stack top index
    lea  rdx, [rel break_base_stack]
    mov  [rdx + rcx*8], rax             ; push snapshot
    inc  qword [rel break_base_depth]
    ret

; ── codegen_emit_break ───────────────────────────────────────────────────────
; Emits an unconditional "jmp 0" placeholder and pushes its rel32 offset onto
; break_jump_stack for later bulk-patching by codegen_patch_breaks.
;
; Emitted bytes:
;   E9 00 00 00 00   jmp <placeholder>  (5)
codegen_emit_break:
    ; Emit E9 (jmp opcode)
    mov  al, 0xE9
    call emit_b

    ; Push rel32 slot offset onto break_jump_stack
    mov  rax, [rel out_idx]
    mov  rcx, [rel break_jump_depth]
    lea  rdx, [rel break_jump_stack]
    mov  [rdx + rcx*8], rax
    inc  qword [rel break_jump_depth]

    ; Emit 4-byte placeholder
    xor  eax, eax
    call emit_d
    ret

; ── codegen_patch_breaks ─────────────────────────────────────────────────────
; Pops the current loop's base from break_base_stack, then back-fills every
; break jmp entry since that base with a forward displacement to out_idx
; (the instruction immediately after the loop).
codegen_patch_breaks:
    push r12
    push r13
    push r14

    ; Pop base from break_base_stack
    dec  qword [rel break_base_depth]
    mov  rcx, [rel break_base_depth]
    lea  rax, [rel break_base_stack]       ; base ptr (no RIP+index in one operand)
    mov  r12, [rax + rcx*8]                ; r12 = base index

    ; r13 = current break_jump_depth (high water mark)
    mov  r13, [rel break_jump_depth]

    ; rax = forward target address (current out_idx)
    mov  rax, [rel out_idx]

    ; Loop: patch entries [base..depth-1]
    mov  r14, r12               ; r14 = loop counter starting at base
.pbk_loop:
    cmp  r14, r13               ; all entries patched?
    jge  .pbk_done

    ; rel32 slot offset for this break
    lea  rcx, [rel break_jump_stack]       ; base ptr
    mov  rdx, [rcx + r14*8]                ; rdx = rel32 slot offset

    ; disp = out_idx - (rdx + 4)
    mov  rcx, rax
    sub  rcx, rdx
    sub  rcx, 4

    ; Patch 4 bytes at out_buffer[rdx]
    lea  rdi, [rel out_buffer]
    add  rdi, rdx
    mov  [rdi], ecx

    inc  r14
    jmp  .pbk_loop

.pbk_done:
    ; Restore break_jump_depth to base (discard all patched entries)
    mov  [rel break_jump_depth], r12

    pop  r14
    pop  r13
    pop  r12
    ret

; ── codegen_emit_ret ─────────────────────────────────────────────────────────
; Emits a single RET instruction (C3).
codegen_emit_ret:
    mov  al, 0xC3
    call emit_b
    ret

; ── codegen_emit_mov_eax_imm32 ───────────────────────────────────────────────
; rdi = value  (lower 32 bits used as imm32)
;
; Emitted bytes:
;   B8 <value:LE32>  mov eax, value  (5)
codegen_emit_mov_eax_imm32:
    push rdi
    mov  al, 0xB8
    call emit_b
    pop  rax
    call emit_d             ; emit lower 32 bits of value
    ret

; ── codegen_emit_call_prot ───────────────────────────────────────────────────
; rdi = prot_buffer_offset  (byte offset from out_buffer start of prot's first
;                            instruction, as returned by proto registration)
;
; Emitted bytes:
;   E8 <disp:LE32>  call <prot>  (5)
;
; disp = prot_offset - (out_idx + 4)  [signed, computed after emitting E8]
codegen_emit_call_prot:
    push r12
    mov  r12, rdi               ; r12 = prot buffer offset

    ; Emit E8 (call opcode)
    mov  al, 0xE8
    call emit_b

    ; disp = r12 - (out_idx + 4)
    mov  rax, r12
    mov  rcx, [rel out_idx]
    add  rcx, 4
    sub  rax, rcx               ; signed displacement

    call emit_d

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
