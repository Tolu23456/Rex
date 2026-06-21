# Rex V5.0 — Language Comparison: Rex vs C vs C++ vs Rust vs Python

---

## Execution Model

| Feature              | Rex V5.0             | C                   | C++                  | Rust                | Python              |
|----------------------|----------------------|---------------------|----------------------|---------------------|---------------------|
| Compilation target   | Direct ELF64 binary  | Machine code (gcc)  | Machine code (g++)   | Machine code (LLVM) | CPython bytecode    |
| Linker required      | Build: `ld` (NASM obj files) / Output: **No** | Yes | Yes | Yes | N/A |
| Runtime dependencies | **None**             | libc (glibc)        | libc + libstdc++     | libc or musl        | CPython interpreter |
| Optimiser passes     | 5 IR passes (multi-pass) | GCC -O0..3      | G++ -O0..3           | LLVM -O0..3         | N/A                 |
| Binary size (min)    | **~500 bytes**       | ~15 KB (dyn.)       | ~15 KB (dyn.)        | ~8 KB (stripped)    | N/A                 |
| Process startup      | **~0.05 ms**         | ~10 ms              | ~14 ms               | ~0.5 ms             | ~50–100 ms          |

Rex emits a hand-crafted 120-byte ELF header directly — no `.plt`, `.got`, `_start`,
or dynamic-linker segment. The binary's first 5 bytes are `JMP CODE_START`.
The `ld` linker is used at *compiler build time* to link the NASM object files that
make up `rexc` itself. The **output** ELF binaries that `rexc` produces require no
linker — they are complete, self-contained executables written directly to disk.

---

## Memory Management

| Feature                   | Rex V5.0                          | C                | C++               | Rust              | Python            |
|---------------------------|-----------------------------------|------------------|-------------------|-------------------|-------------------|
| Default allocator         | Custom pool/arena (rt_alc_blob)   | glibc malloc     | glibc malloc      | System/jemalloc   | CPython obmalloc  |
| Allocation cost           | **O(1) bump pointer (pool)**      | O(log n)         | O(log n)          | O(log n)          | O(1) (obmalloc)   |
| Deallocation cost         | **O(1) pool reset**               | O(log n)         | O(log n)          | O(1)–O(log n)     | Ref-count + cycle |
| GC strategy               | Hot-swappable at compile time     | None             | None (RAII)       | Ownership/borrow  | Ref-count + GC    |
| Allocator context switch  | `use mm pool gc X:` / `arena gc X:` | Manual         | Allocator traits  | Custom allocators | None              |
| Fragmentation             | **Zero (arena/pool)**             | Possible         | Possible          | Possible          | Managed           |

Rex's `use mm pool gc name:` block reclaims the **entire pool in a single instruction**
(`mov qword[pool_offset], 0`) at block exit — zero fragmentation, zero GC pause.

---

## Hashing & Collections

| Feature                 | Rex V5.0                     | C                     | C++                       | Rust                     | Python                  |
|-------------------------|------------------------------|-----------------------|---------------------------|--------------------------|-------------------------|
| Hash algorithm          | SipHash-2-4 (pure asm)       | None built-in         | Identity / Murmur (UB)    | SipHash-1-3              | SipHash-2-4             |
| HashDoS resistance      | **Yes** (SipHash)            | Depends on impl       | Often no                  | Yes                      | Yes                     |
| Dictionary              | Built-in (`dict d`)          | None built-in         | `std::unordered_map`      | `std::collections::HashMap` | Built-in `dict`      |
| Dynamic sequence        | Built-in (`seq s`)           | Manual array          | `std::vector`             | `Vec<T>`                 | `list`                  |
| Sequence allocation     | **~5 ms / 500k ops (pool)**  | 61 ms (malloc)        | 71 ms (new/delete)        | ~60 ms (system alloc)    | Managed                 |

Rex's SipHash-2-4 is written entirely in x86-64 assembly within `rt_prq_blob` —
no external library, no stdlib dependency, same algorithm Python uses.

---

## Performance Benchmarks

Measured on Intel Xeon Platinum 8581C @ 2.30 GHz / Linux 6.17.5 / GCC 14.3.0.
Full methodology in `benchmark/README.md`.

### Integer Sum Loop — 1,000,000,000 iterations

| Language  | Time (ms) | Notes                                  |
|-----------|-----------|----------------------------------------|
| C++       | **340**   | G++ -O2                                |
| C         | 362       | GCC -O2                                |
| Rust      | ~340      | rustc -O (LLVM)                        |
| Rex       | ~850      | Multi-pass; loop optimiser not yet implemented |

Rex is ~2.4× slower on tight integer loops due to the absence of a backend optimiser.
GCC applies loop-induction-variable elimination and register renaming that Rex skips.

### Recursive Fibonacci — fib(42) (≈266 M calls)

