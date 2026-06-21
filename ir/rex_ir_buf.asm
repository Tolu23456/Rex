; ══════════════════════════════════════════════════════════════════════════════
; ir/rex_ir_buf.asm — IR buffer allocation, record emission, vreg/label alloc
; Pure NASM, no C, no external dependencies beyond rex_defs.inc + ir_defs.inc
; ══════════════════════════════════════════════════════════════════════════════
default rel
%include "include/rex_defs.inc"
%include "ir/ir_defs.inc"

global ir_buffer, ir_idx, ir_vreg_ctr, ir_label_ctr
global ir_emit, ir_alloc_vreg, ir_alloc_label
global ir_reset, ir_get_record, ir_mark_dead
global ir_emit_imm, ir_emit_mov, ir_emit_binop
global ir_emit_jmp, ir_emit_jz, ir_emit_jnz, ir_emit_label
global ir_emit_ret, ir_emit_load_var, ir_emit_store_var
; shared pass-specific BSS (used by multiple pass files)
global ir_cf_val, ir_cf_known         ; CFP constants table (pass 1, 6)
global ir_use_cnt                      ; DCE use count (pass 2)
global ir_lr_start, ir_lr_end         ; RA live ranges (pass 7)
global ir_phys_map, ir_spill_slot     ; RA register assignment (pass 7, 8, x86)
global ir_frame_sz                     ; RA spill frame size (pass 7)
global ir_loop_depth                   ; LICM loop depth map (pass 5)

; ── BSS: IR buffer and counters ───────────────────────────────────────────────
section .bss
ir_buffer:      resb IR_MAX * IR_RECORD_SIZE   ; flat array of 32-byte records
ir_idx:         resq 1                          ; current record count (write index)
ir_vreg_ctr:    resw 1                          ; next virtual register number
ir_label_ctr:   resw 1                          ; next label number
; Pass-specific working storage (lives here so all passes share one alloc)
ir_cf_val:      resq VREG_MAX   ; CFP: known constant value per vreg
ir_cf_known:    resb VREG_MAX   ; CFP: 1 if vreg is a known constant
ir_lr_start:    resd VREG_MAX   ; RA: live-range start (record index)
ir_lr_end:      resd VREG_MAX   ; RA: live-range end (record index)
ir_phys_map:    resb VREG_MAX   ; RA: vreg → physical register ID
ir_spill_slot:  resd VREG_MAX   ; RA: vreg → spill frame offset
ir_frame_sz:    resd 1          ; RA: total frame bytes needed for spills
ir_loop_depth:  resb IR_MAX     ; LICM: loop depth at each record
ir_use_cnt:     resw VREG_MAX   ; DCE: use count per vreg

section .text

; ── ir_reset: clear buffer and reset all counters ─────────────────────────────
; No args; clobbers rdi, rcx, rax.
ir_reset:
    ; Zero ir_buffer
    lea rdi, [ir_buffer]
    xor eax, eax
    mov ecx, IR_MAX * IR_RECORD_SIZE / 8    ; divide by 8 for stosq
    rep stosq
    ; Zero counters
    mov qword [ir_idx], 0
    mov word [ir_vreg_ctr], 0
    mov word [ir_label_ctr], 0
    ret

; ── ir_alloc_vreg: allocate a new virtual register ────────────────────────────
; Returns: ax = new vreg number (16-bit); ir_vreg_ctr incremented.
ir_alloc_vreg:
    movzx eax, word [ir_vreg_ctr]
    inc word [ir_vreg_ctr]
    ret

; ── ir_alloc_label: allocate a new label ID ───────────────────────────────────
; Returns: ax = new label ID; ir_label_ctr incremented.
ir_alloc_label:
    movzx eax, word [ir_label_ctr]
    inc word [ir_label_ctr]
    ret

; ── ir_get_record: return pointer to record N ─────────────────────────────────
; rdi = record index N
; Returns: rax = pointer to ir_buffer[N * 32]
ir_get_record:
    mov rax, rdi
    imul rax, IR_RECORD_SIZE
    lea rcx, [ir_buffer]
    add rax, rcx
    ret

