# Rex — Language Syntax Reference

This document is the practical syntax reference for Rex. It covers every
language feature with examples. For the formal EBNF grammar see
`docs/grammar.md`. For the full design rationale see `design.md`.

---

## 1. Variables and Mutability

### Immutable (default)

Declare with a type and value. No `:` write site anywhere in scope = the
compiler treats this as a true constant (eligible for constant folding).

```rex
int age = 13
float pi = 3.14159
str name = "Rex"
```

### Mutable

Add `:` at the declaration site OR infer mutability from later `:x = …` sites.

```rex
:int total = 0          // mutable, declared with sigil

int count = 0           // declared without sigil
:count = count + 1      // compiler infers mutable from this write site
```

Declare without an initial value (type must be explicit):

```rex
int result
:result = @compute(x)
```

### The `:` write-site sigil

Every mutation is marked with `:` at the point where it happens. This makes
all state changes visible at a glance.

```rex
int x = 5
:x = x * 2             // mutation — eye immediately spots the ':'
++x                     // increment — self-evidently a mutation, no sigil
swap a b                // swap — self-evidently a mutation, no sigil
```

### Type inference

Omit the type annotation and Rex infers it from the initialiser.

```rex
n = 5               // int
r = 3.14            // float
s = "hello"         // str
ok = true           // bool
```

Literal → type mapping:
- `5` → `int`
- `3.14` → `float`
- `"..."` → `str`
- `'x'` → `char`
- `0xFF` → `int`
- `true` / `neutral` / `false` → `bool`

Inference does not cross scope boundaries. Without an initial value the type
must be stated explicitly.

---

## 2. Data Types

### Primitive types

| Type        | Default storage | Example              | Notes                                        |
|-------------|----------------|----------------------|----------------------------------------------|
| `int`       | 64-bit signed  | `int a = 5`          | Sized: `int[8]`–`int[1024]`; compiler picks ≤256 |
| `int[N]`    | N-bit signed   | `int[8] a = 127`     | N ∈ {8,16,32,64,128,256,512,1024}            |
| `float`     | 64-bit IEEE 754| `float b = 1.5`      | Sized: `float[32]` / `float[64]` / `float[128]` |
| `bool`      | 8-bit signed   | `bool f = true`      | Always 8-bit; `true(1)` `neutral(0)` `false(-1)` |
| `char`      | 8-bit (default)| `char c = 'R'`       | `char[8]`=ASCII, `char[16]`=UTF-16, `char[32]`=codepoint |
| `byte`      | 8-bit unsigned | `byte b = 0xFF`      | Always 8-bit; literal: `0xFF` or `"A"` (single char) |
| `str`       | Heap pointer   | `str s = "Rex"`      | UTF-8; `str[N]` = max N-byte stack buffer    |

### Collection types

| Type         | Example               | Notes                                         |
|--------------|-----------------------|-----------------------------------------------|
| `seq[T]`     | `seq[int] nums`       | Heap-allocated growable sequence              |
| `seq[T, N]`  | `seq[int, 64] buf`    | Pre-allocated with initial capacity N         |
| `arr[T, N]`  | `arr[int, 8] buf`     | Stack-allocated fixed array; N compile-time   |
| `arr[N]`     | `arr[512] = [1,2,3]`  | Element type inferred from initializer        |
| `dict[T]`    | `dict[int] d`         | SipHash-2-4 map; keys always `str`            |
| `dict[T, N]` | `dict[int, 128] d`    | Initial bucket count hint N                   |
| `tup[T...]`  | `tup[int, str] t`     | Heterogeneous tuple; positional; immutable    |

### User-defined types

| Declaration         | Example                       | Notes                         |
|---------------------|-------------------------------|-------------------------------|
| `struct Name:`      | `struct Point: float x, float y` | Named-field value type     |
| `enum Name:`        | `enum Dir: north, south`      | Typed integer constants        |
| `type Alias = T`    | `type Meters = float`         | Structural alias               |

### Numeric literals

```rex
int a = 255
int b = 0xFF            // hex
int c = 0b11111111      // binary
int d = 0o377           // octal
float f = 3.14
float g = 1.0e-4        // scientific notation

// Underscore separator
int million = 1_000_000
int addr    = 0xFF_00_AA_BB
float big   = 9_999.999_9
```

### Byte literals — two forms

```rex
byte a = 0xFF        // hex value
byte b = "A"         // single-char string → ASCII byte value
byte c = 65          // decimal
```

### Multiline strings and docstrings

```rex
str text = """
Line one
Line two
"""

"""
This docstring describes the next protocol.
"""
prot greet():
    output("Hello")
```

---

## 3. `bool` — Signed Ternary Logic

Rex `bool` is a signed 8-bit integer with exactly three values:

| Literal   | Stored value | Meaning                      |
|-----------|-------------|------------------------------|
| `true`    | `1`         | Affirmative                  |
| `neutral` | `0`         | Indeterminate                |
| `false`   | `-1`        | Negative                     |

**`and` = `min(a, b)`, `or` = `max(a, b)`, `not` = `-x`**

### `and` table

| `and`         | `false` (−1) | `neutral` (0) | `true` (1) |
|---------------|:---:|:---:|:---:|
| **`false`**   | false   | false   | false   |
| **`neutral`** | false   | neutral | neutral |
| **`true`**    | false   | neutral | true    |

### `or` table

