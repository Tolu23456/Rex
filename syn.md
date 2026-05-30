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

| Type      | Syntax Example                          | Notes                          |
|-----------|-----------------------------------------|--------------------------------|
| `int`     | `int a = 5`                             | 64-bit signed integer          |
| `float`   | `float b = 1.5`                         | 64-bit double (SSE2)           |
| `complex` | `complex c = 12j`                       | 128-bit XMM pair               |
| `str`     | `str name = "Rex"`                      | Null-terminated UTF-8 pointer  |
| `bin`     | `bin10 = 01010101`                      | Base-N binary literal          |
| `dict`    | `dict details = {int key: int value}`   | Typed key-value map            |
| `@seq`    | `@seq items`                            | Dynamic sequence (heap)        |
| `set`     | `set d = <{5, 4, 3}>` or `:{5, 4, 3}`  | Unordered unique collection    |
| `tup`     | `tup = (int age, str name)`             | Fixed typed tuple              |

---

## Protocols

Protocols use `->` for return type annotation. Use `None` for no parameters or no return value.

```rex
prot greet_user(None) -> None:
    output "Hello, user"
```

---

## Control Flow

### Conditional
Supports inline type annotations and logical operators (`and`, `or`).

```rex
if int 5 < int 20 and "a" != "b":
    output "Mehh"
```

---

## Loops

### For Loop
Range-based loop with optional `step`.

```rex
for :i in 0..10 step 2:
    output(i)
```

### While Loop

```rex
while True:
    output "Hello"
    stop
```

---