; ── ir_emit: emit one pre-filled 32-byte record ───────────────────────────────
; rdi = pointer to caller-filled 32-byte record (source)
; Returns: rax = index of the newly emitted record
; Clobbers: rsi, rcx, rax, rdx.
ir_emit:
    push rbx
    mov rbx, [ir_idx]
    ; bounds check
    cmp rbx, IR_MAX
    jge .ir_emit_full
    ; destination = ir_buffer + rbx * 32
    mov rax, rbx
    imul rax, IR_RECORD_SIZE
    lea rsi, [ir_buffer]
    add rsi, rax
    ; copy 32 bytes (4 x 64-bit stores)
    mov rax, [rdi]
    mov [rsi], rax
    mov rax, [rdi+8]
    mov [rsi+8], rax
    mov rax, [rdi+16]
    mov [rsi+16], rax
    mov rax, [rdi+24]
    mov [rsi+24], rax
    ; advance counter
    inc qword [ir_idx]
    mov rax, rbx
    pop rbx
    ret
.ir_emit_full:
    ; silently drop if full (callers should check ir_idx < IR_MAX)
    mov rax, [ir_idx]
    dec rax
    pop rbx
    ret

; ── ir_mark_dead: set IRF_DEAD on record at index rdi ────────────────────────
ir_mark_dead:
    mov rax, rdi
    imul rax, IR_RECORD_SIZE
    lea rcx, [ir_buffer]
    add rcx, rax
    or byte [rcx + IR_OFF_FLAGS], IRF_DEAD
    ret

; ── ir_emit_imm: emit IR_IMM dst=vreg_in_di, imm=rsi ────────────────────────
; rdi = dst vreg (16-bit, zero-extended to 32)
; rsi = 64-bit immediate value
; rdx = type (IR_TYPE_*)
; Returns: rax = record index
ir_emit_imm:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    ; clear record
    mov qword [rsp], 0
    mov qword [rsp+8], 0
    mov qword [rsp+16], 0
    mov qword [rsp+24], 0
    ; fill fields
    mov byte [rsp + IR_OFF_OP], IR_IMM
    mov [rsp + IR_OFF_TYPE], dl
    mov [rsp + IR_OFF_DST], edi
    mov [rsp + IR_OFF_SRC0], dword -1
    mov [rsp + IR_OFF_SRC1], dword -1
    mov [rsp + IR_OFF_IMM], rsi
    ; emit
    mov rdi, rsp
    call ir_emit
    leave
    ret

; ── ir_emit_mov: emit IR_MOV dst←src0 ───────────────────────────────────────
; rdi = dst vreg, rsi = src0 vreg, rdx = type
ir_emit_mov:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    mov qword [rsp], 0
    mov qword [rsp+8], 0
    mov qword [rsp+16], 0
    mov qword [rsp+24], 0
    mov byte [rsp + IR_OFF_OP], IR_MOV
    mov [rsp + IR_OFF_TYPE], dl
    mov [rsp + IR_OFF_DST], edi
    mov [rsp + IR_OFF_SRC0], esi
    mov dword [rsp + IR_OFF_SRC1], -1
    mov rdi, rsp
    call ir_emit
    leave
    ret

; ── ir_emit_binop: emit a binary opcode ──────────────────────────────────────
; rdi = opcode (IR_ADD, IR_SUB, etc.)
; rsi = dst vreg
; rdx = src0 vreg
; rcx = src1 vreg
; r8  = type
ir_emit_binop:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    mov qword [rsp], 0
    mov qword [rsp+8], 0
    mov qword [rsp+16], 0
    mov qword [rsp+24], 0
    mov [rsp + IR_OFF_OP], dil
    mov [rsp + IR_OFF_TYPE], r8b
    mov [rsp + IR_OFF_DST], esi
    mov [rsp + IR_OFF_SRC0], edx
    mov [rsp + IR_OFF_SRC1], ecx
    mov rdi, rsp
    call ir_emit
    leave
    ret

; ── ir_emit_jmp: unconditional jump to label L ───────────────────────────────
; rdi = label ID
ir_emit_jmp:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    mov qword [rsp], 0
    mov qword [rsp+8], 0
    mov qword [rsp+16], 0
    mov qword [rsp+24], 0
    mov byte [rsp + IR_OFF_OP], IR_JMP
    mov byte [rsp + IR_OFF_TYPE], IR_TYPE_VOID
    mov dword [rsp + IR_OFF_DST], -1
    mov dword [rsp + IR_OFF_SRC0], -1
    mov dword [rsp + IR_OFF_SRC1], -1
    mov [rsp + IR_OFF_IMM], rdi
    mov rdi, rsp
    call ir_emit
    leave
    ret

