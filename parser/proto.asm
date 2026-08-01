; Rex Protocol Table & Prescan
; written in x86-64 NASM assembly
;
; Holds the protocol table (name → param/return metadata) and the two-pass
; prescanner.  prescan_protocols is invoked once after lex_init and before
; the main parse; it walks the token stream, records every `prot` definition,
; and validates that every `@` call site references a defined protocol.
; It reinitialises the lexer before returning so parse_program starts fresh.

%include "include/rex_defs.inc"

section .bss
    global proto_table
    global proto_count
    proto_table     resb PROTO_MAX * PROTO_ENTRY_SIZE
    proto_count     resd 1

section .data
    err_proto_dup    db "Compile Error: Duplicate protocol definition", 0
    err_proto_full   db "Compile Error: Protocol table full", 0
    err_proto_unknown db "Compile Error: Unknown protocol", 0
    err_proto_syntax db "Syntax Error: Malformed protocol definition", 0

section .text
    global proto_clear
    global proto_add
    global proto_lookup
    global proto_get_name
    global proto_get_body_offset
    global proto_set_body_offset
    global proto_get_param_count
    global proto_set_param_count
    global proto_get_ret_count
    global proto_set_ret_count
    global proto_get_ret_type
    global proto_set_ret_type
    global proto_get_ret_is_result
    global proto_set_ret_is_result
    global proto_get_ret_conc_type
    global proto_set_ret_conc_type
    global proto_set_param_var_idx
    global proto_get_param_var_idx
    global proto_set_var_range
    global proto_get_var_range
    global prescan_protocols

    extern lex_init
    extern next_token
    extern tok_type
    extern tok_str_ptr
    extern tok_str_len
    extern tok_ival
    extern src_ptr
    extern src_len
    extern get_error_loc

; ------------------------------------------------------------------
; proto_clear — reset the protocol table
; ------------------------------------------------------------------
proto_clear:
    mov dword [proto_count], 0
    ret

; ------------------------------------------------------------------
; proto_add — register a new protocol
; rdi = name_ptr, rsi = name_len
; Returns rax = proto_id, or -1 (dup) / -2 (full)
; ------------------------------------------------------------------
proto_add:
    push rbx
    push r12
    push r13

    mov r12, rdi
    mov r13, rsi

    ; Duplicate check against existing entries
    xor ebx, ebx
.pa_dup_loop:
    cmp ebx, [proto_count]
    je .pa_no_dup
    imul eax, ebx, PROTO_ENTRY_SIZE
    lea rdi, [proto_table + rax + PROTO_NAME_OFF]
    mov rsi, r12
    mov rdx, r13
    call proto_match_name
    test rax, rax
    jnz .pa_err_dup
    inc ebx
    jmp .pa_dup_loop

.pa_no_dup:
    ; Table full?
    mov eax, [proto_count]
    cmp eax, PROTO_MAX
    jae .pa_err_full

    ; Clear the entry
    imul eax, eax, PROTO_ENTRY_SIZE
    lea rdi, [proto_table + rax]
    mov rcx, PROTO_ENTRY_SIZE
    xor al, al
    rep stosb

    ; Copy name (max 31 chars + null)
    mov ebx, [proto_count]
    imul eax, ebx, PROTO_ENTRY_SIZE
    lea rdi, [proto_table + rax + PROTO_NAME_OFF]
    xor rcx, rcx
.pa_copy_loop:
    cmp rcx, r13
    je .pa_copy_done
    cmp rcx, 31
    je .pa_copy_done
    movzx rax, byte [r12 + rcx]
    mov [rdi + rcx], al
    inc rcx
    jmp .pa_copy_loop
.pa_copy_done:
    mov byte [rdi + rcx], 0

    ; Init param_var_indices to PROTO_PARAM_UNUSED
    mov ebx, [proto_count]
    imul eax, ebx, PROTO_ENTRY_SIZE
    lea rdi, [proto_table + rax + PROTO_PARAM_VAR_IDX_OFF]
    mov rcx, 65
    mov al, PROTO_PARAM_UNUSED
    rep stosb

    mov eax, [proto_count]
    inc dword [proto_count]
    pop r13
    pop r12
    pop rbx
    ret

.pa_err_dup:
    mov rax, -1
    pop r13
    pop r12
    pop rbx
    ret
.pa_err_full:
    mov rax, -2
    pop r13
    pop r12
    pop rbx
    ret

; ------------------------------------------------------------------
; proto_lookup — find a protocol by name
; rdi = name_ptr, rsi = name_len
; Returns rax = proto_id, or -1 if not found
; ------------------------------------------------------------------
proto_lookup:
    push rbx
    push r12
    push r13

    mov r12, rdi
    mov r13, rsi

    xor ebx, ebx
