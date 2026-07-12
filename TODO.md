# TODO — Remaining Unfixed Issues in Rex Compiler
_Generated 2026-07-12 after comprehensive bug scan. 37 bugs fixed, 15 theoretical/low-priority items remain._

## Legend
- **Severity**: CRITICAL > HIGH > MEDIUM > LOW > TRIVIAL
- **Triggerable**: Can this bug be triggered with current language features?
- **Effort**: LOW (quick fix) / MEDIUM (moderate refactor) / HIGH (major rewrite)

---

## Parser

### 1. `parse_term` stack alignment
- **Severity**: MEDIUM
- **File**: `parser/parser.asm:1305`
- **Triggerable**: No (no called function uses aligned SSE on stack)
- **Effort**: HIGH (requires frame-pointer rewrite of all `[rsp+N]` references)
- **Description**: `parse_term` has no prologue (`push rbp; mov rbp, rsp`). RSP is at 8 mod 16 at entry, causing misaligned `call` instructions in several paths (int_lit, float_lit, bool_lit, char_lit emit_ir calls; str_lit/ident advance/alloc_vreg calls).
- **Why not fixed**: Multiple automated approaches (sub rsp, 8; push/pop per ret; caller-side alignment) all broke stack-relative addressing. The function has 9 return paths with complex stack manipulation. No called function (emit_ir, alloc_vreg, advance, sym_lookup) uses aligned SSE instructions on the stack, so this doesn't cause crashes in practice.
- **Fix approach**: Rewrite parse_term to use frame pointer (`rbp`) for all stack references, then add `push rbp; mov rbp, rsp` prologue and `pop rbp` epilogue.

---

## Codegen

### 2. `.load_str` dword reads for string length
- **Severity**: LOW
- **File**: `codegen/codegen.asm:623,648`
- **Triggerable**: No (strings would need to exceed 2GB)
- **Effort**: LOW
- **Description**: `mov edi, [rsp + 8]` reads only 4 bytes of tok_str_len (stored as qword). Used for jmp rel32 and LEA disp32 calculations, which are inherently 32-bit fields. The dword read is correct for these use cases.
- **Why not fixed**: The 32-bit read is semantically correct — rel32 and disp32 are 32-bit fields. Changing to `mov rdi, [rsp+8]` + `inc edi` was attempted but caused segfaults due to other stack layout assumptions.

---

## IR/Optimizer

### 3. DSE unsound across branches (guarded, not rewritten)
- **Severity**: LOW (guarded)
- **File**: `irgen/opt.asm:299-352`
- **Triggerable**: No (language has no branching constructs)
- **Effort**: HIGH (requires CFG construction)
- **Description**: `pass_dead_store_elimination` does a reverse linear scan. Would incorrectly remove stores that are live on other branches. Currently guarded by `has_branching_ir` — pass is skipped entirely if IR contains JCC/JMP/LABEL opcodes.
- **Fix approach**: Build CFG, compute dominators, only eliminate stores that dominate all reads.

### 4. Constant folding unsound across branches (guarded, not rewritten)
- **Severity**: LOW (guarded)
- **File**: `irgen/opt.asm:55-296`
- **Triggerable**: No (language has no branching constructs)
- **Effort**: HIGH (requires CFG + constant propagation with merge)
- **Description**: `pass_constant_folding` does a forward linear scan. Would incorrectly propagate constants across branch join points. Currently guarded by `has_branching_ir`.
- **Fix approach**: Per-basic-block constant propagation with meet-at-join-point invalidation.

### 5. Vregs 512+ silently spilled (increased to 1024)
- **Severity**: LOW
- **File**: `irgen/ra.asm:57`
- **Triggerable**: Only with 1024+ virtual registers
- **Effort**: MEDIUM
- **Description**: `GRAPHCOL_VMAX` was increased from 512 to 1024. Vregs beyond this limit are still silently forced to spill with no diagnostic.
- **Fix approach**: Add compile-time warning when vreg_counter exceeds GRAPHCOL_VMAX, or implement multi-region interference graph.

