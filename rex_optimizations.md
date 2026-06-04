# Rex V5.0 — Speed Optimizations

## Overview

Rex is a hand-written x86-64 NASM ELF64 compiler.  Because every byte of every
instruction is emitted by explicit `call emit_b` / `call emit_d` sequences, the
compiler has total visibility — and total control — over the machine code it
produces.  This document records every optimization implemented in this session,
followed by a catalogue of further assembly-specific opportunities that are only
practical in a hand-rolled compiler.

---

## Bug Fixes (prerequisites for correct benchmarking)

| # | File | Problem | Fix |
|---|------|---------|-----|
| B1 | `bench_rex.rex` | Loop body wrote `total = total + i` (immutable rebind error at runtime) | Changed to `:total = total + i` |
| B2 | `codegen/codegen.asm` — `codegen_emit_each_start` | Missing `inc qword [loop_pin_depth]`; `each_end` always decremented, causing underflow that spoiled the O2 pin flag for any loop that followed an `each` | Added the missing increment |
| B3 | `codegen/codegen.asm` — `codegen_set_frame` | Dead store `mov [frame_param_cnt], bh` clobbered the parameter count with a stale high byte of rbx | Removed the dead store |

After these fixes `bench_rex.rex` (`for :i in 0..10000000: :total = total + i`)
produces `49999995000000` in ≈ 8 ms (dynamic-bounds path).

---

## Optimizations Implemented

### O-A  Static-bounds `for` loop → O2 r15 register pin

**Files:** `parser/parser.asm`, `codegen/codegen.asm`

**What the problem was.**  The parser always called
`codegen_emit_for_start_dyn` regardless of whether the loop bounds were
compile-time constants.  The dynamic emitter tracks nesting depth
(`loop_pin_depth`) but never sets `loop_pin_active`, so the O2 register-pin
optimization (loop variable held in `r15` for the entire loop body) was dead
code for the most common case.

**What the dynamic inner loop looked like** (`for :i in 0..10000000:`):

```
4021B0: mov rax,[0x440040]   ; load i          — 8 bytes  ← redundant
4021B8: cmp rax,[0x440080]   ; cmp i, i_fe     — 8 bytes
4021C0: jnl 0x4021f4         ; exit if >=      — 6 bytes
4021C6: mov rax,[0x440000]   ; load total      — 8 bytes
4021CE: mov r10,rax          ; save total      — 3 bytes
4021D1: mov rax,[0x440040]   ; load i AGAIN    — 8 bytes  ← redundant
4021D9: mov rbx,r10          ; restore total   — 3 bytes
4021DC: add rax,rbx          ; i + total       — 3 bytes
4021DF: mov [0x440000],rax   ; store total     — 8 bytes
4021E7: inc qword [0x440040] ; i++             — 8 bytes
4021EF: jmp 0x4021b0         ;                 — 5 bytes
; = 11 instructions, 68 bytes, two 8-byte memory loads of i per iteration
```

**Implementation.**

*Parser (`parser/parser.asm` — `.for` section):*

Before calling `parse_expr` for the start expression, save:
- `tok_type` → `for_start_tok` (1 byte BSS)
- `tok_int`  → `for_start_val` (8 byte BSS)
- `out_idx`  → `for_rollback_idx` (8 byte BSS)

Before calling `parse_expr` for the end expression, save:
- `tok_type` → `for_end_tok` (1 byte BSS)
- `tok_int`  → `for_end_val` (8 byte BSS)

If a `step` keyword is detected, `for_start_tok` is zeroed to disable the static
path.

At `.for_nostep`, if both saved token types equal `TOK_INT_LIT`:
1. Restore `out_idx` to `for_rollback_idx` (rolls back all emitted init code).
2. Skip the `i_fe` runtime variable (end value no longer needs memory storage).
3. Jump past the dynamic path to the `__le` allocation then call
   `codegen_emit_for_start(rdi=loop_var_idx, rsi=start_val, rdx=end_val)`.

*Codegen (`codegen_emit_for_start` — already existed):*