.pl_loop:
    cmp ebx, [proto_count]
    je .pl_not_found
    imul eax, ebx, PROTO_ENTRY_SIZE
    lea rdi, [proto_table + rax + PROTO_NAME_OFF]
    mov rsi, r12
    mov rdx, r13
    call proto_match_name
    test rax, rax
    jnz .pl_found
    inc ebx
    jmp .pl_loop

.pl_not_found:
    mov rax, -1
    pop r13
    pop r12
    pop rbx
    ret
.pl_found:
    mov rax, rbx
    pop r13
    pop r12
    pop rbx
    ret

; Match a protocol-table name (null-terminated at rdi) against
; buffer rsi of length rdx.  Returns 1 if equal, 0 otherwise.
proto_match_name:
    push rbx
    xor rcx, rcx
.pmn_loop:
    cmp rcx, rdx
    je .pmn_check_null
    movzx rax, byte [rdi + rcx]
    movzx rbx, byte [rsi + rcx]
    cmp al, bl
    jne .pmn_diff
    inc rcx
    jmp .pmn_loop
.pmn_check_null:
    movzx rax, byte [rdi + rcx]
    test al, al
    jne .pmn_diff
    mov rax, 1
    pop rbx
    ret
.pmn_diff:
    xor rax, rax
    pop rbx
    ret

; ------------------------------------------------------------------
; Accessors
; ------------------------------------------------------------------
proto_get_name:
    imul edi, edi, PROTO_ENTRY_SIZE
    lea rax, [proto_table + rdi + PROTO_NAME_OFF]
    ret

proto_get_body_offset:
    imul edi, edi, PROTO_ENTRY_SIZE
    mov eax, [proto_table + rdi + PROTO_BODY_OFF]
    ret

proto_set_body_offset:
    ; rdi = proto_id, rsi = offset
    imul edi, edi, PROTO_ENTRY_SIZE
    mov [proto_table + rdi + PROTO_BODY_OFF], esi
    ret

proto_get_param_count:
    imul edi, edi, PROTO_ENTRY_SIZE
    movzx eax, byte [proto_table + rdi + PROTO_PARAM_COUNT_OFF]
    ret

proto_set_param_count:
    imul edi, edi, PROTO_ENTRY_SIZE
    mov [proto_table + rdi + PROTO_PARAM_COUNT_OFF], sil
    ret

proto_get_ret_count:
    imul edi, edi, PROTO_ENTRY_SIZE
    movzx eax, byte [proto_table + rdi + PROTO_RET_COUNT_OFF]
    ret

proto_set_ret_count:
    imul edi, edi, PROTO_ENTRY_SIZE
    mov [proto_table + rdi + PROTO_RET_COUNT_OFF], sil
    ret

proto_get_ret_type:
    imul edi, edi, PROTO_ENTRY_SIZE
    movzx eax, byte [proto_table + rdi + PROTO_RET_TYPE_OFF]
    ret

proto_set_ret_type:
    imul edi, edi, PROTO_ENTRY_SIZE
    mov [proto_table + rdi + PROTO_RET_TYPE_OFF], sil
    ret

proto_get_ret_is_result:
    imul edi, edi, PROTO_ENTRY_SIZE
    movzx eax, byte [proto_table + rdi + PROTO_RET_IS_RESULT_OFF]
    ret

proto_set_ret_is_result:
    imul edi, edi, PROTO_ENTRY_SIZE
    mov [proto_table + rdi + PROTO_RET_IS_RESULT_OFF], sil
    ret

; rdi = proto_id, rsi = return index (0 or 1)
proto_get_ret_conc_type:
    imul edi, edi, PROTO_ENTRY_SIZE
    lea rax, [proto_table + rdi + PROTO_RET0_TYPE_OFF]
    movzx eax, byte [rax + rsi]
    ret

; rdi = proto_id, rsi = return index (0 or 1), dl = concrete type
proto_set_ret_conc_type:
    imul edi, edi, PROTO_ENTRY_SIZE
    lea rax, [proto_table + rdi + PROTO_RET0_TYPE_OFF]
    mov [rax + rsi], dl
    ret

; rdi = proto_id, rsi = arg index, rdx = param var absolute offset
proto_set_param_var_idx:
    push rbx
    imul edi, edi, PROTO_ENTRY_SIZE
    mov ebx, esi
    mov eax, edx
    mov [proto_table + rdi + PROTO_PARAM_VAR_IDX_OFF + rbx], al
    pop rbx
    ret

