# Agent 04 Report: Register Allocator & Promotion Analysis

## 1. Current State Assessment

The Rex compiler currently uses several specialized register promotion and allocation strategies rather than a unified global register allocator. These are:

### 1.1. Expression Spill Register Promotion (O6 & O29)
The compiler avoids stack traffic for binary expression evaluation by using `r10` and `r11` as scratch registers.
- **Depth 0:** `mov r10, rax`
- **Depth 1:** `mov r11, rax`
- **Depth ≥ 2:** `push rax`
- **O29 Optimization:** Inside 1-parameter "push-style" protocols, `r13` (callee-saved) is used for Depth 0 instead of `r10` (caller-saved). This eliminates the need to spill `r10` across nested protocol calls like `fib(n-1) + fib(n-2)`.

### 1.2. Loop Variable Pinning (O2)
For `for` loops with static bounds, the loop counter is promoted to `r15`.
- **Hot Path:** `cmp r15, imm32` / `inc r15`.
- This eliminates 2 memory operations per iteration (load/store of the counter).

### 1.3. Loop Accumulator Promotion (O13 & O14)
The compiler identifies the primary accumulator in a loop (the first non-counter variable stored to) and promotes it to `r14`.
- **O14 Strength Reduction:** Fuses `:total = total + i` into a single `add r14, r15`.
- **Hot Path:** Operates entirely in registers `r14` and `r15`.

### 1.4. Protocol Parameter Register Allocation (O18)
The first two parameters of a protocol are promoted to `r12` and `r13`.
- **Benefit:** Accesses to these parameters use registers instead of stack slots.
- **Cost:** Requires `push/pop` of these callee-saved registers in the prologue/epilogue.
- **O27 retroactive elision:** If a protocol is never called from another protocol, the `push/pop r12` is retroactively NOPed out to save cycle latency.

## 2. Identified Spill Locations & Inefficiencies

Despite these optimizations, several areas for improvement remain:

1.  **Limited Register Set:** Only `r10`, `r11`, `r12`, `r13`, `r14`, `r15` are actively used for promotion. `rbx`, `rcx`, `rdx`, `rsi`, `rdi`, `r8`, `r9` are mostly reserved for ABI compliance or temporary use during complex opcodes.
2.  **Lack of Live Range Analysis:** Variables are promoted based on simple heuristics (e.g., "first two params", "first accumulator found"). A variable with a long live range might stay on the stack while a short-lived one gets a register.
3.  **Redundant Moves:** The peephole optimizer (O3) catches some `mov rax, r10 / mov rbx, r10` patterns, but many `mov` instructions remain that could be eliminated by better register selection (e.g., evaluating a result directly into the target register).
4.  **Static Promotion Boundaries:** Promotion is currently restricted to specific scopes (one loop, one protocol). Cross-loop promotion or global variable promotion to registers across an entire program is not implemented.

## 3. Proposed Register Allocator: Linear Scan

To move beyond heuristics, a **Linear Scan Register Allocator** is proposed for the Rex compiler.

### 3.1. Design Overview
1.  **Virtual Register Mapping:** The parser assigns a Virtual Register (VR) to every variable and temporary expression result.
2.  **Live Interval Analysis:** A pre-codegen pass (or integrated with the parser) records the first and last usage of each VR.
3.  **Allocation:**
    - Sort live intervals by start point.
    - Maintain a list of "active" intervals currently in physical registers.
    - When a new interval starts:
        - If a physical register is free, assign it.
        - If not, "spill" the interval that ends latest to the stack.
4.  **Physical Register Pool:**
    - **Callee-saved (preferred for long lives):** `rbx`, `r12`, `r13`, `r14`, `r15`.
    - **Caller-saved (for short lives/temporaries):** `r10`, `r11`, `r8`, `r9`.

### 3.2. Quantified Estimated Savings

| Optimization | Estimated Cycle Savings | Complexity |
|--------------|-------------------------|------------|
| **Linear Scan (General)** | 10–20% in complex protocols | High |
| **Global Var Promotion** | 5–10% in loops with many globals | Medium |
| **`rbx` utilization** | 2–3% (freeing one more callee-saved reg) | Low |

## 4. Specific Bug Found during Analysis

While auditing `codegen_emit_expr_save_rax` (Line 3167), I noted that the `O29` optimization for `r13` is extremely specific to "push-style" 1-param protocols. If a protocol uses `O18` (pinning 2 params to `r12/r13`), `O29` would clobber `r13` (parameter 1). 
- **Current Safeguard:** `O29` is only active if `push_style_frame` is true, which is restricted to 1-param protocols.
- **Recommendation:** Ensure `regalloc_cnt` check is added to `O29` activation logic to prevent accidental clobbering if `O18` is ever expanded.

## 5. Conclusion

The current "Promotion-by-Heuristic" approach has successfully brought Rex performance close to C for tight loops (as seen in the Fibonacci and Sum benchmarks). However, to close the remaining ~3x gap in recursive tasks, a transition to a true register allocator that performs live-range analysis is required. This would allow Rex to keep variables like the `n` in `fib(n)` in registers across the entire call tree, matching the output of `gcc -O2`.

*Reported by Agent 04*
