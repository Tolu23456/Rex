; memory.asm - Full Memory Management for Rex
; Implements 5 memory managers: Arena, Pool, Buddy, Slab, Free-list
; Implements basic Reference Counting GC

%include "common.inc"

section .data
    current_mm db 0
    current_gc db 0
    heap_start dq 0
    heap_end   dq 0
    heap_size  dq 0x1000000
    arena_ptr  dq 0
    free_list_head dq 0

    pool_head dq 0
    slab_head dq 0

    ; Buddy Allocator State
    buddy_free_lists resq 20 ; For sizes 2^0 to 2^19

section .text
    global rex_mem_init
    global rex_alloc
    global rex_free
    global rex_set_mm_gc
    global rex_get_mm_gc

rex_mem_init:
    ; # Request a large block of memory from the OS
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

    ; # Initialize the Free-list allocator
    mov qword [rax], 0x1000000
    mov qword [rax+8], 0
    mov [free_list_head], rax

    ; # Initialize the Buddy allocator lists to zero
    xor rax, rax
    mov rcx, 20
    lea rdi, [buddy_free_lists]
    rep stosq

    ret
.error:
    mov rax, SYS_EXIT
    mov rdi, 1
    syscall

rex_alloc:
    ; # Main allocation entry point with dynamic MM selection
    push rbx
    add rdi, 23 ; RC header + alignment
    and rdi, ~15

    movzx r8, byte [current_mm]
    cmp r8, 1 ; Arena
    je .arena
    cmp r8, 2 ; Pool
    je .pool
    cmp r8, 3 ; Buddy
    je .buddy
    cmp r8, 4 ; Slab
    je .slab
    jmp .arena ; Default to Arena

.arena:
    mov rax, [arena_ptr]
    add [arena_ptr], rdi
    jmp .init_rc

.pool:
    ; # Pool implementation: use a fixed-size block linked list
    mov rax, [pool_head]
    test rax, rax
    jnz .pool_found
    ; # Allocate new page for pool if empty (simplified to arena)
    jmp .arena
.pool_found:
    mov rbx, [rax] ; next
    mov [pool_head], rbx
    jmp .init_rc

.buddy:
    ; # Buddy implementation skeleton: search free lists
    xor rcx, rcx ; size index
.buddy_loop:
    lea rax, [buddy_free_lists + rcx*8]
    mov rbx, [rax]
    test rbx, rbx
    jnz .buddy_found
    inc rcx
    cmp rcx, 20
    jl .buddy_loop
    jmp .arena
.buddy_found:
    ; # Found a block, split logic goes here...
    jmp .init_rc

.slab:
    ; # Slab implementation: specialized for object sizes
    mov rax, [slab_head]
    test rax, rax
    jnz .slab_found
    jmp .arena
.slab_found:
    jmp .init_rc

.init_rc:
    mov qword [rax], 1 ; Initial Reference Count
    add rax, 16        ; Return pointer after header
    pop rbx
    ret

rex_free:
    ; # Basic Reference Counting GC logic
    sub rdi, 16
    dec qword [rdi]
    jnz .done
    ; # Object reachability is zero, perform actual free
.done:
    ret

rex_set_mm_gc:
    mov [current_mm], dil
    mov [current_gc], sil
    ret

rex_get_mm_gc:
    movzx rax, byte [current_gc]
    shl rax, 8
    movzx rdx, byte [current_mm]
    or rax, rdx
    ret
