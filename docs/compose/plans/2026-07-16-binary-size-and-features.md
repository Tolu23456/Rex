# Rex Binary Size Reduction & Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use compose:subagent (recommended) or compose:execute to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce compiled binary sizes by 10-50x (672B → 50-100B for `output(42)`) and implement core missing language features.

**Architecture:** Three independent workstreams: (A) binary size reduction via inline syscalls and runtime packing, (B) language features (range, return, struct, arr), (C) Carnifex memory safety (deferred to separate plan).

**Tech Stack:** x86-64 NASM assembly, ELF64 binary output, Linux syscalls.

## Current State

| Program | Current Size | Target Size | Reduction |
|---------|-------------|-------------|-----------|
| `output(42)` | 672 B | 50-80 B | 8-13x |
| `output("hi")` | 680 B | 60-90 B | 7-11x |
| No output | 152 B | 128 B | 1.2x |
| Seq operations | 3085 B | 500-800 B | 4-6x |

## Workstream A: Binary Size Reduction

### Task 1: Inline syscalls for simple output

**Covers:** TODO Tier 2 #5 — Inline syscalls for simple output

**Files:**
- Modify: `codegen/codegen.asm` — `cge_out_int`, `cge_out_str`, `cge_out_bool` handlers
- Modify: `runtime/rt_pri.asm`, `rt_prs.asm`, `rt_prb.asm` — keep for complex cases

**Approach:** When the codegen detects `IR_OUT_INT` with an `IR_LOAD_IMM` source (constant integer), emit inline `sys_write` instead of calling `rt_pri`. This eliminates the 512-byte rt_pri blob for simple programs.

- [ ] **Step 1:** In `codegen/codegen.asm`, find `cge_out_int` handler. Add a check: if src1 is `IR_FLAG_CONST`, emit inline syscall instead of calling rt_pri.
- [ ] **Step 2:** Inline syscall for int: convert integer to string on stack, then `mov rax,1; mov rdi,1; lea rsi,[rsp]; mov rdx,len; syscall; write newline`.
- [ ] **Step 3:** Same for `cge_out_str` — if string is a literal (IR_LOAD_STR), embed string inline and emit `sys_write` directly.
- [ ] **Step 4:** Same for `cge_out_bool` — emit "true\n" or "false\n" inline.
- [ ] **Step 5:** Test: `output(42)` should produce smaller binary. Verify output matches.
- [ ] **Step 6:** Ensure non-constant cases still fall back to runtime calls.

### Task 2: Pack runtime without padding

**Covers:** TODO Tier 1 #1 — Pack runtime without padding

**Files:**
- Modify: `runtime/rt_pri.asm`, `rt_prs.asm`, `rt_prb.asm`, `rt_prf.asm`, `rt_prc.asm`, `rt_alloc.asm`, `rt_str.asm` — remove `times N - ($ - $$) db 0` padding
- Modify: `codegen/codegen.asm` — `codegen_init` to compute offsets dynamically
- Modify: `codegen/codegen.asm` — all `add edi, 0xNNN` hardcoded offsets → dynamic

**Approach:** Remove fixed padding from all runtime binaries. In `codegen_init`, after writing each needed runtime blob, record its actual size and compute the next blob's offset dynamically.

- [ ] **Step 1:** Remove `times` padding from all `rt_*.asm` files (keep rt_seq at 2048 for now since it has complex internals).
- [ ] **Step 2:** Rebuild runtime binaries, record actual sizes.
- [ ] **Step 3:** In `codegen_init`, after each `emit_block` for a runtime blob, save `out_idx` as the blob's end offset. Compute `rt_*_off` as the start offset.
- [ ] **Step 4:** Update `rt_*_bin_size equ` constants to actual sizes.
- [ ] **Step 5:** Replace all hardcoded `add edi, 0xNNN` with dynamic offset computation. Use a table of (base_off, func_offset) pairs.
- [ ] **Step 6:** Test all 23 tests pass. Measure binary size improvement.

