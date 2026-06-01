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
- [x] `when` statement: Expressive routing block (`when x: / is N:` chain with linear cmp/jz); O(1) jump table optimisation pending
- [x] `pass`: Zero-byte semantic placeholder for empty blocks or unimplemented protocols
- [ ] Loop-Level `else:`: Executes if parent loop finishes naturally without triggering `stop`

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

## Stage 3b — Expression System Expansion (Complete ✅)
- [x] Full expression conditions in `if` / `elif` / `else` (any comparison operator)
- [x] Full expression conditions in `while`
- [x] `true` / `false` / `unknown` as expression atoms in `parse_factor`
- [x] String literals as expression atoms in `parse_factor` (inline code-stream embedding)
- [x] `use mm pool` — full string comparison (not just first char)
- [x] `stop` break system fully wired: `codegen_emit_while_start` called by `for`/`while`
- [x] `codegen_output_rax_bool` — routes bool output to `rt_prb_blob`
- [x] `codegen_emit_cmp_rax_rbx_jcc` — generic comparison-then-branch emitter
- [ ] `and` / `or`: Logical operators with short-circuit code generation
- [ ] `not`: Boolean/bitwise inversion mapping to `xor rax, 1` or `not rax`
- [ ] `is` / `is not`: Semantic identity and type-verification (evaluates to hardware `cmp`)

---

## Stage 4 — Native Collections (In Progress 🔄)
- [x] Dictionaries (SipHash + open addressing) — codegen and runtime implemented
- [x] Dynamic sequences — `seq x`, `push x v`, `pop x` (expr), `len x` (expr)
- [ ] `in` operator: Membership check via SipHash linear probing (dict) or iteration sweeps (seq/str)
- [ ] `each` iterator: Cache-aligned counter loop for sequential collection sweeping
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

## Known Bugs and Hard Limitations

These are confirmed defects in the current implementation, identified by static analysis.
Each must be fixed before the affected feature can be considered complete.

### B-1: Recursive protocols produce wrong results
Protocol parameters are stored in global `var_table` slots (at `VAR_STORAGE_BASE + idx*64`).
A recursive call overwrites the caller's copy of those slots before the caller resumes.
`fib(n)` calling `fib(n-1)` destroys `n` in the caller's frame.
**Fix required:** Per-call stack frames — push/pop param vars onto the hardware stack.
**Affects:** `parser/parser.asm` `.protocol` + `.prot_store_params`

### B-2: `seq` push beyond capacity silently corrupts heap
`push x v` emits `mov [rbx+rcx*8+16], rax` with no bounds check. Initial capacity is 8
slots (80-byte alloc). A 9th `push` writes 8 bytes past the end of the allocation, into
whatever the `rt_alc` allocator placed there.
**Fix required:** Emit a cap check before the store; call a realloc blob if `len == cap`.
**Affects:** `.push_stmt` in `parser/parser.asm`

### B-3: `for` loop bounds must be integer literals
`codegen_emit_for_start` receives `rdi=from`, `rsi=to` as immediate integers parsed directly
from `tok_int`. The syntax `for :i in 0..n:` where `n` is a variable does not work — the
parser reads `n` as an identifier and the codegen never receives an integer value.
**Fix required:** Replace bounds parsing with `parse_expr`; store result before emitting loop.
**Affects:** `.for` handler in `parser/parser.asm`

### B-4: Protocol parameters capped at 4 — 5th and 6th ignored at call site
`.prot_store_params` emits `mov [var_addr], rdi/rsi/rdx/rcx` for params 0–3 only. Params 4
and 5 are stored in `proto_table[entry+45]` and `[entry+46]` but the emit loop stops at
index 3 (no `r8`/`r9` emission). Protocols declared with 5 or 6 params silently drop them.
**Fix required:** Add `r8` (ModRM 0x04) and `r9` (ModRM 0x0C with REX.R) cases in the
store loop.
**Affects:** `.prot_store_params` in `parser/parser.asm`

### B-5: VAR_MAX = 128 is a hard ceiling with no overflow guard
`var_add` increments `[var_count]` without checking against `VAR_MAX`. Adding a 129th
variable writes past the end of `var_table` into adjacent BSS, silently corrupting
`proto_table` or other globals.
**Fix required:** Add `cmp [var_count], VAR_MAX; jge .var_full` guard in `var_add`; emit
compile-error diagnostic and halt.
**Affects:** `var_add` in `parser/parser.asm`

### B-6: `stop` only breaks the innermost loop — no outer-loop break
`codegen_emit_break` emits a `JMP` into the current loop's patch stack. When loops are
nested, `stop` inside the inner loop always patches to the inner loop's exit. There is no
syntax or mechanism to break an outer loop.
**Fix required:** `skip N` or labelled breaks (Stage 9 `skip`).
**Affects:** `codegen_emit_break` in `codegen/codegen.asm`

