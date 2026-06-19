# Agent 29: Self-Hosting Gap Analysis

## Overview
This report analyzes the gaps between the current Rex compiler (written in NASM) and the requirements for a self-hosted Rex compiler. Rex V5.0 aims for full self-hosting, where the compiler is written in Rex itself.

## Current Self-Hosting Status (Phase 2)
The project currently has a skeleton for a self-hosted lexer in `rex_bootstrap.rx`. 

### Features Required for Self-Hosting
Based on the analysis of `rex_bootstrap.rx` and the compiler codebase (`parser/parser.asm`, `codegen/codegen.asm`), the following features are critical:

1.  **Recursive Protocol Calls**:
    *   **Status**: Partial/Open.
    *   **Analysis**: The NASM compiler supports recursion, but issues with stack frame management for deep recursion or complex mutually recursive calls remain (Issue #18). Self-hosting requires robust recursion for the recursive-descent parser.

2.  **String Operations**:
    *   **Status**: Partial.
    *   **Gap**: The lexer needs `str_at` (index access), `str_len`, and `str_cmp`. While some are present as runtime blobs, they are not all exposed as first-class language constructs in the current parser dispatch.
    *   **Requirement**: Full implementation of `str_cat`, `str_at`, and `str_len` built-ins.

3.  **File I/O Syscall Wrappers**:
    *   **Status**: Planned/Missing.
    *   **Gap**: The compiler needs to read source files and write ELF binaries.
    *   **Requirement**: `file_open`, `file_read`, `file_write`, and `file_close` must be exposed. Currently, the lexer in `rex_bootstrap.rx` uses a hardcoded string.

4.  **Pointer Arithmetic / Raw Memory Access**:
    *   **Status**: Missing.
    *   **Analysis**: Compiling a compiler often requires low-level memory manipulation.
    *   **Requirement**: A `#unsafe` mode or a `$` syscall intercept is partially defined in the lexer (`TOK_DOLLAR`) but not fully integrated into the parser's expression tree.

5.  **Compile-Time Constants**:
    *   **Status**: Partial.
    *   **Analysis**: `parser/parser.asm` has some support for folding constant identifiers, but a more robust system for global constants is needed for token IDs.

## Missing Language Features (Detailed)

| Feature | Implementation Difficulty | Priority | Description |
| :--- | :--- | :--- | :--- |
| **Syscall Intercept ($)** | Medium | High | Allow direct `syscall` emission for I/O and OS interaction. |
| **String Indexing** | Low | High | `str_at(s, i)` or `s[i]` for character scanning. |
| **Recursive Protocols** | High | Critical | Required for the recursive-descent parser structure. |
| **Bitwise Operators** | Done | - | Already implemented in Stage 3b. |
| **Dictionary Literals** | Medium | Medium | Useful for keyword tables and symbol tables. |

## 5-Stage Bootstrap Path

### Stage 1: Language Completion (The "Infrastructure" Phase)
Implement the missing primitives in the NASM compiler:
*   Expose `str_at`, `str_len`, and `str_cmp` as built-ins.
*   Implement the `$` syscall intercept in `parser/parser.asm` to allow raw kernel calls.
*   Finalize stack frame management to support arbitrary recursion depth.

### Stage 2: Lexer-in-Rex (`rex_bootstrap.rx`)
Complete the lexer implementation. It should be able to tokenize its own source code and produce the same token stream as the NASM lexer. This validates string handling and basic control flow.

### Stage 3: Parser-in-Rex
Write the recursive-descent parser in Rex. 
*   Uses recursive protocols for grammar rules.
*   Uses `dict` for the symbol table.
*   Produces a flat sequence of "Instruction" records or IR.

### Stage 4: Codegen-in-Rex
Implement the x86-64 emitter in Rex.
*   Translates IR to machine code bytes.
*   Uses `file_write` to produce the final ELF binary.
*   Initially target a subset of Rex needed only for the compiler itself.

### Stage 5: The "Golden Loop"
1.  `rex_nasm compiler.rx -o rex2`
2.  `rex2 compiler.rx -o rex3`
3.  `diff rex2 rex3` (must be identical).

## Conclusion
The primary blockers for self-hosting are **File I/O** and **Recursive Protocol Reliability**. Once these are bridged, the transition to `rex_bootstrap.rx` can proceed. The current architecture of the NASM compiler (single-pass, flat symbol tables) is well-suited for a straightforward Rex-to-Rex port.
