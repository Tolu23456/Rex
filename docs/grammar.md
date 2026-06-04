# Rex V5.0 — Formal Grammar (EBNF)

**Status markers used in this document:**
- ✅ Implemented and tested
- 📋 Planned — Stage 9 / Stage 10 roadmap

Productions marked 📋 are included for completeness; they do not parse in the
current bootstrap compiler.

Notation:
```
rule    ::= definition
[ x ]   = optional
{ x }   = zero or more repetitions
( x )   = grouping
x | y   = alternative
"x"     = literal terminal
<x>     = named terminal (described in Terminals section)
```

---

## 1. Top-Level Program

```ebnf
program         ::= { statement } <EOF>
```

---

## 2. Statements ✅

```ebnf
statement       ::= declaration
                  | assignment
                  | output_stmt
                  | if_stmt
                  | when_stmt
                  | for_stmt
                  | while_stmt
                  | stop_stmt
                  | skip_stmt
                  | pass_stmt
                  | prot_def
                  | call_stmt
                  | return_stmt
                  | err_stmt
                  | push_stmt
                  | pop_stmt
                  | swap_stmt
                  | inc_dec_stmt
                  | dict_set_stmt
                  | use_stmt
                  | repeat_stmt        (📋)
                  | blast_stmt         (📋)
                  | pipe_stmt          (📋)
```

Every statement occupies one or more lines. Indented bodies are delimited by
`<INDENT>` and `<DEDENT>` tokens emitted by the lexer.

---

## 3. Declarations ✅

```ebnf
declaration     ::= type_kw [ ":" ] <IDENT> [ "=" expr ] <NEWLINE>

type_kw         ::= "int"
                  | "float"
                  | "bool"
                  | "str"
                  | "complex"
                  | "seq"
                  | "dict"
```

- Without `":"`: the variable is **immutable** (constant). If `= expr` is
  present, the value is fixed at compile time and no `:x =` assignment is
  allowed later.
- With `":"`: the variable is **mutable**. `= expr` is an optional inline
  initialisation.

---

## 4. Assignment ✅

```ebnf
assignment      ::= ":" <IDENT> "=" expr <NEWLINE>
```

The `:` sigil is mandatory at every mutation site. Assignment to a
constant variable is a compile-time error.

---

## 5. Output ✅

```ebnf
output_stmt     ::= "output" expr <NEWLINE>
```

`output` resolves the printer at compile time from `cur_type`:
- `TYPE_INT` → `rt_pri_blob`
- `TYPE_FLOAT` → `rt_prf_blob`
- `TYPE_BOOL` → `rt_prb_blob`
- `TYPE_STR` → `rt_prs_blob`
- `TYPE_COMPLEX` → `rt_prc_blob` (passes address)

---

## 6. Conditional ✅

```ebnf
if_stmt         ::= "if" expr ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>
                    { elif_clause }
                    [ else_clause ]

elif_clause     ::= "elif" expr ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>

else_clause     ::= "else" ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>
```

---

## 7. `when` / `is` ✅

```ebnf
when_stmt       ::= "when" <IDENT> ":" <NEWLINE>
                    <INDENT> { is_clause } [ when_else ] <DEDENT>

is_clause       ::= "is" <INT_LIT> ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>

when_else       ::= "else" ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>
```

