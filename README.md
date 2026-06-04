# Rex Bootstrap Compiler — V5.0

A hand-written, self-contained x86-64 ELF compiler for the **Rex V5.0** language,
built entirely in NASM assembly with **zero external dependencies** in the output binary.

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
│   └── runtime.asm       # Inline runtime blobs: rt_pri, rt_prf, rt_prb, rt_prs, rt_prc,
│                         #   rt_prq (dict/SipHash), rt_alc, rt_err
│
├── docs/
│   ├── grammar.md               # Formal EBNF grammar (all productions, precedence, layouts)
│   ├── opcodes.md               # Machine-code emit reference (byte sequences by construct)
│   ├── language_comparison.md   # Rex vs C / C++ / Rust / Python feature matrix
│   ├── speed_comparison.md      # Compilation and runtime speed benchmarks
│   ├── rex_ir.md                # IR design spec for future optimisation passes
│   ├── self_hosting.md          # Roadmap to a Rex-compiled Rex compiler
│   └── issues.md                # Known bugs and design limitations
│
├── tests/
│   ├── test.rex                 # Basic: int x = 42 / output x → 42
│   ├── conditional_test.rex     # if branch taken → 1 / 2
│   ├── elif_else_test.rex       # elif branch taken → 2 / 4
│   ├── test_bool.rex            # Tri-state bool: true / false / unknown
│   ├── test_float.rex           # Float arithmetic and output
│   ├── test_str.rex             # String literals and output
│   ├── test_complex.rex         # Complex number printing
│   ├── test_sequences.rex       # seq push / pop / len / cap
│   ├── test_dict.rex            # dict set / get (SipHash)
│   ├── test_arithmetic.rex      # All arithmetic operators
│   ├── test_bitwise.rex         # Bitwise operators
│   ├── test_for_loop.rex        # For loop range + step
│   ├── test_while_full_expr.rex # While with full expression conditions
│   ├── test_if_full_expr.rex    # If/elif with full expression conditions
│   ├── test_parameterized_prot.rex # Protocols with up to 6 parameters
│   ├── test_protocol_return.rex # Protocol return values including float
│   ├── test_type_propagation.rex # cur_type tracking through expressions
│   └── …                       # Additional edge-case and feature tests
│
├── edgecases/
│   └── README.md                # Status table for edge-case tests (issues 4–37)
│
├── benchmark/
│   └── README.md                # Benchmark methodology and results
│
├── syn.md                # Language syntax reference (full feature guide)
├── todo.md               # Implementation roadmap with stage checkboxes
├── rules.md              # Project rules: testing, code style, architecture
├── CHANGELOG.md          # Version history and change log
├── Makefile              # Build all modules; `make test` runs the full pipeline
└── build.sh              # Shell equivalent of `make test` (used by Replit workflow)
```

---

## Rex V5.0 language — implemented feature set

### Types

| Type      | Example              | Notes                                              |
|-----------|----------------------|----------------------------------------------------|
| `int`     | `int a = 5`          | 64-bit signed integer                              |
| `float`   | `float b = 1.5`      | 64-bit double (SSE2)                               |
| `bool`    | `bool f = true`      | Tri-state: `true`, `false`, `unknown` (via rdrand) |
| `complex` | `complex c = 3+4j`   | 128-bit XMM pair (real + imaginary)                |
| `str`     | `str s = "Rex"`      | Null-terminated UTF-8 pointer                      |
| `seq`     | `seq items`          | Dynamic sequence — auto-grows on overflow          |
| `dict`    | `dict d`             | SipHash-2-4 key-value map                          |

### Statements

| Syntax | Meaning |
|---|---|
| `int x` | Declare a **mutable** variable `x` (uninitialized) |
| `int x = 42` | Declare an **immutable** constant `x` initialized to `42` |
| `:x = 10` | Assign `10` to the **mutable** variable `x` (error if `x` is const) |
| `output x` | Print the value of variable `x` followed by a newline |
| `output 42` | Print the integer literal `42` followed by a newline |
| `if x == N:` | Conditional branch — all six comparison operators supported |
| `elif x == N:` | Chained condition (zero or more, after `if`) |
| `else:` | Fallback branch (optional, after `if`/`elif`) |
| `when x:` / `is N:` | Switch-like routing with linear case matching |
| `for :i in 0..N:` | Range loop — bounds accept full expressions |
| `for :i in 0..N step S:` | Range loop with explicit step |
| `while cond:` | While loop — condition is a full expression |
| `stop` | Break the innermost loop |
| `skip N` | Continue the Nth enclosing loop |
| `pass` | Zero-byte semantic placeholder for empty blocks |
| `prot name(a, b):` | Define a protocol (function) with up to 6 parameters |
| `@name(args)` | Call a protocol |
| `return expr` | Return a value from a protocol |
| `err "msg"` | Print to stderr and halt with exit code 1 |
| `push seq val` | Append a value to a sequence (auto-grows) |
| `pop seq` | Remove and return the last element of a sequence |
| `swap x y` | Exchange two variables via `xchg` |
| `++x` / `--x` | Increment / decrement a variable in place |

### Operators

| Category | Operators | Notes |
|---|---|---|
| Arithmetic | `+` `-` `*` `/` `%` | Float-dominant type propagation |
| Bitwise | `&` `\|` `^` `~` `<<` `>>` | Full 64-bit width |
| Comparison | `==` `!=` `<` `>` `<=` `>=` | Returns 0 or 1 |
| Logical | `and` `or` | Short-circuit evaluation |
| Unary | `-x` `~x` `abs(x)` | Negation, bitwise NOT, absolute value |
| Type cast | `int(f)` `float(n)` | SSE2 `cvttsd2si` / `cvtsi2sd` |
| Sequence | `len s` `cap s` | Runtime read from hidden header |
| Reflection | `typeof x` | Returns compile-time type token as int |

### Branching rules
- Conditions accept full expressions with any comparison operator
- Branches are indentation-delimited (INDENT/DEDENT tokens)
- Any number of `elif` clauses may follow an `if`
- An optional `else` terminates the chain
- All branches emit correct forward-jump machine code via a dual patch-stack
  (`jump_patch_stack` for JNE, `end_jump_stack` for JMP-to-chain-end)

---

## Building

### Prerequisites

```bash
nasm     # assembler (version 2.16+ recommended)
ld       # GNU linker (binutils)
```

> **Note:** NASM 2.15.05 (the version in some Nix/Replit environments) segfaults
> on startup. Use NASM 2.16+ from a CI container or install from source.
> See `docs/issues.md` issue #2.

### Build and test

```bash
# Full pipeline: assemble → link → run all tests
bash build.sh

