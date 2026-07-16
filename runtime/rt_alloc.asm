; rt_alloc.asm - Heap allocator for Rex
; Provides: rt_alloc (allocate N bytes, return pointer in rax)
;           rt_alloc_init (initialize heap)
; Uses brk syscall to grow the heap
BITS 64

section .bss
    heap_current resq 1    ; current heap pointer
    heap_end     resq 1    ; end of current heap region

section .text
    global rt_alloc_init
    global rt_alloc

; Initialize the heap allocator
rt_alloc_init:
    push rbx
    ; Get current brk
    mov rax, 12          ; sys_brk
    xor rdi, rdi         ; brk(0) returns current brk
    syscall
    mov [heap_current], rax
    mov [heap_end], rax
    pop rbx
    ret

; Allocate rdi bytes, return pointer in rax
; Aligns to 8 bytes
rt_alloc:
    push rbx
    mov rbx, rdi

    ; Align to 8 bytes
    add rbx, 7
    and rbx, ~7

    ; Check if we have enough space
    mov rax, [heap_current]
    add rax, rbx
    cmp rax, [heap_end]
    jle .have_space

    ; Need more space - grow by at least 4KB
    mov rdi, rax
    add rdi, 4096
    mov rax, 12          ; sys_brk
    syscall
    mov [heap_end], rax

.have_space:
    mov rax, [heap_current]
    add [heap_current], rbx
    pop rbx
    ret

; Pad to 256 bytes
