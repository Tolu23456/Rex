# Rex V5.0 Compiler — Implementation Todo

## Stage 0 — Core Infrastructure (Complete ✅)
- [x] Modular 6-folder architecture: `main/`, `lexer/`, `parser/`, `codegen/`, `headers/`, `runtime/`
- [x] `int x` — mutable variable declaration
- [x] `int x = 42` — immutable constant with inline init
- [x] `:x = N` — mutable assignment + compile-time const guard
- [x] `output x` / `output N` — print variable or int literal
- [x] `if x == N:` — conditional branch with JNE patch stack
- [x] `elif x == N:` — chained elif (multiple allowed)
- [x] `else:` — fallback branch
- [x] Three-level jump-patch architecture (`jump_patch_stack`, `end_jump_stack`, `chain_base_stack`)
- [x] `docs/language_comparison.md` — Rex vs C / C++ / Rust / Zig / Python / JS matrix
- [x] Three passing tests: `test.rex`→42, `conditional_test.rex`→1/2, `elif_else_test.rex`→2/4

---

## Stage 1 — Control Flow Loops (Complete ✅)
- [x] `for :i in 0..N:` range loop
- [x] `stop` keyword (loop break) — fully wired to break_base/patch system
- [x] `while x == N:` loop
- [x] `if :i == N:` inside loop body (loop var support)

---

## Stage 2 — Protocols (Complete ✅)
- [x] Protocol definition `prot name():`
- [x] `return N` / `return` inside prot — now supports full expressions
- [x] `@name()` standalone call

---

## Stage 3 — Additional Types (Complete ✅)
- [x] `float` type: XMM registers, `rt_prf` blob, SSE loading — arithmetic fixed (semicolon bug)
- [x] `bool` tri-state type: `true`, `false`, `unknown` (distributed RNG via `rdrand`) — printer implemented
- [x] `str` type: String literals, UTF-8 inline embedding, output support — fully wired
- [x] `complex` type: Lexer support, storage, arithmetic, `(real+imagj)` printer

---

## Stage 3b — Expression System Fixes (Complete ✅)
- [x] Full expression conditions in `if` / `elif` / `else` (any comparison operator)
- [x] Full expression conditions in `while`
- [x] `true` / `false` / `unknown` as expression atoms in `parse_factor`
- [x] String literals as expression atoms in `parse_factor` (inline code-stream embedding)
- [x] `use mm pool` — full string comparison (not just first char)
- [x] `stop` break system fully wired: `codegen_emit_while_start` called by `for`/`while`
- [x] `codegen_output_rax_bool` — routes bool output to `rt_prb_blob`
- [x] `codegen_emit_cmp_rax_rbx_jcc` — generic comparison-then-branch emitter

---

## Stage 4 — Native Collections (In Progress 🔄)
- [x] Dictionaries (SipHash + open addressing) — codegen and runtime implemented
- [x] Dynamic sequences — `seq x`, `push x v`, `pop x` (expr), `len x` (expr)
- [ ] Sets and Tuples

---

## Stage 5 — Advanced Protocols (Complete ✅)
- [x] Parameterized protocols — `prot name(a, b):` with `@name(expr1, expr2)`
- [ ] Local variable stack frames (callee-saved regs, not yet implemented)
- [x] Protocol return to variables — `@name(args)` usable as expression atom in `parse_factor`

---

## Stage 6 — Memory Allocator Contexts
- [x] `use mm pool gc X:` / `use mm arena gc X:` — full string comparison
- [ ] Dynamic switching of garbage collectors

---

## Stage 7 — Runtime Hardening (Partial ✅)
- [x] Error output to stderr — `err "msg"` statement + `rt_err_blob`
- [ ] Variable table growth (currently fixed at VAR_MAX=128)
- [ ] Multi-file compilation
- [x] Expression type propagation — `cur_type` tracked through `+`, `-`, `*`, `/` chains

---

## Stage 8 — Speed / Binary Quality
- [x] Maintain `< 1 KB` binary size target for compiled output (currently ~500 bytes for basic programs)
- [ ] Benchmarks and optimizations

---

## Stage 9 — Bare-Metal Built-in Keywords and Operators Blueprint (Pending 🔄)

### I. Extended Type Infrastructure & Pridist Values
- [ ] Update `len` keyword:
    - [ ] `len` on `int` or `float` → Compile-time literal constant (8 bytes).
    - [ ] `len` on `complex` → Compile-time literal constant (16 bytes).
    - [ ] `len` on `bool` → Compile-time literal constant (1 byte).
    - [x] `len` on `str`, `seq` (`@[]`), and `dict` (`{}`) → 1-cycle runtime memory read from hidden 8-byte prefix (`mov rax, [reg - 8]`).

### II. Advanced Scalar Type Hooks
- [x] `typeof`: Compile-time reflection returning built-in integer token for `cur_type`.
- [x] Explicit Type Casting:
    - [x] `int(float)` → `cvttsd2si r64, xmm`.
    - [x] `float(int)` → `cvtsi2sd xmm, r64`.
- [x] `bin`: Base-wrapper primitive (Base 2–16) for bitmasks/byte configs (e.g., `bin10`).
- [ ] `abs` / `sign` / `clz`: Single-cycle hardware or branchless mapping to `lzcnt`/`bsr` and `cmovCC`.
- [ ] `ceil` / `floor` / `fract`: SSE floating-point rounding (`roundsd`) and truncation.
- [ ] `real` / `imag` / `conj`: 128-bit XMM parallel component isolators and register bitmasking.
- [ ] `flip` / `rand`: Hardware boolean flags mapping to bitwise NOT pipelines and entropy ring (`rdrand rax`).

### III. Advanced Hardware Pointers & Optimizers
- [ ] `addr`: Fetch variable pointer via immediate Load Effective Address (`lea rax, [rbp - offset]`).
- [ ] `peek` / `poke`: Direct memory-mapped register dereferencing (`mov rax, [rbx]` / `mov [rax], rbx`).
- [ ] `const`: Compile-time parser constraint blocking subsequent mutations.
- [ ] `volatile`: Disable register caching for symbol, forcing direct memory tracking.
- [ ] `unreachable` / `assert`: Optimizing crash boundary guards emitting `ud2` or linking to `rt_err_blob`.

### IV. Bare-Metal Hardware Operators
- [ ] `++` / `--`: Ultra-fast, single-byte hardware increments/decrements (`inc` / `dec`) directly in memory.
- [ ] `->`: Pipeline Operator. Smart Silicon Router cascading results across SysV ABI registers (`RDI`, `RSI`, `RDX`).
- [ ] `$`: Direct System Call Intercept. Pull parameters and drop into kernel space via raw `syscall`.

### V. Operator Precedence Refactor
- [x] Structure math parsing into strict 5-tier recursive-descent hierarchy inside `parse_expr`:
    1. Base Atoms & Parentheticals: `(expr)`, literals, variables, type conversions.
    2. Unary Ops: `-x`, bitwise NOT `~x`.
    3. Multiplicative Ops: `*`, `/`, `%`, bitwise shifts `<<`, `>>`.
    4. Additive & Bitwise Ops: `+`, `-`, `&`, `|`, `^`.
    5. Comparison Ops: Standalone evaluations returning clean byte set (`cmp` + `setCC` + `movzx`).
