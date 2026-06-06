# Rex V0.1 — Language Syntax Reference

**Status markers used in this document:**
- ✅ Implemented and tested
- 🔧 Lexed — token exists, parser/codegen pending
- 📋 Planned — Stage 9 / Stage 10 roadmap

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

### Type inference 📋
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

### Unimplemented types 📋
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
output coin             // prints: true, false, or unknown

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
    output "both positive"

if a == 1 or b == 1:
    output "at least one"
```

### `not` operator 📋

Boolean inversion. Will map to `xor rax, 1` for `bool` operands and `not rax`
for integer bitwise inversion. Not yet implemented in codegen.

```rex
bool flag = true

if not flag:
    output "off"
```

**Planned emission:**
- `bool` operand: `xor rax, 1` (flips 0↔1)
- `int` operand: `not rax` (bitwise complement)

### Comparison ✅
All six operators are supported in `if`, `elif`, and `while` conditions:
```
==   !=   <   >   <=   >=
```

### Identity — `is` / `is not` 📋

Semantic identity check. Evaluates to a hardware `cmp` followed by `sete`/`setne`.
Distinguished from `==` / `!=` in that it will also support runtime type comparison
and null/sentinel checks without triggering arithmetic promotion.

```rex
if x is 0:
    output "zero"

if ptr is not null:
    output "valid"
```

**Planned semantics:**
- `a is b` → `cmp rax, rbx; sete al; movzx rax, al` → yields `1` (true) or `0` (false)
- `a is not b` → `cmp rax, rbx; setne al; movzx rax, al`
- `ptr is not null` → comparison against the integer `0` (null pointer sentinel)
- Result type: `bool`

Differs from `==` in that `is` will participate in the ownership/type-safety
system (Stage 10): `a is b` checks value identity without implying structural
equality for collection types.

### Membership — `in` 📋
Check whether a value is present in a `seq`, `dict`, or `str`.
```rex
if 5 in nums:
    output "found"

if "key" in d:
    output "exists"
```

### Pipeline — `->` 📋
Cascades the result of one expression into the next, routing through SysV ABI registers.
```rex
@compute(x) -> output
a + b -> @process()
```

### Syscall intercept — `$` 📋
Drop directly into kernel space via raw `syscall`. Parameters map to `rdi`, `rsi`, `rdx`, `r10`, `r8`, `r9`.
```rex
$(1, 1, "hello\n", 6)    // sys_write(stdout, buf, len)
$(60, 0)                  // sys_exit(0)
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

### Hash 📋
Direct SipHash-2-4 over a memory region. Returns a 64-bit hash in `rax`.
```rex
int h
:h = hash s
```

### Hardware flags 📋
Read CPU EFLAGS directly after arithmetic. Evaluate to `bool`.
```rex
bool c
:c = carry       // true if last op produced a carry

bool ov
:ov = overflow   // true if last op overflowed
```

### Flip / Rand 📋
`flip` inverts a bool via bitwise NOT. `rand` sources a hardware-entropy integer via `rdrand`.
```rex
bool b = true
flip b

int n
:n = rand
```

---

## Type Casting ✅ / 📋

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
output typeof x
```

---

## Protocols ✅

Define with `prot`. Parameters are **typed** (type-first, matching Rex's variable style).
Return a value with `return`. The return type is annotated with `->`.

### Basic definition

```rex
prot greet():
    output "Hello"

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
output result
```

### Multiple return values — tuples 📋

A protocol can return a tuple of values using `-> (T, T, ...)`. The caller
destructures with a matching declaration on the left side.

```rex
prot minmax(seq[int] s) -> (int, int):
    int lo = s[0]
    int hi = s[0]
    for i in 1..len(s):
        if s[i] < lo:
            :lo = s[i]
        if s[i] > hi:
            :hi = s[i]
    return lo, hi

int lo, int hi
:lo, :hi = @minmax(nums)
output lo
output hi
```

Tuple return values are positional. The types on the left side must match the
declared return tuple exactly — a mismatch is a compile-time error.

### Protocol decorators — `#` ✅

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
    err msg
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
    output "ten"
elif x == 5:
    output "five"
else:
    output "other"
```

All six comparison operators are supported: `==`, `!=`, `<`, `>`, `<=`, `>=`.

### `when` / `is` ✅
Switch-like routing. Each `is` case matches against the `when` expression.
```rex
int code = 2

when code:
    is 1:
        output "one"
    is 2:
        output "two"
    else:
        output "other"
