# Rex — Language Design Document

> This document is the single source of truth for the Rex language design.
> It is written fresh from the existing documentation and supersedes all
> per-feature notes scattered across `syn.md`, `docs/grammar.md`, and `docs/mm.md`.
> Build the new compiler from this file.

---

## 1. Philosophy

Rex is a **systems language** with three non-negotiable properties:

1. **Zero runtime dependencies.** Every Rex binary is a self-contained ELF64
   executable. No libc, no dynamic linker, no interpreter. The runtime is
   inlined into the binary at compile time.

2. **Visible mutation.** State changes are marked at the point they happen, not
   at the declaration. Reading Rex code, you always know whether a line mutates
   something.

3. **Controllable memory.** The programmer chooses the allocation strategy and
   collection strategy per scope. The compiler enforces those choices at compile
   time. There is no hidden allocator.

Everything else — syntax, type system, collections, I/O — serves these three
goals.

---

## 2. Source Layout and Comments

Rex source files use the `.rex` extension. Encoding is UTF-8.

```rex
// This is a comment — everything after // on a line is ignored
```

Block structure is **indentation-delimited** — no braces, no `begin`/`end`.
A consistent indent level (4 spaces recommended) opens a block; returning to
the previous level closes it. Blank lines are ignored by the lexer.

---

## 3. Variables and Mutability

### 3.1 The Core Rule

Rex has one immutability rule that covers the entire language:

> **A variable is immutable by default. It becomes mutable the moment you write
> `:name =` anywhere in its scope. The `:` sigil marks every mutation site.**

There is no `let`, `var`, `mut`, or `const` keyword. The compiler infers
mutability from usage.

```rex
int x = 5           // immutable — no write site exists
int y = 0           // will be mutated (compiler sees :y below)
:y = x + 10         // explicit mutation — : is required here
++y                 // increment — self-evidently a mutation, no : needed
swap x y            // swap — self-evidently a mutation, no : needed
```

### 3.2 Declaration Forms

```rex
// Immutable with value (true compile-time constant — may be inlined/folded)
int age = 13

// Mutable with value
int count = 0
:count = count + 1

// Mutable without value (must be assigned before first read)
int total
:total = 100
```

Reading an uninitialised variable is a **compile-time error**.

### 3.3 Type Inference

Omit the type annotation when the initial value makes the type unambiguous:

```rex
x = 5               // infers int
y = 3.14            // infers float
z = "hello"         // infers str
w = true            // infers bool
result = @add(2, 3) // infers from protocol return type
:x = x + 1          // mutation still requires :
```

Rules:
- `5` → `int`, `3.14` → `float`, `"..."` → `str`, `true`/`false`/`unknown` → `bool`
- Inference does not cross scope boundaries.
- `int x = 3.14` is a compile-time type mismatch error.
- Without an initial value the type must be stated explicitly.

---

## 4. Type System

### 4.1 Primitive Types

| Type    | Example              | Storage         | Notes                                       |
|---------|----------------------|-----------------|---------------------------------------------|
| `int`   | `int a = 5`          | 64-bit signed   | Decimal, hex `0xFF`, binary `0b1010`, octal `0o17` |
| `float` | `float b = 1.5`      | 64-bit IEEE 754 | SSE2 registers                              |
| `bool`  | `bool f = true`      | 0 / 1 / entropy | Tri-state: `true`, `false`, `unknown`       |
| `str`   | `str s = "Rex"`      | Heap pointer    | UTF-8; header `[cap][len][data]`            |
| `char`  | `char c = 'R'`       | 8-bit unsigned  | Single UTF-8 byte; single-quoted literal    |
| `byte`  | `byte b = 0xFF`      | 8-bit unsigned  | Raw binary; `output` prints numeric value  |

### 4.2 Collection Types

| Type         | Example              | Notes                                           |
|--------------|----------------------|-------------------------------------------------|
| `seq[T]`     | `seq[int] nums`      | Heap-allocated growable sequence; typed element |
| `arr[T, N]`  | `arr[int, 8] buf`    | Stack-allocated fixed array; N is compile-time  |
| `dict[T]`    | `dict[int] d`        | SipHash-2-4 map; keys always `str`              |
| `tup[T...]`  | `tup[int, str] t`    | Fixed heterogeneous tuple; positional; immutable by default |

