; ============================================================
; rt_strm — string method runtime functions
; Offsets from blob start:
;   0    strlen(rdi=ptr) → rax=len
;   64   upper(rdi=src) → rax=new ptr (allocated)
;  512   lower(rdi=src) → rax=new ptr (allocated)
; 1024   trim(rdi=src) → rax=new ptr (allocated)
; 1536   contains(rdi=haystack, rsi=needle) → rax=1/0
; ============================================================
bits 64
%include "rex_defs.inc"
org LOAD_BASE + RT_STRM_OFFSET

rt_strm_blob:

; ---- strlen at offset 0 ----
rt_strm_strlen:
    xor     eax, eax
.str_len_loop:
    cmp     byte [rdi + rax], 0
    je      .str_len_done
    inc     rax
    jmp     .str_len_loop
.str_len_done:
    ret
    times 64 - ($ - rt_strm_strlen) db 0x90

; ---- upper at offset 64 ----
rt_strm_upper:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi            ; r12 = src ptr
    ; strlen
    call    rt_strm_strlen      ; rax = len
    mov     r13, rax            ; r13 = len
    ; alloc len+1
    lea     rdi, [rax + 1]
    call    LOAD_BASE + RT_ALC_OFFSET
    test    rax, rax
    jz      .upper_fail
    mov     rbx, rax            ; rbx = dst
    ; copy + uppercase
    xor     rcx, rcx
.upper_loop:
    cmp     rcx, r13
    jge     .upper_done
    movzx   edx, byte [r12 + rcx]
    cmp     dl, 'a'
    jb      .upper_store
    cmp     dl, 'z'
    ja      .upper_store
    sub     dl, 32
.upper_store:
    mov     [rbx + rcx], dl
    inc     rcx
    jmp     .upper_loop
.upper_done:
    mov     byte [rbx + r13], 0
    mov     rax, rbx
    pop     r13
    pop     r12
    pop     rbx
    ret
.upper_fail:
    xor     eax, eax
    pop     r13
    pop     r12
    pop     rbx
    ret
    times 512 - ($ - rt_strm_blob) db 0x90

; ---- lower at offset 512 ----
rt_strm_lower:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi
    call    rt_strm_strlen
    mov     r13, rax
    lea     rdi, [rax + 1]
    call    LOAD_BASE + RT_ALC_OFFSET
    test    rax, rax
    jz      .lower_fail
    mov     rbx, rax
    xor     rcx, rcx
.lower_loop:
    cmp     rcx, r13
    jge     .lower_done
    movzx   edx, byte [r12 + rcx]
    cmp     dl, 'A'
    jb      .lower_store
    cmp     dl, 'Z'
    ja      .lower_store
    add     dl, 32
.lower_store:
    mov     [rbx + rcx], dl
    inc     rcx
    jmp     .lower_loop
.lower_done:
    mov     byte [rbx + r13], 0
    mov     rax, rbx
    pop     r13
    pop     r12
    pop     rbx
    ret
.lower_fail:
    xor     eax, eax
    pop     r13
    pop     r12
    pop     rbx
    ret
    times 1024 - ($ - rt_strm_blob) db 0x90

; ---- trim at offset 1024 ----
rt_strm_trim:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi            ; r12 = src
    call    rt_strm_strlen
    mov     r13, rax            ; r13 = len
    test    rax, rax
    jz      .trim_empty
    ; find first non-space
    xor     r14, r14            ; r14 = start
.trim_start:
    cmp     r14, r13
    jge     .trim_empty
    movzx   edi, byte [r12 + r14]
    cmp     dil, ' '
    je      .trim_inc_s
    cmp     dil, 0x09
    je      .trim_inc_s
    cmp     dil, 0x0A
    je      .trim_inc_s
    cmp     dil, 0x0D
    je      .trim_inc_s
    jmp     .trim_found_start
.trim_inc_s:
    inc     r14
    jmp     .trim_start
.trim_found_start:
    ; find last non-space
    lea     r15, [r13 - 1]      ; r15 = end index
.trim_end:
    cmp     r15, r14
    jl      .trim_empty
    movzx   edi, byte [r12 + r15]
    cmp     dil, ' '
    je      .trim_dec_e
    cmp     dil, 0x09
    je      .trim_dec_e
    cmp     dil, 0x0A
    je      .trim_dec_e
    cmp     dil, 0x0D
    je      .trim_dec_e
    jmp     .trim_found_end
.trim_dec_e:
    dec     r15
    jmp     .trim_end
.trim_found_end:
    ; new length = r15 - r14 + 1
    mov     rcx, r15
    sub     rcx, r14
    inc     rcx                ; rcx = trimmed len
    ; alloc
    lea     rdi, [rcx + 1]
    push    rcx
    push    r14
    call    LOAD_BASE + RT_ALC_OFFSET
    pop     r14
    pop     rcx
    test    rax, rax
    jz      .trim_empty
    ; copy
    mov     rbx, rax
    xor     rdx, rdx
.trim_copy:
    cmp     rdx, rcx
    jge     .trim_copy_done
    lea     rax, [r12 + r14]
    movzx   edi, byte [rax + rdx]
    mov     [rbx + rdx], dil
    inc     rdx
    jmp     .trim_copy
.trim_copy_done:
    mov     byte [rbx + rcx], 0
    mov     rax, rbx
    jmp     .trim_ret
.trim_empty:
    ; alloc 1 byte for empty string
    mov     rdi, 1
    call    LOAD_BASE + RT_ALC_OFFSET
    mov     byte [rax], 0
.trim_ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
    times 1536 - ($ - rt_strm_blob) db 0x90

; ---- contains at offset 1536 ----
rt_strm_contains:
    push    rbx
    push    rcx
    push    rdx
    push    r8
    push    r9
    mov     r8, rsi             ; r8 = needle
    mov     r9, rdi             ; r9 = haystack
    ; strlen needle
    mov     rdi, r8
    push    r8
    push    r9
    call    rt_strm_strlen
    pop     r9
    pop     r8
    mov     rcx, rax            ; rcx = needle_len
    test    rcx, rcx
    jz      .ct_found           ; empty needle = found
    ; strlen haystack
    mov     rdi, r9
    push    rcx
    push    r8
    call    rt_strm_strlen
    pop     r8
    pop     rcx
    ; rax = haystack_len
    cmp     rax, rcx
    jb      .ct_notfound
    mov     rdx, rax
    sub     rdx, rcx            ; rdx = max start
    xor     rsi, rsi            ; rsi = position
.ct_outer:
    cmp     rsi, rdx
    jg      .ct_notfound
    xor     rdi, rdi            ; rdi = inner idx
.ct_inner:
    cmp     rdi, rcx
    jge     .ct_found
    lea     rax, [r9 + rsi]
    movzx   eax, byte [rax + rdi]
    cmp     al, byte [r8 + rdi]
    jne     .ct_next
    inc     rdi
    jmp     .ct_inner
.ct_next:
    inc     rsi
    jmp     .ct_outer
.ct_found:
    mov     eax, 1
    jmp     .ct_done
.ct_notfound:
    xor     eax, eax
.ct_done:
    pop     r9
    pop     r8
    pop     rdx
    pop     rcx
    pop     rbx
    ret

times RT_STRM_SIZE - ($ - rt_strm_blob) db 0x90