```

### `match` 📋
Structural pattern matching. Dense integer ranges compile to O(1) jump tables.
```rex
match x:
    int:
        output "integer"
    float:
        output "float"
    str:
        output "string"
```

### `pass` ✅
Zero-byte semantic placeholder for empty blocks or unimplemented stubs.
```rex
prot todo():
    pass

if x == 0:
    pass
else:
    output x
```

---

## Loops

### For loop ✅
Range-based. Optional `step`. Both bounds accept full expressions (variables,
arithmetic, unary negation). The loop variable is implicitly mutable — the
loop syntax itself implies iteration; no `:` sigil is needed at the declaration.
```rex
for i in 0..10:
    output i

for i in 0..20 step 2:
    output i

for i in -5..5:
    output i
```

### While loop ✅
```rex
while true:
    output "Hello"
    stop
```

### `stop` ✅
Break out of the current (innermost) loop.
```rex
for i in 0..100:
    if i == 5:
        stop
    output i
```

### `stop N` 📋

Multi-level break. `stop N` breaks out of `N` nested loops at once.
`stop 1` is identical to bare `stop` (break the innermost loop).

```rex
for i in 0..10:
    for j in 0..10:
        if i == j:
            stop 2    // break both loops simultaneously
    output i          // never reached if i == j fires
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

### Loop `else:` 📋

An `else:` block attached directly to a `for` or `while` loop executes **only if**
the loop completes naturally — i.e., it was never interrupted by a `stop`.

```rex
for i in 0..10:
    if i == 5:
        stop
else:
    output "completed without stop"
```

```rex
int target = 7
for i in 0..10:
    if i == target:
        stop
else:
    output "target not found in range"
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

### `repeat N:` 📋

Counted loop with no explicit counter variable. Emits a single hardware
`dec` + `jnz` loop — faster than a `for` loop when the iteration index is
not needed inside the body.

```rex
repeat 8:
    output "tick"
```

```rex
int :sum = 0
repeat 100:
    :sum = sum + 1
output sum
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

### `each` 🔧
Cache-aligned iterator for sequential collection sweeping. Token is lexed; parser pending.
```rex
each item in items:
    output item
```

---

## Sequences ✅ / 📋

Sequences are typed. The element type is declared in brackets. Method-call
syntax is the primary API. Sequences grow automatically when capacity is exceeded.

```rex
seq[int] nums
nums.push(10)
nums.push(20)
nums.push(30)

output nums.len()       // 3
output nums.cap()       // allocated capacity
output nums.pop()       // 30 — LIFO pop
output nums[0]          // 10 — index access
```

### `seq[T]` method reference

| Method | Returns | Notes |
|---|---|---|
| `.push(val)` | — | Append to end; grows if needed |
| `.pop()` | `T` | Remove and return last element |
| `.get(i)` | `T` | Same as `s[i]`; index from 0 |
| `.set(i, val)` | — | Same as `:s[i] = val` |
| `.len()` | `int` | Current element count |
| `.cap()` | `int` | Allocated capacity |
| `.contains(val)` | `bool` | Linear scan for value |
| `.remove(i)` | — | Remove element at index; shifts remaining |
| `.sort()` | — | In-place ascending sort |
| `.reverse()` | — | In-place reversal |
| `.slice(start, end)` | `seq[T]` | New sub-sequence (non-mutating) |
| `.map(fn)` | `seq[U]` | Transform every element via lambda |
| `.filter(fn)` | `seq[T]` | Keep elements where `fn` returns `true` |
| `.each(fn)` | — | Call `fn` for every element (forEach) |
| `.clear()` | — | Remove all elements; keep allocation |

### Examples

```rex
seq[int] nums
nums.push(3)
nums.push(1)
nums.push(4)
nums.push(1)
nums.push(5)

nums.sort()                              // [1, 1, 3, 4, 5]
nums.reverse()                           // [5, 4, 3, 1, 1]
output nums.contains(4)                  // true

seq[int] big = nums.filter(fn(int x) -> bool: x > 2)
seq[int] doubled = nums.map(fn(int x) -> int: x * 2)
seq[int] part = nums.slice(1, 3)        // elements at index 1 and 2

nums.each(fn(int x): output "{x}")      // print each
output nums.len()
```

A compile-time error is raised when pushing a value whose type mismatches `T`.

---

## Dictionaries ✅ / 📋

Dictionaries are typed by value. Keys are always `str`. Method-call syntax
is the primary API.

```rex
dict[int] scores
scores.set("alice", 95)
scores.set("bob", 87)

output scores.get("alice")     // 95
output scores.has("carol")     // false
output scores.len()            // 2
```

