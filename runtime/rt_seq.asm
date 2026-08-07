; rt_seq.asm - Sequence runtime operations for Rex
; Provides: rt_seq_new, rt_seq_push, rt_seq_get, rt_seq_len, rt_seq_set
;           rt_seq_insert, rt_seq_remove
;
; Seq layout: [capacity:8][length:8][data_ptr:8]   (24-byte header)
; data array: [elem_size * capacity] bytes at data_ptr
;
; The header address NEVER changes once created: growth allocates a NEW data
; array and swaps data_ptr in place, so caller-held seq pointers always stay
; valid. Heap is bump-allocated via brk (two-step: brk(0) then brk(base+size)).
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
    mov rbx, rdi        ; element size
    mov r12, rsi        ; capacity

    ; Allocate header (24 bytes) via two-step brk
    mov rax, 12         ; sys_brk
    xor rdi, rdi
    syscall
    mov r13, rax        ; r13 = header start
    lea rdi, [r13 + 24]
    mov rax, 12
    syscall

    ; Allocate data array (capacity * element_size) via two-step brk
    mov rax, 12
    xor rdi, rdi
    syscall
    mov r14, rax        ; r14 = data start
    mov rax, r12
    imul rax, rbx
    mov rdi, r14
    add rdi, rax
    mov rax, 12
    syscall

    ; Initialize header
    mov [r13], r12          ; capacity
    mov qword [r13 + 8], 0  ; length = 0
    mov [r13 + 16], r14     ; data_ptr

    mov rax, r13
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rt_seq_push: Push element to end of sequence
; rdi = seq pointer
; rsi = value to push
; rdx = element size
; Returns: rax = seq pointer (header is stable, pointer never changes)
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

    ; Need to grow - double capacity, allocate new data array
    shl r14, 1
    mov rax, 12         ; sys_brk
    xor rdi, rdi
    syscall
    mov r15, rax        ; r15 = new data start
    mov rax, r14
    imul rax, r13
    mov rdi, r15
    add rdi, rax
    mov rax, 12
    syscall

    ; Copy old data bytes into new array
    mov rcx, [rbx + 8]  ; old length
    imul rcx, r13       ; old data bytes
    test rcx, rcx
    jz .push_copy_done
    mov rsi, [rbx + 16] ; old data_ptr
    mov rdi, r15        ; new data
