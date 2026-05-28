; -----------------------------------------------------------------------------
; Rex V5.0 ELF Headers
; Hardcoded ELF64 Header and Program Header for direct binary generation.
; -----------------------------------------------------------------------------

default rel

%include "include/rex_defs.inc"

global elf_header
global program_header
global out_name

section .data

elf_header:
    ; e_ident (16 bytes)
    db 0x7F, 'E', 'L', 'F'      ; 0..3: magic
    db 2                        ; 4: class (64-bit)
    db 1                        ; 5: data (little-endian)
    db 1                        ; 6: version
    db 0                        ; 7: OS ABI
    db 0                        ; 8: ABI version
    db 0, 0, 0, 0, 0, 0, 0      ; 9..15: padding (7 bytes to reach 16)

    dw 2                        ; 16: e_type (EXEC)
    dw 0x3E                     ; 18: e_machine (x86-64)
    dd 1                        ; 20: e_version
    dq LOAD_BASE + HEADERS_SIZE ; 24: e_entry
    dq 64                       ; 32: e_phoff
    dq 0                        ; 40: e_shoff
    dd 0                        ; 48: e_flags
    dw 64                       ; 52: e_ehsize
    dw 56                       ; 54: e_phentsize
    dw 1                        ; 56: e_phnum
    dw 0                        ; 58: e_shentsize
    dw 0                        ; 60: e_shnum
    dw 0                        ; 62: e_shstrndx

program_header:
    dd 1                        ; 0: p_type (LOAD)
    dd 7                        ; 4: p_flags (RWX)
    dq 0                        ; 8: p_offset
    dq LOAD_BASE                ; 16: p_vaddr
    dq LOAD_BASE                ; 24: p_paddr
    dq 0x80000                  ; 32: p_filesz (patched by codegen_finish)
    dq 0x80000                  ; 40: p_memsz
    dq 0x1000                   ; 48: p_align

out_name:
    db "output", 0
