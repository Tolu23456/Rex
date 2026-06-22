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
- `5` → `int`, `3.14` → `float`, `"..."` → `str`, `true`/`neutral`/`false` → `bool`
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
| `bool`  | `bool f = true`      | −1 / 0 / 1 signed | Tri-state: `true` (1), `neutral` (0), `false` (−1) |
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

### 4.3 `bool` — Signed Ternary Logic

Rex `bool` has exactly three values stored as a signed 8-bit integer:

| Literal   | Stored value | Meaning                                        |
|-----------|-------------|------------------------------------------------|
| `true`    | `1`         | Affirmative — the condition holds              |
| `neutral` | `0`         | Indeterminate — neither confirmed nor denied   |
| `false`   | `-1`        | Negative — the condition does not hold         |

This is **Łukasiewicz three-valued logic** expressed as a signed number line.
`and` is `min(a, b)` and `or` is `max(a, b)` over the ordering `false < neutral < true`.
`not` negates: `not x` → `-x`, so `not true` = `false`, `not false` = `true`,
`not neutral` = `neutral`.

**`and` table — minimum of both sides:**

| `and`         | `false` (−1) | `neutral` (0) | `true` (1) |
|---------------|--------------|---------------|------------|
| **`false`**   | false        | false         | false      |
| **`neutral`** | false        | neutral       | neutral    |
| **`true`**    | false        | neutral       | true       |

**`or` table — maximum of both sides:**

| `or`          | `false` (−1) | `neutral` (0) | `true` (1) |
|---------------|--------------|---------------|------------|
| **`false`**   | false        | neutral       | true       |
| **`neutral`** | neutral      | neutral       | true       |
| **`true`**    | true         | true          | true       |

**`not` — numeric negation:**

| Input     | Result  |
|-----------|---------|
| `true`    | `false` |
| `neutral` | `neutral` |
| `false`   | `true`  |

```rex
bool a = true
bool b = neutral
bool c = false
bool result

:result = a and b       // neutral  (min(1, 0) = 0)
:result = a or b        // true     (max(1, 0) = 1)
:result = b or c        // neutral  (max(0, -1) = 0)
:result = not b         // neutral  (-(0) = 0)
:result = not c         // true     (-(-1) = 1)

output(result)          // prints: true
```

**Casting to/from int:**
```rex
int n = int(a)          // true → 1, neutral → 0, false → -1
bool b = bool(1)        // 1 → true, 0 → neutral, -1 → false
bool b2 = bool(5)       // any positive → true
bool b3 = bool(-3)      // any negative → false
```

**Short-circuit evaluation:**
- `and`: if the left side is `false`, the right side is never evaluated (result is `false`).
- `or`: if the left side is `true`, the right side is never evaluated (result is `true`).
- `neutral` never short-circuits — both sides are always evaluated.

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

### 4.5 `int` Methods

All methods return new values — they never mutate the source variable.
Type conversions use cast functions (`float(n)`, `str(n)`) not methods.

#### Arithmetic

| Method              | Returns | Notes                                              |
|---------------------|---------|----------------------------------------------------|
| `.abs()`            | `int`   | Absolute value                                     |
| `.min(other)`       | `int`   | Smaller of self and `other`                        |
| `.max(other)`       | `int`   | Larger of self and `other`                         |
| `.clamp(lo, hi)`    | `int`   | `lo` if below, `hi` if above, self otherwise       |
| `.pow(n)`           | `int`   | Self raised to the power `n` (integer exponentiation) |
| `.gcd(other)`       | `int`   | Greatest common divisor                            |
| `.lcm(other)`       | `int`   | Least common multiple                              |
| `.signum()`         | `int`   | −1 if negative, 0 if zero, 1 if positive           |

#### Predicates

| Method              | Returns | Notes                                              |
|---------------------|---------|----------------------------------------------------|
| `.is_zero()`        | `bool`  | `true` if value is 0                               |
| `.is_positive()`    | `bool`  | `true` if value > 0                                |
| `.is_negative()`    | `bool`  | `true` if value < 0                                |
| `.is_even()`        | `bool`  | `true` if value % 2 == 0                           |
| `.is_odd()`         | `bool`  | `true` if value % 2 != 0                           |

#### Bit Operations

| Method              | Returns | Notes                                              |
|---------------------|---------|----------------------------------------------------|
| `.popcount()`       | `int`   | Number of set bits (1s) in the 64-bit representation |
| `.leading_zeros()`  | `int`   | Count of leading zero bits (`clz`)                 |
| `.trailing_zeros()` | `int`   | Count of trailing zero bits (`ctz`)                |
| `.bit_len()`        | `int`   | Minimum bits required to represent the value       |
| `.swap_bytes()`     | `int`   | Reverse byte order (endian flip)                   |
| `.rotate_left(n)`   | `int`   | Rotate bits left by `n` positions                  |
| `.rotate_right(n)`  | `int`   | Rotate bits right by `n` positions                 |

#### String Representations

| Method              | Returns | Notes                                              |
|---------------------|---------|----------------------------------------------------|
| `.to_bin()`         | `str`   | Binary string e.g. `"1010"` (no `0b` prefix)      |
| `.to_hex()`         | `str`   | Lowercase hex e.g. `"ff"` (no `0x` prefix)        |
| `.to_oct()`         | `str`   | Octal string e.g. `"377"` (no `0o` prefix)        |

```rex
int n = -42
output(n.abs())              // 42
output(n.signum())           // -1
output(n.clamp(-100, 0))     // -42
output(n.is_negative())      // true

int x = 255
output(x.popcount())         // 8
output(x.to_hex())           // "ff"
output(x.to_bin())           // "11111111"
output(x.leading_zeros())    // 56

output(@gcd(12, 8))         // — or:
output(12.gcd(8))            // 4
output(3.pow(4))             // 81
```

---

### 4.6 `float` Methods

All methods return new values. Type conversions use cast functions.

#### Rounding

| Method        | Returns | Notes                                              |
|---------------|---------|----------------------------------------------------|
| `.ceil()`     | `int`   | Round up toward positive infinity                  |
| `.floor()`    | `int`   | Round down toward negative infinity                |
| `.round()`    | `int`   | Round to nearest integer (half rounds up)          |
| `.trunc()`    | `float` | Truncate fractional part (toward zero), keep float |
| `.fract()`    | `float` | Fractional part only (self − trunc)                |

#### Arithmetic

| Method              | Returns | Notes                                              |
|---------------------|---------|----------------------------------------------------|
| `.abs()`            | `float` | Absolute value                                     |
| `.min(other)`       | `float` | Smaller of self and `other`                        |
| `.max(other)`       | `float` | Larger of self and `other`                         |
| `.clamp(lo, hi)`    | `float` | Clamp to `[lo, hi]` range                          |
| `.signum()`         | `float` | −1.0, 0.0, or 1.0                                 |
| `.pow(n)`           | `float` | Self raised to float power `n`                     |
| `.sqrt()`           | `float` | Square root; runtime error if negative             |
| `.cbrt()`           | `float` | Cube root                                          |
| `.recip()`          | `float` | Reciprocal: 1.0 / self                             |

#### Logarithm and Exponential

| Method              | Returns | Notes                                              |
|---------------------|---------|----------------------------------------------------|
| `.exp()`            | `float` | eˣ (natural exponential)                           |
| `.ln()`             | `float` | Natural logarithm (base e)                         |
| `.log2()`           | `float` | Logarithm base 2                                   |
| `.log10()`          | `float` | Logarithm base 10                                  |
| `.log(base)`        | `float` | Logarithm with arbitrary float base                |

#### Trigonometry

| Method        | Returns | Notes                         |
|---------------|---------|-------------------------------|
| `.sin()`      | `float` | Sine (radians)                |
| `.cos()`      | `float` | Cosine (radians)              |
| `.tan()`      | `float` | Tangent (radians)             |
| `.asin()`     | `float` | Arc sine (result in radians)  |
| `.acos()`     | `float` | Arc cosine                    |
| `.atan()`     | `float` | Arc tangent                   |
| `.atan2(y)`   | `float` | Arc tangent of self/y (quadrant-aware) |
| `.to_deg()`   | `float` | Convert radians to degrees    |
| `.to_rad()`   | `float` | Convert degrees to radians    |

