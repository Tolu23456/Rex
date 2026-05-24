# Rex Language Comparative Matrix

| Feature / Metric | Rex | C | C++ | Rust | Zig | Python | JavaScript |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Compiler Dependency** | None (Direct ELF64) | `gcc`/`clang` + `ld` | `g++` + `ld` | `rustc` + `lld` | `zig cc` | Python Interpreter | V8 / SpiderMonkey Engine |
| **Immutability Contract** | Explicit Signatures | Manual (`const`) | Manual (`const`) | Immutable by default | Explicit (`const`/`var`)| None (Dynamic) | Scoped (`const`/`let`) |
| **Control Flow Scope** | Indentation Tokens | Braces `{}` | Braces `{}` | Braces `{}` | Braces `{}` | Indentation Blocks | Braces `{}` |
| **Object System** | Decoupled Protocols | Struct-Only | Class Hierarchy | Traits & Structs | Struct Mixins | Dynamic Classes | Prototype Inheritance |
| **Collections Engine** | Native SipHash Open | Manual / External | STL Map/Unordered | Standard Hashmap | `std.HashMap` | Dict (SipHash/Split) | Map Object Engine |
| **Boolean Logic** | Tri-State Hardware | Bi-State Integer | Bi-State Native | Bi-State Explicit | Bi-State Primitive | Bi-State Object | Dynamic Truthiness |
| **Memory Mechanics** | Dynamic Context Blocks | Manual (`malloc`) | RAII / Manual | Borrow Checker | Explicit Allocators | Global GC Loop | Mark-and-Sweep Engine |
| **Binary Base Footprint**| **< 1 KB** | ~16 KB | ~16 KB+ | ~300 KB+ | ~40 KB+ | N/A | N/A |