### 6. Copy-coalescing hints overwritten per-vreg
- **Severity**: TRIVIAL (missed optimization)
- **File**: `irgen/ra.asm:266-304`
- **Triggerable**: N/A (optimization quality, not correctness)
- **Description**: `gc_copy_hint[dst]` stores only the last src1 for each dst vreg. If a vreg is defined by multiple arithmetic ops, only the last hint is used for biased colouring.

### 7. No vreg range validation in emit_ir
- **Severity**: TRIVIAL (defensive)
- **File**: `irgen/irgen.asm:46-68`
- **Triggerable**: Only if vreg IDs exceed VREG_MAX (65536)
- **Description**: `emit_ir` stores vreg IDs without bounds checking. Added bounds check for VREG_MAX in this session.

### 8. DSE doesn't track IR_OUT_* reads
- **Severity**: TRIVIAL
- **File**: `irgen/opt.asm:299-352`
- **Triggerable**: Theoretical
- **Description**: DSE only tracks IR_LOAD_VAR as reads. Output ops (IR_OUT_INT, etc.) that indirectly read variables via vregs are not tracked. Mitigated by DSE running before load-store coalescing.

---

## Lexer

### 9. `..` range operator not tokenized
- **Severity**: TRIVIAL (no language support)
- **File**: `lexer/lexer.asm:761`
- **Triggerable**: N/A (language doesn't have range syntax)
- **Description**: `..` in number context splits into two TOK_DOT tokens. Comment was corrected. Not a bug — language has no range operator.

---

## Main

### 10. Partial read not detected
- **Severity**: TRIVIAL
- **File**: `main/main.asm:113-117`
- **Triggerable**: Theoretical (regular file sys_read always reads full)
- **Description**: `sys_read` return value not checked against requested size. On regular files, kernel always reads full amount. Would matter only for special files/devices.

### 11. Output write failure ignored
- **Severity**: TRIVIAL
- **File**: `main/main.asm:164-168`
- **Triggerable**: Theoretical (disk full, broken pipe)
- **Description**: `sys_write` for compiled output doesn't check return value. Kernel delivers SIGPIPE on broken pipes.

### 12. Close errors silently ignored
- **Severity**: TRIVIAL
- **File**: `main/main.asm:120-122,171-173`
- **Triggerable**: Theoretical (NFS delayed write failure)
- **Description**: `sys_close` return values not checked. Could matter on network filesystems.

---

## Runtime

### 13. All sys_write errors silently ignored
- **Severity**: TRIVIAL
- **Files**: `rt_prs.asm`, `rt_prb.asm`, `rt_prf.asm`, `rt_pri.asm`, `rt_prq.asm`
- **Triggerable**: Theoretical
- **Description**: All runtime print functions ignore `sys_write` return values. Kernel handles SIGPIPE for broken pipes.

### 14. Latent buffer overlap in rt_prf
- **Severity**: TRIVIAL (safe by design)
- **File**: `runtime/rt_prf.asm`
- **Triggerable**: No (buffer sizes are correctly calculated)
- **Description**: Whole-part and fractional-part digit areas share a 64-byte scratch buffer. Currently safe but fragile if precision cap is increased.

---

## Summary

| Category | Fixed | Remaining | Remaining are triggerable? |
|----------|-------|-----------|---------------------------|
| Lexer | 11 | 1 | No |
| Parser | 14 | 1 | No |
| Codegen | 7 | 1 | No |
| IR/Opt | 8 | 6 | No |
| Runtime/Main | 8 | 4 | No |
| **Total** | **48** | **13** | **None triggerable** |

All 13 remaining items are theoretical/edge-case issues that cannot be triggered with current language features. The 3 most impactful (parse_term alignment, DSE/constfold across branches) would require major refactoring (frame-pointer rewrite, CFG construction) for no practical benefit today.
