; -----------------------------------------------------------------------------
; Rex V5.0 Code Generator
; Emits x86_64 machine code into the output buffer.
; Responsible for ELF construction and binary blob integration.
; -----------------------------------------------------------------------------

default rel

%include "include/rex_defs.inc"

global codegen_write_headers
global codegen_init
global codegen_finish
global out_buffer
global out_idx

global codegen_output_const
global codegen_output_typed
global codegen_patch_jump
global codegen_save_chain_base
global codegen_emit_jmp_end
global codegen_patch_chain_end
global codegen_begin_protos
global codegen_end_protos
global codegen_emit_for_start
global codegen_emit_for_end
global codegen_emit_while_start
global codegen_emit_while_end
global codegen_emit_break
global codegen_patch_breaks
global codegen_emit_ret
global codegen_emit_mov_eax_imm32
global codegen_emit_call_prot
global codegen_emit_assign_var
global codegen_emit_cmp_var_jne
global codegen_emit_unknown_bool
global codegen_emit_mm_switch
global codegen_emit_float_op
global codegen_emit_complex_op
global codegen_output_float_const

; Expression emission helpers (called by parser's expression functions)
global emit_b
global emit_d
global emit_q
global get_var_va
global codegen_output_rax_int
global codegen_output_rax_float
global codegen_emit_store_rax_var

; Externs from Headers & Runtime
extern elf_header
extern program_header
extern rt_pri_blob
extern rt_prs_blob
extern rt_prb_blob
extern rt_prf_blob
extern rt_prc_blob
extern rt_sip_blob
extern rt_alc_blob
extern rt_prq_blob

section .bss
    out_buffer:       resb 131072    ; Buffer for generated ELF binary
    out_idx:          resq 1         ; Current pointer in out_buffer
    jump_patch_stack: resq 32        ; Stack for patching JNE targets
    jump_patch_depth: resq 1
    end_jump_stack:   resq 32        ; Stack for 'if' chain exit jumps
    end_jump_depth:   resq 1
    chain_base_stack: resq 32        ; Nesting tracker for 'if' chains
    chain_base_depth: resq 1
    break_jump_stack: resq 32        ; Stack for 'stop' jumps
    break_jump_depth: resq 1
    break_base_stack: resq 32        ; Nesting tracker for loops
    break_base_depth: resq 1
    prot_jmp_idx:     resq 1         ; Offset for jumping over protocol definitions
    prot_jmp_live:    resb 1         ; Flag: Is protocol jump active?

section .text

; -----------------------------------------------------------------------------
; emit_b / emit_d / emit_q
; Emit byte, dword, or qword to the output buffer.
; -----------------------------------------------------------------------------
emit_b:
    push rbx
    push rcx
    mov rcx, [out_idx]
    lea rbx, [out_buffer]
    mov [rbx+rcx], al
    inc qword [out_idx]
    pop rcx
    pop rbx
    ret

emit_d:
    push rbx
    push rcx
    mov rcx, [out_idx]
    lea rbx, [out_buffer]
    mov [rbx+rcx], eax
    add qword [out_idx], 4
    pop rcx
    pop rbx
    ret

emit_q:
    push rbx
    push rcx
    mov rcx, [out_idx]
    lea rbx, [out_buffer]
    mov [rbx+rcx], rax
    add qword [out_idx], 8
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; emit_blob
; Copies a runtime blob into the output buffer.
; RSI = src, RCX = size
; -----------------------------------------------------------------------------
emit_blob:
    push rdi
    push rsi
    push rcx
    push rdx

    mov rdx, [out_idx]
    lea rdi, [out_buffer]
    add rdi, rdx
    cld
    rep movsb

    pop rdx
    pop rcx
    pop rsi
    pop rdi
    add qword [out_idx], rcx
    ret

; -----------------------------------------------------------------------------
; get_var_va
; Returns the Virtual Address for a variable index.
; Input: RDI = index
; Output: RAX = VA
; -----------------------------------------------------------------------------
get_var_va:
    push rbx
    mov rax, rdi
    shl rax, 6                  ; 64 bytes per entry
    add rax, VAR_STORAGE_BASE
    pop rbx
    ret

; -----------------------------------------------------------------------------
; codegen_write_headers
; Writes initial ELF and Program headers.
; -----------------------------------------------------------------------------
codegen_write_headers:
    push rbp
    mov rbp, rsp
    mov qword [out_idx], 0

    ; ELF Header (64 bytes)
    lea rsi, [elf_header]
    lea rdi, [out_buffer]
    mov rcx, 64
    cld
    rep movsb

    ; Program Header (56 bytes)
    lea rsi, [program_header]
    mov rcx, 56
    rep movsb

    mov qword [out_idx], 120    ; Total header size
    leave
    ret

; -----------------------------------------------------------------------------
; codegen_init
; Emits the runtime skip jump and integrates all runtime blobs.
; -----------------------------------------------------------------------------
codegen_init:
    push rbp
    mov rbp, rsp
    ; E9 <offset> - Jump over runtime to user code
    mov al, 0xE9
    call emit_b
    mov eax, RT_TOTAL_SIZE
    call emit_d

    ; Emit standard runtime blobs
    lea rsi, [rt_pri_blob]
    mov rcx, RT_PRI_SIZE
    call emit_blob

    lea rsi, [rt_prs_blob]
    mov rcx, RT_PRS_SIZE
    call emit_blob

    lea rsi, [rt_prb_blob]
    mov rcx, RT_PRB_SIZE
    call emit_blob

    lea rsi, [rt_prf_blob]
    mov rcx, RT_PRF_SIZE
    call emit_blob

    lea rsi, [rt_prc_blob]
    mov rcx, RT_PRC_SIZE
    call emit_blob

    lea rsi, [rt_sip_blob]
    mov rcx, RT_SIP_SIZE
    call emit_blob

    lea rsi, [rt_alc_blob]
    mov rcx, RT_ALC_SIZE
    call emit_blob

    lea rsi, [rt_prq_blob]
    mov rcx, RT_PRQ_SIZE
    call emit_blob

    leave
    ret

; -----------------------------------------------------------------------------
; codegen_output_const
; Emits code to print a literal integer.
; -----------------------------------------------------------------------------
codegen_output_const:
    push rbp
    mov rbp, rsp
    ; BF <imm32> - mov edi, const
    mov al, 0xBF
    call emit_b
    mov eax, edi
    call emit_d

    ; E8 <offset> - call rt_pri
    mov al, 0xE8
    call emit_b
    mov rax, LOAD_BASE + RT_PRI_OFFSET
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d
    leave
    ret

; -----------------------------------------------------------------------------
; codegen_output_typed
; Emits code to print a variable based on its type.
; RDI = var index, RSI = type
; -----------------------------------------------------------------------------
codegen_output_typed:
    push rbp
    mov rbp, rsp
    push rsi
    push rdi

    ; 48 8B 3C 25 <addr32> - mov rdi, [addr]
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x3C
    call emit_b
    mov al, 0x25
    call emit_b

    pop rdi
    push rdi
    call get_var_va
    call emit_d

    pop rdi
    pop rsi

    ; E8 <offset> - call appropriate printer
    mov al, 0xE8
    call emit_b

    mov rax, RT_PRI_OFFSET      ; Default INT
    cmp sil, TYPE_STR
    je .str
    cmp sil, TYPE_BOOL
    je .bool
    cmp sil, TYPE_FLOAT
    je .float
    cmp sil, TYPE_COMPLEX
    je .complex
    jmp .do_call

.str:     mov rax, RT_PRS_OFFSET; jmp .do_call
.bool:    mov rax, RT_PRB_OFFSET; jmp .do_call
.float:   mov rax, RT_PRF_OFFSET; jmp .do_call
.complex: mov rax, RT_PRC_OFFSET

.do_call:
    add rax, LOAD_BASE
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d
    leave
    ret

; -----------------------------------------------------------------------------
; codegen_emit_assign_var
; Emits assignment code.
; RDI = index, RSI = value
; -----------------------------------------------------------------------------
codegen_emit_assign_var:
    push rbp
    mov rbp, rsp
    push rdi
    ; 48 B8 <imm64> - mov rax, value
    mov al, 0x48
    call emit_b
    mov al, 0xB8
    call emit_b
    mov rax, rsi
    call emit_q

    ; 48 89 04 25 <addr32> - mov [addr], rax
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b

    pop rdi
    call get_var_va
    call emit_d
    leave
    ret

; -----------------------------------------------------------------------------
; codegen_emit_unknown_bool
; Emits hardware random choice for 'unknown' type.
; -----------------------------------------------------------------------------
codegen_emit_unknown_bool:
    push rbp
    mov rbp, rsp
    push rdi
    ; 0F C7 F0 - rdrand eax
    mov al, 0x0F
    call emit_b
    mov al, 0xC7
    call emit_b
    mov al, 0xF0
    call emit_b

    ; 83 E0 01 - and eax, 1
    mov al, 0x83
    call emit_b
    mov al, 0xE0
    call emit_b
    mov al, 0x01
    call emit_b

    ; 89 04 25 <addr32> - mov [addr], eax
    mov al, 0x89
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b

    pop rdi
    call get_var_va
    call emit_d
    leave
    ret

; -----------------------------------------------------------------------------
; codegen_emit_cmp_var_jne
; Emits comparison against variable and conditional jump.
; -----------------------------------------------------------------------------
codegen_emit_cmp_var_jne:
    push rbp
    mov rbp, rsp
    push rsi
    push rdi

    ; 48 81 3C 25 <addr32> <imm32> - cmp qword [addr], val
    mov al, 0x48
    call emit_b
    mov al, 0x81
    call emit_b
    mov al, 0x3C
    call emit_b
    mov al, 0x25
    call emit_b

    pop rdi
    call get_var_va
    call emit_d

    pop rsi
    mov eax, esi
    call emit_d

    ; 0F 85 <offset32> - jne
    mov al, 0x0F
    call emit_b
    mov al, 0x85
    call emit_b

    mov rax, [out_idx]
    mov rbx, [jump_patch_depth]
    lea rcx, [jump_patch_stack]
    mov [rcx+rbx*8], rax
    inc qword [jump_patch_depth]

    xor eax, eax
    call emit_d
    leave
    ret

; -----------------------------------------------------------------------------
; codegen_patch_jump
; Patches the most recent conditional jump to point here.
; -----------------------------------------------------------------------------
codegen_patch_jump:
    push rbp
    mov rbp, rsp
    dec qword [jump_patch_depth]
    mov rbx, [jump_patch_depth]
    lea rcx, [jump_patch_stack]
    mov rdx, [rcx+rbx*8]        ; address to patch

    mov rax, [out_idx]
    sub rax, rdx
    sub rax, 4                  ; Relative offset

    lea rcx, [out_buffer]
    mov [rcx+rdx], eax
    leave
    ret

; -----------------------------------------------------------------------------
; Flow Control Helpers (Chain and Break stacks)
; -----------------------------------------------------------------------------
codegen_save_chain_base:
    mov rax, [end_jump_depth]
    mov rbx, [chain_base_depth]
    lea rcx, [chain_base_stack]
    mov [rcx+rbx*8], rax
    inc qword [chain_base_depth]
    ret

codegen_emit_jmp_end:
    push rbp
    mov rbp, rsp
    ; E9 <imm32>
    mov al, 0xE9
    call emit_b

    mov rax, [out_idx]
    mov rbx, [end_jump_depth]
    lea rcx, [end_jump_stack]
    mov [rcx+rbx*8], rax
    inc qword [end_jump_depth]

    xor eax, eax
    call emit_d
    leave
    ret

codegen_patch_chain_end:
    push rbp
    mov rbp, rsp
    dec qword [chain_base_depth]
    mov rbx, [chain_base_depth]
    lea rcx, [chain_base_stack]
    mov rsi, [rcx+rbx*8]        ; Starting index for this chain

.patch_loop:
    cmp rsi, [end_jump_depth]
    jae .patch_done

    lea rcx, [end_jump_stack]
    mov rdx, [rcx+rsi*8]

    mov rax, [out_idx]
    sub rax, rdx
    sub rax, 4

    lea rcx, [out_buffer]
    mov [rcx+rdx], eax

    inc rsi
    jmp .patch_loop

.patch_done:
    mov [end_jump_depth], rsi
    leave
    ret

; -----------------------------------------------------------------------------
; Protocols and Function Calls
; -----------------------------------------------------------------------------
codegen_begin_protos:
    cmp byte [prot_jmp_live], 0
    jne .skip

    mov al, 0xE9
    call emit_b
    mov rax, [out_idx]
    mov [prot_jmp_idx], rax
    xor eax, eax
    call emit_d
    mov byte [prot_jmp_live], 1
.skip:
    ret

codegen_end_protos:
    push rbp
    mov rbp, rsp
    cmp byte [prot_jmp_live], 0
    je .skip

    mov rdx, [prot_jmp_idx]
    mov rax, [out_idx]
    sub rax, rdx
    sub rax, 4

    lea rcx, [out_buffer]
    mov [rcx+rdx], eax
    mov byte [prot_jmp_live], 0
.skip:
    leave
    ret

codegen_emit_ret:
    mov al, 0xC3
    call emit_b
    ret

codegen_emit_mov_eax_imm32:
    mov al, 0xB8
    call emit_b
    mov eax, edi
    call emit_d
    ret

codegen_emit_call_prot:
    push rbp
    mov rbp, rsp
    mov al, 0xE8
    call emit_b
    mov rax, rdi
    add rax, LOAD_BASE
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d
    leave
    ret

; -----------------------------------------------------------------------------
; Memory Allocator Context Switch
; EDI = mode (0=arena, 1=pool)
; -----------------------------------------------------------------------------
codegen_emit_mm_switch:
    push rbp
    mov rbp, rsp
    ; 48 C7 05 <offset32> <imm32> - mov [rt_alc.mode], edi
    mov al, 0x48
    call emit_b
    mov al, 0xC7
    call emit_b
    mov al, 0x05
    call emit_b

    mov rax, LOAD_BASE + RT_ALC_OFFSET + 4096 - 8 ; Address of .mode in rt_alc
    mov rdx, [out_idx]
    add rdx, 4
    sub rax, rdx
    call emit_d

    mov eax, edi
    call emit_d
    leave
    ret

; -----------------------------------------------------------------------------
; codegen_emit_for_start / end
; -----------------------------------------------------------------------------
codegen_emit_for_start:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    mov r12, rdi                ; index
    mov r13, rdx                ; end val

    ; mov [var], start
    mov al, 0x48
    call emit_b
    mov al, 0xB8
    call emit_b
    mov rax, rsi
    call emit_q
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    mov rdi, r12
    call get_var_va
    call emit_d

    mov rbx, [out_idx]          ; Save loop top

    ; cmp [var], end
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    mov rdi, r12
    call get_var_va
    call emit_d

    mov al, 0x48
    call emit_b
    mov al, 0x3D
    call emit_b
    mov rax, r13
    call emit_d

    ; jge break
    mov al, 0x0F
    call emit_b
    mov al, 0x8D
    call emit_b
    mov rax, [out_idx]
    mov r13, [jump_patch_depth]
    lea rcx, [jump_patch_stack]
    mov [rcx+r13*8], rax
    inc qword [jump_patch_depth]
    xor eax, eax
    call emit_d

    mov rax, rbx                ; Return loop top
    pop r13
    pop r12
    pop rbx
    leave
    ret

codegen_emit_for_end:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    mov r12, rdi                ; top VA
    mov r13, rsi                ; index

    ; inc [var]
    mov al, 0x48
    call emit_b
    mov al, 0x8B
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    mov rdi, r13
    call get_var_va
    call emit_d

    mov al, 0x48
    call emit_b
    mov al, 0xFF
    call emit_b
    mov al, 0xC0
    call emit_b

    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    mov rdi, r13
    call get_var_va
    call emit_d

    ; jmp loop_top
    mov al, 0xE9
    call emit_b
    mov rax, r12
    add rax, LOAD_BASE
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d

    call codegen_patch_jump
    pop r13
    pop r12
    pop rbx
    leave
    ret

; -----------------------------------------------------------------------------
; codegen_finish
; Emits sys_exit and finalizes ELF headers.
; -----------------------------------------------------------------------------
codegen_finish:
    push rbp
    mov rbp, rsp
    ; mov rax, 60 (sys_exit)
    mov al, 0x48
    call emit_b
    mov al, 0xC7
    call emit_b
    mov al, 0xC0
    call emit_b
    mov eax, 60
    call emit_d

    ; xor rdi, rdi
    mov al, 0x48
    call emit_b
    mov al, 0x31
    call emit_b
    mov al, 0xFF
    call emit_b

    ; syscall
    mov al, 0x0F
    call emit_b
    mov al, 0x05
    call emit_b

    ; Patch Program Header: p_memsz = out_idx
    mov rax, [out_idx]
    lea rcx, [out_buffer]
    mov [rcx + 64 + 32], rax    ; offset 96: p_filesz
    mov qword [rcx + 64 + 40], 0x80000 ; p_memsz (static for now)
    leave
    ret

; -----------------------------------------------------------------------------
; Float Arithmetic (SSE2)
; RDI = dest index, RSI = src1 index, RDX = src2 index, RCX = op (0:+, 1:-, 2:*, 3:/)
; -----------------------------------------------------------------------------
codegen_emit_float_op:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    ; 1. Load src1 into XMM0
    ; F2 0F 10 04 25 <addr32> - movsd xmm0, [addr]
    mov al, 0xF2
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0x10
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    mov rdi, rsi
    call get_var_va
    call emit_d

    ; 2. Load src2 into XMM1
    ; F2 0F 10 0C 25 <addr32> - movsd xmm1, [addr]
    mov al, 0xF2
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0x10
    call emit_b
    mov al, 0x0C
    call emit_b
    mov al, 0x25
    call emit_b
    mov rdi, rdx
    call get_var_va
    call emit_d

    ; 3. Perform Op
    mov rax, [rbp-16]           ; op (rcx)
    cmp rax, 0
    je .f_add
    cmp rax, 1
    je .f_sub
    cmp rax, 2
    je .f_mul
    jmp .f_div

.f_add:
    ; F2 0F 58 C1 - addsd xmm0, xmm1
    mov al, 0xF2; call emit_b; mov al, 0x0F; call emit_b; mov al, 0x58; call emit_b; mov al, 0xC1; call emit_b
    jmp .f_store
.f_sub:
    ; F2 0F 5C C1 - subsd xmm0, xmm1
    mov al, 0xF2; call emit_b; mov al, 0x0F; call emit_b; mov al, 0x5C; call emit_b; mov al, 0xC1; call emit_b
    jmp .f_store
.f_mul:
    ; F2 0F 59 C1 - mulsd xmm0, xmm1
    mov al, 0xF2; call emit_b; mov al, 0x0F; call emit_b; mov al, 0x59; call emit_b; mov al, 0xC1; call emit_b
    jmp .f_store
.f_div:
    ; F2 0F 5E C1 - divsd xmm0, xmm1
    mov al, 0xF2; call emit_b; mov al, 0x0F; call emit_b; mov al, 0x5E; call emit_b; mov al, 0xC1; call emit_b

.f_store:
    ; 4. Store XMM0 to dest
    ; F2 0F 11 04 25 <addr32> - movsd [addr], xmm0
    mov al, 0xF2
    call emit_b
    mov al, 0x0F
    call emit_b
    mov al, 0x11
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    mov rdi, [rbp-40]           ; original rdi (dest index)
    call get_var_va
    call emit_d

    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    leave
    ret

; -----------------------------------------------------------------------------
; Complex Arithmetic (SSE2 Packed)
; RDI = dest index, RSI = src1 index, RDX = src2 index, RCX = op (0:+, 1:-)
; -----------------------------------------------------------------------------
codegen_emit_complex_op:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    ; 1. Load src1 (128-bit) into XMM0
    ; 66 0F 28 04 25 <addr32> - movapd xmm0, [addr]
    mov al, 0x66; call emit_b; mov al, 0x0F; call emit_b; mov al, 0x28; call emit_b; mov al, 0x04; call emit_b; mov al, 0x25; call emit_b
    mov rdi, rsi; call get_var_va; call emit_d

    ; 2. Load src2 (128-bit) into XMM1
    mov al, 0x66; call emit_b; mov al, 0x0F; call emit_b; mov al, 0x28; call emit_b; mov al, 0x0C; call emit_b; mov al, 0x25; call emit_b
    mov rdi, rdx; call get_var_va; call emit_d

    ; 3. Perform Op
    mov rax, [rbp-16]
    cmp rax, 0
    je .c_add
    ; 66 0F 5C C1 - subpd xmm0, xmm1
    mov al, 0x66; call emit_b; mov al, 0x0F; call emit_b; mov al, 0x5C; call emit_b; mov al, 0xC1; call emit_b
    jmp .c_store
.c_add:
    ; 66 0F 58 C1 - addpd xmm0, xmm1
    mov al, 0x66; call emit_b; mov al, 0x0F; call emit_b; mov al, 0x58; call emit_b; mov al, 0xC1; call emit_b

.c_store:
    ; 4. Store XMM0 to dest (128-bit)
    ; 66 0F 29 04 25 <addr32> - movapd [addr], xmm0
    mov al, 0x66; call emit_b; mov al, 0x0F; call emit_b; mov al, 0x29; call emit_b; mov al, 0x04; call emit_b; mov al, 0x25; call emit_b
    mov rdi, [rbp-40]
    call get_var_va
    call emit_d

    pop rdi; pop rsi; pop rdx; pop rcx; pop rbx
    leave
    ret

; -----------------------------------------------------------------------------
; codegen_emit_while_start
; -----------------------------------------------------------------------------
codegen_emit_while_start:
    push rbp
    mov rbp, rsp
    push r12
    mov r12, [out_idx]          ; loop top

    ; Logic moved to parser calling emit_cmp_var_jne

    mov rax, r12
    pop r12
    leave
    ret

; -----------------------------------------------------------------------------
; codegen_emit_while_end
; RDI = loop top VA
; -----------------------------------------------------------------------------
codegen_emit_while_end:
    push rbp
    mov rbp, rsp
    ; E9 <offset>
    mov al, 0xE9
    call emit_b
    mov rax, rdi
    add rax, LOAD_BASE
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d

    call codegen_patch_jump     ; patch the while condition failure jump
    call codegen_patch_breaks   ; patch any stop/break jumps
    leave
    ret

; -----------------------------------------------------------------------------
; codegen_emit_break
; -----------------------------------------------------------------------------
codegen_emit_break:
    push rbp
    mov rbp, rsp
    ; E9 <offset>
    mov al, 0xE9
    call emit_b

    mov rax, [out_idx]
    mov rbx, [break_jump_depth]
    lea rcx, [break_jump_stack]
    mov [rcx+rbx*8], rax
    inc qword [break_jump_depth]

    xor eax, eax
    call emit_d
    leave
    ret

; -----------------------------------------------------------------------------
; codegen_patch_breaks
; -----------------------------------------------------------------------------
codegen_patch_breaks:
    push rbp
    mov rbp, rsp
    dec qword [break_base_depth]
    mov rbx, [break_base_depth]
    lea rcx, [break_base_stack]
    mov rsi, [rcx+rbx*8]

.l:
    cmp rsi, [break_jump_depth]
    jae .done

    lea rcx, [break_jump_stack]
    mov rdx, [rcx+rsi*8]

    mov rax, [out_idx]
    sub rax, rdx
    sub rax, 4

    lea rcx, [out_buffer]
    mov [rcx+rdx], eax
    inc rsi
    jmp .l

.done:
    mov [break_jump_depth], rsi
    leave
    ret

; -----------------------------------------------------------------------------
; codegen_output_float_const
; RDI = float bits
; -----------------------------------------------------------------------------
codegen_output_float_const:
    push rbp
    mov rbp, rsp

    ; 48 BF <imm64> - mov rdi, const
    mov al, 0x48
    call emit_b
    mov al, 0xBF
    call emit_b
    mov rax, rdi
    call emit_q

    ; E8 <offset> - call rt_prf
    mov al, 0xE8
    call emit_b
    mov rax, LOAD_BASE + RT_PRF_OFFSET
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d

    leave
    ret

; -----------------------------------------------------------------------------
; codegen_output_rax_int
; Emits runtime code to print RAX as an integer.
; Generates: mov rdi, rax  +  call rt_pri
; -----------------------------------------------------------------------------
codegen_output_rax_int:
    push rbp
    mov rbp, rsp
    ; emit: mov rdi, rax  (48 89 C7)
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC7
    call emit_b
    ; emit: call rt_pri  (E8 <rel32>)
    mov al, 0xE8
    call emit_b
    mov rax, LOAD_BASE + RT_PRI_OFFSET
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d
    leave
    ret

; -----------------------------------------------------------------------------
; codegen_output_rax_float
; Emits runtime code to print RAX as a float (bits -> rdi -> rt_prf).
; Generates: mov rdi, rax  +  call rt_prf
; -----------------------------------------------------------------------------
codegen_output_rax_float:
    push rbp
    mov rbp, rsp
    ; emit: mov rdi, rax  (48 89 C7)
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0xC7
    call emit_b
    ; emit: call rt_prf  (E8 <rel32>)
    mov al, 0xE8
    call emit_b
    mov rax, LOAD_BASE + RT_PRF_OFFSET
    mov rdx, [out_idx]
    add rdx, 4
    add rdx, LOAD_BASE
    sub rax, rdx
    call emit_d
    leave
    ret

; -----------------------------------------------------------------------------
; codegen_emit_store_rax_var
; Emits: mov [var_addr], rax  using the variable's storage address.
; Input: RDI = variable index
; -----------------------------------------------------------------------------
codegen_emit_store_rax_var:
    push rbp
    mov rbp, rsp
    push rdi
    ; emit: mov [addr32], rax  (48 89 04 25 <addr32>)
    mov al, 0x48
    call emit_b
    mov al, 0x89
    call emit_b
    mov al, 0x04
    call emit_b
    mov al, 0x25
    call emit_b
    pop rdi
    call get_var_va
    call emit_d
    leave
    ret