Bracket syntax is also supported for get and set:
```rex
scores["alice"] = 95
output scores["alice"]
```

### `dict[T]` method reference

| Method | Returns | Notes |
|---|---|---|
| `.set(key, val)` | — | Insert or overwrite; same as `d[key] = val` |
| `.get(key)` | `T` | Retrieve value; same as `d[key]` |
| `.has(key)` | `bool` | Returns `true` if key exists |
| `.remove(key)` | — | Delete key-value pair |
| `.keys()` | `seq[str]` | All keys as a sequence |
| `.values()` | `seq[T]` | All values as a sequence |
| `.len()` | `int` | Number of entries |
| `.clear()` | — | Remove all entries; keep allocation |

### Examples

```rex
dict[str] labels
labels.set("en", "Hello")
labels.set("es", "Hola")
labels.set("fr", "Bonjour")

seq[str] langs = labels.keys()
langs.each(fn(str k): output "{k}: {labels.get(k)}")

labels.remove("fr")
output labels.len()    // 2
```

A compile-time error is raised when a value's type mismatches `T`.

---

## Strings ✅ / 📋

`str` is a heap-managed UTF-8 string. It shares the same header layout as `seq`:
`[capacity: 8 bytes][length: 8 bytes][data: variable bytes]`. String literals
are copied onto the heap at declaration.

### Declaration ✅
```rex
str s = "hello"
str t = "world"
```

### Output ✅
```rex
output s
```

### Length ✅
```rex
int n
:n = len s
output n
```

### Concatenation 📋
Produces a new heap-allocated string. The original strings are unchanged.
```rex
str result
:result = s + " " + t
output result           // "hello world"
```

### Indexing — returns `char` 📋
```rex
char c = s[0]
output c                // 'h'
```

### Comparison 📋
Content equality — not pointer equality.
```rex
if s == "hello":
    output "match"

if s != t:
    output "different"
```

### String cast 📋
Convert any value to its string representation.
```rex
str n
:n = str(42)
:n = str(3.14)
```

### `str` method reference 📋

| Method | Returns | Notes |
|---|---|---|
| `.len()` | `int` | Number of bytes |
| `.upper()` | `str` | New uppercase copy |
| `.lower()` | `str` | New lowercase copy |
| `.trim()` | `str` | New copy with leading/trailing whitespace removed |
| `.split(sep)` | `seq[str]` | Split by separator string |
| `.contains(sub)` | `bool` | True if substring found |
| `.starts_with(prefix)` | `bool` | True if string begins with prefix |
| `.ends_with(suffix)` | `bool` | True if string ends with suffix |
| `.replace(old, new)` | `str` | New copy with all occurrences replaced |
| `.slice(start, end)` | `str` | New substring from index start to end |

> **Parsing strings to numbers uses cast functions:** `int("42")`, `float("3.14")` — not `.to_int()` or `.to_float()`.

```rex
str s = "  Hello, World!  "
output s.trim()                       // "Hello, World!"
output s.trim().lower()               // "hello, world!"
output s.trim().contains("World")     // true
output s.trim().replace("World", "Rex") // "Hello, Rex!"
output s.trim().starts_with("Hello")  // true

seq[str] parts = "a,b,c".split(",")  // ["a", "b", "c"]
parts.each(fn(str p): output p)

str name = "Rex"
output "length: {name.len()}"        // length: 3
output name.upper()                  // REX
output name[0]                       // 'R'
output name.slice(0, 2)              // "Re"

int parsed = int("42")               // cast function — not ".to_int()"
float fp = float("3.14")             // cast function — not ".to_float()"
```

---

## `char` Type 📋

A single UTF-8 byte. Declared with single quotes. Backed by an unsigned 8-bit
value (`byte`) but printed and compared as a character.

```rex
char c = 'R'
output c                // R

char first = s[0]       // index into a str

if first == 'h':
    output "starts with h"
```

Casting between `char` and `int`:
```rex
int code
:code = int(c)          // ASCII/UTF-8 code point

char back
:back = char(65)        // 'A'
```

---

## `byte` Type 📋

Raw unsigned 8-bit value. Used for binary data, I/O buffers, and direct memory
manipulation. No display semantics — `output` prints the numeric value.

```rex
byte b = 0xFF
byte mask = 0b10101010

byte x
:x = b & mask
output x                // prints: 170
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
output z
```

### `float` method reference 📋

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
output f.ceil()     // 4
output f.floor()    // 3
output f.round()    // 4
output f.fract()    // 0.7
output f.abs()      // 3.7

