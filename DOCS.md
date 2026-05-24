# Rex Programming Language Specification

Rex is a compiled, low-level language that combines the readability of Python's indentation-based blocks with the performance and control of pure x86_64 assembly.

## Design Philosophy
1.  **Readability:** Code should look like Python.
2.  **No Dependencies:** The compiler (`rexc`) is written in pure assembly and generates standalone ELF64 binaries without needing an external assembler or linker.
3.  **Direct System Access:** Rex translates high-level constructs directly into optimized machine code and system calls.

## Syntax

### Indentation
Rex uses significant whitespace for code blocks.
- **INDENT:** Increases the nesting level.
- **DEDENT:** Decreases the nesting level and closes the current block.

### Variables
All variables are currently 64-bit integers.
```rex
# Declaration
int count

# Mutable Assignment (requires colon prefix)
:count = 42
```

### Output
The `output` keyword prints values to the terminal followed by a newline.
```rex
output count
output 100
```

### Control Flow
Rex supports `if` blocks and `for` loops.
```rex
if :count:
    output 1

# Range-based loops
for i in 0..10:
    output i
```

## Compiler Architecture
The Rex compiler (`rexc`) performs a single-pass over the source file:
1.  **Lexing:** Converts characters into a stream of tokens, tracking indentation levels on a stack.
2.  **Parsing:** Recognizes language constructs using recursive descent.
3.  **Emission:** Emits x86_64 machine code directly into an internal buffer.
4.  **Patching:** Maintains a "patch stack" to resolve forward jumps (e.g., jumping from the `if` condition to the end of the block) once the target address is known.
5.  **ELF Generation:** Manually constructs the ELF64 header and Program Header, prepending them to the emitted machine code.

## Technical Details
- **Base VA:** Executables are loaded at `0x400000`.
- **Entry Point:** Execution begins at `0x400080` (directly after the 128-byte header).
- **Runtime:** Every binary includes a minimal runtime for integer-to-string conversion and terminal output.
