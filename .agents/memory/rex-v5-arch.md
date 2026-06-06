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

## Benchmark — Measured Numbers (June 2026, post-O27+long-NOP)

**Fair 5-benchmark suite (Rex=wall-clock, C=internal clock unless noted):**
- B1 Arith (1B LCG): Rex 1125ms / C 1128ms (int) → **≈ tie**
- B3 Calls (200M calls): Rex 247ms / C 104ms (int) → **~2.4×** (was 3.4× pre-O26, 2.2× pre-O27)
- B6 Fib-rec fib(42): Rex 1091ms / C 407ms (int) → **~2.7×** (was 1147ms pre-O27)
- B7 Fib-iter (10M×80): Rex 817ms / C 390ms (int) → **~2.1×** (was 1039ms pre-O27)
- B9 Dynarray (1M push): Rex 20ms / C 22ms (wall) → **Rex wins**

**B3 per-call cost:** Rex ~1.24 ns/call (was 1.91ns post-O26, 2.95ns post-global-elim, 6.2ns baseline).
**Binary sizes:** Rex wins all 5 (2.9× to 19.7× smaller than GCC output).
**Test suite:** 32/37 pass (5 known pre-existing failures: float_const, memo_reset_test, stage6_mm, test_err, test_mm_switch). The "FAIL test.rex" in `((pass++))` loops is a bash arithmetic false-negative when pass=0; use if/then instead.

## O26: Loop-Free Call-Site Pin-Save Skip (IMPLEMENTED)
Proto table offset 46 = `has_loop` flag (byte). Set to 1 when a `for`/`while` is parsed inside the proto body; cleared to 0 at each proto definition start. At call sites (`.prt_do_normal`), if `proto_table[seq_idx*48+46]==0`, sets `codegen_skip_pin_save=1` so `codegen_emit_push_var_slot`/`_pop_var_slot` skip emitting `push r15`/`pop r15`. Flag cleared after `.prt_cr_done`.
**Why:** callees with no loops cannot clobber r15 (the loop-pin register), making save/restore dead code. Confirmed: B3 binary shrank exactly 4 bytes (push r15=2B + pop r15=2B); B3 Rex 581ms→381ms (34% faster).
**Safety:** loop-having callees still save r15 correctly (O26 does NOT fire). Verified: `sum_to(n)` with for loop + outer for loop produces correct result.

## O27: Retroactive push/pop r12 Elision for Outer-Scope-Only Protos (IMPLEMENTED)
Post-compile finalize pass `codegen_finalize()` called from `main.asm` after parse loop, before `codegen_finish`.
BSS: `proto_push_r12_pos[64]` (qword per proto), `proto_pop_r12_pos[512]` (up to 8 epilogues per proto), `proto_pop_r12_cnt[64]` (byte per proto), `proto_needs_r12_save[64]` (byte per proto), `codegen_cur_proto_seq_idx` (qword).
**Trigger:** `proto_needs_r12_save[idx]=1` is set at `.prt_do_normal` in parser.asm when `prot_body_depth > 0` — i.e. when a proto is called from inside another proto body.
**Action:** for each proto with flag=0, NOP the push r12 (`41 54` → `66 90`) and all pop r12 (`41 5C` → `66 90`).
**Safety:** fib calls itself recursively → flag=1 → O27 skips fib. push/pop r12 preserved. B3 increment has flag=0 → patched.
**Impact:** B3 381ms → ~370ms alone; combined with long-NOP → 247ms (-35% from post-O26).
`proto_count` exported as `global` from parser.asm BSS so codegen_finalize can iterate.

## Long-NOP Optimization (IMPLEMENTED)
Zero-local protos use 7×`90` (single-byte NOP ×7) as placeholder for `sub rsp, imm32` / `add rsp, imm32`. These decode as 7 µops each (14 µops total per call). When `codegen_patch_jump` detects frame_size==0, it now writes Intel's 7-byte long NOP `0F 1F 80 00000000` (1 µop) at both positions. Also: push/pop r12 (2 bytes each) → 2-byte NOP `66 90` (already done by O27 path). Combined µop reduction per call: ~19 → ~6 (-13 µops). At 4 µops/cycle decode: 4.75 cycles → 1.5 cycles theoretical.
**Location:** `codegen.asm`, `codegen_patch_jump`, branch `.cf_check_nop`.