# Or use make
make          # produces ./rexc
make test     # runs all test cases
make clean    # remove object files, rexc, and output
```

---

## How it works

```
source.rex
    │
    ▼
[ lexer ]  →  token stream  (TOK_TYPE_INT, TOK_IDENT, TOK_IF, TOK_FOR, …)
    │
    ▼
[ parser ]  →  variable table  (name, value, type, is_const, is_initialized)
             →  proto table    (name, out_idx, param_count, param_vars, ret_type)
             →  dispatches codegen calls for each statement
    │
    ▼
[ codegen ]  →  out_buffer  (raw x86-64 machine bytes, up to 128 KiB)
             →  patch stacks for forward jumps:
                  jump_patch_stack  — JNE conditional-fail placeholders
                  end_jump_stack    — JMP taken-branch-exit placeholders
                  chain_base_stack  — per-chain depth snapshots for bulk-patch
                  break_patch_stack — JMP loop-exit placeholders
                  cont_base_stack   — loop back-edge addresses for skip
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
| 209 | … | Additional runtime blobs (float, bool, complex, dict, alloc, err) |
| CODE_START | … | Compiled user code |

Entry point VA: `0x400080`  ·  Load base: `0x400000`  ·  Code starts at VA: `0x4000D1`

---

## Test results (core suite)

| Test file | Expected output |
|---|---|
| `tests/test.rex` | `42` |
| `tests/conditional_test.rex` | `1\n2` |
| `tests/elif_else_test.rex` | `2\n4` |
| `tests/test_bool.rex` | `true\nfalse\n` (unknown varies) |
| `tests/test_float.rex` | `4.000000` |
| `tests/test_str.rex` | `hello` |
| `tests/test_complex.rex` | `(3+4j)` |
| `tests/test_sequences.rex` | `3\n8\n30` |
| `tests/test_dict.rex` | `42` |
| `tests/test_arithmetic.rex` | Arithmetic results |
| `tests/test_bitwise.rex` | Bitwise results |
| `tests/test_parameterized_prot.rex` | Protocol results |

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

---

## Documentation index

| File | Contents |
|---|---|
| `syn.md` | Full language syntax reference with status markers |
| `todo.md` | Stage-by-stage implementation checklist |
| `rules.md` | Testing rules, code style rules, architecture rules |
| `CHANGELOG.md` | Version history |
| `docs/grammar.md` | Formal EBNF grammar — all productions, precedence, type and table layouts |
| `docs/opcodes.md` | Machine-code emit reference — every byte sequence Rex emits, indexed by construct |
| `docs/language_comparison.md` | Rex vs C / C++ / Rust / Python feature matrix |
| `docs/speed_comparison.md` | Compilation and runtime speed benchmarks |
| `docs/rex_ir.md` | IR specification for the planned optimisation layer |
| `docs/self_hosting.md` | Roadmap to a self-hosting Rex compiler |
| `docs/issues.md` | Known bugs, fixed issues, and open limitations |
| `edgecases/README.md` | Edge-case test status table |
| `benchmark/README.md` | Benchmark methodology |
