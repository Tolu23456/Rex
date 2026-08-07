; Rex Module System (design.md §17)
; written in x86-64 NASM assembly
;
; Implements the module registry, per-module import records, file-module
; loading, and the cross-buffer parse that emits module init code at the
; first `use` site (so init statements run once, in declaration order,
; interleaved correctly in the flat IR stream — see parse_module_body).

%include "include/rex_defs.inc"

section .data
    global current_module
    global module_parse_depth
    global module_main_dir_ptr
    global module_main_dir_len

    current_module      dd 0          ; module id of the parse/prescan context
    module_parse_depth  dd 0          ; >0 while parsing a module body
    module_main_dir_ptr dq 0          ; directory of the main source file
    module_main_dir_len dq 0

section .rodata
    err_unknown_module  db "Compile Error: Unknown module", 0
    err_dup_module      db "Compile Error: Duplicate module definition", 0
    err_module_full     db "Compile Error: Module table full", 0
    err_module_cycle    db "Compile Error: Circular import (modules: ", 0
    err_module_missing  db "Compile Error: Module file not found", 0
    err_module_too_big  db "Compile Error: Module file exceeds SRC_FILE_MAX", 0
    err_inline_not_parsed db "Compile Error: Inline module must be defined before use", 0
    err_private_member  db "Compile Error: Cannot access private member", 0
    err_import_full     db "Compile Error: Too many module imports (max 256)", 0
    err_nested_module   db "Compile Error: 'module' blocks cannot be nested", 0
    err_mod_close       db "Compile Error: Unexpected token in module block", 0
    err_rparen          db "Compile Error: Expected ')'", 0
    str_empty_close     db ")", 0

section .bss
    global module_table
    global module_count
    global import_table
    global import_count
    module_table        resb MODULE_MAX * MODULE_ENTRY_SIZE
    module_count        resd 1
    import_table        resb IMPORT_MAX * IMPORT_ENTRY_SIZE
    import_count        resd 1
    module_file_bufs    resb MODULE_MAX * SRC_FILE_MAX
    mod_path_buf        resb 512
    err_msg_buf         resb 512

section .text
    global module_clear
    global module_lookup
    global module_add
    global module_get_status
    global module_set_status
    global module_get_kind
    global module_get_source
    global module_mark_visiting
    global module_unmark_visiting
    global module_is_visiting
    global module_import_add
    global module_import_find
    global module_load_file
    global parse_module_body
    global module_set_main_dir
    global module_cycle_error

    extern compile_error
    extern parse_program
    extern lexer_save_state
    extern lexer_restore_state
    extern lexer_load_buffer
    extern tok_str_ptr
    extern tok_str_len
    extern tok_type
    extern current_token
    extern current_sym_module

; ------------------------------------------------------------------
; module_set_main_dir — record the directory prefix of the main source
; file (everything up to and including the last '/'). rdi = path.
; ------------------------------------------------------------------
module_set_main_dir:
    push rsi
    mov rsi, rdi
    xor edx, edx
.msd_scan:
    cmp byte [rsi], 0
    je .msd_done
    cmp byte [rsi], '/'
    jne .msd_next
    lea rdx, [rsi + 1]
.msd_next:
    inc rsi
    jmp .msd_scan
.msd_done:
    ; rdx = ptr just past last '/', or 0 if no '/' (→ no dir prefix)
    test rdx, rdx
    jnz .msd_have_dir
    mov qword [module_main_dir_len], 0
    jmp .msd_ret
.msd_have_dir:
    sub rdx, rdi
    mov [module_main_dir_ptr], rdi
    mov [module_main_dir_len], rdx
.msd_ret:
    pop rsi
    ret

; ------------------------------------------------------------------
; module_clear — reset the module and import tables
; ------------------------------------------------------------------
module_clear:
    mov dword [module_count], 0
    mov dword [import_count], 0
    mov dword [current_module], 0
    mov dword [module_parse_depth], 0
    ret

