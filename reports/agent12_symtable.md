# Agent Report: Variable Table & Scope Analysis (T012)

## Executive Summary
An audit of the Rex compiler's variable table and scope management reveals a robust but functionally limited system. The current implementation uses a linear-scan symbol table with 64-byte fixed entries. Scope is managed via a `scope_depth` stack that tracks `var_count` for reclamation. While effective for simple cases, several critical limitations and potential bugs were identified, particularly regarding collision handling (none), shadowing correctness, and capacity exhaustion.

## Symbol Table Architecture (`var_table`)

### Data Structure
- **Storage**: `var_table` is a contiguous block of `VAR_MAX` (256) entries.
- **Entry Layout (`VAR_ENTRY_SIZE` = 64 bytes)**:
  - `0-31`: Variable Name (NUL-terminated string).
  - `32-39`: Storage address or value (8 bytes).
  - `40`: `is_init` flag.
  - `41`: `is_mutable` flag.
  - `42`: `is_const` flag.
  - `43`: `is_volatile` flag.
  - `44`: `is_param` flag.
  - `48`: `type` byte.
- **Lookup**: `var_find` performs a linear scan from index `0` to `var_count-1`.

### Performance & Complexity (T025)
- **Time Complexity**: $O(N)$ for both find and add, where $N$ is the number of variables in the current and outer scopes.
- **Total Complexity**: For a program with $V$ variables, symbol table operations are $O(V^2)$.
- **Recommendation**: Replace with a hash-based symbol table or a scoped hash map to achieve $O(1)$ average lookup.

## Scope Management Analysis

### Mechanism
Rex uses a `scope_depth` and `scope_stack` (32 entries) to handle nested blocks (`if`, `for`, `while`, `protocol`). 
- **Push**: Current `var_count` is saved to `scope_stack[scope_depth]`, and `scope_depth` increments.
- **Pop**: `var_count` is restored from `scope_stack[scope_depth-1]`, effectively reclaiming all variables declared within the block.

### Identified Issues

#### 1. Shadowing Weakness
The `var_find` implementation scans from index `0` upward:
```asm
.l:
    cmp rcx, [var_count]
    jge .nf
    ; ... compare name ...
    inc rcx
    jmp .l
```
**Bug**: This returns the *first* match found. If a variable in an inner scope shadows a variable in an outer scope, `var_find` will return the outer variable because it is stored at a lower index in `var_table`.
**Fix**: Scan the `var_table` in reverse (from `var_count-1` down to `0`) to always find the most recent (innermost) declaration.

#### 2. Capacity Exhaustion & Reentrancy
- **Limit**: `VAR_MAX` is 256. 
- **Leak Risk**: While `scope_stack` reclaims slots, synthetic variables (like `_fe` for loops or `__le` for loop-else) consume slots. If a protocol with many locals is called recursively without proper frame management, or if the compiler fails to pop scope on error paths, the table will exhaust.
- **Observed Bug**: In `parse_stmt`, many branches (like `.if`, `.for`, `.while`) jump to `.done` or `.nf` on errors. If a scope was pushed but not popped due to a syntax error, subsequent compilations in the same session will leak `var_table` slots.

#### 3. Collision Handling
The current "collision handling" for `var_add` is simply a linear scan to see if a name exists *anywhere* in the table. However, Rex allows re-declaration in inner scopes. The current `var_add` does not check if a variable exists in the *current* scope specifically, leading to potential duplicate entries or incorrect shadowing behavior.

#### 4. Forward Reference Table (Protocols)
`fwd_ref_count` is limited to 16. Deeply coupled protocol graphs will exceed this limit, causing the compiler to emit `0` instead of a valid call, leading to silent runtime failures or crashes.

## Vulnerability Assessment (T024)

- **Buffer Overflow**: `saved_name` and `for_end_name` are fixed 64-byte buffers. `strcpy` does not check length. A variable name longer than 63 bytes in source will overflow these buffers into `cur_type` and `scope_stack`, potentially corrupting the compiler's internal state.
- **Integer Overflow**: `imul rax, PROTO_ENTRY_SIZE` and `shl rax, 6` are used for indexing. While `VAR_MAX` is small, if it were expanded, these could overflow if not checked.

## Proposed Improvements

1. **Reverse Scan**: Modify `var_find` to loop from `var_count-1` to `0`.
2. **Hash-Based Symbol Table**: 
   - Implement a simple open-addressed hash table with linear probing.
   - Use a "linked list of scopes" approach or "stack of hash maps" to handle $O(1)$ shadowing and reclamation.
3. **Safety Checks**: Use `strncpy` (or equivalent length-checked copy) for all name buffers.
4. **Structured Errors**: Ensure every `scope_push` has a guaranteed `scope_pop` even on parse error paths (using a `try-finally` style orchestration in the parser).

## Conclusion
The symbol table is currently the most significant bottleneck for scaling Rex to larger codebases. The shadowing bug is a correctness issue that should be prioritized for fixing by reversing the search order.
