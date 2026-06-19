# Agent 28: Error Reporting & Compiler Diagnostics Analysis

## Audit of Error Paths

The Rex compiler currently handles errors in several ways:
1.  **Silent Failure**: Many parser paths use `jne .done`, which simply skips the statement or expression without reporting an error. This leaves the compiler in an inconsistent state and produces no diagnostic for the user.
2.  **Fatal Compiler Errors**: Some critical paths (like variable declarations missing an identifier) call `fatal`, which prints a hardcoded message (e.g., "error: expected identifier") and terminates the compiler immediately.
3.  **Runtime Error Emittance**: The `err` statement in Rex is translated into a runtime call to `rt_err` (for strings) or a type-specific printer followed by `exit(1)`.
4.  **Implicit Lexer Errors**: The lexer skips unknown characters and resets, which can lead to confusing parser errors later.

### Major Issues Identified

1.  **Lack of Line/Column Information**: While `lexer.asm` tracks `tok_line` and `tok_col`, these are rarely used in error messages. Most error paths don't report WHERE the error occurred.
2.  **Silent Drops**: In `parser.asm`, many `jne .done` cases should probably be error reports. For example, if `parse_expr` fails to find a valid factor, it returns a default integer 0, which might lead to confusing behavior instead of a clear error.
3.  **No Source Snippets**: Errors do not show the offending line of code or a caret pointing to the token.
4.  **Limited Diagnostic Variety**: Only a few hardcoded error messages exist (like `err_id`).

## Proposed Structured Diagnostic System

A robust diagnostic system for Rex should include:
- **Error Code**: (e.g., E001) for easy lookup in documentation.
- **Location**: `file:line:col`.
- **Severity**: Error, Warning, or Note.
- **Message**: Clear description of the problem.
- **Source Context**: 1-3 lines of source code with a caret (`^`) highlighting the error.
- **Suggested Fix**: When possible (e.g., "missing ':' before identifier").

### Implementation Sketch (NASM)

```nasm
; include/rex_defs.inc
%define ERR_EXPECTED_ID 101
%define ERR_TYPE_MISMATCH 201

; main/main.asm or a new diagnostics.asm
report_error:
    ; rdi = error_code
    ; Uses global tok_line, tok_col, and lex_src
    push rdi
    ; Print "error[E{rdi}]: "
    ; Print filename:line:col
    ; Find start of current line in lex_src
    ; Print the line
    ; Print spaces up to tok_col, then '^'
    ; Print error-specific message from a table
    pop rdi
    inc qword [compiler_error_count]
    ret
```

### Action Plan
1.  **Phase 1**: Replace `call fatal` with a call to a new `report_diagnostic` function that includes line numbers.
2.  **Phase 2**: Audit all `jne .done` in `parser.asm` and determine which ones should be actual errors.
3.  **Phase 3**: Implement source snippet printing by scanning `lex_src` backwards from `lex_pos` to find the start of the line.
4.  **Phase 4**: Add a summary at the end of compilation: "X errors found. Compilation failed."

## Summary of Findings
The current system is minimal and "brittle," favoring immediate termination or silent ignoring of invalid syntax. Moving to a structured system will significantly improve the developer experience and help in debugging complex Rex programs.
