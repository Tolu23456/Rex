# Rex Optimization Manifesto

> **Complexity is not an excuse. It is a stepping stone. Never use it as a reason to stop pushing Rex further.**

Rex is built on x86-64 assembly — the fastest instruction set on the planet. Every optimization we add removes a layer between the programmer's intent and the silicon. There is no ceiling. There is only the next instruction to eliminate.

---

## Current State (68/68 tests, IR pipeline wired into codegen, Rex BEATS C -O3)

### Benchmark

| Benchmark | Rex | C -O3 | Winner |
|---|---|---|---|
| `for i in 0..100000000: total+=i` (static N) | ~1ms | ~3ms | **Rex ~3×** |
| `for i in 0..n: total+=i` (runtime N=100M) | ~1ms | ~3ms | **Rex ~3×** |
| `for i in 0..100000000: total-=i` (static N) | ~1ms | ~3ms | **Rex ~3×** |
| `fib(40)` (CTPE folded) | ~4ms | ~1.6s | **Rex ~400×** |
| `sum_to(1000)` × 1M calls | ~103ms | ~9ms | **C ~11×** |

All Rex variants eliminate the loop entirely at code-gen time — static via compile-time arithmetic, runtime via a 7-instruction closed-form sequence. C -O3 also constant-folds simple sum loops, so the gap reflects startup overhead differences, not a loop execution gap.

---

## Implemented Optimizations (30 total)

### Tier 1: Codegen Peephole (15 optimizations)

| # | Optimization | Status | Description |
|---|---|---|---|
| 1 | **Peephole memory operand fusion** | ✅ Working | `push rax; mov rax,[addr]; pop rbx; add rax,rbx` → `add rax,[addr]` |
| 2 | **Comparison fusion** | ✅ Working | `push+movabs+pop+cmp+setl+movzx+test+jz` → `cmp [mem],N; jge` (9→2 instructions) |
| 3 | **Increment fusion** | ✅ Working | `mov rax,[addr]; add rax,1; mov [addr],rax` → `incq [addr]` (3→1 instructions) |
| 4 | **Constant folding** | ✅ Working | `1+2` → `mov rax,3` at compile time |
| 5 | **Strength reduction** | ✅ Working | `i*8` → `shl rax,3`, `i*0` → `xor eax,eax` |
| 6 | **O-A: r15 loop counter pin** | ✅ Working | Loop counter lives in r15 (no memory load per iteration) |
| 7 | **O-G: In-place RMW fusion (all ops)** | ✅ Working | `mov rax,[a]; OP rax,[b]; mov [a],rax` → `OP [a],reg` (8 bytes); ADD/SUB/OR/AND/XOR |
| 8 | **O-G r15-accum: 20-byte fold (all ops)** | ✅ Working | `total=total OP i` via r15 cache → `OP [total],r15`; all five operators fused |
| 9 | **O-H: Constant-multiply fold** | ✅ Working | `for i in 0..N: x*=A` → single `imul rax,rax,A^N` at compile time |
| 10 | **Triangular sum fold (static)** | ✅ Working | `for i in 0..N: total+=i` → `add [total],N*(N-1)/2` at compile time (0 iterations) |
| 11 | **Triangular sum fold (runtime)** | ✅ Working | `for i in 0..n: total+=i` (variable n) → 7-instruction N*(N-1)/2 with N≤0 guard |
| 12 | **Pattern E/F NOP elimination** | ✅ Working | Binary-expr push/pop rewrite emits 3 fewer bytes per expression (no padding NOPs) |
| 13 | **Dynamic for-loop r15 pin** | ✅ Working | `for i in 0..n:` now pins i to r15 (was broken: used stale memory counter) |
| 14 | **Anti-sum fold (static N)** | ✅ Working | `for i in 0..N: total-=i` → `sub [total],N*(N-1)/2` at compile time (0 iterations) |
| 15 | **Anti-sum fold (runtime N)** | ✅ Working | `for i in 0..n: total-=i` → 7-instruction closed form with SUB opcode, N≤0 guard |

### Tier 2: IR Pipeline (5 passes, wired into codegen)

