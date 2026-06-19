# Agent 21: Standard Library (math.rex, str_utils.rex, json.rex) Analysis

## 1. math.rex Audit

The `math.rex` standard library provides wrappers for high-performance floating-point operations implemented as runtime blobs.

### Findings:
- **Missing Core Functions**: The library is missing several essential functions for a complete math suite:
    - `tan(x)`, `asin(x)`, `acos(x)`, `atan(x)`, `atan2(y, x)` (Inverse trigonometry).
    - `log10(x)`, `log2(x)` (Common logarithms).
    - `sinh(x)`, `cosh(x)`, `tanh(x)` (Hyperbolic functions).
- **Precision and Correctness**: 
    - `rt_math_sin` and `rt_math_cos` use the x87 `fsin`/`fcos` instructions. These are known to have precision issues for very large inputs (outside the range of -2^63 to 2^63) because they use a hardware-embedded value of Pi. 
    - `rt_math_exp`, `rt_math_log`, and `rt_math_pow` are currently **empty stubs** returning `0.0`. This is a critical failure.
- **Min/Max Behavior**: `rt_math_min` and `rt_math_max` use `minsd` and `maxsd`. These instructions have specific behavior regarding `NaN` and `-0.0` (they return the second operand if either is `NaN`). Standard library documentation should specify this.

### Proposed Fixes:
- Implement `exp(x)` using `f2xm1` (2^x - 1) or a polynomial approximation for higher precision.
- Implement `log(x)` using `fyl2x`.
- Implement `pow(x, y)` using `2^(y * log2(x))`.
- Add wrappers for `tan`, `atan2`.

---

## 2. str_utils.rex Audit

`str_utils.rex` provides common string manipulation utilities.

### Findings:
- **Stub Implementation**: Almost all functions in `str_utils.rex` (`parse_int`, `parse_float`, `encode_base64`, etc.) are empty stubs returning `0`, `0.0`, or `""`. 
- **Missing Basic Utilities**: 
    - No `find_last`, `replace_all`, or `is_alpha`/`is_numeric` functions.
    - `split` and `join` exist as runtime blobs (`rt_str_split`, `rt_str_join`) but are not exposed through `str_utils.rex` protocols consistently.
- **Index Safety**: `rt_str_slice` (the backend for slicing) has a bug:
    ```nasm
    cmp r13, r14
    jge .empty
    ```
    If `start == end`, it returns an empty string, which is correct. However, if `start < 0` or `end > len`, it also returns `.empty`. It should ideally throw a bounds error or clamp the values according to standard convention.
- **Off-by-one in `split`**: `rt_str_split` counts parts correctly, but if the string ends with a delimiter, it might not handle the trailing empty part consistently with other languages (e.g., Python).

### Proposed Fixes:
- Implement `parse_int` and `parse_float` by iterating over characters and handling signs/decimals.
- Connect `str_utils.rex` protocols to the existing runtime blobs (`rt_str_upper`, `rt_str_lower`, `rt_str_trim`, `rt_str_rev`, `rt_str_split`, `rt_str_join`).

---

## 3. json.rex Audit

`json.rex` is a hand-written JSON parser and serializer.

### Findings:
- **Parser Correctness (RFC 8259)**:
    - The `parse()` protocol is a `pass` stub. It does not implement a recursive descent or state machine parser.
    - String escape sequences (e.g., `\uXXXX`, `\n`, `\t`) are likely unhandled by the planned implementation.
    - Numbers with exponents (e.g., `1.2e-3`) are usually the hardest part of JSON parsing; the current Rex lexer/parser doesn't seem to support them natively.
- **Serializer**: `stringify()` is a stub returning `{}`. It needs to recursively traverse a `dict` (type 11) or `seq` (type 6) and handle nesting.

### Proposed Fixes:
- Implement a recursive descent parser in Rex using `while` loops and `when` statements once the `dict` and `seq` types are fully stable.
- Add support for escape sequence decoding in `str_utils.rex`.

---

## 4. Summary of Bugs and Gaps

| Function | File | Issue | Severity |
| :--- | :--- | :--- | :--- |
| `exp`, `log`, `pow` | `runtime_src.asm` | Stubbed to return 0.0 | High |
| `parse_int`, `parse_float` | `str_utils.rex` | Stubbed to return 0 | High |
| `json.parse` | `json.rex` | Not implemented | Medium |
| `rt_str_replace` | `runtime_src.asm` | Returns original string (stub) | Medium |
| `rt_str_join` | `runtime_src.asm` | Potential overflow in length calculation | Low |

## Conclusion
The Rex standard library is currently a collection of well-defined protocols that mostly point to incomplete or stubbed implementations. While the instruction selection for math (`sqrtsd`, `fsin`) is correct for performance, the lack of logic in `exp`/`log`/`pow` and the entirety of `json.rex` prevents its use in production workloads.
