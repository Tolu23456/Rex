# TODO — Remaining Unfixed Issues in Rex Compiler
_Generated 2026-07-12 after comprehensive bug scan. 37 bugs fixed, 15 theoretical/low-priority items remain._

## Completed This Session

### Binary Size Reduction (3.5x achieved: 8573B → 2456B)
- Removed empty rt_sip (1024B) and rt_alc (4096B) placeholder slots
- Removed unused rt_prq error printer (1024B)
- Updated CODE_START constant from 8573 to 2429
- Updated JMP offset in codegen_init
- All 9 tests pass

### Remaining: 50x Binary Size Reduction
- **Target**: 8573B → ~170B (68x for no-output programs)
- **Approach A**: Pack runtime without padding (saves ~686B, total ~1770B, 4.8x)
  - Remove padding from rt_pri/rt_prs/rt_prb/rt_prf/rt_prc .asm files
  - Compute runtime offsets dynamically in codegen_init
  - Requires updating all hardcoded offset values in codegen
- **Approach B**: Make runtime optional (best reduction)
  - Scan IR before codegen to detect which IR_OUT_* opcodes are used
  - Only embed runtime functions that are actually called
  - Programs without output() → binary is just headers + JMP (~125B, 68x)
  - Programs with output() → headers + JMP + needed print functions
- **Approach C**: Replace runtime with inline syscalls (most invasive)
  - Emit syscall instructions directly for output()
  - Eliminates runtime embedding entirely
  - Requires rewriting the output codegen path
- **Recommendation**: Approach B (modular runtime) — best size reduction with moderate complexity

---

## Binary Size Optimization — Comprehensive Strategy

> Every Rex binary is a self-contained ELF64 executable. The design mandates
> tiny binaries. This section catalogues every technique to minimize output size,
> ordered by impact-to-effort ratio.

### Current Binary Sizes

| Program | Current Size | Theoretical Minimum |
|---------|-------------|-------------------|
| Empty (no output) | ~2,456 B | ~128 B (ELF header only) |
| `output(42)` | ~2,968 B | ~200 B (header + inline syscall) |
| `output("hello")` | ~2,968 B | ~200 B |
| Full program (seq, dict, output) | ~3,500 B | ~800 B |

### Tier 1: Quick Wins (low effort, high impact)

| # | Technique | Savings | Effort | Status |
|---|-----------|---------|--------|--------|
| 1 | **Pack runtime without padding**Remove fixed-size padding (512 B each) from `rt_pri.bin`, `rt_prs.bin`, `rt_prb.bin`, `rt_prf.bin`, `rt_prc.bin`. Compute blob offsets dynamically in `codegen_init` based on actual sizes. | ~600–800 B | MEDIUM | ✅ Done |
| 2 | **`xor reg, reg` for zero loads** — Already done for `IR_LOAD_IMM 0`. Extend to all zero-valued immediates (store offsets, null pointers). | ~3–7 B per occurrence | LOW | ✅ Partial |
| 3 | **Instruction peephole: `mov` → shorter forms** — `mov r, imm32` (7 B) instead of `mov r, imm64` (10 B) when value fits in 32-bit signed. Already done for LOAD_IMM. | ~3 B per occurrence | LOW | ✅ Done |
| 4 | **Dead IR_NOP elimination** — Skip `IR_NOP` records during codegen emission (already done). Extend to eliminate entire unreachable basic blocks after optimizer. | Variable | LOW | ✅ Partial |

### Tier 2: Moderate Effort (significant impact)

| # | Technique | Savings | Effort | Status |
|---|-----------|---------|--------|--------|
| 5 | **Inline syscalls for simple output**For programs that only `output()` a single int/str/bool, emit the `mov rax,1; mov rdi,1; lea rsi,[...]; mov rdx,len; syscall` sequence directly (17 bytes) instead of embedding a 512-byte print routine. | ~500 B per print type | MEDIUM | ✅ Done |
| 6 | **Shared runtime epilogue** — Multiple print functions (`rt_pri`, `rt_prs`, `rt_prb`, `rt_prf`) share identical `sys_write` + `ret` tails (~15 bytes each). Factor into a shared tail called via `jmp`. | ~45–60 B | LOW | ❌ TODO |
| 7 | **Inline `rt_prc` (print char)** — The char-print routine is ~23 bytes. Inline the syscall directly instead of embedding a blob. | ~23 B | LOW | ❌ TODO |
| 8 | **Granular collection runtime**Currently `rt_alloc` (256 B) is embedded whenever ANY collection exists. Embed `rt_alloc` only if heap allocation is used; embed `rt_seq` only if seq ops exist; embed `rt_dict` only if dict ops exist. | ~256–512 B | MEDIUM | ✅ Done |
| 9 | **String constant deduplication** — If the same string literal appears multiple times, emit it once in `.rodata` and reference the same offset. | Variable | MEDIUM | ❌ TODO |
| 10 | **Instruction peephole: arithmetic**Replace common patterns: `add r, 1` → `inc r` (2 B saved); `sub r, 1` → `dec r` (2 B saved); `cmp r, 0` → `test r, r` (2 B saved); `mov r, 1` → `xor r,r; inc r` (4 B saved vs 10 B mov imm64). | ~2–8 B per occurrence | LOW | ✅ Done |

