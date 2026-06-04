---
name: Rex V5.0 markdown doc conventions
description: Status markers, cross-doc consistency rules, and the 5-feature doc spec implemented across syn.md, todo.md, and docs/*.
---

## Status markers
- ✅ = implemented and tested in codegen/parser/runtime
- 🔧 = token exists in lexer; parser/codegen pending
- 📋 = fully planned; not yet lexed or parsed

## Cross-doc rules
- `todo.md` bug list must only contain genuinely open issues; fixed issues belong in `docs/issues.md` Fixed section only.
- `docs/issues.md` Fixed section: sorted by issue number; open issues grouped High/Medium/Low.
- `docs/speed_comparison.md` Key Tradeoffs table must not list already-fixed bugs.
- `docs/self_hosting.md` prerequisites table must reflect actual implementation state (seq realloc = done, dict = done).
- `docs/language_comparison.md`: "Linker required" must distinguish compiler build (ld) from output binaries (no linker); GC strategy = "at compile time", not "at runtime".
- `CHANGELOG.md` Unreleased section tracks grammar.md and 5 planned features.
- `README.md` docs index must list grammar.md first among docs/ entries.

## 5 features documented (📋 spec in syn.md)
1. `not` operator — own subsection under Logical; `xor rax,1` for bool, `not rax` for int.
2. `is` / `is not` — full semantics with cmp+sete/setne; distinction from == for Stage 10 ownership.
3. `stop N` — multi-level break; depth counter in break-patch stack; compile-time depth guard; vs `skip N` (continue).
4. Loop `else:` — per-loop bool flag in var_table; set by every stop site; reclaimed via scope_stack; interacts with stop N.
5. `repeat N:` — dec/jnz hardware loop; counter not exposed; nesting via fresh register or spill.

## grammar.md
35 numbered EBNF sections. All statement forms, 5-tier expression hierarchy,
literal syntax, operator precedence table, reserved keyword list, variable
table layout (64-byte, VAR_MAX=256), protocol table layout (48-byte). Planned
productions included and marked 📋.
**Correction to watch**: VAR_MAX = 256 (from rex_defs.inc), not 128. Already
fixed in grammar.md section 34.

## opcodes.md
29 sections. Derived entirely from codegen/codegen.asm + include/rex_defs.inc.
Covers: address model, all var loads/stores, all integer/float/bitwise/boolean
ops, comparisons (setCC table), all control flow jumps (jz/jnz/jge/jmp),
for/while/break/continue byte patterns, protocol call/ret, output dispatch,
string inline layout, sequence alloc/push/pop/len/cap with grow block,
++/--, swap, abs (cmovs), err, mm_switch, jump patch stacks, quick lookup
table. All RT_*_OFFSET constants confirmed from rex_defs.inc.
