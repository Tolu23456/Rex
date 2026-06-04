# Rex V5.0 Compiler — Changelog

All notable changes to the Rex bootstrap compiler are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### Added
- `docs/grammar.md` — formal EBNF grammar covering all 35 productions: every
  statement, expression tier, literal form, operator precedence table, reserved
  keyword list, variable table layout (64-byte entries), and protocol table
  layout (48-byte entries). Planned productions marked 📋 for completeness.

### Planned
- `not` operator — `xor rax, 1` for `bool`, `not rax` for `int`
- `is` / `is not` — semantic identity check via `cmp` + `sete`/`setne`
- `stop N` — multi-level break; depth counter in break-patch stack
- Loop `else:` — executes when loop exits naturally without `stop`
- `repeat N:` — counted loop; emits single `dec`/`jnz` hardware loop
- `in` operator — membership check for `seq`, `dict`, `str`
- `each` iterator — cache-aligned sequential collection sweep
- `str(expr)` cast + `rt_str_cat` blob — string conversion and concatenation
- Per-call protocol stack frames — fixes recursive protocol issue (#18)
- Variable key dict subscript `d[x]` — fixes issue #23
- `when` O(1) jump table — replaces O(K) linear case chain (issue #27)
- Sequence bounds check on element reads — hardware guard (issue #28)

---

## [5.7.0] — Stage 7 Complete

### Added
- `err` non-string guard: `.err_stmt` now checks `cur_type` after `parse_expr`;
  non-string types are routed through the correct printer then `exit(1)` via
  `codegen_emit_exit1`. Prevents segfault from passing an integer to the strlen loop.
- `codegen_emit_exit1`: new global in `codegen.asm` — emits `mov rax,60; mov rdi,1;
  syscall`. Extern'd in `parser.asm`; available for all error-exit emission sites.
- `VAR_MAX` overflow guard confirmed in `var_add`: `cmp rbx, VAR_MAX; jge .full`
  already present and correct; status updated in `docs/issues.md`.
- `out_buffer` overflow guard in `emit_b`: halts with `rt_err_blob` if
  `out_idx >= 131071`; buffer expanded to `resb 131072` (128 KiB).
- Expression type propagation: `parse_additive` and `parse_term` push `r14`
  (callee-saved) at entry; LHS type tracked through `+`, `-`, `*`, `/` chains.
  Float dominates; `%` always yields `TYPE_INT`.

### Fixed
- Issue #9: `emit_b` buffer overflow — guard added, buffer size doubled to 128 KiB.
- Issue #21: `VAR_MAX` ceiling confirmed guarded; status corrected in issue tracker.
- Issue #25 (partial): `err` with non-string argument no longer segfaults; prints
  value via correct typed printer then exits. Full `int → str` conversion pending (#24).
- Issue #4: Expression type tracking now covers full sub-expression chains, not just
  the last atom.

---

## [5.6.0] — Stage 6 Complete / Short-Circuit Logic

### Added
- Short-circuit `and` / `or` evaluation: `and` emits `test+jz` to skip RHS when LHS
  is false; `or` emits `test+jnz` to skip RHS when LHS is true.
- New codegen helpers: `codegen_emit_test_rax_jnz`, `codegen_emit_normalize_bool_rax`,
  `codegen_emit_jmp_get_slot`, `codegen_patch_slot_to_here`.
- `skip N` depth argument wired: `codegen_emit_skip` now accepts `rdi=depth` and
  walks `N-1` levels from the top of `cont_base_stack`.
- Nested `when` fix: `when_var_stack` (resq 8) and `when_cnt_stack` (resq 8) plus
  `when_stk_depth` added; each `when` pushes both globals on entry and pops on exit.
- `parse_factor` default case now calls `lexer_next` before the fallthrough `xor eax,eax`
  path — unknown tokens are consumed rather than causing an infinite spin.
- `scope_stack` save/restore wraps `for`-loop synthetic variable additions; both the
  loop counter and end-bound variable slots are reclaimed after `codegen_emit_for_end`.

### Fixed
- Issue #33: `and`/`or` eager evaluation replaced with short-circuit emission.
- Issue #32: Nested `when` statements no longer corrupt `when_var_idx` of the outer block.
- Issue #35: `parse_factor` default case infinite spin on unknown token eliminated.
- Issue #36: `and`/`or` documentation corrected to `✅` in `syn.md` and `docs/issues.md`.
- Issue #37: For-loop end variable `_fe` no longer leaks a `var_table` slot.

---

## [5.5.0] — Advanced Protocols / Float Return Type

### Added
- Protocol return type stored in `proto_table[entry+47]` (`ret_type` byte).
- `proto_ret_type` BSS in `parser.asm` mirrors `[entry+47]` after every `proto_find`.
- `.ret` stores `cur_type` into `[entry+47]` at protocol exit.
- `.at_in_expr` restores `cur_type` from `proto_ret_type` after the call — float-
  returning protocols now dispatch to `rt_prf` instead of `rt_pri`.
- Protocol local variables reclaimed: `var_count` pushed onto `scope_stack` before
  the protocol body and restored on exit.
- `emit_b_indirect` and `emit_d_indirect` now `jmp codegen_emit_b_raw` /
  `jmp codegen_emit_d_raw` — previously no-ops.
- `codegen_get_var_va_proxy` added as a global wrapper for `get_var_va`.
- Parameterized protocols extended to 6 parameters: r8 (REX 0x4C, ModRM 0x04) and
  r9 (REX 0x4C, ModRM 0x0C) emission added to `.prot_store_params`.
- `codegen_emit_arg_pops` extended to match: r8 and r9 pop opcodes added.

### Fixed
- Issue #15: Float return type no longer lost through protocol calls.
- Issue #16: `emit_b_indirect` / `emit_d_indirect` were no-ops; now functional.
- Issue #14: Protocol parameters 4 and 5 (r8/r9) no longer silently dropped.
- Issue #26: Protocol local variables no longer persist after protocol return.

---

## [5.4.0] — Stage 4 Complete / Collections

### Added
- `dict` type: SipHash-2-4 open-addressing hash map. `dict d`, `d["key"] = val`,
  `:v = d["key"]`. Runtime blobs: `rt_sip`, `rt_dict_new`, `rt_dict_set`, `rt_dict_get`
  inside `rt_prq_blob`.
- `seq` type: dynamic sequence. `seq s`, `push s v`, `:v = pop s`, `:n = len s`,
  `:c = cap s`. Initial capacity 8 slots; auto-grows on overflow.
- `seq push` inline grow block: 57-byte guarded grow emitted by `codegen_emit_seq_push`.
  On overflow: saves old cap, calls `rt_alc(16 + old_cap*16)`, copies elements with
  `rep movsq`, updates pointer in `var_table`. Growth is unbounded.
- `swap x y`: exchanges two int variables via `xchg rax, rbx`.
  Token `TOK_SWAP=74`. `codegen_emit_swap_vars` implemented.
- `abs(x)`: absolute value via `mov rbx,rax; neg rax; cmovs rax,rbx`.
  Token `TOK_ABS=75`. `codegen_emit_abs_rax` implemented.
- `cap x`: reads capacity from hidden sequence header at offset 0.
  Token `TOK_CAP=76`. `codegen_emit_cap_rax` implemented.
- `++x` / `--x`: prefix increment/decrement. Tokens `TOK_PLUSPLUS=72`,
  `TOK_MINUSMINUS=73`. `codegen_emit_inc_var` / `codegen_emit_dec_var` implemented.
- `when x: is N: body ... else: body` — switch-like statement. Token `TOK_IS=77`.
  Parser `.when` creates `__when__` synthetic var; uses `when_case_count`.
- `for step N` bug fixed: premature `mov qword [for_step_val], 1` resets removed from
  `codegen_emit_for_start` and `codegen_emit_for_start_dyn`. Step is now respected.
- Negative `for` bounds: range bounds use `parse_expr`; `for :i in -5..5:` works.

### Fixed
- Issue #19: `seq push` beyond initial capacity fully fixed — inline grow block added.
- Issue #20: Negative for-loop bounds supported via `parse_expr` on both bounds.
- Issue #29: `codegen_emit_abs_rax` CMOVNS → CMOVS correction (`0x49` → `0x48`).
- Issue #30: `for step N` silently ignored — premature step reset removed.
- Issue #5: For-loop range bounds now accept full expressions, not just literals.

---

## [5.3.0] — Stage 3b Complete / Expression System

### Added
- Full expression conditions in `if`, `elif`, `while` — all six comparison operators.
- `true`, `false`, `unknown` as first-class atoms in `parse_factor`.
- String literals as expression atoms — inline embedding in code stream.
- `and` / `or` logical operators (eager evaluation at this stage; short-circuit added
  in v5.6.0).
- `codegen_emit_cmp_rax_rbx_jcc` — generic comparison-then-branch emitter.
- `codegen_output_rax_bool` — routes bool output to `rt_prb_blob`.
- `use mm pool` / `use mm arena` — full string comparison (not just first char).

### Fixed
- Issue #13: `true`, `false`, `unknown`, string literals handled in `parse_factor`.

---

## [5.3.0] — Stage 3 Complete / Additional Types

### Added
- `float` type: XMM registers, SSE2 arithmetic, `rt_prf_blob` printer.
- `bool` tri-state: `true` (1), `false` (0), `unknown` (rdrand). `rt_prb_blob`
  prints "true\n", "false\n", or "unknown\n".
- `str` type: null-terminated UTF-8 pointer. String literals embedded inline in
  code stream. `rt_prs_blob` prints null-terminated string + newline.
- `complex` type: 128-bit XMM pair. `rt_prc_blob` prints `(real+imagj)\n`.
- `typeof x` compile-time reflection — returns `cur_type` token as integer.
- `int(f)` / `float(n)` explicit type casts via `cvttsd2si` / `cvtsi2sd`.
- Binary (`0b`), hex (`0x`), octal (`0o`) integer literals in lexer.
- `//` comment handler fixed: `.eslash` peeks at next byte; scans to `\n` or EOF
  if another `/` is found. Fixes UTF-8 source corruption.
- String literal max length guard: `cmp rbx, 63; jge .strd` added to `tok_ident`
  loop — overlong strings truncated at 63 bytes, not silently corrupted.

### Fixed
- Issue #1: NASM semicolon bug in float/complex codegen — all instruction sequences
  split to individual lines.
- Issue #7: `output` for `str` variables now routes through `rt_prs_blob`.
- Issue #10: `rt_prb_blob` (bool printer) fully implemented.
- Issue #11: `rt_prc_blob` (complex printer) fully implemented.
- Issue #17: `//` comment handler UTF-8 lexer corruption fixed.
- Issue #34: String literal 63-char truncation guard added.

---

## [5.2.0] — Stage 2 Complete / Protocols

### Added
- `prot name():` protocol definition with indented body.
- `return expr` — calls `parse_expr` to evaluate arbitrary expression before `ret`.
  Bare `return` (void) also supported.
- `@name()` standalone protocol call.
- `@name(args)` usable as expression atom in `parse_factor`.
- `proto_table` entries: 48 bytes each — 32 name, 8 out_idx, 1 param_count,
  6 param var indices, 1 ret_type. All lookups use `imul rax, 48`.

### Fixed
- Issue #8: `return` now supports full expressions, not just integer literals.

---

## [5.1.0] — Stage 1 Complete / Control Flow Loops

### Added
- `for :i in 0..N:` range-based loop with INDENT/DEDENT body.
- `for :i in 0..N step S:` range loop with explicit step.
- `while cond:` loop with full expression condition.
- `stop` — breaks the innermost loop via `codegen_emit_break` / break-patch stack.
- `skip` — continues the innermost loop (jumps back to condition check).
- `when x: is N:` switch-like routing block.
- `pass` — zero-byte semantic placeholder for empty blocks.
- `codegen_emit_while_start` saves break-jump base before each loop.
- `codegen_patch_breaks` called at loop exit to patch all JMP placeholders.

### Fixed
- Issue #12: while/break/patch_breaks functions implemented.

---

## [5.0.0] — Stage 0 Complete / Core Infrastructure

### Added
- Modular 6-folder architecture: `main/`, `lexer/`, `parser/`, `codegen/`,
  `headers/`, `runtime/`.
- `int x` mutable variable declaration.
- `int x = 42` immutable constant with inline initialisation.
- `:x = N` mutable assignment with compile-time const guard.
- `output x` / `output N` — routes to `rt_pri_blob` (print signed 64-bit int + newline).
- `if x == N:` conditional branch with JNE patch stack.
- `elif x == N:` chained conditions (unlimited).
- `else:` fallback branch.
- Three-level jump-patch architecture: `jump_patch_stack`, `end_jump_stack`,
  `chain_base_stack`.
- Hand-crafted 64-byte ELF64 header + 56-byte program header (LOAD, RWX, no linker).
- `rt_pri_blob`: prints signed 64-bit integer + newline via `sys_write`.
- `rt_prs_blob`: prints null-terminated string + newline via `sys_write`.
- Variable table: flat array of 64-byte entries (name[32], value[8], is_init[1],
  type[1]); max 128 entries with overflow guard.
- ELF `p_memsz` computed dynamically: `out_idx + 0x44000` covers code + var storage.

### Tests
- `tests/test.rex` → `42`
- `tests/conditional_test.rex` → `1\n2`
- `tests/elif_else_test.rex` → `2\n4`

---

## Key Architecture Constants

| Constant | Value | Meaning |
|---|---|---|
| `VAR_STORAGE_BASE` | `0x440000` | Virtual address of variable storage region |
| `VAR_ENTRY_SIZE` | `64` | Bytes per variable table entry |
| `VAR_MAX` | `128` | Maximum number of variables (guarded) |
| `CODE_START` | `RT_ERR_OFFSET + RT_ERR_SIZE` | Byte offset where user code begins |
| `out_buffer` size | `131072` (128 KiB) | Maximum compiled code size (guarded) |
| Entry point VA | `0x400080` | ELF entry point virtual address |
| Load base VA | `0x400000` | ELF LOAD segment base virtual address |
