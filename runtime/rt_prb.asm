; ============================================================
; rt_prb — print tri-state bool + newline to stdout
; Input:  rdi = 1 (true), 0 (neutral), −1 (false)
; Output: "true\n", "neutral\n", or "false\n" to fd 1
; Clobbers: rax, rdx, rsi, rdi
; Preserves: rbx, rbp, r12–r15
; ============================================================
bits 64
%include "rex_defs.inc"
org LOAD_BASE + RT_PRB_OFFSET

rt_prb_blob:
    test    rdi, rdi
    js      .is_false
    jnz     .is_true

    ; neutral (0)  →  "neutral\n"  (8 bytes)
    lea     rsi, [rel .neutral_str]
    mov     rax, 1
    mov     rdi, 1
    mov     rdx, 8
    syscall
    ret

.is_true:
    ; true (1)  →  "true\n"  (5 bytes)
    lea     rsi, [rel .true_str]
    mov     rax, 1
    mov     rdi, 1
    mov     rdx, 5
    syscall
    ret

.is_false:
    ; false (−1)  →  "false\n"  (6 bytes)
    lea     rsi, [rel .false_str]
    mov     rax, 1
    mov     rdi, 1
    mov     rdx, 6
    syscall
    ret

.true_str:    db "true",    0x0a
.neutral_str: db "neutral", 0x0a
.false_str:   db "false",   0x0a

times RT_PRB_SIZE - ($ - rt_prb_blob) db 0x90
