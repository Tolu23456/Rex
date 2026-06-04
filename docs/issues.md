# Rex V5.0 — Known Issues

This file documents bugs, limitations, and design decisions that are not yet
resolved in the current codebase.  Issues are grouped by severity.

---

## Fixed ✅

### 1. Semicolons treated as comments in NASM (float/complex ops broken)
**Fixed in:** `codegen/codegen.asm`
All semicolon-separated instruction sequences in `codegen_emit_float_op` and
`codegen_emit_complex_op` have been split onto individual lines.

### 4. Expression type tracking is last-atom only
**Fixed in:** `parser/parser.asm`
`parse_additive` and `parse_term` now push `r14` at entry (callee-saved) and
track the LHS type through each binary operator.  After `+`, `-`, `*`, `/`, if
the LHS type was `TYPE_FLOAT` the result type is forced to `TYPE_FLOAT` (float
dominates).  `%` always yields `TYPE_INT`.  This ensures `cur_type` reflects the
full expression, not just the last atom.

### 5. `for` range bounds must be integer literals
**Fixed in:** `parser/parser.asm`
Both start and end bounds now use `parse_expr`, supporting variables, arithmetic,
and unary minus at any range position.

### 6. `p_memsz` in ELF Program Header is static 0x80000
**Fixed in:** `codegen/codegen.asm`, `codegen_finish`
`p_memsz` is now `out_idx + 0x44000` — dynamically computed to cover the generated
code plus the entire variable-storage region.

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

### 9. `emit_b` has no overflow guard
**Fixed in:** `codegen/codegen.asm`
`emit_b` now checks `out_idx >= 131071` before writing and calls `rt_err_blob`
with a halt if the buffer would overflow.  Buffer size is `resb 131072` (128 KiB).

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

### 14. Protocol parameters capped at 4 — 5th and 6th silently dropped
**Fixed in:** `parser/parser.asm`, `codegen/codegen.asm`
`.prot_store_params` now emits `mov [var_addr], r8` and `mov [var_addr], r9`
for params 4 and 5 using the correct REX prefix (0x4C) and ModRM bytes
(r8=0x04, r9=0x0C).  `codegen_emit_arg_pops` extended to match.
Protocol table entries remain 48 bytes; param slots at [41..46].

### 15. `float` return type lost through protocol call
**Fixed in:** `parser/parser.asm`, `runtime/runtime.asm`
`proto_ret_type` BSS in `parser.asm` mirrors `[entry+47]` from `proto_table`.
`proto_find` sets it after every lookup.  `.ret` stores `cur_type` into
`[entry+47]`.  `.at_in_expr` now restores `cur_type` from `proto_ret_type`
after the call instead of hard-coding `TYPE_INT`.

### 16. `emit_b_indirect` / `emit_d_indirect` were no-ops
**Fixed in:** `codegen/codegen.asm`
Both now `jmp codegen_emit_b_raw` / `jmp codegen_emit_d_raw`, which are
`global` wrappers forwarding to the internal `emit_b` / `emit_d`.
`codegen_get_var_va_proxy` added as a `global` wrapper for `get_var_va`.

### 17. `//` comment handler corrupted lexer state on UTF-8 source
**Fixed in:** `lexer/lexer.asm`
`.eslash` now peeks at the next byte; if also `/`, it scans forward until
`\n` (0x0A) or EOF before returning.  Previously, UTF-8 high bytes (> 0x7F)
fell through all character comparisons, but the leading `/` had already been
emitted as `TOK_SLASH`, scrambling the token stream.

### 19. `seq push` beyond initial capacity — FULLY FIXED ✅

**File:** `codegen/codegen.asm`, `codegen_emit_seq_push`.

**Description:** Previously, a 9th `push` silently wrote past the 8-slot
allocation, corrupting the heap.

**Fix applied:** `codegen_emit_seq_push` now emits a 57-byte inline grow block
guarded by `cmp rcx,[rbx]; jb .ok`.  On overflow the generated code:
1. Saves old cap (= old len) across an `rt_alc` call.
2. Calls `rt_alc(16 + old_cap*16)` — allocates a 2× buffer.
3. Writes `new_cap = old_cap*2` and `len` into the new header.
4. Copies all existing elements with `rep movsq`.
5. Updates the seq variable's pointer slot to the new buffer.
6. Reloads `rcx = len` and falls through to the normal element store.

Growth is unbounded — each overflow doubles capacity again.