### Task 3: Granular collection runtime

**Covers:** TODO Tier 2 #8 — Granular collection runtime

**Files:**
- Modify: `codegen/codegen.asm` — `scan_needed_runtime` to separate seq/dict/alloc flags
- Modify: `codegen/codegen.asm` — `codegen_init` to conditionally embed each module

**Approach:** Currently `need_rt_seq` implies `need_rt_alloc`. Split into three independent flags: `need_rt_alloc`, `need_rt_seq`, `need_rt_dict`. Only embed the modules actually needed.

- [ ] **Step 1:** In `scan_needed_runtime`, add separate tracking for `IR_SEQ_*` → `need_rt_seq`, `IR_DICT_*` → `need_rt_dict`, heap ops → `need_rt_alloc`.
- [ ] **Step 2:** In `codegen_init`, conditionally embed each module based on its flag.
- [ ] **Step 3:** Update offset computation to handle the variable layout.
- [ ] **Step 4:** Test: programs without seq/dict should produce smaller binaries.

### Task 4: Short jumps for forward branches

**Covers:** TODO Tier 3 #12 — Short jumps for forward branches

**Files:**
- Modify: `codegen/codegen.asm` — jump emission code

**Approach:** When emitting `Jcc rel32`, check if the target is within ±127 bytes. If so, use `Jcc rel8` (2 bytes) instead of `Jcc rel32` (6 bytes). Requires two-pass emit or backpatching.

- [ ] **Step 1:** Add a `emit_short_jcc` helper that emits 2-byte short jumps.
- [ ] **Step 2:** In the main emit loop, try short jump first. If target overflows, backpatch to long jump.
- [ ] **Step 3:** Measure size improvement on test programs.

### Task 5: Instruction peephole improvements

**Covers:** TODO Tier 2 #10 — Instruction peephole

**Files:**
- Modify: `irgen/opt.asm` — `pass_peephole`

**Approach:** Add peephole patterns: `x + 0 → x`, `x * 1 → x`, `x * 0 → 0`, `0 + x → x`, `x - x → 0`. Also: `mov r, 0 → xor r, r` (already partial), `cmp r, 0 → test r, r`.

- [ ] **Step 1:** Add `x - x → 0` pattern to peephole pass.
- [ ] **Step 2:** Add `x ^ x → 0` (XOR self) pattern.
- [ ] **Step 3:** Extend `0 - x → NEG x` pattern.
- [ ] **Step 4:** Test with existing test suite.

## Workstream B: Language Features

### Task 6: `return` statements

**Covers:** TODO Phase 1 #1.5

**Files:**
- Modify: `parser/parser.asm` — add `return` keyword parsing
- Modify: `include/rex_ir.inc` — ensure `IR_RET` exists
- Modify: `codegen/codegen.asm` — handle `IR_RET`

**Approach:** Parse `return expr` → emit `IR_RET` with the expression's vreg. Codegen emits `mov rax, vreg; jmp epilogue`.

- [ ] **Step 1:** Add `return` keyword recognition in parser (after `advance`).
- [ ] **Step 2:** Parse `return expr` — call `parse_expr`, emit `IR_RET`.
- [ ] **Step 3:** Codegen: `IR_RET` → `mov rax, src1; jmp .epilogue`.
- [ ] **Step 4:** Add test: `prot add(a: int, b: int) -> int: return a + b`.
- [ ] **Step 5:** Verify existing tests still pass.

### Task 7: `..` range operator

**Covers:** TODO Phase 1 #1.1

**Files:**
- Modify: `lexer/lexer.asm` — tokenize `..` as `TOK_RANGE`
- Modify: `include/rex_defs.inc` — add `TOK_RANGE`
- Modify: `parser/parser.asm` — parse `a..b` as range expression

