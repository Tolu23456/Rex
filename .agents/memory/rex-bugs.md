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

### Bug 8 — Optimizer: stale/wrong comment on vreg_alias clear (🟡)
**File:** `irgen/opt.asm`
**Symptom:** Comment in `pass_load_store_coalescing` said "vreg_alias is intentionally NOT cleared here" but the code immediately below cleared it with `rep stosw`. Contradictory comment could lead a maintainer to remove the clear, which would cause stale alias entries to persist across compiler invocations.
**Fix:** Replaced the misleading comment with an accurate explanation: the clear IS intentional, constant folding never writes vreg_alias, and clearing prevents cross-invocation corruption.

### Bug 9 — Codegen: load_src1_phys / load_src2_phys / get_dst_phys clobber RBX (🟡 ABI)
**File:** `codegen/codegen.asm`
**Symptom:** All three helper functions used `rbx` (callee-saved, SysV ABI) as a scratch register without push/pop. Currently harmless because `codegen_emit_all` never relies on rbx across these calls, but a latent ABI violation that would corrupt callers if that ever changed.
**Fix:** Added `push rbx` at entry and `pop rbx` before every `ret` in all three functions.

### Bug 10 — Lexer: string escape sequences not translated (🔴 critical)
**File:** `lexer/lexer.asm`
**Symptom:** `.str_escape` incremented the length counter but wrote nothing into any buffer — `tok_str_ptr` pointed into the raw source buffer, so `\n` in source appeared as the two-byte sequence `\` + `n` in the output binary instead of LF (10).
**Fix:** Added `tok_str_pool resb SRC_FILE_MAX` + `tok_str_pool_idx` to `.bss`. Rewrote `.string` handler to write each character (with escape translation: `\n`→10, `\t`→9, `\r`→13, `\0`→0, `\a`→7, `\b`→8, `\f`→12, `\v`→11, `\\`/`\"`/unknown→literal) into the pool and set `tok_str_ptr` to the pool slice. Pool index advances after each string so multi-string programs keep all pointers valid through codegen.