| `or`          | `false` (−1) | `neutral` (0) | `true` (1) |
|---------------|:---:|:---:|:---:|
| **`false`**   | false   | neutral | true  |
| **`neutral`** | neutral | neutral | true  |
| **`true`**    | true    | true    | true  |

### `not` table

| Input     | Result    |
|-----------|-----------|
| `true`    | `false`   |
| `neutral` | `neutral` |
| `false`   | `true`    |

### Short-circuit

- `and`: skips RHS if LHS is `false`.
- `or`: skips RHS if LHS is `true`.
- `neutral` on either side never short-circuits.

### Usage

```rex
bool a = true
bool b = neutral
bool c = false

bool result
:result = a and b       // neutral  (min(1, 0) = 0)
:result = a or c        // true     (max(1, -1) = 1)
:result = not c         // true     (-(-1) = 1)
:result = not b         // neutral  (-(0) = 0)

flip b                  // b stays neutral (not neutral = neutral)

output(a.to_int())      // 1
output(b.to_int())      // 0
output(c.to_int())      // -1
```

### Bool methods

| Method           | Returns | Notes                                          |
|------------------|---------|------------------------------------------------|
| `.is_true()`     | `bool`  | `true` only if stored value is 1               |
| `.is_false()`    | `bool`  | `true` only if stored value is −1              |
| `.is_neutral()`  | `bool`  | `true` only if stored value is 0               |
| `.is_decided()`  | `bool`  | `true` if not neutral                          |
| `.to_int()`      | `int`   | `true`→1, `neutral`→0, `false`→−1             |
| `.to_str()`      | `str`   | `"true"`, `"neutral"`, or `"false"`            |

**`flip`** — boolean toggle only:

```rex
bool b = true
flip b          // b → false   ✓
flip b          // b → true    ✓

int x = 5
flip x          // raise "TypeError: flip requires bool, got int"
```

---

## 4. Operators

### Arithmetic

```rex
:c = a + b
:c = a - b
:c = a * b
:c = a / b
:c = a % b
```

### Bitwise

```rex
:z = x & y      // AND
:z = x | y      // OR
:z = x ^ y      // XOR
:z = ~x         // bitwise NOT
:z = x << 1     // left shift
:z = x >> 1     // right shift
```

### Logical

```rex
if x > 0 and y > 0:
    output("both positive")

if a == 0 or b == 0:
    output("at least one zero")

if not flag:
    output("off")
```

`not` on `bool` is signed negation. `not` on `int` is bitwise NOT (`~x`).

### Comparison

```rex
x == y      x != y
x < y       x > y
x <= y      x >= y
```

`bool` comparison uses signed ordering: `false(−1) < neutral(0) < true(1)`.

### Identity and membership

```rex
if ptr is null:
    output("null pointer")

if ptr is not null:
    output("valid")

if 3 in nums:
    output("found")

if "key" in scores:
    output("key exists")

if "ell" in "hello":
    output("substring")
```

### Increment / decrement / swap

```rex
++x
--x
swap a b
```

### `flip` — bool negation in place

```rex
bool flag = true
flip flag           // flag is now false
flip flag           // flag is now true

bool b = neutral
flip b              // stays neutral
```

### `abs`, `hash`, `typeof`

```rex
int v = abs(-42)
int h = hash s
output(typeof x)    // compile-time type tag as int
```

### Hardware primitives

```rex
int n = rand        // hardware entropy (rdrand)
bool c = carry      // CPU carry flag → true or false
bool ov = overflow  // CPU overflow flag → true or false
```

### Syscall intercept — `$`

```rex
#unsafe
prot exit(int code):
    $(60, code)         // sys_exit

#unsafe
prot write_raw(str s, int len):
    $(1, 1, s, len)     // sys_write(stdout, buf, len)
```

### Pipeline — `->`

```rex
@compute(x) -> output           // output(@compute(x))
a + b -> @process()             // @process(a + b)
```

---

## 5. Type Casting

The type name is the cast function.

| Cast         | From                                 | Notes                                                      |
|--------------|--------------------------------------|------------------------------------------------------------|
| `int(x)`     | `float`, `str`, `char`, `byte`, `bool` | Float truncates toward zero; bool → −1/0/1              |
| `float(x)`   | `int`, `str`                         | Str parses decimal                                         |
| `str(x)`     | any primitive                        | Human-readable representation                              |
| `char(x)`    | `int`, `byte`                        | UTF-8 code point                                           |
| `byte(x)`    | `int`, `char`                        | Low 8 bits                                                 |
| `bool(x)`    | `int`                                | positive → `true`, 0 → `neutral`, negative → `false`      |

```rex
float f = 3.7
int i = int(f)          // 3  (truncates toward zero)

str s = str(42)         // "42"
int n = int("42")       // 42

char c = char(65)       // 'A'
int code = int('A')     // 65

bool b = bool(5)        // true
bool nb = bool(-3)      // false
bool zb = bool(0)       // neutral

int bval = int(true)    // 1
int nval = int(neutral) // 0
int fval = int(false)   // -1
```

---

## 6. Primitive Type Methods

### `int` methods

```rex
int n = -42

n.abs()              // 42
n.signum()           // -1
n.clamp(-100, 0)     // -42
n.min(0)             // -42
n.max(0)             // 0
n.pow(2)             // 1764
n.is_negative()      // true
n.is_even()          // true
n.gcd(14)            // 14
n.lcm(14)            // 42  (abs)

int x = 255
x.popcount()         // 8
x.leading_zeros()    // 56
x.trailing_zeros()   // 0
x.to_hex()           // "ff"
x.to_bin()           // "11111111"
x.swap_bytes()       // byte-reversed int
x.rotate_left(4)     // bits rotated
```