### 4.3 `bool` — Kleene Three-Valued Logic

Rex `bool` has exactly three values: `true` (1), `false` (0), and `unknown`
(hardware entropy via `rdrand`). This is **Kleene strong three-valued logic**.

`unknown` represents genuine indeterminacy — it is a first-class value, not an
error state.

**`and` table — false dominates:**

| `and`       | `false` | `true`  | `unknown` |
|-------------|---------|---------|-----------|
| **`false`** | false   | false   | false     |
| **`true`**  | false   | true    | unknown   |
| **`unknown`**| false  | unknown | unknown   |

**`or` table — true dominates:**

| `or`        | `false` | `true` | `unknown` |
|-------------|---------|--------|-----------|
| **`false`** | false   | true   | unknown   |
| **`true`**  | true    | true   | true      |
| **`unknown`**| unknown| true   | unknown   |

**`not`:** `not false` → `true`, `not true` → `false`, `not unknown` → `unknown`

```rex
bool coin = unknown         // hardware-entropy value
bool a = true
bool b = unknown
bool result
:result = a and b           // unknown
:result = a or b            // true (true dominates)
:result = not b             // unknown
```

### 4.4 Numeric Literals

```rex
int a = 255         // decimal
int b = 0xFF        // hex
int c = 0b11111111  // binary
int d = 0o377       // octal
float f = 3.14
float g = 1.0e-4    // scientific notation
```

---

## 5. Operators

### 5.1 Precedence (lowest to highest)

| Tier | Operators                          | Notes                           |
|------|------------------------------------|---------------------------------|
| 5    | `==` `!=` `<` `>` `<=` `>=` `and` `or` `is` `is not` `in` | Comparison and logical |
| 4    | `+` `-` `\|` `&` `^`             | Additive and bitwise            |
| 3    | `*` `/` `%` `<<` `>>`             | Multiplicative and shift        |
| 2    | `-x` `~x` `not x`                 | Unary                           |
| 1    | literals, identifiers, calls, `(expr)` | Atoms                      |

### 5.2 Arithmetic

```rex
:c = a + b
:c = a - b
:c = a * b
:c = a / b      // integer: truncating; float: IEEE 754
:c = a % b      // integer only; result has sign of dividend
```

`float` dominates in mixed arithmetic: `int + float` → `float`.

### 5.3 Bitwise

```rex
:z = x & y      // AND
:z = x | y      // OR
:z = x ^ y      // XOR
:z = ~x         // NOT (bitwise complement)
:z = x << 2     // left shift
:z = x >> 1     // right shift (arithmetic, sign-extends)
```

### 5.4 Logical (short-circuit)

```rex
if x > 0 and y > 0:    // RHS skipped if LHS false
    output("both positive")

if a == 1 or b == 1:   // RHS skipped if LHS true
    output("at least one")
```

### 5.5 Comparison

All six operators: `==`, `!=`, `<`, `>`, `<=`, `>=`

For `str`: lexicographic byte comparison.
For `bool`: value comparison (0/1; `unknown` compares by its random bit).

### 5.6 Identity and Membership

```rex
if x is 0:              // semantic identity (cmp → sete)
    output("zero")

if ptr is not null:
    output("valid")

seq[int] nums = [1, 2, 3]
if 2 in nums:           // O(n) linear scan
    output("found")

dict[int] d = {"a": 1}
if "a" in d:            // O(1) hash lookup
    output("key exists")

if "ell" in s:          // O(n+m) substring search
    output("found")
```

### 5.7 Increment, Decrement, Swap, Abs

```rex
++x                 // x = x + 1
--x                 // x = x - 1
swap x y            // exchange values (xchg)
int v = abs(x)      // absolute value
```

### 5.8 Pipeline

```rex
@compute(x) -> output       // output(@compute(x))
a + b -> @process()         // @process(a + b)
```

### 5.9 Hardware Features

```rex
bool c = carry              // CPU carry flag after last arithmetic op
bool ov = overflow          // CPU overflow flag
int n = rand                // hardware entropy integer via rdrand
bool b = true
flip b                      // b = not b (bitwise NOT of bool)
int h = hash s              // SipHash-2-4 of memory region s
```

