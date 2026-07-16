; rt_seq.asm - Sequence runtime operations for Rex
; Provides: rt_seq_new, rt_seq_push, rt_seq_get, rt_seq_len, rt_seq_set
;           rt_seq_insert, rt_seq_remove
; Seq layout: [capacity:8][length:8][data: element_size * capacity]
BITS 64

section .text
    global rt_seq_new
    global rt_seq_push
    global rt_seq_get
    global rt_seq_set
    global rt_seq_len
    global rt_seq_free
    global rt_seq_pop
    global rt_seq_insert
    global rt_seq_remove
    global rt_seq_count_of

; rt_seq_new: Create a new sequence
; rdi = element size (8 for int/float/str, 1 for bool/char/byte)
; rsi = initial capacity
; Returns: rax = pointer to seq header
rt_seq_new:
    push rbx
    push r12
    push r13
    push r14
    cld
    mov rbx, rdi        ; element size
    mov r12, rsi        ; capacity

    ; Calculate total size: 16 (header) + capacity * element_size
    mov rax, r12
    imul rax, rbx
    add rax, 16         ; header size
    mov r13, rax        ; total size

    ; Allocate memory using brk syscall
    ; Get current brk
    mov rax, 12         ; sys_brk
    xor rdi, rdi
    syscall
    mov r14, rax        ; current brk
    ; Grow brk by r13 bytes
    mov rdi, r14
    add rdi, r13
    mov rax, 12         ; sys_brk
    syscall
    ; rax = new brk, r14 = old brk (start of our allocation)

    ; Initialize header
    mov [r14], r12      ; capacity
    mov qword [r14 + 8], 0  ; length = 0

    mov rax, r14        ; return pointer
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rt_seq_push: Push element to end of sequence
; rdi = seq pointer
; rsi = value to push
; rdx = element size
; Returns: rax = seq pointer (may have reallocated)
rt_seq_push:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi        ; seq pointer
    mov r12, rsi        ; value
    mov r13, rdx        ; element size

    ; Check if we need to grow
    mov r14, [rbx]      ; capacity
    mov rax, [rbx + 8]  ; length
    cmp rax, r14
    jl .push_store

    ; Need to grow - double capacity
    shl r14, 1

    ; Calculate new total size: 16 + capacity * element_size
    mov rax, r14
    imul rax, r13
    add rax, 16

    ; Allocate new buffer via brk
    mov rdi, rax
    mov rax, 12         ; sys_brk
    syscall
    ; rax = new buffer start, save it
    mov r15, rax        ; r15 = new buffer

    ; Copy header
    mov [r15], r14      ; new capacity
    mov rcx, [rbx + 8]  ; old length
    mov [r15 + 8], rcx  ; copy length

    ; Copy data
    imul rcx, r13       ; old data bytes
    test rcx, rcx
    jz .push_copy_done
    lea rsi, [rbx + 16] ; src = old data
    lea rdi, [r15 + 16] ; dest = new data