; rdi = proto_id, rsi = arg index
; Returns rax = param var absolute offset, or 0 if unused
proto_get_param_var_idx:
    imul edi, edi, PROTO_ENTRY_SIZE
    movzx eax, byte [proto_table + rdi + PROTO_PARAM_VAR_IDX_OFF + rsi]
    ret

; rdi = proto_id, rsi = var_low, rdx = var_high
proto_set_var_range:
    imul edi, edi, PROTO_ENTRY_SIZE
    mov [proto_table + rdi + PROTO_VAR_LOW_OFF], esi
    mov [proto_table + rdi + PROTO_VAR_HIGH_OFF], edx
    ret

; rdi = proto_id
; Returns rax = var_low, rdx = var_high
proto_get_var_range:
    imul edi, edi, PROTO_ENTRY_SIZE
    mov eax, [proto_table + rdi + PROTO_VAR_LOW_OFF]
    mov edx, [proto_table + rdi + PROTO_VAR_HIGH_OFF]
    ret

; ------------------------------------------------------------------
; prescan_protocols — two-pass lexical scan
;
; Pass 1: reset the lexer, walk tokens collecting `prot` definitions and
;         validating `@` call sites.  Protocol bodies are skipped using the
;         INDENT/DEDENT depth so their contents do not confuse the scan.
; Pass 2: reset the lexer again so parse_program begins at token 1.
; ------------------------------------------------------------------
prescan_protocols:
    push rbx
    push r12
    push r13
    push r14
    push r15

    call proto_clear

    ; Reset lexer to the start of the buffer
    mov rdi, [src_ptr]
    mov rsi, [src_len]
    call lex_init
    call next_token

    xor r12d, r12d          ; indent depth (0 = module level)

.ps_loop:
    mov eax, [tok_type]

    cmp eax, TOK_EOF
    je .ps_done

    cmp eax, TOK_INDENT
    je .ps_indent
    cmp eax, TOK_DEDENT
    je .ps_dedent

    cmp eax, TOK_PROT
    je .ps_prot

    cmp eax, TOK_AT
    je .ps_at

.ps_next:
    call next_token
    jmp .ps_loop

.ps_indent:
    inc r12d
    jmp .ps_next

.ps_dedent:
    dec r12d
    jmp .ps_next

.ps_prot:
    ; Only top-level (module-level) definitions are allowed.
    cmp r12d, 0
    jne .ps_prot_err
    ; Collect the protocol signature: name, param count, return arity.
    ; We parse the header tokens directly, then rely on INDENT/DEDENT to
    ; skip the body.
    call next_token         ; token after `prot`

    ; Expect IDENT name
    mov eax, [tok_type]
    cmp eax, TOK_IDENT
    jne .ps_prot_err

    ; Register the protocol
    mov rdi, [tok_str_ptr]
    mov rsi, [tok_str_len]
    call proto_add
    cmp rax, -1
    je .ps_prot_dup
    cmp rax, -2
    je .ps_prot_full
    mov r14, rax            ; r14 = proto_id

    call next_token         ; token after name
    ; Expect '('
    mov eax, [tok_type]
    cmp eax, TOK_LPAREN
    jne .ps_prot_err

    ; Count parameter names between '(' and ')'.  Primitive types lex as
    ; TOK_TYPE but custom type names lex as TOK_IDENT (the type registry is
    ; initialised after the prescan), so counting IDENT tokens is the only
    ; reliable way to count params: each param is `type_expr IDENT`.
    xor r15d, r15d          ; param count
.ps_param_loop:
    call next_token
    mov eax, [tok_type]
    cmp eax, TOK_RPAREN
    je .ps_param_done
    cmp eax, TOK_EOF
    je .ps_prot_err
    cmp eax, TOK_IDENT
    jne .ps_param_loop      ; skip types, commas, brackets
    inc r15d
    jmp .ps_param_loop
.ps_param_done:
    cmp r15d, 65
    jae .ps_prot_err
    mov rdi, r14
    mov rsi, r15
    call proto_set_param_count

    ; Optional return type: '->' ...
    call next_token
    mov eax, [tok_type]
    cmp eax, TOK_ARROW
    jne .ps_no_ret
    call next_token
    mov eax, [tok_type]
    cmp eax, TOK_LPAREN
    je .ps_ret_tuple
    ; Single type or result[T]
    mov rdi, r14
    mov rsi, RET_TYPE_SCALAR
    call proto_set_ret_type
    mov rdi, r14
    mov rsi, 1
    call proto_set_ret_count
    ; Store the concrete return type (ret0).  Primitive types lex as TOK_TYPE
    ; with tok_ival = type id; anything else (custom types, result[T], seq[T])
    ; defaults to TYPE_INT, matching the legacy hardcoded call-site behaviour.
    mov eax, [tok_type]
    cmp eax, TOK_TYPE
    jne .ps_sr_default
    mov ebx, [tok_ival]
    jmp .ps_sr_store