### B-7: `out_buffer` has no overflow guard
The emit buffer is `resb 65536`. `emit_b` writes `[out_buffer + out_idx]` and increments
`out_idx` with no bounds check. A program that generates more than 65536 bytes of code
silently overwrites BSS past the buffer.
**Fix required:** Add `cmp [out_idx], 65535; jge .emit_overflow` in `emit_b`; halt with
error.
**Affects:** `emit_b` in `codegen/codegen.asm`

### B-8: `float` type lost through protocol return
When `@prot()` is used as an expression atom (`.at_in_expr` in `parse_factor`), the
handler hard-codes `mov byte [cur_type], TYPE_INT` after `codegen_emit_call_prot`.
A protocol that computes and returns a float value will cause the calling scope to route
the result through `rt_pri` (integer printer) instead of `rt_prf`.
**Fix required:** Store return type in `proto_table` entry; restore `cur_type` from it
after the call.
**Affects:** `.at_in_expr` and `.at_call` in `parser/parser.asm`

### B-9: Negative for-loop bounds not supported
`tok_int` is stored as `uint64`. The lexer does not emit a unary-minus token before an
integer literal when it appears in a range context. `for :i in -5..5:` lexes as
`TOK_MINUS`, `TOK_INT_LIT(5)`, `TOK_DOTDOT`, `TOK_INT_LIT(5)` — the minus is never
applied to the start bound, and the parser discards it.
**Fix required:** Handle `TOK_MINUS` before range start in `.for` handler, or switch bounds
to `parse_expr`.
**Affects:** `.for` handler in `parser/parser.asm` (linked to B-3)

### B-10: Dict keys must be string literals — variable keys not supported
The dict handler emits a `call rt_sip(key_va, key_len)` with the key bytes embedded inline
in the code stream. There is no path for `d[x]` where `x` is a variable holding a runtime
string pointer.
**Fix required:** When the key token is `TOK_IDENT`, resolve the variable's runtime address
and pass it to the SipHash call instead of an inline literal.
**Affects:** Dict get/set handlers in `parser/parser.asm`

### B-11: No string concatenation and no `int → str` conversion
`output` routes `TYPE_STR` correctly, but there is no operator or builtin that joins two
strings or converts an integer to a string at runtime. `str s; :s = x + "px"` does not
work.
**Fix required:** Add `rt_str_cat` blob (Stage 9); add `str(expr)` cast syntax.
**Affects:** Expression parser, runtime

### B-12: `err` only accepts a string pointer — integer codes not supported
`.err_stmt` calls `parse_expr` and assumes the result in `rax` is a null-terminated string
pointer. `err 42` or `err code` where `code` is an `int` will pass a small integer to
`rt_err_blob`'s strlen loop, which will spin or segfault.
**Fix required:** Check `cur_type` after `parse_expr`; if `TYPE_INT`, route through an
int-to-string conversion before calling `rt_err`.
**Affects:** `.err_stmt` in `parser/parser.asm`

---

## Stage 8 — Speed / Binary Quality
- [x] Maintain `< 1 KB` binary size target for compiled output (currently ~500 bytes for basic programs)
- [ ] Benchmarks and optimizations

---

## Stage 9 — Bare-Metal Built-in Keywords and Operators Blueprint (Pending 🔄)

### I. Extended Type Infrastructure & Metadata Headers
- [ ] Update `len` keyword:
    - [ ] `len` on `int` or `float` → Compile-time literal constant (8 bytes).
    - [ ] `len` on `complex` → Compile-time literal constant (16 bytes).
    - [ ] `len` on `bool` → Compile-time literal constant (1 byte).
    - [x] `len` on `str`, `seq` (`@[]`), and `dict` (`{}`) → 1-cycle runtime memory read from hidden 8-byte prefix (`mov rax, [reg - 8]`).
- [x] `cap` (Capacity): 1-cycle read of second 8-byte hidden header (`mov rax, [reg - 16]`) — `codegen_emit_cap_rax` implemented.

### II. Memory, Ownership & Context Control
- [ ] `own` / `move`: Transfer ownership bypassing `ref_count` to eliminate redundant instructions.
- [ ] `free`: Manually recycle allocation block within pool/arena before scope end.
- [ ] `align`: CPU cache line alignment constraint (e.g., `align 64`) for memory offsets.
- [ ] `const`: Compile-time parser constraint blocking mutation assignments.
- [ ] `volatile`: Force direct memory tracking by disabling Stage 8 register caching.

