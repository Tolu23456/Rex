---
name: Rex compiler bug fixes
description: Catalogue of all bugs found and fixed in the Rex NASM compiler, plus architectural improvements.
---

## Fixed bugs

### Bug 1 — Lexer: double read_char in .question handler (🔴 critical)
**File:** `lexer/lexer.asm`
**Symptom:** After reading `?`, the handler called `read_char` a second time, consuming the character immediately following `?`. This broke `?` and `??` tokenization and corrupted all subsequent tokens.
**Fix:** Removed the redundant `call read_char`; the `?` was already consumed by the generic operator dispatch block. Now uses `peek_char` + conditional consume for `??` detection only.

### Bug 2 — Optimizer: peephole aliases never applied (🔴 critical)
**File:** `irgen/opt.asm`
**Symptom:** `pass_peephole` wrote `vreg_alias` entries for identity ops (`+0`, `*1`, etc.) but the downstream IR was never updated to use the canonical vreg. NOP'd instructions left their dst vregs unwritten → garbage at runtime.
**Fix:** Added `pass_apply_aliases` (called last in `run_optimizations`) that follows the full alias chain for every src1/src2 reference across all IR records.

### Bug 3 — Codegen: spurious spill writes (🔴 critical)
**File:** `codegen/codegen.asm`
**Symptom:** `IR_STORE_VAR`, `IR_OUT_*`, and `IR_HALT` handlers called `store_dst_spill` without first calling `get_dst_phys` to reset `dst_spilled_vreg`. A stale vreg ID from the previous instruction caused a phantom `mov [rbp+offset], r14` write, corrupting live values under register pressure.
**Fix:** Added `mov dword [dst_spilled_vreg], 0` at the top of each handler and removed the trailing `call store_dst_spill` from those same handlers.

### Bug 4 — Lexer: check_empty_line clobbers RBX (🟡 dormant ABI violation)
**File:** `lexer/lexer.asm`
**Symptom:** `check_empty_line` used `rbx` (callee-saved in SysV ABI) without push/pop. Any caller relying on `rbx` across this call would see corruption.
**Fix:** Added `push rbx` / `pop rbx` at entry/exit of `check_empty_line`.

### Bug 5 — Parser: sym_table-full error uses wrong message (🟡)
**Files:** `parser/parser.asm`, `parser/symtab.asm`
**Symptom:** When the symbol table is full, `sym_add` returns -1 (correct). The parser's `.full_error` and `.enum_full_err` labels both printed `err_dup_decl` ("Duplicate variable declaration") instead of a "table full" message.
**Fix:** Added `err_sym_full db "Compile Error: Symbol table full (too many variables)", 0` to parser.asm's data section, and updated both error labels to use it.

### Bug 7 — Optimizer: IR_LOAD_FIMM not tracked in constant folding (🟡)
**File:** `irgen/opt.asm`
**Symptom:** Float immediate loads were not recorded in `vreg_is_const[]`, so float constants were never folded. Programs with `float z = 1.5 + 2.5` emitted actual SSE arithmetic at runtime instead of a constant.
**Fix:** Added a `handle_load_fimm` handler in `pass_constant_folding` that stores the bit pattern in `vreg_const_val[]`. Added SSE2 float arithmetic folding (`addsd`/`subsd`/`mulsd`/`divsd`) in `handle_arith` when `type == TYPE_FLOAT`.

---

## Architectural improvements

### Graph-colouring register allocator — improved version (irgen/ra.asm)
**File:** `irgen/ra.asm` — full rewrite (replaces prior Chaitin-Briggs draft)

**Algorithm:** Chaitin-Briggs optimistic colouring with five phases:
1. **Liveness + use-count** — single IR scan; `IR_NOP` records skipped entirely (eliminated instructions must not extend live ranges or inflate use counts).
2. **Build** — pairwise range-overlap interference graph as a symmetric 512×512-bit bitmap (32 KiB). Two vregs interfere iff `[def₁, last₁] ∩ [def₂, last₂] ≠ ∅`.
3. **Worklist simplification** — O(V+E): low-degree nodes seeded into a LIFO worklist after the graph is built; when a neighbour's degree drops below `k` in `gc_dn_update`, it is pushed automatically. When the worklist empties, the cheapest potential spill is selected (minimum `use_count`, tiebreak maximum current degree) and pushed optimistically.
4. **Colouring** — pop the stack; build a used-colour bitmask by scanning the vreg's row with BSF+BTR over 8 × 64-bit words; assign the smallest free colour or mark as spilled.
5. **Map** — populate `vreg_phys[]` / `vreg_offset[]`; align spill frame to 16 bytes.

**Key improvements over the initial draft:**
- `gc_dn_update` uses BSF-based 512-bit row scan (8 qword iterations) instead of O(N) linear scan with one `gc_interf_test` call per vreg.
- Same BSF scan used in Phase 4 colouring (no `gc_interf_test` call at all).
- `gc_interf_test` function removed entirely.
- `gc_orig_degree` table removed; replaced by `gc_use_count` for spill cost.
- `gc_remaining` counter maintained incrementally (no per-iteration full scan).
- NOP-skipping in Phase 1 prevents phantom vregs from cluttering the graph.
- Simplification drops from O(V²) per node to O(V+E) total.

**Physical register map:** colours 0–5 → r10–r15. Colour 255 = spilled.
**Constants:** `GRAPHCOL_VMAX = 512`, `NUM_PHYS_REGS = 6`.

**Why:** The initial draft recomputed the remaining-node count on every simplification iteration (O(V²)) and called `gc_interf_test` for each of the V candidates on every neighbour-decrement (O(V) function calls per decrement). For large programs these costs compound. The worklist + BSF row scan make both operations proportional to the actual graph edges rather than V².

### Optimizer cache correctness
**File:** `irgen/opt.asm`
**Improvement:** `pass_load_store_coalescing` now guards the load-miss path with `cmp rax, -1; je .next` before using `rax` as a symbol index, preventing `var_cached_vreg[-1]` writes. `opt_follow_alias` follows full alias chains (not just one level).

---

## Testing infrastructure
**Files:** `tests/test_*.rex`, `tests/test_*.expected`, `run_tests.sh`
**Tests (all green, 9/9):**
- `test_arithmetic.rex` — all 5 arithmetic ops, precedence
- `test_bool.rex` — Łukasiewicz three-valued logic
- `test_constant_folding.rex` — compile-time integer folding
- `test_float_fold.rex` — compile-time float folding (Bug 7)
- `test_hex_bin_oct.rex` — 0x/0b/0o integer literal formats
- `test_peephole_opts.rex` — identity ops (+0, *1, *0, *2)
- `test_question_ops.rex` — ? token lexing (Bug 1)
- `test_register_pressure.rex` — 8 variables forcing spills
- `test_strings.rex` — string literal output
**Runner:** `run_tests.sh --verbose` diffs actual vs `tests/*.expected`. 9/9 pass.