.push_copy_loop:
    movzx eax, byte [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jnz .push_copy_loop
.push_copy_done:
    mov rbx, r15        ; use new buffer

.push_store:
    ; Store element at data[length]
    mov rax, [rbx + 8]  ; length
    imul rax, r13       ; offset = length * element_size
    add rax, 16         ; skip header
    add rax, rbx        ; absolute address
    mov [rax], r12      ; store value

    ; Increment length
    inc qword [rbx + 8]

    mov rax, rbx        ; return seq pointer
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rt_seq_get: Get element at index
; rdi = seq pointer
; rsi = index
; rdx = element size
; Returns: rax = element value
rt_seq_get:
    push rbx
    mov rbx, rdi        ; seq pointer

    ; Calculate offset: index * element_size + 16
    mov rax, rsi
    imul rax, rdx
    add rax, 16
    add rax, rbx
    mov rax, [rax]      ; load element

    pop rbx
    ret

; rt_seq_set: Set element at index
; rdi = seq pointer
; rsi = index
; rdx = value
; rcx = element size
rt_seq_set:
    push rbx
    mov rbx, rdi        ; seq pointer

    ; Calculate offset: index * element_size + 16
    mov rax, rsi
    imul rax, rcx
    add rax, 16
    add rax, rbx
    mov [rax], rdx      ; store value

    pop rbx
    ret

; rt_seq_len: Get sequence length
; rdi = seq pointer
; Returns: rax = length
rt_seq_len:
    mov rax, [rdi + 8]
    ret

; rt_seq_free: Free sequence (no-op for now, heap is bump-allocated)
; rdi = seq pointer
rt_seq_free:
    ret

; rt_seq_pop: Pop last element from sequence
; rdi = seq pointer
; rsi = element size
; Returns: rax = popped value (0 if empty)
rt_seq_pop:
    push rbx
    mov rbx, rdi
    mov rax, [rbx + 8]
    test rax, rax
    jz .pop_empty
    dec rax
    mov [rbx + 8], rax
    imul rax, rsi
    add rax, 16
    add rax, rbx
    mov rax, [rax]
    pop rbx
    ret
.pop_empty:
    xor rax, rax
    pop rbx
    ret

; rt_seq_insert: Insert element at index, shifting elements right
; rdi = seq pointer
; rsi = index
; rdx = value
; rcx = element size
; Returns: rax = seq pointer
rt_seq_insert:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
    mov r14, rsi
    mov r12, rdx
    mov r13, rcx
    mov rax, [rbx + 8]    ; length
    cmp r14, rax
    ja .insert_done         ; index > length, bail
    mov r15, [rbx]         ; capacity
    cmp rax, r15
    jl .insert_nogrow
    ; Need to grow - double capacity and reallocate
    shl r15, 1
    ; Calculate new total size
    mov r8, r15
    imul r8, r13
    add r8, 16
    ; Allocate new buffer
    push rbx
    mov rdi, r8
    mov rax, 12            ; sys_brk
    syscall
    ; rax = new buffer
    mov r9, rax            ; r9 = new buffer
    pop rbx
    ; Copy header
    mov [r9], r15          ; new capacity
    mov rcx, [rbx + 8]    ; old length
    mov [r9 + 8], rcx     ; copy length
    ; Copy data
    imul rcx, r13
    test rcx, rcx
    jz .insert_copy_done
    lea rsi, [rbx + 16]
    lea rdi, [r9 + 16]
.insert_copy_loop:
    movzx eax, byte [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jnz .insert_copy_loop
.insert_copy_done:
    mov rbx, r9            ; use new buffer
.insert_nogrow:
    mov r15, [rbx + 8]     ; length (reload)
    test r15, r15
    jz .insert_store
    lea rax, [r15 - 1]     ; i = length-1
.insert_loop:
    cmp rax, r14
    jl .insert_store
    mov rcx, rax
    imul rcx, r13
    add rcx, 16
    mov rdx, rax
    inc rdx
    imul rdx, r13
    add rdx, 16
    mov rsi, [rbx + rcx]
    mov [rbx + rdx], rsi
    dec rax
    jmp .insert_loop
.insert_store:
    mov rax, r14
    imul rax, r13
    add rax, 16
    mov [rbx + rax], r12
    inc qword [rbx + 8]
.insert_done:
    mov rax, rbx
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rt_seq_remove: Remove element at index, shifting elements left
; rdi = seq pointer
; rsi = index
; rdx = element size
; Returns: rax = removed element value (0 if out of bounds)
rt_seq_remove:
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rax, [rbx + 8]    ; length
    test rax, rax
    jz .remove_oob
    cmp r12, rax
    jae .remove_oob
    mov rax, r12
    imul rax, r13
    add rax, 16
    mov r14, [rbx + rax]  ; removed value
    mov rax, r12           ; i = index
.remove_loop:
    mov rcx, [rbx + 8]
    dec rcx
    cmp rax, rcx
    jge .remove_done
    mov rcx, rax
    inc rcx
    imul rcx, r13
    add rcx, 16
    mov rdx, [rbx + rcx]  ; data[i+1]
    mov rcx, rax
    imul rcx, r13
    add rcx, 16
    mov [rbx + rcx], rdx  ; data[i] = data[i+1]
    inc rax
    jmp .remove_loop
.remove_done:
    dec qword [rbx + 8]
    mov rax, r14
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.remove_oob:
    xor rax, rax
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rt_seq_contains: Check if seq contains value
; rdi = seq pointer, rsi = value, rdx = element size
; Returns: rax = 1 if found, 0 if not
rt_seq_contains:
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, [rbx + 8]    ; length
    xor rcx, rcx           ; i = 0
.contains_loop:
    cmp rcx, r14
    jge .contains_not_found
    mov rax, rcx
    imul rax, r13
    add rax, 16
    mov rax, [rbx + rax]  ; data[i]
    cmp rax, r12
    je .contains_found
    inc rcx
    jmp .contains_loop
.contains_found:
    mov rax, 1
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.contains_not_found:
    xor rax, rax
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rt_seq_index_of: Find index of value in seq
; rdi = seq pointer, rsi = value, rdx = element size
; Returns: rax = index, or -1 if not found
rt_seq_index_of:
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, [rbx + 8]
    xor rcx, rcx
.index_loop:
    cmp rcx, r14
    jge .index_not_found
    mov rax, rcx
    imul rax, r13
    add rax, 16
    mov rax, [rbx + rax]
    cmp rax, r12
    je .index_found
    inc rcx
    jmp .index_loop
.index_found:
    mov rax, rcx
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.index_not_found:
    mov rax, -1
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rt_seq_copy: Create a copy of a seq
; rdi = seq pointer, rsi = element size
; Returns: rax = new seq pointer
rt_seq_copy:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx]        ; capacity
    mov r14, [rbx + 8]    ; length
    ; Inline allocation (same as rt_seq_new but without call)
    mov rax, r13
    imul rax, r12
    add rax, 16           ; header size
    mov r15, rax           ; total size
    ; Get current brk
    mov rax, 12
    xor rdi, rdi
    syscall
    mov rcx, rax           ; current brk
    ; Grow brk
    mov rdi, rcx
    add rdi, r15
    mov rax, 12
    syscall
    mov r15, rcx           ; new seq pointer
    ; Initialize header
    mov [r15], r13         ; capacity
    mov [r15 + 8], r14     ; length = src length
    ; Copy data
    xor rcx, rcx
.copy_loop:
    cmp rcx, r14
    jge .copy_done
    mov rax, rcx
    imul rax, r12
    add rax, 16
    mov rdx, [rbx + rax]  ; src[i]
    mov [r15 + rax], rdx  ; dst[i]
    inc rcx
    jmp .copy_loop
.copy_done:
    mov rax, r15
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rt_seq_reverse: Reverse seq in place
; rdi = seq pointer, rsi = element size
rt_seq_reverse:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
    mov r12, rsi
    mov r14, [rbx + 8]    ; length
    cmp r14, 2
    jl .reverse_done
    xor r13, r13           ; left = 0
    lea r15, [r14 - 1]    ; right = len - 1
.reverse_loop:
    cmp r13, r15
    jge .reverse_done
    ; Swap data[left] and data[right]
    mov rax, r13
    imul rax, r12
    add rax, 16
    mov rcx, [rbx + rax]  ; tmp = data[left]
    mov rdx, r15
    imul rdx, r12
    add rdx, 16
    mov rsi, [rbx + rdx]  ; data[right]
    mov [rbx + rax], rsi  ; data[left] = data[right]
    mov [rbx + rdx], rcx  ; data[right] = tmp
    inc r13
    dec r15
    jmp .reverse_loop
.reverse_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rt_seq_sum: Sum all elements
; rdi = seq pointer, rsi = element size
; Returns: rax = sum
rt_seq_sum:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx + 8]    ; length
    xor rax, rax           ; sum = 0
    xor rcx, rcx