Full table: see `design.md` §4.5.

### `float` methods

```rex
float f = 3.7

f.ceil()         // 4
f.floor()        // 3
f.round()        // 4
f.fract()        // 0.7
f.abs()          // 3.7
f.clamp(0.0, 3.0) // 3.0

float pi = 3.14159
pi.sin()         // ~0.0
pi.cos()         // ~-1.0
pi.to_deg()      // ~180.0

(2.0).sqrt()     // 1.4142...
(2.0).log2()     // 1.0
(2.0).pow(10.0)  // 1024.0

float nan = (0.0) / (0.0)
nan.is_nan()     // true
nan.is_finite()  // false
```

Full table: see `design.md` §4.6.

### `char` methods

```rex
char c = 'R'

c.is_alpha()     // true
c.is_upper()     // true
c.to_lower()     // 'r'
c.to_int()       // 82
c.to_str()       // "R"

char d = '7'
d.is_digit()     // true
d.to_digit()     // 7

char sp = ' '
sp.is_whitespace() // true
```

### `byte` methods

```rex
byte b = 0b10110100

b.popcount()     // 4
b.to_hex()       // "b4"
b.to_bin()       // "10110100"
b.bit(2)         // true
b.swap_nibbles() // 0b01001011
b.rotate_left(3) // bits rotated within 8 bits
b.to_int()       // 180
b.to_char()      // char with code 180
```

---

## 7. Protocols (Functions)

### Definition

```rex
prot greet():
    output("Hello")

prot square(int x) -> int:
    return x * x

prot add(int a, int b) -> int:
    return a + b
```

- No return annotation → void protocol.
- Up to **65 parameters**. First 6 in registers (`rdi`/`rsi`/`rdx`/`rcx`/`r8`/`r9`); parameters 7–65 are stack-passed (pushed right-to-left, caller cleans up).

### Calling with `@`

`@` is the protocol call prefix — every `@` in Rex code means "this is yours."

```rex
@greet()

int result
:result = @add(3, 4)
output(result)
```

### Multiple return values

```rex
prot minmax(seq[int] s) -> (int, int):
    int lo = s[0]
    int hi = s[0]
    each n in s:
        if n < lo: :lo = n
        if n > hi: :hi = n
    return lo, hi

int lo
int hi
:lo, :hi = @minmax(nums)
```

Two return values come back in `rax` and `rdx`. Three or more use a
caller-allocated stack buffer.

### Decorators

Single decorator: `#name`. Multiple on one line: `#[a, b, c]`.

```rex
// single
#unsafe
prot exit(int code):
    $(60, code)

// multiple — bracket syntax
#[memo, pure]
prot fib(int n) -> int:
    if n <= 1:
        return n
    return @fib(n-1) + @fib(n-2)

#[hot, inline]
prot dot(int a, int b) -> int:
    return a * b

// mixed built-in + user-defined + argument
#[hot, log("render")]
prot render(str template) -> str:
    return template
```

| Decorator   | Effect                                                       |
|-------------|--------------------------------------------------------------|
| `#memo`     | Cache return value keyed on input                            |
| `#pure`     | No side effects — compiler may reorder or elide calls        |
| `#total`    | Hint: terminates for all inputs                              |
| `#inline`   | Force inline at every call site                              |
| `#noinline` | Prevent inlining                                             |
| `#hot`      | Optimize for throughput                                      |
| `#cold`     | Optimize for binary size                                     |
| `#safe`     | Verifies: no raw syscalls or pointer arithmetic inside       |
| `#unsafe`   | Allows `$` syscalls and direct memory ops                    |

Order inside `#[...]` does not matter. Built-in and user-defined decorators mix freely.

### Custom decorators

```rex
// no parameters
decorator trace:
    before: output("→ entering")
    after:  output("← exiting")

// parameterized
decorator log(str tag):
    before: output("→ {tag}")
    after:  output("← {tag}")

// wrap — replaces the whole call; __body__() invokes original
decorator repeat(int n):
    wrap:
        for i in 0..n:
            __body__()

// on_error — runs if an uncaught raise exits the protocol
decorator guarded(str label):
    on_error: output("error in {label}: {__error__.msg}")
    after:    output("done {label}")
```

```rex
#trace
prot greet():
    output("Hello")

#log("net")
prot fetch(str url) -> str:
    return @http_get(url)

#repeat(3)
prot tick():
    output("tick")

#guarded("upload")
prot upload(str path):
    raise "IOError: disk full"
```

Decorator blocks available: `before:`, `after:`, `wrap:`, `on_error:`.
`wrap:` is mutually exclusive with `before:`/`after:`.
`__body__()` is only valid inside `wrap:`.
`__error__` (fields `.tag`, `.msg`) is only valid inside `on_error:`.

### Error handling — `try` / `except` / `finally` / `raise`

```rex
// raise an error
raise "ValueError"
raise "IOError: file not found"

// basic try/except
try:
    int x = @parse_int(raw)
    output(x)
except "ValueError" as e:
    output("bad value: {e.msg}")
except "IOError":
    output("I/O problem")
except:
    output("unexpected error")
finally:
    output("always runs")
```

The `error` object bound in `except "Tag" as e`:

| Field   | Type  | Value                                      |
|---------|-------|--------------------------------------------|
| `e.tag` | `str` | Text before the first `:` in raise string  |
| `e.msg` | `str` | Full raise string                          |
| `e.line`| `int` | Source line of the `raise` statement       |

