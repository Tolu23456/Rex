# Standard Library Analysis Report (agent20_io.md)

## 1. Overview
This report analyzes the current state of `stdlib/io.rex` and `stdlib/os.rex`, as well as their supporting runtime infrastructure in `runtime/runtime_src.asm`.

## 2. Findings: `io.rex` & `os.rex` Audit

### 2.1. Incomplete Implementation
The current `stdlib/io.rex` and `stdlib/os.rex` files contain only protocol stubs with `pass` or placeholder `return` statements. 

**io.rex:**
- `print()`, `println()`, `write()`: All use `pass`. They should probably call built-in `output` or use raw syscalls via `$`.
- `read_file()`, `write_file()`, `append_file()`: Stubs returning empty strings or `pass`. These require `sys_open` (2), `sys_read` (0), `sys_write` (1), and `sys_close` (3).

**os.rex:**
- `args()`: Returns `pass`. Requires access to the stack above `_start` where `argc` and `argv` reside.
- `exit()`: Returns `pass`. Should call `$(60, code)`.
- `getenv()`: Returns `""`. Requires scanning the environment pointer array.
- `time_ns()`: Returns `0`. Requires `sys_clock_gettime` (228) with `CLOCK_MONOTONIC`.
- `sleep()`: Returns `pass`. Requires `sys_nanosleep` (35).

### 2.2. Syscall Usage & Safety
The Rex language supports raw syscalls via the `$` operator (e.g., `$(60, 0)` for `exit(0)`). However, `stdlib` files currently do not use this feature. 
- **Recommendation:** Implement these stubs using the `#unsafe` decorator and `$` operator where appropriate.

### 2.3. Error Handling
There is currently no mechanism in the `stdlib` stubs to check for or return syscall errors (typically returned in `rax` as `-errno`).
- **Gap:** Rex needs a way to handle negative return values from syscalls.

## 3. Findings: Runtime & Codegen Support

### 3.1. Output Buffering
The current `codegen` emits direct `syscall` instructions for `output` (via `rt_prs`, `rt_pri`, etc.).
- **Performance Issue:** Every `output` call results in a `sys_write` syscall. For write-heavy workloads, this is extremely slow.
- **Proposal:** Implement a 4KB user-space buffer in the runtime. `output` should write to this buffer, and only call `sys_write` when the buffer is full or explicitly flushed.

### 3.2. Missing I/O Built-ins
While the lexer and parser have tokens for `TOK_INPUT` and `TOK_SHOW`, they are mostly unimplemented or aliases.
- `TOK_SHOW` is currently an alias for `output` with a newline flag set to 0, but the codegen doesn't actually support suppressing the newline in all printers (e.g., `rt_pri` always adds a newline).
- `TOK_INPUT` is lexed but not handled in the parser's `parse_stmt` or `parse_factor`.

## 4. Proposals & Recommendations

### 4.1. Buffered I/O Layer
Introduce a `runtime` structure for buffered stdout:
```nasm
section .bss
stdout_buf: resb 4096
stdout_idx: resq 1
```
Modify `rt_prs` and others to copy into `stdout_buf` and call `syscall` only on overflow.

### 4.2. File I/O Implementation (Stage 9/10)
Implement `read_file` in `io.rex`:
```rex
#unsafe
prot read_file(str path) -> str:
    int fd = $(2, path, 0, 0) // sys_open(path, O_RDONLY)
    if fd < 0: return ""
    // ... logic to fstat for size, alloc, read, close ...
    return content
```

### 4.3. Zero-Copy I/O
For `write_file`, if the `content` string is already in memory, `sys_write` can point directly to it, which is already "zero-copy" from the perspective of user-to-kernel transition. No additional Rex-level changes needed other than avoiding intermediate concatenations.

## 5. Summary of Bugs/Gaps
1. `rt_pri` (and other printers) always append `\n`, making `write()` and `show` impossible to implement correctly without runtime changes.
2. `TOK_INPUT` is a dead token in the parser.
3. `stdlib` is currently just a collection of empty stubs.
4. Missing `sys_open`, `sys_read`, `sys_close` logic in the compiler/runtime to support `io.rex`.
