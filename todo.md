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
- [x] `stop` keyword (loop break)
- [x] `while x == N:` loop
- [x] `if :i == N:` inside loop body (loop var support)

---

## Stage 2 — Protocols (Complete ✅)
- [x] Protocol definition `prot name():`
- [x] `return N` / `return` inside prot
- [x] `@name()` standalone call

---

## Stage 3 — Additional Types (Complete ✅)
- [x] `float` type: XMM registers, `rt_prf` blob, SSE loading
- [x] `bool` tri-state type: `true`, `false`, `unknown` (distributed RNG via `rdrand`)
- [x] `str` type: String literals, UTF-8 length-prefixed storage, output support
- [x] `complex` type: Lexer support, storage reservation

---

## Stage 4 — Native Collections (In Progress 🔄)
- [ ] Dynamic sequences `@`
- [ ] Dictionaries (SipHash + open addressing)
- [ ] Sets and Tuples

---

## Stage 5 — Advanced Protocols
- [ ] Parameterized protocols
- [ ] Local variable stack frames
- [ ] Protocol return to variables

---

## Stage 6 — Memory Allocator Contexts
- [ ] `use mm N gc N:` syntax
- [ ] Dynamic switching of memory managers and garbage collectors

---

## Stage 7 — Runtime Hardening
- [ ] Error output to stderr
- [ ] Variable table growth
- [ ] Multi-file compilation

---

## Stage 8 — Speed / Binary Quality
- [x] Maintain `< 1 KB` binary size target for compiled output (currently ~500 bytes for basic programs)
- [ ] Benchmarks and optimizations
