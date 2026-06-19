# Global Optimization Framework for Rex

## 1. Introduction
The Rex compiler currently employs several peephole and local optimizations (O2 register pinning, O13/O14 accumulator fusion, FLC frameless calls). To achieve performance parity with optimizing C compilers, a global optimization framework is required. This report outlines the design and implementation strategies for five key global optimizations.

## 2. Global Optimization Architecture

### (1) Inline Expansion of Small Protocols (≤10 instructions)
**Design:**
The parser identifies "small" protocols during its first pass. When a call to such a protocol is encountered, instead of emitting `call`, the compiler substitutes the protocol's IR (or body bytes) into the caller's stream.

**Implementation Sketch (NASM/Pseudocode):**
```nasm
; During protocol definition:
proto_define:
    ...
    mov [proto_table + idx*PROTO_SIZE + OFFSET_SIZE], out_idx_start
    ; after parsing body
    mov rax, out_idx_end
    sub rax, out_idx_start
    mov [proto_table + idx*PROTO_SIZE + OFFSET_LEN], rax
    cmp rax, INLINE_THRESHOLD ; e.g., 64 bytes
    setle byte [proto_table + idx*PROTO_SIZE + OFFSET_INLINEABLE]

; During call parsing:
parse_call:
    ...
    cmp byte [proto_table + idx*PROTO_SIZE + OFFSET_INLINEABLE], 1
    jne .emit_call
    ; Inline: Copy bytes from out_buffer[start] to current out_idx
    ; Replace param loads with moves from current arg registers/stack
    call codegen_inline_copy
    jmp .done
.emit_call:
    call codegen_emit_call_prot
```

### (2) Constant Folding and Propagation
**Design:**
Evaluate expressions involving constants at compile-time. Propagate these values through assignments to eliminate redundant computations.

**Implementation Sketch:**
```nasm
; In parser/parser.asm (parse_expr):
; Check if operands are constants
movzx eax, byte [left_is_const]
and al, [right_is_const]
jz .emit_runtime_op

; Fold:
mov rax, [left_val]
add rax, [right_val]
mov [cur_expr_val], rax
mov byte [cur_expr_is_const], 1
; Skip emitting 'add rax, rbx'
```

### (3) Dead Code Elimination (DCE)
**Design:**
Identify code segments that have no effect on the program's output (e.g., assignments to variables that are never read).

**Implementation Sketch:**
Requires a multi-pass approach or a Backward-Scan on IR.
```pseudocode
// Pass 1: Mark all variables used in 'output' or 'return' as LIVE.
// Pass 2: Scan backwards. If a store to 'x' is found:
//    If 'x' is LIVE: keep store, mark 'x' dependencies as LIVE.
//    If 'x' is NOT LIVE: remove store (replace with NOPs).
```

### (4) Common Subexpression Elimination (CSE)
**Design:**
Detect identical expressions (e.g., `a + b` calculated multiple times) and reuse the previously computed result.

**Implementation Sketch:**
Maintain a "Value Numbering" table during parsing.
```nasm
; Expression: a + b
; 1. Lookup (OP_ADD, id_a, id_b) in hash table.
; 2. If found: mov rax, [previous_result_reg_or_var]
; 3. If not found: emit add, store result, add to hash table.
```

### (5) Partial Redundancy Elimination (PRE)
**Design:**
A generalization of CSE and Loop-Invariant Code Motion. It moves computations that are redundant on some paths (but not all) to locations where they are computed only once.

**Implementation Sketch:**
This usually requires a Control Flow Graph (CFG) and Data Flow Analysis (Busy Expressions, Available Expressions).
```pseudocode
// 1. Compute 'Anticipated' and 'Available' expressions at each block.
// 2. Identify expressions that can be hoisted out of loops or moved to 'earlier' blocks
//    to make them fully redundant, then apply CSE.
```

## 3. Implementation Path
The transition to a formal **Intermediate Representation (IR)** as defined in `docs/rex_ir.md` is the recommended path for these optimizations. Direct byte-patching (as used in current peepholes) becomes prohibitively complex for global transformations like PRE.

## 4. Expected Performance Gains
*   **Inlining:** 5-15% reduction in execution time for recursive or modular code by eliminating call/ret overhead and enabling further local optimizations in the inlined body.
*   **Constant Folding/Propagation:** Massive gains (up to 90%) for initialization-heavy code.
*   **CSE/DCE:** 10-20% reduction in instruction count for complex arithmetic.
