# Agent 14: Jump Patching & Control Flow Integrity Report

## Executive Summary
This report presents a detailed audit of the Rex compiler's jump patching and control flow integrity mechanisms within `codegen/codegen.asm`. The analysis focused on the `jump_patch_stack`, `break_jump_stack`, `end_jump_stack`, and related structures. While the implementation is highly efficient and robust for typical Rex programs, several capacity-related risks and stack frame management edge cases were identified. Recommendations for hardening the compiler against deeply nested structures and ensuring ABI compliance during control flow transitions are provided.

## 1. Jump Patching Architecture Overview
The Rex compiler employs a stack-based architecture for managing forward jump placeholders during machine code emission. This allows for the implementation of nested `if-elif-else` chains and various loop constructs (`for`, `while`, `repeat`, `each`).

### 1.1 Core Patching Structures
| Stack Name | Purpose | Capacity |
| :--- | :--- | :--- |
| `jump_patch_stack` | `if`/`when` condition failure jumps (branch past block). | 32 qwords |
| `end_jump_stack` | `elif`/`else` end-of-body jumps (branch to chain end). | 32 qwords |
| `chain_base_stack` | Snapshot of `end_jump_stack` depth at the start of an `if` chain. | 32 qwords |
| `break_jump_stack` | `stop` (break) forward jumps to loop exit. | 32 qwords |
| `break_base_stack` | Snapshot of `break_jump_stack` depth at loop entry. | 32 qwords |
| `cont_base_stack` | Loop back-edge (continue) targets. | 32 qwords |
| `skip_jump_stack` | Forward jump placeholders for `skip` in `for` loops. | 64 qwords |
| `skip_target_stack`| Target `cont_base_stack` index for each `skip` entry. | 64 qwords |
| `loop_else_flag_stack`| Tracks presence of `else` block for loops. | 32 qwords |

## 2. Analysis of Jump Patching Mechanisms

### 2.1 Conditional Jumps and Chain Patching
The functions `codegen_patch_jump` and `codegen_patch_chain_end` handle the resolution of forward jumps in `if` chains.
- **`codegen_patch_jump`**: Pops the last offset from `jump_patch_stack` and writes the relative displacement (RIP-relative) to the emitted machine code.
- **`codegen_patch_chain_end`**: Uses `chain_base_stack` to identify all `end_jump_stack` entries belonging to the current `if` chain and patches them all to the current output position.

**Finding J01: Hard Capacity Limits.** All primary patch stacks have a fixed capacity of 32 entries. Deeply nested `if` statements or loops exceeding this depth will cause out-of-bounds writes to the `.bss` section, likely clobbering other compiler state and leading to a crash or silent corruption of emitted code.
- **Location**: `codegen/codegen.asm` lines 83-94.
- **Risk**: High (for edge-case source files).
- **Recommendation**: Implement a capacity check in every `inc qword [..._depth]` path. Stop the compiler with a "Nesting too deep" error if the limit is reached (Rule 14).

### 2.2 Break and Stop Implementation
Loops use `break_base_stack` to mark the "start" of breaks for a specific loop.
- **`codegen_emit_break`**: Emits a `jmp 0` and pushes the offset to `break_jump_stack`.
- **`codegen_patch_breaks`**: Patches all entries from the current loop's base to the current `break_jump_depth`.

**Finding J02: Loop-Else Flag Stack Integrity.** The `loop_else_flag_stack` is used to implement `else:` blocks for loops (executed if no `stop` was encountered).
- **Location**: `codegen/codegen.asm` line 2830-2865.
- **Analysis**: `codegen_emit_break` correctly sets the loop-broken flag if a stack is active. However, there is no explicit check if `loop_else_flag_depth > 0` before popping in all loop-end paths, though the parser's structure generally prevents this.

