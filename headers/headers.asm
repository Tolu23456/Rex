; headers.asm - ELF64 header and program header data
; Entry point: 0x400080  (LOAD_BASE + HEADERS_SIZE)

global elf_header
global program_header
global out_name

%include "rex_defs.inc"

section .data

elf_header:
    db  0x7F, 0x45, 0x4C, 0x46      ; EI_MAG  (0x7F 'E' 'L' 'F')
    db  2                            ; EI_CLASS  64-bit
    db  1                            ; EI_DATA   little-endian
    db  1                            ; EI_VERSION
    db  0                            ; EI_OSABI  System V
    db  0                            ; EI_ABIVERSION
    times 7 db 0                     ; padding
    dw  2                            ; e_type    ET_EXEC
    dw  0x3E                         ; e_machine AMD x86-64
    dd  1                            ; e_version
    dq  LOAD_BASE + HEADERS_SIZE     ; e_entry   0x400080
    dq  0x40                         ; e_phoff   program-header offset = 64
    dq  0                            ; e_shoff   no section headers
    dd  0                            ; e_flags
    dw  64                           ; e_ehsize
    dw  56                           ; e_phentsize
    dw  1                            ; e_phnum
    dw  64                           ; e_shentsize
    dw  0                            ; e_shnum
    dw  0                            ; e_shstrndx

program_header:
    dd  1                            ; p_type   PT_LOAD
    dd  5                            ; p_flags  PF_R | PF_X
    dq  0                            ; p_offset file offset 0
    dq  LOAD_BASE                    ; p_vaddr  0x400000
    dq  LOAD_BASE                    ; p_paddr
    dq  0x1000                       ; p_filesz (4 KB max; sufficient for stage-0)
    dq  0x1000                       ; p_memsz
    dq  0x1000                       ; p_align

out_name:
    db  "output", 0
