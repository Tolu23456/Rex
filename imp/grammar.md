# Rex — Formal Grammar (EBNF)

This is the **authoritative EBNF grammar** for Rex as specified in `design.md`.

Notation:
```
rule      ::= definition
[ x ]      = optional (zero or one)
{ x }      = zero or more repetitions
( x | y )  = grouping with alternatives
x | y      = top-level alternative
"x"        = literal terminal
<x>        = named terminal (described in §13 Terminals)
```

---

## 1. Top-Level Program

```ebnf
program         ::= { statement } <EOF>
```

---

## 2. Type Expressions

```ebnf
type_expr       ::= primitive_type
                  | generic_type

primitive_type  ::= "int"
                  | "float"
                  | "bool"
                  | "str"
                  | "char"
                  | "byte"

generic_type    ::= "seq" "[" type_expr "]"
                  | "arr" "[" type_expr "," <INT_LIT> "]"
                  | "dict" "[" type_expr "]"
                  | "tup" "[" type_expr { "," type_expr } "]"
```

The `arr` size argument (`<INT_LIT>`) must be a positive compile-time constant.
`tup` requires at least one type argument.

---

## 3. Declarations

```ebnf
declaration     ::= type_expr [ ":" ] <IDENT> [ "=" expr ] <NEWLINE>
                  | struct_def
                  | enum_def
                  | type_alias
                  | const_decl
                  | escape_decl

struct_def      ::= "struct" <IDENT> ":" <NEWLINE>
                    <INDENT> { type_expr <IDENT> <NEWLINE> } <DEDENT>

enum_def        ::= "enum" <IDENT> ":" <NEWLINE>
                    <INDENT> { enum_variant_def <NEWLINE> } <DEDENT>
                  | "enum" <IDENT> ":" enum_variant_def { "," enum_variant_def } <NEWLINE>

enum_variant_def ::= <IDENT> [ "=" <INT_LIT> ]

type_alias      ::= "type" <IDENT> "=" type_expr <NEWLINE>

const_decl      ::= "const" <IDENT> "=" expr <NEWLINE>

escape_decl     ::= "escape" "\\" <IDENT> "=" <STR_LIT> <NEWLINE>
```

- Without `":"`: variable is **immutable**. The initial `= expr` value is
  fixed at declaration and no `:x = …` assignment is permitted later.
- With `":"`: variable is **mutable**. `= expr` is optional inline
  initialisation.

```rex
int count = 0           // immutable
:int total = 0          // mutable, inline init
seq[str] names          // mutable, no init value
bool :flag = true       // alternative — ":" may precede or follow type_expr

struct Point:
    float x
    float y

enum Dir: north, south, east, west

type Meters = float

const MAX = 1024
```

Both forms `type_expr ":" <IDENT>` and `":" type_expr <IDENT>` are accepted
for readability. The sigil position does not change semantics.

---

## 4. Assignment and Mutation

```ebnf
assignment      ::= ":" lvalue "=" expr <NEWLINE>

lvalue          ::= <IDENT>
                  | <IDENT> "[" expr "]"
                  | <IDENT> "." <INT_LIT>
                  | <IDENT> "." <IDENT>
                  | lvalue "." <IDENT>

multi_assign    ::= ":" lvalue { "," ":" lvalue } "=" expr <NEWLINE>
```

The `<IDENT> "." <IDENT>` and `lvalue "." <IDENT>` forms allow mutation of struct
fields and nested struct fields:
```rex
:p.x = 3.0
:rect.top_left.x = 0.0
```

The `:` sigil is required at every mutation site. Assigning to an immutable
variable is a compile-time error.

`multi_assign` is used to unpack tuples and multiple return values:
```rex
:lo, :hi = @minmax(nums)
:a, :b, :c = triple
```

---

## 5. Statements

```ebnf
statement       ::= declaration
                  | assignment
                  | multi_assign
                  | output_stmt
                  | if_stmt
                  | switch_stmt
                  | for_stmt
                  | while_stmt
                  | each_stmt
                  | repeat_stmt
                  | stop_stmt
                  | skip_stmt
                  | pass_stmt
                  | prot_def
                  | call_stmt
                  | method_stmt
                  | return_stmt
                  | swap_stmt
                  | inc_dec_stmt
                  | flip_stmt
                  | use_stmt
                  | blast_stmt
                  | with_stmt
                  | try_stmt
                  | assert_stmt
                  | unreachable_stmt
                  | docstring

assert_stmt     ::= "assert" "(" expr [ "," <STR_LIT> ] ")" <NEWLINE>

unreachable_stmt ::= "unreachable" "(" ")" <NEWLINE>

docstring       ::= '"""' { <any_char> } '"""' <NEWLINE>
```

Every statement occupies one or more lines. Block bodies are delimited by
`<INDENT>` and `<DEDENT>` tokens emitted by the lexer.

---

## 6. Output and I/O Statements