### 20. Negative `for` loop bounds not supported
**Fixed in:** `parser/parser.asm`
Range bounds now use `parse_expr` which handles `TOK_MINUS` as unary negation;
`for :i in -5..5:` works correctly.

### 21. `VAR_MAX` has no overflow guard
**Fixed in:** `parser/parser.asm`, `var_add`
`var_add` already checks `cmp rbx, VAR_MAX; jge .full` — confirmed present and
correct; status updated to reflect the fix that was already in place.

### 26. Protocol local variables share global `var_table` slots
**Fixed in:** `parser/parser.asm`, `.prot_nobody`
`var_count` is pushed onto `scope_stack` before the protocol body and restored on
exit — local protocol variables are reclaimed after each protocol call.

### 29. `codegen_emit_abs_rax` uses CMOVNS instead of CMOVS — `abs()` always wrong
**Fixed in:** `codegen/codegen.asm`, `codegen_emit_abs_rax`
`mov al, 0x49` changed to `mov al, 0x48` — CMOVS (0x0F 0x48) is now emitted.
After `neg rax`, SF=1 means the original value was positive (neg produced
negative); CMOVS moves rbx (the original) back into rax, giving the correct
absolute value.

### 30. `for step N` silently ignored — step value always 1
**Fixed in:** `codegen/codegen.asm`, `codegen_emit_for_start` and `codegen_emit_for_start_dyn`
Both premature `mov qword [for_step_val], 1` resets removed from the start
functions.  The reset in `codegen_emit_for_end` (after reading the value) is
retained and correct.  `codegen_set_for_step` is no longer dead code.

### 31. `skip` semantics and depth argument
**Fixed in:** `parser/parser.asm` (`.skip`), `codegen/codegen.asm` (`codegen_emit_skip`)
`skip` = continue innermost loop; `skip N` = continue Nth-outer loop (depth
N-1 from top of `cont_base_stack`).  `codegen_emit_skip` now accepts `rdi=depth`.

### 32. Nested `when` statements corrupt outer `when_var_idx`
**Fixed in:** `parser/parser.asm`, `.when` / `.when_done`
Added BSS stacks `when_var_stack` (resq 8) and `when_cnt_stack` (resq 8) plus
`when_stk_depth`.  Each `when` entry pushes both globals; `.when_done` pops them.

### 33. `and` / `or` are eager — both operands always evaluated
**Fixed in:** `parser/parser.asm` (`.land`, `.lor`), `codegen/codegen.asm`
Short-circuit emission: `and` emits `test+jz` around RHS; `or` emits `test+jnz`.
New helpers: `codegen_emit_test_rax_jnz`, `codegen_emit_normalize_bool_rax`,
`codegen_emit_jmp_get_slot`, `codegen_patch_slot_to_here`.

### 34. String literals truncated silently at 63 chars
**Fixed in:** `lexer/lexer.asm`, `.strl` loop
Added `cmp rbx, 63; jge .strd` before the store — excess characters are silently
truncated at 63 bytes, leaving `tok_ident` null-terminated and valid.

### 35. `parse_factor` default case never advances the lexer
**Fixed in:** `parser/parser.asm`, `parse_factor` fall-through default
Added `call lexer_next` before the default `xor eax,eax` path so unknown tokens
are consumed and the parser does not spin on the same token forever.

### 36. `and` / `or` incorrectly marked unimplemented in docs
**Fixed in:** `docs/issues.md`, `syn.md` (status updated)
`and`/`or` are now fully short-circuit (`✅` in syn.md); issue closed.

### 37. For-loop end variable `<name>_fe` leaks a `var_table` slot
**Fixed in:** `parser/parser.asm`, `.for` block
`scope_stack` save/restore wraps the two synthetic var additions; after
`codegen_emit_for_end` `var_count` is restored, reclaiming both slots.

### 18. Recursive protocols produce wrong results
**Fixed in:** `parser/parser.asm`, `.prot_push_old` + `proto_emit_restore`
At protocol entry `.prot_push_old` emits `push qword [var_addr]` for every
parameter (in declaration order) before overwriting the slot with the incoming
register value.  `proto_emit_restore` (called at every `ret` path including the
implicit one after the body) emits `pop qword [var_addr]` in reverse order,
restoring the caller's values.  Verified: `fib(0)=0`, `fib(1)=1`, `fib(5)=5`,
`fib(10)=55`.
**Performance note:** each call now pays two memory round-trips per parameter
(push on entry, pop on return).  For `fib(42)` (~267 M calls) this gives
~7 s vs C's ~0.9 s.  A register-based stack frame (rbp-relative locals) would
eliminate these trips; that is the next performance-oriented milestone.

