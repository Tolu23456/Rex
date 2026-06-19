---
name: RexC backend build layout
description: Directory structure, Makefile conventions, include paths, and known pitfalls for the rxc/ bytecode backend.
---

## Directory name
Source files live in `rxc/` (NOT `rexc/`). The `rexc/` name was renamed because the x86-64 compiler binary is also named `rexc` — having a directory and a binary with the same name causes `ld: cannot open output file rexc: Is a directory`.

**Why:** Make/ld can't write a binary when a directory of the same name exists in the project root.

**How to apply:** Any new backend subdirectory must not share a name with any binary target in the Makefile.

## Makefile tab characters
Makefile recipe lines MUST use real tab characters. The `write` tool can emit spaces instead — use `printf '...\t...'` via bash to generate the file and guarantee tabs are literal `\t`.

## NASM include path convention
`rxc/` files are assembled with `-I include/ -I rxc/` flags. The include directives must match:
- `%include "include/rex_defs.inc"` — shared token/type constants
- `%include "rxc_defs.inc"` — RexC opcode constants (resolved via `-I rxc/`)

Do NOT write `%include "rxc/rxc_defs.inc"` inside the rxc/ files — that fails because the path is relative to the project root, not the `-I` search path.

## Duplicate label pitfall
`codegen_emit_abs_rax` was defined twice in `rxc/rxc_codegen.asm` (at the arithmetic section and again at the misc-builtins section). NASM treats this as a hard error. Audit with:
```
grep -n "^codegen_" rxc/rxc_codegen.asm | awk -F: '{print $2}' | sort | uniq -d
```

## Binary targets produced
- `rexc`      — x86-64 ELF64 native compiler
- `rexc_rxc`  — RexC bytecode backend (Rex → .rxc)
- `rex`       — CLI dispatcher (rex build / rex emit / rex run / rex test / ...)
- `rex_lsp`   — Language server

## RXC_OBJS for rexc_rxc
```
main/main.o lexer/lexer.o parser/parser.o rxc/rxc_codegen.o rxc/rxc_emit.o headers/headers.o
```
No `codegen/codegen.o` or `runtime/runtime.o` — those are x86-64-only.

## Output format verified
A correct .rxc file starts with magic bytes `52 45 58 43` ("REXC"), entry point offset = 0x14 (20), and the instruction stream begins at byte 20. Backward loop jumps (`JMP_T`/`JMP_F`/`JMP`) use negative 4-byte relative offsets — confirmed working.