## data.push(val) Method-Call Syntax (IMPLEMENTED)
New syntax: `seq.push(expr)` — method-call style for seq push. Old `push seq val` still works.
**Lexer:** single `.` now emits `TOK_DOT=88` (was silently skipped). `..` still emits TOK_DOTDOT.
**Parser:** `parse_stmt` dispatches `TOK_IDENT → .ident_stmt`. Handler: save name, lexer_next, check TOK_DOT, lexer_next, check TOK_PUSH, lexer_next, check TOK_LPAREN, var_find, sub rsp 16, save var_idx, lexer_next, parse_expr, check/consume TOK_RPAREN, restore var_idx, call codegen_emit_seq_push.
**BSS needed:** `saved_name resb 64` (already existed), `cur_call_proto_seq_idx resq 1` (new for O26).

## O22: Loop Rotation + 32-byte µop-cache alignment (IMPLEMENTED — CRITICAL LESSON)
O22 replaces the unconditional `jmp loop_top` back-edge with `cmp r15,end; jl body_start` (1 branch/iter instead of 2).
**Without µop-cache alignment, O22 gives ZERO speedup.** The root cause:
- The one-time guard (`cmp r15,end + jge exit`, 13 bytes) and `body_start` (the first loop body instruction)
  were in the SAME 32-byte µop-cache set (Intel DSB, 32-byte aligned blocks).
- On every hot iteration, the CPU re-fetched the entire set, issuing both `jge` and `jl` as branch µops to port 6.
- Port 6 handles 1 branch/cycle → 2 branch µops/iter = 2 cycles/iter even with "1 branch" loop.
- MEASURED: inline asm of the exact same 4-instruction loop runs at 341ms (1 cycle/iter); Rex binary was 665ms (2 cycles/iter).
**Fix:** after emitting the jge placeholder in `.fs_patch` (for the pinned rotation path), emit 1–31 NOP bytes
to advance `body_start` to the **next 32-byte boundary**: `NOPs = (0x20 - (out_idx & 0x1F)) & 0x1F`.
Then record `for_rotation_body_pc = out_idx`. Hot loop lives entirely in ONE 32-byte µop-cache set → 1 branch/iter.
**Rule:** any future loop optimization that creates a bottom-tested loop MUST ensure the loop body is in a
DIFFERENT 32-byte set from any pre-loop guard. The guard's `jge`/`jne` WILL be re-issued by the µop cache
every iteration otherwise, burning port 6 capacity.
**BSS added:** `for_rotation_end_val resq 1`, `for_rotation_body_pc resq 1`, `for_rotation_nop_cnt resb 1`.
In `for_end` (pinned path), back-edge is now `.fe_pin_jmp` (rotation); non-pinned still uses `.fe_jmp` (unconditional jmp).

## O15: Strength-Reduction — sub/mul/div Fusion (IMPLEMENTED)
Extends O14 to fuse `:accum = accum OP pin` for OP = -, *, /  in addition to +.
- **sub:** `sub r14,r15` = `4D 29 FE`
- **mul:** `imul r14,r15` = `4D 0F AF F7`
- **div:** `mov rax,r14; cqo; idiv r15; mov r14,rax` = `4C 89 F0 48 99 49 F7 FF 49 89 C6`
BSS `sr_op` (resb 1) distinguishes op type (0=add 1=sub 2=mul 3=div).
`.srv_do_promote` dispatches on sr_op for deferred case. Sub/mul/div emitters now contain
the same candidate/deferred/normal structure as `codegen_emit_add_rax_rbx`.