; ------------------------------------------------------------------
; module_lookup — rdi = name_ptr, rsi = name_len → rax = id or -1
; ------------------------------------------------------------------
module_lookup:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    xor ebx, ebx
.ml_loop:
    cmp ebx, [module_count]
    jae .ml_not_found
    imul eax, ebx, MODULE_ENTRY_SIZE
    lea rdi, [module_table + rax + MODULE_NAME_OFF]
    mov rsi, r12
    mov rdx, r13
    call module_name_match
    test rax, rax
    jnz .ml_found
    inc ebx
    jmp .ml_loop
.ml_found:
    mov rax, rbx
    pop r13
    pop r12
    pop rbx
    ret
.ml_not_found:
    mov rax, -1
    pop r13
    pop r12
    pop rbx
    ret

; Compare null-terminated name at rdi with [rsi, rsi+rdx). rax = 1/0.
module_name_match:
    push rbx
    xor rcx, rcx
.mnm_loop:
    cmp rcx, rdx
    je .mnm_check_null
    movzx rax, byte [rdi + rcx]
    movzx rbx, byte [rsi + rcx]
    cmp al, bl
    jne .mnm_diff
    inc rcx
    jmp .mnm_loop
.mnm_check_null:
    movzx rax, byte [rdi + rcx]
    test rax, rax
    jnz .mnm_diff
    mov rax, 1
    pop rbx
    ret
.mnm_diff:
    xor rax, rax
    pop rbx
    ret

; ------------------------------------------------------------------
; module_name_match_n — length-only comparison of two identifiers.
; rdi = name A ptr, rsi = name B ptr, rdx = length (bytes).
; Returns rax = 1 if equal, 0 otherwise. Unlike module_name_match this
; does NOT require a null terminator at [rdi + rdx] (import names are
; raw pointers into source text and are not null-terminated).
; ------------------------------------------------------------------
module_name_match_n:
    push rbx
    xor rcx, rcx
.mnmn_loop:
    cmp rcx, rdx
    je .mnmn_eq
    movzx rax, byte [rdi + rcx]
    movzx rbx, byte [rsi + rcx]
    cmp al, bl
    jne .mnmn_diff
    inc rcx
    jmp .mnmn_loop
.mnmn_eq:
    mov rax, 1
    pop rbx
    ret
.mnmn_diff:
    xor rax, rax
    pop rbx
    ret

; ------------------------------------------------------------------
; module_add — get-or-create a module by name.
; rdi = name_ptr, rsi = name_len, edx = kind.
; Returns rax = id, or -1 if the table is full. If the name already
; exists, its id is returned (the caller enforces duplicate conflicts).
; ------------------------------------------------------------------
module_add:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi ; name_ptr
    mov r13, rsi ; name_len
    mov r14, rdx ; kind

    ; Existing module?
    mov rdi, r12
    mov rsi, r13
    call module_lookup
    cmp rax, -1
    jne .ma_done

    ; New entry
    mov eax, [module_count]
    cmp eax, MODULE_MAX
    jae .ma_full

    imul r15, rax, MODULE_ENTRY_SIZE
    lea rdi, [module_table + r15]
    mov rcx, MODULE_ENTRY_SIZE
    xor al, al
    rep stosb

    ; Copy name (max 63)
    lea rdi, [module_table + r15 + MODULE_NAME_OFF]
    xor rcx, rcx
.ma_copy:
    cmp rcx, r13
    je .ma_copy_done
    cmp rcx, 63
    je .ma_copy_done
    movzx rax, byte [r12 + rcx]
    mov [rdi + rcx], al
    inc rcx
    jmp .ma_copy
.ma_copy_done:
    mov byte [rdi + rcx], 0

    mov eax, [module_count]
    imul r15, rax, MODULE_ENTRY_SIZE
    mov [module_table + r15 + MODULE_KIND_OFF], r14b
    mov byte [module_table + r15 + MODULE_STATUS_OFF], MOD_ST_NONE

    mov eax, [module_count]
    inc dword [module_count]
.ma_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.ma_full:
    mov rdi, err_module_full
    call compile_error

; ------------------------------------------------------------------
; Module accessors
; ------------------------------------------------------------------
module_get_status: ; rdi = id → eax
    imul edi, edi, MODULE_ENTRY_SIZE
    movzx eax, byte [module_table + rdi + MODULE_STATUS_OFF]
    ret