#### Predicates

| Method          | Returns | Notes                                              |
|-----------------|---------|----------------------------------------------------|
| `.is_nan()`     | `bool`  | `true` if not-a-number                             |
| `.is_inf()`     | `bool`  | `true` if positive or negative infinity            |
| `.is_finite()`  | `bool`  | `true` if neither NaN nor infinity                 |
| `.is_zero()`    | `bool`  | `true` if value is 0.0                             |
| `.is_positive()`| `bool`  | `true` if value > 0.0                              |
| `.is_negative()`| `bool`  | `true` if value < 0.0                              |

```rex
float f = 3.7
output(f.ceil())         // 4
output(f.floor())        // 3
output(f.round())        // 4
output(f.fract())        // 0.7
output(f.abs())          // 3.7

float pi = 3.14159
output(pi.sin())         // ~0.0
output(pi.cos())         // ~-1.0
output(pi.to_deg())      // ~180.0

float x = 2.0
output(x.sqrt())         // 1.4142...
output(x.pow(10.0))      // 1024.0
output(x.log2())         // 1.0
```

---

### 4.7 `bool` Methods

| Method           | Returns | Notes                                              |
|------------------|---------|----------------------------------------------------|
| `.is_true()`     | `bool`  | `true` only if self is `true` (value 1)            |
| `.is_false()`    | `bool`  | `true` only if self is `false` (value −1)          |
| `.is_neutral()`  | `bool`  | `true` only if self is `neutral` (value 0)         |
| `.is_decided()`  | `bool`  | `true` if self is `true` or `false` (not neutral)  |
| `.flip()`        | `bool`  | Negate: `true`↔`false`, `neutral` stays `neutral`  |
| `.to_int()`      | `int`   | `true`→1, `neutral`→0, `false`→−1                 |
| `.to_str()`      | `str`   | `"true"`, `"neutral"`, or `"false"`               |
| `.and(other)`    | `bool`  | Same as `self and other` (min)                     |
| `.or(other)`     | `bool`  | Same as `self or other` (max)                      |

```rex
bool a = true
bool b = neutral
bool c = false

output(a.is_true())      // true
output(b.is_neutral())   // true
output(c.is_decided())   // true  (false is decided)
output(b.is_decided())   // false (neutral is not decided)

output(a.flip())         // false
output(b.flip())         // neutral
output(c.flip())         // true

output(a.to_int())       // 1
output(b.to_int())       // 0
output(c.to_int())       // -1

output(a.and(b))         // neutral
output(a.or(c))          // true
```

---

### 4.8 `char` Methods

A `char` is a single UTF-8 byte. Its methods inspect and transform the character.

#### Classification

