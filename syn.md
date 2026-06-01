# Rex V5.0 — Language Syntax Reference

**Status markers used in this document:**
- ✅ Implemented and tested
- 🔧 Lexed — token exists, parser/codegen pending
- 📋 Planned — Stage 9 / Stage 10 roadmap

---

## Variable Declaration ✅

### Constant (immutable)
Inline assignment at declaration time locks the value — no reassignment allowed.
```rex
int age = 13
```

### Mutable
Declare with `:` sigil at declaration, or declare then assign separately.
```rex
int :age = 13
```
```rex
int age
:age = 13
```

The `:` sigil marks every write site — not just the declaration. Any line with `:x =` is modifying state; any line without it is not.

---

## Data Types ✅

| Type      | Syntax Example       | Notes                                           |
|-----------|----------------------|-------------------------------------------------|
| `int`     | `int a = 5`          | 64-bit signed integer                           |
| `float`   | `float b = 1.5`      | 64-bit double (SSE2)                            |
| `bool`    | `bool f = true`      | Tri-state: `true`, `false`, `unknown`           |
| `complex` | `complex c = 3+4j`   | 128-bit XMM pair (real + imaginary)             |
| `str`     | `str s = "Rex"`      | Null-terminated UTF-8 pointer                   |
| `seq`     | `seq items`          | Dynamic sequence (heap); push / pop / len       |
| `dict`    | `dict d`             | SipHash key-value map; `d["key"] = val`         |

### Binary / hex / octal literals ✅
```rex
int mask = 0b1100
int page = 0xFF
int oct  = 0o17
```

### Unimplemented types 📋
`set` and `tup` are planned but not yet implemented.

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

### Logical 🔧
Tokens are lexed. Parser wiring is pending.
```rex
if x > 0 and y > 0:
    output "both positive"

if a == 1 or b == 1:
    output "at least one"

if not flag:
    output "off"
```

### Comparison ✅
All six operators are supported in `if`, `elif`, and `while` conditions:
```
==   !=   <   >   <=   >=
```

### Identity — `is` / `is not` 📋
Semantic identity check. Evaluates to a hardware `cmp`.
```rex
if x is 0:
    output "zero"

if ptr is not null:
    output "valid"
```

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

Define with `prot`. Parameters are positional. Return a value with `return`.

```rex
prot greet():
    output "Hello"

prot add(a, b):
    return a + b
```

Call with `@`:
```rex
@greet()

int result
:result = @add(3, 4)
output result
```

Return type annotation with `->`:
```rex
prot square(x) -> int:
    return x * x
```

Use `None` to explicitly declare no parameters or no return value:
```rex
prot log(None) -> None:
    output "log"
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
Range-based. Optional `step`.
```rex
for :i in 0..10:
    output i

for :i in 0..20 step 2:
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
for :i in 0..100:
    if i == 5:
        stop
    output i
```

### `skip N` ✅
Skip N levels of nested loops (break outer loops). `skip 1` is equivalent to `stop`.
```rex
for :i in 0..10:
    for :j in 0..10:
        if i == j:
            skip 2    // break both loops
```

### Loop `else:` 📋
Executes only if the loop completes naturally without a `stop`.
```rex
for :i in 0..10:
    if i == 5:
        stop
else:
    output "completed"
```

### `repeat N:` 📋
Counted loop with no explicit counter variable. Emits a single `dec`/`jnz` hardware loop — faster than `for` when the index is not needed.
```rex
repeat 8:
    output "tick"
```

### `each` 🔧
Cache-aligned iterator for sequential collection sweeping. Token is lexed; parser pending.
```rex
each item in items:
    output item
```

---

## Sequences ✅

```rex
seq nums
push nums 10
push nums 20
push nums 30

int n
:n = len nums       // length (runtime read from hidden header)
output n

int c
:c = cap nums       // capacity (allocated slots)

int v
:v = pop nums       // LIFO pop
output v
```

---

## Dictionaries ✅

```rex
dict d
d["hello"] = 42
d["world"] = 99

int v
:v = d["hello"]
output v
```

---

## String Operations

### Output ✅
```rex
str s = "hello"
output s
```

### Concatenation 📋
```rex
str a = "hello"
str b = " world"
str c
:c = a + b
```

### Length ✅
```rex
int n
:n = len s
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

## Complex Numbers ✅

```rex
complex a = 3+4j
complex b = 1+2j
output a
```

### Component access 📋
```rex
float r
:r = real(a)    // isolates real component

float i
:i = imag(a)    // isolates imaginary component

complex c
:c = conj(a)    // conjugate (negate imaginary)
```

---

## Output ✅

Print any value with `output`. Rex routes to the correct printer based on the variable's declared type.
```rex
output 42
output x
output "hello"
output flag        // bool: prints true / false / unknown
output pi          // float
output c           // complex: prints (real+imagj)
```

---

## Error Handling ✅

Emit a runtime error message to stderr and halt:
```rex
err "something went wrong"
```

---

## Memory Allocator Contexts ✅

Block-scoped allocator strategy. Reverts automatically at block end.
```rex
use mm pool gc mypool:
    seq buf
    push buf 1
    push buf 2

use mm arena gc myarena:
    dict cache
    cache["x"] = 7
```

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
