; Rex Common Definitions
; This file contains constants and macros used throughout the compiler and runtime.

%ifndef COMMON_INC
%define COMMON_INC

; System Calls
%define SYS_READ    0
%define SYS_WRITE   1
%define SYS_OPEN    2
%define SYS_CLOSE   3
%define SYS_STAT    4
%define SYS_MMAP    9
%define SYS_MUNMAP  11
%define SYS_EXIT    60
%define SYS_GETRANDOM 318

; File Constants
%define O_RDONLY    0
%define O_WRONLY    1
%define O_RDWR      2
%define O_CREAT     64
%define O_TRUNC     512

; Standard FDs
%define STDIN       0
%define STDOUT      1
%define STDERR      2

; Memory Constants
%define PROT_READ   0x1
%define PROT_WRITE  0x2
%define MAP_PRIVATE 0x02
%define MAP_ANONYMOUS 0x20

; ELF Constants
%define ELF_CLASS64 2
%define ELF_DATA2LSB 1
%define ELF_V_CURRENT 1
%define ELF_OSABI_SYSV 0
%define ET_EXEC 2
%define EM_X86_64 62

%endif
