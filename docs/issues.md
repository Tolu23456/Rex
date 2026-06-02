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

### 5. `for` range bounds must be integer literals
**Fixed in:** `parser/parser.asm`
Both start and end bounds now use `parse_expr`, supporting variables, arithmetic,
and unary minus at any range position.

### 6. `p_memsz` in ELF Program Header is static 0x80000
**Fixed in:** `codegen/codegen.asm`, `codegen_finish`
`p_memsz` is now `out_idx + 0x44000` — dynamically computed to cover the generated
code plus the entire variable-storage region.

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

---

## High

### 29. `codegen_emit_abs_rax` uses CMOVNS instead of CMOVS — `abs()` always wrong

**File:** `codegen/codegen.asm`, `codegen_emit_abs_rax`.

**Description:** The abs implementation emits `mov rbx, rax; neg rax; cmovns rax, rbx`
(opcode `0x0F 0x49`).  After `neg rax`, the sign flag reflects the *negated* value:
- `neg 5` → rax = -5, SF=1.  CMOVNS (SF=0): not taken → result = -5.  **Wrong.**
- `neg -3` → rax = 3, SF=0.  CMOVNS (SF=0): taken → rax = rbx = -3.  **Wrong.**

Both positive and negative inputs produce the wrong result.  Only `abs(0)` is correct.

The correct opcode is CMOVS (`0x0F 0x48`): move if SF=1, i.e. when the original value
was positive (neg produced a negative result → keep the original).

**Fixed in this scan:** `mov al, 0x49` changed to `mov al, 0x48` and comment updated.

---

### 30. `for step N` silently ignored — step value always 1

**File:** `codegen/codegen.asm`, `codegen_emit_for_start` and `codegen_emit_for_start_dyn`.

**Description:** The parser calls `codegen_set_for_step(N)` which writes N to the global
`for_step_val`.  However, `codegen_emit_for_start` and `codegen_emit_for_start_dyn` both
immediately overwrite it with 1 (`mov qword [for_step_val], 1`) before returning.
`codegen_emit_for_end` then reads `for_step_val = 1` and always emits `inc` regardless
of the `step` clause.  `for :i step 3 in 0..30:` loops with step 1, not 3.

`codegen_set_for_step` was therefore dead code.

**Fixed in this scan:** Both premature resets removed from the start functions.  The
reset in `codegen_emit_for_end` (after reading the value) is retained and correct.

---

### 31. `skip` is "continue" semantics, not "break/exit" semantics

**File:** `codegen/codegen.asm`, `codegen_emit_skip`; `parser/parser.asm`, `.skip`.

**Description:** `codegen_emit_skip` emits `jmp` to `cont_base_stack[top]` — the
loop-top / condition re-evaluation address.  This is `continue` behaviour (advance to
the next iteration), not `break` / exit behaviour.  `stop` is already the correct
break primitive; `skip` as implemented is a second `continue`, not the documented
"break N levels".

Additionally the depth argument `N` in `skip N` is parsed by the lexer but never
extracted or passed to `codegen_emit_skip`, which takes no argument — so `skip 2`
and `skip 99` behave identically to `skip` (always innermost loop continue).

**Fix required:** Decide the intended semantics — either:
- (a) Make `skip` a proper `continue` and document it as such (rename `stop` documentation
  to avoid confusion), or
- (b) Implement `skip N` as a multi-level break by walking `break_base_stack` back N levels
  and emitting a `jmp` to the corresponding exit address.
Whichever is chosen, the parser must pass the depth N into `codegen_emit_skip(rdi=N)`.

---

### 32. Nested `when` statements corrupt outer `when_var_idx`

**File:** `parser/parser.asm`, `.when` block.

**Description:** The `when` handler stores the subject variable index in a single global
qword `when_var_idx` and resets `when_case_count` to 0.  A nested `when` (e.g. a `when`
inside an `is` body) unconditionally overwrites both globals.  When the inner `when`
completes, the outer `when`'s subsequent `is` cases read the wrong `when_var_idx`,
comparing against the inner subject variable instead of the outer one.  Results are
silently wrong.

**Fix required:** Push `when_var_idx` and `when_case_count` onto a small BSS stack
(depth ≤ 8 is sufficient) on entry to each `when` block, and pop them on exit —
the same pattern used for `scope_stack`, `jump_patch_stack`, etc.

---

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

### 18. Recursive protocols produce wrong results

**File:** `parser/parser.asm`, `.protocol` + `.prot_store_params`.

**Description:** Protocol parameters are stored in global `var_table` slots
at `VAR_STORAGE_BASE + idx*64`.  A recursive call overwrites the caller's
copies of those slots before the caller resumes.  For example, `fib(n)`
calling `fib(n-1)` destroys the value of `n` in the caller's frame.
Any protocol that calls itself will silently compute the wrong answer.