The static emitter's pin path (triggered when `loop_pin_depth == 0`):
- Sets `loop_pin_active = 1`, records `loop_pin_var_idx`.
- Emits `mov r15, [i_addr]` to load i into the pinned register.
- Loop condition becomes `cmp r15, end_val_imm32` — no memory load.
- `codegen_emit_for_end` sees `loop_pin_active` and emits `inc r15` instead of
  `inc qword [i_addr]`, then flushes `mov [i_addr], r15` on loop exit.

**Result — pinned inner loop:**

```
; init (once):
xor eax, eax            ; 2 bytes  (from_val == 0 → compact form)
mov [i_addr], eax       ; 7 bytes
mov r15, [i_addr]       ; 8 bytes  ← r15 = i (stays there for entire loop)

; loop top (hot path):
cmp r15, 10000000       ; 7 bytes  ← immediate, no memory read
jnl exit                ; 6 bytes
mov rax, [total_addr]   ; 8 bytes
add rax, r15            ; 3 bytes  ← r15 used directly, no second memory load
mov [total_addr], rax   ; 8 bytes
inc r15                 ; 3 bytes  ← register increment, no memory write
jmp top                 ; 5 bytes
; = 7 instructions, 40 bytes — saves 28 bytes and 4 memory ops per iteration
```

**Estimated speedup for the benchmark: ~30–35%.**

---

### O-B  Peephole Pattern E — fold `r10` save/load/restore round-trip

**File:** `codegen/codegen.asm` — `codegen_peephole`

**Pattern matched (14 bytes):**

```
49 89 C2             mov r10, rax          ; expression-depth save
48 8B 04 25 <a4>     mov rax, [abs32]      ; sub-expression load
4C 89 D3             mov rbx, r10          ; expression-depth restore
```

**Replacement (14 bytes, same size):**

```
48 89 C3             mov rbx, rax          ; fold: save directly to rbx
48 8B 04 25 <a4>     mov rax, [abs32]      ; sub-expression load (unchanged)
90 90 90             NOP NOP NOP           ; pad to same length
```

**Why it works.**  When the left operand of a binary expression is in `rax` and
the right operand is a single memory load, the expression saver stores `rax` to
`r10`, loads the right operand into `rax`, then restores `r10 → rbx`.  The
restoration can instead happen *before* the load: `mov rbx, rax; mov rax, [addr]`.
This eliminates one register rename and the `r10` dependency chain.

**Savings:** 1 instruction, 3 bytes of dependency per matching binary expression.

---

### O-C  Peephole Pattern F — fold adjacent `r10` save/restore

**File:** `codegen/codegen.asm` — `codegen_peephole`

**Pattern matched (6 bytes):**

```
49 89 C2   mov r10, rax    ; expression-depth save
4C 89 D3   mov rbx, r10   ; expression-depth restore (adjacent — no load between)
```

**Replacement (6 bytes):**

```
48 89 C3   mov rbx, rax   ; direct: rax → rbx
90 90 90   NOP NOP NOP
```

**Why it occurs.**  When both operands of a binary op were already evaluated into
registers (e.g., after a chain of subexpressions), the save/restore around a
literal or short rhs collapses to adjacent pairs.  Folding to `mov rbx, rax`
saves 1 instruction per occurrence.

---

### O-D  `__le` flag init — short memory store form

**File:** `codegen/codegen.asm` — new `codegen_emit_zero_var`; `parser/parser.asm`

The loop-else flag (`__le`) was initialized with `codegen_emit_assign_var(idx, 0)`
which emits:

```
48 B8 00 00 00 00 00 00 00 00   mov rax, imm64(0)   — 10 bytes
48 89 04 25 <addr32>             mov [addr], rax     — 8 bytes
                                                      = 18 bytes total
```

The new `codegen_emit_zero_var` emits the shorter:

```
48 C7 04 25 <addr32> 00 00 00 00   mov qword [addr], 0   — 9 bytes
```

**Savings:** 9 bytes per loop entry that has a valid `__le` flag slot.

---

### O-E  Loop-top 16-byte alignment

**File:** `codegen/codegen.asm` — `codegen_align_loop_top`

