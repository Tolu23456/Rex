---
name: Rex V5.0 compiler architecture
description: Key decisions, bugs, offsets, and conventions for the Rex V5.0 NASM compiler.
---

## Build
- `make` assembles 6 object files (main, lexer, parser, codegen, headers, runtime) and links with `ld`.
- NASM 2.16.03 is available at full path in Makefile — build is clean and all tests pass.
- `rexc.asm` (old monolithic file) has been deleted. All content is now modular.

## NASM Semicolon Bug (FIXED)
- NASM treats `;` as a comment, so `instruction1; instruction2` on one line only executes instruction1.
- Fix: every instruction on its own line. All known instances fixed.

## Lexer `//` Comment Handler (FIXED)
- `.eslash` in lexer.asm originally emitted `TOK_SLASH` for every `/` without peeking ahead.
- `//` with non-ASCII UTF-8 bytes (e.g. em-dash `—` = 0xE2 0x80 0x94) would corrupt the lexer state.
- Fix: `.eslash` now peeks at next byte; if also `/`, scans forward until `\n` (0x0A) or EOF before returning.
- **Why:** UTF-8 high bytes (>0x7F) fall through all character comparisons and land at `inc lex_pos; jmp .r`,
  but the first `/` had already been emitted as TOK_SLASH, scrambling the token stream for the parser.

## Dict Runtime Offsets
- `RT_DICT_NEW_OFFSET=7550`, `RT_DICT_SET_OFFSET=7577`, `RT_DICT_GET_OFFSET=7626` — offsets from
  start of binary (after 120-byte ELF header + 5-byte runtime skip JMP) where rt_dict_new/set/get
  live inside rt_prq_blob.
- These are hardcoded in `include/rex_defs.inc`. If any preceding blob size changes, re-measure.

## Key Variable Layout
- `var_table` entry: name[0..31] | value[32..39] | is_init[40] | type[48] (size=64).
- `VAR_STORAGE_BASE=0x440000`. `get_var_va(idx)` returns `0x440000 + idx*64`.
- `cur_type` (resb 1 in parser.bss) holds type of last expression atom for output dispatch.

## Expression Parser — Type Propagation (IMPLEMENTED)
- `parse_additive` and `parse_term` now push r14 at entry (callee-saved; popped at all exits).
- After each binary op (`+`, `-`, `*`, `/`), if LHS type (saved in r14d via `movzx r14d, [cur_type]`)
  was TYPE_FLOAT, set `[cur_type] = TYPE_FLOAT` (float dominates). Mod (`%`) always yields int.
- **Why:** previously cur_type only reflected the last atom; mixed-type sums gave wrong output routing.
- **How to apply:** every `pop r14; leave; ret` must appear at ALL exits of parse_additive/parse_term.

## Proto Table Entry Layout (48 bytes) — FINALIZED
- [0..31]=name (null-padded), [32..39]=out_idx offset (qword), [40]=param_count (byte),
  [41..46]=param var indices (one byte each, up to 6 params), [47]=ret_type (byte).
- `proto_find` and `.protocol` both use `imul rax, 48`. Old 40-byte size is gone.
- `proto_find` stores ret_type at [rax+47] into `proto_ret_type` BSS (parser.asm) after lookup.
- **Why:** 48 bytes needed for 6 param slots + ret_type; must be consistent between find and write paths.

## emit_b_indirect / emit_d_indirect (FIXED)
- Previously these were no-ops (just `ret`). Now they `jmp codegen_emit_b_raw` / `jmp codegen_emit_d_raw`
  which are `global` wrappers in codegen.asm that forward to internal `emit_b` / `emit_d`.
- Also added `codegen_get_var_va_proxy` (global) wrapping internal `get_var_va`.
- **Why:** prot_se loop in parser.asm emits param-store instructions into the output stream; it lives in
  parser.o which cannot see codegen internals directly.

## Parameterized Protocols — Up to 6 Params (FIXED)
- `.prot_se` loop emits `mov [var_addr], reg` for params 0-5. REX prefix = 0x48 for rdi/rsi/rdx/rcx,
  0x4C for r8/r9. ModRM bytes: rdi=0x3C, rsi=0x34, rdx=0x14, rcx=0x0C, r8=0x04, r9=0x0C.
- `codegen_emit_arg_pops` extended to support up to 6 args (added r8/r9 pop opcodes).

