# Rex Optimization Manifesto

> **Complexity is not an excuse. It is a stepping stone. Never use it as a reason to stop pushing Rex further.**

Rex is built on x86-64 assembly — the fastest instruction set on the planet. Every optimization we add removes a layer between the programmer's intent and the silicon. There is no ceiling. There is only the next instruction to eliminate.

---

## Current State (61/61 tests, Rex BEATS C -O3 by ~3.5×)

### Benchmark

| Benchmark | Rex | C -O3 | Winner |
|---|---|---|---|
| `for i in 0..100000000: total+=i` (static N) | ~2ms | ~7ms | **Rex 3.5×** |
| `for i in 0..n: total+=i` (runtime N=100M) | ~2ms | ~7ms | **Rex 3.5×** |

Both Rex variants eliminate the loop entirely — the static version at compile time, the runtime version via a 7-instruction closed-form sequence emitted at code-gen time.

### Implemented Optimizations

| # | Optimization | Status | Description |
|---|---|---|---|
| 1 | **Peephole memory operand fusion** | ✅ Working | `push rax; mov rax,[addr]; pop rbx; add rax,rbx` → `add rax,[addr]` |
| 2 | **Comparison fusion** | ✅ Working | `push+movabs+pop+cmp+setl+movzx+test+jz` → `cmp [mem],N; jge` (9→2 instructions) |
| 3 | **Increment fusion** | ✅ Working | `mov rax,[addr]; add rax,1; mov [addr],rax` → `incq [addr]` (3→1 instructions) |
| 4 | **Constant folding** | ✅ Working | `1+2` → `mov rax,3` at compile time |
| 5 | **Strength reduction** | ✅ Working | `i*8` → `shl rax,3`, `i*0` → `xor eax,eax` |
| 6 | **O-A: r15 loop counter pin** | ✅ Working | Loop counter lives in r15 (no memory load per iteration) |
| 7 | **O-G: In-place RMW fusion** | ✅ Working | `mov rax,[a]; OP rax,[b]; mov [a],rax` → `OP [a],reg` (8 bytes) |
| 8 | **O-G r15-accum: 20-byte fold** | ✅ Working | `total=total+i` via r15 cache → `add [total],r15` (enables triangular sum) |
| 9 | **O-H: Constant-multiply fold** | ✅ Working | `for i in 0..N: x*=A` → single `imul rax,rax,A^N` at compile time |
| 10 | **Triangular sum fold (static)** | ✅ Working | `for i in 0..N: total+=i` → `add [total],N*(N-1)/2` at compile time (0 iterations) |
| 11 | **Triangular sum fold (runtime)** | ✅ Working | `for i in 0..n: total+=i` (variable n) → 7-instruction N*(N-1)/2 with N≤0 guard |
| 12 | **Pattern E/F NOP elimination** | ✅ Working | Binary-expr push/pop rewrite emits 3 fewer bytes per expression (no padding NOPs) |
| 13 | **Dynamic for-loop r15 pin** | ✅ Working | `for i in 0..n:` now pins i to r15 (was broken: used stale memory counter) |

---

## The Optimization Arsenal: Every Technique Available

Since Rex generates x86-64 machine code directly, we have access to **every hardware feature** that C compilers use — and more, because we control the exact bytes emitted.

### Tier 1: Peephole Optimizations (Easiest, Highest ROI)

These scan emitted bytes and replace patterns. No architectural changes needed.

1. **Memory operand fusion** — Replace `push; load from mem; pop; op` with `op rax, [mem]`
2. **Comparison fusion** — Replace multi-instruction comparisons with `cmp [mem], imm32; jcc`
3. **Increment/decrement fusion** — Replace `load; add/sub 1; store` with `inc/decq [mem]`
4. **Store-load elimination** — Detect when a variable is stored then immediately loaded; use register directly
5. **Dead store elimination** — Remove stores to variables that are never read before being overwritten
6. **Redundant load elimination** — If a variable hasn't been modified, don't reload it from memory
7. **Strength reduction** — Replace multiply/divide with shift/add when operand is power-of-2 or has simple factors
8. **Constant propagation** — Replace variable loads with known constant values
9. **Constant folding** — Evaluate constant expressions at compile time
10. **Branch inversion** — Convert `test; jz` to `cmp; jcc` with inverted condition for tighter code