```rex
// re-raise
try:
    @risky()
except "IOError" as e:
    output("logged: {e.msg}")
    raise e.msg             // propagate upward

// nested try
try:
    try:
        raise "Inner"
    except "Inner":
        raise "Outer"
except "Outer" as e:
    output(e.tag)           // Outer

// full example with file I/O
prot safe_open(str path) -> str:
    if not file_exists(path):
        raise "IOError: {path} not found"
    with open(path, "r") as f:
        return f.read()

try:
    str data = @safe_open("config.txt")
    output(data)
except "IOError" as e:
    output("could not read config: {e.msg}")
finally:
    output("done")
```

`finally:` always runs. It may not contain `raise`. Bare `except:` must be
the last clause. Unmatched errors propagate to the enclosing `try`; if no
handler exists the program terminates with the error message.

---

## 8. Control Flow

### `if` / `elif` / `else`

```rex
int x = 10

if x == 10:
    output("ten")
elif x == 5:
    output("five")
else:
    output("other")
```

`neutral` in a condition is falsy. Only `true` is truthy.

### `switch` / `is` — value dispatch

```rex
int code = 2

switch code:
    is 1:
        output("one")
    is 2..5:
        output("two through four")
    is 5:
        output("five")
    else:
        output("other")
```

Ranges are **exclusive** on the right: `2..5` matches 2, 3, 4.
Multiple patterns per case — comma-separated. `else` must be last.

```rex
str status = "ok"

switch status:
    is "ok":
        output("all good")
    is "warn", "error":
        output("problem: {status}")
    else:
        output("unknown")

switch direction:
    is Direction.north, Direction.south:
        output("vertical")
    is Direction.east, Direction.west:
        output("horizontal")
```

Works on `int`, `float`, `str`, `bool`, `char`, enum values. Dense integer
ranges compile to O(1) jump tables. No implicit fallthrough.

### `when` — state monitor

`when expr` returns a `bool` tri-state based on whether the condition **changed**:

| Returns  | Meaning                                               |
|----------|-------------------------------------------------------|
| `true`   | Condition just became true (was false/neutral before) |
| `false`  | Condition just became false (was true before)         |
| `neutral`| Condition state has not changed since last check      |

```rex
int x = 0
bool chg = when x > 0      // false (currently false, first eval)

:x = 5
:chg = when x > 0          // true  (was false, now true → changed)
:chg = when x > 0          // neutral (was true, still true → no change)

// Reactive pattern in a loop
while running:
    if when x > 100:
        output("x crossed 100: {x}")
```

### Inline `if` expression

```rex
int x = if a > 0: 1 else: -1

str label = if score >= 90: "A" elif score >= 80: "B" else: "C"

output(if n == 0: "zero" else: "nonzero")
```

All branches must return the same type. `else` is required.

### `pass`

```rex
prot stub():
    pass

if x == 0:
    pass
else:
    output(x)
```

---

## 9. Loops

### `for` — range loop

```rex
for i in 0..10:
    output(i)

for i in 0..20 step 2:
    output(i)

for i in 10..0 step -1:
    output(i)
```

### `while` — conditional loop

```rex
while x > 0:
    :x = x - 1

while true:
    str line = input("> ")
    if line == "quit":
        stop
    output(line)
```

### `each` — collection iterator

```rex
// Element only
each item in items:
    output(item)

// With index (read-only)
each i, item in items:
    output("{i}: {item}")

// Mutating form — ':' on element name
seq[int] nums = [1, 2, 3, 4, 5]
each :n in nums:
    :n = n * 2          // doubles in place

// Over str — yields char
each ch in "Rex":
    output(ch)          // R, e, x

// Over dict — yields key and value
each k, v in scores:
    output("{k}: {v}")
```

### `repeat` — counted loop

```rex
repeat 8:
    output("tick")

int sum = 0
repeat 100:
    :sum = sum + 1
```

No counter is exposed. Emits a single `dec`/`jnz` hardware loop.
`N` must be a compile-time integer constant.

### Loop control

```rex
for i in 0..100:
    if i == 5:
        stop            // break innermost loop

for i in 0..10:
    for j in 0..10:
        if i == j:
            stop 2      // break both loops at once

for i in 0..10:
    if i % 2 == 0:
        skip            // continue to next iteration

for i in 0..10:
    for j in 0..10:
        if j == 3:
            skip 2      // continue outer loop
```

### Loop `else`

```rex
for i in 0..10:
    if i == 5:
        stop
else:
    output("completed without stop")
```

The `else` block runs only when the loop exits naturally (no `stop` was hit).

---

## 10. Sequences `seq[T]`

```rex
seq[int] nums = [1, 2, 3, 4, 5]
seq[str] words = ["hello", "world"]
seq[seq[int]] matrix
```

### Core

```rex
:nums.push(6)
int last = nums.pop()
output(len(nums))
output(cap(nums))
output(nums.is_empty())
:nums.clear()
:nums.reserve(100)
```

### Access and search

```rex
int first = nums[0]
int last = nums[-1]         // negative indices count from end
:nums[2] = 99               // write requires ':'

nums.first()                // first element
nums.last()                 // last element
nums.contains(3)            // bool
nums.index_of(3)            // int; -1 if not found
nums.last_index_of(3)       // int
nums.count_of(3)            // int
nums.find(fn(int x) -> bool: x > 10)       // first match
nums.find_index(fn(int x) -> bool: x > 10) // index of first match
```

