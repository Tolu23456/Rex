; Rex Type Registry Implementation
; written in x86-64 NASM assembly

%include "include/rex_defs.inc"

TYPE_REG_MAX   equ 256
TYPE_REG_SIZE  equ 32  ; 32 bytes per entry

section .data
    global type_count
    type_count dd 0
    struct_field_count dd 0

    ; Primitive type names
    name_void db "void", 0
    name_int  db "int", 0
    name_float db "float", 0
    name_bool db "bool", 0
    name_str  db "str", 0
    name_char db "char", 0
    name_byte db "byte", 0
    name_file db "file", 0

section .bss
    global type_table
    global type_name_buf
    global type_name_idx
    type_table resb TYPE_REG_SIZE * TYPE_REG_MAX
    type_name_buf resb 4096
    type_name_idx resd 1

    ; struct_fields_table: 1024 entries of 32 bytes each
    struct_fields_table resb 32 * 1024

section .text
    global type_reg_init
    global type_reg_add
    global type_get_kind
    global type_get_size
    global type_set_size
    global type_struct_add_field
    global type_struct_find_field
    global type_struct_field_at
    global type_lookup

type_reg_init:
    mov dword [type_count], 0
    mov dword [type_name_idx], 0
    mov dword [struct_field_count], 0

    ; Register TYPE_VOID (0)
    mov rdi, TYPE_VOID
    mov rsi, 0
    lea rdx, [name_void]
    mov rcx, 4
    xor r8, r8
    call type_reg_add

    ; Register TYPE_INT (1)
    mov rdi, TYPE_INT
    mov rsi, 8
    lea rdx, [name_int]
    mov rcx, 3
    xor r8, r8
    call type_reg_add

    ; Register TYPE_FLOAT (2)
    mov rdi, TYPE_FLOAT
    mov rsi, 8
    lea rdx, [name_float]
    mov rcx, 5
    xor r8, r8
    call type_reg_add

    ; Register TYPE_BOOL (3)
    mov rdi, TYPE_BOOL
    mov rsi, 1
    lea rdx, [name_bool]
    mov rcx, 4
    xor r8, r8
    call type_reg_add

    ; Register TYPE_COMPLEX (4)
    mov rdi, TYPE_COMPLEX
    mov rsi, 0
    xor rdx, rdx
    xor rcx, rcx
    xor r8, r8
    call type_reg_add

    ; Register TYPE_STR (5)
    mov rdi, TYPE_STR
    mov rsi, 8
    lea rdx, [name_str]
    mov rcx, 3
    xor r8, r8
    call type_reg_add

    ; Register TYPE_SEQ (6)
    mov rdi, TYPE_SEQ
    mov rsi, 8
    xor rdx, rdx
    xor rcx, rcx
    xor r8, r8
    call type_reg_add

    ; Register TYPE_DICT (7)
    mov rdi, TYPE_DICT
    mov rsi, 8
    xor rdx, rdx
    xor rcx, rcx
    xor r8, r8
    call type_reg_add

    ; Register TYPE_CHAR (8)
    mov rdi, TYPE_CHAR
    mov rsi, 1
    lea rdx, [name_char]
    mov rcx, 4
    xor r8, r8
    call type_reg_add

    ; Register TYPE_BYTE (9)
    mov rdi, TYPE_BYTE
    mov rsi, 1
    lea rdx, [name_byte]
    mov rcx, 4
    xor r8, r8
    call type_reg_add

    ; Register TYPE_FILE (10)
    mov rdi, TYPE_FILE
    mov rsi, 8
    lea rdx, [name_file]
    mov rcx, 4
    xor r8, r8
    call type_reg_add

    ; Register TYPE_TUP (11)
    mov rdi, TYPE_TUP
    mov rsi, 8
    xor rdx, rdx
    xor rcx, rcx
    xor r8, r8
    call type_reg_add

    ret

; Add type:
; rdi = kind, rsi = size, rdx = name_ptr, rcx = name_len, r8 = aux_data
; Returns rax = type_id, or -1 if full
type_reg_add:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi ; kind
    mov r13, rsi ; size
    mov r14, rdx ; name_ptr
    mov r15, rcx ; name_len

    mov eax, [type_count]
    cmp eax, TYPE_REG_MAX
    jae .err_full

    ; Copy name to type_name_buf if name_ptr is not null
    xor rdi, rdi ; default name_ptr = null
    test r14, r14
    jz .name_done

    mov ebx, [type_name_idx]
    ; Bounds check: ensure name fits in buffer
    lea rax, [rbx + r15 + 1]
    cmp rax, 4096
    jae .name_done          ; skip name if it won't fit
    lea rdi, [type_name_buf + rbx] ; destination
    
    ; Copy loop
    xor rcx, rcx
.copy_loop:
    cmp rcx, r15
    je .copy_done
    movzx edx, byte [r14 + rcx]
    mov [rdi + rcx], dl
    inc rcx
    jmp .copy_loop
.copy_done:
    mov byte [rdi + rcx], 0 ; null-terminate
    
    ; Advance type_name_idx
    add rcx, 1
    add [type_name_idx], ecx

.name_done:
    mov ebx, [type_count]
    imul ebx, ebx, TYPE_REG_SIZE
    lea rax, [type_table + ebx]

    mov [rax + 0], r12b ; kind
    mov [rax + 4], r13d ; size
    mov [rax + 8], rdi ; name_ptr (saved name)
    mov [rax + 16], r15 ; name_len
    mov [rax + 24], r8 ; aux_data

    mov eax, [type_count]
    inc dword [type_count]
    
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

