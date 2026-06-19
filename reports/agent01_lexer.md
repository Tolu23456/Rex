# Agent 01: Lexer Deep Analysis Report

## Task T001: Lexer Audit

This report documents a deep analysis of `lexer/lexer.asm`, focusing on token classification, indentation tracking, keyword dispatch, and potential optimizations.

### 1. Bug Audit & Edge Cases

#### 1.1 Indentation Tracking
*   **Mixed Tabs/Spaces:** The indentation logic (`.cs` loop at line 53) only counts spaces (ASCII `0x20`). Tabs (ASCII `0x09`) are NOT counted toward indentation depth. If a file uses tabs for indentation, it will be treated as zero indentation, potentially causing incorrect block structures.
    *   **Proposed Fix:** Define a standard tab width (e.g., 4 or 8) and increment the column counter accordingly in `.cs`.
*   **Empty Lines Inside Blocks:** The `.cd` logic (line 62) handles newlines (`0x0A`) by jumping to `.bl`, which increments `lex_pos` and restarts the lexer. This correctly skips empty lines without affecting the indentation state.
*   **Dedent Past Root:** The `.li` loop (line 84) handles dedents. If the current indentation `rbx` is less than the top of `indent_stack`, it decrements `indent_depth` and increments `pending_dedents`. If it dedents past the root (depth 0), it stops at `.de`.
    *   **Potential Issue:** If the code dedents to a level that was never explicitly indented to (e.g., indent 4, then dedent to 2), the current logic will emit multiple dedents until it finds a matching level or hits root. This might be intended for some languages, but usually, it's a syntax error.

#### 1.2 Token Classification
*   **Keyword Dispatch:** `lexer_classify` uses a series of `cmp` and `je` instructions. While functional, it is O(N) where N is the number of keywords.
*   **Little-Endian Comparisons:** The code uses `dword [tok_ident]` to compare the first 4 bytes of a token.
    *   **Correctness:** "memo" is `0x6F6D656D` (m=6D, e=65, m=6D, o=6F).
    *   **Found Issue:** At line 715 (decorator check), "memo" is checked as `0x6F6D656D`.
        ```asm
        cmp dword [tok_ident], 0x6F6D656D  ; "memo" LE
        ```
        In Little-Endian, `0x6F6D656D` is `6D 65 6D 6F` which is `m`, `e`, `m`, `o`. This is correct.
    *   **Found Issue:** At line 752, "tota" (for "total") is checked as `0x61746F74`.
        `t=74, o=6F, t=74, a=61`. LE: `74 6F 74 61` which is `t`, `o`, `t`, `a`. Correct.
    *   **Found Issue:** `lexer_classify` at line 973:
        ```asm
        cmp eax, 0x6F6D656D
        ```
        This checks for "memo" as a bare keyword. The comment at line 971 says bare "memo" is removed in favor of `#memo`, which matches the logic (it falls through if it matches "memo" with a null terminator at `+4`).

#### 1.3 Off-by-one & Bounds Errors
*   **Identifier Length:** `tok_ident` is 64 bytes (`resb 64`). The `.id_l` loop (line 473) checks `rbx < 63` before storing, ensuring space for a null terminator. This is safe.
*   **Column Tracking:** `tok_col` is 0-indexed byte offset from line start. However, `lexer_init` sets it to 0, but I don't see it being incremented in `lexer_next`'s main loops. Only `lex_pos` is updated.
    *   **Bug:** `tok_col` remains 0 for all tokens unless a specific handler updates it (which they don't seem to).
*   **Line Tracking:** `tok_line` is 1-indexed. It is set to 1 in `lexer_init`.
    *   **Bug:** I don't see `tok_line` being incremented in the `.enl` (newline) handler.
        ```asm
        .enl:
            inc qword [lex_pos]
            mov byte [at_line_start], 1
            mov byte [tok_type], TOK_NEWLINE
            jmp .done
        ```
        It should `inc qword [tok_line]`.

### 2. Proposed Faster Keyword Dispatch

The current `lexer_classify` is a long chain of comparisons. A **Minimal Perfect Hash (MPH)** or a **Trie-based dispatch** would be significantly faster.

**Minimal Perfect Hash Strategy:**
1.  Compute a simple hash of `tok_ident` (e.g., `(len * 31 + first_char) % table_size`).
2.  Use the hash as an index into a jump table or a compact array of keyword structures.
3.  Since the set of keywords is fixed, we can find a hash function with zero collisions.

**Trie Strategy:**
1.  Switch on the first character.
2.  For each character, switch on the length or the next character.
3.  This reduces the number of comparisons from O(N) to O(L) where L is the length of the identifier.

### 3. Summary of Bug Findings

| Line | Bug | Description | Proposed Fix |
|---|---|---|---|
| 53 | Mixed Tabs/Spaces | Tabs not handled in indentation. | Add `cmp al, 0x09` and handle tab width. |
| 429 | Line Tracking | `tok_line` not incremented on newline. | Add `inc qword [tok_line]` and reset `tok_col`. |
| 19-30 | Column Tracking | `tok_col` never updated. | Update `tok_col` whenever `lex_pos` moves. |
| 762 | LE Constant | `#hot` dword `0x00746F68`. | Correct LE for `h,o,t,\0` is `0x00746F68`. |

### 4. Implementation Notes for `lexer_classify`
The current implementation is actually a "manual trie" using `dword` comparisons for the first 4 bytes, which is quite efficient for x86-64, but the linear search through these `cmp` blocks is the bottleneck. Sorting them by frequency or using a hash-based dispatch would improve performance.
