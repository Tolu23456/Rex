; rt_dict.asm - Dictionary runtime operations for Rex
;
; Dict layout: [capacity:8][count:8][keys_ptr:8][values_ptr:8]  (32-byte header)
; keys array:   [capacity * 8] bytes  (key = string pointer; 0 = empty, 1 = tombstone)
; values array: [capacity * 8] bytes
;
; The header address NEVER changes once created: resize allocates NEW keys/values
; arrays and swaps the pointers in place, so caller-held dict pointers always
; stay valid. Heap is bump-allocated via brk (two-step: brk(0) then brk(base+size)).
BITS 64

section .text
    global rt_dict_new
    global rt_dict_get
    global rt_dict_set
    global rt_dict_len
    global rt_dict_resize

; rt_dict_new: Create a new dict
; rdi = initial capacity
; Returns: rax = pointer to dict header
rt_dict_new:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi        ; capacity

    ; Allocate header (32 bytes) via two-step brk
    mov rax, 12
    xor rdi, rdi
    syscall
    mov rbx, rax        ; rbx = header
    lea rdi, [rbx + 32]
    mov rax, 12
    syscall

    ; Allocate keys array (capacity * 8)
    mov rax, 12
    xor rdi, rdi
    syscall
    mov r13, rax        ; r13 = keys
    mov rax, r12
    shl rax, 3
    mov rdi, r13
    add rdi, rax
    mov rax, 12
    syscall

    ; Allocate values array (capacity * 8)
    mov rax, 12
    xor rdi, rdi
    syscall
    mov r14, rax        ; r14 = values
    mov rax, r12
    shl rax, 3
    mov rdi, r14
    add rdi, rax
    mov rax, 12
    syscall

    ; Initialize header
    mov [rbx], r12          ; capacity
    mov qword [rbx + 8], 0  ; count = 0
    mov [rbx + 16], r13     ; keys_ptr
    mov [rbx + 24], r14     ; values_ptr

    ; Zero keys + values arrays (capacity * 2 qwords total)
    mov rdi, r13
    mov rcx, r12
    shl rcx, 1
    xor rax, rax
    cld
    rep stosq

    mov rax, rbx
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; djb2 string hash
; rdi = string pointer
; Returns: rax = hash
rt_djb2_hash:
    mov rax, 5381
    xor rcx, rcx
.hash_loop:
    mov cl, [rdi]
    test cl, cl
    jz .hash_done
    imul rax, rax, 33
    add rax, rcx
    inc rdi
    jmp .hash_loop
.hash_done:
    ret

; strcmp_eq: check if two strings are equal
; rdi = str1, rsi = str2
; Returns: rax = 1 if equal, 0 otherwise
rt_strcmp_eq:
    xor rax, rax
.eq_loop:
    mov cl, [rdi]
    mov dl, [rsi]
    cmp cl, dl
    jne .eq_no
    test cl, cl
    jz .eq_yes
    inc rdi
    inc rsi
    jmp .eq_loop
.eq_yes:
    mov rax, 1
.eq_no:
    ret

; rt_dict_get: Get value by key
; rdi = dict pointer
; rsi = key (string pointer)
; Returns: rax = value (0 if not found)
rt_dict_get:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
    mov r12, rsi
    test r12, r12
    jz .get_nf
    mov rdi, r12
    call rt_djb2_hash
    mov r14, [rbx]      ; capacity
    test r14, r14
    jz .get_nf
    xor rdx, rdx
    div r14
    mov r15, rdx        ; probe index = hash % capacity (remainder)
.get_probe:
    lea rcx, [r15 * 8]
    mov rsi, [rbx + 16] ; keys_ptr
    mov rsi, [rsi + rcx]
    test rsi, rsi
    jz .get_nf
    cmp rsi, 1
    je .get_next
    mov rdi, r12
    call rt_strcmp_eq
    test rax, rax
    jnz .get_found
.get_next:
    inc r15
    cmp r15, r14
    jb .get_probe
    ; Probed entire table — key not found
    jmp .get_nf
.get_found:
    mov rax, [rbx + 24] ; values_ptr
    lea rcx, [r15 * 8]
    mov rax, [rax + rcx]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.get_nf:
    xor rax, rax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rt_dict_set: Set key-value pair
; rdi = dict pointer
; rsi = key (string pointer)
; rdx = value
; Returns: rax = dict pointer (header is stable, pointer never changes)
rt_dict_set:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test r12, r12
    jz .set_done
    mov rdi, r12
    call rt_djb2_hash
    mov r14, [rbx]      ; capacity
    test r14, r14
    jz .set_done
    xor rdx, rdx
    div r14
    mov r15, rdx        ; probe index = hash % capacity (remainder)
