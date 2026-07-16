; rt_dict.asm - Dictionary runtime operations for Rex
; Dict layout: [capacity:8][count:8][keys: cap*8][values: cap*8]
; Keys are string pointers; 0 = empty slot, 1 = deleted (tombstone)
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
    mov r12, rdi
    mov rax, r12
    shl rax, 4
    add rax, 16
    mov r13, rax
    mov rax, 12
    xor rdi, rdi
    syscall
    mov rbx, rax
    mov rdi, rbx
    add rdi, r13
    mov rax, 12
    syscall
    mov [rbx], r12
    mov qword [rbx + 8], 0
    lea rdi, [rbx + 16]
    mov rcx, r12
    shl rcx, 1
    xor rax, rax
    rep stosq
    mov rax, rbx
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
    mov r14, [rbx]
    test r14, r14
    jz .get_nf
    xor rdx, rdx
    div r14
    mov r15, rdx
.get_probe:
    lea rcx, [r15 * 8]
    mov rsi, [rbx + 16 + rcx]
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
    mov rax, r14
    shl rax, 3
    add rax, 16
    add rax, rbx
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
; Returns: rax = dict pointer
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
    mov r14, [rbx]
    test r14, r14
    jz .set_done
    xor rdx, rdx
    div r14
    mov r15, rdx
.set_probe:
    lea rcx, [r15 * 8]
    mov rsi, [rbx + 16 + rcx]
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
    ; Table is full — resize and rehash
    mov rdi, rbx
    call rt_dict_resize
    mov rbx, rax            ; use new dict
    ; Re-hash the key and retry
    mov rdi, r12
    call rt_djb2_hash
    mov r14, [rbx]          ; new capacity
    xor rdx, rdx
    div r14
    mov r15, rdx
    jmp .set_probe
.set_empty:
    ; Store key at keys[r15]
    lea rcx, [r15 * 8]
    mov [rbx + 16 + rcx], r12
    ; Store value at values[r15] = dict + 16 + cap*8 + r15*8
    mov rax, r14
    shl rax, 3
    add rax, 16
    add rax, rbx
    lea rcx, [r15 * 8]
    mov [rax + rcx], r13
    inc qword [rbx + 8]
    jmp .set_done
.set_update:
    ; Update value at values[r15]
    mov rax, r14
    shl rax, 3
    add rax, 16
    add rax, rbx
    lea rcx, [r15 * 8]
    mov [rax + rcx], r13
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
; Returns: rax = new dict pointer
rt_dict_resize:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi            ; old dict
    mov r14, [rbx]          ; old capacity
    mov r15, [rbx + 8]      ; count
    ; New capacity = old * 2
    lea r12, [r14 * 2]
    ; Allocate new dict: 16 + new_cap*8 (keys) + new_cap*8 (values)
    mov rax, r12
    shl rax, 4
    add rax, 16
    mov rdi, rax
    mov rax, 12             ; sys_brk
    syscall
    ; rax = new dict — save it immediately
    mov r13, rax            ; r13 = new dict
    ; Set new capacity and count
    mov [r13], r12
    mov [r13 + 8], r15
    ; Zero out keys + values arrays (new_cap * 16 bytes starting at r13+16)
    lea rdi, [r13 + 16]
    xor eax, eax
    mov rcx, r12
    shl rcx, 1             ; new_cap * 2 (keys + values)
.resize_zero:
    mov [rdi], rax
    add rdi, 8
    dec rcx
    jnz .resize_zero
    ; Rehash: iterate old entries and insert into new dict
    test r15, r15
    jz .resize_done
    xor r9, r9             ; r9 = old index
.resize_loop:
    cmp r9, r14
    jae .resize_done
    lea rcx, [r9 * 8]
    mov rsi, [rbx + 16 + rcx]  ; key
    test rsi, rsi
    jz .resize_next
    cmp rsi, 1
    je .resize_next         ; skip tombstones
    ; Hash the key
    push r9
    mov rdi, rsi
    call rt_djb2_hash
    pop r9
    ; Insert into new dict: find empty slot
    xor rdx, rdx
    div r12                 ; rax = hash % new_capacity
    mov r10, rax            ; r10 = probe index
.resize_probe:
    lea rcx, [r10 * 8]
    mov rax, [r13 + 16 + rcx]
    test rax, rax
    jnz .resize_probe_next
    ; Found empty slot — store key
    lea rcx, [r10 * 8]
    ; Recover key from old dict
    lea rax, [r9 * 8]
    mov rsi, [rbx + 16 + rax]
    mov [r13 + 16 + rcx], rsi
    ; Store value
    mov rax, r14
    shl rax, 3
    add rax, 16
    add rax, rbx
    mov rsi, [rax + rcx]    ; old value
    ; values offset in new dict = 16 + new_cap*8
    mov rax, r12
    shl rax, 3
    add rax, 16
    add rax, r13
    mov [rax + rcx], rsi
    jmp .resize_next
.resize_probe_next:
    inc r10
    cmp r10, r12
    jb .resize_probe
    xor r10, r10
    jmp .resize_probe
.resize_next:
    inc r9
    jmp .resize_loop
.resize_done:
    mov rax, r13            ; return new dict
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
