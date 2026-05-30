; -----------------------------------------------------------------------------
; Rex V5.0 Runtime - FIXED
; -----------------------------------------------------------------------------

default rel
%include "include/rex_defs.inc"

global rt_pri_blob, rt_prs_blob, rt_prb_blob, rt_prf_blob, rt_prc_blob, rt_sip_blob, rt_alc_blob, rt_prq_blob, rt_err_blob
global rt_dict_new, rt_dict_set, rt_dict_get

section .text

rt_pri_blob:
    push rbp
    mov rbp, rsp
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    sub rsp, 64
    mov rax, rdi
    test rax, rax
    jns .pos
    neg rax
    mov byte [rsp+63], '-'
    mov rax, 1
    mov rdi, 1
    lea rsi, [rsp+63]
    mov rdx, 1
    syscall
    mov rax, [rbp-48]
    neg rax
.pos:
    lea rdi, [rsp+62]
    mov byte [rdi], 10
    mov rcx, 1
    mov rbx, 10
.l1:
    xor rdx, rdx
    div rbx
    add dl, '0'
    dec rdi
    mov [rdi], dl
    inc rcx
    test rax, rax
    jnz .l1
    mov rax, 1
    mov rsi, rdi
    mov rdx, rcx
    mov rdi, 1
    syscall
    add rsp, 64
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    leave
    ret
    times RT_PRI_SIZE - ($ - rt_pri_blob) db 0x90

; rt_prs_blob: print a null-terminated string pointer from RDI, followed by newline.
rt_prs_blob:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    ; compute length: scan for null byte
    mov rbx, rdi            ; save ptr
    xor rcx, rcx
.len_loop:
    cmp byte [rbx+rcx], 0
    je .len_done
    inc rcx
    jmp .len_loop
.len_done:
    ; sys_write(1, ptr, len)
    test rcx, rcx
    jz .write_nl
    mov rax, 1
    mov rdi, 1
    mov rsi, rbx
    mov rdx, rcx
    syscall
.write_nl:
    ; write newline
    push qword 10
    mov rax, 1
    mov rdi, 1
    mov rsi, rsp
    mov rdx, 1
    syscall
    add rsp, 8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    leave
    ret
    times RT_PRS_SIZE - ($ - rt_prs_blob) db 0x90

; rt_prb_blob: print bool from RDI (0=false, 1=true, other=unknown) + newline.
rt_prb_blob:
    push rbp
    mov rbp, rsp
    push rbx
    push rdx
    push rsi
    push rdi
    cmp rdi, 1
    je .b_true
    cmp rdi, 0
    je .b_false
    ; unknown
    lea rsi, [rel .s_unknown]
    mov rdx, 8
    jmp .b_write
.b_true:
    lea rsi, [rel .s_true]
    mov rdx, 5
    jmp .b_write
.b_false:
    lea rsi, [rel .s_false]
    mov rdx, 6
.b_write:
    mov rax, 1
    mov rdi, 1
    syscall
    pop rdi
    pop rsi
    pop rdx
    pop rbx
    leave
    ret
.s_true:    db "true", 10
.s_false:   db "false", 10
.s_unknown: db "unknown", 10
    times RT_PRB_SIZE - ($ - rt_prb_blob) db 0x90

rt_prf_blob:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13
    sub rsp, 128
    lea r13, [rbp-120]
    movq xmm0, rdi
    movmskpd eax, xmm0
    test eax, 1
    jz .pos
    mov byte [r13], '-'
    mov rax, 1
    mov rdi, 1
    mov rsi, r13
    mov rdx, 1
    syscall
    mov rax, 0x7FFFFFFFFFFFFFFF
    movq xmm1, rax
    andpd xmm0, xmm1
.pos:
    cvttsd2si rbx, xmm0
    push rdi
    mov rdi, rbx
    call rt_pri_no_nl
    pop rdi
    mov byte [r13], '.'
    mov rax, 1
    mov rdi, 1
    mov rsi, r13
    mov rdx, 1
    syscall
    cvtsi2sd xmm1, rbx
    subsd xmm0, xmm1
    mov r12, 6
    mov rax, 0x4024000000000000
    movq xmm2, rax
.frac_loop:
    mulsd xmm0, xmm2
    cvttsd2si rbx, xmm0
    add bl, '0'
    mov [r13], bl
    push rdi
    push rsi
    push rdx
    push rcx
    mov rax, 1
    mov rdi, 1
    mov rsi, r13
    mov rdx, 1
    syscall
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    sub bl, '0'
    cvtsi2sd xmm1, rbx
    subsd xmm0, xmm1
    dec r12
    jnz .frac_loop
    mov byte [r13], 10
    mov rax, 1
    mov rdi, 1
    mov rsi, r13
    mov rdx, 1
    syscall
    add rsp, 128
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    leave
    ret
rt_pri_no_nl:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    sub rsp, 32
    mov rax, rdi
    test rax, rax
    jnz .p1
    mov byte [rsp], '0'
    mov rax, 1
    mov rdi, 1
    mov rsi, rsp
    mov rdx, 1
    syscall
    jmp .d
