# Rex V5.0 — Known Issues

This file documents bugs, limitations, and design decisions that are not yet
resolved in the current codebase.  Issues are grouped by severity.

---

## Critical

### 1. Semicolons treated as comments in NASM (codegen float/complex ops broken)

**File:** `codegen/codegen.asm`, functions `codegen_emit_float_op` and
`codegen_emit_complex_op`.

**Description:** NASM uses `;` as the line comment character.  Several
instruction sequences in the existing code were written on a single line
separated by `;`:

```nasm
mov al, 0xF2; call emit_b; mov al, 0x0F; call emit_b; ...
```

NASM sees only `mov al, 0xF2` and discards everything after the first `;`.
The result is that only a single byte (0xF2) is written to `al` but
`emit_b` is never called, so the float/complex opcodes are never emitted
into the output buffer.

**Affected operations:** `+`, `-`, `*`, `/` on `float` variables; `+`, `-`
on `complex` variables; any output that calls `codegen_output_float_const`.

**Workaround:** None currently.  Each instruction must be placed on its own
line.

**Fix required:** Rewrite the affected inner sequences in
`codegen_emit_float_op` and `codegen_emit_complex_op` so every instruction
and every `call emit_b` is on a separate line.

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

**Description:** The dict runtime functions (`rt_dict_new`, `rt_dict_set`,
`rt_dict_get`) are emitted as part of the `rt_prq_blob` byte blob at known
fixed offsets (7550, 7577, 7626).  These values were measured from the
assembled `runtime.asm` and hard-coded.  If `runtime.asm` is modified in a
way that changes the size of any blob before `rt_prq_blob`, or if the
preceding blobs are resized, these offsets will silently become wrong and
produce incorrect runtime calls or crashes.

**Fix required:** Compute offsets via a linker-resolved symbol difference:

```nasm
RT_DICT_NEW_OFFSET equ rt_dict_new - rt_pri_blob
```

This requires nasm to be functional.  Until then, any changes to
`runtime.asm` blob sizes must be accompanied by a manual re-measurement.

---

### 4. Expression type tracking is last-atom only

**File:** `parser/parser.asm`, `[cur_type]` variable.

**Description:** The `[cur_type]` byte is set by `parse_factor` to the type
of the last atom loaded (int, float, str, dict).  For compound expressions
such as `int_var + 1.5`, the final value in `cur_type` will be `TYPE_FLOAT`
because the literal `1.5` was the last atom, even though the integer addition
result is integer-typed.

There is no type propagation rule — each binary operator merely inherits the
type of its right operand.

**Impact:** `output` will sometimes choose the wrong printer (integer vs.
float), producing corrupted output for mixed-type expressions.

**Fix required:** Implement a proper type stack or carry the inferred result
type through each level of the expression parser.

---

## Medium

### 5. `use mm` check hardcodes first character of memory manager name

**File:** `parser/parser.asm`, `.use_mm` block.

```nasm
cmp byte [tok_ident], 'p'
sete al
movzx edi, al
call codegen_emit_mm_switch
```

Only the first character of the memory manager name is tested (`'p'` for
`pool`).  Any name starting with `'p'` will switch to pool mode.  If a
future allocator named e.g. `persistent` is added, it would be
misclassified.

**Fix required:** Full string comparison against `"pool"`.

---

### 6. `if` / `while` conditions only support `var == literal` form

**File:** `parser/parser.asm`, `.if` and `.while` blocks.

**Description:** Conditions are always parsed as `var == literal`
using two `lexer_next` calls to skip the variable and the `==` operator,
then reading `[tok_int]` as the comparison value.  Full expression
conditions (e.g., `if x + 1 == y:`) are not supported.

**Fix required:** Replace the ad-hoc condition parse with a call to
`parse_expr` on each side of the comparison operator, then emit an
appropriate comparison and branch.

---

### 7. `output` for `str` variables falls back to integer printer

**File:** `parser/parser.asm`, `.output` handler.

**Description:** When `cur_type == TYPE_STR`, the output handler emits
`codegen_output_rax_int` (which calls `rt_pri`).  This will print the
raw pointer value of the string, not the string contents.

`rt_prs_blob` in `runtime/runtime.asm` is a stub (`ret` only).

**Fix required:** Implement `rt_prs_blob` to call `sys_write` with the
string pointer, then route `output` for strings through
`codegen_output_rax_str`.

---

### 8. `return` only supports integer immediate literals

**File:** `parser/parser.asm`, `.return` block.

**Description:** Return values are read from `[tok_int]` and emitted with
`codegen_emit_mov_eax_imm32`.  Variables and expressions are not supported.

---

### 9. `for` range must use integer literals, not variables

**File:** `parser/parser.asm`, `.for` block.

**Description:** Start and end values of a `for i in 0..N:` range are
read directly from `[tok_int]` via two `lexer_next` calls.  Variable
bounds are not evaluated.

---

## Low

### 10. `p_memsz` in ELF Program Header is static 0x80000

**File:** `codegen/codegen.asm`, `codegen_finish`.

```nasm
mov qword [rcx + 64 + 40], 0x80000 ; p_memsz (static for now)
```

This should be calculated from `out_idx` plus the variable storage region
size.  For small programs this is fine; for programs that declare more than
`(0x80000 - out_idx) / 8` variables the mapping will be too small.

---

### 11. Output buffer is fixed at 128 KiB

**File:** `codegen/codegen.asm`.

```nasm
out_buffer: resb 131072
```

A program with very many statements could overflow the buffer.  There is
no bounds check before writing.

---

### 12. `complex` type printer (`rt_prc_blob`) is a stub

**File:** `runtime/runtime.asm`.

`rt_prc_blob` consists only of `ret`.  Any `output complex_var` call will
return immediately without printing anything.