`when` evaluates the named variable once and emits a linear `cmp`/`jz` chain
for each `is` case. An O(1) jump-table optimisation for dense integer ranges
is planned (see `docs/issues.md` #27).

---

## 8. For Loop ✅

```ebnf
for_stmt        ::= "for" ":" <IDENT> "in" expr ".." expr
                    [ "step" expr ] ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>
                    [ loop_else ]                          (📋)
```

- The counter variable is declared mutable by the loop and reclaimed on exit.
- Both bounds accept full expressions (variables, arithmetic, unary negation).
- `step` is optional; defaults to 1 when omitted.
- An optional `else:` block (📋) executes if the loop exits without a `stop`.

---

## 9. While Loop ✅

```ebnf
while_stmt      ::= "while" expr ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>
                    [ loop_else ]                          (📋)
```

The condition is a full expression evaluated on every iteration.

---

## 10. Loop `else` 📋

```ebnf
loop_else       ::= "else" ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>
```

Executes only when the parent loop completes naturally (no `stop` was reached).
Planned implementation: a per-loop boolean flag variable is created in
`var_table` at loop entry (reclaimed via `scope_stack`) and set by every `stop`
site before the break JMP. The `else:` body is guarded by `if flag == false`.

---

## 11. `stop` / `stop N` ✅ / 📋

```ebnf
stop_stmt       ::= "stop" [ <INT_LIT> ] <NEWLINE>
```

- `stop` (no argument): breaks the innermost loop. ✅
- `stop N`: breaks `N` levels of nested loops simultaneously. 📋
  `N = 1` is identical to bare `stop`. Values exceeding the current nesting
  depth are a compile-time error.

---

## 12. `skip` / `skip N` ✅

```ebnf
skip_stmt       ::= "skip" [ <INT_LIT> ] <NEWLINE>
```

- `skip` (no argument): continues the innermost loop (jumps to condition check).
- `skip N`: continues the Nth enclosing loop's condition check.
  `N = 1` is the innermost loop.

---

## 13. `pass` ✅

```ebnf
pass_stmt       ::= "pass" <NEWLINE>
```

Emits zero bytes. Legal in any block that requires at least one statement.

---

## 14. `repeat N` 📋

```ebnf
repeat_stmt     ::= "repeat" expr ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>
```

Emits a single `dec`/`jnz` hardware loop. The counter register is not
exposed inside the body. `expr` must evaluate to a non-negative integer.

---

## 15. Protocol Definition ✅

```ebnf
prot_def        ::= "prot" <IDENT> "(" param_list ")" [ "->" type_kw ] ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>

param_list      ::= "None"
                  | <IDENT> { "," <IDENT> }
```

Up to 6 parameters are supported (mapped to rdi, rsi, rdx, rcx, r8, r9).
`None` declares an explicitly parameter-free protocol.
The optional `-> type_kw` return-type annotation is stored in `proto_table`
and restores `cur_type` at call sites.

---

## 16. Protocol Call ✅

```ebnf
call_stmt       ::= "@" <IDENT> "(" arg_list ")" <NEWLINE>

arg_list        ::= [ expr { "," expr } ]
```

When `@name(args)` appears as an expression atom (not a standalone statement),
it participates in `parse_factor` — see Section 24.

---

## 17. `return` ✅

```ebnf
return_stmt     ::= "return" [ expr ] <NEWLINE>
```

Bare `return` emits a void `ret`. `return expr` evaluates the expression into
`rax` (or `xmm0` for floats) before `ret`.

---

## 18. `err` ✅

```ebnf
err_stmt        ::= "err" expr <NEWLINE>
```

If `expr` evaluates to `TYPE_STR`, passes the pointer to `rt_err_blob`
(writes to stderr, exits 1). For other types, prints the value via the
correct typed printer then exits 1. Full `int → str` conversion requires
the planned `str(expr)` cast.

---

## 19. Sequence Operations ✅

```ebnf
push_stmt       ::= "push" <IDENT> expr <NEWLINE>
pop_stmt        ::= "pop" <IDENT> <NEWLINE>
```

`push` appends to a sequence, growing automatically on overflow.
`pop` removes and returns the last element; the result is available as
an expression atom — see `pop_expr` in Section 24.

---

## 20. Dict Assignment ✅

```ebnf
dict_set_stmt   ::= <IDENT> "[" <STR_LIT> "]" "=" expr <NEWLINE>
```

Variable-key subscript `d[x]` is planned (see `docs/issues.md` #23).

---

## 21. Swap ✅

```ebnf
swap_stmt       ::= "swap" <IDENT> <IDENT> <NEWLINE>
```

---

## 22. Increment / Decrement ✅

```ebnf
inc_dec_stmt    ::= "++" <IDENT> <NEWLINE>
                  | "--" <IDENT> <NEWLINE>
```

---

## 23. Memory Context ✅ / 📋

```ebnf
use_stmt        ::= "use" "mm" mm_mode [ "gc" gc_mode ] ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>
                  | "use" "gc" gc_mode ":" <NEWLINE>        (📋)
                    <INDENT> { statement } <DEDENT>
                  | "use" "keyword" <IDENT> "as" "mm" <IDENT> (📋)
                  | "use" "keyword" <IDENT> "as" "gc" <IDENT> (📋)

mm_mode         ::= "arena" | "pool"                         (✅)
                  | "stack" | "heap" | "static"              (📋)
                  | <IDENT>                                   (📋 user-defined)

gc_mode         ::= "sweep" | "ref" | "gen" | "inc" | "region" (📋)
                  | <IDENT>                                      (📋 user-defined)
```

---

## 24. Vectorized Loops 📋

```ebnf
blast_stmt      ::= "blast" <IDENT> "in" <IDENT> ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>

pipe_stmt       ::= "pipe" <IDENT> "from" <IDENT> "into" <IDENT> ":" <NEWLINE>
                    <INDENT> { statement } <DEDENT>
```

---

## 25. Expressions ✅

Expressions are parsed in a strict 5-tier recursive-descent hierarchy.
Higher tiers bind less tightly (evaluated last).

```ebnf
expr            ::= comparison

comparison      ::= additive { cmp_op additive }
                  | additive { "and" additive }
                  | additive { "or" additive }

cmp_op          ::= "==" | "!=" | "<" | ">" | "<=" | ">="

additive        ::= term { add_op term }

add_op          ::= "+" | "-" | "&" | "|" | "^"

term            ::= unary { mul_op unary }

mul_op          ::= "*" | "/" | "%" | "<<" | ">>"

unary           ::= "-" unary
                  | "~" unary
                  | factor

factor          ::= <INT_LIT>
                  | <FLOAT_LIT>
                  | <STR_LIT>
                  | "true" | "false" | "unknown"
                  | <IDENT>
                  | dict_get_expr
                  | call_expr
                  | pop_expr
                  | len_expr
                  | cap_expr
                  | abs_expr
                  | typeof_expr
                  | cast_expr
                  | "(" expr ")"
                  | is_expr           (📋)
                  | not_expr          (📋)
                  | in_expr           (📋)
                  | hash_expr         (📋)
                  | syscall_expr      (📋)
```

---

## 26. Expression Atoms ✅

```ebnf
dict_get_expr   ::= <IDENT> "[" <STR_LIT> "]"

call_expr       ::= "@" <IDENT> "(" arg_list ")"

pop_expr        ::= "pop" <IDENT>

len_expr        ::= "len" <IDENT>

cap_expr        ::= "cap" <IDENT>

abs_expr        ::= "abs" "(" expr ")"

typeof_expr     ::= "typeof" <IDENT>

cast_expr       ::= "int" "(" expr ")"
                  | "float" "(" expr ")"
                  | "str" "(" expr ")"     (📋)
```

---

## 27. Planned Expression Atoms 📋

```ebnf
not_expr        ::= "not" expr

is_expr         ::= expr "is" expr
                  | expr "is" "not" expr

in_expr         ::= expr "in" <IDENT>

hash_expr       ::= "hash" <IDENT>

syscall_expr    ::= "$" "(" arg_list ")"
```

---

## 28. Literals

```ebnf
<INT_LIT>       ::= <DECIMAL>
                  | "0x" <HEX_DIGIT> { <HEX_DIGIT> }
                  | "0b" <BIN_DIGIT> { <BIN_DIGIT> }
                  | "0o" <OCT_DIGIT> { <OCT_DIGIT> }

<FLOAT_LIT>     ::= <DECIMAL> "." <DECIMAL>

<COMPLEX_LIT>   ::= <DECIMAL> "+" <DECIMAL> "j"
                  | <FLOAT_LIT> "+" <FLOAT_LIT> "j"

<STR_LIT>       ::= '"' { <UTF8_CHAR> } '"'
                    (max 63 bytes of content; excess truncated)

<DECIMAL>       ::= <DIGIT> { <DIGIT> }
<DIGIT>         ::= "0" … "9"
<HEX_DIGIT>     ::= "0" … "9" | "a" … "f" | "A" … "F"
<BIN_DIGIT>     ::= "0" | "1"
<OCT_DIGIT>     ::= "0" … "7"
```

---

## 29. Identifiers and Keywords

```ebnf
<IDENT>         ::= <ALPHA> { <ALPHA> | <DIGIT> | "_" }
                    (max 31 bytes)

<ALPHA>         ::= "a" … "z" | "A" … "Z"
```

### Reserved Keywords

The following identifiers are reserved and cannot be used as variable or
protocol names:

| Category | Keywords |
|---|---|
| Types | `int` `float` `bool` `str` `complex` `seq` `dict` |
| Literals | `true` `false` `unknown` |
| Statements | `output` `if` `elif` `else` `when` `is` `for` `in` `while` `stop` `skip` `pass` `repeat` `return` `err` `push` `pop` `swap` `prot` `use` |
| Operators | `and` `or` `not` `abs` `len` `cap` `typeof` `typeof` `swap` |
| Memory | `mm` `gc` `arena` `pool` `stack` `heap` `static` `sweep` `ref` `gen` `inc` `region` `own` `move` `free` `align` `const` `volatile` |
| Future | `blast` `pipe` `each` `match` `repeat` `hash` `flip` `rand` `carry` `overflow` `sign` `clz` `ceil` `floor` `fract` `real` `imag` `conj` `assert` `unreachable` |

---

## 30. Indentation and Layout

```ebnf
<INDENT>        ::= increase in leading spaces relative to previous line
                    (multiples of 4 spaces recommended; any consistent
                    indentation level is accepted)

<DEDENT>        ::= return to previous indentation level

<NEWLINE>       ::= "\n" | "\r\n"

<EOF>           ::= end of input
```

Block bodies must contain at least one statement (use `pass` for empty blocks).
Blank lines and `//` comments are consumed by the lexer and do not produce tokens.

---

## 31. Comments

```ebnf
comment         ::= "//" { <any_char_except_newline> } <NEWLINE>
```

Comments are stripped during lexing. UTF-8 content after `//` is safely consumed.

---

## 32. Operator Precedence Summary

From lowest to highest binding:

| Tier | Operators | Notes |
|---|---|---|
| 5 (lowest) | `==` `!=` `<` `>` `<=` `>=` `and` `or` | Comparison and logical — returns 0 or 1 |
| 4 | `+` `-` `&` `\|` `^` | Additive and bitwise |
| 3 | `*` `/` `%` `<<` `>>` | Multiplicative and shift |
| 2 | `-x` `~x` | Unary negation and bitwise NOT |
| 1 (highest) | literals, variables, calls, `(expr)` | Atoms and parentheticals |

`and` and `or` are short-circuit: the RHS is not evaluated if the result is
determined from the LHS alone. `not` (📋) will bind at the unary tier (2).

---

## 33. Type System Summary

| Type token | Constant | Storage | Printer blob |
|---|---|---|---|
| `TYPE_INT` | 1 | `qword` in `var_table` | `rt_pri_blob` |
| `TYPE_FLOAT` | 2 | `qword` (IEEE 754 double) in `var_table` | `rt_prf_blob` |
| `TYPE_BOOL` | 3 | `qword` (0/1/rdrand) in `var_table` | `rt_prb_blob` |
| `TYPE_COMPLEX` | 4 | two `qword` in `var_table` (real, imag) | `rt_prc_blob` (via LEA) |
| `TYPE_STR` | 5 | `qword` pointer in `var_table` | `rt_prs_blob` |
| `TYPE_SEQ` | 6 | `qword` pointer to heap block in `var_table` | — |
| `TYPE_DICT` | 7 | `qword` pointer to hash table in `var_table` | — |

Type propagation in binary expressions: `float` dominates `int`; `%` always
yields `TYPE_INT`. Other inter-type arithmetic is not yet defined.

---

## 34. Variable Table Layout

Each variable occupies one 64-byte entry in the flat `var_table` array:

```
offset  size  field
──────  ────  ──────────────────────────────
 0      32    name (null-padded ASCII string)
32       8    value (qword — int / float bits / pointer)
40       1    is_initialized flag (0 or 1)
41       6    (reserved)
48       1    type (TYPE_* constant)
49      15    (reserved / padding to 64 bytes)
```

Maximum 256 entries (`VAR_MAX`). `var_add` halts with a compile-time error if
this ceiling is exceeded.

---

## 35. Protocol Table Layout

Each protocol occupies one 48-byte entry in the flat `proto_table` array:

```
offset  size  field
──────  ────  ──────────────────────────────
 0      32    name (null-padded ASCII string)
32       8    out_idx — byte offset of protocol body start in out_buffer
40       1    param_count (0–6)
41       6    param var indices (one byte each; unused slots = 0)
47       1    ret_type (TYPE_* constant; TYPE_VOID = 0 for void protocols)
```

All lookups and writes use `imul rax, 48`.