```ebnf
output_stmt     ::= "output" "(" expr ")" <NEWLINE>

input_expr      ::= "input" "(" expr ")"

fmt_expr        ::= "fmt" "(" fmt_str ")"

fmt_str         ::= <STRING_LIT_WITH_FIELDS>

fmt_field       ::= "{" <IDENT> [ ":" fmt_spec ] "}"

fmt_spec        ::= [ fmt_fill ] [ fmt_align ] [ fmt_sign ]
                    [ fmt_width ] [ "." fmt_prec ] fmt_type

fmt_fill        ::= <any_char_except_brace>
fmt_align       ::= "<" | ">" | "^"
fmt_sign        ::= "+" | "-"
fmt_width       ::= <DECIMAL>
fmt_prec        ::= <DECIMAL>
fmt_type        ::= "d" | "f" | "e" | "g"
                  | "b" | "o" | "x" | "X"
                  | "s" | "c"
```

`output` dispatches to the correct printer at compile time from the type of
`expr`, appending a newline.

`fmt` returns a `str`. Fields inside the template string use `{name}` or
`{name:spec}` syntax. The format specifier mirrors Python's mini-language:

| Specifier | Meaning                                    | Example spec | Input | Output      |
|-----------|--------------------------------------------|--------------|-------|-------------|
| `d`       | Decimal integer (default for `int`)        | `d`          | 42    | `42`        |
| `f`       | Fixed-point float (default for `float`)    | `.2f`        | 3.14159 | `3.14`   |
| `e`       | Scientific notation                        | `.2e`        | 12345.0 | `1.23e4` |
| `g`       | Shorter of `f`/`e`                         | `g`          | 0.0001 | `1e-4`   |
| `b`       | Binary                                     | `08b`        | 5     | `00000101`  |
| `o`       | Octal                                      | `o`          | 8     | `10`        |
| `x`       | Hex lowercase                              | `x`          | 255   | `ff`        |
| `X`       | Hex uppercase                              | `X`          | 255   | `FF`        |
| `s`       | String (default for `str`, `char`)         | `10s`        | `"hi"` | `hi        ` |
| `c`       | Single character from `int` codepoint      | `c`          | 65    | `A`         |

**Width and fill:** `{n:08d}` pads `n` to 8 digits with leading zeros.
`{s:<20s}` left-aligns `s` in a 20-character field. `{v:^10f}` centres `v`.

**Sign:** `{x:+d}` always emits a sign; `{x:-d}` emits sign only for negatives (default).

**Type-dispatch rules:**

| Rex type  | Default fmt | Allowed specifiers          |
|-----------|-------------|-----------------------------|
| `int`     | `d`         | `d` `b` `o` `x` `X` `c`    |
| `float`   | `g`         | `f` `e` `g`                 |
| `bool`    | `s`         | `s` (emits `true`/`false`)           |
| `str`     | `s`         | `s`                         |
| `char`    | `c`         | `c` `d` `x` `X`             |
| `byte`    | `x`         | `d` `b` `o` `x` `X`        |

A specifier incompatible with the expression's type is a **compile-time error**.

---

## 7. Conditional

```ebnf
if_stmt         ::= "if" expr ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>
                    { elif_clause }
                    [ else_clause ]

elif_clause     ::= "elif" expr ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>

else_clause     ::= "else" ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>

if_expr         ::= "if" expr ":" expr
                    { "elif" expr ":" expr }
                    "else" ":" expr
```

The condition expression must be of type `bool`.
Truthy: `true` (`1`). Falsy: `false` (`0`).

**Inline `if` expression** — `if_expr` produces a value and may appear anywhere
an expression is expected. All branches must return the same type. `else` is required.

```rex
int x = if a > 0: 1 else: -1
str s = if score >= 90: "A" elif score >= 80: "B" else: "C"
output(if n == 0: "zero" else: "nonzero")
```

---

## 8. `switch` / `is` and `when`

### 8.1 `switch` / `is` — Value Dispatch

```ebnf
switch_stmt     ::= "switch" expr ":" <NEWLINE>
                    <INDENT> { is_clause } [ switch_else ] <DEDENT>

is_clause       ::= "is" switch_pattern { "," switch_pattern } ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>

switch_pattern  ::= <INT_LIT>
                  | <STR_LIT>
                  | <FLOAT_LIT>
                  | bool_lit
                  | <CHAR_LIT>
                  | enum_variant
                  | range_pattern
                  | "_"

enum_variant    ::= <IDENT> "." <IDENT>

range_pattern   ::= <INT_LIT> ".." <INT_LIT>

switch_else     ::= "else" ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>
```

`switch` evaluates the subject expression once and dispatches by value.
Ranges are **exclusive** on the right: `1..5` matches 1, 2, 3, 4.
Multiple patterns per `is` line are comma-separated — any one matching triggers the case.
`else` is the default/fallthrough case and must be last.
Dense integer ranges compile to O(1) jump tables.
No implicit fallthrough between cases.

### 8.2 `when` — State Monitor

```ebnf
when_expr       ::= "when" expr
```

`when expr` is an **expression** (not a statement) that evaluates `expr` and
compares its truth value to the **previous** evaluation at the same call site.
Returns `bool`:

- `true` — condition just became true (was false before)
- `false` — condition just became false (was true before)

First evaluation behaves as if previous state was `false`.
Each unique source-location `when` expression is an independent monitor tracked by the compiler.

---

## 9. Loops

### 9.1 `for` — Range Loop