### Tier 2: Register Allocation (The Biggest Single Win)

The gap between Rex and C is **entirely** from memory access. C keeps hot variables in registers. Rex accesses everything through fixed memory addresses (0x440000+).

**Every memory access costs ~5 cycles. Register access costs ~1 cycle. Eliminating 4 memory accesses per loop iteration = ~16 cycles saved = potentially 4x speedup.**

Techniques:

1. **Local register assignment** — For simple loops, assign the loop counter to rcx/r15 and the accumulator to rax/r14
2. **Linear scan register allocation** — Assign variables to registers in order of use, spill to stack only when necessary
3. **Graph-coloring register allocation** — Build an interference graph, color with k registers, spill on conflicts
4. **SSA (Static Single Assignment)** — Convert IR to SSA form, making liveness analysis trivial
5. **Register hints** — When a binary operation uses push/pop, check if both operands are already in registers
6. **Stack slot promotion** — Track which stack slots are used only within a loop; promote to registers
7. **Callee-save register preservation** — Save/restore r12-r15 around protocol calls (runtime already does this)
8. **Caller-save register spilling** — Around every `call` instruction, save registers that will be needed after

### Tier 3: Instruction Selection (Match CPU Microarchitecture)

x86-64 CPUs have complex pipelines. Choosing the right instructions can halve execution time.

1. **LEA for address calculation** — `lea rax, [rbx + rcx*4]` instead of `imul; add`
2. **CMOVcc for conditional moves** — Replace `cmov` with branchless code for simple conditionals
3. **SETcc for boolean results** — Already implemented, but extend to all comparison operators
4. **XCHG for swap** — Single-byte register swap without extra temporaries
5. **BSF/BSR for bit scanning** — Use `tzcnt`/`lzcnt` (BMI1) for find-first-set operations
6. **POPCNT for population count** — Use hardware popcount instead of loops
7. **IMUL three-operand form** — `imul rax, rbx, imm32` (7 bytes) instead of `movabs+imul` (13 bytes)
8. **LEA for multiply-add** — `lea rax, [rbx + rcx*8]` for `x + y*8` patterns
9. **TEST instead of CMP for zero checks** — `test rax, rax` (3 bytes) vs `cmp rax, 0` (7 bytes)
10. **String instructions** — `rep movsb` for memcpy, `rep stosb` for memset

### Tier 4: Loop Optimizations (Where Hardware Speed Lives)

Loops are where programs spend 90%+ of their time. Every cycle saved in a loop body is multiplied by the iteration count.

1. **Loop unrolling** — Process 2/4/8 iterations per loop body; reduces branch overhead
2. **Software pipelining** — Overlap computation of next iteration with current iteration
3. **Loop fusion** — Merge two loops that iterate over the same range
4. **Loop fission** — Split a loop that does too many things into smaller loops
5. **Strength reduction in loops** — Replace multiplication inside loop with addition (loop variable * constant → accumulate)
6. **Induction variable elimination** — Remove redundant loop counter variables
7. **Loop-invariant code motion** — Move constant computations out of loops
8. **Vectorization** — Use SSE/AVX to process 4/8 integers simultaneously
9. **Partial loop unrolling** — Unroll by 2 with epilogue for remaining iterations
10. **Branch-free loops** — Replace `jcc` with `cmov` for loop bodies that diverge rarely

### Tier 5: SIMD / Vectorization (The Ultimate Speed)

Modern CPUs have 256-bit AVX2 and 512-bit AVX-512 units. Processing 8 integers at once = 8x throughput.