**Fix required:** Per-call stack frames.  On protocol entry, push param
values onto the hardware stack (or a shadow stack in BSS); pop on return.
Affects `.protocol` preamble and `.prot_store_params` in `parser/parser.asm`.

---

### 19. `seq push` beyond initial capacity silently corrupts heap

**File:** `parser/parser.asm`, `.push_stmt`.

**Description:** `push x v` emits `mov [rbx + rcx*8 + 16], rax` with no
bounds check.  The initial allocation is 80 bytes (8-slot capacity, 16-byte
header).  A 9th `push` writes 8 bytes past the end of the allocation into
whatever `rt_alc` placed there — silently corrupting heap state.

**Fix required:** Emit a cap-vs-len check before the store.  If `len == cap`,
call a realloc blob that doubles the allocation and copies existing elements
before the store proceeds.

---

## Medium

### 5. `for` range bounds must be integer literals, not variables

**File:** `parser/parser.asm`, `.for` block.

**Description:** Start and end values of `for :i in 0..N:` are read directly
from `[tok_int]`.  If either bound is an identifier or expression, the parser
reads the token but `codegen_emit_for_start` never receives a runtime value.
The loop either uses zero or a stale register.

**Fix required:** Replace the literal reads with `parse_expr` calls.  Store
each bound's result register before emitting the loop header so
`codegen_emit_for_start` can use runtime values rather than immediates.
See also issue 20 (negative bounds).

---

### 20. Negative `for` loop bounds not supported

**File:** `parser/parser.asm`, `.for` block; `lexer/lexer.asm`.

**Description:** `tok_int` is stored as `uint64`.  The lexer does not apply
a unary minus in a range context.  `for :i in -5..5:` lexes as
`TOK_MINUS`, `TOK_INT_LIT(5)`, `TOK_DOTDOT`, `TOK_INT_LIT(5)` — the minus
is never applied and the parser discards it, so the start bound is 5, not -5.

**Fix required:** Handle `TOK_MINUS` before the range start in the `.for`
handler (negate the parsed integer), or unify with issue 5 by switching
bounds to `parse_expr` which already handles unary minus.

---

### 21. `VAR_MAX = 128` has no overflow guard

**File:** `parser/parser.asm`, `var_add`.

**Description:** `var_add` increments `[var_count]` without checking against
`VAR_MAX`.  Adding a 129th variable writes a 64-byte entry past the end of
`var_table` into adjacent BSS — typically `proto_table` — silently corrupting
the protocol registry.  No compile-time error or runtime diagnostic is emitted.

**Fix required:** Add `cmp [var_count], VAR_MAX; jge .var_full` at the top
of `var_add`.  On overflow, emit a compile-error message to stderr and halt
with a non-zero exit code.

---

### 22. `stop` only breaks the innermost loop — no outer-loop exit

**File:** `codegen/codegen.asm`, `codegen_emit_break`.

**Description:** `codegen_emit_break` emits a `JMP` patched to the current
loop's exit address.  When loops are nested, `stop` inside the inner loop
always targets the inner loop's exit.  There is no syntax or mechanism to
break out of an outer loop from inside an inner one.

**Fix required:** Introduce `skip N` (Stage 9) or labelled-break syntax.
`skip 1` = break inner (current `stop`), `skip 2` = break outer, etc.
The break patch stack would need a depth counter threaded through it.

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

**Fix required:** Add an `rt_str_cat` blob (Stage 9) and a `str(expr)` cast
atom in `parse_factor`.  `str(expr)` should call an int-to-string conversion
blob and return a pointer to the result.

---

### 33. `and` / `or` are eager — both operands always evaluated

**File:** `parser/parser.asm`, `parse_expr` (`.land`, `.lor`); `codegen/codegen.asm`,
`codegen_emit_and_bool_rax_rbx`, `codegen_emit_or_bool_rax_rbx`.

**Description:** `parse_expr` evaluates both sides before calling the bool combine
function.  `codegen_emit_and_bool_rax_rbx` emits `test rbx,rbx; setnz cl; test rax,rax;
setnz al; and al,cl` — all four operations happen unconditionally.  `syn.md` documents
`and`/`or` as short-circuit operators.  They are not: the RHS expression is always
evaluated even when the LHS already determines the result.  Side effects in the RHS
(e.g. a function call or `pop`) always execute.

**Fix required:** Emit a `test / jz` (for `and`) or `test / jnz` (for `or`) after
evaluating the LHS.  If the condition is already resolved, jump past the RHS evaluation
and the combine instruction.  This requires a forward-jump patch slot, identical to the
existing `if`/`while` pattern.

---

### 34. String literals truncated at 63 chars with no error or warning

**File:** `lexer/lexer.asm`, `.pstr` / `.strl` string-literal handler.

