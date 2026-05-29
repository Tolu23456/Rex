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

## Expression Parser — Type Propagation (IMPLEMENTED)
- `parse_additive` and `parse_term` now push r14 at entry (callee-saved; popped at all exits).
- After each binary op (`+`, `-`, `*`, `/`), if LHS type (saved in r14d via `movzx r14d, [cur_type]`)
  was TYPE_FLOAT, set `[cur_type] = TYPE_FLOAT` (float dominates). Mod (`%`) always yields int.
- **Why:** previously cur_type only reflected the last atom; mixed-type sums gave wrong output routing.
- **How to apply:** every `pop r14; leave; ret` must appear at ALL exits of parse_additive/parse_term.

## Proto Table Entry Layout (48 bytes) — FINALIZED
- [0..31]=name (null-padded), [32..39]=out_idx offset (qword), [40]=param_count (byte),
  [41..46]=param var indices (one byte each, up to 6 params), [47]=padding.
- `proto_find` and `.protocol` both use `imul rax, 48`. Old 40-byte size is gone.
- **Why:** 48 bytes needed for 6 param slots; must be consistent between find and write paths.
- **How to apply:** any new proto table traversal MUST use `imul rax, 48`.

## Parameterized Protocols (IMPLEMENTED)
- Syntax: `prot name(a, b):` or `prot name():`.
- `.protocol` handler: parses param names via `var_add(TYPE_INT)`, stores var indices at [r13+41+i].
- After param parse, emits `mov [var_addr], reg` for each param (rdi=0x3C, rsi=0x34, rdx=0x14, rcx=0x0C
  as ModRM bytes for the MOV r/m64,r64 + SIB absolute-addr form: 48 89 XX 25 <addr32>).
- Body parsing skips ':', NEWLINE, INDENT via 3 `call lexer_next` before the body loop.
- No-paren style `prot name:` still works (falls through to `.prot_no_params`).

## Protocol Call With Args (IMPLEMENTED)
- `emit_at_call_args` (file-local helper in parser.asm): called when tok=TOK_LPAREN.
  Evaluates comma-separated arg expressions, emits `push rax` after each (in order).
  Then emits pop opcodes in reverse: arg[n-1]→last reg, arg[0]→rdi.
  Pop opcodes: rdi=0x5F, rsi=0x5E, rdx=0x5A, rcx=0x59.
  Advances tok past ')'. Returns arg count in rax.
- Used from both `.at_call` (parse_stmt) and `.at_in_expr` (parse_factor).
- `.at_in_expr` saves/restores r12 with explicit push/pop (parse_factor prologue only saves rbx).

## Dynamic Sequences (IMPLEMENTED)
- Syntax: `seq x` (declare), `push x val` (append), `val = pop x` (remove last), `n = len x` (length).
- Heap block layout: [+0: cap u64][+8: len u64][+16..: data u64 array]. Initial alloc=80 bytes (cap=8).
- `seq x` → `call rt_alc(80)`, store ptr, set [ptr]=8, [ptr+8]=0.
- `push x v` → push rax (save v), load ptr into rbx, load [rbx+8] into rcx, pop rax,
  store [rbx+rcx*8+16] = rax (SIB byte 0xCB = rcx*8+rbx), inc [rbx+8].
- `pop x` (expr) → load ptr into rbx, dec [rbx+8], load new len into rcx,
  load [rbx+rcx*8+16] into rax.
- `len x` (expr) → load ptr into rax, load [rax+8] into rax.
- No bounds check or realloc implemented (cap is fixed at initial 8 slots).

## err Statement (IMPLEMENTED)
- Syntax: `err "message"` — evaluates a string expression, calls `rt_err_blob`.
- `rt_err_blob` (128 bytes at RT_ERR_OFFSET=8573): writes null-terminated string to fd=2 (stderr),
  then writes a newline byte (allocated on stack via sub rsp,8 / mov byte[rsp],10 / add rsp,8).
- Emits: `mov rdi, rax` (48 89 C7) + `call rt_err` (E8 <rel32 using LOAD_BASE+RT_ERR_OFFSET>).

## Runtime Blob Layout (within RT segment)
- All blobs are padded with NOPs (0x90) via `times RT_Xxx_SIZE - ($ - rt_xxx_blob) db 0x90`.
- `rt_prq_blob` ends at offset 8573 from binary start. `rt_err_blob` immediately follows.
- `rt_prs_blob` (512B): null-terminated string printer via sys_write + newline.
- `rt_prb_blob` (256B): bool printer — prints "true\n", "false\n", or "unknown\n". Data labels at end.
- `rt_prc_blob` (512B): complex printer "(real+imagj)\n". Contains helper `rt_prf_nonnl`.
- `codegen_output_typed` for TYPE_COMPLEX: patches emitted MOV (8B) → LEA (8D) at out_idx-7 so that
  RDI receives the variable's address, not its (truncated) 64-bit value.

## Token Constants (rex_defs.inc)
- TOK_EQEQ=14, TOK_NEQ=49, TOK_LT=47, TOK_GT=48, TOK_LTE=50, TOK_GTE=51
- TOK_ERR=59, TOK_TYPE_SEQ=60, TOK_PUSH=61, TOK_POP=62, TOK_LEN=63
- TOK_TRUE, TOK_FALSE, TOK_UNKNOWN — handled in parse_factor as TYPE_BOOL atoms.
- TOK_STR_LIT — handled in parse_factor: emits JMP-over-data + string bytes + null + MOV rax,VA.
- TOK_AT=21 — dispatched in parse_stmt (.at_call) and parse_factor (.at_in_expr).

## Lexer Keyword Detection
- New keywords `err`, `seq`, `push`, `pop`, `len` added in `lexer_classify` via `.check_new_kw` label
  (inserted before `.default_id` at the bottom of the keyword chain). Uses 4-byte dword comparison.
- `push` = 0x68737570 ('h','s','u','p' LE), `pop` = 0x00706F70, `len` = 0x006E656C,
  `err` = 0x00727265, `seq` = 0x00716573.

## use_mm Pool Detection
- Old code: `cmp byte [tok_ident], 'p'` (only checked first char).
- Fixed: `cmp dword [tok_ident], 0x6C6F6F70` (= "pool" LE) + `cmp byte [tok_ident+4], 0`.

## Remaining Open Issues (see docs/issues.md)
- Dict offsets hardcoded — will break if blob sizes change.
- for-loop range bounds must be integer literals.
- No sequence bounds check / realloc (fixed cap=8 slots).
- VAR_MAX=128 — no var table growth.
- Proto params limited to 4 (rdi/rsi/rdx/rcx); 5th/6th slot stored but not emitted.
- ELF p_memsz is static 0x80000; output buffer has no bounds check.
