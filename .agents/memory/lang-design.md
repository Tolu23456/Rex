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

## Error Handling

**try/except/finally** — Python-style but no exception class hierarchy. Every error is a `str` message from `err`.
- `except:` — unconditional catch
- `except msg:` — captures error message as `str msg`
- `finally:` — always runs (cleanup)
- `warn` is unaffected (non-fatal, passes through try)
- Nested try: inner catches first; `err` inside `except` propagates outward
- Phase 2: guard conditions (`except msg if "x" in msg:`) — deferred

## Method Call Syntax (Python-style)

**Primary API for all types — method calls via `.method()`.**

**`seq[T]`:** `.push(val)` `.pop()` `.get(i)` `.set(i,val)` `.len()` `.cap()` `.contains(val)` `.remove(i)` `.sort()` `.reverse()` `.slice(s,e)` `.map(fn)` `.filter(fn)` `.each(fn)` `.clear()`
**`dict[T]`:** `.set(k,v)` `.get(k)` `.has(k)` `.remove(k)` `.keys()→seq[str]` `.values()→seq[T]` `.len()` `.clear()`
**`str`:** `.len()` `.upper()` `.lower()` `.trim()` `.split(sep)` `.contains(sub)` `.starts_with(p)` `.ends_with(s)` `.replace(old,new)` `.slice(s,e)` `.to_int()` `.to_float()` `.str()`
**`float`:** `.ceil()` `.floor()` `.round()` `.fract()` `.abs()` `.min(o)` `.max(o)` `.str()`
**`int`:** `.abs()` `.min(o)` `.max(o)` `.str()` `.float()`

## Tuples (standalone)

`tup[int,str,float] t = (1,"Alice",9.5)` — fixed, heterogeneous, immutable by default.
Access: `t.0`, `t.1`. Destructure: `int a, str b, float c = t`. Skip with `_`.
Primary use: multi-value protocol returns.

## Lambdas / `fn`

`fn(int x) -> int: x * 2` — anonymous protocol, single-expression or multi-line body.
Variable type: `prot(int -> int) f = fn(int x) -> int: x * 2`. Called with `@f(5)`.
Used in `.map(fn)`, `.filter(fn)`, `.each(fn)`. Protocol params declared as `prot(T -> U)`.

## Type Inference

`x = 5` (no type annotation) → compiler infers from literal or return type.
If no initial value provided, explicit type required: `int total`.
Explicit types always valid and preferred for protocol params and public interfaces.

## Comments

`//` line comment (existing). `/* */` block comment. `///` doc comment (attaches to next prot).
`#` is NOT a comment — it's the decorator sigil.

## Type Casting

**Global cast functions — no `.` needed. Type name IS the function.**
`int(x)`, `float(x)`, `str(x)`, `char(x)`, `byte(x)`, `bool(x)`.
- `int(float)` truncates toward zero. `int(str)` parses decimal.
- NOT `.str()`, `.float()`, `.to_int()`, `.to_float()` on methods — those are removed.
- Methods only carry computation logic (`.abs()`, `.min()`, `.sort()`, etc.).

## Context Allocator

Rex uses **implicit context allocator** via `use mm:` blocks.
- Current allocator stored in a thread-local register-resident slot.
- All allocations (including inside called protocols) automatically use the active context.
- Nested `use mm:` blocks shadow the outer context.
- No explicit allocator parameter threading needed (contrast: Zig's explicit approach).
- Caller decides the allocator strategy at the call site; callee is unaware.

## Imports & Modules

`import math` — whole module. `from math import sqrt` — specific identifier.
`from math import sqrt as sq` — aliased import. Module-qualified: `@math.sqrt(x)`.
Module = one `.rex` file. Top-level prots are public. No explicit export keyword.
Planned stdlib: `math`, `str_utils`, `io`, `os`, `complex`, `net`, `json`.