### 5.10 Syscall Intercept

```rex
#unsafe
prot exit(int code):
    $(60, code)             // sys_exit; maps args to rdi, rsi, rdx, r10, r8, r9
```

`$` returns `rax`. Only available inside `#unsafe` protocols.

---

## 6. Type Casts

The type name is the cast function. No dot notation.

| Cast         | From                          | Notes                                     |
|--------------|-------------------------------|-------------------------------------------|
| `int(x)`     | `float`, `str`, `char`, `byte`, `bool` | Float truncates toward zero; str parses decimal |
| `float(x)`   | `int`, `str`                  | Str parses decimal notation               |
| `str(x)`     | `int`, `float`, `bool`, `char`, `byte` | Human-readable representation |
| `char(x)`    | `int`, `byte`                 | Interprets as UTF-8 code point            |
| `byte(x)`    | `int`, `char`                 | Low 8 bits                                |
| `bool(x)`    | `int`                         | 0 → `false`, non-zero → `true`            |

```rex
float f = 3.7
int i = int(f)          // 3 — truncates toward zero
str s = str(42)         // "42"
int parsed = int("42")  // 42
char c = char(65)       // 'A'
```

---

## 7. Control Flow

### 7.1 `if` / `elif` / `else`

```rex
if x == 10:
    output("ten")
elif x == 5:
    output("five")
else:
    output("other")
```

Any number of `elif` clauses. `else` is optional. Conditions accept full
expressions. Blocks are indentation-delimited.

### 7.2 `when` / `is`

Switch-like routing. Each `is` case matches the `when` expression linearly.
Dense integer ranges compile to O(1) jump tables.

```rex
when code:
    is 1:
        output("one")
    is 2:
        output("two")
    else:
        output("other")
```

### 7.3 `match`

Structural pattern matching on types:

```rex
match x:
    int:
        output("integer")
    float:
        output("float")
    str:
        output("string")
```

### 7.4 `pass`

Zero-byte placeholder for an empty block (required; blocks cannot be empty):

```rex
prot todo():
    pass

if x == 0:
    pass
else:
    output(x)
```

---

## 8. Loops

### 8.1 `for` — Range Loop

```rex
for i in 0..10:
    output(i)

for i in 0..20 step 2:
    output(i)

for i in -5..5:
    output(i)
```

Both bounds accept full expressions. `step` is optional (default 1). The loop
variable `i` is implicitly mutable — the loop syntax implies it; no `:` needed.

### 8.2 `while`

```rex
while x > 0:
    :x = x - 1

while true:
    output("forever")
    stop
```

Condition is a full expression evaluated on every iteration.

### 8.3 `each` — Collection Iterator

Preferred over `for` when iterating a collection. Emits a cache prefetch hint
on each iteration.

```rex
each item in items:
    output(item)

each i, item in items:     // with index (zero-based, read-only)
    output("{i}: {item}")

// mutating form — : on element name writes back
seq[int] nums = [1, 2, 3, 4, 5]
each :n in nums:
    :n = n * 2             // doubles in place

// over str — yields char
each ch in "Rex":
    output(ch)             // R, e, x

// over dict — yields key and value
each k, v in scores:
    output("{k}: {v}")
```

### 8.4 `repeat` — Counted Loop

No exposed counter variable. Emits a single `dec`/`jnz` hardware loop.

```rex
repeat 8:
    output("tick")

int sum = 0
repeat 100:
    :sum = sum + 1
```

`N` must be an integer literal or a compile-time constant expression.

### 8.5 Loop Control

| Statement  | Effect                                                      |
|------------|-------------------------------------------------------------|
| `stop`     | Break the innermost loop                                    |
| `stop N`   | Break `N` levels simultaneously (`stop 1` == `stop`)       |
| `skip`     | Continue the innermost loop (jump to condition check)       |
| `skip N`   | Continue the Nth enclosing loop's condition check           |

```rex
for i in 0..10:
    for j in 0..10:
        if i == j:
            stop 2         // exits both loops at once
```

