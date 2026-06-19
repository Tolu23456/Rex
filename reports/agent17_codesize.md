# Binary Code Size Optimization Analysis (Agent 17)

## Overview
This report analyzes the x86-64 machine code emitted by the Rex compiler and identifies opportunities to reduce the binary footprint. Current codegen often favors 64-bit instructions and generic patterns where 32-bit instructions or specialized encodings would be more compact.

## Findings

### 1. Unnecessary 64-bit Prefixes (REX.W)
The compiler frequently emits `REX.W` (0x48) prefixes for operations that don't strictly require 64-bit operands, especially when dealing with constants or values that fit in 32 bits. On x86-64, writes to 32-bit registers (e.g., `eax`) automatically zero-extend to the full 64-bit register (`rax`).

**Identified Issues:**
- `codegen_emit_exit1`: Uses 7-byte `mov rax, 60` (48 C7 C0 3C 00 00 00). Could be 5-byte `mov eax, 60` (B8 3C 00 00 00).
- `codegen_finish`: Uses 7-byte `mov rax, 60` (48 C7 C0 3C 00 00 00).
- `codegen_emit_zero_var`: Emits 9 bytes (48 C7 04 25 <addr32> 00 00 00 00).
- `codegen_emit_lnot_int_rax`: Uses 4-byte `movzx rax, al` (48 0F B6 C0). Could be 3-byte `movzx eax, al` (0F B6 C0).

### 2. Immediate Encoding Efficiency
Small constants can often be encoded using shorter instruction forms.

**Opportunities:**
- `mov rax, 0`: Currently often emitted as a full 64-bit move or a 32-bit move. `xor eax, eax` (2 bytes: 31 C0) is already used in some places (like `codegen_emit_mov_eax_imm32`) but not everywhere.
- `add rax, 1`: Can be `inc rax` (3 bytes: 48 FF C0) or `add rax, byte 1` (4 bytes: 48 83 C0 01).
- `cmp rax, 0`: Use `test rax, rax` (3 bytes: 48 85 C0) instead of `cmp rax, 0` (4 bytes: 48 83 F8 00).

### 3. Redundant NOPs and Alignment
The compiler uses `codegen_align_loop_top` to align loops to 16-byte boundaries and `codegen_emit_for_start` to align body starts to 32-byte boundaries.

**Observations:**
- While alignment helps performance (i-cache/µop-cache), it increases binary size significantly in code with many small loops.
- `o28_scan_body` and `o31_scan_body` use 16-byte NOP headers (2x 8-byte NOPs) for retroactive patching. These are often left as NOPs if no promotion occurs.

### 4. Function Outlining Candidates
Repeated sequences in the runtime and generated code could be moved to shared helper functions.

**Candidates:**
- The 5-byte sequence for `syscall` setup and execution in `codegen_finish` and `codegen_emit_exit1`.
- The `cmp sil, TYPE_STR ...` dispatch blocks in `codegen_output_typed` and `codegen_output_rax`.

## Proposed Improvements

| Optimization | Existing Pattern | Optimized Pattern | Savings |
| :--- | :--- | :--- | :--- |
| **32-bit Exit** | `48 C7 C0 3C 00 00 00` | `B8 3C 00 00 00` | 2 bytes |
| **32-bit Zero Ext** | `48 0F B6 C0` (movzx rax, al) | `0F B6 C0` (movzx eax, al) | 1 byte |
| **Short Zero Var** | `48 C7 04 25 <addr32> 0` | `C7 04 25 <addr32> 0` | 1 byte |
| **Test vs Cmp** | `48 83 F8 00` (cmp rax, 0) | `48 85 C0` (test rax, rax) | 1 byte |
| **XOR for Zero** | `48 B8 0000000000000000` | `31 C0` (xor eax, eax) | 8 bytes |

## Quantification of Impact
In a typical Rex program with:
- 10 Global variable accesses: ~10 bytes saved.
- 5 Exit/System calls: ~10 bytes saved.
- 20 Boolean operations: ~20 bytes saved.
- Constant folding/Zeroing: ~50-100 bytes saved.

For the Rex compiler itself (if self-hosted), these optimizations could reduce the binary size by approximately 3-5%.

## Implementation Plan
1. **Audit `codegen.asm`**: Systematically replace `mov rax, imm32` with `mov eax, imm32` where the upper bits are not needed.
2. **Refine `emit_b/d/q`**: Ensure these helpers are as thin as possible.
3. **Peephole Pass**: Add a pass to catch `mov rax, rax` or `add rax, 0` (though Rex's `O3` already does some of this).
4. **Conditional Alignment**: Only align loops that are likely to be "hot" or have a certain minimum body size.