module_set_status: ; rdi = id, esi = status
    imul edi, edi, MODULE_ENTRY_SIZE
    mov [module_table + rdi + MODULE_STATUS_OFF], sil
    ret

module_get_kind: ; rdi = id → eax
    imul edi, edi, MODULE_ENTRY_SIZE
    movzx eax, byte [module_table + rdi + MODULE_KIND_OFF]
    ret

module_get_source: ; rdi = id → rax = ptr, rdx = len
    imul edi, edi, MODULE_ENTRY_SIZE
    mov rax, [module_table + rdi + MODULE_SRC_PTR_OFF]
    mov rdx, [module_table + rdi + MODULE_SRC_LEN_OFF]
    ret

module_mark_visiting: ; rdi = id → eax = 1 if already visiting, 0 if newly marked
    imul edi, edi, MODULE_ENTRY_SIZE
    cmp dword [module_table + rdi + MODULE_VISITING_OFF], 0
    jne .mv_visiting
    mov dword [module_table + rdi + MODULE_VISITING_OFF], 1
    xor eax, eax
    ret
.mv_visiting:
    mov eax, 1
    ret

module_unmark_visiting: ; rdi = id
    imul edi, edi, MODULE_ENTRY_SIZE
    mov dword [module_table + rdi + MODULE_VISITING_OFF], 0
    ret

module_is_visiting: ; rdi = id → eax = 1/0
    imul edi, edi, MODULE_ENTRY_SIZE
    mov eax, [module_table + rdi + MODULE_VISITING_OFF]
    ret

; ------------------------------------------------------------------
; module_import_add — record an import for the current module.
; rdi = target module id, rsi = name_ptr, rdx = name_len, rcx = is_star.
; Returns rax = 0, or -1 if the import table is full.
; ------------------------------------------------------------------
module_import_add:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi ; tgt
    mov r13, rsi ; name_ptr
    mov r14, rdx ; name_len
    mov r15, rcx ; is_star

    mov eax, [import_count]
    cmp eax, IMPORT_MAX
    jae .mia_full

    imul rbx, rax, IMPORT_ENTRY_SIZE
    lea rdi, [import_table + rbx]
    mov ecx, [current_module]
    mov [rdi + IMPORT_SRC_OFF], ecx
    mov [rdi + IMPORT_TGT_OFF], r12d
    mov [rdi + IMPORT_NAME_PTR_OFF], r13
    mov [rdi + IMPORT_NAME_LEN_OFF], r14d
    mov [rdi + IMPORT_STAR_OFF], r15d

    inc dword [import_count]
    xor eax, eax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.mia_full:
    mov rdi, err_import_full
    call compile_error

; ------------------------------------------------------------------
; module_import_find — resolve an unqualified name against the current
; module's imports. rdi = name_ptr, rsi = name_len → rax = target module
; id providing the name, or -1.
; ------------------------------------------------------------------
module_import_find:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi ; name_ptr
    mov r13, rsi ; name_len
    xor r15d, r15d ; star-match fallback (last star import wins)
    mov r14d, -1
    xor ebx, ebx
.mif_loop:
    cmp ebx, [import_count]
    jae .mif_done
    imul eax, ebx, IMPORT_ENTRY_SIZE
    lea rdi, [import_table + rax]
    mov eax, [rdi + IMPORT_SRC_OFF]
    cmp eax, [current_module]
    jne .mif_next
    ; matching source module
    cmp dword [rdi + IMPORT_STAR_OFF], 0
    je .mif_named
    ; star import: remember the last star target (later imports override)
    mov r14d, [rdi + IMPORT_TGT_OFF]
    jmp .mif_next
.mif_named:
    mov rax, [rdi + IMPORT_NAME_LEN_OFF]
    cmp rax, r13
    jne .mif_next
    mov r8, rdi              ; keep entry pointer (module_name_match may clobber rdi)
    mov rsi, [rdi + IMPORT_NAME_PTR_OFF]
    mov rdx, r13
    mov rdi, r12
    call module_name_match_n
    test rax, rax
    jz .mif_next
    ; found a selective import for this name
    mov r14d, [r8 + IMPORT_TGT_OFF]
    jmp .mif_found
