---
name: Rex docs second-pass decisions
description: All confirmed design decisions applied to design.md, grammar.md, syn.md — rules to stay consistent with in future sessions.
---

## Key decisions — enforce these in all future edits

### Keywords
- `switch`/`is` — value dispatch (replaces old `when`/`is`)
- `when` — state-monitor expression returning tri-state `bool` (not a statement)
- `blast` — is CURRENT (in Statements), NOT Future; `#blast` decorator + `blast:` block
- `struct`, `enum`, `type` — current reserved type keywords
- `const`, `assert`, `unreachable`, `escape`, `scope` — current reserved keywords
- `match` is Future; `push`/`pop` as statement form removed

### len / cap — function syntax only
- `len(x)` and `cap(x)` are built-in FUNCTIONS — `x.len()` and `x.cap()` as methods DO NOT EXIST
- All method tables must show `len(x)` / `cap(x)`, not `.len()` / `.cap()`
- Null-safe length: `if x is null: 0 else: len(x)` — no `?.` shorthand for functions

### switch / is
- Ranges: `1..5` is exclusive right (matches 1,2,3,4)
- Multiple patterns per `is` clause — comma-separated
- `else` must be last; no implicit fallthrough
- Works on: int, float, str, bool, char, enum values
- Dense int ranges → O(1) jump table

### when (state monitor)
- `when expr` is an EXPRESSION, not a statement
- Returns tri-state bool: `true`=just became true, `false`=just became false, `neutral`=unchanged
- First eval: behaves as if previous was `neutral`

### inline if expression
- `if cond: val else: val` — all branches same type, `else` required
- Can appear anywhere an expression is valid

### Types added
- Sized: `int[N]` N∈{8,16,32,64,128,256,512,1024}; `float[32/64/128]`; `char[8/16/32]`; `str[N]` stack buffer
- `seq[T, N]` — pre-allocated with capacity N
- `dict[T, N]` — bucket count hint N
- `arr[N]` — element type inferred from initializer
- Structs: value types, all fields required at construction; `:p.field = val` mutation
- Enums: int-backed; `Enum.variant` access; `int(e)` cast; compile-time only
- `type Alias = T` — structural alias, no new type, fully interchangeable
- Generics: `prot name[T, U](...)` — monomorphised at call site; up to 8 type params; inferred
- Null: reference types only (str, seq, dict, tup, struct); value types (int, float, bool, char, byte) cannot be null; `?.` and `??` operators
- `const NAME = expr` — compile-time folded, no runtime storage
- `assert(cond, "msg")` — stripped in `#blast`; `unreachable()` same
- Variadic: `prot f(T... args)` — last param only; args is `seq[T]` inside; not combinable with generics

### Module system additions
- Top-level module statements run at first `use` time, once only; init order follows `use` order
- Memory context default: scoped to module; `use global mm arena` to share across modules
- Modules cannot re-export imported names
- Circular imports = compile-time error (detected at Pass 2)

### Decorator ordering
- `#[a, b, c]` — c innermost, a outermost; before hooks: a→b→c; after hooks: c→b→a
- `on_error` decorator runs only for propagated errors (try/except wins inside body)
- `fn` literals CAN contain try/except

### escape sequences
- Standard: `\n \t \r \\ \" \' \0 \a \b \f \v \e`
- Hex: `\xNN`; Unicode: `\uNNNN` `\UNNNNNNNN`
- User-defined: `escape \name = "..."` — file-scoped, compile-time; used as `\e{name}` in strings

### output / input / fmt
- `output()` = Python print: `sep=" "`, `end="\n"`, multiple args, any type, kwargs only
- `input("prompt")` raises `EOFError` on Ctrl+D
- `fmt("template")` returns str without printing

### grammar.md coverage
- §3: struct_def, enum_def, type_alias, const_decl, escape_decl EBNF added
- §4: lvalue extended with `.field` and nested `lvalue.field` for struct mutation
- §5: switch_stmt replaces when_stmt; assert_stmt, unreachable_stmt, docstring added
- §7: if_expr inline added with examples
- §8: switch/is (§8.1) + when state-monitor (§8.2)
- §22: scope_expr, len_expr, cap_expr, abs_expr, when_expr, null_safe_expr, if_expr, struct_init added
- §23: underscore separators in INT_LIT and DECIMAL; MULTILINE_STR added
- §25: keywords table updated — struct/enum/type/const/assert/unreachable/escape in current