```ebnf
for_stmt        ::= "for" <IDENT> "in" expr ".." expr
                    [ "step" expr ] ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>
                    [ loop_else ]
```

The counter variable is mutable within the loop body and is reclaimed on exit.
Both bounds are expressions evaluated once before the loop begins.
`step` is optional; defaults to `1`. Negative `step` values iterate downward.

### 9.2 `while` — Conditional Loop

```ebnf
while_stmt      ::= "while" expr ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>
                    [ loop_else ]
```

### 9.3 `each` — Collection Iterator

```ebnf
each_stmt       ::= "each" each_target "in" expr ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>
                    [ loop_else ]

each_target     ::= [ ":" ] <IDENT>
                  | <IDENT> "," [ ":" ] <IDENT>
```

- Single `<IDENT>`: binds each element by value (read-only).
- `":" <IDENT>`: mutating form — writes back to the collection on each iteration.
- `<IDENT> "," <IDENT>`: index-and-value form (`i, item`). The index is always
  read-only. The value target may use `:` for mutations.

Iterating over `str` yields `char`. Iterating over `dict` yields `str` (key)
and `T` (value) — the two-target form is required.

### 9.4 `repeat` — Counted Loop

```ebnf
repeat_stmt     ::= "repeat" expr ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>
```

The counter is not exposed. `expr` must evaluate to a non-negative `int`.
Emits a single `dec`/`jnz` hardware loop.

### 9.5 Loop Control

```ebnf
stop_stmt       ::= "stop" [ <INT_LIT> ] <NEWLINE>

skip_stmt       ::= "skip" [ <INT_LIT> ] <NEWLINE>

loop_else       ::= "else" ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>
```

- `stop` / `stop 1`: break the innermost loop.
- `stop N` (N > 1): break N levels simultaneously. Exceeding nesting depth is
  a compile-time error.
- `skip` / `skip 1`: continue the innermost loop's condition check.
- `skip N`: continue the Nth enclosing loop.
- `loop_else`: executes only if the loop exits without `stop`.

---

## 10. Protocols (Functions)

```ebnf
prot_def        ::= [ decorator ] "prot" <IDENT> "(" param_list ")"
                    [ "->" return_type ] ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>

decorator       ::= "#" decorator_item <NEWLINE>
                  | "#" "[" decorator_item { "," decorator_item } "]" <NEWLINE>

decorator_item  ::= decorator_name [ "(" arg_list ")" ]

decorator_name  ::= "memo" | "pure" | "total" | "inline" | "noinline"
                  | "hot" | "cold" | "safe" | "unsafe"
                  | <IDENT>

param_list      ::= [ param { "," param } ]

param           ::= type_expr <IDENT>

return_type     ::= type_expr
                  | result_type
                  | "(" type_expr { "," type_expr } ")"

result_type     ::= "result" "[" type_expr "]"

return_stmt     ::= "return" [ expr ] <NEWLINE>

pass_stmt       ::= "pass" <NEWLINE>
```

Up to **65 parameters** are supported. The first 6 are passed in registers
(`rdi`, `rsi`, `rdx`, `rcx`, `r8`, `r9`); parameters 7–65 are pushed
right-to-left on the stack before the call and cleaned up by the caller.
Empty `param_list` declares a zero-parameter protocol.
Multi-value return uses a parenthesised `return_type`; values come back in
`rax`+`rdx` (2 values) or a caller-allocated stack buffer (3+).

### 10.1 Error Handling — `try` / `except` / `finally` / `raise`

```ebnf
try_stmt        ::= "try" ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>
                    { except_clause }
                    [ bare_except ]
                    [ finally_clause ]

except_clause   ::= "except" <STR_LIT> [ "as" <IDENT> ] ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>

bare_except     ::= "except" ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>

finally_clause  ::= "finally" ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>

raise_stmt      ::= "raise" expr <NEWLINE>
```

- At least one `except` clause or a `finally` clause must follow `try:`.
- `bare_except` (no tag) must be the last `except` clause.
- `finally` executes unconditionally and may not contain `raise`.
- Multiple `except` clauses are checked top-to-bottom; the first match wins.

**`raise` expression:** any `str` expression. The text before the first `:`
is the **error tag**; everything including and after `:` is the **message**.

```ebnf
raise_stmt      ::= "raise" expr <NEWLINE>
                  | "raise" <STR_LIT> <NEWLINE>
```

**The `error` object** (bound via `as <IDENT>` in `except`):

| Field    | Type  | Value                                          |
|----------|-------|------------------------------------------------|
| `.tag`   | `str` | Text before first `:` in the raise string      |
| `.msg`   | `str` | Full raise string                              |
| `.line`  | `int` | Source line number of the `raise` statement   |

### 10.2 User-defined Decorators

```ebnf
decorator_def   ::= "decorator" <IDENT> [ "(" param_list ")" ] ":" <NEWLINE>
                    <INDENT> { decorator_block } <DEDENT>

decorator_block ::= before_block
                  | after_block
                  | wrap_block
                  | on_error_block

before_block    ::= "before" ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>

after_block     ::= "after" ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>

wrap_block      ::= "wrap" ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>

on_error_block  ::= "on_error" ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>
```