.sum_loop:
    cmp rcx, r13
    jge .sum_done
    mov rdx, rcx
    imul rdx, r12
    add rdx, 16
    add rax, [rbx + rdx]
    inc rcx
    jmp .sum_loop
.sum_done:
    pop r13
    pop r12
    pop rbx
    ret

; rt_seq_min: Find minimum element
; rdi = seq pointer, rsi = element size
; Returns: rax = min value (0 if empty)
rt_seq_min:
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx + 8]
    test r13, r13
    jz .min_empty
    mov rax, [rbx + 16]  ; min = data[0]
    mov r14, 1            ; i = 1
.min_loop:
    cmp r14, r13
    jge .min_done
    mov rcx, r14
    imul rcx, r12
    add rcx, 16
    mov rdx, [rbx + rcx]
    cmp rdx, rax
    cmovl rax, rdx
    inc r14
    jmp .min_loop
.min_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.min_empty:
    xor rax, rax
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rt_seq_max: Find maximum element
; rdi = seq pointer, rsi = element size
; Returns: rax = max value (0 if empty)
rt_seq_max:
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx + 8]
    test r13, r13
    jz .max_empty
    mov rax, [rbx + 16]  ; max = data[0]
    mov r14, 1
.max_loop:
    cmp r14, r13
    jge .max_done
    mov rcx, r14
    imul rcx, r12
    add rcx, 16
    mov rdx, [rbx + rcx]
    cmp rdx, rax
    cmovg rax, rdx
    inc r14
    jmp .max_loop
.max_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.max_empty:
    xor rax, rax
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rt_seq_clear: Clear sequence (set length to 0)
; rdi = seq pointer
rt_seq_clear:
    mov qword [rdi + 8], 0
    ret

; rt_seq_cap: Get capacity
; rdi = seq pointer
; Returns: rax = capacity
rt_seq_cap:
    mov rax, [rdi]
    ret

; rt_seq_count_of: Count occurrences of value in sequence
; rdi = seq pointer, rsi = value to count, rdx = element_size
; Returns: rax = count
rt_seq_count_of:
    push rbx
    push r12
    push r13
    mov r12, rdi        ; seq pointer
    mov rbx, rsi        ; value to count
    mov r13, rdx        ; element size
    xor eax, eax        ; count = 0
    mov rcx, [r12 + 8]  ; length
    test rcx, rcx
    jz .count_done
    lea r11, [r12 + 16] ; data pointer
.count_loop:
    ; Load element based on element_size
    cmp r13, 8
    je .count_load_8
    cmp r13, 4
    je .count_load_4
    cmp r13, 2
    je .count_load_2
    ; element_size == 1
    movzx edx, byte [r11]
    jmp .count_cmp
.count_load_8:
    mov rdx, [r11]
    jmp .count_cmp
.count_load_4:
    mov edx, dword [r11]
    jmp .count_cmp
.count_load_2:
    movzx edx, word [r11]
.count_cmp:
    cmp rdx, rbx
    jne .count_next
    inc eax             ; match found
.count_next:
    add r11, r13        ; advance by element_size
    dec rcx
    jnz .count_loop
.count_done:
    pop r13
    pop r12
    pop rbx
    ret

; Pad to 2048 bytes to accommodate new functions
