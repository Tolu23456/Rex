; runtime.asm - PIC machine-code blobs embedded verbatim into the generated binary
;
; rt_pri  (63 bytes): print 64-bit unsigned integer in rdi to stdout + newline
; rt_prs  (13 bytes): write(1, rsi, rdx)  — print string of known length
;
; Both functions are position-independent: they use only RSP-relative addressing
; and Linux syscalls, so they work at any load address.

global rt_pri_blob
global rt_pri_blob_end
global rt_prs_blob
global rt_prs_blob_end

section .data

; ─── rt_pri : print integer in rdi ──────────────────────────────────────────
; Disassembly of the bytes below (verified offsets in comments):
;  +00  48 89 F8              mov rax, rdi
;  +03  48 83 EC 18           sub rsp, 24
;  +07  48 8D 74 24 16        lea rsi, [rsp+22]    ; rsi → just before newline slot
;  +0C  C6 06 0A              mov byte [rsi], 10   ; newline at [rsp+22]
;  +0F  BB 0A 00 00 00        mov ebx, 10          ; divisor
;       ── loop top (offset 0x14) ──
;  +14  31 D2                 xor edx, edx
;  +16  48 F7 F3              div rbx
;  +19  80 C2 30              add dl, 48           ; digit → ASCII
;  +1C  48 FF CE              dec rsi
;  +1F  88 16                 mov [rsi], dl
;  +21  48 85 C0              test rax, rax
;  +24  75 EE                 jnz -18              ; back to offset 0x14
;       ── after loop ──
;  +26  48 8D 54 24 17        lea rdx, [rsp+23]    ; one past newline
;  +2B  48 29 F2              sub rdx, rsi         ; rdx = length
;  +2E  BF 01 00 00 00        mov edi, 1           ; fd = stdout
;  +33  B8 01 00 00 00        mov eax, 1           ; sys_write
;  +38  0F 05                 syscall
;  +3A  48 83 C4 18           add rsp, 24
;  +3E  C3                    ret
;       total = 63 bytes  (= RT_PRI_SIZE)
rt_pri_blob:
    db 0x48, 0x89, 0xF8                         ; mov rax, rdi
    db 0x48, 0x83, 0xEC, 0x18                   ; sub rsp, 24
    db 0x48, 0x8D, 0x74, 0x24, 0x16             ; lea rsi, [rsp+22]
    db 0xC6, 0x06, 0x0A                         ; mov byte [rsi], 10
    db 0xBB, 0x0A, 0x00, 0x00, 0x00             ; mov ebx, 10
    db 0x31, 0xD2                               ; xor edx, edx       ← loop top
    db 0x48, 0xF7, 0xF3                         ; div rbx
    db 0x80, 0xC2, 0x30                         ; add dl, 48
    db 0x48, 0xFF, 0xCE                         ; dec rsi
    db 0x88, 0x16                               ; mov [rsi], dl
    db 0x48, 0x85, 0xC0                         ; test rax, rax
    db 0x75, 0xEE                               ; jnz -18  (→ loop top)
    db 0x48, 0x8D, 0x54, 0x24, 0x17             ; lea rdx, [rsp+23]
    db 0x48, 0x29, 0xF2                         ; sub rdx, rsi
    db 0xBF, 0x01, 0x00, 0x00, 0x00             ; mov edi, 1
    db 0xB8, 0x01, 0x00, 0x00, 0x00             ; mov eax, 1
    db 0x0F, 0x05                               ; syscall
    db 0x48, 0x83, 0xC4, 0x18                   ; add rsp, 24
    db 0xC3                                     ; ret
rt_pri_blob_end:

; ─── rt_prs : print string  (rsi=ptr, rdx=len) ──────────────────────────────
; +00  BF 01 00 00 00         mov edi, 1
; +05  B8 01 00 00 00         mov eax, 1
; +0A  0F 05                  syscall
; +0C  C3                     ret
;      total = 13 bytes  (= RT_PRS_SIZE)
rt_prs_blob:
    db 0xBF, 0x01, 0x00, 0x00, 0x00             ; mov edi, 1
    db 0xB8, 0x01, 0x00, 0x00, 0x00             ; mov eax, 1
    db 0x0F, 0x05                               ; syscall
    db 0xC3                                     ; ret
rt_prs_blob_end:
