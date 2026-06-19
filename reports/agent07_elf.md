# Agent 07: ELF64 Header & Segment Layout Analysis

## Executive Summary
The Rex compiler's ELF64 generation is functional but follows a "minimalist" approach that deviates from standard modern ELF practices. While it produces runnable binaries on Linux x86-64, it lacks several security features (like non-executable stack) and modern segment organization (like separate `.rodata` and `.text` segments). The single-segment approach simplifies implementation but sacrifices security and standard compliance.

## ELF64 Field Verification

The current ELF header in `headers/headers.asm`:

```nasm
elf_header:
    db 0x7F,'E','L','F',2,1,1,0,0,0,0,0,0,0,0,0 ; e_ident: 64-bit, little-endian, version 1
    dw 2                                       ; e_type: ET_EXEC
    dw 0x3E                                    ; e_machine: EM_X86_64
    dd 1                                       ; e_version: 1
    dq LOAD_BASE+HEADERS_SIZE                  ; e_entry: 0x400078
    dq 64                                      ; e_phoff: 64 bytes
    dq 0                                       ; e_shoff: No section headers
    dd 0                                       ; e_flags: 0
    dw 64                                      ; e_ehsize: 64 bytes
    dw 56                                      ; e_phentsize: 56 bytes
    dw 1                                       ; e_phnum: 1 segment
    dw 0                                       ; e_shentsize: 0
    dw 0                                       ; e_shnum: 0
    dw 0                                       ; e_shstrndx: 0
```

### Analysis of Fields:
1.  **e_entry**: Set to `LOAD_BASE+HEADERS_SIZE` (0x400078). This assumes the code starts exactly after the headers (64 + 56 = 120 bytes). However, `codegen_init` emits a 5-byte `JMP` over the runtime blobs. This is correct as the entry point should be at the start of the executable code.
2.  **e_phoff**: Correct at 64 bytes (immediately following the ELF header).
3.  **e_shoff**: 0. Standard for "no section headers", which is valid for an executable but makes debugging/inspection with `readelf` or `objdump` less useful.
4.  **e_phentsize**: 56 bytes. Correct for ELF64.
5.  **e_phnum**: 1. Only one segment is used for everything.

## Program Header Analysis

```nasm
program_header:
    dd 1                                       ; p_type: PT_LOAD
    dd 7                                       ; p_flags: RWX (Read/Write/Execute)
    dq 0                                       ; p_offset: 0 (start of file)
    dq LOAD_BASE                               ; p_vaddr: 0x400000
    dq LOAD_BASE                               ; p_paddr: 0x400000
    dq 0x80000                                 ; p_filesz: Patched later
    dq 0x80000                                 ; p_memsz: Patched later
    dq 0x1000                                  ; p_align: 4KB alignment
```

### Issues Found:
1.  **RWX Permissions**: The single segment is marked `p_flags = 7` (PF_R | PF_W | PF_X). This is a security risk as it allows self-modifying code and makes code-injection attacks easier. Standard practice is to have a `PT_LOAD` for code (R-X) and another for data (RW-).
2.  **p_filesz vs p_memsz**: In `codegen_finish`, `p_filesz` is patched with `out_idx` (total file size), and `p_memsz` is patched with `out_idx + 0x46000` to account for the BSS area (variable storage, memoization tables). This is correct for static allocation.
3.  **Alignment**: `p_align` is 0x1000 (4KB). Since `p_offset` is 0 and `p_vaddr` is 0x400000, `p_vaddr % p_align == p_offset % p_align` holds (0 == 0).

## Recommendations

### 1. PT_GNU_STACK Segment
Modern Linux systems expect a `PT_GNU_STACK` segment to determine if the stack should be executable. Without it, the kernel might default to an executable stack.
**Proposal**: Add a second program header:
```nasm
    dd 0x6474e551                              ; p_type: PT_GNU_STACK
    dd 6                                       ; p_flags: RW (No Execute)
    dq 0, 0, 0, 0, 0                           ; rest zero
```
And increment `e_phnum` to 2.

### 2. Segment Splitting (Optional but Recommended)
Split the output into two segments:
- **Segment 1 (R-X)**: Contains ELF headers, runtime blobs, and generated code.
- **Segment 2 (RW-)**: Contains the BSS area.
Currently, the BSS area starts at a fixed offset `VAR_STORAGE_BASE` (4456448), which is about 262KB after `LOAD_BASE`. This "gap" is handled by the single large segment's `p_memsz`.

### 3. Load Address Correctness
The `LOAD_BASE` is 0x400000. This is the traditional x86-64 load address. While fine for static binaries, modern systems prefer Position Independent Executables (PIE), which require `ET_DYN` and base 0. However, for a custom compiler, `ET_EXEC` at 0x400000 is perfectly valid and standard.

### 4. .rodata Segment
String literals are currently emitted into the same buffer as code. Adding a `.rodata` segment would allow these literals to be mapped as Read-Only, preventing accidental or malicious writes to string constants. This would require the parser and codegen to track a separate offset for data.

## Bug/Compliance Audit
- **Spec Violation**: None strictly, but "best practice" violations are present (RWX segment, missing PT_GNU_STACK).
- **Non-Standard Kernels**: The minimalist header might be rejected by some strict loaders that expect section headers or specific segment orders, though it works fine on standard Linux.
- **p_align**: 0x1000 is standard. Increasing it to 2MB might improve performance on some systems due to huge pages, but is not necessary.

## Proposed NASM Changes for `headers.asm`

```nasm
; Update e_phnum to 2
; Add PT_GNU_STACK header
program_header:
    ; Segment 1: PT_LOAD
    dd 1
    dd 7 ; Still RWX for now due to single-pass nature
    dq 0
    dq LOAD_BASE
    dq LOAD_BASE
    dq 0x80000
    dq 0x80000
    dq 0x1000
    
    ; Segment 2: PT_GNU_STACK
    dd 0x6474e551
    dd 6 ; PF_R | PF_W
    dq 0
    dq 0
    dq 0
    dq 0
    dq 0
    dq 0
```
Note: Adding a segment header requires adjusting `HEADERS_SIZE` and `e_entry` in `rex_defs.inc`.
