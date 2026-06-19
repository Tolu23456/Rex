# Instruction Selection Optimization (T016)

This report analyzes the instruction selection patterns in the Rex compiler and proposes optimizations to replace inefficient instruction sequences with more optimal x86-64 alternatives.

## 1. Arithmetic & Bitwise Operations

### 1.1 `mov rax, 0` → `xor eax, eax`
The compiler often emits `mov rax, imm64` for constant zero, which is 10 bytes.
Replacing this with `xor eax, eax` (2 bytes) saves 8 bytes and reduces execution latency.
*Status: Partially implemented in some peephole patterns, but could be global.*

### 1.2 `imul` → `lea` for small constants
Current Rex uses `imul rax, rbx, imm` or similar for all multiplications.
For multipliers of 2, 3, 4, 5, 8, and 9, `lea` is significantly faster (1 cycle vs 3+ cycles).

| Multiplier | Optimal Sequence | Bytes | Savings |
|------------|------------------|-------|---------|
| x2 | `lea rax, [rax+rax]` | 3 | Latency |
| x3 | `lea rax, [rax+rax*2]` | 4 | Latency |
| x4 | `lea rax, [rax*4]` | 4 | Latency |
| x5 | `lea rax, [rax+rax*4]` | 4 | Latency |
| x8 | `lea rax, [rax*8]` | 4 | Latency |
| x9 | `lea rax, [rax+rax*8]` | 4 | Latency |

### 1.3 `idiv` → `shr` for powers of 2
Division by a constant power of 2 can be replaced by a bit shift.
`idiv` is extremely expensive (20-80 cycles). `sar` (signed) or `shr` (unsigned) is 1 cycle.
*Note: Signed division by power of 2 requires adjustment for negative numbers (see `imod` implementation in `codegen.asm` for existing logic).*

## 2. Comparisons & Booleans

### 2.1 `cmp + setcc + movzx` → `cmovcc`
Currently, Rex evaluates comparisons into a 0/1 boolean in `rax`:
```asm
cmp rbx, rax    ; 3 bytes
setg al         ; 3 bytes
movzx rax, al   ; 4 bytes
```
Total: 10 bytes.

For `if` statements, this boolean is then immediately tested:
```asm
test rax, rax   ; 3 bytes
jz label        ; 6 bytes
```
Total for comparison + branch: 19 bytes.

If we combine these, we can emit the branch directly after the `cmp`:
```asm
cmp rbx, rax    ; 3 bytes
jng label       ; 6 bytes (jump if not greater)
```
Total: 9 bytes. **Savings: 10 bytes (52%) and 3 instructions.**

### 2.2 Boolean Normalization
`codegen_emit_normalize_bool_rax` emits:
```asm
test rax, rax   ; 3 bytes
setnz al        ; 3 bytes
movzx rax, al   ; 4 bytes
```
This is used before conditional branches if the expression wasn't already a boolean.
If the next instruction is `test rax, rax; jz/jnz`, the normalization is redundant.

## 3. String & Memory Operations

### 3.1 Bulk Zeroing with `xorps` or `rep stosq`
`codegen_emit_seq_alloc` currently zeros fields using `mov qword [rax], 0`.
For larger allocations or clearing sequence bodies, `rep stosq` (µcoded) or SIMD `pxor` + `movdqu` is faster.

### 3.2 String Equality
String comparison currently calls a runtime blob.
For very short strings (<= 8 bytes), inline `cmp` on registers could be used if strings are interned or padded.

## 4. Specific Rex Operations

### 4.1 `abs(rax)`
Current implementation:
```asm
mov rbx, rax
neg rax
cmovs rax, rbx  ; if original was positive, restore it
```
Total: 10 bytes.
Using `cdq` (sign extend to rdx) + `xor` + `sub`:
```asm
cqo             ; rax -> rdx:rax (sign bit in every bit of rdx)
xor rax, rdx
sub rax, rdx
```
Total: 8 bytes.

### 4.2 `not rax` (Logical NOT)
Current implementation for integers:
```asm
test rax, rax   ; 3 bytes
setz al         ; 3 bytes
movzx rax, al   ; 4 bytes
```
Total: 10 bytes.
Could be 7 bytes using `cmp rax, 1; sbb rax, rax; inc rax` or similar, but the current sequence is quite readable for the CPU.

## 5. Bitwise Intrinsics (Potential)

Rex currently lacks direct access to specialized x86 instructions:
- `popcnt`: Population count (set bits).
- `bsf` / `tzcnt`: Find first set bit (trailing zeros).
- `bsr` / `lzcnt`: Find last set bit (leading zeros).

Adding these as built-in protocols would allow Rex to compete with C in bit-manipulation heavy benchmarks (e.g., chess engines, compression).

## 6. Summary of Proposed Savings

| Pattern | Current | Optimized | Byte Savings | Cycle Savings |
|---------|---------|-----------|--------------|---------------|
| `if a > b` | 19 bytes | 9 bytes | 10 bytes | 3-5 cycles |
| `abs(x)` | 10 bytes | 8 bytes | 2 bytes | 1-2 cycles |
| `x * 5` | 18 bytes | 4 bytes | 14 bytes | 2 cycles |
| `x / 8` | 11 bytes | 3 bytes | 8 bytes | ~40 cycles |
| `var = 0` | 18 bytes | 9 bytes | 9 bytes | 1-2 cycles |
