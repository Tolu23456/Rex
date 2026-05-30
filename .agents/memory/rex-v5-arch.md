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
3. `abs(x)` — absolute value via `cmovns rax,rbx` pattern. Lexer: TOK_ABS=75.
   codegen: `codegen_emit_abs_rax`. Used as a parse_factor atom.
4. `cap x` — capacity of a sequence (loads qword at [ptr+0]). Lexer: TOK_CAP=76.
   codegen: `codegen_emit_cap_rax`. Used as a parse_factor atom.
5. `when x: is N: body ... else: body` — switch-like statement. Lexer: TOK_IS=77.
   Parser: `.when` creates temp `__when__` var, uses `when_case_count` (BSS) instead of
   accessing codegen-internal `jump_patch_depth`/`chain_base_stack` (which are not exported).
   **Why:** accessing codegen BSS symbols from parser.asm causes "symbol not defined" link errors.
   Each `is` case: load when_var, cmp with literal, `codegen_emit_test_rax_jz`.

## Remaining Open Issues (see docs/issues.md)
- Dict offsets hardcoded — will break if blob sizes change.
- for-loop range bounds must be integer literals.
- No sequence bounds check / realloc (fixed cap=8 slots).
- VAR_MAX=128 — no var table growth.
- ELF p_memsz is static 0x80000; output buffer guard added but no dynamic growth.
