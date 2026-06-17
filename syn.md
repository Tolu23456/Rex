# Rex V0.1 — Language Syntax Reference

**Status markers used in this document:**
- ✅ Implemented and tested
- ✅ Lexed — token exists, parser/codegen pending
- ✅ Planned — Stage 9 / Stage 10 roadmap

---

## Variable Declaration ✅

### Immutable (default)
Declare with a type and an initial value. If no `:` write site exists in the same scope, the compiler treats this as a true constant — eligible for constant folding and inlining.
```rex
int age = 13
float pi = 3.14159
str name = "Rex"
```

### Mutable
Declarations are always written cleanly — no sigil at the declaration site. Mutability is inferred by the compiler from usage: if you ever write `:x = ...` in scope, `x` is mutable. The `:` sigil appears **only at write sites**.
```rex
int age = 13        // declared cleanly
:age = 14           // compiler sees this — age is mutable
```

Declare without an initial value, then assign:
```rex
int total
:total = 100
```

### The `:` sigil — write site marker
Every mutation must be marked with `:` at the point where it happens. This makes state changes visible at a glance without scrolling to the declaration.
```rex
int x = 5           // constant — compiler can fold this
int y = 0           // will be mutated below
:y = x + 10         // explicit mutation — eye immediately spots it
++y                 // increment — self-evidently a mutation, no sigil needed
swap x y            // swap — self-evidently a mutation, no sigil needed
```

### Compiler enforcement
- No `:` write site in scope → true constant. The compiler may inline or fold the value.
- At least one `:` write site → mutable. The compiler tracks this per variable.
- Attempting to read an uninitialised variable (declared but never assigned) is a compile-time error.

### Type inference ✅
Omit the type annotation and Rex infers it from the initial value or expression.
The `:` mutation rule still applies. Explicit types are always valid and preferred
for protocol parameters and public interfaces.

```rex
x = 5               // infers int
y = 3.14            // infers float
z = "hello"         // infers str
w = true            // infers bool
result = @add(2, 3) // infers from protocol return type

:x = x + 1          // mutation still requires :
```

#### Rules
- **Local only:** Inference does not cross scope boundaries.
- **Literal mapping:** `5` -> `int`, `3.14` -> `float`, `"..."` -> `str`, `true`/`false`/`unknown` -> `bool`.
- **Return mapping:** `x = @func()` infers from the protocol's declared return type.
- **Operator mapping:** `x = a + b` infers the type of the expression. If `a` and `b` are `int`, result is `int`. If either is `float`, result is `float`.
- **Conflict:** `int x = 3.14` is a compile-time error.

If no initial value is provided, the type must be stated explicitly:
```rex
int total           // explicit — no value yet
:total = 100
```

---

## Data Types ✅

| Type         | Syntax Example           | Notes                                                        |
|--------------|--------------------------|--------------------------------------------------------------|
| `int`        | `int a = 5`              | 64-bit signed integer                                        |
| `float`      | `float b = 1.5`          | 64-bit double (IEEE 754, SSE2)                               |
| `bool`       | `bool f = true`          | Tri-state: `true`, `false`, `unknown` (Kleene logic)         |
| `str`        | `str s = "Rex"`          | Heap-managed UTF-8 string; `[cap][len][data]` layout         |
| `char`       | `char c = 'R'`           | Single UTF-8 byte; lightweight alias over `byte`             |
| `byte`       | `byte b = 0xFF`          | Raw unsigned 8-bit value; for binary data and I/O            |
| `seq[T]`     | `seq[int] nums`          | Typed dynamic sequence (heap); full method API               |
| `dict[T]`    | `dict[int] d`            | Typed SipHash map; keys always `str`, value type is `T`      |
| `tup[T...]`  | `tup[int,str] t`         | Fixed heterogeneous tuple; positional, immutable by default  |

> **`complex` removed from core.** It is a niche type with significant implementation cost. It will be available as a standard library import in a future release. Existing `complex` code continues to work in V0.1 but is considered deprecated in core.

### Binary / hex / octal literals ✅
```rex
int mask = 0b1100
int page = 0xFF
int oct  = 0o17
```

### Unimplemented types ✅
`set` and `tup` are planned but not yet implemented.

---

## `bool` — Tri-State Logic ✅

Rex `bool` has three values: `true` (1), `false` (0), and `unknown` (hardware entropy via `rdrand`). This is **Kleene strong three-valued logic** — a mathematically principled system, not an arbitrary extension.

`unknown` represents genuine indeterminacy at runtime. It maps directly to the `rdrand` instruction and is a first-class Rex value, not a special-case enum.

### `and` truth table
| `and`       | `false`     | `true`      | `unknown`   |
|-------------|-------------|-------------|-------------|
| **`false`** | false       | false       | **false**   |
| **`true`**  | false       | true        | unknown     |
| **`unknown`**| **false**  | unknown     | unknown     |

Rule: **false dominates** — `false and anything` is always `false`.

### `or` truth table
| `or`        | `false`     | `true`      | `unknown`   |
|-------------|-------------|-------------|-------------|
| **`false`** | false       | true        | unknown     |
| **`true`**  | true        | true        | **true**    |
| **`unknown`**| unknown    | **true**    | unknown     |

Rule: **true dominates** — `true or anything` is always `true`.

### `not`
| input     | result    |
|-----------|-----------|
| `false`   | `true`    |
| `true`    | `false`   |
| `unknown` | `unknown` |

### Usage
```rex
bool coin
:coin = unknown         // hardware-entropy value
output(coin)             // prints: true, false, or unknown

bool a = true
bool b = unknown

bool result
:result = a and b       // unknown  (true and unknown = unknown)
:result = a or b        // true     (true dominates)
:result = not b         // unknown  (not unknown = unknown)
```

---

## Operators

### Arithmetic ✅
```rex
:c = a + b
:c = a - b
:c = a * b
:c = a / b
:c = a % b
```

### Bitwise ✅
```rex
:z = x & y       // AND
:z = x | y       // OR
:z = x ^ y       // XOR
:z = ~x          // NOT
:z = x << 1      // left shift
:z = x >> 1      // right shift
```

### Increment / Decrement ✅
```rex
++x
--x
```

### Logical ✅

`and` and `or` emit short-circuit machine code: `and` skips the RHS if the LHS is false;
`or` skips the RHS if the LHS is true.

```rex
if x > 0 and y > 0:
    output("both positive")

if a == 1 or b == 1:
    output("at least one")
```

### `not` operator ✅

Boolean inversion and bitwise NOT.

```rex
bool flag = true
if not flag:
    output("off")    // prints nothing

int mask = 0x0F
int flipped = not mask // 0xFFFFFFFFFFFFFFF0 (64-bit bitwise NOT)
```

**Emission:**
- `bool` operand: `xor rax, 1` (flips 0 ↔ 1)
- `int` operand: `not rax` (bitwise complement)
- `unknown` operand: remains `unknown` (per Kleene logic)

### Identity — `is` / `is not` ✅

Semantic identity check. Evaluates to a hardware `cmp` followed by `sete`/`setne`.

```rex
if x is 0:
    output("zero")

if ptr is not null:
    output("valid")
```

- `a is b` → yields `1` (true) or `0` (false).
- `ptr is null` checks if the pointer value is `0`.
- Used for checking against sentinel values without triggering structural equality logic.

### Membership — `in` ✅

Check whether a value is present in a `seq`, `dict`, or `str`.

```rex
seq[int] nums = [1, 2, 3]
if 2 in nums:
    output("found")

dict[int] d = {"a": 1}
if "a" in d:
    output("key exists")

str s = "hello"
if "ell" in s:
    output("substring found")
```

**Complexity:**
- `seq[T]`: O(n) linear search.
- `dict[T]`: O(1) average (hash lookup).
- `str`: O(n+m) SIMD search (using `rt_str_find`).

### Pipeline — `->` ✅

Cascades the result of one expression into the next as the first argument.

```rex
// Equivalent to: output(@compute(x))
@compute(x) -> output

// Equivalent to: @process(a + b)
a + b -> @process()
```

### Syscall intercept — `$` ✅

Drop directly into kernel space via raw `syscall`. Parameters map to `rdi`, `rsi`, `rdx`, `r10`, `r8`, `r9`. Returns `rax`.

```rex
#unsafe
prot exit(int code):
    $(60, code) // sys_exit

#unsafe
prot write_stdout(str s):
    $(1, 1, s, len(s)) // sys_write(stdout, buf, len)
```

### Swap ✅
```rex
swap x y
```

### Absolute value ✅
```rex
int v
:v = abs(x)
```

### Capacity ✅
Returns the allocated capacity of a `seq` or `dict` (the hidden header word).
```rex
int c
:c = cap items
```

### Hash ✅
Direct SipHash-2-4 over a memory region. Returns a 64-bit hash in `rax`.
```rex
int h
:h = hash s
```