.set_probe:
    lea rcx, [r15 * 8]
    mov rsi, [rbx + 16] ; keys_ptr
    mov rsi, [rsi + rcx]
    test rsi, rsi
    jz .set_empty
    cmp rsi, 1
    je .set_empty
    mov rdi, r12
    call rt_strcmp_eq
    test rax, rax
    jnz .set_update
.set_next:
    inc r15
    cmp r15, r14
    jb .set_probe
    ; Table is full — resize (swaps pointers in place) and retry
    mov rdi, rbx
    call rt_dict_resize
    mov rdi, r12
    call rt_djb2_hash
    mov r14, [rbx]      ; new capacity
    xor rdx, rdx
    div r14
    mov r15, rdx
    jmp .set_probe
.set_empty:
    ; Store key at keys[r15]
    lea rcx, [r15 * 8]
    mov rsi, [rbx + 16] ; keys_ptr
    mov [rsi + rcx], r12
    ; Store value at values[r15]
    mov rsi, [rbx + 24] ; values_ptr
    mov [rsi + rcx], r13
    inc qword [rbx + 8]
    jmp .set_done
.set_update:
    ; Update value at values[r15]
    lea rcx, [r15 * 8]
    mov rsi, [rbx + 24] ; values_ptr
    mov [rsi + rcx], r13
.set_done:
    mov rax, rbx
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rt_dict_len: Get dict entry count
; rdi = dict pointer
; Returns: rax = count
rt_dict_len:
    mov rax, [rdi + 8]
    ret

; rt_dict_resize: Double the dict capacity and rehash all entries
; rdi = dict pointer
; Returns: rax = dict pointer (same stable header)
rt_dict_resize:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi            ; dict (stable header)
    mov r14, [rbx]          ; old capacity
    mov r15, [rbx + 8]      ; count
    ; New capacity = old * 2
    lea r12, [r14 * 2]

    ; Allocate new keys array (new_cap * 8)
    mov rax, 12
    xor rdi, rdi
    syscall
    mov r13, rax            ; r13 = new keys
    mov rax, r12
    shl rax, 3
    mov rdi, r13
    add rdi, rax
    mov rax, 12
    syscall

    ; Allocate new values array (new_cap * 8)
    mov rax, 12
    xor rdi, rdi
    syscall
    mov r9, rax             ; r9 = new values (rt_djb2_hash does not touch r9)
    mov rax, r12
    shl rax, 3
    mov rdi, r9
    add rdi, rax
    mov rax, 12
    syscall

    ; Zero out new keys + values arrays (new_cap * 2 qwords)
    mov rdi, r13
    mov rcx, r12
    shl rcx, 1
    xor rax, rax
    cld
    rep stosq

    ; Rehash: iterate old entries and insert into new arrays
    test r15, r15
    jz .resize_swap
    xor r8, r8              ; r8 = old index
.resize_loop:
    cmp r8, r14
    jae .resize_swap
    lea rcx, [r8 * 8]
    mov rsi, [rbx + 16]     ; old keys_ptr
    mov rsi, [rsi + rcx]    ; key
    test rsi, rsi
    jz .resize_next
    cmp rsi, 1
    je .resize_next         ; skip tombstones
    ; Hash the key
    push r8
    mov rdi, rsi
    call rt_djb2_hash
    pop r8
    ; Insert into new dict: find empty slot
    xor rdx, rdx
    div r12                 ; rdx = hash % new_capacity (remainder)
    mov r10, rdx            ; r10 = probe index
.resize_probe:
    lea rcx, [r10 * 8]
    mov rax, [r13 + rcx]    ; new keys[probe]
    test rax, rax
    jnz .resize_probe_next
    ; Found empty slot — store key and value at probe
    lea rcx, [r10 * 8]
    mov rsi, [rbx + 16]     ; old keys_ptr
    mov rsi, [rsi + r8 * 8] ; key (old index r8)
    mov [r13 + rcx], rsi    ; new keys[probe] = key
    mov rsi, [rbx + 24]     ; old values_ptr
    mov rsi, [rsi + r8 * 8] ; value (old index r8)
    mov [r9 + rcx], rsi     ; new values[probe] = value
    jmp .resize_next
.resize_probe_next:
    inc r10
    cmp r10, r12
    jb .resize_probe
    xor r10, r10
    jmp .resize_probe
.resize_next:
    inc r8
    jmp .resize_loop
.resize_swap:
    ; Swap new arrays into the header (count unchanged)
    mov [rbx], r12          ; capacity = new_cap
    mov [rbx + 16], r13     ; keys_ptr = new keys
    mov [rbx + 24], r9      ; values_ptr = new values
    mov rax, rbx            ; return same header
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