### Slicing and copying

```rex
seq[int] sub = nums.slice(1, 4)     // [idx 1, 4) exclusive
seq[int] tail = nums.slice_from(3)
seq[int] head = nums.take(3)
seq[int] rest = nums.drop(3)
seq[int] copy = nums.copy()
```

### Ordering

```rex
:nums.sort()
:nums.sort_desc()
:nums.sort_by(fn(int a, int b) -> int: a - b)
:nums.reverse()
nums.is_sorted()
nums.min()
nums.max()
nums.min_index()
nums.max_index()
```

### Math aggregates

```rex
nums.sum()
nums.product()
nums.mean()
nums.median()
```

### Functional

```rex
seq[int] doubled = nums.map(fn(int x) -> int: x * 2)
seq[int] evens = nums.filter(fn(int x) -> bool: x % 2 == 0)
int total = nums.reduce(0, fn(int acc, int x) -> int: acc + x)
seq[int] flat = matrix.flat()
nums.each(fn(int x): output(x))
nums.each_index(fn(int i, int x): output("{i}: {x}"))

bool any = nums.any(fn(int x) -> bool: x > 10)
bool all = nums.all(fn(int x) -> bool: x > 0)
bool none = nums.none(fn(int x) -> bool: x < 0)
int cnt = nums.count(fn(int x) -> bool: x > 5)
```

### Set operations

```rex
seq[int] a = [1, 2, 3, 4]
seq[int] b = [3, 4, 5, 6]

a.unique()          // remove duplicates (order kept)
a.union(b)          // [1, 2, 3, 4, 5, 6]
a.intersect(b)      // [3, 4]
a.diff(b)           // [1, 2]
```

### Zip and enumerate

```rex
seq[int] xs = [1, 2, 3]
seq[str] ys = ["a", "b", "c"]

seq[tup[int, str]] zipped = xs.zip(ys)
seq[tup[int, int]] indexed = xs.enumerate()
```

### Conversion

```rex
output(nums.to_str())                       // "[1, 2, 3]"
str joined = ", ".join(words.to_seq())      // for str seqs
```

---

## 11. Fixed Arrays `arr[T, N]`

```rex
arr[int, 8] buf
arr[float, 3] v = [1.0, 0.0, 0.0]
arr[byte, 16] key = [0] * 16
```

Same access and search API as `seq`. No `push`/`pop`. No realloc.
Sorting and functional methods return `seq[T]`.

```rex
arr[int, 5] a = [4, 2, 7, 1, 9]

output(len(a))           // 5 (compile-time constant)
output(a.first())        // 4
output(a.contains(7))    // true
output(a.min())          // 1
output(a.sum())          // 23
:a.sort()
seq[int] s = a.to_seq()  // copy to heap seq
```

---

## 12. Dictionaries `dict[T]`

```rex
dict[int] scores = {"alice": 95, "bob": 87}
dict[str] config = {"host": "localhost", "port": "8080"}
```

### Access

```rex
int v = scores["alice"]             // read; error if key absent
:scores["alice"] = 99               // write; inserts if absent
scores.has("carol")                 // bool
scores.get_or("dave", 0)            // default if missing; no insert
scores.get_or_set("dave", 50)       // insert default if absent, return value
len(scores)
scores.is_empty()
```

### Modification

```rex
scores.remove("alice")
scores.remove_if("alice")       // bool: was it there?
:scores.clear()
:scores.update(extras)          // merge; extras wins on conflict
:scores.update_if_absent(extras) // merge; self wins (no overwrites)
scores.set_if_absent("new", 0)  // insert only if not present
```

### Keys, values, pairs

```rex
seq[str] ks = scores.keys()
seq[int] vs = scores.values()
seq[tup[str, int]] ps = scores.pairs()
dict[int] copy = scores.copy()
```

### Functional

```rex
scores.each(fn(str k, int v): output("{k}: {v}"))
dict[str] labels = scores.map(fn(str k, int v) -> str: fmt("{v} pts"))
dict[int] passing = scores.filter(fn(str k, int v) -> bool: v >= 75)
bool any = scores.any(fn(str k, int v) -> bool: v == 100)
bool all = scores.all(fn(str k, int v) -> bool: v > 0)
int cnt = scores.count(fn(str k, int v) -> bool: v >= 80)
dict[str] rev = abbrevs.invert()    // swap keys/values; T must be str
```

---

## 13. Tuples `tup[T...]`

```rex
tup[int, str] pair = (42, "hello")
tup[float, float, float] vec3 = (1.0, 0.0, 0.0)
```

Elements accessed by position with `.0`, `.1`, `.2`, etc.

```rex
int n = pair.0          // 42
str s = pair.1          // "hello"
```

### Destructuring

```rex
int a
str b
:a, :b = pair
```

### Methods

```rex
len(pair)           // 2
pair.to_str()       // "(42, "hello")"
pair.copy()         // stack copy

// Homogeneous → seq
tup[int, int, int] rgb = (255, 128, 0)
seq[int] ch = rgb.to_seq()

// Comparison (element-wise)
tup[int, str] x = (1, "a")
tup[int, str] y = (1, "a")
output(x == y)      // true
```

---

## 14. Strings `str`

```rex
str s = "Hello, Rex!"
str t = "world"
```

### Operators

```rex
str r = s + " " + t     // concatenation
str line = "-" * 40     // repetition
char c = s[0]           // index
char last = s[-1]       // negative index
bool eq = s == t        // equality
bool lt = s < t         // lexicographic
bool found = "ell" in s // substring test
```

