---
name: Rex V5.0 compiler architecture
description: Key decisions, bugs, offsets, and conventions for the Rex V5.0 NASM compiler.
---

## Build
- `make` assembles 6 object files (main, lexer, parser, codegen, headers, runtime) and links with `ld`.
- NASM 2.15.05 from `~/.nix-profile/bin/nasm` segfaults in this Replit environment. Use nasm 2.16+ or CI.
- `rexc.asm` (old monolithic file) has been deleted. All content is now modular.

## NASM Semicolon Bug (FIXED)
- NASM treats `;` as a comment, so `instruction1; instruction2` on one line only executes instruction1.
- Was present in `codegen_emit_float_op`, `codegen_emit_complex_op`, and `codegen_output_typed`.
- Fix: every instruction on its own line. All known instances fixed.

## Dict Runtime Offsets
- `RT_DICT_NEW_OFFSET=7550`, `RT_DICT_SET_OFFSET=7577`, `RT_DICT_GET_OFFSET=7626` — offsets from
  start of binary (after 120-byte ELF header + 5-byte runtime skip JMP) where rt_dict_new/set/get
  live inside rt_prq_blob.
- These are hardcoded in `include/rex_defs.inc`. If any preceding blob size changes, re-measure.

## Key Variable Layout
- `var_table` entry: name[0..31] | value[32..39] | is_init[40] | type[48] (size=64).
- `VAR_STORAGE_BASE=0x440000`. `get_var_va(idx)` returns `0x440000 + idx*64`.
- `cur_type` (resb 1 in parser.bss) holds type of last expression atom for output dispatch.
  **Caveat:** cur_type only reflects the last atom; mixed-type expressions give wrong output routing.

## Expression Parser (parser.asm)
- Precedence: bitor > bitxor > bitand > cmp > shift > additive > term > unary > factor.
- parse_expr is NOT global (file-local). Called internally by parse_stmt, parse_dict_inline, etc.
- Binary op pattern: emit push rax (50), parse right, emit mov rbx,rax (48 89 C3), pop rax (58), emit op.
- Comparison: `emit_cmp_binop_setup` emits (48 89 C3 + 58); then `codegen_emit_cmp_rax_rbx_jcc(rdi=op_tok)`
  emits cmp rax,rbx (48 39 D8) + inverted two-byte Jcc (0F XX 00 00 00 00) + pushes patch offset.
- Helper functions `emit_cmp_binop_setup` and `emit_movzx_rax_al` are file-local in parser.asm.

## Codegen Global Functions
- `codegen_output_rax_int`: emits mov rdi,rax + call rt_pri.
- `codegen_output_rax_float`: emits mov rdi,rax + call rt_prf.
- `codegen_output_rax_bool`: emits mov rdi,rax + call rt_prb.
- `codegen_output_rax_str`: emits mov rdi,rax + call rt_prs.
- `codegen_emit_store_rax_var(rdi=idx)`: emits mov [addr32],rax.
- `codegen_emit_cmp_rax_rbx_jcc(rdi=op_tok)`: emits cmp+inverted Jcc, pushes to jump_patch_stack.
- `codegen_emit_while_start`: saves current break_jump_depth to break_base_stack, inc break_base_depth.
  Called by BOTH `.for` and `.while` parser handlers before the loop condition.
- `codegen_patch_breaks`: dec break_base_depth, patches all break jumps from that base to current offset.
- `emit_b`, `emit_d`, `emit_q`, `get_var_va` are `global` (exported for parser use).

## Runtime Blob Layout (within RT segment)
- All blobs are padded with NOPs (0x90) via `times RT_Xxx_SIZE - ($ - rt_xxx_blob) db 0x90`.
- `rt_prs_blob` (512B): null-terminated string printer via sys_write + newline.
- `rt_prb_blob` (256B): bool printer — prints "true\n", "false\n", or "unknown\n". Data labels at end.
- `rt_prc_blob` (512B): complex printer "(real+imagj)\n". Contains helper `rt_prf_nonnl` (float
  print without newline). Calling convention: RDI = pointer to 128-bit complex storage (two doubles).
- `codegen_output_typed` for TYPE_COMPLEX: patches emitted MOV (8B) → LEA (8D) at out_idx-7 so that
  RDI receives the variable's address, not its (truncated) 64-bit value.
- `rt_prf_nonnl` (inside rt_prc_blob region): calls `rt_pri_no_nl` (backward ref inside rt_prf_blob).
  NASM resolves both within runtime.asm; relative offset survives copy into output binary.

## Token Constants (rex_defs.inc)
- TOK_EQEQ=14, TOK_NEQ=49, TOK_LT=47, TOK_GT=48, TOK_LTE=50, TOK_GTE=51
- Inverted Jcc second bytes: EQEQ→JNE(85), NEQ→JE(84), LT→JGE(8D), GT→JLE(8E), LTE→JG(8F), GTE→JL(8C)
- TOK_TRUE, TOK_FALSE, TOK_UNKNOWN — handled in parse_factor as TYPE_BOOL atoms.
- TOK_STR_LIT — handled in parse_factor: emits JMP-over-data + string bytes + null + MOV rax,VA.
  String VA = LOAD_BASE + out_idx_at_string_start. JMP patched at out_idx-4+1 (after E9 opcode).

## use_mm Pool Detection
- Old code: `cmp byte [tok_ident], 'p'` (only checked first char).
- Fixed: `cmp dword [tok_ident], 0x6C6F6F70` (= "pool" LE) + `cmp byte [tok_ident+4], 0`.

## Remaining Open Issues (see docs/issues.md)
- Dict offsets hardcoded — will break if blob sizes change.
- for-loop range bounds must be integer literals (parse_expr cannot be used without redesigning codegen_emit_for_start).
- cur_type is last-atom only — mixed-type expressions may misroute output.
- ELF p_memsz is static 0x80000; output buffer has no bounds check.