### 2.3 Skip (Continue) and For-Loop Forward Patching
Unlike `while` loops which have a fixed back-edge target, `for` loops in Rex (with optimizations like O2, O13, O14) often require a forward jump for `skip` (continue) to reach the increment/rotation logic at the end of the loop body.
- **`codegen_emit_skip`**: If the target loop is a `for` loop, it emits a forward jump and records it in `skip_jump_stack`.
- **`codegen_patch_for_skips`**: Scans the `skip_jump_stack` and patches entries targeting the specific loop being closed.

**Finding J03: Linear Scan Complexity.** `codegen_patch_for_skips` performing a linear scan of `skip_jump_stack` is O(N) where N is the number of active `skip` statements in `for` loops. While N is usually small, a pathological file with thousands of `skip` statements could slow down the compiler.
- **Location**: `codegen/codegen.asm` line 2915-2935.
- **Optimization**: The current implementation is O(N) but since N is capped at 64, this is acceptable for now.

## 3. Control Flow Integrity & ABI Compliance

### 3.1 Stack Frame Teardown
Rex protocols can have hardware stack frames (O1) or push-style frames (O21).
- **Finding J04: Unpatched Jumps to Epilogues.** The compiler must ensure that all `return` statements (which may be emitted in multiple places for a single protocol) correctly execute the epilogue.
- **Analysis**: The parser and `codegen_emit_leave` handle this by recording patch positions in `leave_patch_list`. The `codegen_finalize` function (O27) retroactively NOPs push/pop r12 for outer-scope-only protos, which is a sophisticated optimization that maintains integrity.

### 3.2 Protocol Entry/Exit (O27 Elision)
`codegen_finalize` retroactively modifies emitted code to remove `push r12` / `pop r12` if a protocol is never called from another Rex protocol.
- **Finding J05: Precise Byte Patching.** The elision uses 2-byte NOPs (`66 90`) to replace 2-byte `push/pop` instructions.
- **Location**: `codegen/codegen.asm` line 7283, 7297, 7305, 7318.
- **Audit**: The logic correctly identifies the positions and counts. It also handles the O29 `r13` register which is used as an expression spill register in some contexts.

## 4. Potential Bugs & Edge Cases

### 4.1 Off-by-one in Relative Jump Calculation
Standard relative jumps on x86-64 are calculated from the *end* of the instruction.
- **Logic**: `displacement = target - (placeholder_pos + 4)`.
- **Implementation**:
  ```nasm
  sub rax, rdx   ; rax = target, rdx = placeholder_pos
  sub rax, 4     ; correct: 4 bytes for the rel32 placeholder itself
  ```
- **Audit**: Checked `codegen_patch_jump`, `codegen_patch_chain_end`, `codegen_patch_breaks`, `codegen_patch_for_skips`, `codegen_patch_slot_to_here`. All correctly subtract 4.

### 4.2 Stack Overflows
As noted in Finding J01, there are no checks for stack depth.
- **`jump_patch_depth`**
- **`end_jump_depth`**
- **`break_jump_depth`**
- **`cont_base_depth`**
- **`skip_jump_depth`**
If any of these exceed their resq/resb limits, the compiler will overwrite adjacent variables in the `.bss` section. For example, `jump_patch_stack` is immediately followed by `jump_patch_depth`. Overflowing the stack will overwrite the depth itself, likely leading to an infinite loop or immediate segfault.

## 5. Summary of Findings & Recommendations

| ID | Finding | Severity | Recommendation |
| :--- | :--- | :--- | :--- |
| **J01** | Unprotected Patch Stacks | **High** | Add boundary checks (e.g., `cmp qword [jump_patch_depth], 32`) before every increment. |
| **J02** | O(N) Skip Patching | **Low** | Acceptable given the small cap (64), but document the limit. |
| **J03** | Missing Error Propagation | **Medium**| If a patch fails or a stack is unbalanced at the end of a protocol, the compiler should report a fatal error instead of emitting broken binary code. |

## Conclusion
The Rex jump patching system is a compact, high-performance implementation of control flow management. It avoids the overhead of a full Control Flow Graph (CFG) while supporting complex nesting. The primary weakness is the lack of defensive checks against deeply nested source code, which should be addressed to ensure compiler robustness in the face of adversarial or machine-generated source files.