`__body__()` — special call token, legal only inside `wrap:`.
Invokes the original protocol body in place.

`__error__` — special object, legal only inside `on_error:`.
Fields: `.tag` (`str`), `.msg` (`str`).

**Mutual exclusion:** `wrap:` may not appear alongside `before:` or `after:`.

**Usage:**

```ebnf
decorator       ::= "#" decorator_item <NEWLINE>
                  | "#" "[" decorator_item { "," decorator_item } "]" <NEWLINE>

decorator_item  ::= <IDENT> [ "." <IDENT> ] [ "(" arg_list ")" ]
```

A single decorator uses `#name` or `#name(args)`.
Multiple decorators on one line use `#[a, b, c]` or `#[a(args), b]`.
Module-scoped decorator: `#module.name(args)` or inside `#[mod.name(args), ...]`.

### 10.3 Module System

```ebnf
module_def      ::= "module" <IDENT> ":" <NEWLINE>
                    <INDENT> { top_level_item } <DEDENT>

top_level_item  ::= prot_def
                  | decorator_def
                  | declaration

use_stmt        ::= "use" module_ref [ ":" import_list ] <NEWLINE>

module_ref      ::= <IDENT> { "." <IDENT> }

import_list     ::= import_item { "," import_item }
                  | "*"

import_item     ::= <IDENT>
```

**Visibility:** names starting with `_` are private to the module.
All other names are public and importable.

**Qualified access:** after any `use mod`, `mod.name(args)` is always valid.

**Unqualified access:** only after `use mod: name` or `use mod: *`.

**Circular imports:** compile-time error, detected in pass 2.

---

## 11. Protocol Calls

```ebnf
call_stmt       ::= "@" <IDENT> "(" arg_list ")" <NEWLINE>

call_expr       ::= "@" <IDENT> "(" arg_list ")"

arg_list        ::= [ expr { "," expr } ]
```

`@` is the protocol call prefix. It is required at every call site.
`call_expr` is the form used when the call appears inside an expression.

---

## 12. Method Calls and Field Access

```ebnf
method_stmt     ::= ":" postfix_expr "." <IDENT> "(" arg_list ")" <NEWLINE>
                  | postfix_expr "." <IDENT> "(" arg_list ")" <NEWLINE>

method_expr     ::= postfix_expr "." <IDENT> "(" arg_list ")"

field_access    ::= postfix_expr "." <INT_LIT>

subscript_expr  ::= postfix_expr "[" expr "]"

subscript_stmt  ::= ":" postfix_expr "[" expr "]" "=" expr <NEWLINE>

postfix_expr    ::= primary_expr { postfix_op }

postfix_op      ::= "." <IDENT> "(" arg_list ")"
                  | "." <INT_LIT>
                  | "[" expr "]"
```

Method calls chain left-to-right. Each postfix operation applies to the result
of the previous one:
```rex
nums.filter(fn(int x) -> bool: x > 0).map(fn(int x) -> int: x * 2).sum()
```

Mutating method calls use the `:` sigil on the whole statement:
```rex
:nums.sort()
:nums.push(42)
```

Methods that return new values (not `void`) do not require `:` when the result
is immediately used in an expression or discarded.

---

## 13. Other Statements

```ebnf
swap_stmt       ::= "swap" <IDENT> <IDENT> <NEWLINE>

inc_dec_stmt    ::= ( "++" | "--" ) <IDENT> <NEWLINE>
                  | <IDENT> ( "++" | "--" ) <NEWLINE>

flip_stmt       ::= "flip" <IDENT> <NEWLINE>
```

`flip` negates a `bool` variable in place (`true`↔`false`). Equivalent to `:b = not b`. The variable must be declared mutable.

---

## 14. Memory Context

```ebnf
use_stmt        ::= "use" "mm" mm_mode [ "gc" gc_mode ] ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>
                  | "use" "gc" gc_mode ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>

mm_mode         ::= "arena" | "pool" | "stack" | "heap" | "static"

gc_mode         ::= "sweep" | "ref" | "gen" | "inc" | "region"
```

See `docs/mm.md` for full specification.

---

## 15. File I/O — `with open`

```ebnf
with_stmt       ::= "with" "open" "(" expr "," open_mode ")" "as" <IDENT> ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>

open_mode       ::= <STR_LIT>
```

Valid mode strings: `"r"`, `"w"`, `"a"`, `"rb"`, `"wb"`, `"ab"`, `"r+"`, `"w+"`.

The `<IDENT>` after `as` binds a **file handle** — a scoped, opaque value whose
type is `file`. It is visible only inside the `with` block. The file is
automatically closed (flushed and fd released) on block exit, including via
`err`. No explicit `.close()` is needed or permitted inside a `with` block.

**File handle method call syntax follows the standard `postfix_expr` rule
(§12), e.g.:**

```rex
with open("data.txt", "r") as f:
    str contents = f.read()
    each line in f.lines():
        output(line.trim())

with open("out.txt", "w") as f:
    f.writeln("hello")
    f.writeln("world")

with open("a.bin", "rb") as src:
    with open("b.bin", "wb") as dst:
        dst.write_bytes(src.read_all_bytes())
```

**The `file` type — methods:**

