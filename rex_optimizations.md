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
| B4 | `codegen/codegen.asm` — `codegen_emit_for_start` | `get_var_va` returns the variable address in `rax`, but the immediately-following `mov al, 0x89/0x04/0x25` byte emissions clobbered the low byte of `rax` before `emit_d` consumed it (e.g. 0x440040 → 0x440025) | Save address with `mov rbx, rax` after `get_var_va`; restore with `mov rax, rbx` before `emit_d` |
| B5 | `codegen/codegen.asm` — `codegen_peephole` Pattern D | Pattern D used `mov ecx, eax` for a nibble check, clobbering `rcx` which holds the captured `out_idx` for the entire peephole scan; the scanner then terminated early at the corrupted end index | Changed `mov ecx, eax` → `mov edx, eax` throughout Pattern D |

After these fixes `bench_rex.rex` (`for :i in 0..10000000: :total = total + i`)
produces `49999995000000` correctly.

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
; = 11 instructions, 68 bytes, 5 memory ops per iteration
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

**Result — pinned inner loop (before O13/O14 fusion):**

```
; loop top (hot path):
cmp r15, 10000000       ; 7 bytes  ← immediate, no memory read
jnl exit                ; 6 bytes
mov rax, [total_addr]   ; 8 bytes
add rax, r15            ; 3 bytes  ← r15 used directly, no second memory load
mov [total_addr], rax   ; 8 bytes
inc r15                 ; 3 bytes  ← register increment, no memory write
jmp top                 ; 5 bytes
; = 7 instructions, 40 bytes, 2 memory ops/iter (down from 11 / 68 / 5)
```

**Combined with O13/O14 accumulator fusion (previously implemented), the actual
current inner loop is:**

```
49 81 FF 80 96 98 00   cmp r15, 10000000   ; 7 bytes — static immediate
0F 8D 0B 00 00 00      jnl exit            ; 6 bytes
4D 01 FE               add r14, r15        ; 3 bytes — O14: fused accum+pin add
49 FF C7               inc r15             ; 3 bytes — O2: register increment
E9 E8 FF FF FF         jmp loop_top        ; 5 bytes
; = 5 instructions, 24 bytes, 0 memory ops in hot path
```

Code size for the entire bench program: **119 bytes** (down from 147 bytes on
the fully dynamic path).

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

**Note on interaction with O14:**  In the benchmark, O14 strength-reduction
fusion replaces the `mov r10,rax; load; mov rbx,r10` body with a single
`add r14,r15`.  Pattern E therefore does not fire in the benchmark — it fires
in programs that use binary `+` on two non-pinned variables.

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

### O-F  FLC — Frameless Calling Convention

**File:** `codegen/codegen.asm` — `codegen_emit_frame_prologue`,
`codegen_emit_leave`, `codegen_clear_frame`, `codegen_emit_regalloc_epilogue`;
`parser/parser.asm` — `.prot_fs` param-store loop

**What it replaces.**

Every protocol call previously used the System V ABI frame pointer convention:

```asm
; prologue (4 bytes):
push rbp          ; 55
mov  rbp, rsp     ; 48 89 E5
sub  rsp, N       ; 48 81 EC <N32>

; epilogue:
leave             ; C9  (= mov rsp,rbp; pop rbp)
ret               ; C3
```

**Frameless replacement.**

Remove `push rbp; mov rbp,rsp` entirely.  Address all frame slots
`[rsp + K*8]` (positive offsets, bottom-up layout).  Replace `leave` with a
patched `add rsp, N`:

```asm
; prologue (7 bytes — saves 4):
sub rsp, N        ; 48 81 EC <N32>   (placeholder N, patched at clear_frame)

; epilogue:
add rsp, N        ; 48 81 C4 <N32>   (placeholder, patched to same N)
ret               ; C3
```

**Patch-back mechanism.**  Because N is not known until all locals are declared,
both the prologue `sub rsp` and every epilogue `add rsp` use placeholder `imm32 =
0`.  `codegen_emit_frame_prologue` records the prologue imm32 offset in
`frame_size_patch_pos`.  `codegen_emit_leave` records each epilogue imm32 offset
into `leave_patch_list[leave_patch_cnt++]`.  `codegen_clear_frame` patches all of
them with the computed frame size.

**Frame slot encoding (rsp-relative).**  `[rsp + disp8]` requires a SIB byte
since `rsp` as base triggers SIB-present encoding (`rm = 100`):

| Operation | Encoding | Bytes |
|-----------|----------|-------|
| `mov rax,[rsp+K*8]` | `48 8B 44 24 <K*8>` | 5 |
| `mov [rsp+K*8],rax` | `48 89 44 24 <K*8>` | 5 |
| `mov rdi,[rsp+K*8]` | `48 8B 7C 24 <K*8>` | 5 |
| `mov [rsp+K*8],rdi` | `48 89 7C 24 <K*8>` | 5 |
| `mov [rsp],r12`     | `4C 89 24 24`       | 4 |
| `mov r12,[rsp]`     | `4C 8B 24 24`       | 4 |
| `mov [rsp+8],r13`   | `4C 89 6C 24 08`    | 5 |
| `mov r13,[rsp+8]`   | `4C 8B 6C 24 08`    | 5 |