## overflow guard in emit_b (FIXED)
- If `out_idx >= 131071`, emit_b now calls `rt_err_blob` and halts instead of silently overwriting.
- Buffer is 128KB (`out_buffer resb 131072` in codegen BSS).

## Float Return Type Through Protocol (FIXED)
- `proto_ret_type` BSS in parser.asm mirrors [entry+47] from proto_table.
- `proto_find` sets it after every lookup. `.ret` stores `cur_type` into [entry+47].
- Used by `codegen_output_typed` to dispatch float-typed protocol return values correctly.

## New Features Added (5 from todo.md)
1. `++x` / `--x` — prefix inc/dec operators. Lexer: TOK_PLUSPLUS=72, TOK_MINUSMINUS=73.
   codegen: `codegen_emit_inc_var` / `codegen_emit_dec_var` (inc/dec qword [addr]).
2. `swap x y` — swaps two int vars via xchg rax,rbx. Lexer: TOK_SWAP=74.
   codegen: `codegen_emit_swap_vars`.
3. `abs(x)` — absolute value. Lexer: TOK_ABS=75. codegen: `codegen_emit_abs_rax`.
   Pattern: `mov rbx,rax; neg rax; cmovs rax,rbx` (0x0F 0x48). CMOVS not CMOVNS.
   **Why:** After neg, SF=1 means result is negative (original was positive) — move
   back the positive original. CMOVNS (0x49) was the original wrong opcode; fixed.
4. `cap x` — capacity of a sequence (loads qword at [ptr+0]). Lexer: TOK_CAP=76.
   codegen: `codegen_emit_cap_rax`. Cap is at offset 0, len at offset 8 in seq header.
5. `when x: is N: body ... else: body` — switch-like statement. Lexer: TOK_IS=77.
   Parser: `.when` creates temp `__when__` var (string "\_\_when\_\_"), uses `when_case_count`.
   **Why:** accessing codegen BSS symbols from parser.asm causes link errors.
   Known limitation: nested `when` corrupts `when_var_idx` (issue 32).

## `for step N` — FIXED
`codegen_set_for_step(N)` sets `for_step_val`. Both `codegen_emit_for_start` and
`codegen_emit_for_start_dyn` used to immediately overwrite it with 1 — making step
always 1 and `codegen_set_for_step` dead code. Both resets removed. The reset in
`codegen_emit_for_end` (after reading the value) is the canonical reset point.

## `and` / `or` — IMPLEMENTED (eager, not short-circuit)
Both are wired in `parse_expr`. `codegen_emit_and_bool_rax_rbx` emits
`test/setnz/and` — correct but eager. Short-circuit (issue 33) is NOT implemented.
todo.md and syn.md now correctly mark them as `[x]` / `✅`.

## `skip` semantics
`codegen_emit_skip` jumps to `cont_base_stack` top (loop condition re-eval).
This is **continue** semantics. The `N` depth argument is parsed but never passed.
`skip` and `stop` are both "innermost loop" operations; skip = continue, stop = break.
See issue 31 for resolution options.

## String literal limit (FIXED)
`tok_ident` is 64 bytes; max 63 content chars. Bounds check `cmp rbx,63; jge .strd` added.
Overlong strings are truncated silently (issue 34).

## seq push inline grow (FIXED — two bugs corrected)
`codegen_emit_seq_push` emits `cmp rcx,[rbx]; jb +56` then a 56-byte inline grow block.
Grow: push rcx; compute new_size=16+old_cap*16; call rt_alc; pop rcx; write new_cap/len;
rep movsq copies elements; pop rbx (new ptr); mov [var_addr],rbx; reload rcx. Unbounded growth.
**Bug 1 (FIXED):** `jb +57` (0x39) was off-by-one — grow block is 56 bytes not 57. The
no-grow path skipped `pop rax`, leaking 8 bytes of stack per iteration → stack overflow
at ~1M pushes. Fix: `mov al, 0x38` (jb +56).
**Bug 2 (FIXED):** `shl rdi, 0x10` (shift by 16) instead of `shl rdi, 0x04` (shift by 4).
This computed new_size = 16+old_cap×65536 instead of 16+old_cap×16. For old_cap=131072,
the 8 GB mmap returned MAP_FAILED → segfault. Fix: `mov al, 0x04` for the shift immediate.
**Rule:** grow block is exactly 56 bytes; jb offset must equal 56 (0x38); shift must be 4 (0x04).

