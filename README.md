# Rex Bootstrap Compiler — Stage 0

A hand-written, self-contained x86-64 ELF compiler for the **Rex V4.0** language,
built entirely in NASM assembly with **zero external dependencies**.

---

## Project structure

```
.
├── include/
│   └── rex_defs.inc      # Shared constants: token IDs, VAR_ENTRY_SIZE, ELF offsets
│
├── main/
│   └── main.asm          # Entry point: arg parsing, file I/O, compilation loop
│
├── lexer/
│   └── lexer.asm         # Tokeniser: keywords, identifiers, integers, indent tracking
│
├── parser/
│   └── parser.asm        # Recursive-descent parser + variable table (mutability rules)
│
├── codegen/
│   └── codegen.asm       # Code emitter: write x86-64 machine code into out_buffer
│
├── headers/
│   └── headers.asm       # ELF64 header + program header writer
│
├── runtime/
│   └── runtime.asm       # Inline runtime blobs: rt_pri (print integer) + rt_prs (print string)
│
├── tests/
│   └── test.rex          # Canonical V4.0 test: `int x = 42` / `output x`
│
├── Makefile              # Build all modules; `make test` runs the full pipeline
├── build.sh              # Shell equivalent of `make test` (used by Replit workflow)
└── rexc.asm              # Original monolithic compiler (kept for reference)
```

---

## Rex V4.0 language — Stage 0 subset

| Syntax | Meaning |
|---|---|
| `int x` | Declare a **mutable** variable `x` (uninitialized) |
| `int x = 42` | Declare an **immutable** constant `x` initialized to `42` |
| `:x = 10` | Assign `10` to the **mutable** variable `x` (error if `x` is const) |
| `output x` | Print the value of `x` followed by a newline |

---

## Building

### Prerequisites

```bash
nasm     # assembler
ld       # GNU linker (binutils)
```

### Build and test

```bash
# Full pipeline: assemble → link → compile test.rex → run output
bash build.sh

# Or use make
make          # produces ./rexc
make test     # compiles tests/test.rex and runs ./output
make clean    # remove object files, rexc, and output
```

---

## How it works

```
source.rex
    │
    ▼
[ lexer ]  →  token stream  (TOK_TYPE_INT, TOK_IDENT, TOK_ASSIGN, …)
    │
    ▼
[ parser ]  →  variable table  (name, value, is_const, is_initialized)
    │
    ▼
[ codegen ]  →  out_buffer  (raw x86-64 machine bytes)
    │
    ▼
[ headers ]  +  [ runtime ]  →  complete ELF64 binary
    │
    ▼
  ./output   →  prints result, exits 0
```

### Binary layout (file offsets)

| Offset | Size | Content |
|---|---|---|
| 0 | 64 B | ELF64 header |
| 64 | 56 B | Program header (LOAD, RWX) |
| 120 | 8 B | Padding to 128 B |
| 128 | 5 B | `jmp` past runtime blobs |
| 133 | 63 B | `rt_pri` — print signed 64-bit integer |
| 196 | 13 B | `rt_prs` — print null-terminated string |
| 209 | … | Compiled user code |

Entry point VA: `0x400080`  ·  Load base: `0x400000`  ·  Code starts at VA: `0x4000D1`

---

## Test case

```rex
int x = 42
output x
```

Expected output:

```
42
```

Exit code: `0`
