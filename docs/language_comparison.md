# Rex V5.0 vs. Python vs. C++

## Memory Management
- **Python**: Universal Reference Counting + Cycle GC. No manual control.
- **C++**: Manual (new/delete) or RAII (smart pointers). Static strategies.
- **Rex V5.0**: Dynamic Allocator Contexts. Use `use mm pool gc mark_sweep:` to hot-swap memory managers and collectors at runtime.

## Hashing & Collections
- **Python**: Dictionaries use SipHash, but are opaque.
- **C++**: `std::unordered_map` is often vulnerable to HashDoS (uses simple identity or Murmur).
- **Rex V5.0**: Native SipHash-2-4 implementation in pure Assembly. Sequences (@) and Dictionaries are built-in primitives with guaranteed performance.

## Execution Model
- **Python**: Interpreted / Bytecode (CPython). slow.
- **C++**: Compiled to Machine Code via complex Toolchain (Clang/GCC/Linker).
- **Rex V5.0**: Compiled directly to ELF64 binaries. No linker, no external dependencies, 100% pure x86_64 Assembly.

## Technical Mandates (Stage 4-8)
1. **SipHash-2-4**: All hashing must use SipHash-2-4 for security.
2. **System V AMD64 ABI**: Function calls must follow the standard ABI.
3. **Modular MM/GC**: The runtime must support Arena, Pool, Buddy, Slab, and Free-list allocators.
