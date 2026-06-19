# ABI & Calling Convention Compliance Report (T018)

## Overview
The Rex compiler targets the System V AMD64 ABI. This report audits the implementation in `codegen/codegen.asm`, `parser/parser.asm`, and `runtime/runtime_src.asm` for compliance with argument passing, return values, register preservation, and stack alignment.

## 1. Register Usage & Preservation

### ABI Requirements:
- **Argument Registers**: `rdi`, `rsi`, `rdx`, `rcx`, `r8`, `r9` (in order).
- **Return Register**: `rax` (primary), `rdx` (secondary for 128-bit).
- **Callee-Saved**: `rbx`, `rsp`, `rbp`, `r12`, `r13`, `r14`, `r15`.
- **Caller-Saved**: All other registers (`rax`, `rcx`, `rdx`, `rsi`, `rdi`, `r8`, `r9`, `r10`, `r11`).

### Findings:
- **Protocol Arguments**: `codegen_emit_arg_pops` correctly uses `rdi`, `rsi`, `rdx`, `rcx`, `r8`, `r9` for up to 6 parameters.
- **Internal Optimization Conflicts**:
    - Rex uses `r12` and `r13` for register promotion (O18/O28/O31).
    - Rex uses `r14` as a loop accumulator (O13).
    - Rex uses `r15` as a pinned loop counter (O2).
- **Preservation Violations**:
    - Protocols that use `r12`-`r15` via optimizations often fail to save/restore them unless they are "standard" frames.
    - `codegen_emit_frame_prologue` (line 6363+) only saves `r12` and `r13` if `regalloc_cnt` is set. If `r14` (accumulator) or `r15` (pin) are used, they are clobbered without being saved in the prologue.
    - **Critical**: `r12` is used for "push-style" frames (O21) as a parameter holder. It is pushed/popped (line 6316/6467), but if O27 (retroactive elision) fires, it might be NOPed even if the callee clobbers it.

## 2. Stack Alignment

### ABI Requirements:
- The stack must be 16-byte aligned before any `call` instruction. Since the `call` itself pushes an 8-byte return address, the stack at function entry is `16n + 8`.

### Findings:
- **Violation**: `codegen_emit_frame_prologue` subtracts a patched value from `rsp`.
    - Standard frames: `sub rsp, <size>`. If `<size>` is not `16n + 8` (accounting for the return address), calls inside the protocol will be misaligned.
    - Rex does not seem to force 16-byte alignment in `codegen_clear_frame` when calculating the final frame size.
- **Runtime Calls**: Calls to `rt_alc` and other runtime helpers are emitted throughout `codegen.asm`. Many of these occur when the stack may be misaligned (e.g., after an odd number of `push rax` for expression evaluation).
- **Push-Style Frames (O21)**: These push `r12` and `r13`, adding 16 bytes. This preserves alignment if it was aligned before, but if combined with `sub rsp, imm32`, the total must be checked.

## 3. Red Zone

### ABI Requirements:
- A 128-byte "red zone" below `rsp` is available for temporary data and is not clobbered by signals/interrupts.

### Findings:
- **Compliance**: `rt_prs` (line 127) uses the red zone (`rsp-8`) to store a newline character for a syscall. This is a valid use of the red zone.
- **Potential Risk**: The compiler does not explicitly use the red zone for expression spills, instead preferring `r10`/`r11` or the hardware stack. This is safe but misses an optimization opportunity.

## 4. Parameter Passing & Variadics

### Findings:
- Rex does not currently support variadic functions (like `printf`), so `al` (vector register count) is not set before calls. This is compliant for non-variadic calls.
- Float parameters are passed in `rax` (bit-cast from `xmm0`) rather than `xmm0` in some internal paths, then converted back. While internal to Rex, this violates System V if Rex protocols were to be called from C.

## 5. Summary of Violations

| Issue | Severity | Location | Description |
| :--- | :--- | :--- | :--- |
| **Callee-Saved clobber** | High | `codegen.asm` | `r14` (accumulator) and `r15` (pinned counter) are used without being saved in the prologue. |
| **Stack Alignment** | High | `codegen.asm` | No logic to ensure `rsp` is 16-byte aligned before `E8` call emissions. |
| **R12/R13 Clobber** | Medium | `codegen.asm` | O18 register allocation saves them, but O28/O31 (retroactive promotion) might use them without ensuring they were saved. |
| **Shadowing/TCO** | Low | `parser.asm` | TCO implementation correctly performs `leave` before `jmp`, preserving stack integrity. |

## Recommendations
1. **Mandatory Save**: Always push/pop `r14` and `r15` in `codegen_emit_frame_prologue`/`epilogue` if the protocol contains loops.
2. **Alignment Padding**: In `codegen_finalize` or similar, ensure the total `rsp` adjustment (including pushed registers) is a multiple of 16 (accounting for the 8-byte return address).
3. **Internal ABI Documentation**: Explicitly define the "Rex ABI" if it intentionally deviates from System V for internal calls, but enforce System V for any exported symbols or calls to external blobs.
