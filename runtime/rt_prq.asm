; ============================================================
; rt_prq — print error string to stderr + exit(1)
; Input:  rdi = pointer to null-terminated error message
; Also contains: rt_dict_new, rt_dict_set, rt_dict_get
;
; Dict layout (allocated via rt_alc):
;   [0]        cap  (qword) — number of bucket slots
;   [8]        len  (qword) — number of entries
;   [16..]     buckets: each 24 bytes = {hash:q, key_ptr:q, value:q}
; ============================================================
bits 64
%include "rex_defs.inc"
org LOAD_BASE + RT_PRQ_OFFSET

; ---- rt_prq: stderr print + exit(1) ----
; Must be first entry in blob (RT_PRQ_OFFSET points here)
rt_prq_blob:
    push    r12
    mov     r12, rdi

    ; find length
    xor     eax, eax
    mov     rcx, 0x7fffffff
    repne   scasb
    not     ecx
    dec     ecx                 ; ecx = strlen

    ; write to stderr (fd=2)
    mov     rax, 1
    mov     rdi, 2
    mov     rsi, r12
    mov     rdx, rcx
    syscall

    ; write '\n'
    push    qword 0x0a
    mov     rax, 1
    mov     rdi, 2
    mov     rsi, rsp
    mov     rdx, 1
    syscall
    add     rsp, 8

    pop     r12
    mov     rax, SYS_exit
    mov     rdi, 1
    syscall
    ; never returns

; ============================================================
; rt_dict_new — allocate a new dict with default capacity
; Input:  none
; Output: rax = dict pointer (cap=16, len=0)
; ============================================================
; Offset from rt_prq_blob start = current position
rt_dict_new:
    ; size = 16 (header) + 16 buckets * 24 = 400 bytes
    push    rbx
    mov     rdi, 400
    call    LOAD_BASE + RT_ALC_OFFSET
    test    rax, rax
    jz      .fail
    mov     rbx, rax
    mov     qword [rbx],   16   ; cap = 16
    mov     qword [rbx+8], 0    ; len = 0
    ; zero out buckets
    lea     rdi, [rbx+16]
    mov     ecx, 400-16
    xor     eax, eax
    rep     stosb
    mov     rax, rbx
    pop     rbx
    ret
.fail:
    xor     eax, eax
    pop     rbx
    ret

; ============================================================
; rt_dict_set — set dict[key] = value
; Input:  rdi = dict ptr, rsi = key ptr, rdx = key len, rcx = value
; Output: rax = dict ptr (may change on resize)
; ============================================================
rt_dict_set:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8

    mov     r12, rdi            ; dict ptr
    mov     r13, rsi            ; key ptr
    mov     r14, rdx            ; key len
    mov     r15, rcx            ; value

    ; hash the key
    mov     rdi, r13
    mov     rsi, r14
    call    LOAD_BASE + RT_SIP_OFFSET

    mov     rbx, rax            ; rbx = hash

    ; slot = hash % cap
    mov     rcx, [r12]          ; cap
    xor     edx, edx
    mov     rax, rbx
    div     rcx                 ; rdx = slot index

.probe_loop:
    ; bucket address = r12 + 16 + slot * 24
    mov     r8, rdx
    imul    r8, 24
    lea     r9, [r12 + 16 + r8] ; r9 = bucket ptr

    mov     r10, [r9]           ; bucket.hash
    test    r10, r10
    jz      .empty_slot         ; empty bucket

    ; check for same key (hash match first)
    cmp     r10, rbx
    jne     .next_slot

    ; hash matches — verify key equality
    mov     rdi, [r9 + 8]       ; stored key ptr
    mov     rsi, r13            ; new key ptr
    call    .strcmp_rdi_rsi
    test    rax, rax
    jz      .update_slot        ; keys equal

.next_slot:
    ; linear probe
    inc     rdx
    mov     rcx, [r12]
    cmp     rdx, rcx
    jb      .probe_loop
    xor     edx, edx
    jmp     .probe_loop

.empty_slot:
    mov     [r9],       rbx     ; store hash
    mov     [r9 + 8],   r13     ; store key ptr
    mov     [r9 + 16],  r15     ; store value
    inc     qword [r12 + 8]     ; len++
    mov     rax, r12
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

.update_slot:
    mov     [r9 + 16], r15      ; update value
    mov     rax, r12
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; strcmp helper: rdi=s1, rsi=s2 → rax=0 if equal
.strcmp_rdi_rsi:
.cmp_loop:
    movzx   eax, byte [rdi]
    movzx   ecx, byte [rsi]
    test    eax, eax
    jz      .cmp_end
    cmp     al, cl
    jne     .cmp_ne
    inc     rdi
    inc     rsi
    jmp     .cmp_loop
.cmp_end:
    xor     eax, eax
    ret
.cmp_ne:
    mov     eax, 1
    ret

; ============================================================
; rt_dict_get — get dict[key] → value or 0 if not found
; Input:  rdi = dict ptr, rsi = key ptr, rdx = key len
; Output: rax = value or 0
; ============================================================
rt_dict_get:
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     r12, rdi            ; dict ptr
    mov     r13, rsi            ; key ptr
    mov     r14, rdx            ; key len

    ; hash the key
    mov     rdi, r13
    mov     rsi, r14
    call    LOAD_BASE + RT_SIP_OFFSET

    mov     rbx, rax            ; hash

    mov     rcx, [r12]
    xor     edx, edx
    div     rcx                 ; rdx = slot

.get_probe:
    mov     r8, rdx
    imul    r8, 24
    lea     r9, [r12 + 16 + r8]

    mov     r10, [r9]
    test    r10, r10
    jz      .not_found

    cmp     r10, rbx
    jne     .get_next

    mov     rdi, [r9 + 8]
    mov     rsi, r13
    call    rt_dict_set.strcmp_rdi_rsi
    test    rax, rax
    jnz     .get_next

    mov     rax, [r9 + 16]      ; found!
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

.get_next:
    inc     rdx
    mov     rcx, [r12]
    cmp     rdx, rcx
    jb      .get_probe
    xor     edx, edx
    jmp     .get_probe

.not_found:
    xor     eax, eax
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

times RT_PRQ_SIZE - ($ - rt_prq_blob) db 0x90