; Get kind:
; rdi = type_id
type_get_kind:
    cmp edi, [type_count]
    jae .invalid
    imul edi, edi, TYPE_REG_SIZE
    movzx rax, byte [type_table + rdi + 0]
    ret
.invalid:
    xor rax, rax
    ret

; Get size:
; rdi = type_id
type_get_size:
    cmp edi, [type_count]
    jae .invalid
    imul edi, edi, TYPE_REG_SIZE
    mov eax, [type_table + rdi + 4]
    ret
.invalid:
    xor rax, rax
    ret

; Set size:
; rdi = type_id, rsi = size
type_set_size:
    cmp edi, [type_count]
    jae .done
    imul edi, edi, TYPE_REG_SIZE
    mov [type_table + rdi + 4], esi
.done:
    ret

; Lookup type by name:
; rdi = name_ptr, rsi = name_len
; Returns type_id, or -1 if not found
type_lookup:
    push rbx
    push r12
    push r13
    
    mov r12, rdi ; name_ptr
    mov r13, rsi ; name_len

    xor ebx, ebx ; loop index
.loop:
    cmp ebx, [type_count]
    je .not_found

    imul eax, ebx, TYPE_REG_SIZE
    lea rax, [type_table + rax]

    ; Check if name matches
    mov rsi, [rax + 8] ; entry name_ptr
    test rsi, rsi
    jz .next

    mov rcx, [rax + 16] ; entry name_len
    cmp rcx, r13
    jne .next

    ; Compare strings
    push rax
    mov rdi, r12
    ; rsi already set
    mov rdx, r13
    call strings_equal
    pop rcx
    test rax, rax
    jnz .found

.next:
    inc ebx
    jmp .loop

.not_found:
    mov rax, -1
    pop r13
    pop r12
    pop rbx
    ret

.found:
    mov rax, rbx
    pop r13
    pop r12
    pop rbx
    ret

; Helper strings_equal (rdi = str1, rsi = str2, rdx = len)
; Returns 1 if equal, 0 otherwise
strings_equal:
    xor rcx, rcx
.loop:
    cmp rcx, rdx
    je .equal
    mov al, byte [rdi + rcx]
    mov r8b, byte [rsi + rcx]
    cmp al, r8b
    jne .not_equal
    inc rcx
    jmp .loop
.equal:
    mov rax, 1
    ret
.not_equal:
    xor rax, rax
    ret

type_struct_add_field:
    mov eax, [struct_field_count]
    cmp eax, 1024
    jae .done

    imul eax, eax, 32
    lea rax, [struct_fields_table + rax]

    mov [rax + 0], edi ; struct_type_id
    mov [rax + 8], rsi ; field_name_ptr
    mov [rax + 16], rdx ; field_name_len
    mov [rax + 24], ecx ; field_type_id
    mov [rax + 28], r8d ; field_offset

    inc dword [struct_field_count]
.done:
    ret

; type_struct_find_field: Look up a field by struct type and name
; rdi = struct_type_id, rsi = field_name_ptr, rdx = field_name_len
; Returns: rax = field_offset (-1 if not found), rcx = field_type_id
type_struct_find_field:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi            ; struct_type_id
    mov r13, rsi            ; field_name_ptr
    mov r14, rdx            ; field_name_len
    xor ebx, ebx            ; index
.find_loop:
    cmp ebx, [struct_field_count]
    jae .not_found
    imul eax, ebx, 32
    lea rax, [struct_fields_table + rax]
    ; Check struct_type_id
    cmp [rax], r12d
    jne .find_next
    ; Check field_name_len
    cmp [rax + 16], r14
    jne .find_next
    ; Compare field_name
    mov rsi, [rax + 8]      ; stored name ptr
    mov rdi, r13            ; search name ptr
    mov rcx, r14            ; length
    test rcx, rcx
    jz .find_match
.find_cmp:
    movzx r8, byte [rdi]
    movzx r9, byte [rsi]
    cmp r8b, r9b
    jne .find_next
    inc rdi
    inc rsi
    dec rcx
    jnz .find_cmp
.find_match:
    ; Found! Return offset and type
    imul eax, ebx, 32
    lea rax, [struct_fields_table + rax]
    mov ecx, [rax + 24]     ; field_type_id
    mov eax, [rax + 28]     ; field_offset
    jmp .find_done
.find_next:
    inc ebx
    jmp .find_loop
.not_found:
    mov rax, -1
    xor ecx, ecx
.find_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; type_struct_field_at: enumerate fields by index (for struct copy/compare)
; rdi = struct_type_id, rsi = field index (0-based among THIS struct's fields)
; Returns: rax = field_offset (-1 if index out of range), rcx = field_type_id
type_struct_field_at:
    push rbx
    push r12
    push r13
    mov r12, rdi            ; struct_type_id
    xor ebx, ebx            ; flat index
    xor r13d, r13d          ; count of matching fields seen
.find_loop:
    cmp ebx, [struct_field_count]
    jae .no_field
    imul eax, ebx, 32
    lea rax, [struct_fields_table + rax]
    cmp [rax], r12d         ; belongs to this struct?
    jne .find_next
    cmp r13d, esi           ; this is the requested index?
    je .found
    inc r13d
.find_next:
    inc ebx
    jmp .find_loop
.found:
    mov ecx, [rax + 24]     ; field_type_id
    mov eax, [rax + 28]     ; field_offset
    jmp .done
.no_field:
    mov rax, -1
    xor ecx, ecx
.done:
    pop r13
    pop r12
    pop rbx
    ret