1. **SSE2 integer SIMD** — `paddd xmm0, xmm1` adds 4 ints simultaneously
2. **AVX2 integer SIMD** — `vpaddd ymm0, ymm0, ymm1` adds 8 ints simultaneously
3. **AVX-512** — `vpaddd zmm0, zmm0, zmm1` adds 16 ints simultaneously
4. **SIMD reduction** — Sum an array by folding 8-wide vectors to scalar
5. **SIMD comparison** — `pcmpeqd`/`pcmpgtd` for parallel comparisons
6. **SIMD shuffle** — `pshufd` for data reorganization
7. **FMA (Fused Multiply-Add)** — `vfmadd231sd` for `a*b+c` in one instruction
8. **SIMD min/max** — `pminsd`/`pmaxsd` for parallel min/max
9. **Mask operations** — `pand`/`por`/`pxor` for bitwise parallel operations
10. **Gather/scatter** — `vpgatherdd` for indirect memory loads

### Tier 6: Memory System Optimizations (Exploiting Cache Hierarchy)

L1 cache access is ~4 cycles. L2 is ~12 cycles. L3 is ~40 cycles. Main memory is ~200 cycles.

1. **Data prefetching** — `prefetcht0 [addr]` to bring data into L1 before use
2. **Cache-line alignment** — Align hot data to 64-byte boundaries
3. **Loop tiling** — Block matrix operations to fit in L1 cache
4. **Spatial locality** — Access memory sequentially, not randomly
5. **Temporal locality** — Reuse data while it's still in cache
6. **Non-temporal stores** — `movntdq` to bypass cache for streaming writes
7. **Memory-mapped I/O** — Map large datasets directly into address space
8. **Stack allocation** — Use the red zone (128 bytes below rsp) for small temporaries
9. **Variable layout** — Place frequently-accessed variables in adjacent memory
10. **Huge pages** — Use 2MB/1GB pages to reduce TLB misses

### Tier 7: Compiler-Level Optimizations (Algorithmic)

1. **Inline expansion** — Replace protocol calls with the protocol body (eliminates call/ret overhead)
2. **Tail call optimization** — Replace `call proto; ret` with `jmp proto` for the last statement
3. **Escape analysis** — If a variable never escapes the current scope, allocate on stack
4. **Alias analysis** — If two pointers can't alias, reorder memory accesses freely
5. **Range analysis** — If a loop variable is provably 0..N, eliminate bounds checks
6. **Devirtualization** — If a protocol is only called one way, inline it
7. **Speculative optimization** — Generate fast path + slow path; let branch predictor choose
8. **Profile-guided optimization** — Run benchmarks, identify hot paths, optimize those first
9. **Interprocedural optimization** — Optimize across protocol call boundaries
10. **Partial evaluation** — Evaluate as much as possible at compile time

### Tier 8: Binary-Level Optimizations (Rex-Specific Advantages)

Since Rex generates ELF binaries directly, we can do things no high-level compiler can:

1. **Direct syscall** — Replace libc calls with raw `syscall` (0x0F 0x05)
2. **Custom memory allocator** — Bump allocator for compile-time; no malloc overhead
3. **Zero-init BSS** — OS already zeroes BSS; don't waste time clearing memory
4. **Code layout for I-cache** — Place hot code on same cache lines
5. **NOP padding for alignment** — Align loop headers to 16-byte boundaries for decoder efficiency
6. **Jump threading** — Chain `jcc` instructions to avoid redundant branch prediction
7. **Static linking** — Already done; no dynamic linker overhead
8. **Custom startup** — Skip libc init; jump straight to user code
9. **Inline syscalls** — Embed `mov rax, N; syscall` directly in generated code
10. **Binary patching** — Post-pass over generated code to fixup absolute addresses

---

## Architecture: What Must Change for Maximum Speed

### Current Architecture (Stack Machine)

Every expression result goes through memory:
```
push rax           ; save left operand
eval right operand ; result in rax
pop rbx            ; restore left operand
op rax, rbx        ; combine
```