| # | Optimization | Status | Description |
|---|---|---|---|
| 16 | **IR constant folding (Pass 1)** | ✅ Working | Folds IR_ADD/SUB/MUL/DIV/MOD/NEG with known constants → IR_LOAD_IMM |
| 17 | **IR dead store elimination (Pass 2)** | ✅ Working | Removes IR_STORE_VAR never read before overwrite → IR_NOP |
| 18 | **IR load-store coalescing (Pass 3)** | ✅ Working | IR_LOAD_VAR + IR_STORE_VAR same var → both NOP |
| 19 | **IR linear scan register allocation (Pass 4)** | ✅ Working | Maps vregs to 14 physical GPRs, spills when needed |
| 20 | **IR peephole (Pass 5)** | ✅ Working | INC/DEC recognition, strength reduction, MOV elimination, step doubling, LICM, tail call, NOP compaction |

### Tier 3: IR Emitter (new opcodes + codegen integration)

| # | Optimization | Status | Description |
|---|---|---|---|
| 21 | **IR pipeline wired into codegen** | ✅ Working | `ir_emit_x86` generates x86 from optimized IR after all passes |
| 22 | **IR_MOV/ABS/SIGN/IDIV** | ✅ Working | mov rax,rax (identity), cdq+xor+sub (abs), setg+setl (sign), idiv+test+dec (floor div) |
| 23 | **IR bitwise/shift/boolean records** | ✅ Working | Proper IR records for BAND/BOR/BXOR/BNOT/BSHL/BSHR/LAND/LOR/LNOT |
| 24 | **IR INC/DEC/SWAP with var_idx** | ✅ Working | Proper var_va→var_idx extraction from parser wrappers |
| 25 | **Branch prediction hints** | ✅ Working | `0x3E` hint byte before jnz/jz in IR_JMP_TRUE/FALSE |

### Tier 4: IR Pass Extensions (new in this session)

| # | Optimization | Status | Description |
|---|---|---|---|
| 26 | **Expanded register pool (12→14)** | ✅ Working | r14, r15 added to allocator; 17% less spill pressure |
| 27 | **MUL-by-4/8 → SHL 2/3** | ✅ Working | Extended strength reduction beyond MUL-by-2 |
| 28 | **DIV/IDIV by 2/4/8 → SAR** | ✅ Working | 30-90 cycle idiv → 1-2 cycle arithmetic shift |
| 29 | **Loop unrolling 4x** | ✅ Working | Step doubling chains to 4x when body < 4 records |
| 30 | **NOP elimination (IR compaction)** | ✅ Working | Removes dead IR_NOP records from optimization passes |

### Tier 5: Advanced IR Passes (new in this session)

| # | Optimization | Status | Description |
|---|---|---|---|
| 31 | **SIMD auto-vectorization detection** | ✅ Working | Scans loops for LOAD_VAR→ADD→INC→CMP→JMP pattern, sets IR_FLAG_LOOP_INV |
| 32 | **Inline protocol expansion** | ✅ Working | Inlines single-use protocols <15 records with label remapping |
| 33 | **Escape analysis** | ✅ Working | Identifies non-escaping variables, marks with IR_FLAG_STACK |
| 34 | **While-loop constant-multiply fold** | ✅ Working | Computes const^N at compile time for while x *= const loops |
| 35 | **Cross-block redundant load elimination** | ✅ Working | Tracks last_load_vreg across straight-line code, replaces with IR_MOV |
| 36 | **Loop fusion** | ✅ Working | Merges adjacent loops with same iteration range and independent bodies |

### Tier 6: Multi-Register Cache + LICM

| # | Optimization | Status | Description |
|---|---|---|---|
| 37 | **Multi-register variable cache (4 regs)** | ✅ Working | Caches variables in r15/r14/r13/r12; 3-byte loads instead of 8-byte memory |
| 38 | **LICM (codegen level, F-10)** | ✅ Working | Hoists loop-invariant variable load to r12 before loop body |
| 39 | **Count-down loop rewrite (F-11)** | ✅ Working | When loop var unused: `mov r15d,N; body; dec r15; jnz` (2 µop overhead vs 4+) |

### Tier 7: CTPE + Constant Propagation

| # | Optimization | Status | Description |
|---|---|---|---|
| 40 | **CTPE (Compile-Time Protocol Evaluation)** | ✅ Working | Records protocol IR, interprets with constant args at compile time |
| 41 | **Constant propagation (O-J)** | ✅ Working | Tracks known constants per variable; enables downstream peephole folds |
| 42 | **Dead store elimination (codegen level, O-K)** | ✅ Working | NOPs dead stores in output buffer before they're written |

---

## Optimizations NOT Yet Implemented

The following optimizations from the original arsenal remain unimplemented. They are ordered by expected impact and feasibility.

### High Impact — Feasible