## err non-string guard (PARTIAL FIX — issue 25)
`.err_stmt` in parser.asm checks `cur_type` after `parse_expr`. If not TYPE_STR, calls
`codegen_output_rax` (correct printer for the type) then `codegen_emit_exit1` (exit(1)).
Prevents segfault from passing int as char* to rt_err strlen loop.

## codegen_emit_exit1 (NEW)
New function in codegen.asm emits: `mov rax,60; mov rdi,1; syscall` (exit code 1).
Exposed as global; extern'd in parser.asm. Used by err non-string path and available
for future error-exit emission.

## Prescan Blob Inclusion Rules (CRITICAL — update when adding features)
`prescan_blobs` in main/main.asm does a single-pass byte scan to decide which runtime
blobs to include. Missing a trigger = null VA = segfault at runtime. Current triggers:
- PRI (bit 0, 0x01): always set
- PRS (bit 1, 0x02): `"` (quote byte) OR `str` (3-byte)
- PRB (bit 2, 0x04): `bool`, `true`, `fals` (4-byte)
- PRF (bit 3, 0x08): `floa` (4-byte keyword) OR digit followed by `.` (float literal)
- PRC (bit 4, 0x10): `comp` (4-byte)
- SIP (bit 5, 0x20): `inpu` (4-byte)
- ALC (bit 6, 0x40): `seq`/`push`/`each` (3/4-byte) OR `memo` (4-byte) OR `use ` (4-byte)
- PRQ (bit 7, 0x80): `dict` (4-byte) OR `err ` (4-byte, with trailing space)
**Why:** memo uses rt_alc; use mm/gc uses rt_alc for mode switch; err uses rt_prq.
**Rule:** whenever a new keyword uses a runtime blob, add its 4-byte LE dword to prescan.

## ELF MemSiz BSS Allocation (CRITICAL)
`codegen_finish` patches p_memsz = out_idx + 0x46000.
- 0x44000 covers var_table (0x440000–0x444000, 256 vars × 64 bytes)
- 0x45000 covers MEMO_PTR_BASE (0x445000, 32 protos × 8 bytes)
- 0x46000 adds one page buffer for future growth
**Bug fixed:** was 0x44000 → MEMO_PTR_BASE at 0x445000 was outside MemSiz → segfault on first memo alloc.
**Rule:** if new BSS regions are added above 0x445000, increase this constant accordingly.

## Float Literal Codegen (FIXED)
Float literals (`3.14`, `2.5e6`) hold a 64-bit IEEE 754 bit pattern in `tok_int`.
Previously emitted via `codegen_emit_mov_eax_imm32` → truncated to 32 bits → wrong value.
**Fix:** added `codegen_emit_mov_rax_imm64` (global) which emits `movabs rax, imm64`
(48 B8 + emit_q). Float literal path in parser `.flt` now calls this instead.
**Rule:** any atom that carries a 64-bit value must use emit_q / movabs, not emit_d.

## Benchmark — Measured Numbers (post-O-Affine, June 2026)

**Fair 5-benchmark suite (Rex=wall-clock, C=internal clock):**
- B1 Arith (1B LCG): Rex 27ms / C 1136ms → **Rex wins 42×** (O-Affine binary ladder)
- B3 Calls (200M calls): Rex 490ms / C 80ms → **C wins 6.1×**
- B6 Fib-rec fib(42): Rex 1295ms / C 393ms → **C wins 3.3×**
- B7 Fib-iter (10M×80): Rex 2691ms / C 516ms → **C wins 5.2×**
- B9 Dynarray (1M push): Rex 41ms / C 6ms → **C wins 7.2×**

**#memo benchmark — fib(42):**
- Rex with `memo`: ~20ms average (O(n) distinct calls cached)
- Rex without `memo`: ~1540ms
- C -O2 (no memo): ~900ms
- Rex #memo vs C: **~45× faster** (algorithm wins; memo eliminates 2^42 → 43 calls)

**Binary sizes:** Rex wins all benchmarks (2.9× to 19.7× smaller than GCC output).
**Test suite:** 37/37 pass after June 2026 bugfixes.

## Issue 18 — Recursive Protocols (FIXED)
Push/pop stack-frame mechanism: `.prot_push_old` emits `push qword [param_addr]`
for each param at entry; `proto_emit_restore` emits `pop qword [param_addr]` in
reverse at every ret path. Correct: fib(10)=55 verified.

