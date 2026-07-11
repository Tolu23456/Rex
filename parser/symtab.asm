; Rex Symbol Table Implementation
; written in x86-64 NASM assembly

%include "include/rex_defs.inc"

section .bss
    global sym_table
    global sym_count

    sym_table   resb SYM_ENTRY_SIZE * SYM_MAX
    sym_count   resd 1

section .text
    global sym_clear
    global sym_add
    global sym_lookup
    global sym_get_type
    global sym_set_type
    global sym_get_scope
    global sym_is_mutable
    global sym_set_mutable
    global sym_is_init
    global sym_set_init
    global sym_get_offset
    global sym_set_offset

; Clear the symbol table
sym_clear:
    mov dword [sym_count], 0
    ret

; Compare entry name at rdi (null-terminated) with string at rsi of length rdx
; Returns rax = 1 if match, 0 if not
match_name:
    push rbx
    xor rcx, rcx
.loop:
    cmp rcx, rdx
    je .check_null
    movzx rax, byte [rdi + rcx]
    movzx rbx, byte [rsi + rcx]
    cmp al, bl
    jne .diff
    inc rcx
    jmp .loop
.check_null:
    movzx rax, byte [rdi + rcx]
    cmp al, 0
    jne .diff
    mov rax, 1
    pop rbx
    ret
.diff:
    xor rax, rax
    pop rbx
    ret

; Add a symbol
; rdi = name_ptr, rsi = name_len, rdx = type, rcx = scope
; Returns rax = symbol index, or negative on error
sym_add:
    push rbx
    push r12
    push r13
    push r14
    push r15
    
    mov r12, rdi ; name_ptr
    mov r13, rsi ; name_len
    mov r14, rdx ; type
    mov r15, rcx ; scope

    ; Check if table is full
    mov eax, [sym_count]
    cmp eax, SYM_MAX
    jae .err_full

    ; Check for duplicate in same scope
    xor ebx, ebx ; loop index
.dup_check:
    cmp ebx, [sym_count]
    je .no_dup
    
    ; Get pointer to entry
    imul eax, ebx, SYM_ENTRY_SIZE
    lea rdi, [sym_table + rax] ; entry name ptr
    mov rsi, r12
    mov rdx, r13
    call match_name
    test rax, rax
    jz .next_dup
    
    ; Match found! Check scope
    imul eax, ebx, SYM_ENTRY_SIZE
    movzx eax, byte [sym_table + rax + 33] ; entry scope
    cmp eax, r15d
    je .err_dup ; duplicate in same scope!
    
.next_dup:
    inc ebx
    jmp .dup_check

.no_dup:
    ; Add new entry at sym_count
    mov ebx, [sym_count]
    imul eax, ebx, SYM_ENTRY_SIZE
    lea rdi, [sym_table + rax] ; dest name ptr
    
    ; Copy name (max 31 chars)
    xor rcx, rcx
.copy_loop:
    cmp rcx, r13
    je .copy_done
    cmp rcx, 31
    je .copy_done
    movzx rax, byte [r12 + rcx]
    mov [rdi + rcx], al
    inc rcx
    jmp .copy_loop
.copy_done:
    mov byte [rdi + rcx], 0 ; null-terminate

    ; Set metadata
    imul eax, ebx, SYM_ENTRY_SIZE
    lea rdi, [sym_table + rax]
    
    mov [rdi + 32], r14b ; type
    mov [rdi + 33], r15b ; scope
    mov byte [rdi + 34], 0 ; is_mutable = 0 (by default)
    mov byte [rdi + 35], 0 ; is_init = 0 (by default)
    
    ; Default offset is slot index mapped to VAR_STORAGE_BASE
    imul edx, ebx, 64
    add edx, VAR_STORAGE_BASE
    mov [rdi + 36], edx ; offset

    ; Increment sym_count
    inc dword [sym_count]
    mov rax, r15 ; return index
    mov eax, ebx
    
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.err_full:
    mov rax, -1
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.err_dup:
    mov rax, -2
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Lookup a symbol (searches from innermost scope to outermost, so back to front)
; rdi = name_ptr, rsi = name_len
; Returns rax = symbol index, or -1 if not found
; Lookup a symbol (searches from innermost scope to outermost, so back to front)
; rdi = name_ptr, rsi = name_len
; Returns rax = symbol index, or -1 if not found
sym_lookup:
    push rbx
    push r12
    push r13
    
    mov r12, rdi        ; name_ptr
    mov r13, rsi        ; name_len
    
    mov ebx, [sym_count]
    dec ebx
.loop:
    cmp ebx, 0
    jl .not_found
    
    imul eax, ebx, SYM_ENTRY_SIZE
    lea rdi, [sym_table + rax] ; entry name ptr
    mov rsi, r12
    mov rdx, r13
    call match_name
    test rax, rax
    jz .next
    
    ; Found!
    mov rax, rbx
    pop r13
    pop r12
    pop rbx
    ret

.next:
    dec ebx
    jmp .loop

.not_found:
    mov rax, -1
    pop r13
    pop r12
    pop rbx
    ret


; Accessors
; rdi = symbol index

sym_get_type:
    imul edi, edi, SYM_ENTRY_SIZE
    movzx rax, byte [sym_table + rdi + 32]
    ret

sym_set_type:
    ; rdi = index, rsi = type
    imul edi, edi, SYM_ENTRY_SIZE
    mov [sym_table + rdi + 32], sil
    ret

sym_get_scope:
    imul edi, edi, SYM_ENTRY_SIZE
    movzx rax, byte [sym_table + rdi + 33]
    ret

sym_is_mutable:
    imul edi, edi, SYM_ENTRY_SIZE
    movzx rax, byte [sym_table + rdi + 34]
    ret

sym_set_mutable:
    ; rdi = index, rsi = mutable (0/1)
    imul edi, edi, SYM_ENTRY_SIZE
    mov [sym_table + rdi + 34], sil
    ret

sym_is_init:
    imul edi, edi, SYM_ENTRY_SIZE
    movzx rax, byte [sym_table + rdi + 35]
    ret

sym_set_init:
    ; rdi = index, rsi = init (0/1)
    imul edi, edi, SYM_ENTRY_SIZE
    mov [sym_table + rdi + 35], sil
    ret

sym_get_offset:
    imul edi, edi, SYM_ENTRY_SIZE
    mov eax, [sym_table + rdi + 36]
    ret

sym_set_offset:
    ; rdi = index, rsi = offset
    imul edi, edi, SYM_ENTRY_SIZE
    mov [sym_table + rdi + 36], esi
    ret