A depth exceeding the current nesting level is a **compile-time error**.

### 8.6 Loop `else`

Executes only if the loop exits naturally (without `stop`):

```rex
for i in 0..10:
    if i == 5:
        stop
else:
    output("completed — target not found")
```

`stop N` where N > 1 sets the break-flag in every bypassed loop before the
outer jump is taken, so all their `else` blocks are correctly skipped.

---

## 9. Protocols (Functions)

### 9.1 Definition

```rex
prot greet():
    output("Hello")

prot square(int x) -> int:
    return x * x

prot add(int a, int b) -> int:
    return a + b
```

- No `return` type annotation → void protocol (no `None`, no `void` keyword).
- Parameters are typed, type-first.
- Up to 6 parameters (SysV ABI: `rdi`, `rsi`, `rdx`, `rcx`, `r8`, `r9`).

### 9.2 Calling with `@`

`@` is Rex's protocol call prefix. It separates user-defined protocols from
built-in statements, so any `@` in Rex source means "this is yours."

```rex
@greet()

int result
:result = @add(3, 4)
output(result)
```

### 9.3 Multiple Return Values

```rex
prot minmax(seq[int] s) -> (int, int):
    int lo = s[0]
    int hi = s[0]
    each n in s:
        if n < lo: :lo = n
        if n > hi: :hi = n
    return lo, hi

int lo, int hi
:lo, :hi = @minmax(nums)
```

Two return values come back in `rax` and `rdx`. Three or more use a
caller-allocated stack buffer.

### 9.4 Decorators

Decorators annotate a protocol with compiler directives. They use `#` and
stack one per line directly above `prot`:

```rex
#memo
#pure
prot fib(int n) -> int:
    if n <= 1:
        return n
    return @fib(n-1) + @fib(n-2)

#hot
#inline
prot dot(int a, int b) -> int:
    return a * b

#unsafe
prot exit(int code):
    $(60, code)
```

**Why `#` and not `@`?** `@` already means "call". `#` is unambiguous and
reads clearly as an annotation.

**Built-in decorators:**

| Decorator   | Category    | Effect                                                      |
|-------------|-------------|-------------------------------------------------------------|
| `#memo`     | Algorithmic | Cache return value keyed on input; skip recomputation       |
| `#pure`     | Algorithmic | No side effects — compiler may reorder or elide calls       |
| `#total`    | Algorithmic | Terminates for all inputs (hint only)                       |
| `#inline`   | Performance | Force inline at every call site                             |
| `#noinline` | Performance | Prevent inlining                                            |
| `#hot`      | Performance | Called frequently — optimize for throughput                 |
| `#cold`     | Performance | Called rarely — optimize for binary size                    |
| `#safe`     | Safety      | Compiler verifies: no raw syscalls or pointer arithmetic    |
| `#unsafe`   | Safety      | Allows `$` syscalls and direct memory operations            |

Decorators compose freely. Order does not matter.

### 9.5 Recursion

Protocols may call themselves. Per-call stack frames are required — each
recursive call must save and restore every in-scope variable slot before and
after the call.

```rex
prot fib(int n) -> int:
    if n <= 1:
        return n
    return @fib(n-1) + @fib(n-2)
```

---

## 10. Sequences

```rex
seq[int] nums                           // empty sequence
seq[int] nums = [1, 2, 3, 4, 5]        // literal initialisation
seq[seq[int]] matrix                    // nested sequences
```

Sequences are heap-allocated, typed, and auto-grow on overflow. The hidden
header is `[capacity: 8][length: 8][data: ...]`.

### 10.1 Core Operations

```rex
nums.push(6)            // append
int v = nums.pop()      // remove and return last
int n = nums.len()      // element count
int c = nums.cap()      // allocated capacity
bool e = nums.is_empty()
nums.clear()
```

### 10.2 Access

```rex
int first = nums[0]
int last = nums[-1]     // negative indices count from end
:nums[2] = 99           // write requires : sigil
```

### 10.3 Transformation

```rex
nums.sort()
nums.sort_desc()
nums.reverse()
seq[int] copy = nums.copy()
seq[int] sub = nums.slice(1, 4)
```

### 10.4 Functional

