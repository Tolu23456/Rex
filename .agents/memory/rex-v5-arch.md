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

## Remaining Open Issues (see docs/issues.md)
High: none remaining.
Medium: stop multi-level break (22), dict variable keys (23), string concat (24),
err int-to-string (25 partial).
Low: NASM env (2), dict hardcoded offsets (3), when jump table (27), seq read bounds (28).

## Issue 18 — Recursive Protocols (FIXED)
Push/pop stack-frame mechanism: `.prot_push_old` emits `push qword [param_addr]`
for each param at entry; `proto_emit_restore` emits `pop qword [param_addr]` in
reverse at every ret path. Correct: fib(10)=55 verified.
Performance cost: ~9–10× vs C for fib(42) due to memory round-trips per param per
call. Next step: rbp-relative stack frames to eliminate global-memory indirection.

## Benchmark — Measured Numbers (June 2026, latest run)
- Rex sum (1B): **~385ms** correct `499999999500000000` (O14 fusion intact; ~5.1× faster than C ~1947ms)
- Rex fib(42): **~1355ms** correct `267914296` (O18 active; ~3.6× slower than C ~377ms)
- Rex alloc: **~8ms**
- Rex binary size ~8712 bytes minimal vs C ~15800 bytes (1.8× smaller)

## O15: Strength-Reduction — sub/mul/div Fusion (IMPLEMENTED)
Extends O14 to fuse `:accum = accum OP pin` for OP = -, *, /  in addition to +.
- **sub:** `sub r14,r15` = `4D 29 FE`
- **mul:** `imul r14,r15` = `4D 0F AF F7`
- **div:** `mov rax,r14; cqo; idiv r15; mov r14,rax` = `4C 89 F0 48 99 49 F7 FF 49 89 C6`
BSS `sr_op` (resb 1) distinguishes op type (0=add 1=sub 2=mul 3=div).
`.srv_do_promote` dispatches on sr_op for deferred case. Sub/mul/div emitters now contain
the same candidate/deferred/normal structure as `codegen_emit_add_rax_rbx`.

## O18: Register Allocator — Pin Protocol Params to r12/r13 (IMPLEMENTED)
Pins first min(param_cnt, 2) protocol params to callee-saved registers r12/r13.
**Frame layout** (regalloc_cnt=N): [rbp-8]=saved r12, [rbp-16]=saved r13, then O1 slots
at [rbp-(K+1+N)*8]. `codegen_find_frame_slot` adds regalloc_cnt to all return values
so all callers (emit_mov_rax_var, emit_store_rax_to_var, output_typed, add_frame_local) auto-correct.
**BSS:** `sr_op resb 1`, `regalloc_active resb 1`, `regalloc_cnt resb 1`, `regalloc_vars resb 2`
**Entry/exit sequences** emitted by `codegen_emit_frame_prologue` and `codegen_emit_regalloc_epilogue`.
**Regalloc read:** `mov rax,r12` (4C 89 E0) or `mov rax,r13` (4C 89 E8).
**Regalloc write:** `mov r12,rax` (49 89 C4) or `mov r13,rax` (49 89 C5).
**Priority:** O13 accum and O2 pin checks are BEFORE O18 in read path; O18 store write
guards against intercepting the active O13 accumulator via `loop_accum_active` check.
**Known trade-off:** O18 adds 2 instructions per call (save + load r12) at protocol entry
and 1 at exit (restore r12). For deep-recursive protocols (fib: 700M calls, few param reads)
this HURTS (~7% regression) because store-to-load forwarding already makes [rbp-8] reads
nearly free. O18 HELPS loop-heavy protocols called once with many param reads in the body.
**TCO interaction:** TCO jmp bypasses the r12/r13 load instructions (they're in the prologue,
tco_body_entry is after the prologue). For self-recursive TCO protocols, r12 would hold the
OLD param — CORRECTNESS BUG if TCO fires on a protocol with regalloc_cnt > 0. Fib/sum/alloc
do not trigger TCO, so this is a latent issue only.
**Encoding verified:** [rbp-8] for r12: save=4C 89 65 F8; load-from-rdi=49 89 FC; restore=4C 8B 65 F8.
[rbp-16] for r13: save=4C 89 6D F0; load-from-rsi=49 89 F5; restore=4C 8B 6D F0.

## O14: Strength-Reduction Fusion (IMPLEMENTED)
Fuses `:accum = accum + pin` → single `add r14, r15` (4D 01 FE), cutting the hot loop body
from 6 instructions to 2 (`add r14,r15` + `inc r15`).
Two cases handled:
1. **Accum already active** (loop_accum_active==1 at load time): set candidate in O13 read path;
   rewind 12 bytes (mov rax,r14 + save + mov rax,r15 + restore) in `codegen_emit_add_rax_rbx`,
   suppress next O13 store via `sr_add_done`.
2. **Read-first** (loop_accum_active==0): set candidate in `.mrv_global` read-first block;
   defer to `.srv_do_promote` which rewinds to `sr_add_patch_pos` (before 8-byte global load)
   after patching the pre-loop r14 placeholder, then emits `add r14,r15`.
**Key BSS fields:** `sr_add_candidate`, `sr_add_rhs_is_pin`, `sr_add_done`, `sr_add_patch_pos`.
All cleared at loop start. Fusion only fires when expr_spill_depth==0 (no nested expression).

## For-loop Init Address Corruption Bug (FIXED)
In `codegen_emit_for_start`, the zero-path and 32-bit non-zero path both call
`get_var_va` (returns VA in rax), then immediately emit `mov al, 0x89` / `0x04` / `0x25`
for the `mov [i_addr],eax` encoding. Each `mov al,*` clobbers the low byte of rax,
corrupting the VA before `emit_d` uses it (e.g. 0x440040 → 0x440025).
**Fix:** `mov rbx, rax` after `get_var_va`; `mov rax, rbx` before `emit_d`.
**Rule:** Whenever instruction-byte emissions (`mov al,*; call emit_b`) must be
followed by `call emit_d` using a previously-loaded address, save rax to rbx first.
The `.fs_init64` path (which calls `emit_d` immediately after `get_var_va`) is the
correct pattern to follow.

## O13 Accumulator — Retroactive-Patch for Read-Before-Write (FIXED)
O13 promotes a loop variable to r14 on its first STORE. For `:sum = sum + i` the
variable is LOADED first — that load was emitted as `mov rax,[mem]` (8 bytes, baked
into the loop body machine code). Every iteration then read stale memory, ignoring r14.
**Fix:** `loop_accum_read_first` + `loop_accum_load_patch_pos` BSS fields.
1. In `.mrv_global`: if in outermost pinned loop and accum not yet active, set
   `loop_accum_read_first=1` and record `out_idx` as `loop_accum_load_patch_pos`.
2. In `.srv_first_check`: if `loop_accum_read_first==1`, overwrite the 8 bytes at
   `loop_accum_load_patch_pos` with `4C 89 F0 90 90 90 90 90` (mov rax,r14 + 5 NOPs),
   clear the flag, then proceed with normal promotion.
**Why:** the standard write-before-read path still works unchanged; only the
read-before-write path needs the retroactive patch. Reset both fields at loop start.

## edgecases/ folder
Created edgecases/ with 13 .rex test files covering issues 4, 18-22, 25-26, 29-34, 37.
Each file has expected-output comments and a README.md with a status table.
