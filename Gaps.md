# Rex V0.1 — Architectural Gap Analysis

## Gap 1 — Recursive Protocol Stack Frames

### Symptom
`@fib(42)` returns 21 instead of 267,914,296.  
Execution time is 3224 ms (vs. C's 845 ms) and produces the wrong answer.

### Root Cause
Protocol parameters and local variables are stored in global, fixed-address slots
in `var_table` (`VAR_STORAGE_BASE + var_idx * 64`).  The B-1 mechanism already
saves and restores *parameter* slots at callee entry/exit via `push/pop qword [var_addr]`.
However, **local variables declared inside the protocol body** — such as `int a` and
`int b` in the fib protocol — share the same absolute addresses across every level of
recursion.  When the inner recursive call executes it overwrites those slots, so the
outer frame reads corrupted values on return.

For `fib(n)`:
```
prot fib(n):
    int a
    :a = @fib(n - 1)   ← stores fib(n-1) in global a-slot
    int b
    :b = @fib(n - 2)   ← inner call overwrites a-slot and b-slot
    return a + b        ← reads wrong values → wrong answer
```

### Fix — Caller-Side Save / Restore
Emit `push qword [var_addr]` for every variable currently in scope **before** the
CALL, and `pop qword [var_addr]` (in reverse order) **after** the CALL returns.
This is done at each `@proto(...)` call site in `parse_factor .prt_do`.

Two new codegen primitives are added to `codegen.asm`:

| Function | Emits | Encoding |
|---|---|---|
| `codegen_emit_push_var_slot(rdi=idx)` | `push qword [var_addr]` | `FF 34 25 <addr32>` |
| `codegen_emit_pop_var_slot(rdi=idx)` | `pop qword [var_addr]` | `8F 04 25 <addr32>` |

The B-1 callee-side save/restore for parameters is kept (it becomes redundant but
harmless; correctness is unaffected).

### Impact
Every `@proto()` call now emits `N` extra push/pop pairs (where N = vars in scope).
This increases emitted code size slightly and adds O(N) stack operations per call.
For flat (non-recursive) protocols the cost is a few extra instructions per call.
For deeply recursive protocols the overhead is proportional to recursion depth × N.

---

## Gap 2 — `rt_alc` Ignores the `.mode` Variable in Pool Context

### Symptom
`use mm pool gc bench_pool:` with 500 000 seq allocations times out (> 30 s).
C equivalent runs in ~102 ms.

### Root Cause
`codegen_emit_mm_switch` correctly emits a runtime instruction that stores the
selected mode into `rt_alc + 4088` (the `.mode` qword).  However the `rt_alc`
function itself **never reads `.mode`** — it unconditionally calls `mmap(2)` for
every allocation.  500 000 mmap syscalls take several seconds (each syscall costs
~5–10 µs on Linux).

### Fix — Bump-Pointer Pool Allocator
Two new 8-byte metadata fields are added inside the `rt_alc` blob, just before the
existing `.mode` field:

| Offset from rt_alc | Field | Address in ELF |
|---|---|---|
| 4072 | `pool_base` | `0x401D65` |
| 4080 | `pool_bump` | `0x401D6D` |
| 4088 | `mode`      | `0x401D75` |

The total blob size remains 4096 bytes (`RT_ALC_SIZE`).

The rewritten `rt_alc` logic:
```
if mode == 0:
    mmap(size)              ← arena mode, unchanged
else:
    if pool_base == 0:
        pool_base = pool_bump = mmap(64 MB)   ← lazy init
    rax = pool_bump
    pool_bump += align8(size)
    return rax              ← O(1) bump allocation
```

The pool is not freed within the process (OS reclaims on exit), which is correct
semantics for a pooled GC context.

### Impact
500 000 allocations of 80 bytes consume 40 MB of the 64 MB pool.  Allocation cost
drops from O(syscall) to O(1) arithmetic — benchmark should run in under 1 second.

---

## Status

| Gap | Status |
|---|---|
| Gap 1 — recursive stack frames | **Fixed** |
| Gap 2 — rt_alc pool mode | **Fixed** |
