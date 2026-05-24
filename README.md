# Rex Bootstrap Compiler — Stage 0

A hand-written, self-contained x86-64 ELF compiler for the **Rex V5.0** language,
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
│   └── codegen.asm       # Code emitter: x86-64 machine code into out_buffer
│
├── headers/
│   └── headers.asm       # ELF64 header + program header writer
│
├── runtime/
│   └── runtime.asm       # Inline runtime blobs: rt_pri (print integer) + rt_prs (print string)
│
├── docs/
│   └── language_comparison.md   # Rex vs C / C++ / Rust / Zig / Python / JS matrix
│
├── tests/
│   ├── test.rex              # Basic: `int x = 42` / `output x`  → 42
│   ├── conditional_test.rex  # if branch taken         → 1 / 2
│   └── elif_else_test.rex    # elif branch taken        → 2 / 4
│
├── Makefile              # Build all modules; `make test` runs the full pipeline
└── build.sh              # Shell equivalent of `make test` (used by Replit workflow)
```

---

## Rex V5.0 language — Stage 0 subset

| Syntax | Meaning |
|---|---|
| `int x` | Declare a **mutable** variable `x` (uninitialized) |
| `int x = 42` | Declare an **immutable** constant `x` initialized to `42` |
| `:x = 10` | Assign `10` to the **mutable** variable `x` (error if `x` is const) |
| `output x` | Print the value of variable `x` followed by a newline |
| `output 42` | Print the integer literal `42` followed by a newline |
| `if x == N:` | Conditional branch — body indented one level |
| `elif x == N:` | Chained condition (zero or more, after `if`) |
| `else:` | Fallback branch (optional, after `if`/`elif`) |

### Branching rules
- Conditions are compile-time evaluated: `<ident> == <int_literal>`
- Branches are indentation-delimited (INDENT/DEDENT tokens)
- Any number of `elif` clauses may follow an `if`
- An optional `else` terminates the chain
- All branches emit correct forward-jump machine code via a dual patch-stack
  (`jump_patch_stack` for JNE, `end_jump_stack` for JMP-to-chain-end)

---

## Building

### Prerequisites

```bash
nasm     # assembler
ld       # GNU linker (binutils)
```

### Build and test

```bash
# Full pipeline: assemble → link → run all 3 tests
bash build.sh

# Or use make
make          # produces ./rexc
make test     # runs all 3 test cases
make clean    # remove object files, rexc, and output
```

---

## How it works

```
source.rex
    │
    ▼
[ lexer ]  →  token stream  (TOK_TYPE_INT, TOK_IDENT, TOK_IF, TOK_ELIF, TOK_ELSE, …)
    │
    ▼
[ parser ]  →  variable table  (name, value, is_const, is_initialized)
             →  dispatches codegen calls for each statement
    │
    ▼
[ codegen ]  →  out_buffer  (raw x86-64 machine bytes)
             →  patch stacks for forward jumps:
                  jump_patch_stack  — JNE conditional-fail placeholders
                  end_jump_stack    — JMP taken-branch-exit placeholders
                  chain_base_stack  — per-chain depth snapshots for bulk-patch
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
| 133 | 63 B | `rt_pri` — print signed 64-bit integer + newline |
| 196 | 13 B | `rt_prs` — print null-terminated string |
| 209 | … | Compiled user code |

Entry point VA: `0x400080`  ·  Load base: `0x400000`  ·  Code starts at VA: `0x4000D1`

---

## Test results

| Test file | Input | Expected output |
|---|---|---|
| `tests/test.rex` | `int x = 42 / output x` | `42` |
| `tests/conditional_test.rex` | `int x = 42 / if x == 42: output 1 / output 2` | `1\n2` |
| `tests/elif_else_test.rex` | `int a = 42 / if a==1: … / elif a==42: output 2 / else: … / output 4` | `2\n4` |

---

## Branch jump mechanics (if/elif/else)

For `elif_else_test.rex` (`a = 42`, chain: `if a==1 / elif a==42 / else / output 4`):

```
offset 209:  BF 2A 00 00 00       mov edi, 42       ← load a
offset 214:  81 FF 01 00 00 00    cmp edi, 1        ← if a==1?
offset 220:  0F 85 ?? ?? ?? ??    jne  → elif_start  ← P1 (patched to +17)
             [if body: skipped]
offset 226:  E9 ?? ?? ?? ??       jmp  → chain_end   ← P2 (patched to +28)
elif_start:
offset 231:  BF 2A 00 00 00       mov edi, 42
offset 236:  81 FF 2A 00 00 00    cmp edi, 42       ← elif a==42?
offset 242:  0F 85 ?? ?? ?? ??    jne  → else_start  ← P3 (patched to +10)
offset 248:  E8 xx xx xx xx       call rt_pri        ← prints 2
offset 253:  E9 ?? ?? ?? ??       jmp  → chain_end   ← P4 (patched to +5)
else_start:
             [else body: skipped because P3 → here, but a==42 so P3 not taken]
chain_end:
offset 258:  BF 04 00 00 00       mov edi, 4
offset 263:  E8 xx xx xx xx       call rt_pri        ← prints 4
```