## FLC: Frameless Calling Convention (IMPLEMENTED)
Eliminates `push rbp; mov rbp,rsp` from every protocol prologue. Replaces rbp-relative
frame addressing with rsp-relative (bottom-up slot layout). Epilogue: `add rsp,N; ret`
instead of `leave; ret`. Saves ~2 prologue instructions per call + 1 µop per epilogue.
**Measured gain:** fib(42) 1355ms → 1288ms (~67ms, ~5%); smaller than projected (CPU stack engine
makes push rbp / mov rbp,rsp cheap on modern hardware — near-zero latency via register renaming).
**Frame layout (bottom-up):** slot K → [rsp+K*8]. Slots: 0=r12 save, 1=r13 save (if regalloc_cnt=2),
then param slots at regalloc_cnt, then locals above.
**Slot access encoding (rsp-relative):** `[rsp+K*8]` requires SIB byte 0x24:
  - read rax:  `48 8B 44 24 <K*8>` (5 bytes vs 4 for rbp-relative)
  - write rax: `48 89 44 24 <K*8>`
  - read rdi:  `48 8B 7C 24 <K*8>`
**O18 slot saves/restores (CRITICAL ModRM encoding):**
  - `mov [rsp],r12`  = `4C 89 24 24` (ModRM=0x24: mod=00 reg=100=r12[3:0] rm=100=SIB)
  - `mov r12,[rsp]`  = `4C 8B 24 24`
  - `mov [rsp+8],r13` = `4C 89 6C 24 08` (ModRM=0x6C: mod=01 reg=101=r13[3:0] rm=100=SIB)
  - `mov r13,[rsp+8]` = `4C 8B 6C 24 08`
  **Bug fixed:** `0x04`/`0x4C` (r8/r9 reg fields) were used as ModRM; correct is `0x24`/`0x6C`
  (r12/r13 lower 3 bits are 100/101, not 000/001). Verify: r12=12=0b1100→low3=100; r13=13=0b1101→low3=101.
**Leave patch mechanism:** `codegen_emit_leave` emits `add rsp,imm32` placeholder (48 81 C4 00000000)
and records the imm32 offset in `leave_patch_list` (BSS: resq 16). `codegen_clear_frame` patches
both `sub rsp` prologue AND all `add rsp` epilogues with the same computed frame_size.
**prot_fs encoding (parser.asm):** after emitting ModRM (now 0x7C/0x74/0x54/0x4C/0x44/0x4C for SIB form),
emit SIB=0x24, then disp8=(K+regalloc_cnt)*8 positive (not neg). Old table was rbp-relative.
**Remaining gap with C fib:** Rex spills/reloads local a and b to frame on every non-leaf call
(4 mem ops). C uses callee-saved rbx to hold fib(n-1) across the second recursive call (0 mem ops).

## O18: Register Allocator — Pin Protocol Params to r12/r13 (IMPLEMENTED)
Pins first min(param_cnt, 2) protocol params to callee-saved registers r12/r13.
**Frame layout** (regalloc_cnt=N): slots 0..N-1 are r12/r13 saves (FLC bottom-up); O1 param/local
slots at K+N. `codegen_find_frame_slot` adds regalloc_cnt to all return values so all callers auto-correct.
**BSS:** `sr_op resb 1`, `regalloc_active resb 1`, `regalloc_cnt resb 1`, `regalloc_vars resb 2`
**Entry/exit sequences** emitted by `codegen_emit_frame_prologue` and `codegen_emit_regalloc_epilogue`.
**Regalloc read:** `mov rax,r12` (4C 89 E0) or `mov rax,r13` (4C 89 E8).
**Regalloc write:** `mov r12,rax` (49 89 C4) or `mov r13,rax` (49 89 C5).
**Priority:** O13 accum and O2 pin checks are BEFORE O18 in read path; O18 store write
guards against intercepting the active O13 accumulator via `loop_accum_active` check.
**Known trade-off:** O18 adds mem ops per call. For deep-recursive protocols (fib: 700M calls,
few param reads) this HURTS vs no-regalloc; store-to-load forwarding already makes frame reads
cheap. O18 HELPS loop-heavy protocols called once with many param reads in the body.
**TCO interaction:** r12 holds OLD param if TCO fires — latent correctness bug for regalloc protocols.
Fib/sum/alloc do not trigger TCO.

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

