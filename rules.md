# Rex V5.0 — Project Rules

## Testing

### Rule T-1: All features must have a test file in `tests/`

Every language feature that is implemented in the Rex V5.0 compiler **must** have a
corresponding test source file (`.rex`) in the `tests/` directory.

**Requirements:**
- Each test file must be named after the feature it exercises
  (e.g., `test_bool.rex`, `test_sequences.rex`, `test_parameterized_prot.rex`).
- The test file must exercise the feature in a meaningful, non-trivial way.
- Tests must cover at least one passing case and, where applicable, a boundary case.
- A test file must be created **before** or **at the same time** as the feature is merged.

**Scope:** This rule applies to:
- New language keywords and statement types (`if`, `while`, `for`, `stop`, `return`,
  `err`, `push`, `pop`, `len`, etc.)
- New value types (`int`, `float`, `bool`, `str`, `complex`, `seq`, `dict`)
- Control-flow constructs (if/elif/else chains, while loops, for loops, break)
- Protocol features (zero-arg protocols, parameterized protocols, protocol return values)
- Expression parser features (arithmetic, bitwise, comparisons, type propagation)
- Memory allocator switches (`use mm pool gc ...`, `use mm arena gc ...`)

**Exemptions:**
- Internal refactors that do not change observable compiler output.
- Documentation-only changes.

---

## Code Style

### Rule C-1: No semicolons inside NASM instruction sequences

NASM treats `;` as a line comment. Never write two instructions on one line separated
by `;`. Every instruction must appear on its own line.

### Rule C-2: All globals must be declared

Every symbol used across compilation units must appear in both a `global` declaration
(in the defining file) and an `extern` declaration (in the using file).

### Rule C-3: Runtime blob sizes must be respected

The `times RT_XXX_SIZE - ($ - rt_xxx_blob) db 0x90` padding at the end of each blob
is a hard contract. Adding code to a blob must not push its size past RT_XXX_SIZE.
Measure the assembled size before increasing code inside a blob.

---

## Language

### Rule L-1: Rex must be built in pure x86-64 NASM assembly — no exceptions

Every component of the Rex compiler, runtime, toolchain, and any future tooling (assembler,
disassembler, linker, debugger, test runner, benchmark harness) **must** be written
exclusively in x86-64 NASM assembly.

**This rule prohibits:**
- C, C++, Rust, Python, Shell, Go, or any other programming language inside the Rex project
- Makefile `$(shell ...)` recipes that call external language runtimes to generate code
- Generated source files produced by scripts written in non-assembly languages
- Third-party libraries or object files compiled from non-assembly sources
- Inline C or GCC-intrinsic extensions inside assembly files

**This rule permits:**
- The `Makefile` itself (build system only, no logic — only `nasm`, `ld`, and `ar` invocations)
- Shell one-liners in the `Makefile` that are purely file-system operations (`rm`, `mkdir`, `cp`)
- `.rex` test source files in `tests/` and `benchmark/` (those are Rex language, not compiler code)
- Benchmark subjects written in other languages placed in `benchmark/` for comparison only
  (e.g., `bench_sum.c`) — these are measurement targets, not part of Rex itself

**Rationale:**
Rex is a demonstration that a full compiler — lexer, parser, codegen, runtime, and tooling —
can be built entirely in bare-metal assembly. Introducing any higher-level language defeats
this core thesis. Every line of `.asm` in this project is a deliberate choice. If a feature
cannot be implemented in NASM x86-64, the architecture must be redesigned, not the language rule relaxed.

**Scope:** All files under `main/`, `lexer/`, `parser/`, `codegen/`, `headers/`, `runtime/`,
`compiler/`, and any future tooling directory.

---

## Architecture

### Rule A-1: Dict runtime offsets must be re-measured after blob changes

`RT_DICT_NEW_OFFSET`, `RT_DICT_SET_OFFSET`, and `RT_DICT_GET_OFFSET` in
`include/rex_defs.inc` are manually measured. Any change to a blob that precedes
`rt_prq_blob` in the binary invalidates these offsets. They must be re-measured
and updated immediately.

### Rule A-2: CODE_START must equal RT_ERR_OFFSET + RT_ERR_SIZE

`CODE_START` in `include/rex_defs.inc` marks where user-emitted code begins.
It must be kept equal to the end of the last runtime blob. Update it whenever
a new blob is added or an existing blob's size changes.

### Rule A-3: Protocol table entries are 48 bytes

`proto_table` uses 48-byte entries: 32 bytes for the name, 8 for the out_idx
offset, 1 for param_count, 6 for per-param var indices, 1 byte padding.
All lookups and writes must use `imul rax, 48`.
