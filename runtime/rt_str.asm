; rt_str.asm - String runtime operations for Rex
; Provides: rt_str_concat, rt_str_len, rt_str_compare
; String layout: null-terminated C string (pointer to first byte)
BITS 64

section .text
    global rt_str_concat
    global rt_str_len
    global rt_str_compare
    global rt_deref_byte

; rt_str_concat: Concatenate two strings
; rdi = str1 pointer (null-terminated), rsi = str2 pointer (null-terminated)
; Returns: rax = new string pointer (null-terminated), or 0 on failure
rt_str_concat:
    push rbx
    push r12
    push r13
    push r14
    push r15
    cld

    mov r12, rdi            ; str1
    mov r13, rsi            ; str2

    ; Get length of str1
    xor r14, r14
.len1_loop:
    cmp byte [r12 + r14], 0
    je .len1_done
    inc r14
    jmp .len1_loop
.len1_done:

    ; Get length of str2
    xor r15, r15
.len2_loop:
    cmp byte [r13 + r15], 0
    je .len2_done
    inc r15
    jmp .len2_loop
.len2_done:

    ; Calculate total length and allocation size
    mov rax, r14
    add rax, r15            ; total_len = len1 + len2
    inc rax                 ; +1 for null terminator

    ; Allocate memory using mmap
    mov rbx, rax            ; save size
    xor rdi, rdi            ; addr = NULL
    mov rsi, rax            ; size
    mov rdx, 3              ; PROT_READ | PROT_WRITE
    mov r10, 0x22           ; MAP_PRIVATE | MAP_ANONYMOUS
    mov r8, -1              ; fd = -1
    xor r9, r9              ; offset = 0
    mov rax, 9              ; sys_mmap
    syscall
    mov r10, rax            ; r10 = allocated pointer

    ; Check for mmap failure
    cmp r10, -1
    je .alloc_failed

    ; Copy str1 data
    mov rdi, r10            ; destination
    mov rsi, r12            ; source = str1
    mov rcx, r14            ; length
    rep movsb

    ; Copy str2 data
    mov rsi, r13            ; source = str2
    mov rcx, r15            ; length
    rep movsb

    ; Null terminate
    mov byte [rdi], 0

    mov rax, r10            ; return new string pointer
    jmp .done

.alloc_failed:
    xor rax, rax            ; return null

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rt_str_len: Get string length
; rdi = string pointer (null-terminated)
; Returns: rax = length
rt_str_len:
    xor rax, rax
.loop:
    cmp byte [rdi + rax], 0
    je .done
    inc rax
    jmp .loop
.done:
    ret

; rt_str_compare: Compare two strings
; rdi = str1 pointer, rsi = str2 pointer (both null-terminated)
; Returns: rax = 0 if equal, <0 if str1<str2, >0 if str1>str2
rt_str_compare:
    push rbx
    cld
.loop:
    movzx eax, byte [rdi]
    movzx ebx, byte [rsi]
    cmp al, bl
    jne .not_equal
    test al, al
    je .equal
    inc rdi
    inc rsi
    jmp .loop

.equal:
    xor rax, rax
    jmp .done_cmp

.not_equal:
    sub eax, ebx

.done_cmp:
    pop rbx
    ret

; rt_deref_byte: Load byte from pointer + offset
; rdi = pointer, rsi = offset
; Returns: rax = byte value (zero-extended)
rt_deref_byte:
    movzx eax, byte [rdi + rsi]
    ret

; Pad to 512 bytes