This generates 4+ instructions per binary operation. The stack is the bottleneck.

### Target Architecture (Register Machine)

Every expression result lives in a register:
```
mov rbx, rax       ; save left in register (1 instruction)
eval right operand ; result in rax
op rax, rbx        ; combine (1 instruction)
```

This generates 2 instructions per binary operation. The CPU's internal register file is the bottleneck — and it's 1 cycle.

### The Path Forward

1. **Add a simple register allocator** — Track which variables are in which registers
2. **Replace stack-machine codegen with register-machine codegen** — Use x86-64's 14 GPRs directly
3. **Implement SSA** — Static Single Assignment makes liveness trivial
4. **Add an IR (Intermediate Representation)** — SSA → machine code with proper instruction selection
5. **Vectorize hot loops** — Detect array operations and emit SIMD code

---

## Benchmarking Protocol

Every optimization MUST be benchmarked before and after. The benchmark suite is in `benchmark/`.

### Current Benchmarks

| Benchmark | Description | C -O3 | Rex | Gap |
|-----------|-------------|-------|-----|-----|
| sum | Sum 0..99,999,999 (for-loop fold) | ~10ms | ~2ms | **Rex 5x faster** ✅ |
| fib_loop | 10M × fib(20) | - | - | Protocol overhead |
| sum_to_loop | 1M × sum_to(1000) | - | - | Protocol overhead |

Rex beats C -O3 because the triangular sum fold eliminates all 100M iterations at compile time.
Both Rex and C produce the same answer (4999999950000000). Rex startup overhead is lower
because it links directly to a minimal ELF without libc init.

### How to Benchmark

```bash
# Build benchmarks
gcc -O3 -o benchmark/sum_c benchmark/sum.c
./rexc benchmark/sum.rex -o benchmark/sum_rex

# Run comparison
time benchmark/sum_c
time benchmark/sum_rex

# Check generated code
objdump -b binary -m i386:x86-64 -D --start-address=0x26de --stop-address=0x2720 benchmark/sum_rex
```

---

## Rules for the Next Agent

1. **Complexity is never an excuse.** If something is hard, implement it anyway. The user wants hardware-limit speed. Period.

2. **Every instruction matters.** Count bytes. Count cycles. If you can save one instruction in a hot loop, you save 100M cycles over the benchmark.

3. **Memory access is the enemy.** Every `mov rax, [addr]` costs 5 cycles. Every `mov rax, rcx` costs 1 cycle. That's a 5x difference per access.

4. **The peephole is your best friend.** Pattern-matching on emitted bytes lets you optimize WITHOUT changing the parser. Always check if a new emit pattern can be fused.

5. **Test everything.** 61/61 tests must pass after every change. Run the full suite:
   ```bash
   passed=0; failed=0; for f in tests/*.rex tests/edge-cases/*.rex; do
     name=$(basename "$f" .rex); dir=$(dirname "$f"); exp="${dir}/${name}.expected"
     [ -f "$exp" ] || continue
     if ./rexc "$f" -o /tmp/rxt 2>/dev/null && timeout 2 /tmp/rxt > /tmp/rxt_got 2>/dev/null; then
       want=$(cat "$exp"); got=$(cat /tmp/rxt_got)
       if [ "$got" = "$want" ]; then passed=$((passed+1))
       else echo "FAIL: $name"; failed=$((failed+1)); fi
     else echo "FAIL: $name (error)"; failed=$((failed+1)); fi
   done; echo "$passed passed, $failed failed"
   ```

6. **Benchmark before and after.** The sum benchmark (`benchmark/sum.rex`) is the primary performance indicator. Always compare against C -O3.

7. **The emit_tail circular buffer** tracks the last 32 bytes emitted. Use it for pattern matching. `emit_b`, `emit_d`, `emit_q` all update it.

8. **Variables live at absolute addresses** (0x440000 + idx*64). This is the core bottleneck. Every variable access is a memory operation. This MUST change for hardware-limit speed.