### Hardware flags ✅
Read CPU EFLAGS directly after arithmetic. Evaluate to `bool`.
```rex
bool c
:c = carry       // true if last op produced a carry

bool ov
:ov = overflow   // true if last op overflowed
```

### Flip / Rand ✅
`flip` inverts a bool via bitwise NOT. `rand` sources a hardware-entropy integer via `rdrand`.
```rex
bool b = true
flip b

int n
:n = rand
```

---

## Type Casting ✅ / ✅

Cast functions are global. They look like function calls — no `.` needed.
The type name IS the cast function.

| Cast | From | Notes |
|---|---|---|
| `int(x)` | `float`, `str`, `char`, `byte`, `bool` | Float truncates toward zero; str parses decimal |
| `float(x)` | `int`, `str` | str parses decimal notation |
| `str(x)` | `int`, `float`, `bool`, `char`, `byte` | Human-readable string representation |
| `char(x)` | `int`, `byte` | Interprets as UTF-8 code point |
| `byte(x)` | `int`, `char` | Low 8 bits |
| `bool(x)` | `int` | 0 → `false`, non-zero → `true` |

```rex
float f = 3.7
int i = int(f)          // 3 — truncates toward zero (cvttsd2si)

int n = 5
float g = float(n)      // 5.0 (cvtsi2sd)

str s = str(42)         // "42"
str t = str(3.14)       // "3.14"
str u = str(true)       // "true"

int parsed = int("42")  // 42
float fp = float("3.14") // 3.14

char c = char(65)       // 'A'
int code = int('A')     // 65
byte b = byte(255)      // 0xFF
```

---

## Type Inspection

### `typeof` ✅
Returns the compiler's internal type token for a variable as an integer. Useful for conditional dispatch.
```rex
int x = 5
output(typeof x)
```

---

## Protocols ✅

