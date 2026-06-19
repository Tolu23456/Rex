# Agent 08: Runtime Blob Analysis & Optimization Report

## 1. Overview
This report provides a deep audit of the Rex runtime functions located in `runtime/runtime_src.asm`. The analysis covers correctness, performance, and architectural improvements for key runtime components including I/O, memory management, hashing, and string operations.

## 2. Correctness Audit

### 2.1 Integer Printing (`rt_pri`)
- **Negative Numbers**: Correctly handled via `neg` and prepending '-'.
- **Zero**: Explicitly handled at `.zero` label.
- **Edge Case (MIN_INT)**: `neg r12` on `-2^63` will overflow (still `-2^63` in 2's complement). This might lead to incorrect printing for the most negative 64-bit integer.
- **Buffer Size**: Uses 24 bytes on stack. Sufficient for 20-digit 64-bit integers + sign + newline.

### 2.2 Floating Point Printing (`rt_prf`)
- **Precision**: Hardcoded to 6 decimal places.
- **Rounding**: Uses `cvttsd2si` (truncation), not rounding. `0.9999999` might print as `0.999999` or even `0.000000` depending on how fractional parts are handled.
- **Algorithm**: Multiplies by 10 repeatedly. This accumulates floating point error. A more robust algorithm (like Grisu or Dragon4) would be better but is much larger.

### 2.3 String Operations
- **`rt_str_cat`**: Correctly allocates `len1 + len2 + 1` and NUL terminates.
- **`rt_str_trim`**: Correctly handles empty strings and strings with only spaces.
- **`rt_str_rev`**: Performs in-place reversal. Correct.
- **`rt_str_split`**: Correctly handles multiple delimiters and trailing parts.
- **`rt_str_join`**: Potential off-by-one in total length calculation. At line 1006, `add r15, r14` is called for every element except the last one? No, looking at lines 1004-1007, it checks `cmp rcx, rbx` then `je .alloc`. If it's not the last element, it adds the separator length. Logic seems correct but complex.

### 2.4 Sequence Operations
- **`rt_seq_sum`**: Only supports `TYPE_INT` (assumes 8-byte elements). If a sequence of floats or mixed types is passed, it will interpret bits as integers.
- **`rt_seq_sort`**: Currently a stub (`ret`). This is a major gap.

## 3. Performance Analysis

### 3.1 Division in `rt_pri` and `rt_int2str`
- **Issue**: Uses `div rcx` where `rcx=10`. Hardware division is extremely slow (approx. 30-90 cycles).
- **Optimization**: Replace with reciprocal multiplication (libdivide-style).
  - For `d=10`, `1/10 \approx 0xCCCCCCCCCCCCCCCD >> 3`.
  - `rax = (unsigned__int128(n) * 0xCCCCCCCCCCCCCCCD) >> 64; rax >>= 3;`

### 3.2 String Equality (`rt_str_eq`)
- **Current**: Uses SSE2 `pcmpeqb` for blocks of 16 bytes.
- **Issue**: High overhead for very short strings due to setup.
- **Optimization**: Use `repe cmpsb` for very short strings (<16 bytes) or a simple scalar loop. For long strings, AVX2 could double throughput.

### 3.3 SIPHash / RXHASH (`rt_sip`)
- **Analysis**: The implementation uses FNV-1a as a base then applies SplitMix64 mixers.
- **Correctness**: This is NOT SipHash-2-4 despite the name `rt_sip`. It is a custom hash named `RXHASH-64`.
- **Performance**: FNV-1a is byte-at-a-time. For long identifiers, loading 8 bytes at once and using a 64-bit mixer would be much faster.

## 4. Memory Allocator Audit (`rt_alc`)

### 4.1 Bump Allocator
- **Analysis**: Simple and fast. No `free` support.
- **Risk**: Fragmentation is non-existent, but memory exhaustion is inevitable for long-running processes as it never reclaims.
- **Mode Switching**: Checks `0x401D75` for mode. This is a hardcoded address which is fragile.

### 4.2 Mmap Allocator
- **Analysis**: Calls `sys_mmap` for every allocation if not in pool mode.
- **Issue**: Extremely high syscall overhead. `mmap` is page-aligned; requesting 8 bytes will likely waste 4088 bytes.

## 5. Proposed Enhancements

### 5.1 Reciprocal Multiplication for `rt_pri`
```nasm
; Optimization for div 10
mov rdx, 0xCCCCCCCCCCCCCCCD
mul rdx
shr rdx, 3
; rdx now contains quotient, original rax - rdx*10 is remainder
```

### 5.2 Mmap-based Arena Allocator
Instead of `mmap` per call, `rt_alc` should always use a pool/arena. If the current 64MB pool is exhausted, `mmap` another large chunk and link it.

### 5.3 Vectorized String Search
`rt_str_find` currently uses a mix of SSE2 and scalar. Using `PCMPESTRI` (SSE4.2) could significantly accelerate substring search.

### 5.4 Dictionary Optimization
Dictionary operations are not explicitly in `runtime_src.asm` as distinct blobs but are handled via `rt_sip`. Implementing a true Robin Hood hash or a Cuckoo hash in the runtime would improve dictionary performance.

## 6. Summary of Bug Findings
1. **MIN_INT Printing**: `rt_pri` will fail to correctly handle `-9223372036854775808`.
2. **Missing Implementation**: `rt_seq_sort` is a no-op.
3. **Naming Mismatch**: `rt_sip` is not SipHash, which might mislead security audits expecting SipHash's collision resistance.
4. **Syscall Overhead**: `rt_alc` in `mmap` mode is pathological for small allocations.
