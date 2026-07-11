---
name: Rex compiler bug fixes
description: All bugs found and fixed in the Rex self-hosting x86-64 NASM compiler
---

# Rex Compiler — Bug Catalogue

**Why:** Documents non-obvious root causes so future work avoids re-introducing them.

## Fixed Bugs (chronological)

### Fix 1 — Float token type never set (lexer/lexer.asm)
After lexing a fractional part the `.frac_done` path never wrote `TOK_FLOAT_LIT` to `tok_type`.
Added `mov dword [tok_type], TOK_FLOAT_LIT` in `.frac_done`.

### Fix 2–4 — Runtime blobs stack corruption + unreachable rodata (runtime/*.asm)
- All three runtimes (`rt_prb`, `rt_prs`, `rt_prf`) pushed `rbx`/`rbp` but returned via `ret` without popping → stack corruption crash. Added matching `pop` pairs before each `ret`.
- String/float constants in `.rodata` sections are unreachable from flat `-f bin` blobs. Moved them inline in the code section and used `lea rsi, [rel .label]` / `[rel .float_1m]`.
- `rt_prf.asm` clobbered r12/r13 (used by codegen outer loop). Added `push r12`/`push r13` + matching pops.

### Fix 5–6 — codegen emit_runtime_call and div/mod encoding (codegen/codegen.asm)
- `emit_runtime_call`: `push rdi` before `mov dil, 0xE8` saved the rel32 target; restored with `pop rdi`. Without this the jmp target was always 0xE8.
- `.emit_div` / `.emit_mod` step 1: wrong opcode `0x89` (store) → `0x8B` (load) for `mov rax, r(8+dst)`. Step 4 REX prefix: `0x4C` → `0x49` for `mov r(8+dst), rax/rdx`.

### Fix 7 — Lexer infinite loop at EOF (lexer/lexer.asm)
When `at_line_start=1` and the file has been fully consumed, `check_empty_line` returns "empty" (because src_idx ≥ src_len), `skip_spaces` does nothing, no newline is consumed, and `jmp next_token` loops forever. Added `call peek_char; test rax,rax; jz .eof` after `.no_lf` to break the loop at EOF.

### Fix 8 — emit_block never advances out_idx (codegen/codegen.asm)
`rep movsb` decrements `rcx` to 0, then `add [out_idx], rcx` adds 0. Every `emit_block` call wrote at offset 0, overwriting the ELF header. Also read `[out_idx]` as 64-bit (`mov rdi`) instead of 32-bit. Fixed: save length in `eax` before `rep movsb`, use `add [out_idx], eax`, and read with `mov edi`.

### Fix 9 — codegen_emit_all commented out (main/main.asm)
`; call codegen_emit_all` meant user code was never emitted → binary contained only headers/runtime, resulting in "Not an ELF file" or wrong magic. Uncommented the call.

### Fix 10 — IR_LOAD_BOOL and IR_LOAD_STR unhandled in codegen (codegen/codegen.asm)
Both opcodes fell through to `.next_ir` leaving destination registers at zero/null. Fixed:
- `IR_LOAD_BOOL`: `jmp .load_imm` (imm holds 1/0/−1 same as integer).
- `IR_LOAD_STR`: emit jmp-over-string + string bytes + null + RIP-relative LEA pattern so the string is embedded inline in the code stream and the register gets the correct runtime address. displacement = -(tok_str_len + 8).

### Fix 11 — Float arithmetic used integer ADD/SUB/etc on IEEE 754 bits (codegen/codegen.asm)
`.op_emit` had no type check; float values stored as bit patterns in r8–r13 were operated on with integer instructions. Added type check at top of `.op_emit`: if TYPE_FLOAT, use `.op_emit_float` which does: `movq xmm0, r(8+dst)` → SSE op (addsd/subsd/mulsd/divsd) xmm0,xmm1 → `movq r(8+dst), xmm0`. Encoding: 66 49 0F 6E/7E for integer↔XMM, F2 0F 58/5C/59/5E C1 for the SSE ops.

## Key Invariants
- Runtime blobs use `-f bin` BITS 64 flat format with `times N-($ - $$) db 0` padding. All data must be reachable via RIP-relative addressing — no absolute `.rodata` sections.
- `emit_block` is the only function that bulk-copies bytes; `emit_b`/`emit_d`/`emit_q` handle individual byte/dword/qword emission and correctly maintain `out_idx` (32-bit `resd 1`).
- Physical registers 0–5 map to r8–r13. The outer codegen loop owns r12 (total count), r13 (index), r14 (IR record ptr). Handlers may use r8, r9, r15 as scratch without saving, but must not touch r12/r13/r14.
- `at_line_start` is 1 at program start; the first `next_token` call processes indent (finds 0 = same as stack) then proceeds to the first real token.