| Method              | Returns | Notes                                              |
|---------------------|---------|----------------------------------------------------|
| `.is_alpha()`       | `bool`  | Letter (a–z, A–Z)                                  |
| `.is_digit()`       | `bool`  | Decimal digit (0–9)                                |
| `.is_alnum()`       | `bool`  | Letter or digit                                    |
| `.is_whitespace()`  | `bool`  | Space, tab, newline, carriage return               |
| `.is_upper()`       | `bool`  | Uppercase letter (A–Z)                             |
| `.is_lower()`       | `bool`  | Lowercase letter (a–z)                             |
| `.is_punct()`       | `bool`  | Printable non-alphanumeric (!, @, #, …)            |
| `.is_printable()`   | `bool`  | Printable ASCII (code point 0x20–0x7E)             |
| `.is_ascii()`       | `bool`  | Value ≤ 127                                        |

#### Transformation

| Method        | Returns | Notes                                              |
|---------------|---------|----------------------------------------------------|
| `.to_upper()` | `char`  | Uppercase (A–Z only; others unchanged)             |
| `.to_lower()` | `char`  | Lowercase (a–z only; others unchanged)             |

#### Conversion

| Method        | Returns | Notes                                              |
|---------------|---------|----------------------------------------------------|
| `.to_int()`   | `int`   | UTF-8 code point (same as `int(c)`)                |
| `.to_byte()`  | `byte`  | Raw byte value (same as `byte(c)`)                 |
| `.to_str()`   | `str`   | Single-character string                            |
| `.to_digit()` | `int`   | Numeric value of `'0'`–`'9'`; −1 if not a digit   |

```rex
char c = 'R'
output(c.is_alpha())        // true
output(c.is_upper())        // true
output(c.to_lower())        // 'r'
output(c.to_int())          // 82
output(c.to_str())          // "R"

char d = '7'
output(d.is_digit())        // true
output(d.to_digit())        // 7

char sp = ' '
output(sp.is_whitespace())  // true
output(sp.is_printable())   // true
```

---

### 4.9 `byte` Methods

A `byte` is a raw unsigned 8-bit value (0–255). Methods treat it as a machine
word fragment.

#### Inspection

| Method              | Returns | Notes                                              |
|---------------------|---------|----------------------------------------------------|
| `.popcount()`       | `int`   | Number of set bits                                 |
| `.leading_zeros()`  | `int`   | Count of leading zero bits (of the 8-bit value)    |
| `.trailing_zeros()` | `int`   | Count of trailing zero bits                        |
| `.bit(n)`           | `bool`  | `true` if bit `n` is set (0 = least significant)  |

#### Transformation

| Method              | Returns | Notes                                              |
|---------------------|---------|----------------------------------------------------|
| `.rotate_left(n)`   | `byte`  | Rotate bits left by `n` within 8 bits              |
| `.rotate_right(n)`  | `byte`  | Rotate bits right by `n` within 8 bits             |
| `.swap_nibbles()`   | `byte`  | Swap upper and lower 4-bit nibbles                 |

#### Conversion

| Method        | Returns | Notes                                              |
|---------------|---------|----------------------------------------------------|
| `.to_int()`   | `int`   | Zero-extend to 64-bit integer                      |
| `.to_char()`  | `char`  | Interpret as UTF-8 byte (same as `char(b)`)        |
| `.to_hex()`   | `str`   | Two-character lowercase hex e.g. `"0f"`, `"ff"`   |
| `.to_bin()`   | `str`   | Eight-character binary string e.g. `"00001111"`   |

#### Predicates

| Method          | Returns | Notes                                              |
|-----------------|---------|----------------------------------------------------|
| `.is_zero()`    | `bool`  | `true` if value is 0                               |
| `.is_ascii()`   | `bool`  | `true` if value ≤ 127                              |

```rex
byte b = 0b10110100
output(b.popcount())         // 4
output(b.leading_zeros())    // 0
output(b.to_hex())           // "b4"
output(b.to_bin())           // "10110100"
output(b.bit(2))             // true  (bit 2 of 0b10110100 is 1)
output(b.swap_nibbles())     // 0b01001011 = 0x4B

byte x = 0xFF
output(x.rotate_left(3))     // 0xFF (all bits set, rotation unchanged)
output(x.to_char())          // char with code 255
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
For `bool`: signed integer comparison over `false (−1) < neutral (0) < true (1)`.

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
bool c = carry              // CPU carry flag after last arithmetic op → true or false
bool ov = overflow          // CPU overflow flag → true or false
int n = rand                // hardware entropy integer via rdrand
bool b = true
flip b                      // b = not b  (true→false, false→true, neutral→neutral)
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
| `bool(x)`    | `int`                         | positive → `true`, 0 → `neutral`, negative → `false` |

```rex
float f = 3.7
int i = int(f)          // 3 — truncates toward zero
str s = str(42)         // "42"
int parsed = int("42")  // 42
char c = char(65)       // 'A'
bool b = bool(5)        // true  (positive)
bool n = bool(0)        // neutral
bool fb = bool(-2)      // false (negative)
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
- Up to **65 parameters**. The first 6 are passed in registers (`rdi`, `rsi`,
  `rdx`, `rcx`, `r8`, `r9`). Parameters 7–65 are pushed right-to-left on the
  stack before the call and cleaned up by the caller after return.

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
stack one per line directly above `prot`. Rex supports both built-in
decorators and user-defined custom decorators.

#### Built-in decorators

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

#### User-defined decorators

Custom decorators are defined with the `decorator` keyword. They inject code
`before` the protocol body, `after` it, or replace the entire call with a
`wrap` block. The special token `__body__()` invokes the original protocol
body inside `wrap`.

```rex
// Simple before/after (no parameters)
decorator trace:
    before:
        output("→ entering")
    after:
        output("← exiting")

// Parameterized decorator
decorator log(str tag):
    before:
        output("→ {tag}")
    after:
        output("← {tag}")

// Wrap — replaces the call; __body__() runs original body
decorator repeat(int n):
    wrap:
        for i in 0..n:
            __body__()

// Error hook — runs if an uncaught raise exits the protocol
decorator guarded(str label):
    before:
        output("starting {label}")
    on_error:
        output("error in {label}: {__error__.msg}")
    after:
        output("done {label}")
```

Usage:

```rex
#trace
prot greet():
    output("Hello")

#log("compute")
prot compute(int x) -> int:
    return x * 2

#repeat(3)
prot announce():
    output("Rex!")

#guarded("network")
prot fetch():
    raise "IOError: connection refused"
```

**Decorator rules:**

- A decorator body may contain `before:`, `after:`, `wrap:`, and `on_error:`
  blocks. All are optional; at least one is required.
- `wrap:` is mutually exclusive with `before:`/`after:`. A decorator may
  not declare both `wrap:` and `before:`/`after:`.
- `__body__()` is only legal inside `wrap:`.
- `__error__` is a built-in `error` object only accessible inside `on_error:`.
  It has fields `.tag` (`str`) and `.msg` (`str`).
- Decorator parameters are typed, type-first, same as protocol parameters.
- A decorator defined inside a module is module-scoped; prefix with the
  module name to use it externally (`#mymod.log("x")`).

### 9.5 Error Handling — `try` / `except` / `finally` / `raise`

Rex uses Python-style structured error handling. Errors are tagged string
values; there is no class hierarchy or heap-allocated exception object.

#### `raise` — signal an error

```rex
raise "ValueError"
raise "IOError: file not found"
raise "TypeError: expected int, got str"
```

A `raise` carries a **tag** (the text before the first `:`) and an optional
**message** (the text after). The tag is used for matching in `except`.

#### `try` / `except` / `finally`

```rex
try:
    int x = @parse_int(raw)
    output(x)
except "ValueError" as e:
    output("bad value — {e.msg}")
except "IOError":
    output("I/O problem")
except:
    output("unexpected error")
finally:
    output("always runs, whether or not an error occurred")
```

- **`except "Tag" as e`** — catches errors whose tag matches exactly.
  `e` is an `error` object with fields `.tag` (`str`) and `.msg` (`str`).
- **`except "Tag"`** — catches by tag without binding the error object.
- **`except:`** (bare) — catches any uncaught error; must be the last
  `except` clause.
- **`finally:`** — always executes: after normal completion, after a caught
  error, and before re-raise propagation. Cannot contain `raise`.
- Multiple `except` clauses are checked top-to-bottom; the first match wins.
- If no `except` matches and there is no bare `except:`, the error propagates
  to the next enclosing `try` block. If no handler exists, the program
  terminates printing the tag and message to the output.

#### The `error` object

| Field   | Type  | Value                                          |
|---------|-------|------------------------------------------------|
| `.tag`  | `str` | Text before the first `:` in the raise string |
| `.msg`  | `str` | Full raise string                              |
| `.line` | `int` | Source line number of the `raise` statement   |

#### Re-raising

```rex
try:
    @risky()
except "IOError" as e:
    output("logging: {e.msg}")
    raise e.msg          // propagate upward with same message
```

#### Nested try blocks

```rex
try:
    try:
        raise "Inner"
    except "Inner":
        raise "Outer"     // propagates to outer handler
except "Outer" as e:
    output(e.tag)         // prints: Outer
```

#### Full example

```rex
prot safe_open(str path) -> str:
    if not file_exists(path):
        raise "IOError: {path} does not exist"
    with open(path, "r") as f:
        return f.read()

try:
    str data = @safe_open("config.txt")
    output(data)
except "IOError" as e:
    output("could not open file: {e.msg}")
finally:
    output("done")
```

#### Implementation model (assembly)

- A fixed global handler stack in a reserved memory region holds
  `(catch_addr, finally_addr)` pairs, one per active `try` block.
- `raise` sets two global string pointers (`[error_tag]`, `[error_msg]`),
  then pops the handler stack and jumps to `catch_addr`.
- `finally` code is emitted unconditionally at the end of the try/except
  chain and also along every path that exits the `try` block.
- An empty handler stack on `raise` terminates the program.

### 9.6 Recursion

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

All mutating methods require the `:` sigil on the receiver (e.g. `:nums.push(6)`),
except void operations that are explicitly mutating by design (marked **mut**).

---

### 10.1 Core — Size and Capacity

| Method          | Returns | Notes                                                      |
|-----------------|---------|------------------------------------------------------------|
| `.len()`        | `int`   | Number of elements currently stored                        |
| `.cap()`        | `int`   | Allocated capacity (elements before realloc)               |
| `.is_empty()`   | `bool`  | `true` if `len()` == 0                                     |
| `.clear()` **mut** | `void` | Set length to 0; capacity unchanged                      |
| `.reserve(n)` **mut** | `void` | Ensure capacity for at least `n` elements          |
| `.shrink()` **mut** | `void` | Reduce capacity to exactly `len()`                    |

### 10.2 Insertion and Removal

| Method                  | Returns | Notes                                                   |
|-------------------------|---------|---------------------------------------------------------|
| `.push(x)` **mut**      | `void`  | Append element to the end; grows if needed              |
| `.pop()` **mut**        | `T`     | Remove and return last element; error if empty          |
| `.pop_front()` **mut**  | `T`     | Remove and return first element; shifts elements left   |
| `.insert(i, x)` **mut** | `void`  | Insert `x` at index `i`; elements at `i+` shift right  |
| `.remove(i)` **mut**    | `T`     | Remove and return element at index `i`; shifts left     |
| `.extend(other)` **mut**| `void`  | Append all elements of another `seq[T]`                 |
| `.push_front(x)` **mut**| `void`  | Insert element at index 0; shifts all elements right    |

### 10.3 Access and Search

| Method               | Returns | Notes                                                      |
|----------------------|---------|------------------------------------------------------------|
| `s[i]`               | `T`     | Read at index `i`; negative indices count from end         |
| `:s[i] = v`          | `void`  | Write at index `i`                                         |
| `.first()`           | `T`     | First element; runtime error if empty                      |
| `.last()`            | `T`     | Last element; runtime error if empty                       |
| `.get(i)`            | `T`     | Same as `s[i]` — explicit form                             |
| `.contains(x)`       | `bool`  | `true` if any element equals `x`                           |
| `.index_of(x)`       | `int`   | Index of first match; −1 if not found                      |
| `.last_index_of(x)`  | `int`   | Index of last match; −1 if not found                       |
| `.count_of(x)`       | `int`   | Number of elements equal to `x`                            |
| `.find(pred)`        | `T`     | First element where predicate is `true`; error if none     |
| `.find_index(pred)`  | `int`   | Index of first matching element; −1 if none                |

### 10.4 Slicing and Copying

| Method                  | Returns    | Notes                                                |
|-------------------------|------------|------------------------------------------------------|
| `.slice(lo, hi)`        | `seq[T]`   | New seq from index `lo` to `hi` (exclusive)          |
| `.slice_from(lo)`       | `seq[T]`   | From index `lo` to end                               |
| `.slice_to(hi)`         | `seq[T]`   | From start to index `hi` (exclusive)                 |
| `.take(n)`              | `seq[T]`   | First `n` elements as a new seq                      |
| `.drop(n)`              | `seq[T]`   | All elements after skipping the first `n`            |
| `.copy()`               | `seq[T]`   | Shallow copy of the entire seq                       |

### 10.5 Ordering

| Method                   | Returns | Notes                                                   |
|--------------------------|---------|---------------------------------------------------------|
| `.sort()` **mut**        | `void`  | Sort ascending in place (comparison via `<`)            |
| `.sort_desc()` **mut**   | `void`  | Sort descending in place                                |
| `.sort_by(cmp)` **mut**  | `void`  | Sort in place using custom comparator `fn(T, T) -> int` |
| `.reverse()` **mut**     | `void`  | Reverse elements in place                               |
| `.is_sorted()`           | `bool`  | `true` if elements are in non-decreasing order          |
| `.min()`                 | `T`     | Smallest element; error if empty                        |
| `.max()`                 | `T`     | Largest element; error if empty                         |
| `.min_index()`           | `int`   | Index of the smallest element                           |
| `.max_index()`           | `int`   | Index of the largest element                            |

### 10.6 Math Aggregates

Only valid for `seq[int]` and `seq[float]`.

| Method       | Returns | Notes                                                         |
|--------------|---------|---------------------------------------------------------------|
| `.sum()`     | `T`     | Sum of all elements                                           |
| `.product()` | `T`     | Product of all elements                                       |
| `.mean()`    | `float` | Arithmetic mean (always float)                               |
| `.median()`  | `float` | Median value (always float; sorts a copy internally)          |

### 10.7 Set Operations

Both sequences must have the same element type `T`.

| Method              | Returns  | Notes                                              |
|---------------------|----------|----------------------------------------------------|
| `.unique()`         | `seq[T]` | New seq with duplicate elements removed (order kept) |
| `.union(other)`     | `seq[T]` | All elements from both, duplicates removed         |
| `.intersect(other)` | `seq[T]` | Elements present in both                           |
| `.diff(other)`      | `seq[T]` | Elements in self but not in `other`                |

### 10.8 Transformation (Functional)

| Method                   | Returns  | Notes                                              |
|--------------------------|----------|----------------------------------------------------|
| `.map(fn(T) -> U)`       | `seq[U]` | Apply function to each element, collect results    |
| `.filter(fn(T) -> bool)` | `seq[T]` | Keep elements where predicate is `true`            |
| `.reduce(init, fn(acc T, x T) -> T)` | `T` | Fold left with initial accumulator       |
| `.flat()`                | `seq[U]` | Flatten one level: `seq[seq[U]]` → `seq[U]`       |
| `.flat_map(fn(T) -> seq[U])` | `seq[U]` | Map then flatten                              |
| `.zip(other)`            | `seq[tup[T, U]]` | Pair elements by index; length = shorter  |
| `.enumerate()`           | `seq[tup[int, T]]` | Pair each element with its index          |
| `.each(fn(T))`           | `void`   | Call function on each element (side effects)       |
| `.each_index(fn(int, T))`| `void`   | Call function with index and element               |

### 10.9 Predicates

| Method                    | Returns | Notes                                             |
|---------------------------|---------|---------------------------------------------------|
| `.any(fn(T) -> bool)`     | `bool`  | `true` if predicate holds for at least one element |
| `.all(fn(T) -> bool)`     | `bool`  | `true` if predicate holds for all elements        |
| `.none(fn(T) -> bool)`    | `bool`  | `true` if predicate holds for no elements         |
| `.count(fn(T) -> bool)`   | `int`   | Number of elements where predicate is `true`      |

### 10.10 Conversion

| Method           | Returns    | Notes                                                  |
|------------------|------------|--------------------------------------------------------|
| `.to_str()`      | `str`      | `"[1, 2, 3]"` style representation                    |
| `.join(sep)`     | `str`      | Join with separator string; `T` must be `str` or `char` |
| `.to_arr()`      | `arr[T, N]`| Only valid if size is compile-time known               |

```rex
seq[int] nums = [5, 3, 8, 1, 9, 2]

// Insertion / removal
:nums.push(10)
int last = nums.pop()          // 10
:nums.insert(2, 99)            // [5, 3, 99, 8, 1, 9, 2]

// Search
output(nums.contains(8))       // true
output(nums.index_of(99))      // 2
output(nums.find(fn(int x) -> bool: x > 7))  // 99

// Sorting and slicing
:nums.sort()                   // [1, 2, 3, 5, 8, 9, 99]
seq[int] top = nums.slice(4, 7) // [8, 9, 99]
seq[int] head = nums.take(3)   // [1, 2, 3]

// Functional
seq[int] doubled = nums.map(fn(int x) -> int: x * 2)
seq[int] small = nums.filter(fn(int x) -> bool: x < 10)
int total = nums.reduce(0, fn(int acc, int x) -> int: acc + x)
output(nums.sum())             // 127
output(nums.mean())            // 18.14...

// Sets
seq[int] a = [1, 2, 3, 4]
seq[int] b = [3, 4, 5, 6]
output(a.intersect(b))         // [3, 4]
output(a.diff(b))              // [1, 2]
output(a.unique())             // [1, 2, 3, 4] (no change, already unique)
```

---

## 11. Fixed Arrays

Stack-allocated, size known at compile time. `N` must be a compile-time constant.

```rex
arr[int, 8] buf                         // uninitialized
arr[float, 3] v = [1.0, 0.0, 0.0]      // literal initialisation
arr[byte, 16] key = [0] * 16           // zero-fill
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

### 11.1 Access

| Method / Syntax  | Returns | Notes                                                      |
|------------------|---------|------------------------------------------------------------|
| `a[i]`           | `T`     | Read at index `i`; negative indices count from end         |
| `:a[i] = v`      | `void`  | Write at index `i`; in-place, no realloc                   |
| `.first()`       | `T`     | First element                                              |
| `.last()`        | `T`     | Last element                                               |
| `.len()`         | `int`   | Always returns `N` (compile-time constant)                 |
| `.is_empty()`    | `bool`  | Always `false` for `N > 0`                                 |

### 11.2 Search

| Method               | Returns | Notes                                                      |
|----------------------|---------|------------------------------------------------------------|
| `.contains(x)`       | `bool`  | Linear scan; `true` if any element equals `x`              |
| `.index_of(x)`       | `int`   | Index of first match; −1 if not found                      |
| `.count_of(x)`       | `int`   | Number of elements equal to `x`                            |
| `.find(pred)`        | `T`     | First element where predicate is `true`; error if none     |
| `.find_index(pred)`  | `int`   | Index of first matching element; −1 if none                |
| `.min()`             | `T`     | Smallest element                                           |
| `.max()`             | `T`     | Largest element                                            |

### 11.3 Slicing

| Method               | Returns     | Notes                                                  |
|----------------------|-------------|--------------------------------------------------------|
| `.slice(lo, hi)`     | `seq[T]`    | New heap seq from index `lo` to `hi` (exclusive)       |
| `.slice_from(lo)`    | `seq[T]`    | From index `lo` to end                                 |
| `.slice_to(hi)`      | `seq[T]`    | From start to index `hi`                               |
| `.take(n)`           | `seq[T]`    | First `n` elements as a heap seq                       |
| `.drop(n)`           | `seq[T]`    | Elements after skipping the first `n`                  |

### 11.4 Ordering

| Method                   | Returns | Notes                                                   |
|--------------------------|---------|---------------------------------------------------------|
| `.sort()` **mut**        | `void`  | Sort in place ascending                                 |
| `.sort_desc()` **mut**   | `void`  | Sort in place descending                                |
| `.sort_by(cmp)` **mut**  | `void`  | Sort in place with custom comparator                    |
| `.reverse()` **mut**     | `void`  | Reverse elements in place                               |
| `.is_sorted()`           | `bool`  | `true` if elements are in non-decreasing order          |

### 11.5 Math Aggregates

Only valid for `arr[int, N]` and `arr[float, N]`.

| Method       | Returns | Notes                    |
|--------------|---------|--------------------------|
| `.sum()`     | `T`     | Sum of all elements       |
| `.product()` | `T`     | Product of all elements   |
| `.mean()`    | `float` | Arithmetic mean           |

### 11.6 Functional

| Method                   | Returns  | Notes                                           |
|--------------------------|----------|-------------------------------------------------|
| `.map(fn(T) -> U)`       | `seq[U]` | Apply function to each element; result is a seq |
| `.filter(fn(T) -> bool)` | `seq[T]` | Collect matching elements into a seq            |
| `.reduce(init, fn)`      | `T`      | Fold left                                       |
| `.each(fn(T))`           | `void`   | Call function on each element                   |
| `.any(fn(T) -> bool)`    | `bool`   | `true` if predicate holds for at least one      |
| `.all(fn(T) -> bool)`    | `bool`   | `true` if predicate holds for all               |
| `.none(fn(T) -> bool)`   | `bool`   | `true` if predicate holds for none              |

### 11.7 Conversion

| Method         | Returns    | Notes                                                   |
|----------------|------------|---------------------------------------------------------|
| `.to_seq()`    | `seq[T]`   | Copy elements into a new heap-allocated sequence        |
| `.copy()`      | `arr[T, N]`| Stack copy of the entire array                          |

```rex
arr[int, 5] a = [4, 2, 7, 1, 9]

output(a.len())          // 5
output(a.first())        // 4
output(a.last())         // 9
output(a.contains(7))    // true
output(a.index_of(7))    // 2
output(a.min())          // 1
output(a.max())          // 9
output(a.sum())          // 23

:a.sort()
output(a[0])             // 1
output(a[4])             // 9

seq[int] big = a.filter(fn(int x) -> bool: x > 4)
output(big)              // [7, 9]

seq[int] copy = a.to_seq()
```

---

## 12. Dictionaries

SipHash-2-4 internally. Keys are always `str`. Value type is declared in `[T]`.
Heap-allocated, grows automatically. Iteration order is insertion order.

```rex
dict[int] scores                                        // empty
dict[int] scores = {"alice": 95, "bob": 87}            // literal init
dict[str] config = {"host": "localhost", "port": "8080"}
```

---

### 12.1 Access and Lookup

| Method / Syntax            | Returns | Notes                                                       |
|----------------------------|---------|-------------------------------------------------------------|
| `d[key]`                   | `T`     | Read; runtime error if key not present                      |
| `:d[key] = val`            | `void`  | Write; inserts if key absent, overwrites if present         |
| `.get(key)`                | `T`     | Same as `d[key]` — explicit form                            |
| `.get_or(key, default)`    | `T`     | Returns `default` if key absent; does not insert            |
| `.get_or_set(key, default)`| `T`     | Inserts `default` if absent, then returns stored value      |
| `.has(key)`                | `bool`  | `true` if key exists                                        |
| `.is_empty()`              | `bool`  | `true` if no entries                                        |
| `.len()`                   | `int`   | Number of key-value pairs                                   |

Missing-key access via `d[key]` or `.get()` is a **runtime error**. Always
guard with `.has()` or use `.get_or()`.

### 12.2 Insertion and Removal

| Method                         | Returns | Notes                                                  |
|--------------------------------|---------|--------------------------------------------------------|
| `.remove(key)` **mut**         | `T`     | Remove and return the value; error if key absent       |
| `.remove_if(key)` **mut**      | `bool`  | Remove if present; return `true` if it existed         |
| `.clear()` **mut**             | `void`  | Remove all entries                                     |
| `.update(other)` **mut**       | `void`  | Merge `other` into self; `other` wins on conflict      |
| `.update_if_absent(other)` **mut** | `void` | Merge `other`; self wins on conflict (no overwrites) |
| `.set_if_absent(key, val)` **mut** | `bool` | Insert only if key is not present; return `true` if inserted |

### 12.3 Keys, Values, and Pairs

| Method        | Returns      | Notes                                                    |
|---------------|--------------|----------------------------------------------------------|
| `.keys()`     | `seq[str]`   | All keys in insertion order                              |
| `.values()`   | `seq[T]`     | All values in insertion order                            |
| `.pairs()`    | `seq[tup[str, T]]` | All key-value pairs in insertion order           |
| `.copy()`     | `dict[T]`    | Shallow copy of the entire dict                          |

### 12.4 Functional

| Method                              | Returns   | Notes                                          |
|-------------------------------------|-----------|------------------------------------------------|
| `.each(fn(str, T))`                 | `void`    | Call function on every key-value pair          |
| `.map(fn(str, T) -> U)`             | `dict[U]` | New dict with values transformed               |
| `.map_keys(fn(str, T) -> str)`      | `dict[T]` | New dict with keys transformed; must stay unique |
| `.filter(fn(str, T) -> bool)`       | `dict[T]` | New dict with only matching pairs              |
| `.reduce(init, fn(acc R, str, T) -> R)` | `R`   | Fold over all pairs                            |

### 12.5 Predicates

| Method                        | Returns | Notes                                              |
|-------------------------------|---------|---------------------------------------------------|
| `.any(fn(str, T) -> bool)`    | `bool`  | `true` if predicate holds for at least one pair   |
| `.all(fn(str, T) -> bool)`    | `bool`  | `true` if predicate holds for all pairs           |
| `.none(fn(str, T) -> bool)`   | `bool`  | `true` if predicate holds for no pairs            |
| `.count(fn(str, T) -> bool)`  | `int`   | Number of pairs where predicate is `true`         |

### 12.6 Set Operations on Keys

| Method             | Returns   | Notes                                                   |
|--------------------|-----------|----------------------------------------------------------|
| `.invert()`        | `dict[str]` | Swap keys and values; `T` must be `str`              |
| `.key_union(other)` | `seq[str]` | All distinct keys from both dicts                   |
| `.key_intersect(other)` | `seq[str]` | Keys present in both dicts                    |
| `.key_diff(other)` | `seq[str]` | Keys in self but not in `other`                      |

```rex
dict[int] scores = {"alice": 95, "bob": 87, "carol": 72}

// Access
output(scores["alice"])                // 95
output(scores.get_or("dave", 0))       // 0
output(scores.has("carol"))            // true

// Mutation
:scores["dave"] = 88
scores.remove("bob")
output(scores.len())                   // 3

// Keys / values
seq[str] ks = scores.keys()           // ["alice", "carol", "dave"] (insertion order)
seq[int] vs = scores.values()         // [95, 72, 88]

// Functional
dict[int] high = scores.filter(fn(str k, int v) -> bool: v >= 80)
dict[str] labels = scores.map(fn(str k, int v) -> str: fmt("{v} pts"))
bool any_perfect = scores.any(fn(str k, int v) -> bool: v == 100)

// Set ops
dict[int] extras = {"eve": 91, "alice": 60}
scores.update(extras)                  // alice becomes 60 (extras wins)
output(scores.key_intersect(extras))   // ["alice"]
```

---

## 13. Strings

Heap-managed UTF-8. Header layout: `[capacity: 8][length: 8][data: N]`.
All methods return **new strings** — the source string is never mutated.
Reassignment uses the `:` sigil: `:s = s.upper()`.

### 13.1 Operators

| Operator / Syntax | Returns | Notes                                                   |
|-------------------|---------|---------------------------------------------------------|
| `s + t`           | `str`   | Concatenate two strings                                 |
| `s * n`           | `str`   | Repeat `s` exactly `n` times                            |
| `s[i]`            | `char`  | Character at index `i`; negative counts from end        |
| `s == t`          | `bool`  | Byte-for-byte equality                                  |
| `s < t`           | `bool`  | Lexicographic ordering                                  |
| `s in t`          | `bool`  | `true` if `s` is a substring of `t`                    |

### 13.2 Size and Inspection

| Method            | Returns | Notes                                                   |
|-------------------|---------|---------------------------------------------------------|
| `.len()`          | `int`   | Byte count (UTF-8; may differ from character count)     |
| `.is_empty()`     | `bool`  | `true` if `len()` == 0                                  |
| `.char_count()`   | `int`   | Number of UTF-8 code points (≤ `len()`)                 |

### 13.3 Case and Whitespace

| Method            | Returns | Notes                                                   |
|-------------------|---------|---------------------------------------------------------|
| `.upper()`        | `str`   | New uppercase copy (ASCII only)                         |
| `.lower()`        | `str`   | New lowercase copy (ASCII only)                         |
| `.trim()`         | `str`   | Strip leading and trailing whitespace                   |
| `.trim_left()`    | `str`   | Strip leading whitespace only                           |
| `.trim_right()`   | `str`   | Strip trailing whitespace only                          |
| `.trim_char(c)`   | `str`   | Strip specific char from both ends                      |

### 13.4 Search and Testing

| Method                   | Returns | Notes                                                 |
|--------------------------|---------|-------------------------------------------------------|
| `.contains(sub)`         | `bool`  | `true` if `sub` appears anywhere                      |
| `.starts_with(prefix)`   | `bool`  | `true` if string begins with `prefix`                 |
| `.ends_with(suffix)`     | `bool`  | `true` if string ends with `suffix`                   |
| `.index_of(sub)`         | `int`   | First index of `sub`; −1 if not found                 |
| `.last_index_of(sub)`    | `int`   | Last index of `sub`; −1 if not found                  |
| `.count(sub)`            | `int`   | Non-overlapping occurrences of `sub`                  |
| `.find(pred)`            | `char`  | First character where predicate is `true`; error if none |

### 13.5 Slicing and Splitting

| Method                   | Returns    | Notes                                              |
|--------------------------|------------|----------------------------------------------------|
| `.slice(lo, hi)`         | `str`      | New substring from byte index `lo` to `hi` (exclusive) |
| `.slice_from(lo)`        | `str`      | From byte index `lo` to end                        |
| `.slice_to(hi)`          | `str`      | From start to byte index `hi`                      |
| `.take(n)`               | `str`      | First `n` bytes as a new string                    |
| `.drop(n)`               | `str`      | All bytes after skipping the first `n`             |
| `.split(sep)`            | `seq[str]` | Split on separator string                          |
| `.split_char(c)`         | `seq[str]` | Split on a single char delimiter                   |
| `.lines()`               | `seq[str]` | Split on `\n` (strips trailing newline if present) |
| `.words()`               | `seq[str]` | Split on any run of whitespace                     |

### 13.6 Transformation

| Method                        | Returns | Notes                                              |
|-------------------------------|---------|----------------------------------------------------|
| `.replace(old, new)`          | `str`   | Replace first occurrence of `old` with `new`       |
| `.replace_all(old, new)`      | `str`   | Replace all non-overlapping occurrences            |
| `.reverse()`                  | `str`   | New reversed string                                |
| `.repeat(n)`                  | `str`   | Repeat string `n` times                            |
| `.insert(i, sub)`             | `str`   | New string with `sub` inserted at byte index `i`   |
| `.remove_at(i, n)`            | `str`   | New string with `n` bytes removed at index `i`     |

### 13.7 Padding and Alignment

| Method                     | Returns | Notes                                                 |
|----------------------------|---------|-------------------------------------------------------|
| `.pad_left(width, fill)`   | `str`   | Right-align in `width` chars, filled with `fill` char |
| `.pad_right(width, fill)`  | `str`   | Left-align in `width` chars, filled with `fill` char  |
| `.center(width, fill)`     | `str`   | Center in `width` chars, filled with `fill` char      |

### 13.8 Joining and Iterating

| Method               | Returns     | Notes                                                  |
|----------------------|-------------|--------------------------------------------------------|
| `.join(parts)`       | `str`       | Self is separator; `parts` is `seq[str]`               |
| `.chars()`           | `seq[char]` | Sequence of individual characters                      |
| `.bytes()`           | `seq[byte]` | Sequence of raw byte values                            |
| `.each(fn(char))`    | `void`      | Call function on each character                        |

### 13.9 Conversion and Parsing

| Method        | Returns | Notes                                                    |
|---------------|---------|----------------------------------------------------------|
| `.to_int()`   | `int`   | Parse decimal integer; runtime error if invalid          |
| `.to_float()` | `float` | Parse float; runtime error if invalid                    |
| `.to_upper()` | `str`   | Alias for `.upper()`                                     |
| `.to_lower()` | `str`   | Alias for `.lower()`                                     |
| `.to_bytes()` | `seq[byte]` | Same as `.bytes()`                                   |
| `.to_chars()` | `seq[char]` | Same as `.chars()`                                   |

### 13.10 Predicates

| Method               | Returns | Notes                                                   |
|----------------------|---------|---------------------------------------------------------|
| `.is_alpha()`        | `bool`  | All characters are letters (a–z, A–Z)                   |
| `.is_digit()`        | `bool`  | All characters are decimal digits                        |
| `.is_alnum()`        | `bool`  | All characters are letters or digits                    |
| `.is_whitespace()`   | `bool`  | All characters are whitespace                           |
| `.is_ascii()`        | `bool`  | All bytes ≤ 127                                         |
| `.is_upper()`        | `bool`  | All alphabetic characters are uppercase                 |
| `.is_lower()`        | `bool`  | All alphabetic characters are lowercase                 |

### 13.11 String Interpolation

All Rex string literals support `{expr}` interpolation — no prefix needed:

```rex
output("x is {x} and y is {y}")
output("result: {a + b}")
output("fib(10) = {@fib(10)}")
output("{{not interpolated}}")     // literal {
```

Any valid Rex expression is allowed inside `{ }`.

### 13.12 Format Specifiers

A `:` inside `{}` activates format mode:

```rex
output("pi = {pi:.2f}")            // 3.14
output("{n:08b}")                  // 00001111
output("{n:x}")                    // ff (hex lowercase)
output("{n:X}")                    // FF (hex uppercase)
output("{n:10d}")                  // right-aligned, space-padded
output("{name:10s}")               // left-aligned, space-padded
```

```rex
str s = "  Hello, Rex!  "
output(s.trim())                   // "Hello, Rex!"
output(s.lower())                  // "  hello, rex!  "
output(s.contains("Rex"))          // true
output(s.index_of("Rex"))          // 9
output(s.replace("Rex", "World"))  // "  Hello, World!  "
output(s.split(", "))             // ["  Hello", "Rex!  "]
output(s.words())                  // ["Hello,", "Rex!"]
output(s.trim().reverse())         // "!xeR ,olleH"
output(s.trim().chars().len())     // 13

str greeting = "hi"
output(greeting.pad_left(10, '.'))  // "........hi"
output(greeting.center(10, '-'))    // "----hi----"
output(greeting.repeat(3))         // "hihihi"

seq[str] parts = ["one", "two", "three"]
output(", ".join(parts))           // "one, two, three"
```

---

## 14. Tuples

Tuples are fixed-size, heterogeneous, stack-allocated, and immutable by default.
The types and count of elements are part of the type signature.

```rex
tup[int, str] pair = (42, "hello")
tup[float, float, float] vec3 = (1.0, 0.0, 0.0)
tup[int, bool, str] triple = (7, true, "yes")
```

Elements are accessed positionally using `.0`, `.1`, `.2`, etc.
Tuples are value types — assignment copies all elements.

```rex
int n = pair.0          // 42
str s = pair.1          // "hello"
```

---

### 14.1 Access

| Syntax / Method     | Returns | Notes                                                        |
|---------------------|---------|--------------------------------------------------------------|
| `t.0`, `t.1`, …    | `T_i`   | Field access by zero-based index; type known at compile time |
| `.len()`            | `int`   | Always the arity declared in the type (compile-time constant)|
| `.copy()`           | same    | Stack copy of the tuple                                      |

### 14.2 Conversion

| Method        | Returns     | Notes                                                         |
|---------------|-------------|---------------------------------------------------------------|
| `.to_seq()`   | `seq[T]`    | Only valid when **all** elements share the same type `T`      |
| `.to_str()`   | `str`       | `"(42, "hello")"` style representation                       |
| `.values()`   | spreads to stack | Unpack all fields (used in destructuring assignment)    |

### 14.3 Destructuring

Tuples can be unpacked into individual variables using a destructuring assignment.
Each target must be declared before the assignment.

```rex
tup[int, str] pair = (42, "hello")

int n
str s
:n, :s = pair           // n = 42, s = "hello"
```

Multiple return values from protocols are tuples at the call site:

```rex
prot minmax(seq[int] vals) -> (int, int):
    // ...
    return 1, 99

int lo
int hi
:lo, :hi = @minmax(nums)
```

### 14.4 Comparison and Predicates

| Method / Operator   | Returns | Notes                                                        |
|---------------------|---------|--------------------------------------------------------------|
| `t == u`            | `bool`  | Element-wise equality; both must have the same type          |
| `t != u`            | `bool`  | `not (t == u)`                                               |
| `.is_empty()`       | `bool`  | Always `false` — tuples always have at least one element     |

### 14.5 Usage Notes

- Tuples are **immutable by default**. Mutable tuple fields are not supported.
  To mutate, unpack into variables, mutate, then construct a new tuple.
- The element count `N` and each element type `T_i` must be known at
  compile time. Tuples of unknown arity cannot be created at runtime.
- Nesting is allowed: `tup[tup[int, int], str]`.
- Tuples with one element (`tup[T]`) are allowed but unusual; prefer using
  the type directly.

```rex
tup[int, float, str] t = (10, 3.14, "Rex")

output(t.0)                    // 10
output(t.1)                    // 3.14
output(t.2)                    // "Rex"
output(t.len())                // 3
output(t.to_str())             // "(10, 3.14, "Rex")"

// Destructuring
int a
float b
str c
:a, :b, :c = t                 // a=10, b=3.14, c="Rex"

// Homogeneous tuple → seq
tup[int, int, int] rgb = (255, 128, 0)
seq[int] ch = rgb.to_seq()     // [255, 128, 0]

// Comparison
tup[int, str] x = (1, "a")
tup[int, str] y = (1, "a")
output(x == y)                 // true
```

---

## 15. I/O

### 14.1 Output

```rex
output(x)           // print x followed by newline (type-dispatched)
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

### 15.4 File I/O — `with open`

Rex uses Python-style `with open(...) as var:` for file access. The file is
automatically closed when the block exits.
Manual `.close()` is not needed inside a `with` block.

```rex
with open("data.txt", "r") as f:
    str contents = f.read()
    output(contents)

with open("log.txt", "w") as f:
    f.writeln("started")
    f.writeln("done")

with open("image.png", "rb") as f:
    seq[byte] raw = f.read_bytes(f.size())
```

**Open modes:**

| Mode  | Meaning                                               |
|-------|-------------------------------------------------------|
| `"r"` | Read text (UTF-8); error if file does not exist       |
| `"w"` | Write text; creates or truncates                      |
| `"a"` | Append text; creates if absent; never truncates       |
| `"rb"`| Read raw bytes                                        |
| `"wb"`| Write raw bytes; creates or truncates                 |
| `"ab"`| Append raw bytes                                      |
| `"r+"`| Read and write; file must exist                       |
| `"w+"`| Read and write; creates or truncates                  |

**File handle methods:**

| Method                | Returns    | Notes                                                  |
|-----------------------|------------|--------------------------------------------------------|
| `.read()`             | `str`      | Read entire file as a string (text modes)              |
| `.read_line()`        | `str`      | Read one line including `\n`; empty at EOF             |
| `.read_bytes(n)`      | `seq[byte]`| Read exactly `n` bytes; fewer at EOF                  |
| `.read_all_bytes()`   | `seq[byte]`| Read entire file as bytes (binary modes)               |
| `.lines()`            | `seq[str]` | Read all lines, each stripped of trailing `\n`         |
| `.write(s)`           | `void`     | Write string or bytes; no newline added                |
| `.writeln(s)`         | `void`     | Write string and append `\n`                           |
| `.write_bytes(buf)`   | `void`     | Write raw `seq[byte]` or `arr[byte, N]`                |
| `.seek(n)`            | `void`     | Seek to byte offset `n` from start                     |
| `.seek_end(n)`        | `void`     | Seek `n` bytes before end (e.g. `.seek_end(0)` = EOF) |
| `.pos()`              | `int`      | Current byte position                                  |
| `.size()`             | `int`      | Total file size in bytes                               |
| `.is_eof()`           | `bool`     | `true` if at end of file                               |
| `.flush()`            | `void`     | Flush write buffer to OS                               |
| `.path()`             | `str`      | File path as given to `open`                           |

**Reading line by line:**

```rex
with open("words.txt", "r") as f:
    while not f.is_eof():
        str line = f.read_line()
        if line.is_empty():
            stop
        output(line.trim())
```

**Using `.lines()` (reads whole file at once):**

```rex
with open("words.txt", "r") as f:
    each line in f.lines():
        output(line.upper())
```

**Writing and flushing:**

```rex
with open("output.txt", "w") as f:
    for i in 0..100:
        f.writeln("line {i}")
    f.flush()
```

**Binary copy:**

```rex
with open("a.bin", "rb") as src:
    with open("b.bin", "wb") as dst:
        dst.write_bytes(src.read_all_bytes())
```

**Error handling:**
If `open` fails (file not found for `"r"`, permission denied, etc.),
Rex raises a runtime error with a descriptive message and exits with
code 1. Wrap in a checked file-existence test if needed:

```rex
// Check first, then open
bool exists = file_exists("data.txt")
if not exists:
    output("data.txt not found")

with open("data.txt", "r") as f:
    output(f.read())
```

`file_exists(path)` is a built-in that returns `bool` without opening the file.

---

## 16. Memory Management

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

## 17. Module System

Rex modules are the unit of namespace and code organisation. A module is
either an **inline block** inside the current file or a **file module**
(`name.rex` in the same directory). There is no package registry; all
resolution is local and compile-time.

### 17.1 Defining a Module

#### Inline module

```rex
module math:
    prot add(int a, int b) -> int:
        return a + b

    prot sub(int a, int b) -> int:
        return a - b

    // Private — prefix _ makes it invisible outside the module
    prot _clamp(int x, int lo, int hi) -> int:
        if x < lo: return lo
        if x > hi: return hi
        return x
```

#### File module

Any `.rex` file in the same directory is automatically a module. The module
name is the filename without extension.

```
project/
    main.rex
    math.rex        ← module math
    io_utils.rex    ← module io_utils
```

No declaration is needed in the file itself — the filename determines the
module name.

### 17.2 Importing with `use`

```rex
use math                // all public names qualified: math.add(...)
use math: add           // add imported unqualified: @add(...)
use math: add, sub      // multiple selective imports
use math: *             // all public names, unqualified
```

Qualified call (always works after any form of `use`):

```rex
int r = math.add(3, 4)
```

Unqualified call (only after `use math: add` or `use math: *`):

```rex
int s = @add(3, 4)
```

### 17.3 Visibility Rules

| Name pattern     | Visible outside module? |
|------------------|------------------------|
| `prot name`      | Yes (public)           |
| `prot _name`     | No (private)           |
| `int global_var` | Yes (public)           |
| `int _global`    | No (private)           |

There are no `pub` / `private` keywords — underscore prefix is the sole
visibility marker.

### 17.4 Standard Library Modules

| Module   | Contents                                              |
|----------|-------------------------------------------------------|
| `io`     | File open/read/write/close; stdin; buffered I/O       |
| `os`     | Process exit, environment variables, command-line args|
| `math`   | Trig, sqrt, pow, log, min, max, floor, ceil           |
| `str`    | String search, split, trim, pad, replace, encode      |
| `rand`   | Seeded PRNG, random int/float, shuffle                |
| `time`   | Monotonic clock, sleep, timestamps                    |
| `mem`    | Low-level memory copy, fill, compare                  |

Standard library modules are resolved at compile time. No dynamic loading.

### 17.5 Module-scoped Decorators

A decorator defined inside a module is scoped to that module. To use it
externally:

```rex
// in logger.rex
module logger:
    decorator log(str tag):
        before: output("→ {tag}")
        after:  output("← {tag}")

// in main.rex
use logger: log

#log("main")
prot run():
    output("running")
```

### 17.6 Circular Imports

Circular imports are a **compile-time error**. Pass 2 (Symbol Collection)
detects cycles and reports all modules involved.

```rex
use math:               // import stdlib math module
    float r = sqrt(2.0)

use io:                 // import stdlib io module
    // file, stdin, stdout operations
```

Modules resolve at compile time. No runtime dynamic loading.

---

## 18. Compiler Pipeline

Rex uses a **multi-pass** architecture. Each pass operates on a well-defined
data structure and has a single, bounded responsibility. No pass peeks ahead
into a later pass's concern.

```
source.rex
    │
    ▼
┌─────────────────────────────────────────────────────────────────┐
│  PASS 1 — Lexer                                                  │
│  Read the entire source file once.                               │
│  Emit a flat token array:                                        │
│      TOK_INT, TOK_IDENT, TOK_IF, TOK_FOR, TOK_NEWLINE, …        │
│  Track INDENT / DEDENT from column changes.                      │
│  Strip comments and blank lines.                                 │
│  Output: token_buf[]  (immutable for all later passes)           │
└─────────────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────────────┐
│  PASS 2 — Symbol Collection                                      │
│  Walk token_buf once without emitting code.                      │
│  Record every top-level declaration:                             │
│    • Protocol name, return type, parameter names and types       │
│    • Global variable name and declared type                      │
│    • Module imports                                              │
│  Populate proto_table and var_table headers.                     │
│  Output: complete proto_table[], var_table[] (names + types)     │
│  Effect: forward references to any protocol are now legal.       │
│  Mutual recursion is resolved without pre-declaration stubs.     │
└─────────────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────────────┐
│  PASS 3 — Type Checking & IR Emission                            │
│  Recursive-descent parse of token_buf.                           │
│  Full type knowledge available (proto_table complete).           │
│  Type-check every expression; reject mismatches at this pass.    │
│  Fill in var_table entries (mutability, initialisation flag).    │
│  Emit IR records into ir_buf[].                                  │
│  Output: ir_buf[]  (32-byte records, one per compiler op)        │
└─────────────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────────────┐
│  PASS 4 — IR Optimisation (5 sub-passes, iterated until stable)  │
│  4a: Constant folding         — collapse compile-time exprs      │
│  4b: Dead store elimination   — remove stores never read         │
│  4c: Load-store coalescing    — collapse redundant pairs         │
│  4d: Linear scan reg alloc    — map vregs → physical registers   │
│  4e: Peephole optimisation    — collapse adjacent instr pairs    │
│  Output: optimised ir_buf[]                                      │
└─────────────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────────────┐
│  PASS 5 — x86-64 Emission                                        │
│  Walk ir_buf[], convert each record to machine bytes.            │
│  IR_NOP records silently skipped.                                │
│  Forward jumps patched via a label-resolution table.             │
│  Output: code_buf[]  (raw machine bytes)                         │
└─────────────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────────────┐
│  PASS 6 — ELF64 Writer                                           │
│  Prepend 120-byte ELF64 header + program header (LOAD, RWX).    │
│  Emit a 5-byte JMP past runtime blobs to user code start.       │
│  Inline all runtime blobs (print, alloc, hash).                  │
│  Append code_buf[].                                              │
│  Write complete binary to disk in one syscall — no linker.       │
│  Output: ./output  (self-contained ELF64 executable)            │
└─────────────────────────────────────────────────────────────────┘
    │
    ▼
  ./output   (self-contained ELF64 binary)
```

**Why multi-pass matters:**

| Benefit                        | Single-pass limit              | Multi-pass solution                      |
|-------------------------------|--------------------------------|------------------------------------------|
| Forward references            | Required pre-declaration stubs | Pass 2 collects all names first          |
| Mutual recursion              | Impossible without workarounds | Natural — both protos known before pass 3 |
| Whole-program type checking   | Only sees declarations so far  | Full symbol table available in pass 3    |
| Dead code at program scope    | Cannot detect cross-function   | Pass 4b sees full IR of all protocols    |
| Constant propagation          | Bounded to one scope           | Pass 4a can fold across protocol calls   |

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

### 18.3 Implementation Mandate — Assembly-First & Self-Hosting Goal

**Rex must be implemented strictly in x86-64 assembly (NASM syntax). No C,
no C++, no other compiled language is permitted anywhere in the compiler,
runtime, or standard library blobs.** Every byte of the toolchain — lexer,
parser, IR buffer, optimiser, code emitter, ELF writer, and all runtime blobs
— is hand-written assembly.

This is a deliberate and non-negotiable constraint, not a temporary measure.
Reasons:

1. **Total control.** Assembly allows exact knowledge of every instruction
   emitted, every byte of the binary, and every memory access. There are no
   hidden costs introduced by a host compiler's code generation.

2. **Zero-dependency proof.** If the compiler itself links no external
   libraries, it demonstrates that the language it compiles can also link none.
   The toolchain must eat its own cooking.

3. **Auditability.** A systems language whose compiler cannot be read and
   understood at the machine level is a systems language in name only. The
   full compiler must be auditable by any programmer who understands x86-64.

4. **Bootstrap simplicity.** One NASM invocation produces the compiler binary.
   No build system, no package manager, no host-language runtime is needed to
   build Rex from source.

#### Ultimate Goal — Rex Self-Hosting

The long-term goal of the Rex project is **full self-hosting**: the Rex
compiler is eventually rewritten in Rex itself and can compile its own source
code to produce an identical binary.

The bootstrap path is:

```
Stage 0  rex_compiler.asm     — hand-written NASM; produces the first rex binary
              │
              ▼
Stage 1  rex_compiler.rex     — Rex source of the compiler; compiled by Stage 0
              │
              ▼
Stage 2  rex_compiler (self)  — Stage 1 binary compiles rex_compiler.rex
              │
              ▼
         Quine check: Stage 1 output == Stage 2 output  ✓  self-hosting achieved
```

A Rex build is considered **self-hosted** when the Rex-compiled compiler binary
produces byte-for-byte identical output to the assembly-compiled binary on the
full Rex test suite. Until that point, the NASM stage-0 compiler remains the
authoritative reference implementation.

---

## 19. Type Inspection

```rex
int x = 5
output(typeof x)    // prints compile-time type token as int
```

Type tokens: `int=1`, `float=2`, `bool=3`, `str=5`, `seq=6`, `dict=7`.

---

## 20. Safety Model

Rex has two safety levels, declared per-protocol with a decorator:

| Mode      | Allows                                    | Verified by compiler |
|-----------|-------------------------------------------|----------------------|
| `#safe`   | All Rex constructs except `$` and raw pointer arithmetic | Yes |
| `#unsafe` | Raw `$` syscalls, direct memory access    | No (programmer's responsibility) |

The default (no decorator) is equivalent to `#safe`. Unsafe operations outside
an `#unsafe` protocol are a **compile-time error**.

---

## 21. Keywords Reference

### Reserved — Types
`int`, `float`, `bool`, `str`, `char`, `byte`, `seq`, `arr`, `dict`, `tup`

### Reserved — Literals
`true`, `neutral`, `false`, `null`

### Reserved — Statements
`output`, `input`, `fmt`
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

## 22. Standard Library Modules (planned)

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

## 23. Design Goals Summary

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

## 24. Example Programs

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