## O21: Push-Style Prologue for 1-Param Protocols (IMPLEMENTED)
Replaces `sub rsp,N; mov [rsp],r12; mov r12,rdi` with `push r12; mov r12,rdi; sub rsp,N`.
Eliminates the stack save of r12 at function entry (the push IS the save) and the
`mov r12,[rsp]` restore (replaced by `pop r12` at epilogue).
**BSS:** `push_style_frame resb 1` in codegen.asm. Set by `codegen_set_frame` when
param_cnt==1 AND regalloc_cnt==1. Cleared at `codegen_clear_frame`.
**Prologue:** emits `41 54` (push r12) + `49 89 FC` (mov r12,rdi) + `48 81 EC 00000000` (sub rsp placeholder).
**Epilogue:** `codegen_emit_regalloc_epilogue` emits `41 5C` (pop r12) instead of `4C 8B 24 24` (mov r12,[rsp]).
**proto_emit_restore order (CRITICAL):** push-style = leave THEN pop r12 (leave adjusts rsp first,
then pop undoes the push). Standard = regalloc-restore THEN leave.
**Frame slot for param 0:** `codegen_find_frame_slot` returns slot=1 (not -1) for param 0
in push-style, so Gap-1 correctly skips caller-save (r12 is callee-saved by the push/pop pair).
**Performance:** Rex fib(40) ~454ms vs C ~142ms = 3.2× (improved from 3.4×).

## O20: Self-Recursive Protocol Flag (IMPLEMENTED)
BSS `proto_is_self_recursive resb 1` set to 1 in parse_prot `.prt_do_normal` when the
called proto_idx equals `cur_proto_idx`. Reset to 0 at each `.prot` entry. Carries the
information that the current protocol calls itself (for future optimizations).

## @memo: Algorithmic Memoization (IMPLEMENTED)
Syntax: `memo proto name(n): ...` — `memo` keyword (TOK_MEMO=86) before `proto`.
Lexer: matches dword `0x6F6D656D` ("memo"), emits TOK_MEMO via `.kmemo` handler.
Parser: `next_proto_memo` BSS flag set on TOK_MEMO; latched into `proto_memo_active` at `.prot`.
**Cache:** per-protocol pointer at `MEMO_PTR_BASE + proto_idx*8` (= 0x445000 for proto 0).
  Pointer is null until first call; then `rt_alc(8192)` allocates 1024×8-byte table,
  filled with -1 (sentinel = uncached). Key = param value (assumed non-negative integer ≤ 1023).
**codegen_emit_memo_check:** emitted at protocol body entry by parser at `.prot_nobody`.
  Alloc path is **46 bytes** (NOT 48 — `mov [addr],r11` is 8 bytes: 4D 89 1C 25 + addr32).
  jnz offset must be 46 (0x2E). Bug: was 48 (0x30) → jumped 2 bytes INTO the cmp instruction → segfault.
  Cache hit path: `mov rbx,[r11+r12*8]; cmp rbx,-1; je .miss; mov rax,rbx; epilogue; ret`.
  REX encoding: `4B 8B 1C E3` (REX.WXB, ModRM=1C, SIB=E3: scale=8, index=r12, base=r11).
**codegen_emit_memo_store:** emitted before every epilogue by `proto_emit_restore`.
  Bounds-checks n < 1024 then stores: `mov [r11+r12*8], rax` = `4B 89 04 E3`.
  Table pointer reloaded from MEMO_PTR_BASE (not cached in register across calls).
**MEMO_PTR_BASE=0x445000** (safe: var storage ends at 0x444000, no collision).
**Performance:** @memo fib(40) ~3ms vs non-memo ~454ms — effectively O(n) instead of O(2^n).
**Known limitation:** `ret expr` (direct expression return, e.g. `ret n*n`) returns -1 on first
  cache miss (pre-existing); use `int x = expr; ret x` as workaround.