```rex
nums.each(fn(int x): output(x))
seq[int] doubled = nums.map(fn(int x) -> int: x * 2)
seq[int] evens = nums.filter(fn(int x) -> bool: x % 2 == 0)
bool any = nums.any(fn(int x) -> bool: x > 10)
bool all = nums.all(fn(int x) -> bool: x > 0)
int cnt = nums.count(fn(int x) -> bool: x > 5)
int total = nums.reduce(0, fn(int acc, int x) -> int: acc + x)
int s = nums.sum()
int mn = nums.min()
int mx = nums.max()
```

---

## 11. Fixed Arrays

Stack-allocated, size known at compile time:

```rex
arr[int, 8] buf                         // uninitialized
arr[float, 3] v = [1.0, 0.0, 0.0]      // literal initialisation
```

Same index and slice API as `seq`. No push/pop. Converting to sequence:

```rex
seq[int] s = buf.to_seq()
```

**When to use `arr` vs `seq`:**

| | `seq[T]` | `arr[T, N]` |
|---|---|---|
| Size known at compile time | no | yes |
| Growable | yes | no |
| Memory location | heap | stack |
| Header overhead | 16 bytes | none |
| Use for | lists, queues | fixed buffers, vectors |

---

## 12. Dictionaries

SipHash-2-4 internally. Keys are always `str`. Value type is declared in `[T]`.

```rex
dict[int] scores                                        // empty
dict[int] scores = {"alice": 95, "bob": 87}            // literal init
dict[str] config = {"host": "localhost", "port": "8080"}
```

### 12.1 Access

```rex
int v = scores["alice"]             // read
:scores["alice"] = 99               // write — : required
bool found = scores.has("carol")
int safe = scores.get_or("dave", 0) // 0 if missing, no insert
int val = scores.get_or_set("dave", 50) // insert default if missing
scores.remove("alice")
```

Missing-key access via `[]` or `.get()` is a **runtime error**. Always guard
with `.has()` or `.get_or()`.

### 12.2 Bulk and Functional

```rex
scores.update(extras)               // merge, other wins on conflict
dict[int] copy = scores.copy()
seq[str] ks = scores.keys()
seq[int] vs = scores.values()
int n = scores.len()
scores.clear()

scores.each(fn(str k, int v): output("{k}: {v}"))
dict[str] labels = scores.map(fn(str k, int v) -> str: str(v) + " pts")
dict[int] passing = scores.filter(fn(str k, int v) -> bool: v >= 75)
bool any = scores.any(fn(str k, int v) -> bool: v == 100)
bool all = scores.all(fn(str k, int v) -> bool: v > 0)
int cnt = scores.count(fn(str k, int v) -> bool: v >= 80)
dict[str] rev = abbrevs.invert()    // swap keys/values; T must be str
```

---

## 13. Strings

Heap-managed UTF-8. Header layout: `[capacity: 8][length: 8][data: N]`.
Methods return new strings — mutation always goes through `:s = s.method()`.

### 13.1 Operations

```rex
str result = s + " " + t           // concatenation
str line = "-" * 40                // repetition
char c = s[0]                      // index
char last = s[-1]                  // negative index
if s == "hello": output("match")   // content equality
```

### 13.2 Core Methods

```rex
s.len()            // byte count
s.upper()          // new uppercase copy
s.lower()          // new lowercase copy
s.trim()           // strip leading/trailing whitespace
s.contains("sub")  // bool
s.starts_with("p") // bool
s.ends_with("!")   // bool
s.replace("a","b") // new string
s.slice(1, 4)      // new substring (end exclusive)
s.split(", ")      // seq[str]
s.index_of("x")    // int; -1 if not found
s.count("ss")      // int (non-overlapping occurrences)
s.reverse()        // new reversed string
s.repeat(3)        // new repeated string
s.pad_left(10, ' ')
s.pad_right(10, '-')
s.center(10, '*')
s.lines()          // seq[str] — split on \n
s.words()          // seq[str] — split on whitespace runs
", ".join(names)   // str — join seq[str] with separator
s.chars()          // seq[char]
s.bytes()          // seq[byte]
```

### 13.3 String Interpolation

