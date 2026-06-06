# Rex V0.1 Compiler — Implementation Todo

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
- [x] Loop-Level `else:`: Executes if parent loop finishes naturally without triggering `stop` (for / while / repeat / each — hidden `__le` flag var + flag stack in codegen)

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
- [x] `and` / `or`: Logical operators — short-circuit evaluation implemented
- [x] `not`: Boolean/bitwise inversion — `not rax` (int) or `xor rax,1` (bool) — type-dispatched in parse_factor + parse_unary
- [ ] `is` / `is not`: Semantic identity and type-verification (evaluates to hardware `cmp`)

---

## Stage 4 — Native Collections (In Progress 🔄)
- [x] Dictionaries (SipHash + open addressing) — codegen and runtime implemented
- [x] Dynamic sequences — `seq x`, `push x v`, `pop x` (expr), `len x` (expr)
- [x] `seq push` grow-on-overflow — inline 57-byte grow block doubles capacity automatically
- [ ] `in` operator: Membership check via SipHash linear probing (dict) or iteration sweeps (seq/str)
- [x] `each` iterator: `each :i in s:` — counter var `__ec`, hidden init before loop top, `mov rax,[rbx+rax*8+16]` element load, else: support
- [ ] Sets and Tuples

---

## Stage 5 — Advanced Protocols (Complete ✅)
- [x] Parameterized protocols — `prot name(a, b):` with `@name(expr1, expr2)`
- [x] Up to 6 parameters — r8/r9 emission added for params 4 and 5
- [x] Protocol return to variables — `@name(args)` usable as expression atom in `parse_factor`
- [x] Float return type preserved through protocol call — `proto_ret_type` BSS mirrors `[entry+47]`
- [x] Protocol local variables reclaimed via `scope_stack` save/restore
- [x] Per-call stack frames for recursive protocols — `.prot_push_lp` pushes params, `.prot_se` loads from ABI regs, `proto_emit_restore` pops in reverse order

---

## Stage 6 — Memory Allocator Contexts
- [x] `use mm pool gc X:` / `use mm arena gc X:` — full string comparison
- [x] Dynamic switching of garbage collectors — `codegen_emit_gc_switch(rdi=mode)` emits `mov [GC_MODE_ADDR], rdi`; GC_MODE_ADDR = VAR_STORAGE_BASE-8

---

## Stage 7 — Runtime Hardening (Partial ✅)
- [x] Error output to stderr — `err "msg"` statement + `rt_err_blob`
- [x] `err` non-string guard — `cur_type` checked after `parse_expr`; non-string types routed through correct printer then `exit(1)`
- [x] Variable table growth guard — `var_add` checks `cmp rbx, VAR_MAX; jge .full`
- [x] `out_buffer` overflow guard — `emit_b` halts with error if `out_idx >= 131071`; buffer is 128 KiB
- [x] Expression type propagation — `cur_type` tracked through `+`, `-`, `*`, `/` chains
- [x] `codegen_emit_exit1` — new global; emits `mov rax,60; mov rdi,1; syscall`
- [ ] Multi-file compilation

---

## Known Open Issues

These are confirmed defects in the current implementation that are not yet resolved.
See `docs/issues.md` for full descriptions.

### Medium

#### B-6: `stop` only breaks the innermost loop — no outer-loop break
`codegen_emit_break` emits a `JMP` into the current loop's patch stack. When loops are
nested, `stop` inside the inner loop always patches to the inner loop's exit. There is no
syntax or mechanism to break an outer loop.
**Fix required:** `stop N` labelled-break syntax (Stage 9). The break patch stack needs a
depth counter; `stop N` walks N levels and emits a JMP to the Nth outer loop's exit.
**Affects:** `codegen_emit_break` in `codegen/codegen.asm`
**Tracker:** `docs/issues.md` #22

#### B-10: Dict keys must be string literals — variable keys not supported
The dict handler emits a `call rt_sip(key_va, key_len)` with the key bytes embedded inline
in the code stream. There is no path for `d[x]` where `x` is a variable holding a runtime
string pointer.
**Fix required:** When the key token is `TOK_IDENT`, resolve the variable's runtime address
and pass it to the SipHash call instead of an inline literal.
**Affects:** Dict get/set handlers in `parser/parser.asm`
**Tracker:** `docs/issues.md` #23

#### B-11: No string concatenation and no `int → str` conversion
`output` routes `TYPE_STR` correctly, but there is no operator or builtin that joins two
strings or converts an integer to a string at runtime. `str s; :s = x + "px"` does not
work.
**Fix required:** Add `rt_str_cat` blob (Stage 9); add `str(expr)` cast syntax.
**Affects:** Expression parser, runtime
**Tracker:** `docs/issues.md` #24

