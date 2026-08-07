; rt_file.asm — file I/O runtime functions for Rex (design.md §15.4)
; Flat binary blob (BITS 64, no ELF headers)
;
; File handle layout (24-byte heap struct, allocated via brk):
;   +0   fd         (qword)
;   +8   mode_flags (qword; bit0 = binary)
;   +16  path_ptr   (qword; heap copy of path, null-terminated)
;
; Calling convention (SysV AMD64). Callee-saved registers (rbx, r12-r15)
; are preserved; r8-r11 are clobbered freely (codegen saves them around
; calls). Never touches rbp (generated spill frames use it).

BITS 64
default rel                     ; all memory refs are RIP-relative

; ── rt_file_open ─────────────────────────────────────────────────────────
; rdi = path string ptr, rsi = mode string ptr
; Returns: rax = file handle
rt_file_open:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                ; path ptr
    mov r13, rsi                ; mode ptr

    ; ---- parse mode ----
    xor r14, r14                ; open flags
    xor r15, r15                ; binary flag
    movzx eax, byte [r13]
    cmp al, 'r'
    jne .open_mode_w
    mov r14, 0                  ; O_RDONLY
    jmp .open_mode1
.open_mode_w:
    cmp al, 'w'
    jne .open_mode_a
    mov r14, 1                  ; O_WRONLY
    or r14, 0x40                ; O_CREAT
    or r14, 0x200               ; O_TRUNC
    jmp .open_mode1
.open_mode_a:
    cmp al, 'a'
    jne .open_mode_bad
    mov r14, 1                  ; O_WRONLY
    or r14, 0x40                ; O_CREAT
    or r14, 0x400               ; O_APPEND
.open_mode1:
    movzx eax, byte [r13 + 1]
    test al, al
    jz .open_mode_done
    cmp al, '+'
    jne .open_mode_b
    and r14, ~1                 ; convert access to O_RDWR
    or r14, 2
    jmp .open_mode_done
.open_mode_b:
    cmp al, 'b'
    jne .open_mode_bad
    mov r15, 1
.open_mode_done:
    ; ---- sys_open(path, flags, 0644) ----
    mov rax, 2                  ; SYS_open
    mov rdi, r12
    mov rsi, r14
    mov rdx, 0x1B4              ; 0644
    syscall
    test rax, rax
    js .open_fail
    mov rbx, rax                ; fd

    ; ---- copy path string to heap ----
    xor r14, r14
.open_path_len:
    cmp byte [r12 + r14], 0
    je .open_path_len_done
    inc r14
    jmp .open_path_len
.open_path_len_done:
    lea rdi, [r14 + 1]
    call rt_brk_alloc
    xor rcx, rcx
.open_path_copy:
    cmp rcx, r14
    je .open_path_copy_done
    movzx edx, byte [r12 + rcx]
    mov [rax + rcx], dl
    inc rcx
    jmp .open_path_copy
.open_path_copy_done:
    mov byte [rax + rcx], 0
    mov r12, rax                ; heap path ptr

    ; ---- allocate 24-byte handle ----
    mov rdi, 24
    call rt_brk_alloc
    mov [rax + 0], rbx          ; fd
    mov [rax + 8], r15          ; mode_flags (binary flag)
    mov [rax + 16], r12         ; path ptr

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.open_fail:
    mov rdi, r12
    call rt_file_open_fail      ; never returns
.open_mode_bad:
    mov rdi, r12
    call rt_file_open_fail      ; never returns

; ── rt_file_open_fail ────────────────────────────────────────────────────
; rdi = path ptr. Writes "RexRuntimeError: cannot open '<path>'\n" to stderr
; and exits with code 1. Never returns.
rt_file_open_fail:
    push rbx
    push r12
    mov rbx, rdi                ; path ptr
    xor r12, r12
.fail_len:
    cmp byte [rbx + r12], 0
    je .fail_len_done
    inc r12
    jmp .fail_len