## O26: Loop-Free Call-Site Pin-Save Skip (IMPLEMENTED)
Proto table offset 46 = `has_loop` flag (byte). Set to 1 when a `for`/`while` is parsed inside the proto body; cleared to 0 at each proto definition start. At call sites (`.prt_do_normal`), if `proto_table[seq_idx*48+46]==0`, sets `codegen_skip_pin_save=1` so `codegen_emit_push_var_slot`/`_pop_var_slot` skip emitting `push r15`/`pop r15`. Flag cleared after `.prt_cr_done`.
**Why:** callees with no loops cannot clobber r15 (the loop-pin register), making save/restore dead code. Confirmed: B3 binary shrank exactly 4 bytes (push r15=2B + pop r15=2B); B3 Rex 581ms→381ms (34% faster).

## O27: Retroactive push/pop r12 Elision for Outer-Scope-Only Protos (IMPLEMENTED)
Post-compile finalize pass `codegen_finalize()` called from `main.asm` after parse loop, before `codegen_finish`.
BSS: `proto_push_r12_pos[64]`, `proto_pop_r12_pos[512]`, `proto_pop_r12_cnt[64]`, `proto_needs_r12_save[64]`, `codegen_cur_proto_seq_idx`.
**Trigger:** `proto_needs_r12_save[idx]=1` set at `.prt_do_normal` when `prot_body_depth > 0`.
**Action:** for each proto with flag=0, NOP the push r12 and all pop r12.

## Long-NOP Optimization (IMPLEMENTED)
Zero-local protos use 7-byte Intel long NOP `0F 1F 80 00000000` (1 µop) instead of
7 single-byte NOPs (7 µops) for sub/add rsp placeholders when frame_size==0.

## O22: Loop Rotation + 32-byte µop-cache alignment (IMPLEMENTED — CRITICAL LESSON)
**Without µop-cache alignment, O22 gives ZERO speedup.** After emitting the jge placeholder,
emit NOPs = (0x20 - (out_idx & 0x1F)) & 0x1F to advance body_start to the next 32-byte boundary.
**Rule:** hot loop body must be in a DIFFERENT 32-byte µop-cache set from any pre-loop guard.

## @memo: Algorithmic Memoization (IMPLEMENTED)
Syntax: `memo prot name(n): ...` — `memo` keyword (TOK_MEMO=86) before `prot`.
**Cache:** per-protocol pointer at `MEMO_PTR_BASE + proto_idx*8` (= 0x445000 for proto 0).
  Pointer is null until first call; then `rt_alc(8192)` allocates 1024×8-byte table.
**Prescan:** `memo` (dword 0x6F6D656D) triggers ALC bit (0x40) — required for rt_alc.
**ELF BSS:** p_memsz extended to out_idx + 0x46000 (covers MEMO_PTR_BASE at 0x445000).
**Performance:** fib(42) ~20ms (memo) vs ~1540ms (no memo) vs ~900ms (C -O2, no memo).

## memo_reset: Cache Invalidation Keyword (IMPLEMENTED)
Syntax: `memo_reset <proto_name>` — clears a protocol's memo cache at runtime.
TOK_MEMO_RESET=87. Emits: `mov qword [MEMO_PTR_BASE + proto_idx*8], 0`.
`proto_find_seq_idx` BSS holds sequential index (NOT out_idx) — use this for memo_reset.

## O18: Register Allocator — Pin Protocol Params to r12/r13 (IMPLEMENTED)
Pins first min(param_cnt, 2) protocol params to callee-saved registers r12/r13.
**Known trade-off:** hurts deep-recursive protocols (fib: extra mem ops per 700M calls).

## O21: Push-Style Prologue for 1-Param Protocols (IMPLEMENTED)
Replaces `sub rsp,N; mov [rsp],r12; mov r12,rdi` with `push r12; mov r12,rdi; sub rsp,N`.
**proto_emit_restore order (CRITICAL):** push-style = leave THEN pop r12.

## FLC: Frameless Calling Convention (IMPLEMENTED)
Eliminates `push rbp; mov rbp,rsp`. Uses rsp-relative addressing.
Frame layout (bottom-up): slot K → [rsp+K*8]. Read: `48 8B 44 24 K*8`. Write: `48 89 44 24 K*8`.
O18 slot saves: `mov [rsp],r12` = `4C 89 24 24`; `mov r12,[rsp]` = `4C 8B 24 24`.

