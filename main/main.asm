default rel
%include "include/rex_defs.inc"
global _start
extern lexer_init, lexer_next, parse_stmt, codegen_write_headers, codegen_init, codegen_finish
extern proto_prescan
extern codegen_finalize
extern out_buffer, out_idx, out_name, tok_type
section .bss
src_buffer: resb 1048576    ; BUG-15/SEC-06 fix: 1MB (was 64KB = 65536)
src_len:    resq 1
src_fd:     resq 1
out_fd:     resq 1
section .text
_start:
    mov rax, [rsp]
    cmp rax, 2
    jl .err
    mov rdi, [rsp+16]
    mov rax, 2
    xor rsi, rsi
    xor rdx, rdx
    syscall
    test rax, rax
    js .err
    mov [src_fd], rax
    mov rdi, rax
    mov rax, 0
    lea rsi, [src_buffer]
    mov rdx, 1048576        ; BUG-15/SEC-06 fix: read up to 1MB (was 65536)
    syscall
    mov [src_len], rax
    ; BUG-15: check for truncation — if we read exactly the buffer size the file may be larger
    cmp rax, 1048576
    jne .src_ok
    mov rax, 1
    mov rdi, 2
    lea rsi, [src_too_large_msg]
    mov rdx, src_too_large_len
    syscall
    mov rax, 60
    mov rdi, 1
    syscall
.src_ok:
    mov rax, 3
    mov rdi, [src_fd]
    syscall
    call codegen_write_headers
    lea rdi, [src_buffer]
    mov rsi, [src_len]
    call prescan_blobs          ; returns blob inclusion mask in rax
    mov rdi, rax
    call codegen_init
    ; ── Pass 1: proto prescan — pre-register all proto signatures ─────────────
    lea rdi, [src_buffer]
    mov rsi, [src_len]
    call lexer_init
    call lexer_next
    call proto_prescan       ; scans full source, pre-registers all proto names
    ; ── Pass 2: full compilation ───────────────────────────────────────────────
    lea rdi, [src_buffer]
    mov rsi, [src_len]
    call lexer_init
    call lexer_next
.l:
    movzx eax, byte [tok_type]
    cmp al, TOK_EOF
    je .d
    cmp al, TOK_NEWLINE
    je .s
    call parse_stmt
    jmp .l
.s:
    call lexer_next
    jmp .l
.d:
    call codegen_finalize   ; O27: retroactively NOP push/pop r12 for outer-scope-only protos
    call codegen_finish
    mov rax, 87
    lea rdi, [out_name]
    syscall
    mov rax, 2
    lea rdi, [out_name]
    mov rsi, 0x41
    mov rdx, 493
    syscall
    test rax, rax
    js .err
    mov [out_fd], rax
    mov rdi, rax
    mov rax, 1
    lea rsi, [out_buffer]
    mov rdx, [out_idx]
    syscall
    mov rax, 3
    mov rdi, [out_fd]
    syscall
    mov rax, 60
    xor rdi, rdi
    syscall
.err:
    mov rax, 60
    mov rdi, 1
    syscall

section .data
src_too_large_msg: db "error: source file exceeds 1MB limit",10
src_too_large_len  equ $ - src_too_large_msg
section .text
; ── Pre-scan: determine which runtime blobs are actually needed ────────────────
; rdi=source_ptr  rsi=source_len
; Returns rax = blob inclusion bitmask:
;   bit 0 (0x01): PRI (int)    — always set
;   bit 1 (0x02): PRS (str)    — if '"' or 'str' keyword found
;   bit 2 (0x04): PRB (bool)   — if 'bool'/'true'/'fals' found
;   bit 3 (0x08): PRF (float)  — if 'floa' (float) found
;   bit 4 (0x10): PRC (complex)— if 'comp' (complex) found
;   bit 5 (0x20): SIP (input)  — if 'inpu' (input) found
;   bit 6 (0x40): ALC (alloc)  — if 'seq'/'push'/'each'/'dict' found
;   bit 7 (0x80): PRQ (dict)   — if 'dict' found
prescan_blobs:
    push rbx
    push r12
    push r13
    push r8
    mov r12, rdi            ; source ptr
    mov r13, rsi            ; source length
    mov eax, 1              ; bit 0 = PRI always included
    xor rbx, rbx
.psb_loop:
    cmp rbx, r13
    jge .psb_done
    ; single-byte check: string literal quote → PRS
    cmp byte [r12+rbx], '"'
    jne .psb_nq
    or eax, 0x02
.psb_nq:
    ; single-byte check: digit followed by '.' → float literal → PRF
    ; e.g. "3.14" — check current byte is digit AND next byte is '.'
    movzx ecx, byte [r12+rbx]
    cmp ecx, '0'
    jl .psb_nfl
    cmp ecx, '9'
    jg .psb_nfl
    mov r8, r13
    sub r8, rbx
    cmp r8, 2
    jl .psb_nfl
    cmp byte [r12+rbx+1], '.'
    jne .psb_nfl
    or eax, 0x08
.psb_nfl:
    ; multi-byte keyword checks: need at least 4 bytes remaining
    mov r8, r13
    sub r8, rbx
    cmp r8, 4
    jl .psb_next
    mov r8d, dword [r12+rbx]   ; load 4 bytes as little-endian dword
    ; "floa" (float) → PRF
    cmp r8d, 0x616F6C66
    jne .p1
    or eax, 0x08
.p1:; "bool" → PRB
    cmp r8d, 0x6C6F6F62
    jne .p2
    or eax, 0x04
.p2:; "true" → PRB
    cmp r8d, 0x65757274
    jne .p3
    or eax, 0x04
.p3:; "fals" (false) → PRB
    cmp r8d, 0x736C6166
    jne .p4
    or eax, 0x04
.p4:; "push" → ALC
    cmp r8d, 0x68737570
    jne .p5
    or eax, 0x40
.p5:; "each" → ALC
    cmp r8d, 0x68636165
    jne .p6
    or eax, 0x40
.p6:; "dict" → ALC + PRQ + DICT blob (bit 8 = 0x100)
    cmp r8d, 0x74636964
    jne .p7
    or eax, 0x1C0
.p7:; "inpu" (input) → SIP
    cmp r8d, 0x75706E69
    jne .p8
    or eax, 0x20
.p8:; "comp" (complex) → PRC
    cmp r8d, 0x706D6F63
    jne .p9
    or eax, 0x10
.p9:; "memo" → ALC : m(6D) e(65) m(6D) o(6F) → 0x6F6D656D
    cmp r8d, 0x6F6D656D
    jne .pe
    or eax, 0x40
.pe:; "err " → PRQ : e(65) r(72) r(72) space(20) → 0x20727265
    cmp r8d, 0x20727265
    jne .pf2
    or eax, 0x80
.pf2:; "use " → ALC : u(75) s(73) e(65) space(20) → 0x20657375
    cmp r8d, 0x20657375
    jne .pb
    or eax, 0x40
.pb:; 3-byte patterns (safe since >= 4 bytes remain)
    ; "str" → PRS : low 3 bytes = s(73) t(74) r(72) → 0x00727473
    mov ecx, r8d
    and ecx, 0x00FFFFFF
    cmp ecx, 0x00727473
    jne .pa
    or eax, 0x02
.pa:; "seq" → ALC : s(73) e(65) q(71) → 0x00716573
    cmp ecx, 0x00716573
    jne .psb_next
    or eax, 0x40
.psb_next:
    inc rbx
    jmp .psb_loop
.psb_done:
    pop r8
    pop r13
    pop r12
    pop rbx
    ret