.fail_len_done:
    mov rax, 1                  ; SYS_write
    mov rdi, 2                  ; stderr
    lea rsi, [open_fail_msg]
    mov rdx, open_fail_msg_len
    syscall
    mov rax, 1
    mov rdi, 2
    mov rsi, rbx
    mov rdx, r12
    syscall
    mov rax, 1
    mov rdi, 2
    lea rsi, [open_fail_suffix]
    mov rdx, open_fail_suffix_len
    syscall
    mov rax, 60                 ; SYS_exit
    mov rdi, 1
    syscall

; ── rt_file_close ────────────────────────────────────────────────────────
; rdi = handle
rt_file_close:
    mov rax, 3                  ; SYS_close
    mov rdi, [rdi]              ; fd
    syscall
    ret

; ── rt_file_read_all_text ────────────────────────────────────────────────
; rdi = handle. Returns: rax = str (heap, null-terminated)
rt_file_read_all_text:
    push rbx
    push r12
    push r13
    push r14
    mov r13, rdi                ; handle
    mov rbx, [r13]              ; fd
    ; size = fstat(fd).st_size (offset 48)
    mov rax, 5                  ; SYS_fstat
    mov rdi, rbx
    lea rsi, [stat_buf]
    syscall
    mov r12, [stat_buf + 48]
    ; pos = lseek(fd, 0, SEEK_CUR)
    mov rax, 8
    mov rdi, rbx
    xor rsi, rsi
    mov rdx, 1
    syscall
    sub r12, rax                ; remaining
    jle .rat_eof
    lea rdi, [r12 + 1]
    call rt_brk_alloc
    mov r14, rax                ; buf
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r12
    call rt_read_loop
    mov byte [r14 + rax], 0
    mov rax, r14
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.rat_eof:
    mov rdi, 1
    call rt_brk_alloc
    mov byte [rax], 0
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ── rt_file_read_line ────────────────────────────────────────────────────
; rdi = handle. Returns: rax = str incl '\n' (empty string at EOF)
rt_file_read_line:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r13, rdi                ; handle
    mov rbx, [r13]              ; fd
    mov rax, 5
    mov rdi, rbx
    lea rsi, [stat_buf]
    syscall
    mov r14, [stat_buf + 48]    ; size
    mov rax, 8
    mov rdi, rbx
    xor rsi, rsi
    mov rdx, 1
    syscall
    mov r15, rax                ; pos
    sub r14, rax                ; remaining
    jle .rl_eof
    lea rdi, [r14 + 1]
    call rt_brk_alloc
    mov r12, rax                ; buf
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r14
    call rt_read_loop           ; rax = bytes read
    xor rcx, rcx
.rl_scan:
    cmp rcx, rax
    jge .rl_no_nl
    cmp byte [r12 + rcx], 10
    je .rl_found
    inc rcx
    jmp .rl_scan
.rl_found:
    push rcx                    ; index of '\n'
    lea rdi, [rcx + 2]
    call rt_brk_alloc
    pop rcx
    xor rdx, rdx
.rl_copy:
    cmp rdx, rcx
    jg .rl_copy_done
    movzx r8d, byte [r12 + rdx]
    mov [rax + rdx], r8b
    inc rdx
    jmp .rl_copy
.rl_copy_done:
    mov byte [rax + rdx], 0
    push rax                    ; line ptr
    lea rsi, [r15 + rcx + 1]    ; offset = pos + index + 1
    mov rax, 8
    mov rdi, rbx
    xor rdx, rdx                ; SEEK_SET
    syscall
    pop rax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.rl_no_nl:
    mov byte [r12 + rax], 0
    mov rax, r12
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.rl_eof:
    mov rdi, 1
    call rt_brk_alloc
    mov byte [rax], 0
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ── rt_file_read_bytes ───────────────────────────────────────────────────
; rdi = handle, rsi = n. Returns: rax = seq[byte] (elements at 8-byte stride)
rt_file_read_bytes:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                ; handle
    mov r13, rsi                ; n
    mov rbx, [r12]              ; fd
    mov rdi, 24
    call rt_brk_alloc
    mov r14, rax                ; header
    mov rdi, r13
    call rt_brk_alloc
    mov r15, rax                ; temp buffer (n bytes)
    mov rdi, rbx
    mov rsi, r15
    mov rdx, r13
    call rt_read_loop
    mov r13, rax                ; bytes read
    test r13, r13
    jle .rby_empty
    lea rdi, [r13*8]
    call rt_brk_alloc
    mov [r14 + 16], rax         ; data_ptr
    mov r10, rax
    xor rcx, rcx