.mif_next:
    inc ebx
    jmp .mif_loop
.mif_found:
    mov rax, r14
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.mif_done:
    mov rax, r14
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ------------------------------------------------------------------
; module_load_file — read <main_dir>/<name>.rx into the module's buffer.
; rdi = module_id. Never returns on failure (compile_error).
; The module name is already stored in the table.
; Register budget: r12 = module_id (held for the whole function);
; r13/r14/r15 transient.
; ------------------------------------------------------------------
module_load_file:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi ; module_id (kept intact)

    ; Build path: [main_dir]<name>.rx
    lea rbx, [mod_path_buf] ; cursor
    mov rsi, [module_main_dir_ptr]
    mov rcx, [module_main_dir_len]
.mlf_cp_dir:
    test rcx, rcx
    jz .mlf_dir_done
    movzx rax, byte [rsi]
    mov [rbx], al
    inc rsi
    inc rbx
    dec rcx
    jmp .mlf_cp_dir
.mlf_dir_done:
    imul eax, r12d, MODULE_ENTRY_SIZE
    lea rsi, [module_table + rax + MODULE_NAME_OFF]
.mlf_cp_name:
    cmp byte [rsi], 0
    je .mlf_name_done
    mov al, [rsi]
    mov [rbx], al
    inc rsi
    inc rbx
    jmp .mlf_cp_name
.mlf_name_done:
    mov byte [rbx], '.'
    mov byte [rbx + 1], 'r'
    mov byte [rbx + 2], 'x'
    mov byte [rbx + 3], 0

    ; sys_open(path, O_RDONLY)
    mov rax, 2
    lea rdi, [mod_path_buf]
    xor rsi, rsi
    xor rdx, rdx
    syscall
    cmp rax, 0
    jl .mlf_missing
    mov r14, rax ; fd

    ; size via lseek END
    mov rax, 8
    mov rdi, r14
    xor rsi, rsi
    mov rdx, 2
    syscall
    cmp rax, SRC_FILE_MAX
    jge .mlf_too_big
    mov r15, rax ; size

    ; seek back
    mov rax, 8
    mov rdi, r14
    xor rsi, rsi
    xor rdx, rdx
    syscall

    ; read into module_file_bufs[id]
    mov rax, r12
    imul rax, rax, SRC_FILE_MAX
    lea r13, [module_file_bufs + rax]
    xor ebx, ebx ; bytes read
.mlf_read:
    mov rax, 0
    mov rdi, r14
    mov rdx, r15
    sub rdx, rbx
    jz .mlf_read_done
    lea rsi, [r13 + rbx]
    syscall
    cmp rax, 0
    jl .mlf_read_err
    jz .mlf_read_done
    add rbx, rax
    cmp rbx, r15
    jl .mlf_read
.mlf_read_done:
    ; close fd
    mov rax, 3
    mov rdi, r14
    syscall

    ; store source ptr/len in the module entry
    imul eax, r12d, MODULE_ENTRY_SIZE
    lea rdi, [module_table + rax + MODULE_SRC_PTR_OFF]
    mov [rdi], r13
    imul eax, r12d, MODULE_ENTRY_SIZE
    lea rdi, [module_table + rax + MODULE_SRC_LEN_OFF]
    mov [rdi], rbx

    xor eax, eax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.mlf_missing:
    mov rdi, err_module_missing
    call module_name_error
.mlf_too_big:
    mov rdi, err_module_too_big
    call module_name_error
.mlf_read_err:
    mov rdi, err_module_missing
    call module_name_error