.p1:
    lea rdi, [rsp+31]
    mov rcx, 0
    mov rbx, 10
.l2:
    xor rdx, rdx
    div rbx
    add dl, '0'
    dec rdi
    mov [rdi], dl
    inc rcx
    test rax, rax
    jnz .l2
    mov rax, 1
    mov rsi, rdi
    mov rdx, rcx
    mov rdi, 1
    syscall
.d:
    add rsp, 32
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    leave
    ret
    times RT_PRF_SIZE - ($ - rt_prf_blob) db 0x90

; rt_prc_blob: print a complex value.
; RDI = pointer to complex variable storage (128-bit: 2 × 64-bit double).
; Prints "(real+imagj)\n".
rt_prc_blob:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push rdi
    mov r14, rdi                ; save complex ptr

    ; print "("
    lea rsi, [rel .lp]
    mov rax, 1
    mov rdi, 1
    mov rdx, 1
    syscall

    ; print real part (first 8 bytes as double)
    mov rdi, [r14]
    call rt_prf_nonnl

    ; print "+"
    lea rsi, [rel .plus]
    mov rax, 1
    mov rdi, 1
    mov rdx, 1
    syscall

    ; print imag part (next 8 bytes as double)
    mov rdi, [r14+8]
    call rt_prf_nonnl

    ; print "j)\n"
    lea rsi, [rel .suf]
    mov rax, 1
    mov rdi, 1
    mov rdx, 3
    syscall

    pop rdi
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

; rt_prf_nonnl: print a 64-bit double from RDI without trailing newline.
; Used by both rt_prf_blob and rt_prc_blob.
rt_prf_nonnl:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13
    sub rsp, 128
    lea r13, [rbp-120]
    movq xmm0, rdi
    movmskpd eax, xmm0
    test eax, 1
    jz .pnl_pos
    ; print '-'
    mov byte [r13], '-'
    mov rax, 1
    mov rdi, 1
    mov rsi, r13
    mov rdx, 1
    syscall
    mov rax, 0x7FFFFFFFFFFFFFFF
    movq xmm1, rax
    andpd xmm0, xmm1
.pnl_pos:
    cvttsd2si rbx, xmm0
    push rdi
    mov rdi, rbx
    call rt_pri_no_nl
    pop rdi
    mov byte [r13], '.'
    mov rax, 1
    mov rdi, 1
    mov rsi, r13
    mov rdx, 1
    syscall
    cvtsi2sd xmm1, rbx
    subsd xmm0, xmm1
    mov r12, 6
    mov rax, 0x4024000000000000
    movq xmm2, rax
.pnl_frac:
    mulsd xmm0, xmm2
    cvttsd2si rbx, xmm0
    add bl, '0'
    mov [r13], bl
    push rdi
    push rsi
    push rdx
    push rcx
    mov rax, 1
    mov rdi, 1
    mov rsi, r13
    mov rdx, 1
    syscall
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    sub bl, '0'
    cvtsi2sd xmm1, rbx
    subsd xmm0, xmm1
    dec r12
    jnz .pnl_frac
    add rsp, 128
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    leave
    ret

.lp:   db "("
.plus: db "+"
.suf:  db "j)", 10
    times RT_PRC_SIZE - ($ - rt_prc_blob) db 0x90

rt_sip_blob:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, [rdx]
    mov r13, [rdx+8]
    mov r8, 0x736f6d6570736575
    xor r8, r12
    mov r9, 0x646f72616e646f6d
    xor r9, r13
    mov r10, 0x6c7967656e657261
    xor r10, r12
    mov r11, 0x7465646279746573
    xor r11, r13
    mov rcx, rsi
    shr rcx, 3
    jz .final_short
.loop:
    mov rax, [rdi]
    xor r11, rax
    add r8, r9
    add r10, r11
    rol r9, 13
    rol r11, 16
    xor r9, r8
    xor r11, r10
    rol r8, 32
    add r10, r9
    add r8, r11
    rol r9, 17
    rol r11, 21
    xor r9, r10
    xor r11, r8
    rol r10, 32
    add r8, r9
    add r10, r11
    rol r9, 13
    rol r11, 16
    xor r9, r8
    xor r11, r10
    rol r8, 32
    add r10, r9
    add r8, r11
    rol r9, 17
    rol r11, 21
    xor r9, r10
    xor r11, r8
    rol r10, 32
    xor r8, rax
    add rdi, 8
    dec rcx
    jnz .loop
