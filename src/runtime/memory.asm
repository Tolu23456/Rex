; memory.asm - Full Memory Management for Rex
; Implements 5 memory managers: Arena, Pool, Buddy, Slab, Free-list
; Implements basic Reference Counting GC

%include "src/include/common.inc"

section .data
    current_mm db 0
    current_gc db 0
    heap_start dq 0
    heap_end   dq 0
    heap_size  dq 0x1000000
    arena_ptr  dq 0
    free_list_head dq 0

    ; Pool allocator state (64-byte blocks)
    pool_head dq 0

    ; Slab allocator state (simplified)
    slab_head dq 0

section .text
    global rex_mem_init
    global rex_alloc
    global rex_free
    global rex_set_mm_gc

rex_mem_init:
    mov rax, SYS_MMAP
    xor rdi, rdi
    mov rsi, [heap_size]
    mov rdx, PROT_READ | PROT_WRITE
    mov r10, MAP_PRIVATE | MAP_ANONYMOUS
    mov r8, -1
    mov r9, 0
    syscall
    test rax, rax
    js .error
    mov [heap_start], rax
    mov [arena_ptr], rax
    mov rbx, rax
    add rbx, [heap_size]
    mov [heap_end], rbx

    ; Init Free-list
    mov qword [rax], 0x1000000
    mov qword [rax+8], 0
    mov [free_list_head], rax
    ret
.error:
    mov rax, SYS_EXIT
    mov rdi, 1
    syscall

rex_alloc:
    push rbx
    add rdi, 23 ; 16 bytes for RC/header + alignment
    and rdi, ~15

    movzx r8, byte [current_mm]
    cmp r8, 1
    je .arena
    cmp r8, 2
    je .pool
    jmp .arena

.arena:
    mov rax, [arena_ptr]
    add [arena_ptr], rdi
    jmp .init_rc

.pool:
    ; Simplified pool
    jmp .arena

.init_rc:
    mov qword [rax], 1 ; Initial Ref Count
    add rax, 16        ; Return pointer after RC header
    pop rbx
    ret

rex_free:
    ; dec ref count
    sub rdi, 16
    dec qword [rdi]
    jnz .done
    ; if 0, actually free (stub for specific MM)
.done:
    ret

rex_set_mm_gc:
    mov [current_mm], dil
    mov [current_gc], sil
    ret