### Methods — inspection

```rex
len(s)              // byte count
s.char_count()      // UTF-8 code point count
s.is_empty()        // bool
```

### Methods — case and whitespace

```rex
s.upper()           // "HELLO, REX!"
s.lower()           // "hello, rex!"
s.trim()            // strip leading/trailing whitespace
s.trim_left()       // strip leading only
s.trim_right()      // strip trailing only
s.trim_char('.')    // strip specific char from both ends
```

### Methods — search

```rex
s.contains("Rex")       // true
s.starts_with("Hello")  // true
s.ends_with("!")        // true
s.index_of("Rex")       // int; -1 if not found
s.last_index_of("l")    // int
s.count("l")            // 3
```

### Methods — slicing and splitting

```rex
s.slice(7, 10)          // "Rex"
s.slice_from(7)         // "Rex!"
s.take(5)               // "Hello"
s.drop(7)               // "Rex!"
s.split(", ")           // seq[str]
s.split_char(',')       // seq[str]
s.lines()               // split on \n
s.words()               // split on whitespace runs
```

### Methods — transformation

```rex
s.replace("Rex", "World")   // first occurrence
s.replace_all("l", "L")     // all occurrences
s.reverse()                 // "!xeR ,olleH"
s.repeat(3)
s.insert(7, "dear ")
s.remove_at(0, 7)           // remove 7 bytes at index 0
```

### Methods — padding

```rex
"hi".pad_left(10, '.')      // "........hi"
"hi".pad_right(10, '-')     // "hi--------"
"hi".center(10, '*')        // "****hi****"
```

### Methods — joining and iterating

```rex
", ".join(names)            // "alice, bob, carol"
s.chars()                   // seq[char]
s.bytes()                   // seq[byte]
s.each(fn(char c): output(c))
```

### Methods — conversion and parsing

```rex
"42".to_int()       // 42
"3.14".to_float()   // 3.14
s.is_alpha()        // bool
s.is_digit()        // bool
s.is_ascii()        // bool
```

### String interpolation

```rex
output("x is {x} and y is {y}")
output("result: {a + b}")
output("fib(10) = {@fib(10)}")
output("{{not interpolated}}")     // literal {
```

### Format specifiers

`:` inside `{}` activates format mode:

```rex
output("pi = {pi:.2f}")        // 3.14
output("{n:08b}")              // 00001111
output("{n:x}")                // ff
output("{n:X}")                // FF
output("{n:10d}")              // right-aligned, width 10
output("{name:10s}")           // left-aligned, width 10
```

---

## 15. File I/O — `with open`

Files are opened with `with open(...) as var:`. The file is automatically
closed when the block exits.

```rex
with open("data.txt", "r") as f:
    str contents = f.read()
    output(contents)

with open("log.txt", "w") as f:
    f.writeln("started")
    f.writeln("done")

with open("image.png", "rb") as f:
    seq[byte] raw = f.read_all_bytes()
```

### Open modes

| Mode  | Meaning                                          |
|-------|--------------------------------------------------|
| `"r"` | Read text; error if file does not exist          |
| `"w"` | Write text; creates or truncates                 |
| `"a"` | Append text; creates if absent                   |
| `"rb"`| Read raw bytes                                   |
| `"wb"`| Write raw bytes; creates or truncates            |
| `"ab"`| Append raw bytes                                 |
| `"r+"`| Read and write; file must exist                  |
| `"w+"`| Read and write; creates or truncates             |

### File handle methods

| Method                | Returns    | Notes                                         |
|-----------------------|------------|-----------------------------------------------|
| `.read()`             | `str`      | Read entire file as a string                  |
| `.read_line()`        | `str`      | Read one line; empty string at EOF            |
| `.read_bytes(n)`      | `seq[byte]`| Read exactly `n` bytes                        |
| `.read_all_bytes()`   | `seq[byte]`| Read entire file as bytes                     |
| `.lines()`            | `seq[str]` | All lines, `\n` stripped                      |
| `.write(s)`           | `void`     | Write string; no newline added                |
| `.writeln(s)`         | `void`     | Write string + `\n`                           |
| `.write_bytes(buf)`   | `void`     | Write raw bytes                               |
| `.seek(n)`            | `void`     | Seek to byte offset from start                |
| `.seek_end(n)`        | `void`     | Seek `n` bytes before end                     |
| `.pos()`              | `int`      | Current byte position                         |
| `.size()`             | `int`      | Total file size in bytes                      |
| `.is_eof()`           | `bool`     | `true` if at end of file                      |
| `.flush()`            | `void`     | Flush write buffer to OS                      |
| `.path()`             | `str`      | Path as given to `open`                       |

### Patterns

**Line-by-line:**
```rex
with open("words.txt", "r") as f:
    while not f.is_eof():
        str line = f.read_line()
        if line.is_empty(): stop
        output(line.trim())
```

**All lines at once:**
```rex
with open("words.txt", "r") as f:
    each line in f.lines():
        output(line.upper())
```

**Writing with flush:**
```rex
with open("out.txt", "w") as f:
    for i in 0..100:
        f.writeln("line {i}")
    f.flush()
```

**Binary copy:**
```rex
with open("src.bin", "rb") as src:
    with open("dst.bin", "wb") as dst:
        dst.write_bytes(src.read_all_bytes())
```