.final_short:
    mov rax, rsi
    shl rax, 56
    xor r11, rax
    add r8, r9
    add r10, r11
    rol r9, 13
    rol r11, 16
    xor r9, r8
    xor r11, r10
    rol r8, 32
    add r10, r9
    add r8, r11
    rol r9, 17
    rol r11, 21
    xor r9, r10
    xor r11, r8
    rol r10, 32
    add r8, r9
    add r10, r11
    rol r9, 13
    rol r11, 16
    xor r9, r8
    xor r11, r10
    rol r8, 32
    add r10, r9
    add r8, r11
    rol r9, 17
    rol r11, 21
    xor r9, r10
    xor r11, r8
    rol r10, 32
    xor r8, rax
    xor r10, 0xff
    add r8, r9
    add r10, r11
    rol r9, 13
    rol r11, 16
    xor r9, r8
    xor r11, r10
    rol r8, 32
    add r10, r9
    add r8, r11
    rol r9, 17
    rol r11, 21
    xor r9, r10
    xor r11, r8
    rol r10, 32
    add r8, r9
    add r10, r11
    rol r9, 13
    rol r11, 16
    xor r9, r8
    xor r11, r10
    rol r8, 32
    add r10, r9
    add r8, r11
    rol r9, 17
    rol r11, 21
    xor r9, r10
    xor r11, r8
    rol r10, 32
    mov rax, r8
    xor rax, r9
    xor rax, r10
    xor rax, r11
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
    times RT_SIP_SIZE - ($ - rt_sip_blob) db 0x90

rt_alc_blob:
    push rbp
    mov rbp, rsp
    mov rax, [rel .p]
    test rax, rax
    jnz .d
    mov rax, 9
    xor rdi, rdi
    mov rsi, 0x100000
    mov rdx, 3
    mov r10, 34
    mov r8, -1
    xor r9, r9
    syscall
    mov [rel .p], rax
.d:
    mov rax, [rel .p]
    add rax, [rel .o]
    add [rel .o], rdi
    leave
    ret
.p: dq 0
.o: dq 0
    times RT_ALC_SIZE - ($ - rt_alc_blob) db 0x90

rt_prq_blob:
    ret
rt_dict_new:
    push rdi
    mov rdi, 280                 ; 8-byte hidden len + 8-byte cap + 16 * 16-byte entries
    mov rax, LOAD_BASE + RT_ALC_OFFSET
    call rax
    mov qword [rax], 0           ; hidden len = 0
    add rax, 8                   ; skip hidden len
    mov qword [rax], 16          ; cap = 16
    pop rdi
    ret
rt_dict_set:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov rdi, rbp
    sub rdi, 16
    mov [rdi], r13
    mov rsi, 8
    lea rdx, [rel .k1]
    mov rax, LOAD_BASE + RT_SIP_OFFSET
    call rax
    mov rbx, [r12]
    xor rdx, rdx
    div rbx
.p1:
    mov rax, rdx
    shl rax, 4
    add rax, r12
    add rax, 8                   ; data starts at dict_ptr + 8 (cap is at dict_ptr)
    cmp qword [rax], 0
    je .new_entry
    cmp qword [rax], r13
    je .f1
    inc rdx
    cmp rdx, rbx
    jne .p1a
    xor rdx, rdx
.p1a:
    jmp .p1
.new_entry:
    inc qword [r12-8]            ; increment hidden length
.f1:
    mov [rax], r13
    mov [rax+8], r14
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
.k1: dq 0, 0
rt_dict_get:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    mov rdi, rbp
    sub rdi, 16
    mov [rdi], r13
    mov rsi, 8
    lea rdx, [rel .k2]
    mov rax, LOAD_BASE + RT_SIP_OFFSET
    call rax
    mov rbx, [r12]
    xor rdx, rdx
    div rbx
.p2:
    mov rax, rdx
    shl rax, 4
    add rax, r12
    add rax, 8
    cmp qword [rax], 0
    je .nf
    cmp qword [rax], r13
    je .f2
    inc rdx
    cmp rdx, rbx
    jne .p2a
    xor rdx, rdx
.p2a:
    jmp .p2
.f2:
    mov rax, [rax+8]
    jmp .d2
.nf:
    xor rax, rax
.d2:
    pop r13
    pop r12
    pop rbx
    leave
    ret
.k2: dq 0, 0
    times RT_PRQ_SIZE - ($ - rt_prq_blob) db 0x90

; -----------------------------------------------------------------------------
; rt_err_blob: write null-terminated string from RDI to stderr (fd=2) + newline
; RDI = pointer to null-terminated error message string
; -----------------------------------------------------------------------------
rt_err_blob:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    mov rbx, rdi            ; save string pointer
    xor rcx, rcx
.err_len:
    cmp byte [rbx+rcx], 0
    je .err_write
    inc rcx
    jmp .err_len
.err_write:
    test rcx, rcx
    jz .err_nl
    mov rax, 1              ; sys_write
    mov rdi, 2              ; fd = stderr
    mov rsi, rbx
    mov rdx, rcx
    syscall
.err_nl:
    sub rsp, 8              ; allocate 8 bytes on stack for newline byte
    mov byte [rsp], 10      ; '\n'
    mov rax, 1              ; sys_write
    mov rdi, 2              ; fd = stderr
    mov rsi, rsp
    mov rdx, 1
    syscall
    add rsp, 8              ; release stack newline slot
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    leave
    ret
    times RT_ERR_SIZE - ($ - rt_err_blob) db 0x90
