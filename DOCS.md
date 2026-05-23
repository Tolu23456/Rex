; DOCS.md
# Rex Programming Language Documentation

Rex is a compiled, high-performance language designed with Python-style readability and absolute control over system resources.

## Syntax

### Variables
```rex
int age
:age = 56
```

### Arithmetic
```rex
output 10 + 5 * 2
```

### Protocols (Functions)
```rex
prot greet_user(None) -> str:
    return :"Hello, User"
```

### Control Flow
```rex
for :i in 0..10:
    output i

if :age >= 10:
    output age
```

### Memory Management
Rex supports 5 memory managers and 3 GCs.
```rex
use mm 2 gc 1:
    @data = @[10, 20, 30]
```

## Comparisons

| Feature | Rex | Python | C++ | Rust |
|---------|-----|--------|-----|------|
| Speed | Extremely Fast (Asm) | Slow | Fast | Fast |
| Readability | High | High | Low | Medium |
| Memory Control| Absolute | Low | High | High |
| Compiled | Yes | No | Yes | Yes |

## Future Syntax & Functionality
- Full Standard Library (I/O, Networking, File System)
- Foreign Function Interface (FFI) to call C libraries
- Advanced Pattern Matching
- Built-in Concurrency (Protocols as Threads)
