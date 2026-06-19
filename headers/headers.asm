default rel
%include "include/rex_defs.inc"
global elf_header, program_header, out_name
section .data
elf_header:
    db 0x7F,'E','L','F',2,1,1,0,0,0,0,0,0,0,0,0
    dw 2
    dw 0x3E
    dd 1
    dq LOAD_BASE+HEADERS_SIZE
    dq 64
    dq 0
    dd 0
    dw 64
    dw 56
    dw 2           ; SEC-04/05 fix: e_phnum = 2 (PT_LOAD + PT_GNU_STACK)
    dw 0
    dw 0
    dw 0
program_header:
    dd 1
    dd 7
    dq 0
    dq LOAD_BASE
    dq LOAD_BASE
    dq 0x80000
    dq 0x80000
    dq 0x1000
; SEC-04/05 fix: PT_GNU_STACK with no-execute flag (PF_R|PF_W only)
gnu_stack_header:
    dd 0x6474e551   ; p_type = PT_GNU_STACK
    dd 6            ; p_flags = PF_R|PF_W (no PF_X — disables exec stack)
    dq 0            ; p_offset
    dq 0            ; p_vaddr
    dq 0            ; p_paddr
    dq 0            ; p_filesz
    dq 0            ; p_memsz
    dq 0x10         ; p_align
out_name: db "output",0