All Rex string literals support `{expr}` interpolation — no prefix needed:

```rex
output("x is {x} and y is {y}")
output("result: {a + b}")
output("fib(10) = {@fib(10)}")
output("{{not interpolated}}")     // literal {
```

Any valid Rex expression is allowed inside `{ }`.

### 13.4 Format Specifiers

A `:` inside `{}` activates format mode:

```rex
output("pi = {pi:.2f}")            // 3.14
output("{n:08b}")                  // 11111111
output("{n:x}")                    // ff (hex lowercase)
output("{n:X}")                    // FF (hex uppercase)
output("{n:10d}")                  // right-aligned, space-padded
output("{name:10s}")               // left-aligned, space-padded
```

---

## 14. I/O

### 14.1 Output

```rex
output(x)           // print x followed by newline (type-dispatched)
show(x)             // print x without newline
write(buf)          // raw bytes to stdout (seq[byte] or arr[byte, N])
flush()             // drain stdout buffer
debug(x)            // stderr: "type: value\n" — development only
warn("msg")         // stderr: warning message with newline
err("msg")          // stderr: error message + exit code 1
```

`output` takes **one expression**. For multiple values on one line use string
interpolation.

### 14.2 Formatted String

```rex
str label = fmt("score: {score:.1f} / 100")
str hex = fmt("0x{addr:X}")
```

`fmt` returns a `str` instead of printing.

### 14.3 Input

```rex
str name = input("Enter your name: ")
output("Hello, {name}!")
int age = int(input("Enter your age: "))
```

### 14.4 File I/O

```rex
use file:
    file :f = open("data.txt", "r")
    str contents = f.read()
    f.close()

use file:
    file :f = open("out.txt", "w")
    f.writeln("hello")
    f.close()
```

Modes: `"r"`, `"w"`, `"a"`, `"rb"`, `"wb"`.

---

## 15. Memory Management

Rex gives explicit control over allocation strategy and collection strategy per
scope. Both are orthogonal and may be combined.

### 15.1 Syntax

```rex
use mm <mode>:
    // everything here uses the chosen allocator

use mm <mode> gc <mode>:
    // allocator + collector

use gc <mode>:
    // collector only (allocator stays default)
```

### 15.2 MM Modes

| Mode     | Strategy                      | Speed             | Best for                              |
|----------|-------------------------------|-------------------|---------------------------------------|
| `arena`  | Bump-pointer                  | 1 instruction     | Frame-scoped work, parsers, per-request buffers |
| `pool`   | Fixed-size freelist           | O(1)              | Homogeneous objects: game entities, packets |
| `stack`  | LIFO                          | O(1), zero frag   | Recursive algorithms, scratch space   |
| `heap`   | General-purpose (`malloc`)    | O(log n)          | Long-lived objects, unpredictable lifetimes |
| `static` | Compile-time static segment   | 0 runtime cost    | Lookup tables, constant data          |

```rex
use mm arena:
    seq[int] scratch = [1, 2, 3]
    output(scratch.sum())
// entire arena freed in one instruction at scope exit
```

### 15.3 GC Modes

| Mode     | Strategy                   | Pauses | Best for                                      |
|----------|----------------------------|--------|-----------------------------------------------|
| `sweep`  | Mark-and-sweep             | Yes    | General managed memory                        |
| `ref`    | Reference counting         | None   | Latency-sensitive; does not collect cycles    |
| `gen`    | Generational               | Amortised | Long-running programs, mixed lifetimes     |
| `inc`    | Incremental                | None   | Real-time, games, UI                          |
| `region` | Region-based               | None   | Compilers, databases, lifetime-partitioned data |

### 15.4 Combined Example

```rex
use mm arena gc sweep:
    int i = 0
    for i in 1..100:
        seq[int] tmp = [i, i*2, i*3]
        output(tmp.sum())
// arena reset + sweep on exit
```

### 15.5 Performance Reference

| Strategy     | Allocation cost    | Deallocation cost |
|--------------|--------------------|-------------------|
| `mm arena`   | 1 instruction      | 1 instruction     |
| `mm pool`    | O(1) freelist      | O(1) freelist     |
| glibc malloc | O(log n)           | O(log n)          |