**Check before open:**
```rex
if not file_exists("config.txt"):
    output("config.txt not found")

with open("config.txt", "r") as f:
    output(f.read())
```

---

## 16. I/O — Console

### `output()` — Python-style print

```rex
output()                              // blank line
output("hello")                       // hello
output(1, 2, 3)                       // 1 2 3
output("a", "b", "c", sep="-")       // a-b-c
output("loading", end="...")          // loading... (no newline)
output("x =", 42, sep="")            // x =42
```

- Default `sep = " "`, default `end = "\n"`
- Multiple args of any type accepted; each stringified
- `sep` and `end` are always keyword arguments

### `input()` — read from stdin

```rex
str name = input("Enter name: ")
int n = int(input("Number: "))

// EOF / Ctrl+D raises EOFError
try:
    str line = input("> ")
except "EOFError":
    output("bye")
```

### `fmt()` — format without printing

```rex
str label = fmt("score: {score:.1f}")
str hex   = fmt("0x{addr:X}")
```

---

## 17. Memory Management — `use mm` / `use gc`

```rex
use mm arena:
    seq[int] buf = [1, 2, 3]    // allocated from arena
    // all allocations freed at block exit (single free)

use mm pool:
    seq[int] items              // fixed-size pool allocator

use gc sweep:
    dict[int] d                 // mark-and-sweep GC

use mm heap gc ref:
    str big = "..."             // heap alloc + reference counting
```

**Memory modes:**

| Mode      | Strategy                    | Best for                         |
|-----------|-----------------------------|----------------------------------|
| `arena`   | Bump-pointer; O(1) free     | Short-lived batch allocations    |
| `pool`    | Fixed-size freelist         | Many same-sized objects          |
| `stack`   | LIFO                        | Scoped allocations               |
| `heap`    | General `malloc`            | Unpredictable lifetimes          |
| `static`  | Compile-time static region  | Fixed-size globals               |

**GC modes:**

| Mode     | Strategy           |
|----------|--------------------|
| `sweep`  | Mark-and-sweep     |
| `ref`    | Reference counting |
| `gen`    | Generational       |
| `inc`    | Incremental        |
| `region` | Region-based       |

---

## 18. Safety — `#safe` / `#unsafe`

```rex
#safe
prot pure_compute(int x) -> int:
    return x * x               // verified: no syscalls, no raw memory

#unsafe
prot exit(int code):
    $(60, code)                // raw syscall allowed
```

`#safe` protocols are verified by the compiler: no `$` syscalls, no pointer
arithmetic. `#unsafe` lifts all restrictions. Default is `#safe`.

---

## 19. Module System — `module` / `use`

**Defining an inline module:**
```rex
module geometry:
    float pi = 3.14159265358979

    prot area(float r) -> float:
        return pi * r * r

    prot _validate(float r):   // _prefix = private
        if r < 0.0:
            raise "ValueError: negative radius"
```

**Importing:**
```rex
use geometry              // qualified access only: geometry.area(5.0)
use geometry: area        // unqualified + qualified
use geometry: area, pi    // multiple names
use geometry: *           // all public names
```

**Using imported names:**
```rex
use math: sqrt, sin, cos

float h = sqrt(9.0)           // unqualified
float s = math.sin(0.0)       // qualified always works too
```

**File modules** — any `name.rex` in the same directory is automatically `module name`:
```rex
// utils.rex  →  module utils (automatic)
prot clamp(int v, int lo, int hi) -> int:
    if v < lo: return lo
    if v > hi: return hi
    return v
```
```rex
// main.rex
use utils: clamp
int n = clamp(42, 0, 10)
```

**Module-scoped decorators:**
```rex
// logger.rex
decorator log(str tag):
    before: output("→ {tag}")
    after:  output("← {tag}")
```
```rex
use logger: log

#log("fetch")
prot fetch(str url) -> str:
    return @http_get(url)

#[hot, log("render")]
prot render(str t) -> str:
    return t
```

**Visibility rules:**
- `_prefix` → private to the module; not importable
- No `_prefix` → public; importable with `use`
- Circular imports → compile-time error (detected in pass 2)

**Rules:**
- Modules resolve at compile time; no runtime dynamic loading
- `use name: *` imports all public names into the current scope
- Qualified call `module.name(args)` always works after any `use` form
- A module cannot re-export another module's names

---

## 20. `fn` Literals (Anonymous Protocols)

Used as arguments to higher-order methods (`.map`, `.filter`, `.sort_by`, etc.).
`fn` literals capture no variables from the enclosing scope.

```rex
seq[int] doubled = nums.map(fn(int x) -> int: x * 2)

seq[int] pos = nums.filter(fn(int x) -> bool: x > 0)

int total = nums.reduce(0, fn(int acc, int x) -> int: acc + x)

:nums.sort_by(fn(int a, int b) -> int: a - b)

nums.each(fn(int x): output(x))
```

Multi-line `fn` body:

```rex
seq[int] processed = nums.map(fn(int x) -> int:
    int v = x * x
    return v - 1
)
```

---

## 21. Type Inspection

```rex
int x = 5
output(typeof x)    // prints compile-time type tag as int

// Type tokens:
// int=1, float=2, bool=3, str=5, char=8, byte=9, seq=6, dict=7, tup=11
```

---

## 22. Structs

Named-field value types. Fields immutable by default; `:.field =` to mutate.

```rex
struct Point:
    float x
    float y

struct Person:
    str name
    int age
    bool active

struct Rect:
    Point top_left
    Point bottom_right
```