.rby_spread:
    cmp rcx, r13
    jge .rby_fill
    movzx rax, byte [r15 + rcx]
    mov [r10 + rcx*8], al
    inc rcx
    jmp .rby_spread
.rby_fill:
    mov [r14], r13              ; capacity
    mov [r14 + 8], r13          ; length
    mov rax, r14
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.rby_empty:
    mov qword [r14], 0
    mov qword [r14 + 8], 0
    mov qword [r14 + 16], 0
    mov rax, r14
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ── rt_file_read_all_bytes ───────────────────────────────────────────────
; rdi = handle. Returns: rax = seq[byte] (whole rest of file)
rt_file_read_all_bytes:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r13, rdi                ; handle
    mov rbx, [r13]              ; fd
    mov rax, 5
    mov rdi, rbx
    lea rsi, [stat_buf]
    syscall
    mov r14, [stat_buf + 48]    ; size
    mov rax, 8
    mov rdi, rbx
    xor rsi, rsi
    mov rdx, 1
    syscall
    sub r14, rax                ; remaining
    jle .rab_empty
    mov rdi, 24
    call rt_brk_alloc
    mov r12, rax                ; header
    mov rdi, r14
    call rt_brk_alloc
    mov r15, rax                ; temp buffer
    mov rdi, rbx
    mov rsi, r15
    mov rdx, r14
    call rt_read_loop
    mov r14, rax                ; bytes read
    lea rdi, [r14*8]
    call rt_brk_alloc
    mov [r12 + 16], rax         ; data_ptr
    mov r10, rax
    xor rcx, rcx
.rab_spread:
    cmp rcx, r14
    jge .rab_fill
    movzx rax, byte [r15 + rcx]
    mov [r10 + rcx*8], al
    inc rcx
    jmp .rab_spread
.rab_fill:
    mov [r12], r14
    mov [r12 + 8], r14
    mov rax, r12
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.rab_empty:
    mov rdi, 24
    call rt_brk_alloc
    mov qword [rax], 0
    mov qword [rax + 8], 0
    mov qword [rax + 16], 0
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ── rt_file_lines ────────────────────────────────────────────────────────
; rdi = handle. Returns: rax = seq[str] (remaining lines, '\n' stripped)
rt_file_lines:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r13, rdi                ; handle
    mov rbx, [r13]              ; fd
    mov rax, 5
    mov rdi, rbx
    lea rsi, [stat_buf]
    syscall
    mov r14, [stat_buf + 48]    ; size
    mov rax, 8
    mov rdi, rbx
    xor rsi, rsi
    mov rdx, 1
    syscall
    sub r14, rax                ; remaining
    jle .lines_empty
    lea rdi, [r14 + 1]
    call rt_brk_alloc
    mov r12, rax                ; text buffer
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r14
    call rt_read_loop
    mov r15, rax                ; bytes read
    mov byte [r12 + r15], 0
    ; count lines ('\n' count, plus 1 if last line lacks '\n')
    xor rcx, rcx
    xor rdx, rdx
.lines_count:
    cmp rdx, r15
    jge .lines_count_done
    cmp byte [r12 + rdx], 10
    jne .lines_count_next
    inc rcx
.lines_count_next:
    inc rdx
    jmp .lines_count
.lines_count_done:
    test r15, r15
    jz .lines_count_final
    lea rdx, [r15 - 1]
    cmp byte [r12 + rdx], 10
    je .lines_count_final
    inc rcx
.lines_count_final:
    push rcx                    ; line count
    mov rdi, 24
    call rt_brk_alloc
    mov r14, rax                ; header
    pop rcx
    push rcx
    lea rdi, [rcx * 8]
    call rt_brk_alloc
    mov [r14 + 16], rax         ; data_ptr
    pop rcx
    mov [r14], rcx              ; capacity
    mov [r14 + 8], rcx          ; length
    xor rdx, rdx                ; read offset
    xor rcx, rcx                ; line index
