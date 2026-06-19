; rxc_emit.asm — RexC low-level byte emitter
; Provides: out_buffer, out_idx, rxc_emit_b, rxc_emit_d, rxc_emit_q, rxc_emit_name

default rel
%include "include/rex_defs.inc"
%include "rxc_defs.inc"

global out_buffer, out_idx
global rxc_emit_b, rxc_emit_d, rxc_emit_q, rxc_emit_name

section .bss
out_buffer:    resb 1048576   ; 1MB output buffer
out_idx:       resq 1         ; current write position

section .text

; rxc_emit_b — emit one byte (byte value in dil / al)
rxc_emit_b:
    mov rbx, [out_idx]
    lea rcx, [out_buffer]
    mov [rcx+rbx], dil
    inc qword [out_idx]
    ret

; rxc_emit_d — emit 4 bytes little-endian (dword in edi)
rxc_emit_d:
    mov rbx, [out_idx]
    lea rcx, [out_buffer]
    mov [rcx+rbx], edi
    add qword [out_idx], 4
    ret

; rxc_emit_q — emit 8 bytes little-endian (qword in rdi)
rxc_emit_q:
    mov rbx, [out_idx]
    lea rcx, [out_buffer]
    mov [rcx+rbx], rdi
    add qword [out_idx], 8
    ret

; rxc_emit_name — emit a length-prefixed name from (rdi=ptr, rsi=len, max 255)
; emits: [1-byte len] [len bytes]
rxc_emit_name:
    push r12
    push r13
    mov r12, rdi       ; name ptr
    mov r13, rsi       ; name len (capped at 255)
    cmp r13, 255
    jle .ok
    mov r13, 255
.ok:
    mov dil, r13b
    call rxc_emit_b    ; emit length byte
    test r13, r13
    jz .done
    xor ecx, ecx
.loop:
    cmp rcx, r13
    jge .done
    movzx edi, byte [r12+rcx]
    call rxc_emit_b
    inc rcx
    jmp .loop
.done:
    pop r13
    pop r12
    ret