**Construct, access, mutate:**

```rex
Point p = Point{x: 1.0, y: 2.0}
Person alice = Person{name: "Alice", age: 30, active: true}

output(p.x)              // 1.0
output(alice.name)       // "Alice"

:p.x = 3.0              // : required for mutation
:alice.age = alice.age + 1

// Nested
Rect r = Rect{top_left: Point{x: 0.0, y: 0.0}, bottom_right: Point{x: 10.0, y: 5.0}}
output(r.top_left.x)
```

---

## 23. Enums

Typed integer constants grouped under a name.

```rex
enum Direction: north, south, east, west

enum Status:
    ok    = 0
    warn  = 1
    error = 2
    fatal = 3

enum Bit: off = 0, on = 1
```

```rex
Direction d = Direction.north
output(d)               // "north"
output(int(d))          // 0

switch d:
    is Direction.north, Direction.south:
        output("vertical")
    is Direction.east, Direction.west:
        output("horizontal")
```

---

## 24. Type Aliases

```rex
type Meters    = float
type Name      = str
type Matrix    = arr[float, 16]
type IntSeq    = seq[int]
type SmallInt  = int[16]

Meters dist = 10.5
Name user = "Rex"
float d2 = dist         // OK — same underlying type
```

---

## 25. Generics

Type-parameterised protocols. Types resolved at call site (monomorphised).

```rex
prot map[T, U](seq[T] s, fn(T) -> U f) -> seq[U]:
    seq[U] result = []
    each item in s:
        result.push(f(item))
    return result

prot first[T](seq[T] s) -> T:
    if len(s) == 0:
        raise "ValueError: empty sequence"
    return s[0]
```

```rex
seq[int] nums = [1, 2, 3]
seq[str] strs = @map(nums, fn(int x) -> str: str(x))  // T=int, U=str inferred
int n = @first(nums)                                   // T=int inferred
```

---

## 26. Null

Any reference type can hold `null`. Value types (`int`, `float`, `bool`, `char`, `byte`) cannot.

```rex
str name = null
seq[int] items = null

if name is null:
    output("unset")
else:
    output("name: {name}")

// Accessing null raises NullError
output(name)            // raise "NullError: dereferenced null str"
```

**Null-safe operators:**

```rex
str n = null
str safe = n ?? "default"         // "default" if n is null
str up = n?.to_upper() ?? ""      // null-safe method call; "" if n is null
int length = if n is null: 0 else: len(n)   // safe len with null check
```

---

## 27. Constants

```rex
const MAX    = 1024
const PI     = 3.14159265358979
const PREFIX = "rex_"
const MASK   = 0xFF_00_FF_00
const DOUBLE = MAX * 2        // expressions allowed if all operands are const

// Use anywhere a literal is valid
arr[int, MAX] buf
for i in 0..MAX:
    output(buf[i])
```

---

## 28. Assert and Unreachable

```rex
assert(x > 0)                        // raise "AssertionError: assertion failed"
assert(x > 0, "x must be positive")  // raise "AssertionError: x must be positive"

unreachable()                         // raise "UnreachableError: reached unreachable code"
```

In `#blast` protocols both are stripped — use only when provably safe.

---

## 29. Variadic Protocols

The last parameter may accept variable arguments using `...`:

```rex
prot log(str level, str... msgs):
    each m in msgs:
        output("[{level}] {m}")

prot sum(int... nums) -> int:
    int total = 0
    each n in nums:
        :total = total + n
    return total

@log("INFO", "started", "ready")
output(@sum(1, 2, 3, 4, 5))    // 15
```

Inside the body the variadic param is `seq[T]`. Only the last param may be variadic.

---

## 30. Example Programs

### Hello World

```rex
output("Hello, World!")
```

### Fibonacci

```rex
prot fib(int n) -> int:
    if n <= 1:
        return n
    return @fib(n-1) + @fib(n-2)

for i in 0..10:
    output(@fib(i))
```

### Word frequency counter

```rex
with open("words.txt", "r") as f:
    dict[int] freq

    each line in f.lines():
        each word in line.words():
            str w = word.lower()
            :freq[w] = freq.get_or(w, 0) + 1

    seq[str] keys = freq.keys()
    :keys.sort()
    each k in keys:
        output("{k}: {freq[k]}")
```

### Signed ternary bool demo

```rex
bool a = true
bool b = neutral
bool c = false

output(a.to_int())      // 1
output(b.to_int())      // 0
output(c.to_int())      // -1

output(a and b)         // neutral
output(a or c)          // true
output(not c)           // true
output(b.is_neutral())  // true
output(c.is_decided())  // true
```

### File copy

```rex
prot copy_file(str src, str dst):
    with open(src, "rb") as fin:
        with open(dst, "wb") as fout:
            fout.write_bytes(fin.read_all_bytes())

@copy_file("a.bin", "b.bin")
```

### Seq functional pipeline

```rex
seq[int] nums = [5, -3, 8, -1, 9, 2, -6, 4]

seq[int] result = nums
    .filter(fn(int x) -> bool: x > 0)
    .map(fn(int x) -> int: x * x)
    .filter(fn(int x) -> bool: x > 10)

output(result)          // [64, 81]
output(result.sum())    // 145
output(result.mean())   // 72.5
```

### Binary read

```rex
with open("data.bin", "rb") as f:
    int size = f.size()
    seq[byte] buf = f.read_bytes(size)

    for i in 0..len(buf):
        output("{i:04d}: {buf[i].to_hex()}")
```