| Method                | Returns    | Valid modes     | Notes                               |
|-----------------------|------------|-----------------|-------------------------------------|
| `.read()`             | `str`      | `r`, `r+`, `w+` | Read entire file as UTF-8 string    |
| `.read_line()`        | `str`      | text modes      | One line incl. `\n`; `""` at EOF   |
| `.read_bytes(n)`      | `seq[byte]`| `rb`, `r+`, `wb`| Read up to `n` bytes                |
| `.read_all_bytes()`   | `seq[byte]`| binary modes    | Read entire file as bytes           |
| `.lines()`            | `seq[str]` | text modes      | All lines, `\n` stripped            |
| `.write(s)`           | `void`     | write modes     | Write `str`; no newline added       |
| `.writeln(s)`         | `void`     | write modes     | Write `str` + `\n`                  |
| `.write_bytes(buf)`   | `void`     | binary modes    | Write `seq[byte]` or `arr[byte, N]` |
| `.seek(n)`            | `void`     | any             | Seek to byte offset from start      |
| `.seek_end(n)`        | `void`     | any             | Seek `n` bytes before end           |
| `.pos()`              | `int`      | any             | Current byte position               |
| `.size()`             | `int`      | any             | Total file size in bytes            |
| `.is_eof()`           | `bool`     | any             | `true` if at end of file            |
| `.flush()`            | `void`     | write modes     | Flush write buffer to OS            |
| `.path()`             | `str`      | any             | Path as given to `open`             |

**`file_exists` built-in:**

```ebnf
file_exists_expr ::= "file_exists" "(" expr ")"
```

Returns `bool`. Does not open the file. Used to guard `open` in `"r"` mode.

```rex
if not file_exists("config.txt"):
    output("config.txt not found")
```

`file_exists` is classified as a **built-in expression** (same tier as
`typeof`, `rand`) and produces a `bool` at call site.

---

## 16. Vectorised Loops

```ebnf
blast_stmt      ::= "blast" <IDENT> "in" <IDENT> ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>

pipe_stmt       ::= "pipe" <IDENT> "from" <IDENT> "into" <IDENT> ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>
```

---

## 17. Expressions

Expressions form a strict 6-tier recursive-descent hierarchy.
Higher tiers bind less tightly (evaluated last).

```ebnf
expr            ::= or_expr

or_expr         ::= and_expr { "or" and_expr }

and_expr        ::= not_expr { "and" not_expr }

not_expr        ::= "not" not_expr
                  | comparison

comparison      ::= in_expr { cmp_op in_expr }

cmp_op          ::= "==" | "!=" | "<" | ">" | "<=" | ">="

in_expr         ::= additive [ "in" additive ]
                  | additive [ "is" additive ]
                  | additive [ "is" "not" additive ]
                  | additive

additive        ::= term { add_op term }

add_op          ::= "+" | "-" | "&" | "|" | "^"

term            ::= unary { mul_op unary }

mul_op          ::= "*" | "/" | "%" | "<<" | ">>"

unary           ::= "-" unary
                  | "~" unary
                  | postfix_expr

postfix_expr    ::= primary_expr { postfix_op }

postfix_op      ::= "." <IDENT> "(" arg_list ")"
                  | "." <INT_LIT>
                  | "[" expr "]"

primary_expr    ::= <INT_LIT>
                  | <FLOAT_LIT>
                  | <STR_LIT>
                  | <CHAR_LIT>
                  | bool_lit
                  | "null"
                  | <IDENT>
                  | call_expr
                  | cast_expr
                  | typeof_expr
                  | input_expr
                  | fmt_expr
                  | hardware_expr
                  | seq_lit
                  | dict_lit
                  | tup_lit
                  | fn_lit
                  | "(" expr ")"
```

---

## 18. Bool Literals

```ebnf
bool_lit        ::= "true" | "false"
```

| Literal | Stored value | Meaning     |
|---------|--------------|-------------|
| `true`  | `1`          | Affirmative |
| `false` | `0`          | Negative    |

`and` = logical AND, `or` = logical OR, `not` = logical NOT.

**Tri-state / Kleene logic** (`true`/`false`/`unknown`) is available via the
`tristate` stdlib module and is **not** part of core `bool`:

```rex
from tristate import unknown
bool a = unknown        // hardware entropy via rdrand
```

---

## 19. Container Literals

```ebnf
seq_lit         ::= "[" [ expr { "," expr } ] "]"

dict_lit        ::= "{" [ dict_pair { "," dict_pair } ] "}"

dict_pair       ::= <STR_LIT> ":" expr

tup_lit         ::= "(" expr { "," expr } ")"
```

`seq_lit` is also used to initialise `arr[T, N]` — the compiler checks the
element count against `N` at compile time.

`tup_lit` with a single element `(x)` is parenthesised precedence, not a tuple.
A 1-tuple must be written as `tup[T] t = (x,)` with a trailing comma (or via
declaration syntax — context disambiguates).

---

## 20. `fn` Literals (Anonymous Protocols)

```ebnf
fn_lit          ::= "fn" "(" fn_param_list ")" [ "->" type_expr ] ":" fn_body

fn_param_list   ::= [ fn_param { "," fn_param } ]

fn_param        ::= type_expr <IDENT>

fn_body         ::= expr
                  | <NEWLINE> <INDENT> { statement } <DEDENT>
```