#### B-12: `err` only accepts a string pointer — integer codes produce print + exit
`.err_stmt` calls `parse_expr` and checks `cur_type`. If not `TYPE_STR`, it routes through
the correct printer for the type and then calls `codegen_emit_exit1` (exit code 1). This
prevents the segfault but does not produce a formatted error message with the value.
**Fix required:** Proper int-to-string conversion so `err 42` emits the number as text in
the error output. Requires `str(expr)` cast (B-11 / issue #24).
**Affects:** `.err_stmt` in `parser/parser.asm`
**Tracker:** `docs/issues.md` #25

---

### Low

#### B-13: Dict runtime offsets are hardcoded constants
`RT_DICT_NEW_OFFSET`, `RT_DICT_SET_OFFSET`, and `RT_DICT_GET_OFFSET` in
`include/rex_defs.inc` are manually measured byte offsets into `rt_prq_blob`. Any
change to a preceding blob that shifts sizes will silently break dict operations.
**Fix required:** Compute offsets via a linker-resolved symbol difference.
**Affects:** `include/rex_defs.inc`
**Tracker:** `docs/issues.md` #3

#### B-14: `when` statement uses linear case search instead of jump table
Each `is N:` case emits a `mov`/`cmp`/`jz` sequence, making `when` with K cases O(K).
**Fix required:** Detect dense-integer ranges after collecting all case values and emit
an indirect jump table (`jmp [table + rax*8]`) instead of the linear chain.
**Affects:** `.when` in `parser/parser.asm`
**Tracker:** `docs/issues.md` #27

#### B-15: No sequence bounds check on element reads
Reading `seq[i]` emits `mov rax, [rbx + rcx*8 + 16]` with no check that `rcx < len`.
**Fix required:** Emit `cmp rcx, [rbx+8]; jae .oob_err` before the load.
**Affects:** Sequence subscript handler in `parser/parser.asm`
**Tracker:** `docs/issues.md` #28

---

## Stage 8 — Speed / Binary Quality
- [x] Maintain `< 1 KB` binary size target for compiled output (currently ~500 bytes for basic programs)
- [x] **O2**: Loop counter pinned to `r15` — eliminates all memory reads/writes for the induction variable
- [x] **O6**: Expression spill to `r10`/`r11` — replaces `push`/`pop` in expression evaluation with register moves
- [x] **O13**: Accumulator promotion to `r14` with retroactive-patch for read-before-write patterns
- [x] **O14**: Strength-reduction add fusion — `:accum = accum + pin` → `add r14, r15` (single instruction; hot path 6→2)

### Pending Optimisations

#### O15 — Strength-reduction fusion for `-`, `*`, `/` operators
Extend O14 to cover all four arithmetic operators on the `accum`+`pin` register pair:

| Pattern | Fused instruction | Encoding | Notes |
|---|---|---|---|
| `:a = a - i` | `sub r14, r15` | `4D 29 FE` | 3 bytes, direct |
| `:a = a * i` | `imul r14, r15` | `4D 0F AF F7` | 4 bytes, direct |
| `:a = a / i` | `mov rax,r14` + `cqo` + `idiv r15` + `mov r14,rax` | ~11 bytes | 4 instructions; idiv has no register-only 2-operand form |

All three share the same detection machinery as O14 (`sr_add_candidate`, `sr_add_rhs_is_pin`, `sr_add_patch_pos`). The only change is in `codegen_emit_sub_rax_rbx` / `codegen_emit_imul_rax_rbx` / `codegen_emit_div_rax_rbx`: check the same flags and emit the corresponding fused sequence instead of the generic `rax`/`rbx` form.

Subtraction needs care: Rex currently computes `rbx - rax` → `rax` (negate-then-add pattern). The fused `sub r14, r15` is `r14 -= r15`, which is `accum - pin`. Verify parser operand order matches before wiring.

**Expected gain:** same 6→2 (or 6→4 for division) on any tight accumulate-loop.

---

#### O27 — Skip push r12 / pop r12 for protos never called from inside another proto ✅ IMPLEMENTED
**Status:** DONE — post-compile finalize pass NOPs push r12 / pop r12 in callees that are only
ever invoked from outer scope. Removes 2 µops from the serial critical path per call.
**Result (B3):** ~381ms → ~260ms expected; confirmed by binary size drop of 4 bytes per affected proto.

---

#### O28 — Inner loop multi-variable register promotion (B7 fix)
**Problem:** B7 fib-iter inner loop `for :j in 0..80:` operates on vars `a`, `b`, `c` via global
memory loads/stores every iteration. GCC keeps all three in registers (0 loads, 0 stores). Rex
emits 3 loads + 3 stores per inner iteration = 800M memory ops for 10M×80 iterations.
**Fix:** At inner for-loop start, detect that local variables are only used within this loop body
(no uses outside after the loop). Allocate `rcx`/`rdx`/`rsi` as ephemeral register slots:
- Emit load-from-memory at loop entry: `mov rcx, [a]; mov rdx, [b]; mov rsi, [c]`
- Replace all `mov rax, [a_addr]` / `mov [a_addr], rax` body accesses with rcx/rdx/rsi equivalents
  using the same retroactive-patch technique as O13 (scan body bytes for `48 8B 04 25 addr32` / `48 89 04 25 addr32` patterns)
- Emit store-to-memory at loop exit: `mov [a], rcx; mov [b], rdx; mov [c], rsi`
**Challenge:** Must detect which variables are "loop-local" (modified inside the loop body and not
read from memory again outside before next write). Need a per-variable "modified-inside-loop" bitmap.
**Available registers:** `rcx`, `rdx`, `rsi` free when inside an inner loop (r15=pin, r14=outer accum, r12=proto param).
**Estimated gain:** B7 1.94× → near 1× vs C; closes the last major throughput gap.
**Affects:** `codegen_emit_for_start`, `codegen_emit_for_end`, new `loop_regprom_*` BSS tracking.

---

#### O29 — rbx intermediate register for recursive protocol local elimination (B6 fix)
**Problem:** Recursive fib emits `mov [rsp+0], rax` to spill `fib(n-1)` before calling `fib(n-2)`,
then `mov rax, [rsp+0]` to reload it for the final addition. At ~267M call levels, this is ~534M
extra memory round-trips that GCC eliminates by keeping the intermediate in a register.
**Fix:** When a push-style protocol has local variable slots (`frame_local_cnt > 0`), promote the
FIRST local slot to the callee-saved register `rbx`:
- Emit `push rbx` in the prologue immediately after `push r12` (new sub-state: `push_rbx_active`)
- Replace all `mov [rsp+0], rax` / `mov rax, [rsp+0]` for local slot 0 with `mov rbx, rax` / `mov rax, rbx`
  via retroactive-patch: scan leave_patch offsets for known 7-byte `48 89 44 24 00` (store to rsp+0)
  and `48 8B 44 24 00` (load from rsp+0) patterns; overwrite with `48 89 D8` (mov rax,rbx) + 4 NOPs
- Emit `pop rbx` in each epilogue after `add rsp` / before `pop r12`
**Safety:** Only applies when `proto_is_self_recursive == 1` AND `frame_local_cnt == 1` (exactly one
local; two or more needs rbx+rcx which collides with argument passing). Self-recursive flag already tracked (O20).
**Estimated gain:** B6 1.61× → ~1.1× vs C; eliminates ~534M memory ops from the recursion critical path.
**Affects:** `codegen_emit_frame_prologue`, `codegen_emit_leave`, `codegen_emit_regalloc_epilogue`,
new `push_rbx_active` BSS flag, retroactive store/load patch in `codegen_clear_frame`.

---

#### O30 — True proto inlining for tiny loop-free push-style protos (B3 near-parity with C)
**Problem:** Even with O27, the `call` + `ret` pair in B3 costs ~2 cycles round-trip due to RSB
lookup + pipeline drain. At 200M calls, 2 cycles × (1/2.3GHz) × 200M ≈ 174ms unavoidable overhead.
**Fix:** For protos where ALL of the following hold:
  1. `push_style_frame` was active (1-param)
  2. `frame_local_cnt == 0` (no locals)
  3. `proto_table[i+46] == 0` (no loops, O26 flag)
  4. Body size ≤ 24 bytes (fits in a cache line with the call site)
  5. `proto_needs_r12_save[i] == 0` (O27: not called from inside another proto)
Record the body's start and end positions in `proto_body_start[i]` / `proto_body_end[i]`.
At each call site, instead of emitting `call func_addr` (5 bytes):
  - Emit the body bytes directly (minus the 2-byte `push r12` and 2-byte `pop r12` which O27 already NOPs,
    minus the 7-byte NOP `sub rsp` block and 7-byte NOP `add rsp` block, minus the 1-byte `ret`)
  - The remaining body bytes are the pure computation (e.g., `lea rax, [rdi+1]` = 4 bytes for increment)
  - The arg is already in `rdi` (from the caller's `mov rdi, arg` before the call)
**Key insight:** After O27, the callee body for a 0-local 1-param proto is:
  `NOP NOP` | `mov r12, rdi` | `NOP×7` | [computation] | `NOP×7` | `NOP NOP` | `ret`
  The only live bytes are `mov r12, rdi` (3 bytes, free via rename) + [computation] + `ret` (1 byte).
  When inlining, skip the `ret`, replace all `r12` occurrences in computation with `rdi` refs (1-byte
  ModRM patch: r12 encoding `0x4C/0x44` → rdi encoding `0x48/0x00`), and copy the computation bytes.
**Estimated gain:** B3 ~260ms → ~87ms (C-level); eliminates the remaining call/ret latency entirely.
**Affects:** `codegen_finalize`, `proto_body_start[64]` / `proto_body_end[64]` new BSS in codegen.
**Complexity:** HIGH — requires encoding-aware r12→rdi substitution in copied body bytes. Every
  instruction that reads r12 as a source/base operand must be individually patched. Safe to limit
  to the patterns Rex actually generates (lea rax,[r12+N], add rax,r12, mov rax,r12, etc.).

---

#### P1 — rbp-relative stack frames for protocol locals (fib fix)
**The fib benchmark is 1.6× slower than C** (measured: 1147ms vs 713ms post-O26).
The root cause is push/pop of global-memory vars at each recursive frame boundary.

**Fix:** Allocate protocol locals on the real hardware stack via `rbp`-relative addressing:
- On protocol entry: `push rbp; mov rbp, rsp; sub rsp, N*8` (N = param count + local count).
- Map each param/local var to `[rbp - K*8]` instead of a `var_table` global slot.
- Load params from ABI registers (`rdi`, `rsi`, …) directly into `[rbp-8]`, `[rbp-16]`, etc.
- On `ret`: `mov rsp, rbp; pop rbp; ret` — single epilogue, no per-param pop loop.

This eliminates O(params × call-depth) global-memory accesses and replaces them with a single
`push rbp` / `pop rbp` pair, giving the CPU's stack engine a chance to optimise the frame.

**Note:** O29 (rbx intermediate) should be implemented first — it's lower-risk and targets the
same B6 bottleneck with only ~50 lines of change vs the full rbp-frame refactor (~300 lines).
**Estimated gain (O29):** B6 1.61× → ~1.1×. **(P1 on top):** B6 → ~1.0× (C-level).
**Affects:** `codegen_emit_prot_start`, `proto_emit_restore`, `codegen_find_frame_slot`, `parser.asm` prot_se loop.

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
- [x] `skip N`: Multi-level loop continue. `codegen_emit_skip` + `codegen_push_cont`/`codegen_pop_cont` implemented. `skip N` continues the Nth enclosing loop's condition check.
- [ ] `stop N`: Multi-level loop break. `stop N` breaks N levels of nested loops simultaneously. Requires depth counter in the break-patch stack.
- [x] Loop `else:`: Implemented — `for`, `while`, `repeat`, `each` all support `else:` via `__le` flag + `loop_else_flag_stack` in codegen.
- [x] `repeat N:`: Counted loop — hidden `__rp` counter var, `dec`+`jnz` at end, else: support.
- [ ] `match`: Structural pattern-matching. Sequential integers map to high-speed O(1) Jump Tables.
- [x] `unreachable` / `assert`: Crash boundary guards — `unreachable` emits `ud2`; `assert` emits `test`+`ud2` on false.

### IV. Bare-Metal Hardware Atoms & Intrinsics
- [x] `typeof`: Compile-time reflection returning built-in integer token for `cur_type`.
- [x] Explicit Type Casting:
    - [x] `int(float)` → `cvttsd2si r64, xmm`.
    - [x] `float(int)` → `cvtsi2sd xmm, r64`.
- [x] `bin`: Base-wrapper primitive (Base 2–16) for bitmasks/byte configs (e.g., `bin10`).
- [x] `abs`: `codegen_emit_abs_rax` implemented (`cmovs` pattern).
- [ ] `sign` / `clz`: Single-cycle hardware mapping to `lzcnt`/`bsr` — not yet implemented.
- [ ] `ceil` / `floor` / `fract`: SSE floating-point rounding (`roundsd`) and truncation.
- [ ] `real` / `imag` / `conj`: 128-bit XMM parallel component isolators and register bitmasking.
- [ ] `not`: Boolean/bitwise inversion — `xor rax, 1` for `bool`, `not rax` for `int`.
- [ ] `is` / `is not`: Semantic identity check — `cmp` + `sete`/`setne` + `movzx`.
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
