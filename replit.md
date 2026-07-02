# Rex Bootstrap Compiler

A hand-written, self-contained x86-64 ELF compiler for the **Rex V0.1** language, built entirely in NASM assembly with zero external dependencies in the output binary.

## How to build

```sh
make          # build ./rexc
make test     # build + run all tests (67 tests)
make clean    # remove build artifacts
```

## How to compile a Rex program

```sh
./rexc input.rex -o output
./output
```

## Project structure

| Directory | Contents |
|-----------|----------|
| `main/` | Entry point (arg parsing, file I/O, compilation loop) |
| `lexer/` | Tokeniser: keywords, identifiers, integers, indent tracking |
| `parser/` | Recursive-descent parser + variable table |
| `codegen/` | x86-64 machine code emitter |
| `runtime/` | Inline runtime blobs: print, alloc, SipHash, etc. |
| `include/` | Shared constants (`rex_defs.inc`) |
| `tests/` | Rex test programs + `.expected` output files |
| `docs/` | Grammar, opcodes, IR spec, benchmarks |

## Key docs

- `syn.md` — full language syntax reference
- `design.md` — language design decisions
- `OPTIMIZATIONS.md` / `rex_optimizations.md` — peephole & loop optimisations
- `todo.md` — stage-by-stage implementation checklist
- `CHANGELOG.md` — version history
- `docs/grammar.md` — formal EBNF grammar
- `docs/opcodes.md` — machine-code emit reference

## User preferences

<!-- Agent: record explicit user preferences here -->