; ── ir_emit_jz: conditional jump if vreg == 0 ────────────────────────────────
; rdi = cond vreg, rsi = label ID
ir_emit_jz:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    mov qword [rsp], 0
    mov qword [rsp+8], 0
    mov qword [rsp+16], 0
    mov qword [rsp+24], 0
    mov byte [rsp + IR_OFF_OP], IR_JZ
    mov byte [rsp + IR_OFF_TYPE], IR_TYPE_VOID
    mov dword [rsp + IR_OFF_DST], -1
    mov [rsp + IR_OFF_SRC0], edi
    mov dword [rsp + IR_OFF_SRC1], -1
    mov [rsp + IR_OFF_IMM], rsi
    mov rdi, rsp
    call ir_emit
    leave
    ret

; ── ir_emit_jnz: conditional jump if vreg != 0 ───────────────────────────────
; rdi = cond vreg, rsi = label ID
ir_emit_jnz:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    mov qword [rsp], 0
    mov qword [rsp+8], 0
    mov qword [rsp+16], 0
    mov qword [rsp+24], 0
    mov byte [rsp + IR_OFF_OP], IR_JNZ
    mov byte [rsp + IR_OFF_TYPE], IR_TYPE_VOID
    mov dword [rsp + IR_OFF_DST], -1
    mov [rsp + IR_OFF_SRC0], edi
    mov dword [rsp + IR_OFF_SRC1], -1
    mov [rsp + IR_OFF_IMM], rsi
    mov rdi, rsp
    call ir_emit
    leave
    ret

; ── ir_emit_label: place a label (branch target) ─────────────────────────────
; rdi = label ID
ir_emit_label:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    mov qword [rsp], 0
    mov qword [rsp+8], 0
    mov qword [rsp+16], 0
    mov qword [rsp+24], 0
    mov byte [rsp + IR_OFF_OP], IR_LABEL
    mov byte [rsp + IR_OFF_TYPE], IR_TYPE_VOID
    mov dword [rsp + IR_OFF_DST], -1
    mov dword [rsp + IR_OFF_SRC0], -1
    mov dword [rsp + IR_OFF_SRC1], -1
    mov [rsp + IR_OFF_IMM], rdi
    mov rdi, rsp
    call ir_emit
    leave
    ret

; ── ir_emit_ret: return src0 vreg ────────────────────────────────────────────
; rdi = src0 vreg (or -1 for void), rsi = type
ir_emit_ret:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    mov qword [rsp], 0
    mov qword [rsp+8], 0
    mov qword [rsp+16], 0
    mov qword [rsp+24], 0
    cmp rdi, -1
    jne .ir_ret_val
    mov byte [rsp + IR_OFF_OP], IR_RET_VOID
    jmp .ir_ret_emit
.ir_ret_val:
    mov byte [rsp + IR_OFF_OP], IR_RET
    mov [rsp + IR_OFF_SRC0], edi
.ir_ret_emit:
    mov [rsp + IR_OFF_TYPE], sil
    mov dword [rsp + IR_OFF_DST], -1
    mov dword [rsp + IR_OFF_SRC1], -1
    mov rdi, rsp
    call ir_emit
    leave
    ret

; ── ir_emit_load_var: emit IR_LOAD_VAR dst←var[imm32] ───────────────────────
; rdi = dst vreg, rsi = var index (imm32), rdx = type
ir_emit_load_var:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    mov qword [rsp], 0
    mov qword [rsp+8], 0
    mov qword [rsp+16], 0
    mov qword [rsp+24], 0
    mov byte [rsp + IR_OFF_OP], IR_LOAD_VAR
    mov [rsp + IR_OFF_TYPE], dl
    mov [rsp + IR_OFF_DST], edi
    mov dword [rsp + IR_OFF_SRC0], -1
    mov dword [rsp + IR_OFF_SRC1], -1
    mov [rsp + IR_OFF_IMM], rsi
    mov rdi, rsp
    call ir_emit
    leave
    ret

; ── ir_emit_store_var: emit IR_STORE_VAR var[imm32]←src0 ────────────────────
; rdi = var index (imm32), rsi = src0 vreg
ir_emit_store_var:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    mov qword [rsp], 0
    mov qword [rsp+8], 0
    mov qword [rsp+16], 0
    mov qword [rsp+24], 0
    mov byte [rsp + IR_OFF_OP], IR_STORE_VAR
    mov byte [rsp + IR_OFF_TYPE], IR_TYPE_VOID
    mov dword [rsp + IR_OFF_DST], -1
    mov [rsp + IR_OFF_SRC0], esi
    mov dword [rsp + IR_OFF_SRC1], -1
    mov [rsp + IR_OFF_IMM], rdi
    mov rdi, rsp
    call ir_emit
    leave
    ret
