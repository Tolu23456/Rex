# Rex V5.0 — Language Syntax Reference

---

## Variable Declaration

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

---

## Data Types

| Type      | Syntax Example                          | Notes                                             |
|-----------|-----------------------------------------|---------------------------------------------------|
| `int`     | `int a = 5`                             | 64-bit signed integer                             |
| `float`   | `float b = 1.5`                         | 64-bit double (SSE2)                              |
| `bool`    | `bool flag = true`                      | Tri-state: `true`, `false`, `unknown`             |
| `complex` | `complex c = 3+4j`                      | 128-bit XMM pair (real + imaginary)               |
| `str`     | `str name = "Rex"`                      | Null-terminated UTF-8 pointer                     |
| `seq`     | `seq items`                             | Dynamic sequence (heap); use `push`/`pop`/`len`   |
| `dict`    | `dict d`                                | SipHash key-value map; use `d["key"] = val`       |

### Binary literals
Binary, hex, and octal integer literals use standard prefixes:
```rex
int mask = 0b1100
int page = 0xFF
int oct  = 0o17
```

### Notes on unimplemented types
`set` and `tup` are planned but not yet implemented.

---

## Operators

### Arithmetic
```rex
int a = 10
int b = 3
int c
:c = a + b
:c = a - b
:c = a * b
:c = a / b
:c = a % b
```

### Bitwise
```rex
int x = 0b1100
int y = 0b1010
int z
:z = x & y
:z = x | y
:z = x ^ y
:z = ~x
:z = x << 1
:z = x >> 1
```

### Increment / Decrement
```rex
++x
--x
```

### Swap
```rex
swap x y
```

### Absolute value
```rex
int v
:v = abs(x)
```

---

## Type Casting

```rex
float f = 3.7
int i
:i = int(f)

int n = 5
float g
:g = float(n)
```

---

## Protocols

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

Return type annotation with `->` (optional):
```rex
prot square(x) -> int:
    return x * x
```

---

## Control Flow

### Conditional
```rex
int x = 10

if x == 10:
    output "ten"
elif x == 5:
    output "five"
else:
    output "other"
```

All six comparison operators are supported in conditions: `==`, `!=`, `<`, `>`, `<=`, `>=`.

### `when` / `is`
Switch-like routing. Each `is` case matches an integer value.
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

---

## Loops

### For loop
Range-based. Optional `step`.

```rex
for :i in 0..10:
    output i

for :i in 0..10 step 2:
    output i
```

### While loop
```rex
while true:
    output "Hello"
    stop
```

`stop` breaks out of the current loop.

---

## Sequences

```rex
seq nums
push nums 10
push nums 20
push nums 30

int n
:n = len nums
output n

int v
:v = pop nums
output v
```

---

## Dictionaries

```rex
dict d
d["hello"] = 42
d["world"] = 99

int v
:v = d["hello"]
output v
```

---

## Output

Print any value with `output`:
```rex
output 42
output x
output "hello"
output flag
output pi
output c
```

Rex routes output through the correct printer based on the variable's declared type.

---

## Error Handling

Emit a compile-annotated runtime error message and halt:
```rex
err "something went wrong"
```

---

## Memory Allocator Contexts

```rex
use mm pool gc 512:
    seq buf
    push buf 1

use mm arena gc 1024:
    dict cache
    cache["x"] = 7
```

---

## `typeof`

Compile-time type reflection returning the internal type token:
```rex
int x = 5
output typeof x
```

---

## `err` with `bool unknown`

`unknown` is a tri-state boolean backed by hardware entropy (`rdrand`). Use it to represent values that are genuinely indeterminate at compile time:
```rex
bool coin
:coin = unknown
output coin
```