`fn` literals are used as arguments to higher-order methods (`.map`, `.filter`,
`.sort_by`, etc.). They capture no variables from the enclosing scope (no
closures — Rex does not have heap closures).

```rex
seq[int] doubled = nums.map(fn(int x) -> int: x * 2)
seq[int] pos = nums.filter(fn(int x) -> bool: x > 0)
int total = nums.reduce(0, fn(int acc, int x) -> int: acc + x)
```

---

## 21. Cast Expressions

```ebnf
cast_expr       ::= "int" "(" expr ")"
                  | "float" "(" expr ")"
                  | "str" "(" expr ")"
                  | "char" "(" expr ")"
                  | "byte" "(" expr ")"
                  | "bool" "(" expr ")"
```

| Cast         | From types               | Notes                                                        |
|--------------|--------------------------|--------------------------------------------------------------|
| `int(x)`     | `float`, `str`, `char`, `byte`, `bool` | `float` truncates toward zero; `str` parses decimal; `bool` → −1/0/1 |
| `float(x)`   | `int`, `str`             | `str` parses decimal notation                                |
| `str(x)`     | any primitive            | Human-readable representation                                |
| `char(x)`    | `int`, `byte`            | Interprets as UTF-8 code point                               |
| `byte(x)`    | `int`, `char`            | Low 8 bits                                                   |
| `bool(x)`    | `int`                    | non-zero → `true`, 0 → `false`                              |

---

## 22. Special Expressions

```ebnf
typeof_expr     ::= "typeof" expr

hardware_expr   ::= "rand"
                  | "carry"
                  | "overflow"
                  | "hash" expr

scope_expr      ::= "scope" "(" expr ")"

len_expr        ::= "len" "(" expr ")"

cap_expr        ::= "cap" "(" expr ")"

abs_expr        ::= "abs" "(" expr ")"

when_expr       ::= "when" expr

null_safe_expr  ::= expr "?." <IDENT> [ "(" { expr { "," expr } } ")" ]
                  | expr "??" expr

if_expr         ::= "if" expr ":" expr
                    { "elif" expr ":" expr }
                    "else" ":" expr

struct_init     ::= <IDENT> "{" field_init { "," field_init } "}"

field_init      ::= <IDENT> ":" expr
```

`typeof` returns the compile-time type token as an `int` constant.

`rand` reads one hardware-entropy integer via `rdrand`.
`carry` and `overflow` read the CPU flag bits after the most recent arithmetic
operation — both return `bool` (`true` or `false`, never `neutral`).
`hash expr` computes a SipHash-2-4 digest of the memory region `expr` refers to.
`scope(x)` returns `"global"`, `"local"`, or `"block"` for the variable `x`.
`len(x)` returns element count or byte length. `cap(x)` returns allocated capacity.
`abs(x)` returns the absolute value of numeric `x`.
`when expr` — see §8.2 (state monitor expression).
`x?.method()` — null-safe method call; returns `null` if `x` is `null`.
`x ?? default` — returns `x` if not null, else `default`. Right-associative.
`if_expr` — inline conditional expression; all branches must share the same type; `else` required.
`struct_init` — struct construction literal: `Point{x: 1.0, y: 2.0}`.

---

## 23. Literals and Terminals

```ebnf
<INT_LIT>       ::= <DECIMAL>
                  | "0x" <HEX_DIGIT> { [ "_" ] <HEX_DIGIT> }
                  | "0b" <BIN_DIGIT> { [ "_" ] <BIN_DIGIT> }
                  | "0o" <OCT_DIGIT> { [ "_" ] <OCT_DIGIT> }

<DECIMAL>       ::= <DIGIT> { [ "_" ] <DIGIT> }

<FLOAT_LIT>     ::= <DECIMAL> "." <DECIMAL> [ ( "e" | "E" ) [ "+" | "-" ] <DECIMAL> ]

<STR_LIT>       ::= '"' { str_char } '"'

str_char        ::= <UTF8_CHAR_EXCEPT_BRACE_AND_QUOTE>
                  | "{" expr "}"
                  | "{{" | "}}"
                  | escape_seq

escape_seq      ::= "\\" ( "n" | "t" | "r" | "\\" | '"' | "'" | "0"
                          | "a" | "b" | "f" | "v" | "e"
                          | "x" <HEX_DIGIT> <HEX_DIGIT>
                          | "u" <HEX_DIGIT> <HEX_DIGIT> <HEX_DIGIT> <HEX_DIGIT>
                          | "U" <HEX_DIGIT> <HEX_DIGIT> <HEX_DIGIT> <HEX_DIGIT>
                              <HEX_DIGIT> <HEX_DIGIT> <HEX_DIGIT> <HEX_DIGIT>
                          | "e{" <IDENT> "}" )

<CHAR_LIT>      ::= "'" ( <UTF8_CHAR> | escape_seq ) "'"

<MULTILINE_STR> ::= '"""' { <any_char> } '"""'

<DIGIT>         ::= "0" … "9"
<HEX_DIGIT>     ::= "0" … "9" | "a" … "f" | "A" … "F"
<BIN_DIGIT>     ::= "0" | "1"
<OCT_DIGIT>     ::= "0" … "7"
```

