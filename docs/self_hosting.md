# Rex Self-Hosting Roadmap

Rex V5.0 targets full self-hosting: the Rex compiler will eventually be written in
Rex and compile itself. This document records the bootstrap plan, prerequisites,
and milestone criteria.

---

## What Self-Hosting Means

A self-hosting compiler can compile its own source code and produce a binary that,
when run on the same source, produces an identical binary. For Rex this means:

1. `rex_compiler.rx` (Rex source) compiled by the NASM-bootstrap Rex compiler
   produces `rex2` binary.
2. `rex2` compiles `rex_compiler.rx` and produces `rex3` binary.
3. `rex2` and `rex3` are byte-for-byte identical (modulo timestamps).

---

## Prerequisites

The following Rex features must be working before the self-hosted compiler can
be written:

| # | Feature | Status |
|---|---------|--------|
| 1 | Recursive protocols (`@recurse` or indirect call) | **done** — per-call stack frames, `@proto` syntax |
| 2 | String operations (concat, char-index, compare, slice) | **done** — `str_at`, `str_eq`, `str_slice` wired |
| 3 | Dynamic sequences (realloc on overflow) | **done** — issue #19 fixed |
| 4 | File I/O syscall wrappers (read, write, open, close) | **done** — `file_open/read_all/write/close` live |
| 5 | Dict / hash-map for symbol tables | **done** — Stage 4 complete |
| 6 | Bitwise byte operations (shr 8, and 0xFF) | **done** — Stage 3b complete |
| 7 | Module / include system | planned |

All blocking prerequisites for Phase 2 are now satisfied.

---

## Phase Plan

### Phase 0 — Current (V5.0)
Hand-written NASM ELF64 compiler.  All language features through Stage 7 are
complete.

### Phase 1 — Language Completion ✅
All milestones met:

- Recursive protocol calls with proper per-call stack frames — **done**.
- `file_open(path, flags) → fd`, `file_read_all(path) → str`,
  `file_write(fd, s)`, `file_close(fd)` — **done** (inline syscall emission).
- `str_at(s,i) → int`, `str_eq(a,b) → int`, `str_slice(s,i,j) → str` — **done**.
- Dict literal `{k: v, ...}` and variable-key subscript `d[x]` — **done** (Stage 4).

### Phase 2 — Bootstrap Lexer in Rex (`rex_bootstrap.rx`)
Write the Rex lexer in Rex.  Input: null-terminated source string.
Output: flat sequence of (type, start, len) token records.

Key challenges:
- Character-by-character scanning needs `str_at` and byte comparisons.
- Token table needs a dict or a flat array of (name, token_type) pairs.
- Identifier classification loop needs recursion or a `while` loop with seq.

See `rex_bootstrap.rx` for the current skeleton.

### Phase 3 — Bootstrap Parser + Codegen in Rex
Write the recursive-descent parser and x86-64 ELF emitter in Rex.
The emitter will be a sequence of bytes built up with `push` and written
via `file_write`.

Required: recursive protocols (phase 1), seqs of bytes, bitwise ops.

### Phase 4 — Bootstrapping
```
rex rex_compiler.rx -o rex2          # compile with NASM compiler
rex2 rex_compiler.rx -o rex3         # compile with Rex-hosted compiler
diff rex2 rex3                        # should be identical
```

---

## Key Design Decisions for Self-Hosted Compiler

### No Dynamic Linking
The ELF binary is fully static.  All runtime support is inlined or linked at
a fixed offset (same strategy as the NASM compiler).

### Single-Pass Codegen
The NASM compiler uses a single-pass walk: parse then immediately emit.
The Rex-hosted compiler will mirror this design to keep it simple.

### Fixed Symbol-Table Layout
Use a flat array of 64-byte VAR_ENTRY records (same as NASM compiler) so the
same `get_var_va` address formula works in both compilers.

### Tokenizer Output
Produce a seq of records: `[type:int, start:int, len:int, ival:int, fval:float]`
so both the parser and error reporter have full context.

---

## File Structure for Bootstrap

```
rex_bootstrap.rx        ← phase-2 skeleton (lexer in Rex)
rex_compiler.rx         ← phase-3 full compiler in Rex (future)
docs/self_hosting.md    ← this file
docs/rex_ir.md          ← IR specification
```

---

## Milestone Criteria

| Phase | Done When |
|-------|-----------|
| Phase 0 | All open issues resolved; `use` block fully expanded |
| Phase 1 | `rex_bootstrap.rx` compiles without errors; recursion + file I/O work |
| Phase 2 | Lexer-in-Rex tokenises `hello.rx` identically to NASM lexer |
| Phase 3 | Parser+codegen in Rex compiles `hello.rx` to a working ELF |
| Phase 4 | `rex2 rex_compiler.rx` == `rex3 rex_compiler.rx` (byte identical) |
