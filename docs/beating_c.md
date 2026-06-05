# Beating C -O3 with Rex — ABI Freedom

## The Core Constraint C Cannot Escape

GCC and Clang must emit code that interoperates with the OS, libc, and every other compiled object. That means **SysV ABI compliance is mandatory**:

- Callee must preserve `rbp`, `rbx`, `r12–r15`
- Stack must be 16-byte aligned before every `call`
- Frame pointer expected by debuggers and stack unwinders

For `fib(42)` at `-O3`, GCC emits roughly this per non-leaf call:

```nasm
push rbp       ; mandatory save
push r12       ; mandatory save
push rbx       ; mandatory save
sub rsp, 8     ; alignment padding
... body ...
add rsp, 8
pop rbx
pop r12
pop rbp
ret
```

That is **10 instructions of pure ABI overhead** per call, across 700 million recursive calls. GCC cannot remove any of them without breaking the ABI.

---

## What Rex Can Do That C Cannot

Rex only calls Rex. It can define its own calling convention where **none of those constraints apply**.

### 1. Frameless Convention — Eliminate the Frame Entirely

No `push rbp`, no `mov rbp,rsp`, no `sub rsp,N`. Instead, use raw `push`/`pop` directly on rsp for the two values fib actually needs to save per call (`n` and `fib(n-1)`). The CPU's stack engine handles push/pop at near-zero throughput cost — they are tracked by dedicated hardware, not the main execution units.

| Path | Instructions per non-leaf call |
|---|---|
| Rex today | ~12 (frame setup + O18 overhead) |
| C `-O3` (SysV ABI) | ~10 (ABI-constrained minimum) |
| Rex frameless | ~5–6 (no ABI obligation) |

Roughly **2× less call overhead than C -O3**.

### 2. Treat All Registers as Caller-Saved Between Rex Protocols

C must save `rbx`/`r12` because a callee might clobber them. If Rex declares all registers caller-saved for inter-Rex calls, no protocol ever needs save/restore boilerplate — callers push only what they actually need, nothing more.

### 3. Red Zone for Leaf Calls

Linux x86-64 guarantees the 128 bytes below `rsp` (the "red zone") will not be touched by the kernel between user instructions. Leaf functions (fib base case: `n ≤ 1`) can store temporaries at `[rsp-8]` without ever adjusting `rsp` at all — zero stack-adjustment instructions for every base-case return.

### 4. 16-Byte Alignment Is Rex's Choice

C must align `rsp` to 16 bytes before every `call`. Rex can use 8-byte alignment internally since it never calls libc during protocol execution. This eliminates the `sub rsp,8` / `add rsp,8` padding instructions that GCC must emit to maintain ABI alignment.

---

## Realistic Outcome

A Rex fib using a frameless, caller-saves-all, no-alignment-padding internal ABI:

| Scenario | Non-leaf call overhead |
|---|---|
| Rex V5.0 (current) | ~12 instructions |
| C `-O3` (SysV ABI bound) | ~10 instructions |
| Rex frameless (target) | ~5–6 instructions |

**Projected speedup over C -O3: 1.5–2×** for recursive call-heavy workloads — not from a smarter algorithm, but from discarding the convention that C is permanently bound to.

---

## The Tradeoff

Rex protocols compiled with the frameless internal ABI cannot be called directly from C without a thin ABI-translation shim. Since Rex already has no C interop at the protocol level (no header export, no symbol mangling), nothing is lost in practice.

---

## Current Status

| Optimization | Status |
|---|---|
| O18: pin params to r12/r13 | Implemented — helps loop-heavy protocols, adds ~7% overhead to deep recursion |
| Frameless calling convention | Not yet implemented |
| Caller-saves-all register model | Not yet implemented |
| Red zone leaf optimization | Not yet implemented |

The frameless convention is the highest-leverage next step for closing the gap with C on recursive workloads.
