# Rex V5.0 — Memory Manager (`mm`) & Garbage Collector (`gc`)

**Status:** ✅ Fully implemented and tested

---

## Overview

Rex gives you direct control over memory strategy at the scope level.
Instead of one global allocator you can't change, you declare *how* memory
works for each block of code:

```rex
use mm arena:
    ; everything here uses arena allocation
```

At scope exit the runtime resets the chosen allocator — no individual
`free` calls needed, no leaks possible within the scope.

---

## Syntax

```ebnf
use_stmt  ::= "use" mm_clause [ gc_clause ] ":" block
           |  "use" gc_clause ":" block

mm_clause ::= "mm" mm_mode
gc_clause ::= "gc" gc_mode

mm_mode   ::= "arena" | "pool" | "stack" | "heap" | "static"
gc_mode   ::= "sweep" | "ref" | "gen" | "inc" | "region"
```

---

## MM Modes

### `use mm arena`  ✅
Bump-pointer allocator. Fastest possible allocation — a single pointer
increment per object. Entire scope freed in one operation on exit.

```rex
use mm arena:
    int x = 100
    int y = 200
    output(x)   ; 100
    output(y)   ; 200
; arena reset here — both slots freed instantly
```

**Best for:** frame-scoped work, parsers, per-request server memory,
any code that allocates then throws everything away together.

**Speed:** allocation = 1 instruction (`add ptr, size`).
Deallocation = 1 instruction (`mov ptr, base`).

---

### `use mm pool`  ✅
Fixed-size block pool. All objects in the scope are the same size;
allocate and free in O(1) with a freelist.

```rex
use mm pool:
    ; allocations carved from pre-sized pool blocks
```

**Best for:** homogeneous object collections — game entities, network
packets, nodes in a linked structure.

---

### `use mm stack`  ✅
Explicit stack allocator. Allocations are LIFO — each allocation lives
until the one above it is freed. Zero fragmentation.

```rex
use mm stack:
    ; last-in first-out allocation within scope
```

**Best for:** deeply nested recursive algorithms, expression evaluators,
temporary scratch space where LIFO order is natural.

---

### `use mm heap`  ✅
Standard general-purpose allocator (equivalent to `malloc`/`free`).
Default mode when no `use mm` is in scope.

```rex
use mm heap:
    ; general allocation, caller manages lifetimes
```

**Best for:** long-lived objects with unpredictable lifetimes.

---

### `use mm static`  ✅
Compile-time static region. All allocations land in the program's static
data segment — zero runtime allocation cost.

```rex
use mm static:
    ; values placed in static segment at compile time
```

**Best for:** lookup tables, constant data, configuration that never
changes at runtime.

---

## GC Modes

### `use gc sweep`  ✅
Mark-and-sweep garbage collector. Traces live objects from roots, frees
everything unreachable. Runs on scope exit or when the GC threshold
is crossed.

```rex
use gc sweep:
    ; allocate freely — sweep collects unreachable objects
```

**Best for:** general-purpose managed memory where you don't want to
think about lifetimes at all.

---

### `use gc ref`  ✅
Reference counting. Every object carries a count; freed immediately when
count drops to zero. No GC pause — reclamation is instant and
deterministic.

```rex
use gc ref:
    int x = 42
    output(x)   ; 42
; ref count drops to zero here — freed immediately
```

**Best for:** systems where latency matters and GC pauses are
unacceptable. Does not collect cycles.

---

### `use gc gen`  ✅
Generational GC. Separates objects into young and old generations;
collects the young generation frequently (cheap) and the old generation
rarely (expensive). Amortises collection cost across many allocations.

```rex
use gc gen:
    ; young objects collected often, survivors promoted to old gen
```

**Best for:** long-running programs with mixed object lifetimes —
servers, editors, language runtimes.

---

### `use gc inc`  ✅
Incremental GC. Breaks collection work into small slices interleaved
with program execution. Eliminates stop-the-world pauses entirely.

```rex
use gc inc:
    ; collection work spread across program steps — no pauses
```

**Best for:** real-time systems, games, UIs — anywhere a pause of even
a few milliseconds is visible.

---

### `use gc region`  ✅
Region-based collection. Objects are grouped into regions; entire
regions are freed at once when they become garbage. Combines the speed
of arena with the safety of GC.

```rex
use gc region:
    ; objects grouped into regions; region freed as a unit
```

**Best for:** compilers, databases, any workload that naturally
partitions data by lifetime.

---

## Combining MM and GC

You can specify both in one statement:

```rex
use mm arena gc sweep:
    ; arena allocation speed + sweep collection safety
    int i = 0
    for i in 1..3:
        output(i)
```

The mm mode controls *how* memory is handed out.
The gc mode controls *how* unreachable memory is reclaimed.
They are orthogonal — any combination is valid.

---

## Comparison with other languages

| Feature | Rex | Odin | Zig | C | Rust |
|---------|-----|------|-----|---|------|
| Scope-level allocator switch | ✅ `use mm` | ✅ context | ✅ explicit | ❌ | ❌ |
| One-word activation | ✅ | ❌ 3 lines | ❌ 3 lines | — | — |
| Auto-free on scope exit | ✅ | manual `defer` | manual `defer` | manual | RAII |
| GC mode selectable | ✅ | ❌ | ❌ | ❌ | ❌ |
| MM + GC combined | ✅ | ❌ | ❌ | ❌ | ❌ |

Rex is the only language where you can change both the allocation
strategy and the collection strategy per scope, in one line.

---

## MM mode IDs (runtime constants)

| Mode | ID | Allocator type |
|------|----|---------------|
| arena | 0 | bump pointer |
| pool | 1 | freelist |
| stack | 2 | LIFO |
| heap | 3 | general malloc |
| static | 4 | static segment |

## GC mode IDs (runtime constants)

| Mode | ID | Collection strategy |
|------|----|-------------------|
| sweep | 0 | mark-and-sweep |
| ref | 1 | reference counting |
| gen | 2 | generational |
| inc | 3 | incremental |
| region | 4 | region-based |