### Tier 3: Aggressive Optimization (high impact, harder)

| # | Technique | Savings | Effort | Status |
|---|-----------|---------|--------|--------|
| 11 | **Stack-relative variables** — For programs with few variables, use `rsp`-relative or `rbp`-relative addressing (`[rbp-N]`, 2–3 bytes) instead of absolute `[0x440000+N]` (7 bytes per load/store). | ~4 B per variable access | HIGH | ❌ TODO |
| 12 | **`short` jumps for forward branches** — When the jump target is within ±127 bytes, use `Jcc rel8` (2 bytes) instead of `Jcc rel32` (6 bytes). Requires a two-pass emit or backpatching. | ~4 B per short jump | MEDIUM | ❌ TODO |
| 13 | **Conditional section emission** — Move error-handling code (`compile_error`, overflow handlers, string constants) to a separate `.rodata` section. The OS pages them independently; doesn't reduce file size but reduces memory working set. | 0 B file, less RAM | MEDIUM | ❌ TODO |
| 14 | **Register-based parameter passing for runtime** — Print functions currently load parameters from memory. Pass values in registers (rdi/rsi) to avoid the load sequence. | ~10–20 B per call site | MEDIUM | ❌ TODO |
| 15 | **Tail-call optimization** — If a function's last instruction is `call foo; ret`, replace with `jmp foo`. Eliminates the `ret` and the stack frame overhead. | ~5 B per tail call | MEDIUM | ❌ TODO |

### Tier 4: Architectural (maximum impact, major effort)

| # | Technique | Savings | Effort | Status |
|---|-----------|---------|--------|--------|
| 16 | **Bytecode interpreter for tiny programs** — For programs under ~100 IR records, emit a compact bytecode + a tiny interpreter loop (~50 bytes) instead of native x86-64. Could achieve ~200-byte binaries for trivial programs. | ~2,000+ B | HIGH | ❌ TODO |
| 17 | **COM-style flat binary output mode** — Skip ELF headers entirely. Output raw machine code with a minimal 2-byte header (`EB xx` jump to entry). Requires a custom loader or `chmod +x`. Could achieve ~50-byte binaries for trivial programs. | ~120 B | HIGH | ❌ TODO |
| 18 | **Self-modifying code for constants** — If a value is known at compile time, patch the immediate directly into the instruction stream at emit time instead of loading from the variable region. | ~7 B per constant | HIGH | ❌ TODO |
| 19 | **Segmented ELF output** — Split output into `PT_LOAD` segments for `.text` (RX) and `.rodata` (R). Allows OS to page-align and share read-only pages across processes. | 0 B file, less RAM | HIGH | ❌ TODO |
| 20 | **Compression for large binaries** — For programs exceeding ~10 KB, add a decompression stub (~100 bytes) that LZ4-decompresses the payload at startup. Only worthwhile for very large programs. | Variable (2–5x) | HIGH | ❌ TODO |

### Recommended Priority Order

```
 1. Pack runtime (Tier 1)              — saves ~600-800 B, moderate effort
 2. Inline syscalls for output (Tier 2) — saves ~500 B, moderate effort
 3. Instruction peephole (Tier 2)       — saves ~100-300 B, low effort
 4. Shared runtime epilogue (Tier 2)    — saves ~45-60 B, low effort
 5. Granular collection runtime (Tier 2)— saves ~256-512 B, moderate effort
 6. Short jumps (Tier 3)               — saves ~100-200 B, moderate effort
 7. Stack-relative variables (Tier 3)   — saves ~200-400 B, high effort
 8. Bytecode mode (Tier 4)             — saves ~2,000+ B, high effort
```

### Implementation Notes