## memo_reset: Cache Invalidation Keyword (IMPLEMENTED)
Syntax: `memo_reset <proto_name>` — clears a protocol's memo cache at runtime.
TOK_MEMO_RESET=87. Lexer: after "memo" dword match, checks byte[4]='_' then "reset\0".
**Emitted runtime code (12 bytes):** `mov qword [MEMO_PTR_BASE + proto_idx*8], 0`
  Encoding: `48 C7 04 25 addr32 00000000`. Nulls the pointer slot; the existing
  alloc path in memo_check re-allocates and re-fills with -1 on the next call.
  Register-safe: no caller-saved registers are touched.
**proto_find returns out_idx (body offset), NOT sequential proto index.** proto_find now
  also saves the sequential index to `proto_find_seq_idx` BSS at `.m` match site.
  `.memo_reset` reads `[proto_find_seq_idx]` for the correct rdi to codegen_emit_memo_reset.
  **Why:** using proto_find's rax (= out_idx ≈ 200+) as proto_idx computes
  MEMO_PTR_BASE + out_idx*8 → address outside the mapped segment → segfault.
**Null guard:** if the pointer slot is already 0 (table never allocated), the store is a no-op;
  next call goes through the normal alloc path. Safe to call before any protocol call.

## O23: 2× Unroll + Dual Accumulators (IMPLEMENTED)
Fires when: `loop_accum_active==1` AND body bytes = `4D 01 FE` (`add r14,r15`) AND
`(end_val - from_val) % 2 == 0` AND body_size == 3 (all confirmed at `for_end` time).
**Do NOT check `sr_add_done` in for_end** — that flag is reset to 0 by the O14 store
suppression path (line ~1720) before for_end ever runs. Check `loop_accum_active` and
verify body bytes directly via `lea rcx,[out_buffer]; mov rdx,[for_rotation_body_pc]`.
**Init (emitted before guard in for_start):**
  `xor eax,eax` (31 C0) — zero odd accumulator (rax)
  `lea rbx,[r15+1]` (49 8D 5F 01) — odd counter = from+1
**Body extension (appended in for_end after body):**
  `add rax,rbx` (48 01 D8), `add r15,2` (49 83 C7 02), `add rbx,2` (48 83 C3 02)
**Combine (post-loop after codegen_patch_jump):**
  `add r14,rax` = `4B 01 C6` — REX=0x4B (W=1,R=0,X=0,B=1)
**BSS:** `o23_active resb 1`, `for_rotation_from_val resq 1`.
**Result:** 331ms → 139ms (2.38× on sum 1B); breaks serial add-r14 dependency chain.

## REX Prefix Encoding Rule for `add r14,rax` (CRITICAL — easy to get wrong)
`ADD r/m64, r64` (opcode 01): destination=rm field, source=reg field.
- REX.B extends **rm** (destination); REX.R extends **reg** (source).
- `add r14,rax`: r14 is dest (rm=110, needs REX.B=1); rax is src (reg=000, REX.R=0)
  → REX = 0100_1011 = **0x4B**. Encoding: `4B 01 C6`.
- `add r14,r15`: both need extension → REX.R=1, REX.B=1 → **0x4D**. Encoding: `4D 01 FE`.
- `add rax,rbx`: neither needs extension → REX.W only → **0x48**. Encoding: `48 01 D8`.
- Confusion: 0x4C = W=1,R=1,X=0,B=0 → encodes `add rsi,r8` (NOT r14). Bug 7 was exactly this.

## O24: 4× Unroll + 4 Accumulators (IMPLEMENTED — CRITICAL REX BUG FIXED)
Fires inside O23 path when `(end_val - from_val) % 4 == 0`.
**Init (emitted before guard, after O23 spec init):**
  `xor edx,edx` (31 D2), `lea r8,[r15+2]` (4D 8D 47 02), `xor ecx,ecx` (31 C9), `lea r9,[r15+3]` (4D 8D 4F 03)
