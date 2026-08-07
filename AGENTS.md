# AGENTS.md

## What this is
Rex is an x86-64 compiler for the Rex language, written **entirely in NASM assembly** (no C, no libc, no other languages). `rexc` compiles `.rex` sources to standalone ELF64 binaries with the runtime inlined. `imp/design.md` is the source of truth for language syntax; `imp/grammar.md` and `imp/rex_ir.md` describe grammar and IR (some can be stale — when code and `design.md` disagree, `design.md` is the conformance target).

## Build & test
- Requires `nasm` and `ld`.
- `make` builds `./rexc`. `make test` runs `./run_tests.sh`. `make clean` removes all `.o`, `*.bin`, and `rexc`.
- Single test: `./rexc tests/foo.rex -o /tmp/t && /tmp/t`, diff against `tests/foo.expected`. Tests without a `.expected` are skipped (suite is ~48). `run_tests.sh --verbose` shows diffs.
- CLI: `rexc <source.rex> [-o <output>]` (default output `a.out`, no `.bin` suffix).

## Architecture (dependency order)
`lexer/` → `parser/` (symtab, type_reg, proto, parser) → `irgen/` (`irgen.asm` emit, `ra.asm` register allocator, `opt.asm` optimizer) → `codegen/` (ELF emission) → `main/` (entry, plus `ir_dump.asm` debug hook). `include/rex_defs.inc` / `include/rex_ir.inc` hold all shared constants (token/type IDs, IR opcodes, record layout, limits) — every module depends on them.

## CRITICAL gotchas
- **Runtime blob offsets are baked into `codegen.asm`.** Any edit to `runtime/rt_*.asm` shifts every symbol in that blob; `codegen.asm` has ~99 hardcoded `mov edi,[rt_X_off]; add edi,0xNNN` dispatch constants that MUST be re-extracted (nasm `-f bin -l` listing → symbol offsets → rewrite the constants) or calls land mid-function and segfault. Extract scripts lived at `/tmp/opencode/extract_rt_off.py` / `extract_offsets.py` (ephemeral — the listing-grep method is the procedure). `rt_file.asm` symbol list is in `MEMORY.md`.
- Codegen→blob call ABI: `mov edi,[rt_X_off]; add edi,0x...; call edi`; caller preserves r8-r11 around the call. `rt_conv` returns a fresh 96-byte brk heap string per conversion and **clobbers rdi** — callers must restore rdi from stack after the call.
- Emitted ELF has **no section headers** — `objdump` won't disassemble. Use `ndisasm -b 64 -o 0x400000 <bin>` (entry ~0x40015d); `gdb b *0x400xxx` works on raw addresses.
- Debug aid: `REX_IRDUMP=1 ./rexc ...` dumps IR to stderr (hooked in `main/`).
- `emit_ir` ABI (`irgen.asm`): rdi=opcode, rsi=type, rdx=dst, rcx=src1, r8=src2, r9=imm, r10=aux. IR record = 32B: op@0, type@1, dst@2, src1@4, src2@6, imm@8, aux@16, flags@24. Opcodes in `include/rex_ir.inc`.
- RA (`ra.asm`): 6 physical regs r8-r13; colours 0-3 (r8-r11) caller-saved, 4-5 (r12-r13) callee-saved.
- Hard limits: SYM_MAX=256, PROTO_MAX=256, IR_MAX_RECORDS=4096 (overflow = clean error), GRAPHCOL_VMAX=1024, label table 65536. Table overflow miscompiles silently — error out instead of patching with a guess.

## Rex source conventions (parser evolved mid-project)
- Statements are NEWLINE-terminated; **no semicolons**. Comments are `//`.
- Mutation needs a `:` sigil: `:s = s + 1`; the first assignment (`s = 0`) needs none.
- `if` is both a statement and an expression (`x = if a>0: 1 else: -1`). `else:`/`elif:` only work as chain continuations of an `if`, never standalone. `0..N` ranges are EXCLUSIVE.
- `file_exists` is a builtin, not a method. `seq[byte]` literals only work in declarations (`seq[byte] wb = [...]`), not in expressions.

## Memory & process
- Read `.opencode/skills/knowledge-base/SKILL.md` at session start and before compaction. Tiers: `MEMORY.md` (working memory, repo root), `.opencode/memory/session-log.md` (append-only log), `~/.agent/memory.json` (long-term). `.opencode/plugins/memory-checkpoint.ts` auto-injects these on compaction.
- Before fixing a bug, check `cleanups/AUDIT_REPORT.md` / `AUDIT_NOTES.md` and `.agents/memory/rex-bugs.md` — many "obvious" bugs are known and already fixed.
- `scratch/`, `cleanups/`, `TODO.md`, `docs/compose/plans/` are working notes, not build inputs. `imp/self_hosting.md` is stale (actual self-hosting is 0%). `a.out` / `rexc` are gitignored build artifacts.
