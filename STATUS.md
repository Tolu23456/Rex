# Rex Compiler Status Report

## Current State
The Rex compiler (`rexc`) is a pure x86_64 assembly compiler designed to compile a Python-like indented language directly into standalone Linux ELF64 binaries.

### What is working:
- **Direct ELF64 Generation:** The compiler manually constructs the ELF header and Program Header. It emits valid executables that the Linux kernel can load and execute.
- **Indentation-Aware Lexer:** Implemented a lexer that handles Python-style blocks using an internal indentation stack.
- **Recursive Descent Parser:** A single-pass parser is in place for variable declarations (`int x`), mutable assignments (`:x = 10`), conditional logic (`if`), and loops (`for`).
- **Integrated Runtime:** A minimal assembly runtime is embedded in every generated binary, providing routines for integer-to-string conversion and terminal output via direct syscalls.

### Current Challenges (In Progress):
- **Stack Stability:** I identified that some utility functions (like `strcpy`) were using recursive calls instead of loops, which caused stack overflows. I am currently refactoring these into iterative versions.
- **Memory Management:** The compiler is being updated to strictly distinguish between internal buffer addresses and target virtual addresses to prevent segmentation faults during code emission.
- **Single-Pass Branching:** Refining the logic for forward-jump patching (used in `if` and `for` blocks) to ensure relative displacements are calculated correctly relative to the instruction pointer.

## Next Steps
1.  Finalize the iterative refactor of utility functions to ensure compiler stability.
2.  Verify the "Minimal Milestone": a single Rex file with `output 42` compiling to a binary that prints "42".
3.  Re-verify nested loop and conditional stability.
4.  Expand the runtime to support string concatenation and input.

## Repository Layout
- `rexc.asm`: The main compiler source.
- `common.inc` / `tokens.inc`: Shared constants and token definitions.
- `DOCS.md`: Language specification and usage guide.
- `STATUS.md`: This report.