`[rbp-K*8]` was 4 bytes (no SIB needed for rbp base); `[rsp+K*8]` costs one
extra SIB byte per access, but the saved `push rbp; mov rbp,rsp` (4 bytes of
prologue, ~2 µops) and the simpler `add rsp` epilogue (vs `leave` which is
micro-sequenced) more than compensate.

**ModRM table for param stores in `.prot_fs` (`parser.asm`).**  Stores of ABI
argument registers into frame slots use ModRM `mod=01, rm=100` (SIB present):

```
reg:      rdi    rsi    rdx    rcx    r8     r9
ModRM:    0x7C   0x74   0x54   0x4C   0x44   0x4C
```

Followed by `SIB = 0x24` and `disp8 = (K + regalloc_cnt) * 8`.

**Measured gain (fib(42), 700 M recursive calls):**
`1355 ms → 1288 ms` (~67 ms, ~5 %).  Smaller than expected because modern CPUs
rename `push rbp` / `mov rbp,rsp` at near-zero latency via the stack engine;
the main savings come in register pressure and code density, not µop count.

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

### Benchmark: `for :i in 0..10000000: :total = total + i`

| Stage | Instructions (hot loop) | Bytes (hot loop) | Mem ops/iter | Total code size |
|-------|------------------------|-----------------|--------------|-----------------|
| Baseline (fully dynamic) | 11 | 68 | 5 | 147 bytes |
| + O-A (static pin, r15) | 7 | 40 | 2 | — |
| + O-D (9-byte `__le` init) | 7 | 40 | 2 | — |
| + O-E (16-byte loop alignment) | 7 | ≤ 55 | 2 | — |
| + O13/O14 accum fusion (r14) | **5** | **24** | **0** | **119 bytes** |

The inner hot loop is now:

```
49 81 FF 80 96 98 00   cmp r15, 10000000   ; static immediate — no load
0F 8D 0B 00 00 00      jnl exit
4D 01 FE               add r14, r15        ; O14 fused accum+pin (3 bytes)
49 FF C7               inc r15             ; O2 register increment (3 bytes)
E9 E8 FF FF FF         jmp loop_top
```

All five instructions are single-µop.  Zero memory operations in the hot path.

### Benchmark: `fib(42)` (700 M recursive calls)

| Stage | Time | Notes |
|-------|------|-------|
| Before FLC | ~1355 ms | rbp-relative frame, `push rbp; leave` |
| After O-F (FLC) | ~1288 ms | rsp-relative frame, `sub rsp; add rsp` |
| Gain | ~67 ms (~5%) | Stack engine makes `push rbp` near-free; savings mainly from code density |
| vs C (`gcc -O2`) | ~377 ms | Rex ~3.4× slower; remaining gap is 4 spill/reload ops per call vs C's 0 |

---

## O-H: Constant-Multiply Loop Rolling

**Pattern**: `for i in 0..N: x = x * A` → replace N iterations with `x *= A^N` (A^N computed at compile time via binary ladder).

**Detection**: 15-byte tail peephole at `codegen_emit_store_rax_to_var` detects `mov rax,[x_addr](8) + imul rax,rax,imm32(7)` preceding the store to the same address. Sets `oh_mul_fired_in_body=1`, `oh_mul_addr32`, `oh_mul_const=A`.

**At `for_end`**: Requires `loop_pin_active=1` (O-A), body length exactly 23 bytes, N>0. Binary ladder computes A^N in O(log N) multiplications during codegen. Output rewound to `for_body_start_idx`. Emits 23 bytes (imm32) or 26 bytes (movabs, if A^N > 2^31-1).

**Gain**: Eliminates N-1 iterations, the back-jump, and the loop counter check entirely.

```
; for i in 0..4: x = x * 3   (A=3, N=4, A^N=81)
; Loop preamble (dead code, harmless):
xor r15d, r15d
jmp .check
.check: cmp r15, 4 ; jge exit   ← never taken
; Rolled body (emitted once, executes once):
mov rax, [x_addr]
imul rax, rax, 81
mov [x_addr], rax
; Loop-var cleanup:
mov qword [i_addr], 4
exit:
```

---

## Loop Rolling: Triangular Sum

**Pattern**: `for i in 0..N: total += i` → replace N iterations with `total += N*(from+to-1)/2`.

**Detection**: O-G ADD+r15 RMW fires at `.og_r15_ok`. If `loop_pin_active=1` and op=ADD, sets `og_fired_in_body=1` and `og_rw_addr32`. At `for_end`: body must be exactly 8 bytes (the 8-byte `4C 01 3C 25 addr32` RMW).

**Formula**: `delta = N*(from+to-1)/2` where N=to-from. Correct for any from/to including negative from.

**Gain**: Replaces N memory-touching loop iterations with a single `add [total], delta` (12 bytes) or `movabs+add` (18 bytes for very large delta).

| Loop | N | Delta | Instruction |
|------|---|-------|-------------|
| `for i in 0..8: total += i` | 8 | 28 | `add [total], 28` |
| `for i in 3..8: total += i` | 5 | 25 | `add [total], 25` |
| `for i in 0..100: total += i` | 100 | 4950 | `add [total], 4950` |

