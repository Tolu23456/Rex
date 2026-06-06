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

---

## Data Types ✅

| Type       | Syntax Example         | Notes                                                        |
|------------|------------------------|--------------------------------------------------------------|
| `int`      | `int a = 5`            | 64-bit signed integer                                        |
| `float`    | `float b = 1.5`        | 64-bit double (IEEE 754, SSE2)                               |
| `bool`     | `bool f = true`        | Tri-state: `true`, `false`, `unknown` (Kleene logic)         |
| `str`      | `str s = "Rex"`        | Heap-managed UTF-8 string; `[cap][len][data]` layout         |
| `char`     | `char c = 'R'`         | Single UTF-8 byte; lightweight alias over `byte`             |
| `byte`     | `byte b = 0xFF`        | Raw unsigned 8-bit value; for binary data and I/O            |
| `seq[T]`   | `seq[int] nums`        | Typed dynamic sequence (heap); push / pop / len / cap        |
| `dict[T]`  | `dict[int] d`          | Typed SipHash map; keys are always `str`, value type is `T`  |

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

## Type Casting ✅

```rex
float f = 3.7
int i
:i = int(f)         // cvttsd2si — truncates toward zero

int n = 5
float g
:g = float(n)       // cvtsi2sd
```

### String cast 📋
Convert any value to its string representation.
```rex
str s
:s = str(42)
:s = str(pi)
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

### Protocol decorators — `#` 📋

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

## Sequences ✅

Sequences are typed. The element type is declared in brackets. The compiler
uses the type to size elements, enforce push/pop type safety, and optimise
access patterns.

```rex
seq[int] nums
push nums 10
push nums 20
push nums 30

int n
:n = len nums       // length (runtime read from hidden header)
output n

int c
:c = cap nums       // capacity (allocated slots)

int v
:v = pop nums       // LIFO pop — returns int
output v
```

Method-call syntax is also valid:
```rex
seq[float] data
data.push(1.5)
data.push(2.7)
```

Sequences grow automatically: if a `push` would exceed capacity, the runtime
allocates a larger block, copies existing elements, and resumes. Growth is
unbounded. A compile-time error is raised if you push an element whose type
does not match the declared element type.

---

## Dictionaries ✅

Dictionaries are typed by value. Keys are always `str`. The value type is
declared in brackets.

```rex
dict[int] d
d["hello"] = 42
d["world"] = 99

int v
:v = d["hello"]
output v
```

```rex
dict[str] labels
labels["en"] = "Hello"
labels["es"] = "Hola"
output labels["en"]
```

A compile-time error is raised if you assign a value whose type does not match
the declared value type.

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

### Rounding 📋
```rex
float f = 3.7
float c
:c = ceil(f)

float fl
:fl = floor(f)

float fr
:fr = fract(f)      // fractional part only
```

---

## Complex Numbers — Deprecated in Core

`complex` has been moved out of the Rex core type system. It will be available
as a standard library import in a future release. The type and its operations
(`real`, `imag`, `conj`) continue to function in V0.1 but should not be relied
on in new code.

---

## Output ✅

Print any value with `output`. Rex routes to the correct printer based on the variable's declared type.
```rex
output 42
output x
output "hello"
output flag        // bool: prints true / false / unknown
output pi          // float
output c           // char: prints the character
output b           // byte: prints the numeric value
```

---

## Error Handling ✅

Emit a runtime error message to stderr and halt:
```rex
err "something went wrong"
```

Passing a non-string argument to `err` is handled gracefully: the value is
printed using its type's printer, then the process exits with code 1. Full
`int → str` conversion in error messages requires the `str(expr)` cast (planned).

---

## Memory Allocator Contexts

All memory management is **block-scoped**. The chosen strategy is active for the
duration of the indented body and reverts to the enclosing strategy on exit.
`mm` (allocator) and `gc` (collector) are independent axes — each can be used
alone or combined in a single `use` block.

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