.push_copy_loop:
    movzx eax, byte [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jnz .push_copy_loop
.push_copy_done:
    ; Swap in the new data array and capacity (header stays put)
    mov [rbx + 16], r15
    mov [rbx], r14

.push_store:
    ; Store element at data[length]
    mov rax, [rbx + 8]  ; length
    imul rax, r13
    mov rcx, [rbx + 16] ; data_ptr
    mov [rcx + rax], r12 ; store value

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
; Returns: rax = element value (0 if index out of bounds)
rt_seq_get:
    push rbx
    mov rbx, rdi        ; seq pointer
    mov rax, [rbx + 8]  ; length
    cmp rsi, rax
    jae .get_oob
    mov rax, rsi
    imul rax, rdx
    mov rcx, [rbx + 16] ; data_ptr
    mov rax, [rcx + rax]
    pop rbx
    ret
.get_oob:
    xor rax, rax
    pop rbx
    ret

; rt_seq_set: Set element at index
; rdi = seq pointer
; rsi = index
; rdx = value
; rcx = element size
; Out-of-bounds index is silently ignored
rt_seq_set:
    push rbx
    mov rbx, rdi        ; seq pointer
    mov rax, [rbx + 8]  ; length
    cmp rsi, rax
    jae .set_done
    mov rax, rsi
    imul rax, rcx
    mov rdi, [rbx + 16] ; data_ptr
    mov [rdi + rax], rdx
.set_done:
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
    mov rcx, [rbx + 16]
    mov rax, [rcx + rax]
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
; Returns: rax = seq pointer (header is stable)
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
    ; Need to grow - double capacity, allocate new data array
    shl r15, 1
    mov rax, 12            ; sys_brk
    xor rdi, rdi
    syscall
    mov r9, rax            ; r9 = new data start
    mov rax, r15
    imul rax, r13
    mov rdi, r9
    add rdi, rax
    mov rax, 12
    syscall
    ; Copy old data bytes into new array
    mov rcx, [rbx + 8]
    imul rcx, r13
    test rcx, rcx
    jz .insert_copy_done
    mov rsi, [rbx + 16]
    mov rdi, r9
.insert_copy_loop:
    movzx eax, byte [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jnz .insert_copy_loop
.insert_copy_done:
    mov [rbx + 16], r9
    mov [rbx], r15
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
    mov rdx, rax
    inc rdx
    imul rdx, r13
    mov rsi, [rbx + 16]    ; data_ptr
    mov r8, [rsi + rcx]    ; tmp = data[i]
    mov [rsi + rdx], r8    ; data[i+1] = tmp
    dec rax
    jmp .insert_loop
.insert_store:
    mov rax, r14
    imul rax, r13
    mov rcx, [rbx + 16]
    mov [rcx + rax], r12
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
    mov rcx, [rbx + 16]
    mov r14, [rcx + rax]  ; removed value
    mov rax, r12           ; i = index
.remove_loop:
    mov rcx, [rbx + 8]
    dec rcx
    cmp rax, rcx
    jge .remove_done
    mov rcx, rax
    inc rcx
    imul rcx, r13
    mov rdx, rax
    imul rdx, r13
    mov rsi, [rbx + 16]   ; data_ptr
    mov r8, [rsi + rcx]   ; data[i+1]
    mov [rsi + rdx], r8   ; data[i] = data[i+1]
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
    mov rcx, [rbx + 16]   ; data_ptr
    xor rdx, rdx           ; i = 0
.contains_loop:
    cmp rdx, r14
    jge .contains_not_found
    mov rax, rdx
    imul rax, r13
    cmp r12, [rcx + rax]  ; data[i]
    je .contains_found
    inc rdx
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
    mov rcx, [rbx + 16]
    xor rdx, rdx
.index_loop:
    cmp rdx, r14
    jge .index_not_found
    mov rax, rdx
    imul rax, r13
    cmp r12, [rcx + rax]
    je .index_found
    inc rdx
    jmp .index_loop
.index_found:
    mov rax, rdx
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
    ; Allocate new header (24 bytes)
    mov rax, 12
    xor rdi, rdi
    syscall
    mov r15, rax          ; r15 = new header
    lea rdi, [r15 + 24]
    mov rax, 12
    syscall
    ; Allocate new data array (capacity * element_size)
    mov rax, 12
    xor rdi, rdi
    syscall
    mov [r15 + 16], rax   ; new data_ptr
    mov rax, r13
    imul rax, r12
    mov rdi, [r15 + 16]
    add rdi, rax
    mov rax, 12
    syscall
    ; Initialize header
    mov [r15], r13        ; capacity
    mov [r15 + 8], r14    ; length
    ; Copy data bytes
    cld
    mov rcx, r14
    imul rcx, r12
    mov rsi, [rbx + 16]   ; src data_ptr
    mov rdi, [r15 + 16]   ; dst data_ptr
    rep movsb
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
    mov rcx, [rbx + 16]   ; data_ptr
.reverse_loop:
    cmp r13, r15
    jge .reverse_done
    ; Swap data[left] and data[right]
    mov rax, r13
    imul rax, r12
    mov rdx, r15
    imul rdx, r12
    mov rsi, [rcx + rax]  ; tmp = data[left]
    mov rdi, [rcx + rdx]  ; data[right]
    mov [rcx + rdx], rsi  ; data[right] = tmp
    mov [rcx + rax], rdi  ; data[left] = data[right]
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
    mov rcx, [rbx + 16]   ; data_ptr
    xor rax, rax
    xor rdx, rdx
.sum_loop:
    cmp rdx, r13
    jge .sum_done
    mov rsi, rdx
    imul rsi, r12
    add rax, [rcx + rsi]
    inc rdx
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
    mov rcx, [rbx + 16]   ; data_ptr
    mov rax, [rcx]        ; min = data[0]
    mov r14, 1            ; i = 1
.min_loop:
    cmp r14, r13
    jge .min_done
    mov rdx, r14
    imul rdx, r12
    cmp [rcx + rdx], rax
    cmovl rax, [rcx + rdx]
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
    mov rcx, [rbx + 16]   ; data_ptr
    mov rax, [rcx]        ; max = data[0]
    mov r14, 1
.max_loop:
    cmp r14, r13
    jge .max_done
    mov rdx, r14
    imul rdx, r12
    cmp [rcx + rdx], rax
    cmovg rax, [rcx + rdx]
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
    mov r11, [r12 + 16] ; data_ptr
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

; rt_seq_slice: New heap seq with elements [lo, hi) copied from source
; rdi = seq pointer, rsi = lo, rdx = hi, rcx = element size
; Returns: rax = new seq pointer (lo/hi clamped to source length)
rt_seq_slice:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi        ; seq
    mov r12, rsi        ; lo
    mov r13, rdx        ; hi

    ; Clamp hi to source length
    mov rax, [rbx + 8]  ; source length
    cmp r13, rax
    jbe .slice_hi_ok
    mov r13, rax
.slice_hi_ok:
    ; Clamp lo to hi (empty slice if lo >= hi)
    cmp r12, r13
    jbe .slice_lo_ok
    mov r12, r13
.slice_lo_ok:
    ; new length = hi - lo
    mov r15, r13
    sub r15, r12

    mov r14, rcx        ; element size

    ; Allocate data array
    ; NOTE: sys_brk clobbers rcx and r11 — recompute byte counts after it.
    mov rax, 12
    xor rdi, rdi
    syscall
    mov r13, rax        ; r13 = data_start
    mov rax, r15
    imul rax, r14
    mov rcx, rax        ; rcx = data_bytes
    lea rdi, [r13 + rcx]
    mov rax, 12
    syscall

    ; Allocate header (24 bytes)
    mov rax, 12
    xor rdi, rdi
    syscall
    mov rdx, rax        ; rdx = header
    lea rdi, [rdx + 24]
    mov rax, 12
    syscall

    ; Initialize header
    mov [rdx], r15      ; capacity = new length
    mov [rdx + 8], r15  ; length = new length
    mov [rdx + 16], r13 ; data_ptr

    ; Copy src[lo*elem .. lo*elem + len*elem) into new data
    mov rax, r12
    imul rax, r14
    mov rsi, [rbx + 16]
    add rsi, rax        ; rsi = src = data + lo*elem
    mov rdi, r13        ; rdi = dst = data_start
    mov rax, r15
    imul rax, r14
    mov rcx, rax        ; rcx = byte count
    cld
    rep movsb

    mov rax, rdx        ; return header
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
