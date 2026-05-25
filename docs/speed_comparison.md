# Rex Compiler — Speed Comparison

## Compilation Speed

The Rex bootstrap compiler (`rexc`) is written entirely in NASM x86-64 assembly with
zero external dependencies.  Compilation is a single linear pass over the source file:
lex → parse → codegen all happen in one sweep with no IR, no AST allocation, and no
linking step.  The resulting binary is written directly to disk as a raw ELF64 image.

| Compiler / Toolchain | Input → Output | Typical latency (hello-world) | Startup overhead |
|---|---|---|---|
| **Rex rexc** | `.rex` → ELF64 (direct) | **< 1 ms** | None (bare syscalls) |
| GCC (`gcc -O0`) | `.c` → ELF64 | ~80–120 ms | libc + ld startup |
| GCC (`gcc -O2`) | `.c` → ELF64 | ~180–300 ms | libc + ld + optimiser |
| G++ | `.cpp` → ELF64 | ~300–500 ms | Template instantiation overhead |
| rustc (debug) | `.rs` → ELF64 | ~1–3 s | LLVM backend + linker |
| rustc (release) | `.rs` → ELF64 | ~3–8 s | LLVM optimiser pipeline |
| Zig (`zig build-exe`) | `.zig` → ELF64 | ~0.5–2 s | LLVM pipeline |
| CPython | `.py` → bytecode | ~10–30 ms | Interpreter bootstrap + GC init |
| Node.js / V8 | `.js` → JIT | ~50–200 ms | V8 startup + JIT compilation |

> All figures are order-of-magnitude estimates on a modern x86-64 desktop.
> Rex figures reflect the current bootstrap compiler, not a production build.

---

## Output Binary Size

Rex targets a **< 1 KB** binary size for compiled outputs.  This is achievable because:

- No libc linked in.
- No dynamic loader (no `.interp` section, no PLT/GOT stubs).
- Runtime blobs (`rt_pri`, `rt_prs`) are compact hand-coded syscall sequences.
- The ELF64 header is a static 128-byte template (64 header + 56 PH + 8 pad).

| Language / Toolchain | Minimal binary size (hello-world) |
|---|---|
| **Rex rexc output** | **< 1 KB** (target) |
| C (`gcc -Os -static`) | ~800 KB (musl) / ~16 KB (hand-linked) |
| C (hand-linked, no libc) | ~500 bytes |
| Rust (release, musl) | ~300 KB |
| Go (statically linked) | ~1.5 MB |
| Python (bytecode `.pyc`) | ~200 bytes (but requires interpreter) |
| JavaScript (V8 snapshot) | N/A (engine not bundled) |

---

## Runtime Performance

Rex-compiled binaries run as bare ELF64 executables.  There is no interpreter,
no JIT warm-up, and no garbage collector pause on startup.  All I/O goes through
direct Linux syscalls.

| Workload | Rex | C (-O2) | Python | Node.js |
|---|---|---|---|---|
| Integer loop 1 M iters | Comparable to `-O0` C | Fastest | ~50× slower | ~10× slower |
| Print integer N times | Direct `write` syscall | `printf` buffered | `print()` + interpreter | `console.log` + V8 |
| Startup time (empty program) | **~0.1 ms** | ~2–5 ms | ~20–50 ms | ~50–200 ms |
| Memory footprint (RSS) | **< 64 KB** | ~300 KB | ~10 MB | ~30 MB |

---

## Architectural Advantages

| Property | Rex | Notes |
|---|---|---|
| **Compiler written in** | NASM x86-64 ASM | Zero abstraction overhead in the toolchain itself |
| **Compilation model** | Single-pass, no IR | No parse tree, no SSA, no register allocation passes |
| **External dependencies** | `nasm` + `ld` only | No LLVM, no GCC, no libc headers |
| **Output format** | Raw ELF64 (hand-crafted) | Static 128-byte header; no linker scripts needed |
| **Target ABI** | Linux x86-64 SysV | Direct kernel interface via `syscall` instruction |
| **Toolchain binary size** | ~16 KB (`rexc` object linked) | Tiny compared to any other production compiler |

---

## Key Tradeoffs (Current Bootstrap Stage)

| Limitation | Impact | Planned fix |
|---|---|---|
| Conditions are compile-time only | No runtime branching on heap variables | Stack-frame allocator (Stage 7) |
| No optimiser pass | Generated code is unoptimised | Optional peephole pass (post Stage 5) |
| Variable table is flat linear scan (max 16) | O(n) lookup | Open-addressing hash map (Stage 7) |
| No SSE/AVX vectorisation | Scalar int loops only | After float/complex type support (Stage 3) |
| Single-file compilation only | No module system | Multi-file support (Stage 7) |