**Description:** String content is accumulated into `tok_ident` which is `resb 64` (64
bytes, null-terminated → max 63 content bytes).  The `.strl` loop has no bounds check on
`rbx`: a string literal of 64 or more characters writes past `tok_ident` into adjacent
BSS fields (`tok_int`, `lex_src`, `lex_len`, etc.) without any diagnostic.  The lexer
silently produces a corrupted token and subsequent parsing produces wrong results or a
segfault.

**Fix required:** Add `cmp rbx, 63; jge .strd` inside the `.strl` loop to cap content
at 63 bytes.  Optionally emit a compile-time warning to stderr before truncating.

---

### 35. `parse_factor` default (unknown-token) case never advances the lexer

**File:** `parser/parser.asm`, `parse_factor` fall-through default.

**Description:** When `parse_factor` encounters a token that matches none of the
recognised atoms, it falls through to a default path that emits `xor eax, eax` (zero)
and jumps to `.done` without calling `lexer_next`.  The same unrecognised token is then
seen again by whatever called `parse_factor`.  If the caller loops (e.g. `parse_term`'s
`.loop`, `parse_additive`'s `.loop`, `parse_stmt`'s dispatch loop), the parser spins
forever on the same token, hanging the compiler.

**Fix required:** Call `lexer_next` before the `jmp .done` in the default case, or emit
a compile-error message to stderr and halt.  The error path is preferable: silent zero
substitution hides bugs.

---

### 25. `err` only accepts a string pointer — integer codes cause a crash

**File:** `parser/parser.asm`, `.err_stmt`.

**Description:** `.err_stmt` calls `parse_expr` and passes `rax` directly
to `rt_err_blob`'s strlen loop, assuming a null-terminated string pointer.
`err 42` or `err code` where `code` is an `int` will pass a small integer
as a pointer.  The strlen loop will spin or segfault on address 42.

**Fix required:** Check `cur_type` after `parse_expr`.  If `TYPE_INT`,
call an int-to-string conversion blob first, then pass the resulting pointer
to `rt_err_blob`.

---

## Low

### 6. `p_memsz` in ELF Program Header is static 0x80000

**File:** `codegen/codegen.asm`, `codegen_finish`.

**Description:** `p_memsz` is hard-coded to `0x80000` regardless of actual
code size.  It should be `out_idx + VAR_STORAGE_SIZE` rounded up to a page
boundary.  Oversized binaries still run but waste virtual address space;
undersized programs (if the static value were ever lowered) would crash.

**Fix required:** Compute `p_memsz` dynamically from `out_idx` plus the
variable storage region in `codegen_finish`.

---

### 26. Protocol local variables share global `var_table` slots

**File:** `parser/parser.asm`, `.protocol`.

**Description:** Variables declared inside a protocol body occupy permanent
slots in the global `var_table`.  They are never reclaimed after the protocol
returns, so repeated calls accumulate variable entries.  With `VAR_MAX = 128`
(issue 21), a protocol called in a loop can exhaust the table quickly.

**Fix required:** Track the `var_count` on protocol entry and restore it on
exit, effectively reclaiming local slots.  This is a partial fix; full
isolation requires per-call stack frames (issue 18).

---

### 36. `and` / `or` incorrectly marked unimplemented in `todo.md` and `syn.md`

**File:** `todo.md`, `syn.md`.

**Description:** Both files mark `and` and `or` as not yet implemented (`[ ]` in
`todo.md`, `🔧` or `📋` in `syn.md`).  In reality `parse_expr` has fully wired
`.land` and `.lor` branches that call `codegen_emit_and_bool_rax_rbx` and
`codegen_emit_or_bool_rax_rbx`, which emit correct eager boolean machine code.
The operators work correctly for all common uses; they are missing only
short-circuit behaviour (issue 33).

**Fix required:** Update `todo.md` to `[x]` for `and`/`or`; update `syn.md` status
to `✅` with a note "(eager; short-circuit pending issue 33)".

---

### 37. For-loop end variable `<name>_fe` leaks a `var_table` slot per loop

**File:** `parser/parser.asm`, `.for` block; `parser/parser.asm`, `var_add`.

**Description:** The `for` parser adds two variables to `var_table`: the loop variable
(e.g. `i`) and a synthetic end-bound variable (`i_fe`).  These are never reclaimed
after the loop body.  `var_add` has no duplicate check, so two `for :i in …:` loops
at the same scope level each add fresh `i` and `i_fe` entries — consuming 4 slots.
A program with 64 for-loops using the same variable name will exhaust `VAR_MAX=256`
(leaving only 128 slots for user-declared variables).  No error is emitted.

The same leak applies to `when`'s `__when__` variable (one per `when` statement,
never reclaimed unless wrapped in a protocol whose `var_count` is restored on exit).

**Fix required:** After `codegen_emit_for_end`, restore `var_count` to the value it
had before the two synthetic variables were added (identical pattern to the existing
`scope_stack` save/restore used for protocol scoping).

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
