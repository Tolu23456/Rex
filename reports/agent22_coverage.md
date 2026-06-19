# Test Coverage Gap Analysis (T022)

## Compiler Feature Coverage Map

| Feature | Test File(s) | Status |
|---|---|---|
| **Basic Types** | `test.rex`, `tests/math_test.rex`, `tests/test_bool.rex`, `tests/test_str.rex` | covered |
| **Control Flow (if/elif/else)** | `tests/elif_else_test.rex`, `tests/conditional_test.rex` | covered |
| **Control Flow (for/while)** | `tests/for_test.rex`, `tests/while_stop_test.rex` | covered |
| **Control Flow (when/is)** | `edgecases/test_nested_when.rex`, `tests/suite/t_when_T*` | covered |
| **Protocols (Basic)** | `tests/prot_test.rex`, `tests/return_test.rex` | covered |
| **Protocols (Recursive)** | `edgecases/test_recursive_protocol.rex`, `tests/suite/t_rec_T*` | covered |
| **Protocols (Parameterized)** | `tests/test_parameterized_prot.rex` | covered |
| **Memory (Arena/Pool)** | `tests/test_mm_switch.rex`, `tests/stage6_mm.rex` | covered |
| **Collections (Sequences)** | `tests/test_sequences.rex`, `tests/suite/t_seq_T*` | covered |
| **Collections (Dictionaries)** | `tests/dict.rex`, `tests/test_dict.rex`, `tests/suite/t_dict_T*` | covered |
| **Expressions (Short-circuit)** | `edgecases/test_and_or_short_circuit.rex` | covered |
| **Type Propagation** | `edgecases/test_type_propagation.rex`, `tests/test_type_propagation.rex` | covered |
| **Memoization** | `tests/memo_reset_test.rex`, `tests/suite/t_memo_T*` | covered |

## Identified Gaps

### 1. Zero-Length Collections
The current tests use non-empty sequences and dictionaries. Edge cases like initializing a sequence and immediately calling `len` or `pop`, or an empty dictionary, are not explicitly verified.

### 2. Boundary Value Arithmetic
Integer overflow/underflow is not tested. Floating point edge cases (Inf, NaN, very small/large values) are missing.

### 3. Deep Nesting
While `test_nested_when` exists, deeply nested loops (3+ levels) combined with `stop N` (if implemented) or just complex control flow are missing.

### 4. Empty Protocol Bodies
Protocols with only `pass` or no statements (if permitted) are not tested.

### 5. String Literal Limits
The grammar mentions a 63-byte limit. Tests for strings exactly 63 bytes and exactly 64 bytes (checking truncation) are needed.

### 6. Complex Type Arithmetic
The `complex` type has lexer support but its arithmetic operators and propagation rules are sparsely tested.

### 7. Logical Operator Combinations
Complex boolean expressions like `(a and b) or (c and not d)` with various combinations of `true`, `false`, and `unknown` need more systematic coverage.

### 8. Dictionary with 0 and 1 Entries
Dictionary performance and correctness at the very start of its life (0 or 1 keys) are not specifically targeted.

## Prioritized Missing Test Cases

| # | Priority | Title | Rex Code Snippet / Description |
|---|---|---|---|
| 1 | High | Empty Sequence Ops | `seq s; output len s; pop s` (should error or return 0 gracefully) |
| 2 | High | String Truncation | `str s = "..."` (64+ chars) - verify length is 63. |
| 3 | High | Negative Loop Steps | `for :i in 10..0 step -1:` |
| 4 | High | Complex Arithmetic | `complex c = 1+2j; output c + (3+4j)` |
| 5 | Medium | Empty Protocol | `prot p(): pass` + `@p()` |
| 6 | Medium | Max Var Table | Declare 256 variables to trigger `VAR_MAX` guard. |
| 7 | Medium | Max Proto Table | Declare 128 protocols to trigger `PROTO_MAX` guard. |
| 8 | Medium | Nested Logical Ops | `output (true and unknown) or false` |
| 9 | Medium | Zero Step Loop | `for :i in 0..10 step 0:` (should handle or error) |
| 10 | Medium | Large String Literal | Source file with 1MB string literal. |
| 11 | Low | Type Cast Edge Cases | `int(1.9999)`, `float(-1)` |
| 12 | Low | Dict Key Variable | `str k = "key"; d[k] = 1` (Verify B-10 defect) |
| 13 | Low | Protocol Pointer Type | `typeof @prot` (Stage 5 feature) |
| 14 | Low | Carry Flag Check | `if carry: ...` (Stage 9 feature) |
| 15 | Low | Overflow Flag Check| `if overflow: ...` (Stage 9 feature) |
| 16 | High | Multi-level Skip | `skip 2` in nested loops. |
| 17 | Medium | Bitwise Unary | `~(-1)` |
| 18 | Medium | Mixed Bitwise/Arith | `1 + (2 & 3) ^ 4` |
| 19 | High | Recursive Prot Param | `prot r(n): if n > 0: @r(n-1); output n` |
| 20 | Medium | Protocol Return Shadow| `int x; prot p(): int x; :x = 1; return x` |
| 21 | High | Sequence OOB | `seq s; push s 1; output s[1]` (Should trigger B-15) |
| 22 | Medium | When Else Fallthrough| `when x: is 1: pass else: output 0` |
| 23 | Low | Abs with Float | `abs(-1.5)` |
| 24 | Medium | Short-circuit Side Effects | `prot p(): output 1; return true` + `if false and @p(): pass` |
| 25 | Medium | Integer Base Literals | `0xG` (invalid), `0b2` (invalid), `0o8` (invalid) |
| 26 | Medium | Identifiers at Limit | Variable with exactly 31 chars vs 32 chars. |
| 27 | High | Dict Collision | Multiple keys hashing to same slot (if known). |
| 28 | Medium | Use Statement Nesting | `use mm pool: use mm arena: ...` |
| 29 | Low | Pass in All Blocks | `if x: pass elif y: pass else: pass` |
| 30 | Medium | Return from While | `while true: return 1` |