**Body extension (appended after O23 extensions):**
  `add rdx,r8` = `4C 01 C2`, `add rcx,r9` = `4C 01 C9`, `add r8,4` = `49 83 C0 04`, `add r9,4` = `49 83 C1 04`
**Patching:** also changes O23's `add r15,2` → `add r15,4` (body_pc+9) and `add rbx,2` → `add rbx,4` (body_pc+13).
**Combine (after O23 combine):**
  `add r14,rdx` = `4B 01 D6`, `add r14,rcx` = `4B 01 CE`
**CRITICAL BUG FIXED:** REX byte for `add rdx,r8` and `add rcx,r9` must be **0x4C** (REX.R=1 extends reg field 000/001 → r8/r9), NOT 0x4A (REX.R=0, REX.X=1 → encodes `add rdx,rax` / `add rcx,rcx` instead). 0x4A vs 0x4C differs by exactly bit 2 (REX.R). Symptom: 0..4 sum gave 2 instead of 6; the `add rcx,rcx` doubled a zero, giving 0.
**Rule:** for `ADD r/m64, r64` (opcode 01), REX.R extends the SOURCE (reg field). r8–r15 as SOURCE need REX.R=1. r8–r15 as DESTINATION (rm field) need REX.B=1.

## Dead Blob Elimination + Short Back-edge JMP (IMPLEMENTED)
**Dead blob elimination:** `prescan_blobs` in main.asm scans source for 4-byte keyword patterns (BLOB_MASK constants); `codegen_init` emits only the blobs needed, records actual VAs into BSS (`actual_pri_va` etc.). Result: int-only sum benchmark = 1850 bytes vs 8448+ with all blobs.
**Caveat:** prescan scans raw bytes including comments/strings — false positives are harmless (extra blobs included = slightly larger binary, still correct).
**Short back-edge JMP:** in `.fe_pin_jmp`, computes target_VA = body_pc + LOAD_BASE; if `target_VA - VA_after_short_jl >= -128`, emits 2-byte `7C rel8`; else 6-byte `0F 8C rel32`. For 1B iteration loop: saves 4 bytes + avoids 32-bit displacement decode per iteration.

## Rex Protocol Call Syntax
Rex uses `@name(args)` NOT `name(args)` for protocol calls. In parse_factor, `TOK_AT`
dispatches to `.prt` which calls `proto_find`. Plain `TOK_IDENT` goes to `.idn` (var lookup)
and returns 0 if not a variable — protocol names are NOT valid as bare identifiers in expressions.
**Why this matters for debugging:** `output(fib(10))` outputs 0 (silent wrong result);
correct is `output(@fib(10))`. Always use `@` prefix when calling protocols.

## Compound Assignment `a = expr` (IMPLEMENTED)
Syntax: bare identifier followed by `TOK_ASSIGN` (no leading colon — colon signals declaration).
**Location:** parser.asm, `.ident_stmt`. After saving ident name and calling `lexer_next`,
if next token == TOK_ASSIGN: call `var_find` (looks up existing var), `lexer_next`, `parse_expr`
(full order-of-operations expr), then `codegen_emit_store_rax_to_var`.
**Why separate from declaration:** declaration is `int :x = expr` — starts with a type keyword,
then colon-prefixed ident. Bare `x = expr` (no colon, no type keyword) reuses `.ident_stmt`.
**Verified:** `x = y * 4 + 2` → 14 (y=3), `y = x / 3 - 1` → 3 (x=14). Correct OoO.