### III. Concurrency, Control Flow & Selection
- [ ] `blast` / `pipe`: Vectorized iteration unrolling into `movntdq` / `movdqa` (bypassing CPU cache).
- [x] `skip`: Multi-level loop break. `codegen_emit_skip` + `codegen_push_cont`/`codegen_pop_cont` implemented. `skip N` breaks N levels.
- [ ] `match`: Structural pattern-matching. Sequential integers map to high-speed O(1) Jump Tables.
- [ ] `repeat N:`: Counted loop with no explicit counter variable. Emits a single `dec`+`jnz` hardware loop.
- [ ] `unreachable` / `assert`: Optimizing crash boundary guards emitting `ud2` or linking to `rt_err_blob`.

### IV. Bare-Metal Hardware Atoms & Intrinsics
- [x] `typeof`: Compile-time reflection returning built-in integer token for `cur_type`.
- [x] Explicit Type Casting:
    - [x] `int(float)` → `cvttsd2si r64, xmm`.
    - [x] `float(int)` → `cvtsi2sd xmm, r64`.
- [x] `bin`: Base-wrapper primitive (Base 2–16) for bitmasks/byte configs (e.g., `bin10`).
- [x] `abs`: `codegen_emit_abs_rax` implemented (`cmovns` pattern).
- [ ] `sign` / `clz`: Single-cycle hardware mapping to `lzcnt`/`bsr` — not yet implemented.
- [ ] `ceil` / `floor` / `fract`: SSE floating-point rounding (`roundsd`) and truncation.
- [ ] `real` / `imag` / `conj`: 128-bit XMM parallel component isolators and register bitmasking.
- [ ] `flip` / `rand`: Hardware boolean flags mapping to bitwise NOT pipelines and entropy ring (`rdrand rax`).
- [ ] `carry` / `overflow`: Built-in boolean expressions checking EFLAGS via `jc` or `jo`.
- [x] `swap`: Instant value exchange via `xchg rax, rbx` — `codegen_emit_swap_vars` implemented.
- [ ] `hash`: Direct backend SipHash-2-4 tracking loop over targeted memory pointers.

### V. Bare-Metal Hardware Operators
- [x] `++` / `--`: Single-byte hardware inc/dec — `codegen_emit_inc_var` / `codegen_emit_dec_var` implemented.
- [ ] `->`: Pipeline Operator. Smart Silicon Router cascading results across SysV ABI registers (`RDI`, `RSI`, `RDX`).
- [ ] `$`: Direct System Call Intercept. Pull parameters and drop into kernel space via raw `syscall`.

### VI. Operator Precedence Refactor
- [x] Structure math parsing into strict 5-tier recursive-descent hierarchy inside `parse_expr`:
    1. Base Atoms & Parentheticals: `(expr)`, literals, variables, type conversions.
    2. Unary Ops: `-x`, bitwise NOT `~x`.
    3. Multiplicative Ops: `*`, `/`, `%`, bitwise shifts `<<`, `>>`.
    4. Additive & Bitwise Ops: `+`, `-`, `&`, `|`, `^`.
    5. Comparison Ops: Standalone evaluations returning clean byte set (`cmp` + `setCC` + `movzx`).

---

## Stage 10 — Deterministic Hybrid Memory Safety Matrix (Pending 🔄)

### I. Strategy A: Destructive Linear Ownership (Compile-Time)
- [ ] Implement Affine ownership tracking in symbol table for `str`, `seq`, and `dict`.
- [ ] Add `is_live` state to collection tokens.
- [ ] Enforce destructive moves on assignment or protocol passing (`is_live = false`).
- [ ] Implement parser halt and ownership safety exception on dead variable access.

### II. Strategy B: Hardware Bounds Checking (Runtime Spatial Guard)
- [ ] Refactor subscription loop (`collection[i]`) for mandatory scale checks.
- [ ] Emit hardware scale check: load hidden length prefix (`mov rbx, [rax - 8]`).
- [ ] Emit `cmp index, rbx` + `jae` to route to `rt_err_blob` on violation.

### III. Strategy C: Lexical Region Closure (1-Cycle Reclamation)
- [ ] Auto-emit reclamation code on `TOK_DEDENT` for `use mm arena` blocks.
- [ ] Emit single-cycle reset: `mov qword [arena_offset], 0`.

### IV. Strategy D: Zero-Overhead Composite Null Safety
- [ ] Ban raw uninitialized/nullable pointers in type propagation.
- [ ] Enforce tri-state boolean gating (`true`/`false`/`unknown`) for optional/unknown variants.
- [ ] Back unknown variants with hardware processor entropy ring (`rdrand rax`).
