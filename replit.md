# Rex Bootstrap Compiler — Agent Context

## Project purpose

This is a from-scratch, single-pass, zero-dependency x86-64 ELF compiler for the
Rex V5.0 language, written entirely in NASM assembly.  The compiler (`rexc`) reads a
`.rex` source file, emits raw machine code into an internal buffer, prepends a static
128-byte ELF64 header, and writes the result as a directly executable binary called
`./output`.

No libc.  No linker scripts.  No external tools beyond `nasm` + `ld`.

---

## File tree

```
include/rex_defs.inc      shared token IDs, VAR_ENTRY_SIZE constant
main/main.asm             argv[1] open → read loop → parse_stmt loop → codegen_finish
lexer/lexer.asm           tokeniser: keywords, idents, int literals, INDENT/DEDENT
parser/parser.asm         recursive-descent: decl, assign, output, if/elif/else
codegen/codegen.asm       machine-code emitter + three-level jump patch stacks
headers/headers.asm       static ELF64 header + PT_LOAD program header data
runtime/runtime.asm       rt_pri blob (print int+newline) + rt_prs blob (print string)
docs/language_comparison.md   Rex vs C/C++/Rust/Zig/Python/JS feature matrix
tests/test.rex            basic variable + output test  → 42
tests/conditional_test.rex    if branch taken            → 1 / 2
tests/elif_else_test.rex      elif branch taken          → 2 / 4
Makefile                  nasm + ld rules; `make test` runs all three tests
build.sh                  shell equivalent used by the Replit workflow
```

---

## Build and test

```bash
bash build.sh     # assemble, link, run all 3 tests — should print 42 / 1\n2 / 2\n4
make test         # same via make
```

All three tests must pass before any further work.

---

## Token IDs (include/rex_defs.inc)

```
TOK_EOF=0  TOK_NEWLINE=1  TOK_INDENT=2  TOK_DEDENT=3
TOK_IDENT=4  TOK_INT_LIT=5  TOK_TYPE_INT=6
TOK_ASSIGN=7  TOK_COLON=8  TOK_OUTPUT=9
TOK_IF=10  TOK_FOR=11  TOK_IN=12  TOK_DOTDOT=13
TOK_EQEQ=14  TOK_ELSE=15  TOK_ELIF=16
```

---

## Implemented features (Stage 1)

| Feature | Status |
|---|---|
| `for :i in 0..N:` range loop | ✅ |
| Loop variable live in edi (is_loop_var flag) | ✅ |
| `stop` keyword (break out of loop) | ✅ |
| `while x == N:` condition loop | ✅ |
| `prot name():` protocol definition | ✅ |
| `@name()` standalone protocol call | ✅ |
| `return N` inside prot | ✅ |
| `docs/todo.md` — full V5.0 roadmap | ✅ |
| `docs/speed_comparison.md` | ✅ |

---

## Implemented features (Stage 0)

| Feature | Status |
|---|---|
| `int x` (mutable var declaration) | ✅ |
| `int x = 42` (immutable const, inline init) | ✅ |
| `:x = N` (mutable assignment, const guard) | ✅ |
| `output x` (print variable) | ✅ |
| `output 42` (print integer literal) | ✅ |
| `if x == N:` (conditional branch) | ✅ |
| `elif x == N:` (chained condition) | ✅ |
| `else:` (fallback branch) | ✅ |

---

## Codegen jump-patch architecture

Three stacks in codegen.asm BSS:

| Stack | Purpose |
|---|---|
| `jump_patch_stack` / `jump_stack_depth` | One JNE placeholder per live conditional branch |
| `end_jump_stack` / `end_jump_depth` | One JMP placeholder per taken if/elif body exit |
| `chain_base_stack` / `chain_base_depth` | Snapshots end_jump_depth at each chain entry |

Key codegen functions:

| Function | Role |
|---|---|
| `codegen_emit_cmp_jne(rdi=var_val, rsi=cmp_val)` | Emit `mov edi,V; cmp edi,C; jne +0` → pushes JNE placeholder |
| `codegen_patch_jump` | Pop top JNE placeholder, back-fill rel32 to current `out_idx` |
| `codegen_save_chain_base` | Push current `end_jump_depth` onto `chain_base_stack` |
| `codegen_emit_jmp_end` | Emit `jmp +0` → push JMP placeholder onto `end_jump_stack` |
| `codegen_patch_chain_end` | Pop chain base; patch all end_jump entries to `out_idx`; reset depth |

---

## Parser flow for if/elif/else

`parse_if` (in parser/parser.asm) handles the complete chain:

1. Calls `codegen_save_chain_base` once at chain entry.
2. Parses condition `<ident> == <int_lit>`, emits `cmp+JNE` placeholder.
3. Runs body loop until `TOK_DEDENT`.
4. Advances past DEDENT, then checks next token:
   - `TOK_ELIF` → emit `JMP end`, patch JNE, advance to ident, jump to step 2.
   - `TOK_ELSE` → emit `JMP end`, patch JNE, parse else body, `codegen_patch_chain_end`.
   - Anything else → `codegen_patch_jump` + `codegen_patch_chain_end`, return.

---

## Next features to implement (V5.0 spec priority order)

1. **`float` type** — add `TOK_FLOAT_LIT`, XMM register allocation in codegen, `rt_prf` blob.
2. **`bool` type** with tri-state (`true`/`false`/`unknown`) — `unknown` triggers `rdrand`.
3. **String literals** — UTF-8, length-prefix stored in var table, `rt_prs` already present.
4. **Protocol parameters** — `prot compute_factorial(int n)`, register-based arg passing.
5. **`@` sequences / dicts / sets** — SipHash open-addressing hash table in runtime.
6. **`use mm N gc N:` allocator contexts** — dynamic allocator handoff blocks.

See `todo.md` for the full V5.0 implementation roadmap.

Refer to the architecture document in `attached_assets/` for canonical Rex V5.0 source
examples for each of the above features.

---

## Known limitations / future hardening

- Variable table is a flat linear scan (max 64 vars, 32-byte names).
- Conditions are compile-time: the compiler substitutes the variable's stored value at
  parse time rather than emitting a runtime load from memory.  True runtime variables
  require a stack-frame allocator in codegen.
- `output` currently only handles `int` variables and integer literals.
- Error messages write to stdout; a proper stderr path is planned.
- Binary size budget target: **< 1 KB** for the compiled output.

---

## Replit workflow

The `Start application` workflow runs `bash build.sh`, which assembles all six modules,
links them into `./rexc`, then compiles and runs all three test files.  Green output
means all tests pass.