.lines_walk:
    cmp rdx, r15
    jge .lines_done
    mov rdi, rdx                ; line start
.lines_find_nl:
    cmp rdx, r15
    jge .lines_end_nl
    cmp byte [r12 + rdx], 10
    je .lines_found_nl
    inc rdx
    jmp .lines_find_nl
.lines_found_nl:
    mov rsi, rdx
    sub rsi, rdi                ; line len (excludes '\n')
    inc rdx                     ; skip '\n'
    jmp .lines_copy
.lines_end_nl:
    mov rsi, rdx
    sub rsi, rdi                ; line len
.lines_copy:
    push rcx
    push rdx
    push rsi
    push rdi
    lea rdi, [rsi + 1]
    call rt_brk_alloc
    pop rdi                     ; line start
    pop rsi                     ; line len
    pop rdx                     ; next offset
    pop rcx                     ; line index
    push rax
    mov r10, r12
    add r10, rdi                ; r10 = &text[line_start]
    xor r8, r8
.lines_copy_loop:
    cmp r8, rsi
    jge .lines_copy_done
    movzx r9d, byte [r10 + r8]
    mov [rax + r8], r9b
    inc r8
    jmp .lines_copy_loop
.lines_copy_done:
    pop rax
    mov byte [rax + rsi], 0
    mov r8, [r14 + 16]          ; data_ptr
    mov [r8 + rcx * 8], rax
    inc rcx
    jmp .lines_walk
.lines_done:
    mov rax, r14
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.lines_empty:
    mov rdi, 24
    call rt_brk_alloc
    mov qword [rax], 0
    mov qword [rax + 8], 0
    mov qword [rax + 16], 0
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ── rt_file_write ────────────────────────────────────────────────────────
; rdi = handle, rsi = str
rt_file_write:
    push rbx
    push r12
    push r13
    mov r12, rdi                ; handle
    mov r13, rsi                ; str
    mov rbx, [r12]              ; fd
    xor rdx, rdx
.wr_len:
    cmp byte [r13 + rdx], 0
    je .wr_len_done
    inc rdx
    jmp .wr_len
.wr_len_done:
    mov rdi, rbx
    mov rsi, r13
    call rt_write_loop
    pop r13
    pop r12
    pop rbx
    ret

; ── rt_file_writeln ──────────────────────────────────────────────────────
; rdi = handle, rsi = str (appends '\n')
rt_file_writeln:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    mov rbx, [r12]
    xor rdx, rdx
.wln_len:
    cmp byte [r13 + rdx], 0
    je .wln_len_done
    inc rdx
    jmp .wln_len
.wln_len_done:
    mov rdi, rbx
    mov rsi, r13
    call rt_write_loop
    lea rsi, [rel .wln_nl]      ; NOT [rsp]: call would clobber the byte
    mov rdx, 1
    mov rdi, rbx
    call rt_write_loop
    pop r13
    pop r12
    pop rbx
    ret
.wln_nl: db 10

; ── rt_file_write_bytes ──────────────────────────────────────────────────
; rdi = handle, rsi = seq[byte] (elements at 8-byte stride)
rt_file_write_bytes:
    push rbx
    push r12
    push r13
    push r15
    mov rbx, [rdi]              ; fd
    mov r15, [rsi + 8]          ; length
    test r15, r15
    jz .wby_done
    mov r12, [rsi + 16]         ; data_ptr
    xor r13, r13                ; i
.wby_loop:
    cmp r13, r15
    jge .wby_done
    lea rsi, [r12 + r13*8]
    mov rdi, rbx
    mov rdx, 1
    call rt_write_loop
    inc r13
    jmp .wby_loop
.wby_done:
    pop r15
    pop r13
    pop r12
    pop rbx
    ret

; ── rt_file_seek ─────────────────────────────────────────────────────────
; rdi = handle, rsi = byte offset from start
rt_file_seek:
    push rbx
    mov rbx, [rdi]
    mov rax, 8
    mov rdi, rbx
    xor rdx, rdx                ; SEEK_SET
    syscall
    pop rbx
    ret