String literals support `{expr}` interpolation inline. `{{` and `}}` produce
literal brace characters. A `:` inside `{}` activates format mode:
`{pi:.2f}`, `{n:08b}`, `{n:x}`, `{name:10s}`.

---

## 24. Identifiers

```ebnf
<IDENT>         ::= <ALPHA_UNDER> { <ALPHA_UNDER> | <DIGIT> }

<ALPHA_UNDER>   ::= "a" … "z" | "A" … "Z" | "_"
```

Maximum identifier length is 255 bytes. Identifiers are case-sensitive.
Keywords are reserved and cannot be used as identifiers.

---

## 25. Reserved Keywords

| Category    | Keywords                                                                                                    |
|-------------|-------------------------------------------------------------------------------------------------------------|
| Types       | `int` `float` `bool` `str` `char` `byte` `seq` `arr` `dict` `tup` `file` `error` `struct` `enum` `type`   |
| Literals    | `true` `false` `null`                                                                                       |
| Statements  | `output` `input` `fmt`                                                                                      |
|             | `if` `elif` `else` `switch` `is` `when` `for` `in` `while` `each` `repeat` `stop` `skip` `pass`           |
|             | `return` `swap` `flip` `prot` `use` `module` `blast`                                                       |
|             | `with` `open` `as`                                                                                          |
|             | `try` `except` `finally` `raise`                                                                            |
|             | `decorator` `before` `after` `wrap` `on_error`                                                              |
|             | `const` `assert` `unreachable` `escape`                                                                     |
| Operators   | `and` `or` `not`                                                                                            |
| Expressions | `typeof` `rand` `carry` `overflow` `hash` `fn` `file_exists` `scope` `len` `cap` `abs`                     |
| Special     | `__body__` `__error__`                                                                                      |
| Memory      | `mm` `gc` `arena` `pool` `stack` `heap` `static` `sweep` `ref` `gen` `inc` `region`                        |
| Decorators  | `memo` `pure` `total` `inline` `noinline` `hot` `cold` `safe` `unsafe` `blast`                             |
| Future      | `pipe` `match` `move` `own` `free` `align` `volatile`                                                      |

---

## 26. Lexical Structure

```ebnf
comment         ::= "//" { <any_char_except_newline> } <NEWLINE>

<INDENT>        ::= increase in leading whitespace relative to the previous
                    logical line (multiples of 4 spaces recommended)

<DEDENT>        ::= return to a previous indentation level

<NEWLINE>       ::= "\n" | "\r\n"

<EOF>           ::= end of input
```

- Comments begin with `//` and extend to end of line. There are no block comments.
- Blank lines and comments are consumed by the lexer and produce no tokens.
- Indentation is significant. Block bodies are opened by `:` + `<NEWLINE>` and
  the subsequent `<INDENT>`, and closed by `<DEDENT>`.
- A block body must contain at least one statement. Use `pass` for empty blocks.
- Trailing whitespace on a line is ignored.
- The lexer enforces consistent indentation within a block (mixing tabs and spaces
  is a lexer error).

---

## 27. Operator Precedence Summary

From lowest to highest binding:

| Tier | Operators                            | Associativity | Notes                             |
|------|--------------------------------------|---------------|-----------------------------------|
| 6    | `or`                                 | left          | Logical or (max)                  |
| 5    | `and`                                | left          | Logical and (min)                 |
| 4    | `not`                                | right (unary) | Logical negation (negate)         |
| 3    | `==` `!=` `<` `>` `<=` `>=` `in` `is` | left        | Comparison and membership         |
| 2    | `+` `-` `&` `\|` `^`                  | left          | Additive, bitwise                 |
| 1    | `*` `/` `%` `<<` `>>`               | left          | Multiplicative, shift             |
| 0    | `-x` `~x`                            | right (unary) | Unary negation, bitwise NOT       |
| -1   | `.method()` `.field` `[index]`       | left          | Postfix — highest precedence      |

`and`/`or` short-circuit:
- `and`: skips RHS if LHS is `false` (result is `false`).
- `or`: skips RHS if LHS is `true` (result is `true`).

`not`: `not true` = `false`, `not false` = `true`.

---

## 28. Type System Summary

| Type      | Tag | Storage                              | Notes                              |
|-----------|-----|--------------------------------------|------------------------------------|
| `int`     | 1   | 64-bit signed integer (`qword`)      | Two's complement                   |
| `float`   | 2   | 64-bit IEEE 754 double               | `qword` (bit pattern)              |
| `bool`    | 3   | 8-bit unsigned integer (`byte`)      | 0 / 1 only                         |
| `str`     | 5   | `qword` heap pointer                 | UTF-8; `[cap:8][len:8][data:N]`   |
| `char`    | 8   | 8-bit unsigned integer               | Single UTF-8 byte                  |
| `byte`    | 9   | 8-bit unsigned integer               | Raw byte; 0–255                    |
| `seq[T]`  | 6   | `qword` heap pointer                 | `[cap:8][len:8][data:N]`          |
| `arr[T,N]`| 10  | inline stack array                   | Size `N` is compile-time constant  |
| `dict[T]` | 7   | `qword` heap pointer (hash table)    | SipHash-2-4; keys always `str`    |
| `tup[T…]` | 11  | inline stack struct                  | Immutable; positional access       |