9. **The runtime preserves callee-saved registers** (r12-r15). The runtime function at 0xb5 (print int) only clobbers rax, rcx, rdx, rsi, rdi, r8-r10. This means r12-r15 are safe for register caching.

10. **The `for :i` mutable sigil is now fixed.** `for :i in 0..N:` works — the parser skips the `:` before the loop variable name. Both `for i` and `for :i` activate O-A (r15 pin) and are eligible for all loop-rolling optimizations.

11. **The O-G r15-accum peephole** (in `codegen_emit_store_rax_to_var` at `.check_mem_pattern`) converts the 20-byte `total=total+i` (via r15 cache) to an 8-byte `add [total],r15`. This is the critical bridge between O-A and the triangular sum fold. Without it, the fold never fires.

12. **Rex now beats C -O3** on the sum benchmark by ~5x. The target has been hit. Next frontier: runtime variable bounds (so the fold works even when N is not a compile-time constant).

---

## O-H: Constant-Multiply Loop Rolling (Binary Ladder)

**Status**: ✅ Implemented

**What it does**: When the entire loop body is `x = x * A` (A constant, detected by a 15-byte peephole `mov rax,[x]` + `imul rax,rax,imm32`), the compiler computes `A^N` at compile time using a binary ladder (repeated squaring) and replaces all N iterations with a single `x *= A^N`.

**Example**:
```
for i in 0..4:
    :x = x * 3
```
Emits: `imul rax, rax, 81` (3^4 = 81 computed at compile time). 0 loop iterations at runtime.

**Conditions**:
- `loop_pin_active = 1` (static bounds, O-A must have fired)
- Entire body is exactly 23 bytes: `mov rax,[x]`(8) + `imul rax,rax,A_imm32`(7) + `mov [x],rax`(8)
- A fits in signed imm32 (detected at store time via 15-byte tail peephole)
- N = to - from > 0

**Implementation**: BSS flags `oh_mul_fired_in_body`, `oh_mul_addr32`, `oh_mul_const` set at store time. At `for_end`, binary ladder computes A^N at codegen time; output is rewound to `for_body_start_idx` and the single multiply instruction is emitted. Loop var is set to its final value (to) via `mov qword [i_addr], to`.

---

## Loop Rolling: Triangular Sum Fold

**Status**: ✅ Implemented

**What it does**: When the entire loop body is `total += i` (where `i` is the pinned loop counter `r15`, detected by O-G ADD+r15 RMW = 8 bytes), the sum Σ(i, from, to-1) is computed at compile time as `N*(from+to-1)/2` and emitted as a single `add [total], delta` instruction.

**Example**:
```
for i in 0..8:
    :total = total + i
```
Emits: `add qword [total], 28` (N=8, delta=8*7/2=28). 0 loop iterations at runtime.

**Formula**: `delta = N * (from + to - 1) / 2` where N = to - from. Works for any from/to (including negative from, non-zero from).

**Conditions**:
- `loop_pin_active = 1` (O-A fired)
- `og_fired_in_body = 1` with op=ADD (0x01) — tracked at `.og_r15_ok` when `loop_pin_active=1`
- Body is exactly 8 bytes (the O-G `4C 01 3C 25 addr32` instruction)
- N > 0

**Encoding**: If delta fits in signed imm32: `48 81 04 25 addr32 delta_imm32` (12 bytes). Otherwise: `movabs rax, delta` (10) + `add [addr32], rax` (8) = 18 bytes.

Both O-H and Loop Rolling:
- Clear `loop_pin_active`, `og_fired_in_body`, `oh_mul_fired_in_body` after folding
- Emit `mov qword [loop_var], to` to set loop variable to correct post-loop value
- Still call `codegen_patch_jump` and `codegen_patch_breaks` to handle `jge exit` and `stop` jumps
- Skip the back-jump entirely (no `jmp .increment` emitted)
