# Rex Programming Language Documentation

Rex is a compiled, high-performance language designed with Python-style readability and absolute control over system resources.

## New Features (v0.2)
- **Flattened Codebase**: All source files are moved to the root/modular folders for better NASM indexing.
- **Improved Comments**: Now uses `#` for single-line and `"""` for multi-line comments.
- **Variable Scoping**: Integrated symbol table for local and global variable management.
- **Control Flow**: Implemented `if` blocks with machine code emission and relative jump patching.
- **Dynamic Memory Routing**: `use mm <1-5> gc <1-3>:` blocks for context-specific allocation.
- **Memory Safety**: Strict Memory Boundary Pass to prevent variables from escaping custom MM blocks.

## Syntax

### Variables
```rex
# Declaration
int age
# Assignment
:age = 56
```

### Control Flow
```rex
if :age > 10:
    output 1
```

### Memory Contexts
```rex
use mm 2 gc 1:
    # Code here uses MM 2 (Pool) and GC 1
    int x
    :x = 10
```

## Comparisons

| Feature | Rex | Python | C++ | Rust |
|---------|-----|--------|-----|------|
| Speed | Extremely Fast (Asm) | Slow | Fast | Fast |
| Binary Size | < 1 KB | N/A | > 10 KB | > 200 KB |
| Memory Routing| Yes | No | No | No |
