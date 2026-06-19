# T009: Memory Allocator Algorithm Analysis

## Overview
The Rex runtime utilizes a dual-mode memory allocation strategy implemented in `rt_alc` (found in `runtime/runtime_src.asm`). It supports a direct `mmap` mode (arena-style but per-allocation) and a high-performance **bump-pointer pool allocator**.

## Allocator Architecture Analysis

### 1. Direct `mmap` Mode
- **Trigger**: When `mode` (at `0x401D75`) is 0.
- **Mechanism**: Every `rt_alc` call results in a `sys_mmap` (9) syscall.
- **Alignment**: Requests are 8-byte aligned.
- **Complexity**: $O(Kernel)$, involves context switches and page table manipulations.
- **Safety**: Each allocation is independent, providing isolation but high overhead.

### 2. Bump-Pointer Pool Allocator
- **Trigger**: When `mode` is non-zero.
- **Mechanism**: 
    - On first use, it maps a 64 MB chunk (`MAP_PRIVATE | MAP_ANONYMOUS`).
    - Subsequent allocations simply increment a `pool_bump` pointer.
    - **Alignment**: Guaranteed 8-byte alignment.
- **Complexity**: $O(1)$ (effectively a single `add` instruction in the hot path).
- **Pros**: extremely high throughput, zero fragmentation within the pool.
- **Cons**: No `free` implementation (all-or-nothing reclamation).

### 3. "use mm arena" Language Construct
The language exposes this via `use mm arena:`. As seen in `benchmarks/bench_arena.rex`, this is specifically designed for high-frequency small allocations (e.g., sequence growth in a loop).

## Performance Bottlenecks & Improvements

### Current Issues
1. **No Slab/Free-list**: The current `rt_heap_free` is a `ret` (NOP). This leads to memory exhaustion in long-running programs that don't use the arena model.
2. **Global Lock Contention**: While Rex is currently single-threaded, the allocator uses global state (`pool_base`, `pool_bump`). If multithreading is added, this will be a massive bottleneck.
3. **Large Allocation Overhead**: Small and large allocations follow the same path. Large allocations (> 4KB) should always bypass the pool to avoid exhausting it quickly.

### Proposed Two-Tier Allocator
A more robust strategy would be:
- **Tier 1: Small Objects (≤ 128 bytes)**
  - Use a **Slab Allocator** or **Free-list** for common sizes (16, 32, 64, 128).
  - This allows recycling memory without the "all-or-nothing" limitation of the bump allocator.
- **Tier 2: Large Objects (> 128 bytes)**
  - Use the existing `mmap` strategy for very large objects.
  - Use the **Bump Allocator** for medium objects within specific lifetime scopes (Arenas).

### Estimated Throughput Improvement
- Switching from `mmap` to `bump` provides ~1000% speedup for small allocations.
- Implementing a **Slab** recycler for the "free-list" cases would improve memory efficiency by orders of magnitude for non-scoped allocations, preventing `out-of-memory` crashes in iterative workloads.

## Security & Safety Audit
- **Double-Free/Use-After-Free**: Since `rt_heap_free` does nothing, these bugs are currently *impossible* to trigger in a way that crashes the allocator, but they represent logical leaks.
- **Overflow**: `rt_alc` adds 7 then aligns. A request of `0xFFFFFFFFFFFFFFF8` would overflow and result in a small allocation, leading to a heap buffer overflow.
- **Bounds**: Rex relies on the compiler to emit bounds checks (as seen in `rt_str_find` and others). The allocator itself does not provide guard pages between small pool allocations.

## Implementation Sketch: Slab Recycler
```asm
; Pseudocode for 64-byte slab recycling
rt_alc_64:
    mov rax, [slab_64_free_list]
    test rax, rax
    jz .do_bump
    mov rdx, [rax] ; next pointer
    mov [slab_64_free_list], rdx
    ret
.do_bump:
    mov rdi, 64
    jmp rt_alc
```