float a = 2.5
float b = 4.0
output a.min(b)     // 2.5
output a.max(b)     // 4.0
output str(a)       // "2.5" — cast function, not method
```

### `int` method reference 📋

| Method | Returns | Notes |
|---|---|---|
| `.abs()` | `int` | Absolute value |
| `.min(other)` | `int` | Smaller of two |
| `.max(other)` | `int` | Larger of two |

> **Type conversions use cast functions, not methods.** Use `str(n)`, `float(n)` — not `.str()` or `.float()`.

```rex
int n = -5
output n.abs()      // 5
output n.min(0)     // -5
output n.max(0)     // 0
output str(n)       // "-5" — cast function
output float(n)     // -5.0 — cast function
```

---

## Complex Numbers — Deprecated in Core

`complex` has been moved out of the Rex core type system. It will be available
as a standard library import in a future release. The type and its operations
(`real`, `imag`, `conj`) continue to function in V0.1 but should not be relied
on in new code.

---

## Output ✅ / 📋

### `output` — print with newline ✅
Print any value followed by a newline. Rex auto-dispatches to the correct printer
based on the variable's declared type.
```rex
output 42
output x
output "hello"
output flag        // bool: prints true / false / unknown
output pi          // float
output c           // char: prints the character
output b           // byte: prints the numeric value
```

### `show` — print without newline 📋
Like `output` but no trailing newline. Use when building a line incrementally.
```rex
show "Loading"
show "..."
output "done"      // newline lands here — prints: Loading...done
```

### String interpolation — `{expr}` 📋
Any string literal can embed expressions inside `{ }`. No prefix needed — all Rex
strings support interpolation. The expression is evaluated and converted to its
string representation at runtime.

```rex
output "x is {x} and y is {y}"
output "result: {a + b}"
output "fib(10) = {@fib(10)}"       // @ still marks protocol calls inside {}
output "name: {name}, age: {age}"
output "half of {n} is {n / 2}"
```

**Rule:** `{` in a string literal opens an interpolation block. Any valid Rex
expression is allowed inside — arithmetic, protocol calls, casts, boolean ops.
`}` closes it. A literal `{` is written `{{`.

```rex
output "{{not interpolated}}"    // prints: {not interpolated}
output "{x * x} squared"         // prints: 25 squared  (if x == 5)
```

---

## I/O ✅ / 📋

### `input` — read from stdin 📋
Prints a prompt (no trailing newline — cursor stays inline), reads until `\n`,
returns a `str`.

```rex
str name = input "Enter your name: "
output "Hello, {name}!"

int age = int(input "Enter your age: ")   // cast after reading
output "You are {age} years old."
```

---

## Error Handling ✅ / 📋

### `err` — fatal error to stderr ✅
Emit a message to stderr and halt with exit code 1.
```rex
err "something went wrong"
err "expected positive value, got {x}"    // interpolation works here too
```

### `warn` — non-fatal warning to stderr 📋
Like `err` but does **not** exit. Use for recoverable conditions or diagnostic
logging that shouldn't stop the program.
```rex
warn "cache miss — falling back to disk"
warn "retry {attempt} of 3"
```

### The complete stderr/stdout picture

| Keyword | Destination | Newline | Exits? |
|---|---|---|---|
| `output x` | stdout | ✅ yes | no |
| `show x` | stdout | ✗ no | no |
| `warn "msg"` | stderr | ✅ yes | no |
| `err "msg"` | stderr | ✅ yes | yes — code 1 |
| `input "prompt"` | stdin (read) | — | no |

---

## Structured Error Handling — `try` / `except` / `finally` 📋

Rex uses `try/except/finally` for recoverable errors. Unlike Python, Rex has no
exception class hierarchy — every error is a message string from `err`. So `except`
is always unconditional or captures the message as a `str`. `warn` is unaffected
by `try` — only `err` is intercepted.

### Basic form

```rex
try:
    str data = @read_file("config.txt")
    output "loaded: {data}"
except:
    warn "file not found, using defaults"
finally:
    output "attempt complete"
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
    output "you entered {n}"
except msg:
    output "invalid input: {msg}"
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
    err "completely failed: {msg}"   // re-raise as fatal
```

### `warn` passes through

`warn` is non-fatal and is never intercepted by `except`. It behaves identically
inside and outside `try` blocks.

### When to use what

| Situation | Tool |
|---|---|
| Unrecoverable bug | `err "msg"` with no `try` |
| Expected failure, can recover | `try / except` |
| Guaranteed cleanup | `try / finally` |
| Non-fatal log | `warn "msg"` |

---

## Memory Allocator Contexts

All memory management is **block-scoped**. The chosen strategy is active for the
duration of the indented body and reverts to the enclosing strategy on exit.
`mm` (allocator) and `gc` (collector) are independent axes — each can be used
alone or combined in a single `use` block.

### Context Allocator — Design Intent 📋

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

### Built-in Allocators — `use mm <mode>:` ✅ / 📋

Five allocator strategies are available:

| Mode | Strategy | Free trigger | Status |
|------|----------|-------------|--------|
| `arena` | Bump-pointer; all allocs from one contiguous block | Bulk-free entire block at scope exit | ✅ |
| `pool` | Fixed-size block reuse; recycled free-list | Per-block or bulk at scope exit | ✅ |
| `stack` | Sub-allocates directly from the hardware stack | Automatic — zero runtime cost | 📋 |
| `heap` | Standard independent alloc/free | Each object freed individually | 📋 |
| `static` | Persistent allocation; survives all scope exits | Never freed; program lifetime | 📋 |

```rex
use mm arena:
    seq buf             // bump-allocated; entire region freed at dedent
    push buf 1
    push buf 2

use mm pool:
    dict cache          // pool-allocated; fixed-size blocks recycled
    cache["x"] = 7

use mm stack:
    seq tmp             // lives on the hardware stack; zero allocator overhead

use mm heap:
    seq log             // each push/pop is a standalone malloc/free

use mm static:
    dict config         // config survives forever; never collected
    config["debug"] = 1
```

---

### Built-in Garbage Collectors — `use gc <mode>:` 📋

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

### Combined — `use mm <mode> gc <mode>:` 📋

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

### User-Defined Allocators — `mm <name>:` 📋

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

### User-Defined Garbage Collectors — `gc <name>:` 📋

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

### Custom Keyword Registration — `use keyword <word> as mm <name>:` 📋

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

## Memory / Ownership 📋

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

## Diagnostics 📋

### `unreachable`
Asserts a code path cannot be reached. Emits `ud2` — illegal instruction trap.
```rex
when code:
    is 1:
        output "one"
    else:
        unreachable
```

### `assert`
Runtime guard. Halts with `rt_err_blob` if the expression is false.
```rex
assert x > 0
assert len items > 0
```

---

## Concurrency / Vectorization 📋

### `blast` / `pipe`
Vectorized iteration unrolling. Maps to `movntdq` / `movdqa` (bypasses CPU cache).
```rex
blast item in items:
    :item = item * 2

pipe result from source into sink:
    output result
```

---

## `err` with `bool unknown` ✅

`unknown` is a tri-state boolean backed by hardware entropy (`rdrand`). Use it to represent values that are genuinely indeterminate at compile time:
```rex
bool coin
:coin = unknown
output coin           // prints: true, false, or unknown
```

---

## Comments

### Line comments ✅
`//` begins a line comment. Everything after it on that line is ignored.
```rex
int x = 5    // this is a constant
:x = 10      // mutation — x is now mutable
```

### Block comments 📋
`/* */` spans multiple lines. Useful for temporarily disabling code or long notes.
```rex
/*
   This entire block is ignored by the compiler.
   Useful for multi-line notes or disabling code.
*/
int y = 42
```

### Doc comments 📋
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

## Tuples — Standalone Type 📋

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
output record.0    // 1
output record.1    // "Alice"
output record.2    // 9.5
```

### Destructuring
Unpack all fields into named variables in one line.
```rex
int id, str name, float score = record
output "id={id} name={name} score={score}"
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
output "quotient={q} remainder={r}"
```

### Tuple method reference

| Method | Returns | Notes |
|---|---|---|
| `.len()` | `int` | Always fixed — known at compile time |

> Use `str(t)` to get a string representation — cast function, not a method.

---

## Lambdas / Anonymous Protocols — `fn` 📋

Anonymous protocols are written with `fn`. They can be stored in variables,
passed as arguments, and used with `.map()`, `.filter()`, `.each()`, and
any protocol that accepts a protocol-typed parameter.

### Syntax
```rex
fn(int x) -> int: x * 2              // single-expression body
fn(int x, int y) -> int: x + y       // two params
fn(str s) -> bool: s.len() > 3       // bool return
fn(int x):                            // no return value (side-effect only)
    output "item: {x}"
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
output result
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
nums.each(fn(int x): output "{x}")

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

## Imports & Modules 📋

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
