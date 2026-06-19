# Parser Analysis Report - Agent 02

## 1. Control Flow & Grammar Correctness Analysis

The Rex parser in `parser/parser.asm` implements a recursive descent parser with manual dispatch for statements and expressions.

### 1.1 Statement Dispatch Audit
The `parse_stmt` function handles top-level and block-level statements. 

- **Keyword Classification:** The dispatcher correctly identifies all implemented keywords: `prot`, `const`, type keywords (`int`, `float`, `bool`, `str`, `complex`, `seq`), `colon` (assignment), `output`, `show`, `if`, `for`, `while`, `return`, `stop`, `skip`, `pass`, `unreachable`, `assert`, `repeat`, `each`, `when`, and `@` (implicit through `parse_expr` as a fallback).
- **Control Flow Integrity:**
    - `if`: Correctly handles `if-elif-else` chains.
    - `for`: Implements both static-bounds (O2 optimization) and dynamic-bounds paths.
    - `while`: Handles loop-else logic.
    - `when`: Implements both subject-based and condition-mode (`when:`) switching.
    - `repeat`: Implements counted loops with hidden counter variables.
    - `each`: Implements sequence iteration.
- **Missing Productions / Deviations:**
    - `repeat_stmt` (📋): Implemented in code but marked as planned in grammar.
    - `blast_stmt` (📋): Missing implementation.
    - `pipe_stmt` (📋): Missing implementation.
    - `dict_set_stmt`: Grammar suggests `<IDENT> "[" <STR_LIT> "]" = expr`, but parser implementation for bracketed assignment was not found in the main `parse_stmt` loop (may be handled as a call or special case).

### 1.2 Expression Hierarchy Audit
Expressions use a 5-tier recursive descent hierarchy:
1. `parse_expr` (Comparison/Logical)
2. `parse_comparison` (Relational)
3. `parse_additive` (Addition/Bitwise)
4. `parse_term` (Multiplication/Shift)
5. `parse_unary` (Unary ops)
6. `parse_factor` (Atoms)

- **Operator Precedence:** Matches `docs/grammar.md`.
- **Short-circuiting:** `and`/`or` implement Kleene logic correctly with short-circuiting in `parse_expr`.
- **Type Propagation:** `parse_additive` and `parse_term` correctly handle type promotion (e.g., int + float -> float) by checking `cur_type` and emitting appropriate conversion or typed opcodes.

## 2. Grammar Rule Violations & Ambiguities

### 2.1 Grammar Ambiguities
- **Protocol Calls:** Standalone protocol calls are allowed as statements (`@func()`), but they are parsed via the `parse_expr` fallback in `parse_stmt`. This is functionally correct but less efficient than a dedicated call-statement parser.
- **Indentation:** The parser relies heavily on `TOK_INDENT`/`TOK_DEDENT`. While generally robust, the `if/elif/else` chain uses a local `r13` flag to track whether a block was indented. If a block is empty or the lexer miscounts dedents, the parser might consume the next statement incorrectly.

### 2.2 Invalid Rex Accepted
- The `parse_factor` implementation for `TOK_IDENT` (lines 380-419) allows reading from a variable. If `var_find` fails (line 388), it just emits a zero and moves on (`.idn_skip`). This means the compiler silently accepts undefined variables as `0`.
- Missing error reporting for mismatched argument counts in protocol calls (lines 444-557). It populates arguments but doesn't strictly verify against `proto_table`'s `param_count` during the call emission, though it does save the count.

## 3. Bug Findings & Proposed Fixes

### 3.1 Undefined Variable Silence
- **Location:** `parser/parser.asm` lines 388-389 and 420-425.
- **Bug:** `je .idn_skip` / `.idn_skip:` emits `mov eax, 0` when an identifier is not found.
- **Fix:** Replace `.idn_skip` logic with a call to `fatal` with "undefined identifier" error.

### 3.2 `err` Statement Stub
- **Location:** `parser/parser.asm` lines 1429-1432.
- **Bug:** The `err` statement is essentially a stub that always calls `fatal` with a fixed "expected identifier" error message, ignoring the provided expression.
- **Fix:** Implement `parse_expr` inside `.err`, then check `cur_type`. If string, call `rt_err_blob`. If other, convert to string then call.

### 3.3 Protocol Forward Reference Limit
- **Location:** `parser/parser.asm` lines 561-562.
- **Bug:** Hardcoded limit of 16 forward references (`fwd_ref_count`).
- **Fix:** Increase `fwd_ref_patches` and `fwd_ref_names` buffer sizes in `.bss` and update the limit check.

## 4. Proposals

### 4.1 Operator-Precedence Climbing
Replacing the manual pratt-like/recursive-descent dispatch in `parse_expr` with an operator-precedence climbing algorithm would reduce stack depth and consolidate binary operator handling. Currently, `parse_additive`, `parse_term`, etc., are very similar. A table-driven approach could reduce code size by ~400 lines of ASM.

### 4.2 Symbolic Symbol Table
The current `var_find` (lines 185-222) is an O(N) linear scan. As programs grow, this will become a bottleneck. Propose implementing a simple hash-based lookup for `var_table`.

## 5. Summary of Compliance
The implementation is ~90% compliant with the V5.0 EBNF. The primary gaps are in advanced vectorized loops and strict error reporting for undefined symbols. Control flow is logically sound but sensitive to lexer accuracy regarding indentation.
