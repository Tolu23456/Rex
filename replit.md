# Rex Compiler

A self-hosting x86-64 compiler written entirely in NASM assembly. Rex compiles `.rex` source files to native ELF64 binaries.

## How to build

```
make clean && make all
```

This assembles all runtime blobs (`runtime/*.bin`), compiles all compiler modules, and links them into `./rexc`.

## How to run

```
./rexc <source.rex> [-o output]
```

Example:
```
./rexc tests/test_basic.rex -o out
./out
```

## Project structure

| Directory   | Contents                                      |
|-------------|-----------------------------------------------|
| `lexer/`    | Tokeniser (NASM)                              |
| `parser/`   | Parser, symbol table, type registry (NASM)    |
| `irgen/`    | IR generation, register allocator, optimizer  |
| `codegen/`  | x86-64 code generation (NASM)                 |
| `runtime/`  | Flat binary runtime blobs (print functions)   |
| `main/`     | Entry point                                   |
| `tests/`    | `.rex` source test files                      |
| `include/`  | Shared NASM include files                     |

## User preferences

- Keep the existing NASM assembly structure — do not migrate to another language or build system.
