---
name: Rex language design decisions
description: Mutability sigil rules, type system decisions, bool Kleene logic, and protocol design — agreed in design session, written to syn.md.
---

## Mutability — Path B (write-site only)

**Rule:** No sigil at declaration. `:` appears only at write/mutation sites.
- `int x = 5` — clean declaration (always)
- `:x = 10` — explicit mutation (required)
- `++x`, `swap x y`, `push seq val` — self-evidently mutations; no sigil needed

**Compiler enforcement:** If no `:x =` write site exists in the variable's scope, the compiler treats it as a true constant (eligible for constant folding/inlining). If at least one `:x =` exists, the variable is mutable. Reading an uninitialised variable is a compile-time error.

**For-loop variable:** No sigil needed. `for i in 0..10:` — the loop syntax implies mutation. Previously was `for :i in 0..10:`.

**Why:** The declaration-site sigil (`int :x = 5`) was redundant — the write site already tells you everything. The write-site signal is the valuable one for reading code quickly.

## Type System

**Typed sequences:** `seq[T]` — e.g. `seq[int] nums`. Compile-time error on type mismatch at push.
**Typed dicts:** `dict[T]` — keys always `str`, value type declared in brackets. e.g. `dict[int] d`.
**str elevated:** `str` is now a heap-managed UTF-8 string with `[cap][len][data]` layout (same as seq). Supports: concat (`+`), indexing (returns `char`), `len`, content equality (`==`/`!=`), `str(expr)` cast.
**char added:** Single UTF-8 byte, single-quote literals (`'R'`). Thin alias over `byte` with display semantics. `str[i]` returns `char`.
**byte added:** Raw unsigned 8-bit value. For binary data and I/O. `output` prints numeric value.
**complex deprecated:** Moved out of core. Will be stdlib in future release. Too niche for core; V0.1 still works but deprecated.

## bool — Tri-State Kleene Logic (KEEP)

Three values: `true` (1), `false` (0), `unknown` (rdrand hardware entropy).
This is Kleene strong three-valued logic — mathematically principled.

**and:** false dominates — `false and anything = false`
**or:** true dominates — `true or anything = true`
**not unknown = unknown**

**Why kept:** `unknown` maps directly to `rdrand` hardware instruction. It's Rex's most distinctive type feature, useful for randomized algorithms, non-deterministic testing, probabilistic branching. Already implemented.

## Protocols

**`@` call prefix — KEEP.** Visual two-tier system: `@name(args)` = user protocol, bare keyword = built-in. Every `@` in Rex means "this is yours."
**`None` — REMOVED.** Empty parens for no params (`prot greet():`). Omit `->` entirely for no return. No `void`, no `None`.
**Typed parameters — YES.** Type-first matching Rex style: `prot add(int a, int b) -> int:`. Untyped params deprecated.
**Multiple returns — tuples.** `-> (int, int)` with destructuring: `int lo, int hi` then `:lo, :hi = @minmax(nums)`. Type mismatch = compile-time error.
**Decorators — `#` sigil, one per line, stacked above `prot`.** `#` chosen over `@` (already a call prefix). No inline lists.
**Decorator set:** `#memo`, `#pure`, `#total` (algorithmic); `#inline`, `#noinline`, `#hot`, `#cold` (performance); `#safe`, `#unsafe` (safety). Combine freely, order doesn't matter.

## Output / I/O

**`output x`** — stdout + newline. Keep the name (Rex-specific, unambiguous).
**`show x`** — stdout, no newline. For inline/incremental printing.
**`warn "msg"`** — stderr, no exit. Non-fatal logging.
**`err "msg"`** — stderr + exit(1). Already implemented.
**`input "prompt"`** — prints prompt inline, reads line from stdin, returns `str`.
**String interpolation** — `{expr}` inside any string literal, automatic, no prefix. `{{` = literal brace. `@` still marks protocol calls inside `{}`.