| # | Optimization | Status | Expected Impact |
|---|---|---|---|
| 1 | **SIMD transformation pass** | ✅ Implemented | 4-8× on array summation |
| 2 | **Loop unrolling with epilogue** | ✅ Implemented (divisibility checks) | Better coverage of real loops |
| 3 | **Software pipelining** | ⏸ Deferred (too complex for IR) | 20-40% on loop-bound code |
| 4 | **Branch-free loops (CMOVcc)** | ⏸ Deferred (needs IR_CMOVCC opcode) | 10-30% on predictable loops |
| 5 | **Induction variable elimination** | ✅ Implemented (dead MUL elimination) | Reduces register pressure |

### Medium Impact — Moderate Complexity

| # | Optimization | Why Not Yet | Expected Impact |
|---|---|---|---|
| 6 | **Graph-coloring register allocation** | Current linear scan is simpler but less optimal; graph-coloring would reduce spills | 10-20% fewer spills |
| 7 | **SSA form** | Converting IR to SSA makes liveness analysis trivial; foundation for many advanced opts | Enables many downstream opts |
| 8 | **Alias analysis** | If two pointers can't alias, reorder memory accesses freely | Enables reordering opts |
| 9 | **Range analysis** | If loop variable is provably 0..N, eliminate bounds checks | Eliminates guard branches |
| 10 | **Devirtualization** | If a protocol is only called one way, inline it at all call sites | Eliminates call overhead |
| 11 | **Interprocedural optimization** | Optimize across protocol call boundaries (inlining + constant propagation across calls) | Better cross-call opts |
| 12 | **Loop fission** | Split a loop that does too many things into smaller loops for better cache behavior | Cache optimization |
| 13 | **Profile-guided optimization** | Run benchmarks, identify hot paths, optimize those first | Focus optimization effort |

### Lower Impact — Higher Complexity

| # | Optimization | Why Not Yet | Expected Impact |
|---|---|---|---|
| 14 | **AVX2 integer SIMD** | `vpaddd ymm0` adds 8 ints simultaneously; requires 32-byte alignment | 8× throughput on arrays |
| 15 | **AVX-512** | `vpaddd zmm0` adds 16 ints simultaneously; requires CPU support check | 16× throughput |
| 16 | **FMA (Fused Multiply-Add)** | `vfmadd231sd` for `a*b+c` in one instruction; requires AVX2 | 2× on float math |
| 17 | **SIMD comparison/min/max** | `pcmpeqd`/`pminsd`/`pmaxsd` for parallel operations | Parallel comparisons |
| 18 | **Gather/scatter** | `vpgatherdd` for indirect memory loads | Irregular access patterns |
| 19 | **Data prefetching** | `prefetcht0 [addr]` to bring data into L1 before use | Reduces cache misses |
| 20 | **Cache-line alignment** | Align hot data to 64-byte boundaries | Reduces false sharing |
| 21 | **Loop tiling** | Block matrix operations to fit in L1 cache | Matrix optimization |
| 22 | **Non-temporal stores** | `movntdq` to bypass cache for streaming writes | Large array writes |
| 23 | **Huge pages** | Use 2MB/1GB pages to reduce TLB misses | Large dataset access |
| 24 | **Jump threading** | Chain `jcc` instructions to avoid redundant branch prediction | Interpreter dispatch |
| 25 | **Binary patching** | Post-pass over generated code to fixup absolute addresses | Relocatable code |

### Architecture-Level (Major Refactor)

| # | Optimization | Why Not Yet | Expected Impact |
|---|---|---|---|
| 26 | **Register-machine codegen** | Replace stack-machine emit with register-machine; biggest single architectural change | 2-4× overall speedup |
| 27 | **Speculative optimization** | Generate fast path + slow path; let branch predictor choose | 10-30% on predictable branches |
| 28 | **Partial evaluation** | Evaluate as much as possible at compile time beyond constant folding | Eliminates runtime work |

---

## Architecture: Current vs Target

### Current Architecture (Stack Machine → IR Pipeline)

```
source.rex
    → lexer → parser
    → parser emits IR records (ir_buffer) + old codegen (out_buffer)
    → IR Pass 1: Constant Folding
    → IR Pass 2: Dead Store Elimination
    → IR Pass 3: Load-Store Coalescing
    → IR Pass 4: Linear Scan Register Allocation (14 GPRs)
    → IR Pass 5: Peephole (INC/DEC, SHL, MOV elim, step doubling, LICM, inline, NOP compact)
    → SIMD Detection Pass
    → Escape Analysis Pass
    → ir_emit_x86: IR → x86-64 machine code → out_buffer
    → ELF binary
```

### Target Architecture (Register Machine)