## O25: LEA Tree Combine for O23+O24 Post-Loop (IMPLEMENTED)
Replaces the old `add r14,rcx` (4B 01 CE) in `.fe_o25_tree` with `lea r14,[r14+rcx]` (4D 8D 34 0E).
**Encoding:** REX=0x4D (W=1,R=1,X=0,B=1), opcode=0x8D, ModRM=0x34 (mod=00,reg=110,rm=100=SIB),
SIB=0x0E (scale=00,index=001=rcx,base=110=r14). Scales from base+index with no displacement.
**Why LEA over ADD:** ADD is port 0; LEA ([base+index]) dispatches to p1 or p5, freeing port 0
for the parallel `add rax,rdx` in step 1a. Reduces 3 serial r14 dependencies to 2.
**Verified:** sum reduction O23+O24 path gives 4999999950000000 (1..1e8 sum) in 15ms.

## O28: Inner-Loop Register Promotion via Retroactive Byte-Patching (IMPLEMENTED)
Promotes up to 2 non-pin/non-accum variables to r12/r13 within the inner loop of a nested
`for` pair. Active only when `regalloc_active==0` and `loop_pin_depth==1→2`.
**Mechanism:**
1. **for_start hook** (`.fs_cond_global`, before `inc loop_pin_depth`): when depth==1 and
   regalloc_active==0, emit 2×8-byte Intel long NOPs as patchable header slots; record
   `o28_header_pos` (out_idx before NOPs) and `o28_inner_loop_var` (the loop pin var).
2. **body_start** recorded in `.fs_push_cont` immediately after the header.
3. **for_end scan** (`codegen_o28_scan_body`): at for_end entry (before back-edge), scans
   body bytes `[o28_body_start..out_idx]` for `48 8B 04 25 addr32` (8-byte global load) and
   `48 89 04 25 addr32` (8-byte global store) of variables that are NOT the inner loop counter.
   Promotes up to 2 unique addrs: slot 0→r12, slot 1→r13.
4. **Patch loads:** 8 bytes at match site → `4C 89 E0 90 90 90 90 90` (mov rax,r12 + 5 NOPs)
   or `4C 89 E8 90 90 90 90 90` (mov rax,r13 + 5 NOPs).
5. **Patch stores:** `48 89 04 25 addr32` (7 bytes+junk) → `49 89 C4 90 90 90 90 90` (r12)
   or `49 89 C5 90 90 90 90 90` (r13).
6. **Header patch** (`codegen_o28_scan_body`): overwrites the 2×8-byte NOPs with
   `mov r12,[addr32]` = `4C 8B 24 25 addr32` (8B) + padding and same for r13.
7. **Flush emit** (`.fe_after_jmp`, after `codegen_patch_jump`): `codegen_o28_emit_flushes`
   emits `mov [addr32],r12` = `4C 89 24 25 addr32` for each promoted slot. Lands exactly
   at the jge jump target. Then `o28_active=0` reset.
**Register slots:** 0=r12, 1=r13 only. r14 excluded (O13 accum). r15 is loop pin.
**BSS added:** `o28_active`, `o28_var_count`, `o28_var_addrs resq 2`, `o28_inner_loop_var`,
  `o28_header_pos`, `o28_body_start` — all in codegen.asm BSS after `o24_active`.
**Depth guard:** flush fires only when `loop_pin_depth==2` (inner loop); checked in `.fe_after_jmp`.
**B7 result:** correct fib(81)=37889062373143906 at 1.574s. All 5 benchmarks pass.
**Key encodings (must be exact):**
  - Pre-load r12: `4C 8B 24 25 <addr32>` (8 bytes)
  - Pre-load r13: `4C 8B 2C 25 <addr32>` (8 bytes)
  - Flush r12:    `4C 89 24 25 <addr32>` (8 bytes)
  - Flush r13:    `4C 89 2C 25 <addr32>` (8 bytes)
  - Body load→r12 patch:  `4C 89 E0 90 90 90 90 90` (8 bytes, replaces 8-byte global load)
  - Body load→r13 patch:  `4C 89 E8 90 90 90 90 90`
  - Body store←r12 patch: `49 89 C4 90 90 90 90 90` (8 bytes, replaces 7-byte global store)
  - Body store←r13 patch: `49 89 C5 90 90 90 90 90`