.ps_sr_default:
    mov ebx, TYPE_INT
.ps_sr_store:
    mov rdi, r14
    xor rsi, rsi
    mov rdx, rbx
    call proto_set_ret_conc_type
    ; Consume the rest of the return type tokens up to ':'
.ps_skip_ret:
    call next_token
    mov eax, [tok_type]
    cmp eax, TOK_COLON
    je .ps_header_done
    cmp eax, TOK_EOF
    je .ps_prot_err
    jmp .ps_skip_ret
.ps_ret_tuple:
    ; '(' T (',' T)* ')'
    mov rdi, r14
    mov rsi, RET_TYPE_TUPLE
    call proto_set_ret_type
    xor r15d, r15d
.ps_rt_loop:
    call next_token
    mov eax, [tok_type]
    cmp eax, TOK_RPAREN
    je .ps_rt_done
    cmp eax, TOK_EOF
    je .ps_prot_err
    cmp eax, TOK_TYPE
    je .ps_rt_type
    cmp eax, TOK_IDENT
    jne .ps_rt_loop
    ; Custom type in tuple — count it, default concrete type TYPE_INT
    mov ebx, TYPE_INT
    jmp .ps_rt_store
.ps_rt_type:
    mov ebx, [tok_ival]
.ps_rt_store:
    mov rdi, r14
    mov rsi, r15
    mov rdx, rbx
    call proto_set_ret_conc_type
    inc r15d
    jmp .ps_rt_loop
.ps_rt_done:
    mov rdi, r14
    mov rsi, r15
    call proto_set_ret_count
    call next_token
    mov eax, [tok_type]
    cmp eax, TOK_COLON
    je .ps_header_done
    cmp eax, TOK_EOF
    je .ps_prot_err
    jmp .ps_rt_done

.ps_no_ret:
    ; No return type — wait for ':'
    mov eax, [tok_type]
    cmp eax, TOK_COLON
    je .ps_header_done
    cmp eax, TOK_EOF
    je .ps_prot_err
    jmp .ps_no_ret

.ps_header_done:
    jmp .ps_next

.ps_at:
    ; '@' call sites are validated by parse_proto_call during the real parse,
    ; after every protocol name has been registered.  Forward references (a
    ; protocol body calling a protocol defined later in the file) are legal
    ; per design.md, so we only skip over the name here.
    call next_token ; token after '@'
    jmp .ps_next

.ps_prot_dup:
    mov rdi, err_proto_dup
    jmp ps_error_exit
.ps_prot_full:
    mov rdi, err_proto_full
    jmp ps_error_exit
.ps_prot_err:
    mov rdi, err_proto_syntax
    jmp ps_error_exit
.ps_unknown:
    mov rdi, err_proto_unknown
    jmp ps_error_exit

.ps_done:
    ; Reset the lexer so the main parse starts from the beginning
    mov rdi, [src_ptr]
    mov rsi, [src_len]
    call lex_init

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Report a prescan error (reusing the parser's compile_error is awkward from
; here, so emit the message directly with the current line number).
ps_error_exit:
    push rdi
    call get_error_loc        ; rax = line, rdx = column
    mov r13, rax              ; line
    pop rsi                   ; message
    ; write message to stderr
    mov rax, 1
    mov rdi, 2
    push rsi
    xor rdx, rdx
.len_loop:
    cmp byte [rsi + rdx], 0
    je .len_done
    inc rdx
    jmp .len_loop
.len_done:
    syscall
    pop rsi
    ; write " at line "
    mov rax, 1
    mov rdi, 2
    lea rsi, [rel .at_line_str]
    mov rdx, .at_line_len
    syscall
    ; print line number (r13)
    mov rax, r13
    lea rdi, [rel .num_buf + 15]
    xor ecx, ecx              ; digit count
    mov r8b, 10
.num_loop:
    xor edx, edx
    div r8
    add dl, '0'
    mov [rdi], dl
    dec rdi
    inc ecx
    test rax, rax
    jnz .num_loop
    inc rdi
    ; write the digits
    mov rax, 1
    mov rdi, 2
    mov rsi, rdi
    mov rdx, rcx
    syscall
    ; write newline
    mov rax, 1
    mov rdi, 2
    lea rsi, [rel .nl_str]
    mov rdx, 1
    syscall
    ; exit 1
    mov rax, 60
    mov rdi, 1
    syscall

section .bss
    alignb 1
    .num_buf resb 16

section .rodata
    .at_line_str db " at line "
    .at_line_len equ $ - .at_line_str
    .nl_str db 10
