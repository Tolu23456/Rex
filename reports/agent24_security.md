# Security & Memory Safety Analysis - Rex Compiler

This report details a security and memory safety audit of the Rex compiler codebase, focusing on potential vulnerabilities such as buffer overflows, integer overflows, format string issues, and input validation failures.

## 1. Buffer Overflows (Fixed-size Buffers)

### 1.1 Lexer `tok_ident` Overflow
- **Location**: `lexer/lexer.asm`, `tok_ident` buffer (64 bytes).
- **Vulnerability**: The lexer collects identifiers and string literals into `tok_ident`.
- **Analysis**: 
    - In `.pid` (identifier) and `.pstr` (string literal) loops, there is a check `cmp rbx, 63`. If the identifier or string is longer than 63 bytes, it is truncated.
    - However, if the truncation logic is slightly off or if a future modification misses this check, a buffer overflow could occur.
    - String literals in `tok_ident` are currently limited to 63 bytes. A 10MB source file with a single massive string literal would be truncated, which is safe for memory but potentially incorrect for the user.
- **Risk**: Low (currently mitigated by checks), but limiting string literals to 63 bytes is a functional bottleneck.

### 1.2 `out_buffer` Overflow
- **Location**: `codegen/codegen.asm`, `out_buffer` (512 KB).
- **Vulnerability**: The compiler emits machine code directly into this buffer.
- **Analysis**:
    - `emit_b`, `emit_d`, and `emit_q` deliberately omit bounds checks for performance (as noted in comments: "enables bounds-check removal").
    - A sufficiently large Rex source file (e.g., millions of lines) will generate more than 512KB of machine code, leading to a heap/bss overflow and likely a segfault or code injection if exploited.
- **Risk**: **High**. The compiler should check `out_idx` against `out_buffer` capacity before emission or use a dynamic/growing buffer.

### 1.3 `src_buffer` Overflow
- **Location**: `main/main.asm`, `src_buffer` (64 KB).
- **Vulnerability**: The entire source file is read into this buffer.
- **Analysis**:
    - The `read` syscall (line 29) uses a hardcoded 64KB limit.
    - If a user provides a source file larger than 64KB, the `read` syscall will truncate the input.
    - While not a memory overflow (since `read` is told the buffer size), it's a silent failure/truncation that might lead to incomplete parsing.
- **Risk**: Medium (functional impact).

### 1.4 Patch Stacks Overflow
- **Location**: `codegen/codegen.asm`, `jump_patch_stack`, `break_jump_stack`, etc. (32 entries each).
- **Vulnerability**: Deeply nested control flow (ifs, loops) could exceed stack capacity.
- **Analysis**:
    - These stacks have a fixed depth of 32.
    - There are no explicit checks in `codegen_emit_while_start`, `codegen_emit_for_start`, etc., before incrementing depth.
    - A source file with 33 nested loops will cause a stack overflow in the BSS.
- **Risk**: **Medium-High**. Needs explicit depth checks.

## 2. Integer Overflows in Size Calculations

### 2.1 Runtime Allocator (`rt_alc`)
- **Location**: `runtime/runtime_src.asm`, `rt_alc`.
- **Analysis**:
    - `add rbx, 7; and rbx, -8` is used for alignment. If `rbx` (size) is `0xFFFFFFFFFFFFFFF9` or higher, this will wrap around to 0.
    - While `mmap` might fail or handle small sizes, wrapping to a small number could lead to a successful small allocation followed by a large out-of-bounds write in the caller.
- **Risk**: Low-Medium.

### 2.2 String Concatenation (`rt_str_cat`)
- **Location**: `runtime/runtime_src.asm`, `rt_str_cat`.
- **Analysis**:
    - `lea rdi, [r13 + r15 + 1]` calculates the new capacity (len1 + len2 + 1).
    - If `len1 + len2` overflows 64-bit space, the allocation will be smaller than the subsequent `rep movsb` copies.
- **Risk**: **High** (if Rex allows very large strings).

## 3. Format String & Input Validation

### 3.1 `rt_prq` (Error printing)
- **Location**: `runtime/runtime_src.asm`, `rt_prq`.
- **Analysis**:
    - `rt_prq` takes a pointer to a null-terminated string and prints it. It does not use `printf`-style format strings, so typical format string attacks are not applicable.
    - However, it relies on null-termination. If a malformed string is passed, it will read past the buffer until a NUL is found.

### 3.2 Compiler Input Validation
- **Source file size**: Limited to 64KB by `main/main.asm`.
- **Token count**: No explicit limit, but limited by source size.
- **Protocol parameters**: `frame_param_vars` (line 114 of `codegen.asm`) is `resb 6`. This suggests a limit of 6 parameters for some optimizations. If the parser allows more without checking this limit, an overflow occurs.
- **Analysis**: `parser/parser.asm` line 1493 confirms a 6-parameter limit for O18/O19 optimizations but doesn't seem to enforce a hard global limit that protects the buffer.

## 4. Summary of Risks

| Vulnerability | Severity | Mitigation |
| :--- | :--- | :--- |
| `out_buffer` overflow | High | Add bounds checks to `emit_*` or implement dynamic resizing. |
| `rt_str_cat` overflow | High | Add overflow check for `len1 + len2`. |
| Patch stack overflow | Medium | Add depth checks for nested control flow. |
| Large source truncation | Medium | Use `fstat` to determine file size and `mmap` or dynamic buffer. |
| Protocol param overflow | Medium | Enforce parameter count limits in parser. |

## 5. Recommendations

1. **Mandatory Bounds Checks**: Even if "slow", the compiler MUST check `out_idx` before every emission.
2. **Dynamic Reading**: `main/main.asm` should use `fstat` to get the actual source size and allocate a buffer accordingly.
3. **Safe Math**: All size calculations for allocations (especially string/sequence operations) should use carry-checking or saturation.
4. **Depth Limits**: Enforce a maximum nesting depth in the parser and report a clean error if exceeded.