; ── rt_file_seek_end ─────────────────────────────────────────────────────
; rdi = handle, rsi = n bytes before end (seek_end(0) = EOF)
rt_file_seek_end:
    push rbx
    mov rbx, [rdi]
    mov rax, 8
    mov rdi, rbx
    neg rsi
    mov rdx, 2                  ; SEEK_END
    syscall
    pop rbx
    ret

; ── rt_file_pos ──────────────────────────────────────────────────────────
; rdi = handle. Returns: rax = current byte position
rt_file_pos:
    push rbx
    mov rbx, [rdi]
    mov rax, 8
    mov rdi, rbx
    xor rsi, rsi
    mov rdx, 1                  ; SEEK_CUR
    syscall
    pop rbx
    ret

; ── rt_file_size ─────────────────────────────────────────────────────────
; rdi = handle. Returns: rax = total file size
rt_file_size:
    push rbx
    mov rbx, [rdi]
    mov rax, 5
    mov rdi, rbx
    lea rsi, [stat_buf]
    syscall
    mov rax, [stat_buf + 48]
    pop rbx
    ret

; ── rt_file_is_eof ───────────────────────────────────────────────────────
; rdi = handle. Returns: rax = 1 if at end of file, else 0
rt_file_is_eof:
    push rbx
    push r12
    push r13
    mov rbx, [rdi]
    mov rax, 8
    mov rdi, rbx
    xor rsi, rsi
    mov rdx, 1
    syscall
    mov r12, rax                ; pos
    mov rax, 5
    mov rdi, rbx
    lea rsi, [stat_buf]
    syscall
    mov r13, [stat_buf + 48]    ; size
    xor eax, eax
    cmp r12, r13
    jl .eof_no
    mov al, 1
.eof_no:
    pop r13
    pop r12
    pop rbx
    ret

; ── rt_file_flush ────────────────────────────────────────────────────────
; rdi = handle. Writes are unbuffered (direct syscalls); no-op.
rt_file_flush:
    ret

; ── rt_file_path ─────────────────────────────────────────────────────────
; rdi = handle. Returns: rax = path string ptr
rt_file_path:
    mov rax, [rdi + 16]
    ret

; ── rt_file_exists ───────────────────────────────────────────────────────
; rdi = path string ptr. Returns: rax = 1 if exists, else 0
rt_file_exists:
    mov rax, 21                 ; SYS_access
    xor rsi, rsi                ; F_OK
    syscall
    test rax, rax
    setz al
    movzx eax, al
    ret

; ── internal helpers ─────────────────────────────────────────────────────
; rt_brk_alloc: rdi = bytes → rax = pointer (two-step brk)
rt_brk_alloc:
    push rbx
    mov rbx, rdi
    mov rax, 12
    xor rdi, rdi
    syscall
    push rax
    mov rdi, rax
    add rdi, rbx
    mov rax, 12
    syscall
    pop rax
    pop rbx
    ret

; rt_read_loop: rdi = fd, rsi = buf, rdx = count → rax = bytes read
rt_read_loop:
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor r14, r14
.rl_loop:
    test r13, r13
    jz .rl_done
    mov rax, 0                  ; SYS_read
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    syscall
    test rax, rax
    jle .rl_done
    add r12, rax
    sub r13, rax
    add r14, rax
    jmp .rl_loop
.rl_done:
    mov rax, r14
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rt_write_loop: rdi = fd, rsi = buf, rdx = count
rt_write_loop:
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor r14, r14
.wl_loop:
    test r13, r13
    jz .wl_done
    mov rax, 1                  ; SYS_write
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    syscall
    test rax, rax
    jle .wl_done
    add r12, rax
    sub r13, rax
    add r14, rax
    jmp .wl_loop
.wl_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ── static data (inline in text so the flat blob is self-contained) ─────
open_fail_msg   db "RexRuntimeError: cannot open '", 0
open_fail_msg_len equ $ - open_fail_msg
open_fail_suffix db "'", 10, 0
open_fail_suffix_len equ $ - open_fail_suffix
stat_buf        times 144 db 0