| Language  | Time (ms) | Notes                                  |
|-----------|-----------|----------------------------------------|
| C         | **444**   | GCC -O2                                |
| C++       | 447       | G++ -O2                                |
| Rust      | ~450      | rustc -O                               |
| Rex       | ~680†     | †Stack frames pending (issue #18)      |

† Rex protocol parameters are currently stored in global `var_table` slots. Per-call
stack frames (issue #18) will bring Rex closer to C -O0 speed (~550 ms).

### Bubble Sort — 20,000 integers

| Language  | Time (ms) | Notes                                  |
|-----------|-----------|----------------------------------------|
| C++       | **1435**  | G++ -O2                                |
| C         | 1436      | GCC -O2                                |
| Rust      | ~1430     | rustc -O                               |
| Rex       | ~1700†    | †Index assignment pending (Stage 4)    |

All compiled languages are memory-bandwidth bound here. Rex's estimate assumes correct
index-write support.

### Heap Allocation — 500,000 × 80 bytes

| Language        | Time (ms) | Notes                           |
|-----------------|-----------|---------------------------------|
| Rex (pool gc)   | **~5**    | Bump pointer; O(1) pool reset   |
| C               | 61        | GCC -O2, glibc malloc           |
| Rust            | ~60       | rustc -O, system allocator      |
| C++             | 71        | G++ -O2, glibc new/delete       |

**Rex wins by ~12×.** Pool allocation is a single pointer increment. The entire pool
is wiped in one instruction at `use mm` block exit.

### Binary Size (stripped minimal program)

| Language  | Size          | Notes                            |
|-----------|---------------|----------------------------------|
| Rex       | **~500 B**    | Hand-crafted ELF64, no libc      |
| Rust      | ~8,000 B      | Stripped, panic=abort            |
| C         | 15,584 B      | Dynamic-linked glibc             |
| C++       | 15,584 B      | Dynamic-linked glibc + libstdc++ |

Rex binaries are **30× smaller** than C equivalents.

### Process Startup Time

| Language  | Startup (ms) | Notes                             |
|-----------|-------------|-----------------------------------|
| Rex       | **~0.05**   | Bare ELF, no dynamic linker       |
| Rust      | ~0.5        | Minimal runtime                   |
| C         | 10.3        | Measured — libc `_start` + ctors  |
| C++       | 14.5        | Measured — global ctors           |

Rex startup is **200× faster than C** — no dynamic linker, no constructor tables,
no TLS setup. `execve` → first user instruction in ~50 µs.

---

## Type System

| Feature              | Rex V5.0           | C               | C++             | Rust            | Python          |
|----------------------|--------------------|-----------------|-----------------|-----------------|-----------------|
| Integer              | `int` (64-bit)     | `int`, `long`…  | Same + templates | `i32`, `i64`… | `int` (bignum)  |
| Float                | `float` (64-bit)   | `double`        | Same            | `f32`, `f64`    | `float` (64-bit)|
| Boolean              | `bool` (tri-state) | `_Bool`         | `bool`          | `bool`          | `bool`          |
| Complex              | `complex` (128-bit XMM) | `_Complex` | `std::complex`  | `num` crate     | `complex`       |
| String               | `str` (UTF-8 ptr)  | `char*`         | `std::string`   | `&str` / `String` | `str` (UCS)  |
| Sequence             | `seq` (dynamic)    | Manual          | `std::vector`   | `Vec<T>`        | `list`          |
| Dictionary           | `dict` (SipHash)   | Manual          | `unordered_map` | `HashMap`       | `dict`          |

Rex's `bool` is deliberately tri-state: `true`, `false`, `unknown`. The `unknown` state
maps to hardware entropy via `rdrand rax` — representing genuine CPU-level uncertainty.

---

## Safety Guarantees

| Feature                  | Rex V5.0 (Stage 10 roadmap)      | C       | C++     | Rust    | Python  |
|--------------------------|----------------------------------|---------|---------|---------|---------|
| Null-pointer safety      | Tri-state bool gating (planned)  | No      | No      | Yes     | N/A     |
| Bounds checking          | Hardware guard planned (Stage 10)| No      | No      | Yes     | Yes     |
| Ownership tracking       | Affine types planned (Stage 10)  | No      | RAII    | Yes     | N/A     |
| Use-after-free           | Arena reclamation blocks         | Unsafe  | Unsafe  | No      | N/A     |
| Data races               | Not yet addressed                | Unsafe  | Unsafe  | No      | GIL     |

---

## Technical Mandates (Stages 4–8)

1. **SipHash-2-4**: All dictionary and sequence hashing must use SipHash-2-4 — same
   as Python, stronger than C++'s default `std::hash`.
2. **System V AMD64 ABI**: All protocol calls follow the standard 6-register calling
   convention (rdi, rsi, rdx, rcx, r8, r9).
3. **Modular MM/GC**: The runtime supports Arena, Pool, Buddy, Slab, and Free-list
   allocators, hot-swappable at compile time via `use mm X gc Y:` blocks.
4. **No external dependencies**: Rex binaries link against nothing — no libc, no
   libstdc++, no Rust std. Every runtime function lives in `runtime/runtime.asm`.
5. **Sub-kilobyte baseline**: Basic compiled programs must remain under 1 KB. Current
   measured baseline is ~500 bytes.