**Approach:** Lexer: when seeing `.`, peek next char. If `.`, emit `TOK_RANGE`. Parser: `a..b` creates a range value (start, end).

- [ ] **Step 1:** Add `TOK_RANGE` to `rex_defs.inc`.
- [ ] **Step 2:** In lexer, after dot handling, check for second dot → emit `TOK_RANGE`.
- [ ] **Step 3:** Parser: add `parse_range` that parses `expr .. expr`.
- [ ] **Step 4:** Add test: `r = 0..10; output(r)`.

### Task 8: `struct` type definitions

**Covers:** TODO Phase 1 #1.6

**Files:**
- Modify: `parser/parser.asm` — parse `struct Name: field: type` syntax
- Modify: `parser/type_reg.asm` — register struct types with field offsets
- Modify: `irgen/irgen.asm` — IR for struct field access
- Modify: `codegen/codegen.asm` — codegen for struct load/store

**Approach:** Parser recognizes `struct` keyword, parses field declarations, registers type with `type_struct_add_field`. Field access `s.field` emits `IR_LOAD_VAR` with computed offset.

- [ ] **Step 1:** Add `struct` keyword recognition in parser.
- [ ] **Step 2:** Parse struct body: `field: type` lines, register each field.
- [ ] **Step 3:** Parse struct construction: `MyStruct(field1: val1, field2: val2)`.
- [ ] **Step 4:** Parse field access: `s.field` → compute offset, emit load.
- [ ] **Step 5:** Add test: `struct Point: x: int, y: int; p = Point(x: 1, y: 2); output(p.x)`.

### Task 9: `arr[T, N]` fixed-size array type

**Covers:** TODO Phase 1 #1.7

**Files:**
- Modify: `parser/parser.asm` — parse `arr[int, 5]` type syntax
- Modify: `irgen/irgen.inc` — add `IR_ARR_NEW`, `IR_ARR_LOAD`, `IR_ARR_STORE` (already exist)
- Modify: `codegen/codegen.asm` — codegen for fixed arrays (stack-allocated)

**Approach:** `arr[T, N]` allocates `N * sizeof(T)` bytes on the stack. Index access `a[i]` emits `IR_ARR_LOAD` with the array vreg and index.

- [ ] **Step 1:** Parse `arr[T, N]` type syntax in parser.
- [ ] **Step 2:** Array initialization: `arr[int, 3] = [1, 2, 3]` → stack allocation + stores.
- [ ] **Step 3:** Index access: `a[i]` → `IR_ARR_LOAD`.
- [ ] **Step 4:** Add test.

## Workstream C: Deferred (Separate Plan Required)

The following items are too large for this plan and require dedicated planning:

- **Carnifex memory safety** (Phase 3): Region tree, ownership, capabilities, generation counters — estimated 2-4 weeks of work
- **Memory management** (Phase 2): Arena, stack, pool allocators, GC — estimated 1-2 weeks
- **`prot` function calls** (Phase 1 #1.4): Full function call ABI with calling convention — estimated 1 week
- **`enum` types** (Phase 1): Typed integer constants — estimated 2-3 days
- **Null propagation** (Phase 1): `?.` and `??` operators — estimated 2-3 days
- **Bytecode interpreter** (Tier 4 #16): Separate output mode — estimated 1-2 weeks
- **Stack-relative variables** (Tier 3 #11): Major codegen rewrite — estimated 1 week

## Verification

After each task:
1. `make clean && make runtimes && make` — zero warnings
2. `./run_tests.sh` — all tests pass
3. Measure binary size for `output(42)` and no-output programs
4. Compare before/after sizes

## Size Tracking

| Checkpoint | `output(42)` | No output | Seq ops |
|------------|-------------|-----------|---------|
| Baseline | 672 B | 152 B | 3085 B |
| After Task 1 | | | |
| After Task 2 | | | |
| After Task 3 | | | |
| After Task 4 | | | |
| After Task 5 | | | |
