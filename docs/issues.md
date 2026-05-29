# Rex V5.0 — Known Issues

This file documents bugs, limitations, and design decisions that are not yet
resolved in the current codebase.  Issues are grouped by severity.

---

## Fixed ✅

### 1. Semicolons treated as comments in NASM (float/complex ops broken)
**Fixed in:** `codegen/codegen.asm`
All semicolon-separated instruction sequences in `codegen_emit_float_op` and
`codegen_emit_complex_op` have been split onto individual lines.

### 5. `use mm` check hardcoded to first character
**Fixed in:** `parser/parser.asm`
The memory-manager name is now compared as a full 4-byte word ("pool" = 0x6C6F6F70).

### 6. `if`/`while` conditions only support `var == literal`
**Fixed in:** `parser/parser.asm`
Both `if` and `while` now call `parse_expr` on each side of the comparison
operator, supporting full expressions (variables, literals, arithmetic, function
calls) with any of the six comparison operators (==, !=, <, >, <=, >=).

### 7. `output` for `str` variables falls back to integer printer
**Fixed in:** `parser/parser.asm`, `runtime/runtime.asm`
`rt_prs_blob` is now a full null-terminated string printer (sys_write + newline).
`parse_factor` handles `TOK_STR_LIT` by embedding the string inline in the code
stream and loading its VA into RAX.  `output` routes `TYPE_STR` through
`codegen_output_rax_str`.

### 8. `return` only supports integer immediate literals
**Fixed in:** `parser/parser.asm`
`return` now calls `parse_expr` to evaluate an arbitrary expression into RAX
before emitting `ret`.  Bare `return` (void) is also supported.

### 10. `rt_prb_blob` (bool printer) was a stub
**Fixed in:** `runtime/runtime.asm`
Implemented: prints "true\n", "false\n", or "unknown\n".  `output` for
`TYPE_BOOL` now routes through `codegen_output_rax_bool`.

### 11. `rt_prc_blob` (complex printer) was a stub
**Fixed in:** `runtime/runtime.asm`, `codegen/codegen.asm`
Implemented: prints `(real+imagj)\n` by receiving the variable's address (LEA
instead of MOV in `codegen_output_typed`) and reading both 64-bit double halves.

### 12. While/break/patch_breaks functions missing implementations
**Fixed in:** `codegen/codegen.asm`
`codegen_emit_while_start` now correctly saves the break-jump base before each
loop.  `codegen_emit_for_end` now calls `codegen_patch_breaks`.  `for` and
`while` handlers in the parser now call `codegen_emit_while_start`.

### 13. Bool/str/unknown literals not handled in parse_factor
**Fixed in:** `parser/parser.asm`
`parse_factor` now handles `TOK_TRUE`, `TOK_FALSE`, `TOK_UNKNOWN`, and
`TOK_STR_LIT` as first-class expression atoms.

---

## High

### 2. NASM 2.15 segfaults in this Replit environment

**Tool:** `~/.nix-profile/bin/nasm` (version 2.15.05).

**Description:** Invoking `nasm` — even with `--version` — causes an
immediate segfault in the sandbox environment.  This prevents building or
testing the compiler.

**Workaround:** Build via a CI environment, a Docker container with a known-
good NASM version (2.16+), or install from source.  The build script already
sets `PATH` to include the Nix profile, but nasm itself is broken in this
kernel configuration.

---

### 3. Dict runtime offsets are hardcoded, not linker-resolved

**File:** `include/rex_defs.inc` (`RT_DICT_NEW_OFFSET`, `RT_DICT_SET_OFFSET`,
`RT_DICT_GET_OFFSET`).

**Description:** The dict runtime functions are embedded at fixed offsets
inside `rt_prq_blob`.  These were measured manually and hard-coded.  If
`runtime.asm` is changed in a way that shifts any preceding blob size, these
offsets will silently become wrong.

**Fix required:** Compute offsets via a linker-resolved symbol difference.
Until NASM is functional, any change to `runtime.asm` blob sizes must be
accompanied by a manual re-measurement.

---

## Medium

### 4. Expression type tracking is last-atom only

**File:** `parser/parser.asm`, `[cur_type]` variable.

**Description:** The `[cur_type]` byte is set by `parse_factor` to the type
of the last atom loaded.  For compound expressions such as `int_var + 1.5`,
the final value in `cur_type` will be `TYPE_FLOAT` because the literal `1.5`
was the last atom, even though the integer addition result is integer-typed.

**Impact:** `output` may choose the wrong printer for mixed-type expressions.

**Fix required:** Implement a proper type stack or carry the inferred result
type through each level of the expression parser.

---

### 5. `for` range bounds must be integer literals, not variables

**File:** `parser/parser.asm`, `.for` block.

**Description:** Start and end values of a `for i in 0..N:` range are read
directly from `[tok_int]`.  Variable bounds are not evaluated.

**Fix required:** To support variable bounds, `codegen_emit_for_start` must
be redesigned to emit runtime code that evaluates the bounds rather than
taking them as compile-time immediates.

---

## Low

### 6. `p_memsz` in ELF Program Header is static 0x80000

**File:** `codegen/codegen.asm`, `codegen_finish`.

Should be calculated from `out_idx` plus the variable storage region size.

---

### 7. Output buffer is fixed at 128 KiB

**File:** `codegen/codegen.asm`.

A program with very many statements could overflow the buffer.  There is
no bounds check before writing.