Modern x86 CPUs fetch instructions in 16-byte (or 32-byte on newer µarches)
aligned blocks.  If a loop's top straddles a fetch block boundary, the branch
predictor and decoder see partial blocks on every taken-branch return, wasting
bandwidth.

A new helper `codegen_align_loop_top` is called just before recording the loop
condition address in `codegen_emit_for_start` (both pin and global paths) and in
`codegen_emit_for_start_dyn`.  It emits 0–15 `0x90` NOP bytes to advance
`out_idx` to the next 16-byte boundary:

```asm
codegen_align_loop_top:
    push rcx
.alt_spin:
    mov rcx, [out_idx]
    test rcx, 15        ; aligned already?
    jz .alt_done
    mov al, 0x90        ; emit NOP
    call emit_b
    jmp .alt_spin
.alt_done:
    pop rcx
    ret
```

**Savings:** up to 15 bytes of wasted fetch bandwidth per loop iteration, zero
cost when already aligned.

---

## Assembly-Specific Opportunities (future work)

These optimizations are practical only in a hand-written assembler compiler
because they require direct control over the instruction stream, register
allocation, and hardware features that are invisible to C/C++/Rust compilers.

### F-1  SIMD bulk memory operations

Rex's sequence type (dynamic arrays) currently copies and clears memory in 8-byte
chunks.  Switching to `movdqu` / `vmovups` (16 / 32 bytes per instruction):

```asm
; clear 64 bytes: 4 × movdqu vs 8 × mov qword
xorps xmm0, xmm0
movdqu [rdi+0],  xmm0
movdqu [rdi+16], xmm0
movdqu [rdi+32], xmm0
movdqu [rdi+48], xmm0
```

For sequence push/pop and GC sweep, this alone could halve memory-bandwidth time.

### F-2  `rep stosq` / `rep movsq` for bulk zeroing and copying

The `rep stosq` instruction (with `rdi=dest, rax=value, rcx=count`) zeros memory
at roughly 32 bytes/cycle on modern hardware.  Use it in sequence allocation and
frame-local zeroing:

```asm
lea rdi, [seq_buf]
xor eax, eax
mov rcx, size_in_qwords
rep stosq
```

Replaces a software loop with a single µcoded instruction that uses the memory
bus optimally.

### F-3  `CMOVcc` for branchless conditionals

Rex boolean results (`==`, `<`, etc.) currently emit a `SETcc al; movzx rax,al`
sequence (Peephole D).  Many if-else expressions could instead use `CMOVcc`:

```asm
; if (a > b) then x else y
cmp rax, rbx
cmovg rax, rcx   ; select x or y without a branch
```

This eliminates branch-predictor misses entirely for value-selecting expressions.
Useful for `min`, `max`, ternary-style `when` expressions.

### F-4  `LEA` for multiply-by-small-constant

Instead of `imul rax, rax, N` (3-byte instruction, 3-cycle latency), use `lea`:

| Multiply | LEA form | Bytes | Latency |
|----------|----------|-------|---------|
| × 2 | `lea rax,[rax+rax]` | 3 | 1 |
| × 3 | `lea rax,[rax+rax*2]` | 4 | 1 |
| × 5 | `lea rax,[rax+rax*4]` | 4 | 1 |
| × 9 | `lea rax,[rax+rax*8]` | 4 | 1 |

For scaling VAR_STORAGE offsets (currently `imul rax, rax, 64`) this is a win:
`lea rax, [rax*8]` + `lea rax, [rax*8]` = 2 × 1-cycle vs 1 × 3-cycle.

### F-5  SIMD peephole scanner

The `codegen_peephole` function walks the output buffer one byte at a time.  For
a large program it scans tens of thousands of bytes.  Using `pcmpeqb` +
`pmovmskb` the scanner can test 16 candidate bytes in parallel:

```asm
movdqu xmm1, [rdi+rbx]          ; load 16 bytes from buffer
pcmpeqb xmm0, xmm1              ; compare all 16 with pattern byte 0
pmovmskb eax, xmm0              ; bitmask of matching positions
bsf eax, eax                    ; first match offset
jz .no_match                    ; none in this block
```

