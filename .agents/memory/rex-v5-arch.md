---
name: Rex V5.0 compiler architecture
description: Key decisions, bugs, offsets, and conventions for the Rex V5.0 NASM compiler.
---

## Build
- `make` assembles 6 object files (main, lexer, parser, codegen, headers, runtime) and links with `ld`.
- NASM 2.15.05 from `~/.nix-profile/bin/nasm` segfaults in this Replit environment. Use nasm 2.16+ or CI.
- `rexc.asm` (old monolithic file) has been deleted. All content is now modular.

## NASM Semicolon Bug (pre-existing, not fixed)
- In `codegen/codegen.asm`, `codegen_emit_float_op` and `codegen_emit_complex_op` use `;` to separate instructions on one line. NASM treats `;` as a comment, so only the first instruction on each line executes. Float/complex arithmetic is silently broken. Fix: put each instruction on its own line.

## Dict Runtime Offsets
- `RT_DICT_NEW_OFFSET=7550`, `RT_DICT_SET_OFFSET=7577`, `RT_DICT_GET_OFFSET=7626` — offsets from start of binary (after 120-byte ELF header + 5-byte runtime skip JMP) where rt_dict_new/set/get live inside rt_prq_blob.
- These are hardcoded in `include/rex_defs.inc`. If any preceding blob size changes, re-measure.

## Key Variable Layout
- `var_table` entry: name[0..31] | value[32..39] | is_init[40] | type[48] (size=64).
- `VAR_STORAGE_BASE=0x440000`. `get_var_va(idx)` returns `0x440000 + idx*64`.
- `cur_type` (resb 1 in parser.bss) holds type of last expression atom for output dispatch.

## Expression Parser (parser.asm)
- Precedence: bitor > bitxor > bitand > cmp > shift > additive > term > unary > factor.
- parse_expr is NOT global (file-local). Called internally by parse_stmt, parse_dict_inline, etc.
- Binary op pattern: emit push rax (50), parse right, emit mov rbx,rax (48 89 C3), pop rax (58), emit op.
- Comparison: cmp rax,rbx (48 39 D8) + setXX al + movzx rax,al (48 0F B6 C0).
- Helper functions `emit_cmp_binop_setup` and `emit_movzx_rax_al` are file-local in parser.asm.

## New Codegen Functions (V5.0 additions)
- `codegen_output_rax_int`: emits mov rdi,rax + call rt_pri. For `output expr` (int).
- `codegen_output_rax_float`: emits mov rdi,rax + call rt_prf. For `output expr` (float).
- `codegen_emit_store_rax_var(rdi=idx)`: emits mov [addr32],rax. Used after parse_expr.
- `emit_b`, `emit_d`, `emit_q`, `get_var_va` are now `global` (exported for parser use).

## Remaining Known Issues
- Float arithmetic silent broken (semicolon bug in codegen.asm).
- if/while conditions only support `var == literal`, not full expressions.
- output for str falls back to int printer (rt_prs_blob is a stub).
- Dict offsets hardcoded — will break if blob sizes change.
- See `docs/issues.md` for full list.