Type propagation in binary expressions:
- `float` dominates `int` in arithmetic.
- `bool` arithmetic uses signed 8-bit values; results may be cast to `int`.
- Container element types must match exactly (no implicit widening).

---

## 29. Variable Table Layout

Each variable occupies one 64-byte entry in the flat `var_table` array:

```
offset  size  field
──────  ────  ──────────────────────────────────────────────────
 0      32    name (null-padded ASCII, max 31 bytes + NUL)
32       8    value (qword — int / float bits / pointer)
40       1    is_initialized  (0 = no, 1 = yes)
41       1    is_mutable      (0 = immutable, 1 = mutable)
42       1    type tag        (TYPE_* constant from §27)
43       5    (reserved — padding)
48      16    (reserved — future use, e.g. generic type params)
```

Maximum 256 entries (`VAR_MAX`). Exceeding this limit is a compile-time error.

---

## 30. Protocol Table Layout

Each protocol occupies one **128-byte** entry in the flat `proto_table` array:

```
offset  size  field
──────  ────  ──────────────────────────────────────────────────────────
  0     32    name (null-padded ASCII, max 31 bytes + NUL)
 32      8    body_offset — byte offset of protocol body in output buffer
 40      1    param_count (0–65)
 41      1    ret_type tag (TYPE_* constant; 0 = void)
 42      1    ret_count (0 = void, 1 = single, 2+ = multi-value)
 43      1    ret_is_result (0 = plain type, 1 = result[T] wrapper)
 44      1    decorator_mask (bitmask; bit 0=memo, 1=pure, 2=total,
              3=inline, 4=noinline, 5=hot, 6=cold, 7=unsafe)
 45      3    (reserved — padding to align param block)
 48     65    param_var_indices — one byte per parameter, index into
              var_table; unused slots set to 0xFF
113     15    (reserved — future generic type params)
```

**Entry size is 128 bytes.** Lookups use `imul rax, 128` (or `shl rax, 7`).
Maximum 256 entries (`PROTO_MAX`). Exceeding this limit is a compile-time error.

**Argument passing convention:**

| Parameter position | Register / location         |
|--------------------|-----------------------------|
| 1                  | `rdi`                       |
| 2                  | `rsi`                       |
| 3                  | `rdx`                       |
| 4                  | `rcx`                       |
| 5                  | `r8`                        |
| 6                  | `r9`                        |
| 7–65               | Stack, pushed right-to-left; caller cleans up after return |

---

## 31. Formal Constraints

The following rules are enforced by the compiler and are **not** captured by
the EBNF alone:

1. **Mutability**: `:x = …` is legal only if `x` was declared with `":"`.
2. **Initialization**: Reading an uninitialized variable is a compile-time error.
3. **Arity**: Protocol calls must supply exactly as many arguments as declared.
   Maximum 65 parameters per protocol definition.
4. **Type matching**: All operands must be compatible types (see §28 propagation).
5. **Loop depth**: `stop N` / `skip N` where N exceeds the current nesting depth
   is a compile-time error.
6. **`arr` size**: The literal element count in `[…]` must equal `N`.
7. **`tup` immutability**: Tuple fields may not be assigned via `:t.0 = …`.
8. **`fn` capture**: `fn` literals may not reference variables from the enclosing
   scope. All inputs must be explicit parameters.
9. **`when` exhaustiveness**: `when` without an `else` and without covering all
   possible values is a compile-time warning; with `_` it is always exhaustive.
10. **`dict` keys**: All dict operations that write use `str` keys only. Variable
    key expressions are supported; key type must be `str`.
11. **Forward references**: All protocol names and global variable names are
    visible throughout the entire source file. Pass 2 (Symbol Collection) builds
    the full `proto_table` and `var_table` headers before any IR is emitted.
    Calling a protocol defined later in the file is legal. Mutual recursion
    requires no pre-declaration stubs.
12. **`try`/`except` structure**: At least one `except` clause or a `finally`
    clause must follow `try:`. `bare_except` (no tag) must be the last clause.
    `finally:` may not contain `raise`.
13. **`raise` type**: The expression following `raise` must be `str`.
14. **`__body__()` scope**: Only legal inside a `wrap:` block of a
    `decorator` definition. Use elsewhere is a compile-time error.
15. **`__error__` scope**: Only legal inside an `on_error:` block of a
    `decorator` definition. Use elsewhere is a compile-time error.
16. **`wrap` exclusivity**: A `decorator` body may not contain both `wrap:`
    and `before:`/`after:`.
17. **Module visibility**: Names starting with `_` inside a `module` block
    are private; all others are public. A private name accessed outside
    its module is a compile-time error.
18. **Circular imports**: `use` chains that form a cycle are a compile-time
    error detected in pass 2.
19. **`decorator` application**: A decorator must be defined (or imported)
    before it is applied with `#`. Applying an undefined decorator name is
    a compile-time error.