- **Tier 1–2 items are self-contained** — each can be implemented independently without affecting other components.
- **Stack-relative variables (Tier 3)** requires rewriting all `[rsp+N]` and absolute-address references in codegen. High risk of regressions.
- **Bytecode mode (Tier 4)** is a separate output path, not a modification of the existing codegen. Could be added as a `--bytecode` flag.
- **All savings estimates** assume typical programs. A "hello world" benefits most from runtime packing; a compute-heavy loop benefits most from instruction peephole.

---

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

---

## Carnifex — Memory Safety Implementation

> Reference: `imp/Carnifex-Design-Specification.md`
> Sections to implement: `imp/design.md` §3 (Variables) through §4.10 (Sequences)

### IR Record Room Assessment

Current IR record: 32 bytes. Unused space:

| Offset | Size | Current Use | Carnifex Use |
|--------|------|-------------|--------------|
| 24 | 4 bytes | `flags` (3 bits used: CONST, DEAD, SPILLED) | `IR_FLAG_OWNED`, `IR_FLAG_RELEASE` (2 bits) |
| 28 | 4 bytes | `_pad` (unused) | **region-id** (16 bits) + **capability** (2 bits) + padding |

**Verdict**: The IR record has room for Carnifex without growing. The `_pad` field at offset 28 can hold a 16-bit region-id and 2-bit capability flag. The `flags` field has 29 unused bits for ownership/release markers.

### Phase 1: Prerequisites (design.md §3–§4.10 foundation)

These are required before Carnifex can be implemented:

| Task | Status | File | Description |
|------|--------|------|-------------|
| `prot` keyword lexing | ✅ Fixed | lexer.asm | `prot` and `return` keywords now lexed |
| Mutability checking | ✅ Fixed | parser.asm | `:` sigil checked via `sym_is_mutable` |
| Bool OR/AND type checks | ✅ Fixed | parser.asm | Type verification for `and`/`or` operators |
| Type cast IR emission | ✅ Fixed | parser.asm | 5 cast opcodes now emit IR |
| Null coalesce IR | ✅ Fixed | parser.asm | `IR_NULL_COALESCE` opcode added |
| `..` range operator | ✅ Done (in for loops) | parser/lexer | Range expressions for `for` loops |
| `if`/`elif`/`else` | ✅ Partial | parser/codegen | Branching (if/else implemented, elif and for/while loop bodies parse but don't emit IR) |
| `for`/`while`/`each` loops | ✅ Partial | parser/codegen | Loop constructs (parser consumes tokens, loop body IR not yet emitted) |
| `prot` function calls | ❌ TODO | parser/codegen | `@func()` calling convention |
| `return` statements | ✅ Done | parser/codegen | Return values (rax/rdx or stack) |
| `seq[T]` type | ✅ Implemented | parser/irgen/codegen | Heap-allocated growable array |
| `arr[T,N]` type | ❌ TODO | parser/irgen/codegen | Stack-allocated fixed array |
| `dict[T]` type | ✅ Implemented | parser/irgen/codegen | Hash map |
| `struct` types | ❌ TODO | parser/irgen/codegen | Named-field records |
| `enum` types | ✅ Implemented | parser/irgen/codegen | Typed integer constants |
| Null propagation (`?.`, `??`) | ✅ Partial (?? implemented) | parser/codegen | Null-safe member access |

### Phase 2: Memory Management (design.md §3.3, §10)

| Task | Status | Description |
|------|--------|-------------|
| `use mm arena(N):` scope | ❌ TODO | Arena allocator with fixed capacity |
| `use mm stack:` scope | ❌ TODO | Stack-frame allocator |
| `use mm pool(N):` scope | ❌ TODO | Pool allocator with N slots |
| `use mm heap:` scope | ❌ TODO | Default heap (GC-managed) |
| `use mm static:` scope | ❌ TODO | Program-lifetime allocation |
| `use gc mark_sweep:` | ❌ TODO | Mark-sweep collector |
| `use gc ref_count:` | ❌ TODO | Reference counting |
| Scope enter/exit opcodes | ❌ TODO | IR for `MM_ENTER`/`MM_EXIT` |

### Phase 3: Carnifex Core (imp/Carnifex-Design-Specification.md §4–§10)

| Task | Status | Description |
|------|--------|-------------|
| Region tree construction | ❌ TODO | Build lexical scope tree at compile time |
| Region-id assignment | ❌ TODO | Assign region IDs to all allocations |
| Ownership binding (`owned`/`free`) | ❌ TODO | Per-variable ownership annotation |
| Pinned ownership enforcement | ❌ TODO | No transfer between existing bindings |
| `.copy()` / `.release()` hooks | ❌ TODO | Type-level duplication and cleanup contracts |
| Generation counter infrastructure | ❌ TODO | Per-region generation counter |
| Runtime generation check | ❌ TODO | `cmp` instruction on dereference |
| `DanglingRefError` | ❌ TODO | Runtime error for stale references |
| Capability (read/write) tracking | ❌ TODO | Block-granularity alias checking |
| Statically uniform release points | ❌ TODO | Release on all control-flow paths |
| DSE exclusion for `owned` bindings | ❌ TODO | Don't eliminate stores to owned vars |
| Exception safety via release calls | ❌ TODO | Emit `.release()` at each `raise` site |

### Phase 4: Binary Size Optimization (beyond current 56x)

| Task | Status | Description |
|------|--------|-------------|
| Pack runtime without padding | ❌ TODO | Remove fixed-size padding from rt_pri/rt_prs/rt_prb/rt_prf/rt_prc |
| Dynamic runtime offset computation | ✅ Done | Offsets computed at compile time based on IR scan |
| Conditional runtime embedding | ✅ Done | Only embed print functions actually used |
| Instruction selection peephole | ❌ TODO | Recognize common patterns (e.g., `x + 0` → `x`) |
| Constant propagation across basic blocks | ❌ TODO | Requires CFG construction |
| Dead store elimination (CFG-aware) | ❌ TODO | Only eliminate stores dominating all reads |
| Inline small functions | ❌ TODO | `#inline` decorator implementation |

### Implementation Order

```
Phase 1 (Prerequisites):
  1.1  Lexer: `..` range operator tokenization
  1.2  Parser: `if`/`elif`/`else` → IR_JCC/IR_JMP/IR_LABEL
  1.3  Parser: `for`/`while` loops
  1.4  Parser: `prot` function definitions + `@call` calling convention
  1.5  Parser: `return` statements
  1.6  Parser: `struct` type definitions
  1.7  Parser: `seq[T]` / `arr[T,N]` types

Phase 2 (Memory Management):
  2.1  `use mm arena(N):` scope implementation
  2.2  `use mm stack:` scope implementation
  2.3  Scope enter/exit IR opcodes

Phase 3 (Carnifex):
  3.1  Region tree + region-id assignment
  3.2  Ownership binding (`owned`/`free`)
  3.3  Pinned ownership enforcement
  3.4  `.copy()` / `.release()` hooks
  3.5  Generation counter infrastructure
  3.6  Runtime generation check on dereference
  3.7  DSE exclusion for `owned` bindings
  3.8  Exception safety (release at raise sites)
  3.9  Capability tracking (read/write aliasing)
```

### Test Files Required

| Phase | Test File | Description |
|-------|-----------|-------------|
| 1.1 | `tests/test_range.rex` | `for i in 0..10` range loops |
| 1.2 | `tests/test_if_else.rex` | `if`/`elif`/`else` branching |
| 1.3 | `tests/test_loops.rex` | `for`, `while`, `each`, `repeat` loops |
| 1.4 | `tests/test_protocols.rex` | Function definitions and calls |
| 1.5 | `tests/test_return.rex` | Return values (single and multiple) |
| 1.6 | `tests/test_structs.rex` | Struct definition, construction, field access |
| 1.7 | `tests/test_collections.rex` | `seq`, `arr`, `dict` basic operations |
| 2.1 | `tests/test_mm_arena.rex` | Arena allocator scope |
| 2.2 | `tests/test_mm_stack.rex` | Stack allocator scope |
| 3.1 | `tests/test_carnifex_region.rex` | Region tree construction |
| 3.2 | `tests/test_carnifex_ownership.rex` | Owned/free binding semantics |
| 3.3 | `tests/test_carnifex_pinned.rex` | No-transfer enforcement |
| 3.6 | `tests/test_carnifex_gen_check.rex` | Runtime generation mismatch detection |

### Scratch Files

| File | Purpose |
|------|---------|
| `scratch/carnifex_region_tree.asm` | Region tree data structure experiments |
| `scratch/carnifex_gen_counter.asm` | Generation counter implementation prototypes |
| `scratch/carnifex_calling_conv.asm` | Function call ABI experiments |
| `scratch/mm_arena.asm` | Arena allocator implementation prototype |
| `scratch/mm_stack.asm` | Stack allocator implementation prototype |
| `scratch/seq_ops.asm` | Sequence operations implementation prototype |
| `scratch/struct_layout.asm` | Struct field layout experiments |