Define with `prot`. Parameters are **typed** (type-first, matching Rex's variable style).
Return a value with `return`. The return type is annotated with `->`.

### Basic definition

```rex
prot greet():
    output("Hello")

prot square(int x) -> int:
    return x * x

prot add(int a, int b) -> int:
    return a + b
```

**No params:** empty parens — `prot greet():`.
**No return value:** omit the `->` annotation entirely. No `None`, no `void`.

### Calling with `@`

`@` is Rex's protocol call prefix. It visually separates **user-defined protocols**
from **built-in statements** (`output`, `push`, `pop`, `err`, etc.). Every `@` in
Rex code means: "this is yours."

```rex
@greet()

int result
:result = @add(3, 4)
output(result)
```

### Multiple return values — tuples ✅

A protocol can return a tuple of values using `-> (T, T, ...)`. The caller
destructures with a matching declaration on the left side.

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
output(lo)
output(hi)
```

**Implementation:**
- 2 values: returned in `rax` and `rdx`.
- 3+ values: returned via a stack buffer allocated by the caller.

### Protocol decorators — # ✅

Decorators annotate a protocol with compiler directives. They use the `#` sigil
and stack **one per line** directly above the `prot` keyword.

```rex
#memo
prot fib(int n) -> int:
    if n <= 1:
        return n
    return @fib(n-1) + @fib(n-2)

#hot
#inline
prot dot(int a, int b) -> int:
    return a * b

#cold
#safe
prot log_error(str msg):
    err(msg)
```

**Why `#` and not `@`?** `@` is already Rex's call prefix. Using it for decorators
would create two meanings for the same sigil. `#` is free (Rex comments use `//`),
unambiguous, and reads clearly as an annotation.

**Rule:** decorators are always on their own lines, never inline. Multiple decorators
stack vertically — one idea per line.

#### Built-in decorators

| Decorator | Category | Effect |
|---|---|---|
| `#memo` | Algorithmic | Cache return value keyed on input; skip recomputation |
| `#pure` | Algorithmic | No side effects — compiler may reorder or elide calls |
| `#total` | Algorithmic | Hint: terminates for all inputs |
| `#inline` | Performance | Force inline at every call site |
| `#noinline` | Performance | Prevent inlining; useful for hot/cold splitting |
| `#hot` | Performance | Called frequently — optimize for throughput |
| `#cold` | Performance | Called rarely — optimize for binary size |
| `#safe` | Safety | Compiler verifies: no raw syscalls or pointer arithmetic inside |
| `#unsafe` | Safety | Allows raw `$` syscalls and direct memory operations |

Decorators can be combined freely. Order does not matter.

```rex
#memo
#pure
prot factorial(int n) -> int:
    if n <= 1:
        return 1
    return n * @factorial(n - 1)
```

### Recursive protocols ✅

Protocols may call themselves. Rex tracks recursion and handles stack frames
correctly. `#memo` is especially useful on recursive protocols.

```rex
prot fib(int n) -> int:
    if n <= 1:
        return n
    return @fib(n-1) + @fib(n-2)
```

### Up to 6 parameters ✅

Rex maps parameters to SysV ABI registers (`rdi`, `rsi`, `rdx`, `rcx`, `r8`, `r9`).
The maximum is 6 parameters per protocol. This is a current implementation limit.

```rex
prot clamp(int val, int lo, int hi) -> int:
    if val < lo:
        return lo
    if val > hi:
        return hi
    return val
```

---

## Control Flow

### Conditional ✅
```rex
int x = 10

if x == 10:
    output("ten")
elif x == 5:
    output("five")
else:
    output("other")
```

All six comparison operators are supported: `==`, `!=`, `<`, `>`, `<=`, `>=`.

### `when` / `is` ✅
Switch-like routing. Each `is` case matches against the `when` expression.
```rex
int code = 2

when code:
    is 1:
        output("one")
    is 2:
        output("two")
    else:
        output("other")
```

### `match` ✅
Structural pattern matching. Dense integer ranges compile to O(1) jump tables.
```rex
match x:
    int:
        output("integer")
    float:
        output("float")
    str:
        output("string")
```

### `pass` ✅
Zero-byte semantic placeholder for empty blocks or unimplemented stubs.
```rex
prot todo():
    pass

if x == 0:
    pass
else:
    output(x)
```

---

## Loops

### For loop ✅
Range-based. Optional `step`. Both bounds accept full expressions (variables,
arithmetic, unary negation). The loop variable is implicitly mutable — the
loop syntax itself implies iteration; no `:` sigil is needed at the declaration.
```rex
for i in 0..10:
    output(i)

for i in 0..20 step 2:
    output(i)

for i in -5..5:
    output(i)
```

### While loop ✅
```rex
while true:
    output("Hello")
    stop
```

### `stop` ✅
Break out of the current (innermost) loop.
```rex
for i in 0..100:
    if i == 5:
        stop
    output(i)
```

### `stop N` ✅

Multi-level break. `stop N` breaks out of `N` nested loops at once.
`stop 1` is identical to bare `stop` (break the innermost loop).

```rex
for i in 0..10:
    for j in 0..10:
        if i == j:
            stop 2    // break both loops simultaneously
    output(i)          // never reached if i == j fires
```

**Planned semantics:**
- The break-patch stack is extended with a depth counter alongside each JMP slot.
- `stop N` walks `N` levels deep in the break-patch stack and emits a JMP to the
  Nth outer loop's exit address.
- `stop 1` is equivalent to the current `stop` (innermost loop exit).
- A depth that exceeds the current nesting level is a compile-time error.

**Distinction from `skip N`:**
- `skip N` is a *continue* (jump back to the Nth outer loop's condition check).
- `stop N` is a *break* (jump past the Nth outer loop's exit entirely).

### `skip N` ✅
Continue the Nth enclosing loop (jump back to its condition check).
`skip 1` is a continue of the innermost loop.
```rex
for i in 0..10:
    for j in 0..10:
        if i == j:
            skip 2    // re-evaluate outer loop condition
```

### Loop `else:` ✅

An `else:` block attached directly to a `for` or `while` loop executes **only if**
the loop completes naturally — i.e., it was never interrupted by a `stop`.

```rex
for i in 0..10:
    if i == 5:
        stop
else:
    output("completed without stop")
```

```rex
int target = 7
for i in 0..10:
    if i == target:
        stop
else:
    output("target not found in range")
```

**Planned semantics:**
- At the start of the loop a `bool` flag is initialised to `false` (no-break).
- Every `stop` site inside the loop sets the flag to `true` before jumping out.
- After the loop's exit label, an `if flag == false:` guards the `else:` block.
- The flag variable consumes one `var_table` slot (reclaimed via `scope_stack` on
  loop exit, same strategy as the `for` end-variable `_fe`).
- An `else:` block is optional; omitting it has zero overhead.

**Interaction with `stop N`:**
- `stop N` where `N > 1` bypasses the `else:` of all loops it exits (the flag
  is set in each bypassed loop before the outer JMP is taken).

### `repeat N:` ✅

Counted loop with no explicit counter variable. Emits a single hardware
`dec` + `jnz` loop — faster than a `for` loop when the iteration index is
not needed inside the body.

```rex
repeat 8:
    output("tick")
```

```rex
int sum = 0
repeat 100:
    :sum = sum + 1
output(sum)
```

**Planned emission:**

```
mov rcx, N          ; load count into rcx (or r15 to avoid clobber)
.top:
    <body>
dec rcx
jnz .top
```

- `N` must be an integer literal or a compile-time constant expression.
- The counter register (`rcx`) is not exposed as a variable inside the body.
  Use a `for` loop if you need the index.
- Nesting is supported; each `repeat` uses a fresh register (spill to stack
  if all candidate registers are occupied).
- `stop` inside `repeat` emits the standard break-JMP and is patched at
  `repeat` exit, identical to `for`/`while`.

### `each` ✅

Cache-aligned iterator over any collection. Preferred over `for i in 0..N:` when
the iteration index is not needed — the compiler emits a prefetch hint
(`prefetcht0`) on each iteration for better cache behaviour.

Works on `seq[T]`, `arr[T, N]`, `str` (yields `char`), and `dict[T]` (yields
key-value pairs). Token is lexed; parser/codegen pending.

#### Basic form — element only
```rex
each item in items:
    output(item)
```

#### With index — `each i, item in <col>:`
```rex
each i, item in items:
    output("{i}: {item}")
```

`i` is a zero-based `int`. It is implicitly mutable (the loop advances it) but
is read-only inside the body — assigning to `i` is a compile-time error.

#### Over a `str` — yields `char`
```rex
str word = "Rex"
each ch in word:
    output(ch)         // R, e, x
```

#### Over a `dict` — yields key and value
```rex
dict[int] scores = {"alice": 95, "bob": 87}
each k, v in scores:
    output("{k}: {v}")
```

Key iteration order is unspecified (hash-determined). For sorted output use
`.keys().sort()` then iterate.

#### Mutating form — `:` on the element name
Prefix the element name with `:` to write back to the collection. Without `:`,
the element is a read-only copy.
```rex
seq[int] nums = [1, 2, 3, 4, 5]
each :n in nums:
    :n = n * 2          // doubles every element in place
output(nums)            // [2, 4, 6, 8, 10]
```

The `:` on the `each` variable signals that writes flow back to the source
collection. Attempting to write to a non-`:` `each` variable is a compile-time
error.

#### `stop` and `skip` inside `each`
```rex
each item in items:
    if item == 0:
        skip 1          // skip to next element
    if item < 0:
        stop            // exit the each loop entirely
    output(item)
```

#### Nested `each`
```rex
each row in matrix:
    each cell in row:
        output("{cell} ")
    output("")           // newline after each row
```

#### `each` vs `for` — when to use which

| | `for i in 0..N:` | `each item in col:` |
|---|---|---|
| Iterates a numeric range | ✅ yes | ✗ no |
| Iterates a collection | ✗ no | ✅ yes |
| Index exposed | ✅ always | optional (`each i, item`) |
| Cache prefetch emitted | ✗ | ✅ yes |
| Mutating elements | ✗ (use `col[i]`) | ✅ `:` form |
| Works on `dict` | ✗ | ✅ yes |
| Works on `str` | ✗ | ✅ yes (yields `char`) |

**Rule:** use `each` when you have a collection and don't need to compute the
index manually. Use `for` when you need a numeric counter or a custom step.

---

## Sequences ✅

Sequences are heap-allocated, typed, and growable. The element type is declared
in brackets. Method-call syntax is the canonical API.

### Declaration and literals ✅

```rex
seq[int] nums               // empty seq — extend or insert elements
seq[int] nums = [1, 2, 3]  // literal initialisation — type inferred from declaration
seq[str] words = ["hello", "world"]
seq[float] vals = [1.0, 2.5, 3.14]
```

`[...]` is only valid at a seq declaration site. The compiler verifies each
element matches `T` — a mismatch is a compile-time error.

### Pre-sizing

Declare an initial capacity without setting any elements. Avoids the first few
grows when the final size is roughly known:

```rex
seq[int] buf = 1024     // capacity 1024, length 0 — no elements yet
buf.extend([42])        // first element; no allocation needed
```

### Index access and negative indexing

```rex
output(nums[0])          // first element
output(nums[-1])         // last element  (len - 1)
output(nums[-2])         // second-to-last
:nums[0] = 99           // write to first  — `:` mutation sigil required
:nums[-1] = 0           // write to last
```

Negative indices count from the end. An out-of-range index (positive or
negative) is a runtime panic.

### Concatenation ✅ / ✅

`+` produces a new seq containing all elements of both operands. Neither
operand is modified:

```rex
seq[int] a = [1, 2, 3]
seq[int] b = [4, 5, 6]
seq[int] c = a + b      // [1, 2, 3, 4, 5, 6]
```

---

### `seq[T]` method reference

#### Core ✅

| Method | Returns | Notes |
|---|---|---|
| `.pop()` | `T` | Remove and return last element (LIFO) |
| `.get(i)` | `T` | Same as `s[i]`; supports negative indices |
| `.set(i, val)` | — | Same as `:s[i] = val`; supports negative indices |
| `.len()` | `int` | Current element count |
| `.cap()` | `int` | Allocated capacity |
| `.clear()` | — | Remove all elements; keep allocation |
| `.sort()` | — | In-place ascending sort |
| `.reverse()` | — | In-place reversal |
| `.contains(val)` | `bool` | Linear scan; `true` if value found |
| `.remove(i)` | — | Remove element at index i; shift remaining left — O(n) |
| `.slice(start, end)` | `seq[T]` | New sub-sequence; `end` is exclusive |
| `.map(fn)` | `seq[U]` | New seq — every element transformed via `fn` |
| `.filter(fn)` | `seq[T]` | New seq — keep elements where `fn` returns `true` |
| `.each(fn)` | — | Call `fn(element)` for every element in order |

#### Access ✅

| Method | Returns | Notes |
|---|---|---|
| `.first()` | `T` | First element; runtime error if empty |
| `.last()` | `T` | Last element; runtime error if empty |
| `.is_empty()` | `bool` | True when `len() == 0` |
| `.index_of(val)` | `int` | Index of first occurrence; `-1` if not found |
| `.find(fn)` | `T` | First element where `fn` returns `true`; error if none |
| `.find_index(fn)` | `int` | Index of first match; `-1` if none |

#### Mutation ✅

| Method | Returns | Notes |
|---|---|---|
| `.insert(i, val)` | — | Insert before index i; shift right — O(n) |
| `.prepend(val)` | — | Insert at front; same as `.insert(0, val)` — O(n) |
| `.dequeue()` | `T` | Remove and return first element (FIFO); shift left — O(n) |
| `.extend(other)` | — | Append all elements of `other` seq in place |
| `.fill(val)` | — | Set every element to `val` (length unchanged) |
| `.truncate(n)` | — | Keep only first `n` elements; length becomes `min(n, len)` |
| `.swap_at(i, j)` | — | Swap elements at indices `i` and `j` in place |
| `.sort_by(fn)` | — | In-place sort; `fn(a, b) -> int` — negative/zero/positive |
| `.sort_desc()` | — | In-place descending sort |

#### Aggregation ✅

| Method | Returns | Notes |
|---|---|---|
| `.sum()` | `T` | Sum of all elements; `T` must be `int` or `float` |
| `.min()` | `T` | Minimum value; runtime error if empty |
| `.max()` | `T` | Maximum value; runtime error if empty |
| `.count(fn)` | `int` | Number of elements where `fn` returns `true` |

#### Predicate checks ✅

| Method | Returns | Notes |
|---|---|---|
| `.all(fn)` | `bool` | `true` if every element satisfies `fn` |
| `.any(fn)` | `bool` | `true` if at least one element satisfies `fn` |
| `.none(fn)` | `bool` | `true` if no element satisfies `fn` |

#### Transformation ✅

| Method | Returns | Notes |
|---|---|---|
| `.reduce(fn, init)` | `T` | Left fold; `fn(accumulator, element) -> T` |
| `.unique()` | `seq[T]` | New seq with duplicates removed; order preserved |
| `.copy()` | `seq[T]` | Shallow copy; independent allocation |
| `.zip(other)` | `seq[tup[T,U]]` | Pair elements by index; length = min of both |
| `.flatten()` | `seq[T]` | Collapse `seq[seq[T]]` into `seq[T]` |

---

### Examples

```rex
seq[int] nums = [3, 1, 4, 1, 5, 9, 2, 6]

// sorting and access
nums.sort()
output(nums.first())         // 1
output(nums.last())          // 9
output(nums[-1])             // 9 — negative index

// search
output(nums.index_of(5))     // 4
output(nums.find_index(fn(int x) -> bool: x > 7))   // 7 (value 9)

// aggregation
output(nums.sum())           // 31
output(nums.min())           // 1
output(nums.max())           // 9
output(nums.count(fn(int x) -> bool: x % 2 == 0))   // 3

// predicates
output(nums.any(fn(int x) -> bool: x > 8))   // true
output(nums.all(fn(int x) -> bool: x > 0))   // true
output(nums.none(fn(int x) -> bool: x < 0))  // true

// transformation
seq[int] doubled = nums.map(fn(int x) -> int: x * 2)
seq[int] evens = nums.filter(fn(int x) -> bool: x % 2 == 0)
int total = nums.reduce(fn(int acc, int x) -> int: acc + x, 0)
seq[int] deduped = nums.unique()             // [3, 1, 4, 5, 9, 2, 6]

// mutation
nums.insert(0, 0)           // prepend 0
nums.extend([7, 8])         // append 7 and 8
nums.truncate(5)            // keep first 5

// concatenation
seq[int] a = [1, 2, 3]
seq[int] b = [4, 5, 6]
seq[int] c = a + b          // [1, 2, 3, 4, 5, 6]
```

A compile-time error is raised when pushing or inserting a value whose type
mismatches `T`.

---

### Fixed Arrays — `arr[T, N]` ✅

For data whose size is known at compile time. Stack-allocated, zero header
overhead, no heap touch. `N` must be an integer literal or compile-time
constant.

```rex
arr[int, 3] rgb = [255, 128, 0]
arr[float, 4] quat = [0.0, 0.0, 0.0, 1.0]
```

`arr[T, N]` is NOT growable. `.push()`, `.extend()`, `.dequeue()` are not
available. The element count is fixed and known to the compiler — `.len()`
is a compile-time constant.

### Index access

```rex
output(rgb[0])           // 255
:rgb[2] = 64            // write — `:` sigil required
output(rgb[-1])          // 0 — negative index supported
```

### `arr[T, N]` method reference

| Method | Returns | Notes |
|---|---|---|
| `.len()` | `int` | Always `N` — compile-time constant |
| `.get(i)` | `T` | Same as `a[i]`; negative indices supported |
| `.set(i, val)` | — | Same as `:a[i] = val` |
| `.contains(val)` | `bool` | Linear scan |
| `.sort()` | — | In-place ascending sort |
| `.sort_by(fn)` | — | In-place sort with custom comparator |
| `.sort_desc()` | — | In-place descending sort |
| `.reverse()` | — | In-place reversal |
| `.slice(start, end)` | `arr[T, M]` | Sub-array; `M = end - start`, compile-time |
| `.each(fn)` | — | Call `fn(element)` for every element |
| `.map(fn)` | `arr[U, N]` | New array — every element transformed |
| `.contains(val)` | `bool` | Linear scan |
| `.sum()` | `T` | Sum of all elements |
| `.min()` | `T` | Minimum value |
| `.max()` | `T` | Maximum value |
| `.copy()` | `arr[T, N]` | Independent copy |
| `.to_seq()` | `seq[T]` | Heap-allocate a new `seq[T]` with same elements |

### `arr` vs `seq` — when to use which

| | `seq[T]` | `arr[T, N]` |
|---|---|---|
| Size known at compile time | no | **yes** |
| Growable | **yes** | no |
| Memory | heap | **stack** |
| Header overhead | 16 bytes | **none** |
| Use for | lists, queues, accumulators | vectors, fixed buffers, matrices |

---

## Dictionaries ✅

Hash maps keyed by `str`, typed by value. SipHash-2-4 internally.
Keys are always `str` — no exceptions. Method-call syntax is the canonical API.

### Declaration and literals ✅

```rex
dict[int] scores                                    // empty dict
dict[int] scores = {"alice": 95, "bob": 87}        // literal initialisation
dict[str] config = {"host": "localhost", "port": "8080"}
```

`{key: val, ...}` is only valid at a dict declaration site. The compiler
verifies each value matches `T` — a type mismatch is a compile-time error.
Key iteration order is unspecified (hash-determined). For sorted keys use
`.keys().sort()`.

### Index syntax

Bracket syntax is canonical for single-key read and write:

```rex
:scores["alice"] = 95          // write — `:` sigil required, same as seq
output(scores["alice"])        // read
```

`.get()` and `.set()` are the method equivalents. Dict writes use the same `:` mutation sigil as all other write sites in Rex — `d["key"] = val` is a compile-time error; write `:d["key"] = val` instead.

### Missing-key behaviour

`.get(key)` and `d[key]` on a missing key are a **runtime error**.
Use `.get_or()` or `.has()` to guard:

```rex
if scores.has("carol"):
    output(scores["carol"])

int val = scores.get_or("carol", 0)     // 0 if missing — no insert
```

---

### `dict[T]` method reference

#### Core ✅

| Method | Returns | Notes |
|---|---|---|
| `.set(key, val)` | — | Insert or overwrite; same as `d[key] = val` |
| `.get(key)` | `T` | Retrieve value; runtime error if missing |
| `.has(key)` | `bool` | `true` if key exists |
| `.remove(key)` | — | Delete key-value pair; no-op if missing |
| `.keys()` | `seq[str]` | All keys; order unspecified |
| `.values()` | `seq[T]` | All values; order mirrors `.keys()` |
| `.len()` | `int` | Number of entries |
| `.clear()` | — | Remove all entries; keep allocation |
| `.is_empty()` | `bool` | `true` when `len() == 0` |

#### Safe access ✅

| Method | Returns | Notes |
|---|---|---|
| `.get_or(key, default)` | `T` | Return `default` if key missing; does NOT insert |
| `.get_or_set(key, default)` | `T` | Return value if present; insert `default` and return it if not |

#### Search ✅

| Method | Returns | Notes |
|---|---|---|
| `.has_value(val)` | `bool` | Linear scan over values; `true` if any value equals `val` |
| `.find_key(val)` | `str` | First key whose value equals `val`; empty string if none |

#### Bulk operations ✅

| Method | Returns | Notes |
|---|---|---|
| `.update(other)` | — | Merge `other` into self; `other`'s values overwrite on key conflict |
| `.copy()` | `dict[T]` | Independent shallow copy; same SipHash seed |
| `.entries()` | `seq[tup[str,T]]` | All key-value pairs as tuples — **blocked on `tup` implementation** |

#### Functional ✅

| Method | Returns | Notes |
|---|---|---|
| `.each(fn)` | — | Call `fn(key, val)` for every entry |
| `.map(fn)` | `dict[U]` | New dict — transform every value; `fn(str key, T val) -> U` |
| `.filter(fn)` | `dict[T]` | New dict — keep entries where `fn(str key, T val) -> bool` |
| `.any(fn)` | `bool` | `true` if at least one entry satisfies `fn(str key, T val) -> bool` |
| `.all(fn)` | `bool` | `true` if every entry satisfies `fn(str key, T val) -> bool` |
| `.count(fn)` | `int` | Number of entries satisfying `fn(str key, T val) -> bool` |

#### Structural ✅

| Method | Returns | Notes |
|---|---|---|
| `.invert()` | `dict[str]` | Swap keys and values; `T` must be `str`; duplicate values → last key wins |

---

### Examples

```rex
dict[int] scores = {"alice": 95, "bob": 87, "carol": 72}

// basic access
output(scores["alice"])                   // 95
output(scores.has("dave"))               // false
output(scores.get_or("dave", 0))         // 0

// safe insert-if-missing
int s = scores.get_or_set("dave", 50)   // inserts 50, returns 50
output(scores.len())                      // 4

// searching
output(scores.has_value(87))             // true
output(scores.find_key(95))              // "alice"

// iteration
scores.each(fn(str k, int v): output "{k}: {v}")

// transformation
dict[str] labels = scores.map(fn(str k, int v) -> str: str(v) + " pts")
// {"alice": "95 pts", "bob": "87 pts", ...}

dict[int] passing = scores.filter(fn(str k, int v) -> bool: v >= 75)
// {"alice": 95, "bob": 87}

// aggregation
output(scores.any(fn(str k, int v) -> bool: v == 100))    // false
output(scores.all(fn(str k, int v) -> bool: v > 50))      // true
output(scores.count(fn(str k, int v) -> bool: v >= 80))   // 2

// bulk
dict[int] extras = {"eve": 88, "alice": 99}
scores.update(extras)       // alice → 99, eve → 88 added
output(scores.len())         // 5

// sorted keys (deterministic output)
seq[str] sorted_keys = scores.keys().sort()
sorted_keys.each(fn(str k): output "{k}: {scores[k]}")

// invert (requires str values)
dict[str] abbrevs = {"en": "English", "es": "Spanish", "fr": "French"}
dict[str] rev = abbrevs.invert()    // {"English": "en", "Spanish": "es", ...}
```

A compile-time error is raised when a value's type mismatches `T`.

---

## Strings ✅

`str` is a heap-managed UTF-8 string with header layout
`[capacity: 8 bytes][length: 8 bytes][data: variable]`. All methods return
new strings — mutation always goes through `:s = s.method()`.

### Declaration ✅
```rex
str s = "hello"
str t = "world"
```

### Operators

```rex
// concatenation — new string, originals unchanged
str result = s + " " + t       // "hello world"

// repetition
str line = "-" * 40            // "----------------------------------------"
// equivalent to:
str line = "-".repeat(40)
```

### Indexing and negative indices ✅

```rex
char c = s[0]       // first char
char last = s[-1]   // last char
char prev = s[-2]   // second to last
```

Negative indices count from the end. Out-of-range is a runtime error.

### Comparison ✅

Content equality — not pointer equality:
```rex
if s == "hello":
    output("match")
if s != t:
    output("different")
```

All six comparison operators (`==`, `!=`, `<`, `>`, `<=`, `>=`) use
lexicographic byte order.

### String cast ✅

```rex
str a = str(42)        // "42"
str b = str(3.14)      // "3.14"
str c = str(true)      // "true"
```

> **Parsing strings to numbers uses cast functions:** `int("42")`, `float("3.14")` — not method calls.

---

### `str` method reference

#### Core ✅

| Method | Returns | Notes |
|---|---|---|
| `.len()` | `int` | Byte count (not codepoint count) |
| `.upper()` | `str` | New uppercase copy (ASCII) |
| `.lower()` | `str` | New lowercase copy (ASCII) |
| `.trim()` | `str` | New copy with leading/trailing whitespace stripped |
| `.trim_left()` | `str` | Strip leading whitespace only |
| `.trim_right()` | `str` | Strip trailing whitespace only |
| `.contains(sub)` | `bool` | `true` if substring `sub` found anywhere |
| `.starts_with(prefix)` | `bool` | `true` if string begins with `prefix` |
| `.ends_with(suffix)` | `bool` | `true` if string ends with `suffix` |
| `.replace(old, new)` | `str` | New copy with every occurrence of `old` replaced by `new` |
| `.slice(start, end)` | `str` | New substring; `end` exclusive; negative indices supported |
| `.split(sep)` | `seq[str]` | Split on separator string; empty string splits every char |

#### Access ✅

| Method | Returns | Notes |
|---|---|---|
| `.is_empty()` | `bool` | `true` when `len() == 0` |
| `.first()` | `char` | First character; runtime error if empty |
| `.last()` | `char` | Last character; runtime error if empty |
| `.char_at(i)` | `char` | Same as `s[i]`; negative indices supported |
| `.byte_at(i)` | `byte` | Raw byte value at index; negative indices supported |

#### Search ✅

| Method | Returns | Notes |
|---|---|---|
| `.index_of(sub)` | `int` | Index of first occurrence of `sub`; `-1` if not found |
| `.last_index_of(sub)` | `int` | Index of last occurrence; `-1` if not found |
| `.find(fn)` | `char` | First char where `fn(char) -> bool`; runtime error if none |
| `.find_index(fn)` | `int` | Index of first char matching predicate; `-1` if none |

#### Count ✅

| Method | Returns | Notes |
|---|---|---|
| `.count(sub)` | `int` | Count of non-overlapping occurrences of substring `sub` |
| `.count(fn)` | `int` | Count of chars matching `fn(char) -> bool` |

#### Predicates ✅

| Method | Returns | Notes |
|---|---|---|
| `.all(fn)` | `bool` | `true` if every char satisfies `fn(char) -> bool` |
| `.any(fn)` | `bool` | `true` if at least one char satisfies `fn(char) -> bool` |
| `.none(fn)` | `bool` | `true` if no char satisfies `fn(char) -> bool` |

#### Transformation ✅

| Method | Returns | Notes |
|---|---|---|
| `.reverse()` | `str` | New byte-reversed string |
| `.repeat(n)` | `str` | New string repeated `n` times |
| `.pad_left(n, char)` | `str` | Left-pad with `char` until total length is `n` |
| `.pad_right(n, char)` | `str` | Right-pad with `char` until total length is `n` |
| `.center(n, char)` | `str` | Center in width `n` with `char` on both sides |
| `.strip_prefix(prefix)` | `str` | Remove `prefix` if present; unchanged otherwise |
| `.strip_suffix(suffix)` | `str` | Remove `suffix` if present; unchanged otherwise |
| `.replace_first(old, new)` | `str` | Replace only the first occurrence of `old` |

#### Splitting and joining ✅

| Method | Returns | Notes |
|---|---|---|
| `.lines()` | `seq[str]` | Split on `\n`; trailing newline produces no empty final element |
| `.words()` | `seq[str]` | Split on whitespace runs; leading/trailing whitespace ignored |
| `.join(parts)` | `str` | Use self as separator to join `seq[str]` — e.g., `", ".join(names)` |

#### Collection views ✅

| Method | Returns | Notes |
|---|---|---|
| `.chars()` | `seq[char]` | All characters as a sequence |
| `.bytes()` | `seq[byte]` | All raw UTF-8 bytes as a sequence |

---

### Examples

```rex
str s = "  Hello, World!  "

// core
output(s.trim())                              // "Hello, World!"
output(s.trim().lower())                      // "hello, world!"
output(s.trim().replace("World", "Rex"))      // "Hello, Rex!"
output(s.trim().starts_with("Hello"))         // true
output(s.trim().ends_with("!"))               // true

// search
str name = "mississippi"
output(name.index_of("ss"))                   // 2
output(name.last_index_of("ss"))              // 5
output(name.count("ss"))                      // 2
output(name.find_index(fn(char c) -> bool: c == 'p'))  // 8

// predicates
str digits = "12345"
output(digits.all(fn(char c) -> bool: c >= '0' and c <= '9'))  // true
output(digits.any(fn(char c) -> bool: c == '3'))               // true
output(digits.none(fn(char c) -> bool: c == 'a'))              // true

// transformation
output("abc".repeat(3))                       // "abcabcabc"
output("abc" * 3)                             // "abcabcabc"
output("hi".pad_left(6, ' '))                // "    hi"
output("hi".pad_right(6, '-'))               // "hi----"
output("hi".center(6, '*'))                  // "**hi**"
output("  hello".strip_prefix("  "))         // "hello"
output("hello!".strip_suffix("!"))           // "hello"
output("Hello World".reverse())              // "dlroW olleH"

// splitting and joining
seq[str] lines = "one\ntwo\nthree".lines()   // ["one", "two", "three"]
seq[str] words = "  foo  bar  baz  ".words() // ["foo", "bar", "baz"]
seq[str] names = ["alice", "bob", "carol"]
output(", ".join(names))                      // "alice, bob, carol"
output("\n".join(names))                      // one per line

// collection views
seq[char] cs = "Rex".chars()                 // ['R', 'e', 'x']
seq[byte] bs = "Hi".bytes()                  // [72, 105]

// chaining
str clean = "  {user_input}  ".trim().lower().strip_suffix("!")
```

---

## `char` Type ✅

A single UTF-8 byte. Declared with single quotes. Backed by an unsigned 8-bit
value (`byte`) but printed and compared as a character.

```rex
char c = 'R'
output(c)                // R

char first = s[0]       // index into a str

if first == 'h':
    output("starts with h")
```

Casting between `char` and `int`:
```rex
int code
:code = int(c)          // ASCII/UTF-8 code point

char back
:back = char(65)        // 'A'
```

---

## `byte` Type ✅

Raw unsigned 8-bit value. Used for binary data, I/O buffers, and direct memory
manipulation. No display semantics — `output` prints the numeric value.

```rex
byte b = 0xFF
byte mask = 0b10101010

byte x
:x = b & mask
output(x)                // prints: 170
```

---

## Float / Math

### Basic arithmetic ✅
```rex
float x = 2.5
float y = 1.5
float z
:z = x + y
:z = x * y
output(z)
```

### `float` method reference ✅

| Method | Returns | Notes |
|---|---|---|
| `.ceil()` | `int` | Round up |
| `.floor()` | `int` | Round down |
| `.round()` | `int` | Round to nearest |
| `.fract()` | `float` | Fractional part only |
| `.abs()` | `float` | Absolute value |
| `.min(other)` | `float` | Smaller of two |
| `.max(other)` | `float` | Larger of two |

> **Type conversions use cast functions, not methods.** Use `str(f)`, `int(f)` — not `.str()` or `.int()`.

```rex
float f = 3.7
output(f.ceil())     // 4
output(f.floor())    // 3
output(f.round())    // 4
output(f.fract())    // 0.7
output(f.abs())      // 3.7

float a = 2.5
float b = 4.0
output(a.min(b))     // 2.5
output(a.max(b))     // 4.0
output(str(a))       // "2.5" — cast function, not method
```

### `int` method reference ✅

| Method | Returns | Notes |
|---|---|---|
| `.abs()` | `int` | Absolute value |
| `.min(other)` | `int` | Smaller of two |
| `.max(other)` | `int` | Larger of two |

> **Type conversions use cast functions, not methods.** Use `str(n)`, `float(n)` — not `.str()` or `.float()`.

```rex
int n = -5
output(n.abs())      // 5
output(n.min(0))     // -5
output(n.max(0))     // 0
output(str(n))       // "-5" — cast function
output(float(n))     // -5.0 — cast function
```

---

## Complex Numbers — Deprecated in Core

`complex` has been moved out of the Rex core type system. It will be available
as a standard library import in a future release. The type and its operations
(`real`, `imag`, `conj`) continue to function in V0.1 but should not be relied
on in new code.

---

## Output ✅ / ✅

### `output` — print with newline ✅

Print one expression followed by a newline. Rex auto-dispatches to the correct
printer based on the value's declared type.

```rex
output(42)
output(x)
output("hello")
output(flag)        // bool: true / false / unknown
output(pi)          // float: 3.14159...
output(c)           // char: prints the character glyph
output(b)           // byte: prints the numeric value (0–255)
```

`output` takes **one expression**. For multiple values on one line use string
interpolation or `show` chains — there is no `output(a, b, c)` form.

### Collection output format

Collections print using their literal syntax, making output readable and
round-trippable:

```rex
seq[int] nums = [1, 2, 3]
output(nums)          // [1, 2, 3]

dict[int] scores = {"alice": 95, "bob": 87}
output(scores)        // {"alice": 95, "bob": 87}

arr[float, 3] v = [1.0, 0.0, 0.0]
output(v)             // [1.0, 0.0, 0.0]
```

Nested collections follow the same rule recursively:
```rex
seq[seq[int]] matrix
output(matrix)        // [[1, 2], [3, 4]]
```

---

### String interpolation — `{expr}` ✅

Any string literal embeds expressions inside `{ }`. No prefix needed — all Rex
strings support interpolation. The expression is evaluated and converted to its
string representation at runtime.

```rex
output("x is {x} and y is {y}")
output("result: {a + b}")
output("fib(10) = {@fib(10)}")       // @ still marks protocol calls inside {}
output("name: {name}, age: {age}")
output("half of {n} is {n / 2}")
```

**Rule:** `{` opens an interpolation block. Any valid Rex expression is allowed
inside — arithmetic, protocol calls, casts, boolean ops. `}` closes it.
A literal `{` is written `{{`.

```rex
output("{{not interpolated}}")    // {not interpolated}
output("{x * x} squared")         // 25 squared  (if x == 5)
```

---

### Format specifiers — `{expr:spec}` ✅

A `:` inside an interpolation block activates format mode. The specifier
controls width, precision, and base representation.

```
{val:.Nf}   — float with N decimal places
{val:Nd}    — integer with minimum width N (right-aligned, space-padded)
{val:0Nd}   — integer with minimum width N (zero-padded)
{val:x}     — hex lowercase
{val:X}     — hex uppercase
{val:b}     — binary
{val:o}     — octal
{val:Ns}    — string with minimum width N (right-padded with spaces)
```

```rex
float pi = 3.14159
output("pi = {pi:.2f}")         // pi = 3.14
output("pi = {pi:.4f}")         // pi = 3.1416

int n = 255
output("{n:x}")                 // ff
output("{n:X}")                 // FF
output("{n:b}")                 // 11111111
output("{n:08b}")               // 11111111  (8 wide, zero-padded)
output("{n:10d}")               // '       255' (10 wide, space-padded)

str name = "Rex"
output("{name:10s}")            // 'Rex       ' (10 wide, right-padded)
```

Specifiers compose with expressions:
```rex
output("avg: {total / count:.1f}")
output("hex addr: {addr:x}")
```

---

### `fmt` — format to string ✅

Same interpolation and format-specifier syntax as `output`, but produces a
`str` value instead of printing. Use when you need a formatted string for
further processing.

```rex
str label = fmt("score: {score:.1f} / 100")
str hex_addr = fmt("0x{addr:X}")
str report = fmt("{name}: {val:8.2f}")
output(report)
```

`fmt` accepts exactly one string expression — the template. Any `{expr}` or
`{expr:spec}` inside it is evaluated at the call site.

---

### `show` — print without newline ✅

Like `output` but no trailing newline. Use to build a line incrementally, then
land the newline with a final `output`.

```rex
show("Loading")
show(".")
show(".")
show(".")
output("done")       // prints: Loading...done
```

`show` accepts the same expression types and format specifiers as `output`:
```rex
show("{progress:.0f}%  \r")    // overwrite the current line (carriage return)
```

---

### `flush()` — explicit stdout drain ✅

Drain the stdout buffer immediately. Normally stdout is flushed on newline
(`output`) or program exit. Use `flush()` after a `show` chain when you need
output to appear before a blocking operation.

```rex
show("Connecting...")
flush()               // ensure "Connecting..." is visible before the syscall blocks
@connect()
output("done")
```

---

### `debug` — typed diagnostic output to stderr ✅

Print `type: value` to stderr. Never pollutes stdout. Intended for development
and diagnostic use — strip before release.

```rex
int x = 42
debug(x)             // stderr: int: 42

seq[int] nums = [1, 2, 3]
debug(nums)          // stderr: seq[int]: [1, 2, 3]

dict[str] d = {"a": "b"}
debug(d)             // stderr: dict[str]: {"a": "b"}
```

`debug` shows both the declared type and the runtime value in one line.

---

### `write` — raw bytes to stdout ✅

Write a `seq[byte]` or `arr[byte, N]` directly to stdout with no conversion,
no newline, and no encoding. Use for binary protocols and file content.

```rex
seq[byte] buf = [0x48, 0x65, 0x6C, 0x6C, 0x6F]
write(buf)           // writes raw bytes: Hello
```

---

### Complete I/O keyword reference

| Keyword | Destination | Newline | Format | Exits? |
|---|---|---|---|---|
| `output(x)` | stdout | ✅ yes | type-dispatched | no |
| `show(x)` | stdout | ✗ no | type-dispatched | no |
| `write(buf)` | stdout | ✗ no | raw bytes only | no |
| `flush()` | stdout | — | — | no |
| `debug(x)` | stderr | ✅ yes | `type: value` | no |
| `warn("msg")` | stderr | ✅ yes | string only | no |
| `err("msg")` | stderr | ✅ yes | string only | yes — code 1 |
| `input("prompt")` | stdin (read) | — | returns `str` | no |

---

## I/O ✅ / ✅

### `input` — read from stdin ✅

Prints a prompt (no trailing newline — cursor stays inline), reads until `\n`,
returns a `str`.

```rex
str name = input("Enter your name: ")
output("Hello, {name}!")

int age = int(input("Enter your age: "))
output("You are {age} years old.")
```

### File I/O ✅

File reading and writing are planned as a standard library (`use file`). The
design uses explicit open/close handles with a method API:

```rex
use file:
    file :f = open("data.txt", "r")
    str contents = f.read()
    f.close()

use file:
    file :f = open("out.txt", "w")
    f.write("hello\n")
    f.writeln("world")
    f.close()
```

Modes: `"r"` (read), `"w"` (write/truncate), `"a"` (append), `"rb"` / `"wb"`
(binary). File handles respect the active `use mm:` context for internal buffers.

---

## Error Handling ✅ / ✅

### `err` — fatal error to stderr ✅
Emit a message to stderr and halt with exit code 1.
```rex
err("something went wrong")
err("expected positive value, got {x}")    // interpolation works here too
```

### `warn` — non-fatal warning to stderr ✅
Like `err` but does **not** exit. Use for recoverable conditions or diagnostic
logging that shouldn't stop the program.
```rex
warn("cache miss — falling back to disk")
warn("retry {attempt} of 3")
```

### The complete stderr/stdout picture

| Keyword | Destination | Newline | Exits? |
|---|---|---|---|
| `output(x)` | stdout | ✅ yes | no |
| `show(x)` | stdout | ✗ no | no |
| `warn("msg")` | stderr | ✅ yes | no |
| `err("msg")` | stderr | ✅ yes | yes — code 1 |
| `input("prompt")` | stdin (read) | — | no |

---

## Structured Error Handling — `try` / `except` / `finally` ✅

Rex uses `try/except/finally` for recoverable errors. Unlike Python, Rex has no
exception class hierarchy — every error is a message string from `err`. So `except`
is always unconditional or captures the message as a `str`. `warn` is unaffected
by `try` — only `err` is intercepted.

### Basic form

```rex
try:
    str data = @read_file("config.txt")
    output("loaded: {data}")
except:
    warn("file not found, using defaults")
finally:
    output("attempt complete")
```

- **`try:`** — run this block
- **`except:`** — runs if `err` was called inside `try` (instead of halting)
- **`finally:`** — always runs, whether or not an error occurred
- `except` and `finally` are both optional independently

### Capturing the error message

`except` can bind the message string to a name:

```rex
try:
    int n = int(input "Enter a number: ")
    output("you entered {n}")
except msg:
    output("invalid input: {msg}")
    :n = 0
```

`msg` is automatically `str`. It is whatever string was passed to `err`.

### `try` / `finally` without `except`

Use when you need guaranteed cleanup but don't intend to recover:

```rex
try:
    @open_connection()
    @do_work()
finally:
    @close_connection()    // always runs, even if err fires
```

### Nested `try` blocks

Inner `try` catches first. Calling `err` inside `except` propagates to the
next outer `try`.

```rex
try:
    try:
        str data = @load_primary()
    except:
        str data = @load_backup()    // fallback attempt
    @process(data)
except msg:
    err("completely failed: {msg}")   // re-raise as fatal
```

### `warn` passes through

`warn` is non-fatal and is never intercepted by `except`. It behaves identically
inside and outside `try` blocks.

### When to use what

| Situation | Tool |
|---|---|
| Unrecoverable bug | `err("msg")` with no `try` |
| Expected failure, can recover | `try / except` |
| Guaranteed cleanup | `try / finally` |
| Non-fatal log | `warn("msg")` |

---

## Memory Allocator Contexts

All memory management is **block-scoped**. The chosen strategy is active for the
duration of the indented body and reverts to the enclosing strategy on exit.
`mm` (allocator) and `gc` (collector) are independent axes — each can be used
alone or combined in a single `use` block.

### Context Allocator — Design Intent ✅

Rex uses an **implicit context allocator** model. The current `use mm:` block
sets a thread-local allocator context. Every allocation that happens within that
block — including allocations inside protocols called from within the block —
uses that context automatically. No explicit allocator parameter is needed.

```rex
use mm arena:
    seq[int] nums       // arena-allocated
    nums.push(10)
    @build_graph(nums)  // any allocs inside build_graph also use the arena
// entire arena freed here in one shot
```

This is the key idea: **the allocator context flows invisibly through the call
stack**. The compiler stores the current allocator in a reserved thread-local
slot (a fast register-resident pointer). Any allocation instruction routes
through it automatically.

**Nested overrides** are supported — inner blocks shadow the outer context:
```rex
use mm arena:
    seq[int] outer      // arena

    use mm pool[64]:    // inner block switches to pool
        seq[int] inner  // pool-allocated
        @tight_loop()   // pool context flows through here
    // pool freed; back to arena context

    seq[int] back       // arena again
// arena freed
```

**Why this matters:** you can write protocols that allocate freely — `.push()`,
`.split()`, `.map()` — without those protocols needing to know or care what
allocator they're running under. The caller decides. This eliminates the need
to thread allocator parameters through every signature.

**Contrast with explicit-parameter style (Zig):**
```
// Zig — allocator passed explicitly everywhere
fn build(allocator: std.mem.Allocator) !ArrayList { ... }
```
```rex
// Rex — allocator set at call site via context
use mm arena:
    @build()   // no parameter; context handles it
```

---

### Built-in Allocators — `use mm <mode>:` ✅ / ✅

Five allocator strategies are available:

| Mode | Strategy | Free trigger | Status |
|------|----------|-------------|--------|
| `arena` | Bump-pointer; all allocs from one contiguous block | Bulk-free entire block at scope exit | ✅ |
| `pool` | Fixed-size block reuse; recycled free-list | Per-block or bulk at scope exit | ✅ |
| `stack` | Sub-allocates directly from the hardware stack | Automatic — zero runtime cost | ✅ |
| `heap` | Standard independent alloc/free | Each object freed individually | ✅ |
| `static` | Persistent allocation; survives all scope exits | Never freed; program lifetime | ✅ |

```rex
use mm arena:
    seq[int] buf        // bump-allocated; entire region freed at dedent
    buf.push(1)
    buf.push(2)

use mm pool[64]:
    dict[int] cache     // pool-allocated; fixed-size 64-byte blocks recycled
    :cache["x"] = 7

use mm stack:
    seq[int] tmp        // lives on the hardware stack; zero allocator overhead

use mm heap:
    seq[int] log        // each push/pop is a standalone malloc/free

use mm static:
    dict[int] config    // config survives forever; never collected
    :config["debug"] = 1
```

---

### Built-in Garbage Collectors — `use gc <mode>:` ✅

Five collection strategies are available:

| Mode | Strategy | Pause behaviour |
|------|----------|----------------|
| `sweep` | Mark-and-sweep; walk var_table, free unreachable | Stop-the-world at scope exit |
| `ref` | Reference counting; decrement on overwrite/exit | Per-assignment, no pause |
| `gen` | Generational; young objects collected often, old rarely | Short frequent pauses |
| `inc` | Incremental sweep; work spread across small slices | Many tiny pauses, no long ones |
| `region` | Region-based; all objects in scope freed together | One bulk-free at scope exit |

```rex
use gc sweep:
    seq items           // collected by mark-and-sweep when block exits

use gc ref:
    dict counts         // reference-counted; freed when count reaches zero

use gc gen:
    seq events          // generational; short-lived objects collected first

use gc inc:
    seq stream          // incremental; no long pauses during collection

use gc region:
    seq batch           // entire region freed as one unit at scope exit
```

---

### Combined — `use mm <mode> gc <mode>:` ✅

Allocator and collector can be paired in a single block:

```rex
use mm pool gc ref:
    seq buf
    dict index

use mm arena gc region:
    seq scratch
    push scratch 42

use mm heap gc sweep:
    dict live_objects
```

The allocator controls **how** memory is handed out; the collector controls **when**
unreachable memory is reclaimed. Not all combinations are meaningful — `mm static`
with any GC is valid (GC simply never fires since nothing is freed). `mm stack`
with `gc ref` is redundant (stack already frees on exit) but not an error.

---

### User-Defined Allocators — `mm <name>:` ✅

Define a custom allocator with `mm`:

```rex
mm myalloc:
    alloc(size):
        // size is in rax at entry
        // return heap pointer in rax
        // custom logic here
        ...
    free(ptr):
        // ptr is in rax at entry
        // release the block
        ...
    reset:
        // called at scope exit to bulk-free everything
        ...
```

Use it identically to a built-in mode:

```rex
use mm myalloc:
    seq data
    push data 99
```

Pair with any GC:

```rex
use mm myalloc gc sweep:
    dict live
```

---

### User-Defined Garbage Collectors — `gc <name>:` ✅

Define a custom collector with `gc`:

```rex
gc mygc:
    mark(ptr):
        // called for each reachable root in var_table
        // mark ptr and all objects reachable from it
        ...
    collect:
        // called at scope exit
        // sweep all unmarked objects; reset mark bits
        ...
    trigger:
        // optional: called after every N allocations
        // return true (1) to run a collection cycle early
        ...
```

Use it identically to a built-in mode:

```rex
use gc mygc:
    seq managed

use mm pool gc mygc:
    dict tracked
```

---

### Custom Keyword Registration — `use keyword <word> as mm <name>:` ✅

A user-defined allocator or collector can be bound to a **custom keyword**, making
it indistinguishable from a built-in mode at the call site:

```rex
use keyword slab as mm myalloc
use keyword trace as gc mygc
```

After registration, the new keywords work everywhere:

```rex
use mm slab:
    seq items

use gc trace:
    dict objects

use mm slab gc trace:
    seq hot
```

Custom keywords are resolved at parse time. A keyword that shadows a built-in
(`arena`, `pool`, `stack`, `heap`, `static`, `sweep`, `ref`, `gen`, `inc`, `region`)
is a compile-time error.

---

### Named Contexts — `ctx` ✅

A named context gives explicit, user-managed control over a slab's lifetime.
Use it when you need to reuse a slab across iterations or share it across calls.

```rex
ctx scratch = arena(8192)         // one mmap, 8 KB slab

for k in 0..1000000:
    use mm scratch:
        seq[int] tmp              // allocates from scratch
        tmp.push(k)
        @process(tmp)
    reset scratch                 // O(1) bump rewind — no syscall

free scratch                      // munmap — releases slab to OS
```

**`reset name`** — rewinds the bump pointer to the base. All previously allocated
objects become unreachable (no per-object free). The slab memory is reused.
Zero syscall cost.

**`free name`** — releases the slab back to the OS (`munmap`). The name becomes
invalid after this point.

**Contrast with scoped `use mm arena:`** — scoped form does one mmap on entry
and one munmap on exit, every time the block is entered. Use named contexts when
the block is inside a hot loop and the syscall pair would dominate runtime.

---

### Resolved Design Decisions ✅

These decisions are final and govern the implementation of the `mm` system.

#### Arena grow behavior
When a `seq` inside `use mm arena:` or a named arena context needs to grow
(push beyond capacity), the allocator **bump-allocates a new larger buffer**
and leaves the old one as dead space in the slab until the context exits or
is reset. No per-object reclaim happens inside an arena.

**Implication:** size the arena for peak working set, not initial state. If a
seq grows from 8 → 16 → 32 → 64 elements, all four buffers consume arena space
simultaneously. Pre-sizing avoids this:

```rex
use mm arena(16384):
    seq[int] tmp = 1024     // pre-allocate 1024-element capacity — no grows
    tmp.push(1)
    tmp.push(2)
```

**Arena overflow** is a runtime panic (`err("arena overflow")` + exit 1). There
is no silent fallback to heap — the user sized the arena incorrectly and must
know about it.

#### `pool[N]` — N is block size in bytes
`pool[N]` means every allocation from this pool is exactly `N` bytes.
Requesting more than `N` bytes from a pool is a runtime error. The total number
of blocks grows on demand — a new slab is mmap'd when the free list is empty.

```rex
use mm pool[64]:
    dict[int] cache     // each dict entry is exactly 64 bytes
```

`use mm pool:` without a size is a **compile-time error** — no sensible default
exists.

#### `use mm arena:` inside a for-loop
`use mm arena:` creates a fresh slab every time the block is entered and
releases it on exit. Inside a loop, that is one mmap + one munmap per iteration.
This is correct for the "process a batch, discard, repeat" pattern.

For the "create once, reset each iteration" pattern, use a **named context**
declared outside the loop (see above).

#### Active context storage
Rex is single-threaded. The current allocator context pointer is stored at a
fixed BSS address (`ALLOC_CTX_PTR = 0x447000`). On `use mm:` entry the compiler
saves the previous pointer and installs the new one; on exit it restores the
previous. Protocol calls inside the block see the correct pointer automatically
— no hidden arguments, no register pressure, no calling convention changes.

When no `use mm:` block is active, `ALLOC_CTX_PTR` points to the default heap
context, preserving existing behaviour for all code that does not opt in.

---

## Memory / Ownership ✅

### `own` / `move`
Transfer ownership of a collection, bypassing reference count overhead.
```rex
own b = move a      // a is no longer valid after this
```

### `free`
Manually recycle an allocation block within a pool/arena before scope end.
```rex
free buf
```

### `align`
Constrain a variable's storage to a specific byte alignment (e.g. CPU cache line).
```rex
align 64
seq hot_data
```

### `const`
Compile-time parser constraint — stronger than immutable declaration; blocks any mutation path at parse time.
```rex
const int LIMIT = 128
```

### `volatile`
Disable register caching for a variable — all reads go directly to memory.
```rex
volatile int tick
```

---

## Diagnostics ✅

### `unreachable`
Asserts a code path cannot be reached. Emits `ud2` — illegal instruction trap.
```rex
when code:
    is 1:
        output("one")
    else:
        unreachable
```

### `assert`
Runtime guard. Halts with `rt_err_blob` if the expression is false.
```rex
assert x > 0
assert items.len() > 0
```

---

## Concurrency / Vectorization ✅

### `blast` / `pipe`
Vectorized iteration unrolling. Maps to `movntdq` / `movdqa` (bypasses CPU cache).
```rex
blast item in items:
    :item = item * 2

pipe result from source into sink:
    output(result)
```

---

## `err` with `bool unknown` ✅

`unknown` is a tri-state boolean backed by hardware entropy (`rdrand`). Use it to represent values that are genuinely indeterminate at compile time:
```rex
bool coin
:coin = unknown
output(coin)           // prints: true, false, or unknown
```

---

## Comments

### Line comments ✅
`//` begins a line comment. Everything after it on that line is ignored.
```rex
int x = 5    // this is a constant
:x = 10      // mutation — x is now mutable
```

### Block comments ✅
`/* */` spans multiple lines. Useful for temporarily disabling code or long notes.
```rex
/*
   This entire block is ignored by the compiler.
   Useful for multi-line notes or disabling code.
*/
int y = 42
```

### Doc comments ✅
`///` attaches documentation to the next `prot` definition. Tools and future
language servers read these to generate documentation.
```rex
/// Computes the nth Fibonacci number.
/// Uses memoization for O(n) performance.
/// @param n — must be non-negative
/// @returns the nth Fibonacci number
#memo
prot fib(int n) -> int:
    if n <= 1:
        return n
    return @fib(n-1) + @fib(n-2)
```

---

## Tuples — Standalone Type ✅

Tuples are fixed-size, ordered, heterogeneous collections. They are immutable
by default. Declared with `tup[T, T, ...]` and initialised with `(val, val, ...)`.

### Declaration
```rex
tup[int, str, float] record = (1, "Alice", 9.5)
tup[bool, int] status = (true, 200)
```

### Index access
Use `.0`, `.1`, `.2` etc. to read fields positionally.
```rex
output(record.0)    // 1
output(record.1)    // "Alice"
output(record.2)    // 9.5
```

### Destructuring
Unpack all fields into named variables in one line.
```rex
int id, str name, float score = record
output("id={id} name={name} score={score}")
```

### Partial destructuring with `_`
Use `_` to skip fields you don't need.
```rex
int id, _, float score = record    // skip the name
```

### Tuples as protocol return values
The most common use. Protocols can return multiple typed values cleanly.
```rex
prot divmod(int a, int b) -> (int, int):
    return a / b, a % b

int q, int r = @divmod(17, 5)
output("quotient={q} remainder={r}")
```

### Tuple method reference

| Method | Returns | Notes |
|---|---|---|
| `.len()` | `int` | Always fixed — known at compile time |

> Use `str(t)` to get a string representation — cast function, not a method.

---

## Lambdas / Anonymous Protocols — `fn` ✅

Anonymous protocols are written with `fn`. They can be stored in variables,
passed as arguments, and used with `.map()`, `.filter()`, `.each()`, and
any protocol that accepts a protocol-typed parameter.

### Syntax
```rex
fn(int x) -> int: x * 2              // single-expression body
fn(int x, int y) -> int: x + y       // two params
fn(str s) -> bool: s.len() > 3       // bool return
fn(int x):                            // no return value (side-effect only)
    output("item: {x}")
```

### Multi-line body
```rex
fn(int x) -> int:
    int doubled = x * 2
    return doubled + 1
```

### Storing in a variable
The variable type is written as `prot(params -> return)`:
```rex
prot(int -> int) double = fn(int x) -> int: x * 2
prot(int, int -> int) add = fn(int a, int b) -> int: a + b
prot(str -> bool) long = fn(str s) -> bool: s.len() > 5

int result = @double(7)     // 14
output(result)
```

### Passing to higher-order protocols
```rex
seq[int] nums
nums.push(1)
nums.push(2)
nums.push(3)
nums.push(4)
nums.push(5)

seq[int] evens = nums.filter(fn(int x) -> bool: x % 2 == 0)
seq[int] doubled = nums.map(fn(int x) -> int: x * 2)
nums.each(fn(int x): output("{x}"))

// Chaining
seq[int] result = nums
    .filter(fn(int x) -> bool: x > 2)
    .map(fn(int x) -> int: x * 10)
```

### Writing protocols that accept lambdas
Declare the parameter type as `prot(T -> U)`:
```rex
prot apply(seq[int] s, prot(int -> int) transform) -> seq[int]:
    return s.map(transform)

seq[int] result = @apply(nums, fn(int x) -> int: x * x)
```

---

## Imports & Modules ✅

Rex modules map to `.rex` source files. Import a module by name (no extension).
The compiler searches the same directory first, then the standard library path.

### Import a whole module
```rex
import math
import utils

:x = @math.sqrt(16.0)        // module-qualified call
:s = @utils.read_file("x.txt")
```

### Import specific identifiers
```rex
from math import sqrt, floor, ceil
from utils import @read_file, @write_file

:x = @sqrt(16.0)             // directly available, no prefix
:data = @read_file("x.txt")
```

### Import with alias
```rex
from math import sqrt as sq

:x = @sq(25.0)
```

### Standard library modules (planned)

| Module | Contents |
|---|---|
| `math` | `sqrt`, `pow`, `log`, `sin`, `cos`, `pi`, `e` |
| `str_utils` | `format`, `pad`, `repeat`, `encode`, `decode` |
| `io` | `read_file`, `write_file`, `read_lines`, `append_file` |
| `os` | `args`, `env`, `exit`, `cwd`, `time` |
| `complex` | `complex` type, `real`, `imag`, `conj`, `magnitude` |
| `net` | Basic TCP/UDP socket primitives |
| `json` | `parse`, `stringify` |

### Module rules
- Each `.rex` file is one module. Module name = filename without extension.
- Protocols defined at the top level of a file are its public exports.
- No explicit `export` keyword — everything top-level is public.
- Circular imports are a compile-time error.