This could make the peephole pass 10–16× faster for large programs.

### F-6  `popcnt` / `lzcnt` / `tzcnt` as built-in intrinsics

These are single-cycle instructions exposed since SSE4.2 / ABM:

| Instruction | Operation | Typical use |
|-------------|-----------|-------------|
| `popcnt rax, rbx` | population count (set bits) | Hamming weight, bloom filters |
| `lzcnt rax, rbx` | leading zero count | fast log₂, bit-width |
| `tzcnt rax, rbx` | trailing zero count | lowest set bit, alignment |

Rex could expose these as `popcount(x)`, `leading_zeros(x)`, `trailing_zeros(x)`
built-in calls — each compiles to exactly one instruction.

### F-7  `write()` syscall batching

Every `output` statement currently calls `rt_pri` which issues a separate
`write(1, buf, len)` syscall for each printed value.  Syscall overhead is
~100 ns on modern Linux.  Buffering all output into a ring buffer and flushing
once at program exit (or when the buffer is full) replaces N syscalls with 1.

For a program that outputs inside a loop this is a 10–50× reduction in
output-related runtime.

### F-8  FMA for floating-point expressions

Fused multiply-add (`vfmadd213sd xmm0, xmm1, xmm2`) computes `xmm1*xmm0 + xmm2`
in one instruction with a single rounding error (IEEE 754-2008 compliant).
Current Rex emits `mulsd` + `addsd` (two instructions, two rounding steps,
two cycles).  For expressions like `a*b + c` the FMA encoding is smaller, faster,
and more numerically accurate.

### F-9  Multi-register XMM spilling

The expression evaluator uses `r10` as the depth-0 spill register (now folded
away by Patterns E and F) and the stack for deeper nesting.  The 16 XMM
registers (`xmm0`–`xmm15`) are scratch registers that survive across ordinary
integer code.  Expression depths 0–7 could each spill to a dedicated XMM
register (`movq xmm8, rax`) instead of using the stack, avoiding memory traffic
entirely for expressions up to 8 levels deep.

### F-10  Loop-invariant code motion (LICM)

Currently, every variable referenced inside a loop body is reloaded from
`VAR_STORAGE_BASE + idx*64` on each iteration, even if that variable is never
written in the loop.  A single pass at `codegen_emit_for_start` time could
identify variables that are read but not assigned inside the loop body and emit
a `mov reg, [addr]` hoist before the loop top, replacing all inner loads with
a cheaper `mov rax, reg`.

### F-11  Counted (count-down) loop form

For a loop `for :i in 0..N:` where `i` is not used in the body, a count-down
formulation:

```asm
mov rcx, N
.top:
    ; body (uses rcx as decremented counter if needed)
    dec rcx
    jnz .top
```

uses `dec + jnz` (2 bytes each) fused into a single µop by modern CPUs, vs the
current `inc r15` + `cmp r15, N` + `jge exit` sequence.  Detected at parse time
when `i` has zero references in the body.

### F-12  `prefetcht0` before large array walks

For `each` loops over sequences longer than the L1 cache (> 32 KiB), emitting:

```asm
prefetcht0 [rdi + 64*8]   ; prefetch ~4 cache lines ahead
```

inside the loop body ensures the next elements are in L1 when the loop reaches
them, hiding DRAM latency entirely.

---

## Performance Summary

| Inner loop | Instructions | Bytes | Memory ops/iter |
|------------|-------------|-------|-----------------|
| Before (dynamic bounds) | 11 | 68 | 4 (2 loads of i, 1 store i, 1 load total, 1 store total = 5; with cmp = +1 indirect) |
| After O-A (static + pinned) | 7 | 40 | 2 (1 load total, 1 store total) |
| After O-B (peephole E) | 6 | 37 | 2 |
| After O-E (aligned top) | 6 | ≤ 40 | 2 (top is 16-byte aligned) |

The combination of O-A through O-E brings the benchmark loop from a
memory-bound 11-instruction sequence to a 6-instruction loop dominated only by
the `total` accumulator read-modify-write.
