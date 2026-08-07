<p align="center">
  <img src="rex-icon-v1.svg" width="200" alt="Rex logo" />
</p>

<h1 align="center">Rex</h1>

<p align="center">
  An x86-64 compiler for the Rex language, written entirely in NASM assembly.
  No C. No libc. No other languages.
</p>

`rexc` compiles `.rx` sources to standalone ELF64 binaries with the runtime
inlined.

## Features

- Self-contained compiler: ~330 KB executable built purely from NASM assembly
- Inlined runtime — generated binaries need no external runtime or libc
- Native x86-64 code generation with register allocation and an optimizer
- Modules, structs, sequences, dictionaries, file I/O, and more
- Error messages with source locations and carets

## Building

Requires `nasm` and `ld`.

```
make
```

This assembles all runtime blobs, compiles all compiler modules, and links
them into `./rexc`.

## Usage

```
rexc <source.rx> [-o <output>]
```

```rex
int a = 10
int b = 5
output(a + b)   // prints 15
```

```
./rexc hello.rx -o hello
./hello
```

## Tests

```
make test
```

The suite compiles and runs `tests/*.rx` and diffs output against the
corresponding `.expected` files. Negative tests use a `.err` file: the compile
must fail with that message substring.

## Project structure

| Directory  | Contents                                      |
|------------|-----------------------------------------------|
| `lexer/`   | Tokeniser (NASM)                              |
| `parser/`  | Parser, symbol table, type registry (NASM)    |
| `irgen/`   | IR generation, register allocator, optimizer  |
| `codegen/` | x86-64 code generation (NASM)                 |
| `runtime/` | Flat binary runtime blobs (print functions)   |
| `main/`    | Entry point                                   |
| `tests/`   | `.rx` source test files                       |
| `include/` | Shared NASM include files                     |

## Design

- `imp/design.md` — language design and syntax (source of truth)
- `imp/grammar.md` — grammar
- `imp/rex_ir.md` — intermediate representation

## License

[MIT](LICENSE)