---

## Medium

### 22. `stop` only breaks the innermost loop — no outer-loop exit

**File:** `codegen/codegen.asm`, `codegen_emit_break`.

**Description:** `codegen_emit_break` emits a `JMP` patched to the current
loop's exit address.  When loops are nested, `stop` inside the inner loop
always targets the inner loop's exit.  There is no syntax or mechanism to
break out of an outer loop from inside an inner one.

**Fix required:** Introduce `stop N` labelled-break syntax.
`stop 1` = break inner (current `stop`), `stop 2` = break outer, etc.
The break patch stack needs a depth counter threaded through it.
`stop N` where `N` exceeds the current nesting depth is a compile-time error.

---

### 23. Dict keys must be string literals — variable keys not supported

**File:** `parser/parser.asm`, dict get/set handlers.

**Description:** The dict handler embeds the key bytes inline in the code
stream and calls `rt_sip(key_va, key_len)` with the inline pointer.  There
is no code path for `d[x]` where `x` is a variable holding a runtime string
pointer.  Using an identifier as a dict key silently misinterprets it.

**Fix required:** When the key token is `TOK_IDENT`, resolve the variable's
runtime address and length, then pass them to the SipHash call in place of
the inline literal.

---

### 24. No string concatenation and no `int → str` conversion

**File:** Expression parser, `runtime/runtime.asm`.

**Description:** `output` correctly routes `TYPE_STR`, but there is no
operator or built-in that joins two strings or converts a numeric value to
a string at runtime.  `str s; :s = x + "px"` does not compile, and
`output x` where `x` is an `int` cannot produce a formatted string.

**Fix required:** Add an `rt_str_cat` blob and a `str(expr)` cast
atom in `parse_factor`.  `str(expr)` should call an int-to-string conversion
blob and return a pointer to the result.

---

### 25. `err` with non-string argument — partial fix applied

**File:** `parser/parser.asm`, `.err_stmt`.

**Description:** `.err_stmt` calls `parse_expr` and passes `rax` directly
to `rt_err_blob`'s strlen loop, assuming a null-terminated string pointer.
`err 42` or `err code` where `code` is an `int` will pass a small integer
as a pointer.  The strlen loop will spin or segfault on address 42.

**Partial fix applied:** `.err_stmt` now checks `cur_type` after `parse_expr`.
If the type is not `TYPE_STR`, it routes through `codegen_output_rax` (prints
the value using the correct printer for the type) then emits `exit(1)` via
`codegen_emit_exit1`.  This prevents the segfault.

**Remaining work:** Proper int-to-string conversion so `err 42` emits the
number as text in the error message (requires issue 24 — `str(expr)` cast).

---

## Low

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
inside `rt_prq_blob` (currently 7550, 7577, 7626 bytes from binary start).
These were measured manually and hard-coded.  If `runtime.asm` is changed in
a way that shifts any preceding blob size, these offsets will silently become
wrong — dict operations will call into arbitrary bytes.

**Fix required:** Compute offsets via a linker-resolved symbol difference.
Until then, any change to `runtime.asm` blob sizes must be accompanied by
a manual re-measurement and update of all three constants.

---

### 27. `when` statement uses linear case search instead of a jump table

**File:** `parser/parser.asm`, `.when`.

**Description:** Each `is N:` case emits a `mov`/`cmp`/`jz` sequence,
so `when` with K cases is O(K).  The Stage 9 design calls for O(1) jump
tables when case values are dense integers.

**Fix required:** After collecting all case values, detect dense-integer
ranges and emit an indirect jump table (`jmp [table + rax*8]`) instead
of the linear chain.

---

### 28. No sequence bounds check on element reads

**File:** `parser/parser.asm`, sequence subscript handler.

**Description:** Reading `seq[i]` emits `mov rax, [rbx + rcx*8 + 16]`
with no check that `rcx < len`.  An out-of-range index reads past the
allocation silently; no runtime error is raised.

**Fix required:** Emit `cmp rcx, [rbx+8]; jae .oob_err` before the load,
routing to `rt_err_blob` on violation.  Matches the Stage 10 hardware
bounds-checking strategy.
