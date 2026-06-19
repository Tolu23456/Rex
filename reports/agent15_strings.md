# Agent 15: String Handling & Buffer Safety Analysis

## Overview
This report analyzes string operations in the Rex compiler and runtime, focusing on buffer safety, bounds checking, and memory management.

## String Operations Audit

### 1. Concatenation (`rt_str_cat`)
- **Implementation**: Allocates a new buffer of size `len1 + len2 + 1`.
- **Safety**: 
    - Verified: Checks for integer overflow during length summation.
    - Verified: Null-terminates the resulting string.
    - Verified: Uses `rep movsb` for efficient copying.
- **Improvement**: Added explicit overflow check for `len1 + len2 + 1`.

### 2. Slicing (`rt_str_slice`)
- **Implementation**: Takes `start` and `end` indices.
- **Safety**:
    - Verified: Checks `start < 0`, `end > len`, and `start >= end`.
    - Verified: Returns an empty string if bounds are invalid.
    - Verified: Null-terminates the slice.

### 3. Comparison (`rt_str_eq`)
- **Implementation**: Uses SSE2 (pcmpeqb) for fast comparison of blocks of 16 bytes, falling back to scalar.
- **Safety**: Correctly compares lengths first.

### 4. Search (`rt_str_find`)
- **Implementation**: Uses a SIMD-accelerated search for the first character of the needle.
- **Safety Bug Found**: `repe cmpsb` clobbers `rcx`, but `rcx` was not preserved in the needle verification loop, potentially leading to incorrect loop behavior in the caller or outer loop.
- **Fix**: Added `push rcx` / `pop rcx` around `repe cmpsb` in `rt_str_find`.

### 5. Length (`rt_str_len`)
- **Implementation**: Uses `repne scasb`.
- **Safety**: Safe for null-terminated strings.

### 6. Literal Handling
- **Implementation**: `lexer.asm` reads string literals into `tok_ident` (size 64).
- **Vulnerability**: Long string literals in source code could overflow `tok_ident` and corrupt adjacent BSS data.
- **Status**: Checked `lexer/lexer.asm`. The current implementation in `.pstr` has a check `cmp rbx, 63` to truncate overlong strings.
- **Recommendation**: Increasing `tok_ident` size or using dynamic allocation for literals would support longer strings, but truncation prevents safety issues.

### 7. Splitting (`rt_str_split`)
- **Safety**:
    - Verified: Added overflow checks for sequence allocation size (`count * 8 + 16`).
    - Verified: Correctly handles multiple parts and null-terminates each part.

### 8. Joining (`rt_str_join`)
- **Safety**:
    - Verified: Added overflow check for total joined length.
    - Verified: Correctly handles empty sequences.

## Buffer Overflow Vectors
- **Lexer**: String literal length is capped at 63 bytes in `tok_ident`. This prevents BSS corruption but silently truncates.
- **Runtime**: Most operations use `rt_alc` (mmap/bump) based on calculated lengths. Integer overflow in length calculation was a primary concern.

## Proposed Optimizations

### 1. Immutable String Interning
- **Concept**: Maintain a global hash table of strings.
- **Benefit**: Reduces allocation pressure and makes equality checks `O(1)` (pointer comparison).
- **Implementation**: Use `rt_sip` (SipHash) to index a string table.

### 2. Zero-Copy Slicing
- **Concept**: Strings could be represented as `(ptr, len)` pairs rather than always being null-terminated.
- **Benefit**: Slicing becomes `O(1)` with no allocation.
- **Trade-off**: Requires updating all string-consuming runtime functions and complicates null-termination for syscalls.

## Conclusion
The Rex string runtime is generally safe against simple buffer overflows due to explicit length-based allocations. The most significant risks were integer overflows in length calculations and register clobbering in complex SIMD routines, both of which have been addressed in this audit.
