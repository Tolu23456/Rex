; ============================================================
; rt_alc — simple mmap-based allocator
; Input:  rdi = size in bytes requested (> 0)
; Output: rax = pointer to zeroed memory, or calls exit(1) on OOM
; Clobbers: rax, rdi, rsi, rdx, r8, r9, r10
; Preserves: rbx, rcx, rbp, r11–r15
; ============================================================
bits 64
%include "rex_defs.inc"
org LOAD_BASE + RT_ALC_OFFSET

rt_alc_blob:
    test    rdi, rdi
    jz      .fail
    cmp     rdi, 0x7fffffff8         ; sanity: < 8 GB
    ja      .oom

    ; align size to 8 bytes
    add     rdi, 7
    and     rdi, ~7

    ; mmap(NULL, size, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0)
    mov     rsi, rdi                ; length = aligned size
    mov     rax, SYS_mmap           ; 9
    xor     edi, edi                ; addr = NULL
    mov     edx, 3                  ; PROT_READ | PROT_WRITE
    mov     r10, 0x22               ; MAP_PRIVATE | MAP_ANONYMOUS
    mov     r8,  -1                 ; fd = -1
    xor     r9d, r9d                ; offset = 0
    syscall

    ; MAP_FAILED = (void*) -1
    cmp     rax, -1
    je      .oom
    test    rax, rax
    jz      .fail
    ret

.fail:
    xor     eax, eax
    ret

.oom:
    ; Print "rex: out of memory\n" to stderr and exit(1)
    lea     rsi, [rel .oom_msg]
    mov     rax, SYS_write
    mov     rdi, 2
    mov     rdx, 20
    syscall
    mov     rax, SYS_exit
    mov     rdi, 1
    syscall

.oom_msg:
    db "rex: out of memory", 0x0a, 0

times RT_ALC_SIZE - ($ - rt_alc_blob) db 0x90
