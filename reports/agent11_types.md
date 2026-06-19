# Agent 11 Report: Type System & Propagation Analysis

## Executive Summary
The Rex type system is a static-inferred system that currently operates during a single-pass recursive descent parse. This report details the mapping of type IDs, the propagation rules through expressions, and identifies critical holes in the current implementation.

## 1. Type ID Mapping
Based on `include/rex_defs.inc` and `parser/parser.asm`, the following types are defined and tracked:

| Type ID | Constant | Symbol | Description |
|---------|----------|--------|-------------|
| 1 | `TYPE_INT` | `int` | 64-bit signed integer |
| 2 | `TYPE_FLOAT` | `float` | 64-bit IEEE 754 float |
| 3 | `TYPE_BOOL` | `bool` | Tri-state Kleene logic |
| 4 | `TYPE_COMPLEX`| `complex` | Deprecated core type |
| 5 | `TYPE_STR` | `str` | Heap-managed UTF-8 string |
| 6 | `TYPE_SEQ` | `seq[T]` | Heap-managed dynamic sequence |
| 11 | `TYPE_DICT` | `dict[T]` | SipHash-based map |

## 2. Type Tracking Mechanism
The compiler tracks types using a global variable `cur_type` in `parser/parser.asm`.
- `parse_factor` sets `cur_type` based on the leaf node (literal, variable, or protocol return).
- Higher-level parser functions (`parse_term`, `parse_additive`, etc.) update `cur_type` based on the operator and operand types.

## 3. Propagation Rules & Implementation Status

### 3.1 Arithmetic Operators (`+`, `-`, `*`, `/`)
- **Rule:** If either operand is `float`, the result is `float`. Otherwise, it is `int`.
- **Implementation Hole:** The current implementation of `parse_additive` and `parse_term` only checks the type of the **first** operand (LHS) stored in `r12b` to decide between integer and float codegen. 
    - *Bug:* If the LHS is `int` and the RHS is `float`, it incorrectly emits integer instructions and sets `cur_type` to `TYPE_INT`, causing precision loss or incorrect results.
    - *Fix Needed:* Check both operands' types and promote to float if either is `TYPE_FLOAT`.

### 3.2 Modulo Operator (`%`)
- **Rule:** Always yields `int`.
- **Status:** ✅ Correctly implemented in `parse_term`.

### 3.3 Bitwise Operators (`&`, `|`, `^`, `~`, `<<`, `>>`)
- **Rule:** Operates on integers, yields `int`.
- **Status:** ✅ Correctly implemented.

### 3.4 Logical Operators (`and`, `or`, `not`)
- **Rule:** Yields `bool` (tri-state).
- **Status:** ✅ Correctly implemented in `parse_expr` and `parse_unary`.

### 3.5 Comparison Operators (`==`, `!=`, `<`, `>`, `<=`, `>=`)
- **Rule:** Yields `bool`.
- **Status:** ✅ Correctly implemented in `parse_comparison`.

### 3.6 Membership Operator (`in`)
- **Rule:** Yields `bool`.
- **Status:** ✅ Correctly implemented in `parse_expr`.

## 4. Critical Inference Holes

### 4.1 Missing Implicit Coercions
Rex currently lacks implicit coercion for `int` → `float` in mixed-type arithmetic.
- `output 1 + 2.5` results in integer addition because the first operand is `int`.
- This violates the language's own documentation in `syn.md` (Operator mapping).

### 4.2 Silent Acceptance of Mismatched Types
The compiler often fails to emit errors when types are incompatible.
- `int x = "string"`: `parse_stmt` (.pinit) parses the expression, then adds the variable with the declared type `TYPE_INT`. It does **not** check if the expression's `cur_type` matches `TYPE_INT`.
- `return "string"` in an `int` protocol: The return type is saved into the protocol table from `cur_type`, but no validation is performed against the declared return type at the definition site.

### 4.3 `typeof` and `match`
- `typeof` (TOK_TYPEOF) is lexed but appears to be missing a handler in `parse_factor` (it's in `rex_defs.inc` but not in the `cmp al, TOK_...` list).
- `match` statement (TOK_MATCH) is lexed but lacks a full implementation in `parse_stmt`.

## 5. Proposed Improvements

### 5.1 Hindley-Milner Inference Pass
Transition from a single-pass greedy type tracker to a multi-pass approach:
1. **Pass 1:** Build AST and collect type constraints.
2. **Pass 2:** Resolve constraints (Unification).
3. **Pass 3:** Codegen with validated types.
This would eliminate the `cur_type` global and allow for more robust inference across nested scopes.

### 5.2 Immediate Validation
In the short term, add validation in `parse_stmt` assignments and `parse_factor` protocol calls to ensure types match.

### 5.3 Unified Float Promotion
Refactor binary operator parsing to a helper that handles symmetric type promotion (if either is float, both must be float).

---
*Report produced by Agent 11 on Type System & Propagation Analysis.*