## O-Affine family: Closed-Form Binary Ladder for Affine Loops (IMPLEMENTED)

Three detectors run in sequence at `for_end` (after pinned-loop step==1 check), before O256:

### O-Affine (46-byte, `:x = x*A + B`)
Detects combined mul+add affine LCG pattern. Exact byte pattern:
- [0..2]=4C 89 F0, [3..7]=90×5 NOPs, [8..10]=49 89 C2, [11]=B8, [12..15]=imm32 A, [16..18]=4C 89 D3,
- [19..22]=48 0F AF C3 (imul), [23..25]=49 89 C6, [26..28]=4C 89 F0, [29..31]=49 89 C2,
- [32]=B8, [33..36]=imm32 B, [37..39]=4C 89 D3, [40..42]=48 01 D8 (add), [43..45]=49 89 C6.
**Computation (in compiler):** binary ladder: cur_a=A, cur_b=B, res_a=1, res_b=0, N=end-from.
  While N>0: if N&1: res_b=cur_a*res_b+cur_b; res_a*=cur_a. cur_b*=(cur_a+1); cur_a*=cur_a; N>>=1.
**Emits:** `mov rax, res_a; imul r14, rax` + `mov rax, res_b; add r14, rax` (up to 24 bytes).
**BSS:** `affine_tmp_a: resq 1`, `affine_tmp_b: resq 1`.
**B1 result:** Rex 20ms vs C 1338ms = **~67× faster**.

### O-Affine-Mul (26-byte, `:x = x*A`)
Detects multiply-only: [0..2]=4C 89 F0, [3..7]=90×5, [8..10]=49 89 C2, [11]=B8, [12..15]=imm32 A,
[16..18]=4C 89 D3, [19..22]=48 0F AF C3 (imul — distinguishes from add-only), [23..25]=49 89 C6.
**Computation:** binary ladder (mul-only): res_a=1, cur_a=A; while N>0: if N&1: res_a*=cur_a; cur_a*=cur_a; N>>=1.
**Emits:** `mov rax, A^N; imul r14, rax`. If A^N==1: emits nothing.
**B10 result:** Rex 20ms vs C 670ms = **~33.5× faster** (C must run full 1B loop; no modular exp pass).
**Label:** `.fe_no_affine` starts this check; failure jumps to `.fe_no_mul_only`.

### O-Affine-Add (25-byte, `:x = x+B`)
Detects add-only: same [0..18] prefix, then [19..21]=48 01 D8 (add rax,rbx — not imul), [22..24]=49 89 C6.
**Computation:** B_N = B*N mod 2^64 (single compiler-time `imul r8, r10`).
**Emits:** if B_N ≤ 0x7FFFFFFF: `add r14, imm32` (7 bytes, compact). Else: `mov rax, B_N; add r14, rax` (13 bytes).
**B11 result:** Rex 21ms (startup only) vs C ~0ms (GCC also folds). Both eliminate loop; parity confirmed.
**Special case:** `:x = x+1` over any N → `add r14, N` (single 7-byte instruction if N ≤ 0x7FFFFFFF).
**Label:** `.fe_no_mul_only` starts this check; failure jumps to `.fe_no_add_only` (then O256).

**Common finish path for all three:** rewind `out_idx` to `for_rotation_body_pc`, emit replacement,
`call codegen_patch_jump`, `mov byte [loop_pin_active], 0`, `jmp .fe_no_combine`.
**Key invariant:** `loop_accum_active` must be set (r14 is the accumulator) and loop step must be 1.
r8/r10/r11 survive across emit_b/emit_d/emit_q calls (those only clobber rax, preserve rbx/rcx via push/pop).

## O14/O15: Strength-Reduction Fusion (IMPLEMENTED)
Fuses `:accum = accum OP pin` → single `add/sub/imul/idiv r14, r15`.
BSS: `sr_add_candidate`, `sr_add_rhs_is_pin`, `sr_add_done`, `sr_add_patch_pos`, `sr_op`.

## edgecases/ folder
Created edgecases/ with 13 .rex test files covering issues 4, 18-22, 25-26, 29-34, 37.

## O23: 2× Unroll + Dual Accumulators (IMPLEMENTED)