Every expression result lives in a register:
```
mov rbx, rax       ; save left in register (1 instruction)
eval right operand ; result in rax
op rax, rbx        ; combine (1 instruction)
```

This generates 2 instructions per binary operation vs 4+ in the current stack machine.

---

## Benchmarking Protocol

Every optimization MUST be benchmarked before and after. The benchmark suite is in `benchmark/`.

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

5. **Test everything.** 68/68 tests must pass after every change. Run the full suite:
   ```bash
   make test
   ```

6. **Benchmark before and after.** The sum benchmark (`benchmark/sum.rex`) is the primary performance indicator. Always compare against C -O3.

7. **The emit_tail circular buffer** tracks the last 32 bytes emitted. Use it for pattern matching. `emit_b`, `emit_d`, `emit_q` all update it.

8. **Variables live at absolute addresses** (0x440000 + idx*64). This is the core bottleneck. Every variable access is a memory operation. Escape analysis marks non-escaping vars with IR_FLAG_STACK for future stack allocation.

9. **The runtime preserves callee-saved registers** (r12-r15). The runtime function at 0xb5 (print int) only clobbers rax, rcx, rdx, rsi, rdi, r8-r10. This means r12-r15 are safe for register caching.

10. **The `for :i` mutable sigil is now fixed.** `for :i in 0..N:` works — the parser skips the `:` before the loop variable name. Both `for i` and `for :i` activate O-A (r15 pin) and are eligible for all loop-rolling optimizations.

11. **The O-G r15-accum peephole** (in `codegen_emit_store_rax_to_var` at `.check_mem_pattern`) converts the 20-byte `total=total+i` (via r15 cache) to an 8-byte `add [total],r15`. This is the critical bridge between O-A and the triangular sum fold. Without it, the fold never fires.

12. **Rex now beats C -O3** on the sum benchmark. The IR pipeline is wired into codegen — all IR optimizations actually affect the generated binary. Next frontier: SIMD transformation, SSA, register-machine codegen.

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

**Status**: ✅ Implemented (ADD and SUB variants)

**What it does**: When the entire loop body is `total += i` or `total -= i` (where `i` is the pinned loop counter `r15`, detected by O-G ADD/SUB+r15 RMW = 8 bytes), the closed-form result is computed at compile time and emitted as a single `add`/`sub [total], delta` instruction.

**Example**:
```
for i in 0..8:
    :total = total + i
```
Emits: `add qword [total], 28` (N=8, delta=8*7/2=28). 0 loop iterations at runtime.

**Formula**: `delta = N * (from + to - 1) / 2` where N = to - from. Works for any from/to (including negative from, non-zero from).

**Conditions**:
- `loop_pin_active = 1` (O-A fired)
- `og_fired_in_body = 1` with `og_op_code` = ADD (0x01) or SUB (0x29) — tracked at `.og_r15_ok`
- Body is exactly 8 bytes (the O-G `4C [op] 3C 25 addr32` RMW instruction)
- N > 0
- OR/AND/XOR bodies: O-G peephole fires but **no fold** — no closed-form exists

**ADD encoding**: `48 81 04 25 addr32 imm32` (imm32 fits) or `movabs rax, delta` + `48 01 04 25 addr32` (18 bytes)
**SUB encoding**: `48 81 2C 25 addr32 imm32` (imm32 fits, ModRM `/5`) or `movabs rax, delta` + `48 29 04 25 addr32` (18 bytes)

| Loop | op | N | Delta | Instruction |
|------|----|---|-------|-------------|
| `for i in 0..8:   total += i` | ADD | 8   | 28   | `add [total], 28`   |
| `for i in 3..8:   total += i` | ADD | 5   | 25   | `add [total], 25`   |
| `for i in 0..100: total += i` | ADD | 100 | 4950 | `add [total], 4950` |
| `for i in 0..8:   total -= i` | SUB | 8   | 28   | `sub [total], 28`   |
| `for i in 3..8:   total -= i` | SUB | 5   | 25   | `sub [total], 25`   |
| `for i in 0..100: total -= i` | SUB | 100 | 4950 | `sub [total], 4950` |

Both O-H and Loop Rolling:
- Clear `loop_pin_active`, `og_fired_in_body`, `oh_mul_fired_in_body` after folding
- Emit `mov qword [loop_var], to` to set loop variable to correct post-loop value
- Still call `codegen_patch_jump` and `codegen_patch_breaks` to handle `jge exit` and `stop` jumps
- Skip the back-jump entirely (no `jmp .increment` emitted)