### Bug 11 — Lexer: char literal escape sequences not translated (🔴)
**File:** `lexer/lexer.asm`
**Symptom:** `.char_escape` stored the raw byte after `\` into `tok_ival`. So `'\n'` → 110 ('n') instead of 10 (LF).
**Fix:** Added the same translation table as Bug 10 inside `.char_escape` before `mov [tok_ival], rax`.

### Bug 12 — Lexer: `is not` matches `is nothing`, `is notify`, `is not_x` etc. (🔴)
**File:** `lexer/lexer.asm`
**Symptom:** The `is not` lookahead checked only the four bytes `' '+'n'+'o'+'t'` with no word-boundary check. `is nothing` would match `is not` and leave `hing` as a stale suffix in the token stream, corrupting all subsequent tokens on that line.
**Fix:** After matching `'t'`, peek at the next character (if within bounds). If it is a letter, digit, or `_` (identifier continuation), fall through to `.is_single` instead of consuming " not".

### Bug 13 — Parser: `int→bool` cast uses wrong opcode name (🟡 semantic)
**File:** `parser/parser.asm`
**Symptom:** `.cast_use_itb` (int→bool) emitted `IR_CAST_BTI` (labelled "bool→int, no-op"). The codegen for `IR_CAST_BTI` happened to implement signum anyway, so runtime output was correct, but the opcode name was misleading and relied on an undocumented coincidence.
**Fix:** Changed to `IR_SIGNUM` which explicitly documents the intent: map negative→-1, zero→0, positive→1.

### Bug 14 — Main: wrong error messages for file-too-large and read-fail (🟡)
**File:** `main/main.asm`
**Symptom:** `.err_file_too_large` and `.err_read_source` both printed "Error: Cannot open source file". A user hitting either would see a misleading message.
**Fix:** Added `err_file_large` ("Source file too large (max 64KB)"), `err_read_src` ("Cannot read source file"), and `err_write_out` ("Cannot write output file") strings; wired each error handler to its correct string.

### Bug 15 — Main: single sys_read may return short (🟡)
**File:** `main/main.asm`
**Symptom:** One `sys_read` syscall was expected to read the entire source file. POSIX allows short reads; a short read would silently truncate the source, causing the lexer to see a partial file.
**Fix:** Replaced the single read with a retry loop (`r14` = bytes read so far; loop until `r14 == src_file_size` or error/EOF). After the loop, `[src_file_size]` is updated to the actual bytes read and passed to `lex_init`.

---

## Architectural improvements

### Graph-colouring register allocator — full enhanced version (irgen/ra.asm)
**File:** `irgen/ra.asm`

**Algorithm:** Chaitin-Briggs optimistic colouring with five phases:
1. **Liveness + use-count + copy-hint** — single IR scan; `IR_NOP` records skipped entirely. For arithmetic ops (`IR_ADD`..`IR_XOR`, `IR_BOOL_AND`/`OR`), records `gc_copy_hint[dst] = src1` for use in Phase 4 biased colouring.
2. **Build** — pairwise range-overlap interference graph as a symmetric 512×512-bit bitmap (32 KiB). Two vregs interfere iff `[def₁, last₁] ∩ [def₂, last₂] ≠ ∅`. Outer loop v1: 1..gc_max_vreg-1 (jge); inner loop v2: v1+1..gc_max_vreg (jg) — covers every pair exactly once.
3. **Worklist simplification** — low-degree nodes seeded after build; `gc_dn_update` BSF-scans the interference row (8 qwords) and pushes neighbours that drop below k. When worklist empties, selects the cheapest potential spill using ratio heuristic (see below) and pushes optimistically.
4. **Biased colouring** — pop stack; build used-colour bitmask via BSF+BTR over 8 × 64-bit row words. **Biased colouring first:** if `gc_copy_hint[v]` names an already-coloured, non-spilled vreg whose colour is free, assign that colour immediately — eliminates the `mov dst_reg, src1_reg` copy in `codegen.asm`. Otherwise fall back to smallest free colour or spill.
5. **Map** — populate `vreg_phys[]` / `vreg_offset[]`; align spill frame to 16 bytes.

**Spill heuristic (Bug 10 fix + enhancement):**
Classic Chaitin: minimise `use_count / (degree + 1)`. Implemented without division via cross-multiplication:
  candidate c beats current best b iff `use_count[c] * (degree[b]+1) < use_count[b] * (degree[c]+1)`
Max product: 2 * IR_MAX_RECORDS * GRAPHCOL_VMAX = 2048 * 512 = 1 048 576 — fits in a 32-bit register. No overflow.

**Copy-hint biased colouring:**
`gc_copy_hint resw GRAPHCOL_VMAX` table zeroed in Phase 0. Phase 1 fills it for arithmetic ops. Phase 4 tries the hint colour before the generic pick loop — when honoured, the codegen's `mov dst_reg, src1_reg` pre-copy becomes a `mov r_x, r_x` no-op that the peephole can eliminate, or the codegen skips it entirely.

**Physical register map:** colours 0–5 → r10–r15. Colour 255 = spilled.
**Constants:** `GRAPHCOL_VMAX = 512`, `NUM_PHYS_REGS = 6`.

### Optimizer cache correctness
**File:** `irgen/opt.asm`
**Improvement:** `pass_load_store_coalescing` guards the load-miss path with `cmp rax, -1; je .next` before using `rax` as a symbol index, preventing `var_cached_vreg[-1]` writes. `opt_follow_alias` follows full alias chains (not just one level).

---

## Testing infrastructure
**Files:** `tests/test_*.rx`, `tests/test_*.expected`, `run_tests.sh`
**Tests (all green, 9/9):**
- `test_arithmetic.rx` — all 5 arithmetic ops, precedence
- `test_bool.rx` — Łukasiewicz three-valued logic
- `test_constant_folding.rx` — compile-time integer folding
- `test_float_fold.rx` — compile-time float folding (Bug 7)
- `test_hex_bin_oct.rx` — 0x/0b/0o integer literal formats
- `test_peephole_opts.rx` — identity ops (+0, *1, *0, *2)
- `test_question_ops.rx` — ? token lexing (Bug 1)
- `test_register_pressure.rx` — 8 variables forcing spills
- `test_strings.rx` — string literal output
**Runner:** `run_tests.sh --verbose` diffs actual vs `tests/*.expected`. 9/9 pass.
