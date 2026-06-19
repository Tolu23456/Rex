# Rex vs C Performance Bottleneck Report (T023)

## 1. Executive Summary
Rex V5.0 demonstrates near-parity or superiority to C in specific workloads (compilation speed, startup latency, simple arithmetic, constant-folded loops). However, in general-purpose computational kernels (Fibonacci, nested loops, complex while-loops), Rex remains **2× to 4× slower than GCC -O3**.

The primary performance gap is not due to the instruction set or logic, but rather to **redundant memory traffic** and **ABI-constrained call overhead**.

## 2. Top 5 Performance Bottlenecks

### B1: Memory Round-trips for Mutable Variables
*   **Root Cause**: Rex stores almost all mutable variables in the `var_table` (memory). While O13/O14 promote the outermost loop's accumulator and O2 promote the loop counter, inner-loop variables are not promoted to registers.
*   **Impact**: In `B7 (Iterative Fib)`, Rex pays 3 loads and 3 stores per inner iteration. GCC keeps these in registers.
*   **Benchmark evidence**: B7 (C ~2.1× faster).
*   **Proposed Fix**: **O28 (Inner-loop Register Promotion)**. Retroactively scan inner loops for global variables and patch them to use `r12`/`r13`. This is partially implemented but restricted to non-recursive protocols (due to O18/O28 register contention).

### B2: System V ABI Call Overhead
*   **Root Cause**: Rex currently follows the SysV ABI for all protocol calls, involving 10+ instructions for stack alignment, `rbp` saving, and callee-saved register preservation.
*   **Impact**: In deep recursion or high-frequency calls, this overhead dominates the actual work.
*   **Benchmark evidence**: B3 (C ~2.4× faster), B6 (C ~2.7× faster).
*   **Proposed Fix**: **Internal Frameless ABI**. Transition inter-Rex calls to a custom convention:
    1.  Eliminate `rbp` frame pointer where not needed.
    2.  Use a "caller-saves-all" model between Rex protocols.
    3.  Ignore 16-byte alignment (8-byte is sufficient for internal calls).
    4.  Utilize the **Red Zone** for leaf calls to avoid `rsp` adjustments.

### B3: Intermediate Store/Load in Compound Expressions
*   **Root Cause**: The single-pass compiler emits code for each statement/expression component sequentially. It lacks a temporary-to-register promotion pass for intermediate results in multi-line calculations.
*   **Impact**: Even simple LCG steps like `:x = x * A; :x = x + B` result in a store-load cycle between the multiply and add.
*   **Benchmark evidence**: B1 (statistical tie, but Rex pays ~50ms more than strictly necessary due to this).
*   **Proposed Fix**: **Expression-Spill Optimization (O6/O29)**. Expand the use of `r13` as a zero-cost scratchpad for intermediate values within protocols.

### B4: Missing Mathematical Identity Folding
*   **Root Cause**: While Rex has advanced `O-Affine` folding for LCG-like loops (beating C by 1000×), it lacks folding for polynomial closed forms.
*   **Impact**: GCC recognizes `Σi*j` as a constant; Rex runs 9 million iterations.
*   **Benchmark evidence**: B12 (C >22× faster).
*   **Proposed Fix**: **Algebraic Reduction Pass**. Detect nested loops with induction-variable products and replace with the closed-form formula at compile time.

### B5: Lack of Scalar Evolution / Strength Reduction for Complex Dividers
*   **Root Cause**: Rex uses `idiv` for most divisions/modulos unless they are powers of 2 (O30).
*   **Impact**: Integer division is extremely slow (~20-40 cycles). GCC replaces non-power-of-2 division with reciprocal multiplication.
*   **Benchmark evidence**: B14 (C ~4× faster).
*   **Proposed Fix**: **O30-Ext (Magic Constant Division)**. Implement the Granlund-Montgomery algorithm to replace `idiv` by constant with `imul` + shift.

## 3. Quantified Speedup Projections

| Improvement | Targeted Benchmark | Est. Speedup | Status |
|---|---|---|---|
| **Frameless Internal ABI** | B6 (Recursive Fib) | **1.5× – 1.8×** | Proposed |
| **Full O28 (Inner-loop Regs)** | B7 (Iterative Fib) | **1.6× – 2.0×** | Partial |
| **Magic Constant Division** | B14 (While Log2) | **2.5× – 3.0×** | Planned |
| **Red Zone Leaf Opts** | B6 (Base cases) | **1.1×** | Proposed |
| **O6 Expression Glue** | B1 (Arithmetic) | **1.05×** | Implemented |

## 4. Conclusion
Rex is currently competitive with C on "wide" loops (high iterations, simple bodies) and specialized constant-folding cases. To achieve parity or dominance on general recursive and nested-loop code, the compiler must break free from the System V ABI for internal calls and aggressively move variable traffic from memory to registers (`r12-r15`).