; ------------------------------------------------------------------
; parse_module_body — parse a FILE module's source to EOF, emitting its
; protos and init statements into the IR stream at the current position.
; rdi = module_id.
; The lexer is switched to the module's buffer for the duration and fully
; restored afterwards (so the enclosing buffer's token stream continues).
; Init statements therefore land in the main linear execution path at the
; first-`use` site, giving "run once, in declaration order" semantics.
; ------------------------------------------------------------------
parse_module_body:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r14, rdi ; module_id

    ; Save the enclosing lexer state
    sub rsp, LEXSV_SIZE
    mov rdi, rsp
    call lexer_save_state

    ; Switch to the module's source buffer
    mov rdi, r14
    call module_get_source ; rax = ptr, rdx = len
    mov r12, rax
    mov r13, rdx
    test r12, r12
    jz .pmb_no_source
    mov rdi, r12
    mov rsi, r13
    call lexer_load_buffer

    ; Prime: the module file starts as if at a newline boundary.
    mov dword [tok_type], 0

    ; Switch module context
    mov eax, [current_module]
    push rax
    mov dword [current_module], r14d
    ; Globals declared in the module belong to the module's namespace.
    mov eax, [current_sym_module]
    push rax
    mov dword [current_sym_module], r14d

    inc dword [module_parse_depth]
    ; .prot_stmt uses r14 (and r15) as scratch without preserving it, so the
    ; module_id in r14 is not reliable across parse_program — stash it on the
    ; stack for the status update below.
    push r14
    call parse_program
    pop r14
    dec dword [module_parse_depth]

    pop rax
    mov [current_sym_module], eax
    pop rax
    mov [current_module], eax

    ; Mark parsed
    mov rdi, r14
    mov esi, MOD_ST_PARSED
    call module_set_status

    ; Restore the enclosing lexer state
    mov rdi, rsp
    call lexer_restore_state
    ; The lexer's tok_type was restored to the enclosing stream's current
    ; token (the NEWLINE ending the `use` line); the parser's current_token
    ; still holds the module's trailing EOF, which would terminate the
    ; enclosing parse_program early. Resync it from the restored lexer.
    mov eax, [tok_type]
    mov [current_token], eax
    add rsp, LEXSV_SIZE

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.pmb_no_source:
    mov rdi, err_module_missing
    call compile_error

; ------------------------------------------------------------------
; Error helpers
; ------------------------------------------------------------------
; Build "Circular import (modules: a, b, c)" listing every module whose
; prescan is currently visiting, then report it.
module_cycle_error:
    lea rdi, [err_msg_buf]
    mov rsi, err_module_cycle
.mce_cp:
    cmp byte [rsi], 0
    je .mce_cp_done
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    jmp .mce_cp
.mce_cp_done:
    xor ebx, ebx
    mov rcx, rdi ; rcx = msg cursor (first name)
.mce_loop:
    cmp ebx, [module_count]
    jae .mce_done
    imul eax, ebx, MODULE_ENTRY_SIZE
    cmp dword [module_table + rax + MODULE_VISITING_OFF], 0
    je .mce_next
    ; append ", " before all but the first
    cmp rdi, rcx
    je .mce_no_sep
    mov byte [rdi], ','
    mov byte [rdi + 1], ' '
    add rdi, 2
.mce_no_sep:
    lea rsi, [module_table + rax + MODULE_NAME_OFF]
.mce_nm:
    cmp byte [rsi], 0
    je .mce_nm_done
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    jmp .mce_nm
.mce_nm_done:
.mce_next:
    inc ebx
    jmp .mce_loop
.mce_done:
    mov byte [rdi], ')'
    mov byte [rdi + 1], 0
    lea rdi, [err_msg_buf]
    call compile_error

; Append the current identifier token's name to err_msg_buf and report it.
; rdi = base error message (null-terminated).
module_name_error:
    mov rsi, rdi
    ; copy base message
    lea rdi, [err_msg_buf]
.mne_cp:
    cmp byte [rsi], 0
    je .mne_cp_done
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    jmp .mne_cp
.mne_cp_done:
    ; append ": <name>"
    mov byte [rdi], ':'
    mov byte [rdi + 1], ' '
    add rdi, 2
    mov rsi, [tok_str_ptr]
    mov rcx, [tok_str_len]
.mne_nm:
    test rcx, rcx
    jz .mne_nm_done
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jmp .mne_nm
.mne_nm_done:
    mov byte [rdi], 0
    lea rdi, [err_msg_buf]
    call compile_error
