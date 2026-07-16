; Rex Symbol Table Implementation
; written in x86-64 NASM assembly

%include "include/rex_defs.inc"

section .data
    global current_stack_offset
    current_stack_offset dd VAR_STORAGE_BASE

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
    global sym_find_by_offset
    global sym_set_private
    global sym_remove_block_scope

; Clear the symbol table
sym_clear:
    mov dword [sym_count], 0
    mov dword [current_stack_offset], VAR_STORAGE_BASE
    ret

; Remove all block-scoped symbols (SCOPE_BLOCK) from the symbol table.
; Called when exiting an indented block to destroy __-prefixed variables.
; rdi = saved sym_count at block entry (only remove symbols added after this)
sym_remove_block_scope:
    push rbx
    push r12
    push r13

    mov r12d, edi           ; r12 = block_start_count
    mov ebx, [sym_count]

    ; Walk backwards from current sym_count to block_start_count
    ; Remove any SCOPE_BLOCK entries by shifting subsequent entries down
    ; We use a forward scan-and-compact approach:
    ;   dst = block_start_count (where we write surviving entries)
    ;   src scans from block_start_count to sym_count

    mov r12d, edi           ; r12 = block_start_count (dst boundary)
    xor r13d, r13d          ; r13 = dst index, starts at block_start_count
    mov r13d, r12d

    ; Scan entries from block_start_count onward
    ; For each entry: if SCOPE_BLOCK, skip it (don't copy); otherwise keep it
    ; At the end, also restore current_stack_offset to the max offset of surviving entries

    ; First pass: compact — move non-block-scoped entries down
    mov ecx, r12d           ; ecx = src index
.compact_loop:
    cmp ecx, [sym_count]
    jae .compact_done

    imul eax, ecx, SYM_ENTRY_SIZE
    lea rsi, [sym_table + rax]

    ; Check if this entry is SCOPE_BLOCK
    movzx eax, byte [rsi + 36] ; scope
    cmp eax, SCOPE_BLOCK
    je .skip_entry            ; block-scoped → remove

    ; Keep this entry: copy to dst position (if dst != src)
    cmp r13d, ecx
    je .no_copy

    imul eax, r13d, SYM_ENTRY_SIZE
    lea rdi, [sym_table + rax]

    ; Copy SYM_ENTRY_SIZE bytes from rsi to rdi
    push rcx
    mov rcx, SYM_ENTRY_SIZE
    rep movsb
    pop rcx

.no_copy:
    inc r13d
.skip_entry:
    inc ecx
    jmp .compact_loop

.compact_done:
    ; Update sym_count to new compacted count
    mov [sym_count], r13d

    ; Recompute current_stack_offset: find max (offset + size) among surviving entries
    ; For simplicity, reset to VAR_STORAGE_BASE then walk all surviving entries
    mov dword [current_stack_offset], VAR_STORAGE_BASE

    xor ebx, ebx
.recalc_loop:
    cmp ebx, r13d
    jae .recalc_done

    imul eax, ebx, SYM_ENTRY_SIZE
    lea rsi, [sym_table + rax]

    ; Get type and its size
    push rbx
    push rsi
    mov edi, [rsi + 32]       ; type_id
    extern type_get_size
    call type_get_size         ; rax = size
    pop rsi
    pop rbx

    ; Get this entry's offset
    mov edx, [rsi + 40]       ; offset
    add edx, eax              ; offset + size
    cmp edx, [current_stack_offset]
    jbe .recalc_next
    mov [current_stack_offset], edx
.recalc_next:
    inc ebx
    jmp .recalc_loop

.recalc_done:
    pop r13
    pop r12
    pop rbx
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
    movzx eax, byte [sym_table + rax + 36] ; entry scope
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
    
    mov [rdi + 32], r14d ; type_id (dword)
    mov [rdi + 36], r15b ; scope
    mov byte [rdi + 37], 0 ; is_mutable = 0 (by default)
    mov byte [rdi + 38], 0 ; is_init = 0 (by default)
    mov byte [rdi + 39], 0 ; is_private = 0 (by default)
    
    ; Set offset to current_stack_offset
    mov edx, [current_stack_offset]
    mov [rdi + 40], edx ; offset

    ; Get type size and increment current_stack_offset
    extern type_get_size
    push rdi
    mov rdi, r14 ; type_id
    call type_get_size
    pop rdi
    add [current_stack_offset], eax ; increment offset

    ; Increment sym_count
    inc dword [sym_count]
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
    mov eax, [sym_table + rdi + 32]
    ret

sym_set_type:
    ; rdi = index, rsi = type
    imul edi, edi, SYM_ENTRY_SIZE
    mov [sym_table + rdi + 32], esi
    ret

sym_get_scope:
    imul edi, edi, SYM_ENTRY_SIZE
    movzx rax, byte [sym_table + rdi + 36]
    ret

sym_is_mutable:
    imul edi, edi, SYM_ENTRY_SIZE
    movzx rax, byte [sym_table + rdi + 37]
    ret

sym_set_mutable:
    ; rdi = index, rsi = mutable (0/1)
    imul edi, edi, SYM_ENTRY_SIZE
    mov [sym_table + rdi + 37], sil
    ret

sym_is_init:
    imul edi, edi, SYM_ENTRY_SIZE
    movzx rax, byte [sym_table + rdi + 38]
    ret

sym_set_init:
    ; rdi = index, rsi = init (0/1)
    imul edi, edi, SYM_ENTRY_SIZE
    mov [sym_table + rdi + 38], sil
    ret

sym_get_offset:
    imul edi, edi, SYM_ENTRY_SIZE
    mov eax, [sym_table + rdi + 40]
    ret

sym_set_offset:
    ; rdi = index, rsi = offset
    imul edi, edi, SYM_ENTRY_SIZE
    mov [sym_table + rdi + 40], esi
    ret

sym_is_private:
    imul edi, edi, SYM_ENTRY_SIZE
    movzx rax, byte [sym_table + rdi + 39]
    ret

sym_set_private:
    ; rdi = index, rsi = private (0/1)
    imul edi, edi, SYM_ENTRY_SIZE
    mov [sym_table + rdi + 39], sil
    ret

sym_find_by_offset:
    push rbx
    mov ebx, [sym_count]
    dec ebx
.loop:
    cmp ebx, 0
    jl .not_found
    
    imul eax, ebx, SYM_ENTRY_SIZE
    mov eax, [sym_table + rax + 40] ; offset is at 40
    cmp eax, edi
    je .found
    
    dec ebx
    jmp .loop
.not_found:
    mov rax, -1
    pop rbx
    ret
.found:
    mov rax, rbx
    pop rbx
    ret