Rex `mm pool` is **~12× faster** than glibc for homogeneous allocations.

---

## 16. Module System

```rex
use math:               // import stdlib math module
    float r = sqrt(2.0)

use io:                 // import stdlib io module
    // file, stdin, stdout operations
```

Modules resolve at compile time. No runtime dynamic loading.

---

## 17. Compiler Pipeline

The compiler processes source in a single linear pass:

```
source.rex
    │
    ▼
[ Lexer ]
    Produces a token stream:
    TOK_INT, TOK_IDENT, TOK_IF, TOK_FOR, …
    Tracks INDENT / DEDENT from indentation changes.
    Strips comments and blank lines.
    │
    ▼
[ Parser ]
    Recursive-descent.
    Maintains var_table (name, type, value, mutability, initialisation).
    Maintains proto_table (name, return type, param count, param types).
    Emits IR records instead of machine bytes.
    │
    ▼
[ IR Buffer ]
    Flat array of 32-byte records.
    One record per compiler operation.
    │
    ▼
[ Optimisation Passes ]
    Pass 1: Constant folding      — evaluate compile-time expressions
    Pass 2: Dead store elimination — remove stores never read
    Pass 3: Load-store coalescing  — collapse redundant load/store pairs
    Pass 4: Linear scan register allocation — map vregs to physical registers
    Pass 5: Peephole optimisation  — collapse adjacent instruction pairs
    │
    ▼
[ x86-64 Emission ]
    Convert IR records to machine bytes.
    IR_NOP records are silently skipped.
    Forward jumps patched via label resolution table.
    │
    ▼
[ ELF64 Writer ]
    Prepend 120-byte ELF64 + program header.
    Inline all runtime blobs (print, alloc, hash, error).
    Emit a 5-byte JMP past the runtime blobs to user code start.
    Write complete executable to disk — no linker step.
    │
    ▼
  ./output   (self-contained ELF64 binary)
```

### 17.1 IR Record Layout (32 bytes)

```
offset  size  field     description
──────  ────  ────────  ──────────────────────────────────────────────
  0       1   opcode    operation (IR_ADD, IR_JMP, IR_CALL, …)
  1       1   type      TYPE_INT / TYPE_FLOAT / TYPE_BOOL / TYPE_STR / …
  2       2   dst       destination virtual register (0 = none)
  4       2   src1      first source virtual register (0 = unused)
  6       2   src2      second source virtual register (0 = unused)
  8       8   imm       primary immediate: int value / float bits / var index / label
 16       8   aux       secondary immediate: condition code / arg count / step
 24       4   flags     IR_FLAG_CONST | IR_FLAG_DEAD | IR_FLAG_SPILLED | IR_FLAG_LOOP_INV
 28       4   _pad      reserved (must be zero)
```

### 17.2 ELF64 Binary Layout

| Offset | Size    | Content                                          |
|--------|---------|--------------------------------------------------|
| 0      | 64 B    | ELF64 header                                     |
| 64     | 56 B    | Program header (LOAD, RWX)                       |
| 120    | 8 B     | Padding to 128 B                                 |
| 128    | 5 B     | `jmp` past runtime blobs to user code            |
| 133    | …       | Runtime blobs: print_int, print_float, print_bool, print_str, alloc, hash, error |
| CODE_START | … | Compiled user code                           |

- Entry point VA: `0x400080`
- Load base: `0x400000`
- No `.plt`, no `.got`, no dynamic linker segment.

---

## 18. Type Inspection

```rex
int x = 5
output(typeof x)    // prints compile-time type token as int
```

Type tokens: `int=1`, `float=2`, `bool=3`, `str=5`, `seq=6`, `dict=7`.

---

## 19. Safety Model

Rex has two safety levels, declared per-protocol with a decorator:

| Mode      | Allows                                    | Verified by compiler |
|-----------|-------------------------------------------|----------------------|
| `#safe`   | All Rex constructs except `$` and raw pointer arithmetic | Yes |
| `#unsafe` | Raw `$` syscalls, direct memory access    | No (programmer's responsibility) |

The default (no decorator) is equivalent to `#safe`. Unsafe operations outside
an `#unsafe` protocol are a **compile-time error**.

---

## 20. Keywords Reference

### Reserved — Types
`int`, `float`, `bool`, `str`, `char`, `byte`, `seq`, `arr`, `dict`, `tup`

### Reserved — Literals
`true`, `false`, `unknown`, `null`

### Reserved — Statements
`output`, `show`, `write`, `flush`, `debug`, `warn`, `err`, `input`, `fmt`
`if`, `elif`, `else`, `when`, `is`, `match`
`for`, `each`, `while`, `repeat`, `stop`, `skip`, `pass`
`return`, `prot`, `use`, `swap`, `push`, `pop`

### Reserved — Operators (word form)
`and`, `or`, `not`, `in`, `abs`, `len`, `cap`, `typeof`, `hash`, `flip`, `rand`
`carry`, `overflow`

### Reserved — Memory
`mm`, `gc`, `arena`, `pool`, `stack`, `heap`, `static`
`sweep`, `ref`, `gen`, `inc`, `region`

### Reserved — Future
`blast`, `pipe`, `own`, `move`, `free`, `align`, `const`, `volatile`
`assert`, `unreachable`, `clz`, `ceil`, `floor`, `fract`
`sign`, `real`, `imag`, `conj`

---

## 21. Standard Library Modules (planned)

| Module   | Contents                                             |
|----------|------------------------------------------------------|
| `math`   | `sqrt`, `pow`, `sin`, `cos`, `tan`, `log`, `exp`, `pi`, `e` |
| `io`     | File open/read/write/close; stdin; buffered I/O      |
| `os`     | Process exit, environment variables, command-line args |
| `str`    | Additional string utilities beyond built-in methods  |
| `json`   | Parse and emit JSON                                  |
| `net`    | TCP/UDP socket primitives via raw syscalls           |
| `complex`| Complex number arithmetic (removed from core)        |

---

## 22. Design Goals Summary

| Goal                      | How Rex achieves it                                              |
|---------------------------|------------------------------------------------------------------|
| Zero runtime dependencies | Runtime inlined as blobs in every output binary                  |
| Tiny binary size          | Hand-crafted 120-byte ELF header; ~500 B baseline               |
| Fast startup              | No dynamic linker, no constructor tables: ~0.05 ms               |
| Visible mutation          | `:` sigil at every write site; immutable by default              |
| Controlled memory         | `use mm X gc Y:` per scope; 5 allocators × 5 collectors          |
| C-competitive speed       | IR + 5-pass optimizer; linear scan register allocation           |
| Safe by default           | `#unsafe` required for raw syscalls and pointer arithmetic        |
| Self-hostable             | Language is expressive enough to write its own compiler in Rex   |

---

## 23. Example Programs

### Hello World
```rex
output("Hello, World!")
```

### Fibonacci with memoisation
```rex
#memo
prot fib(int n) -> int:
    if n <= 1:
        return n
    return @fib(n-1) + @fib(n-2)

output(@fib(40))
```

### Sum with arena allocator
```rex
use mm arena:
    seq[int] nums = [1, 2, 3, 4, 5]
    int total = nums.sum()
    output("sum: {total}")
```

### Dictionary word count
```rex
dict[int] freq
str text = "the cat sat on the mat"
seq[str] words = text.words()

each word in words:
    int count = freq.get_or(word, 0)
    :freq[word] = count + 1

each k, v in freq:
    output("{k}: {v}")
```

### Multi-level loop exit
```rex
bool found = false
int fx = 0
int fy = 0

for i in 0..10:
    for j in 0..10:
        if i * j == 42:
            :found = true
            :fx = i
            :fy = j
            stop 2
else:
    output("no solution found")

if found:
    output("found: {fx} × {fy} = 42")
```

### Protocol with multiple return values
```rex
prot minmax(seq[int] s) -> (int, int):
    int lo = s[0]
    int hi = s[0]
    each n in s:
        if n < lo: :lo = n
        if n > hi: :hi = n
    return lo, hi

seq[int] data = [3, 1, 4, 1, 5, 9, 2, 6]
int lo, int hi
:lo, :hi = @minmax(data)
output("min={lo}, max={hi}")
```
