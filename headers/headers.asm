default rel
%include "include/rex_defs.inc"
global elf_header, program_header, out_name
section .data
elf_header:
    db 0x7F,'E','L','F',2,1,1,0,0,0,0,0,0,0,0,0
    dw 2; dw 0x3E; dd 1; dq LOAD_BASE+HEADERS_SIZE; dq 64; dq 0; dd 0
    dw 64; dw 56; dw 1; dw 0; dw 0; dw 0
program_header:
    dd 1; dd 7; dq 0; dq LOAD_BASE; dq LOAD_BASE; dq 0x80000; dq 0x80000; dq 0x1000
out_name: db "output",0
