---
name: rex-bug-scan
description: Systematically scan the Rex compiler codebase for bugs, fix them, rebuild, and test until clean. Use before commits or when investigating regressions.
---

# Rex Bug Scan & Fix

Systematically scan the Rex x86-64 NASM compiler for bugs, fix them, and verify with a clean build+test cycle.

## Procedure

1. **Build first** — `make clean && make 2>&1` in `/home/black_king/Rex`. If the build fails, fix build errors before continuing.

2. **Run full test suite** — `make test 2>&1`. Record all failures (test name + error output).

3. **Scan for common bug patterns** (grep the assembly source):
   - **Register clobbers**: functions that use callee-saved regs (rbx, rbp, r12-r15) without push/pop
   - **Stack imbalance**: mismatched push/pop, missing `add rsp, N` after stack allocation
   - **Uninitialized variables**: BSS variables read before first write
   - **Label scope violations**: code inserted between a function's `.done: ret` and its internal local labels
   - **Dead code after ret**: unreachable instructions after `ret`
   - **Missing `rax` preservation**: emit functions that clobber rax without saving across calls
   - **WRAP_PASS stubs that should emit real IR**: check `ir_codegen_wrap.asm` for stubs that now have IR opcodes
   - **Duplicate label definitions**: NASM "label inconsistently redefined" errors

4. **Scan for stubs and incomplete implementations**:
   - `grep -rn "WRAP_PASS\|IR_NOP\|stub\|TODO\|FIXME\|HACK" --include="*.asm"` in source dirs
   - Check `ir_emit_x86.asm` for opcodes that jump to `.op_stub` or return 0 from `est_x86_size`

5. **For each bug found**:
   - Read the surrounding context (at least 50 lines around the issue)
   - Understand the calling convention and register state at that point
   - Apply the minimal fix
   - Verify the fix doesn't break adjacent code

6. **After all fixes** — rebuild (`make clean && make`) and re-run tests (`make test`).

7. **Repeat** steps 3-6 until all tests pass and no bug patterns remain.

## Key Files

- `lexer/lexer.asm` — tokenizer
- `parser/parser.asm` — parser + semantic analysis
- `codegen/codegen.asm` — old codegen (being replaced by IR)
- `irgen/ir_emit_x86.asm` — IR → x86 emission
- `irgen/ir_codegen_wrap.asm` — parser → IR wrapper layer
- `irgen/ir_passes.asm` — optimization passes
- `runtime/runtime.asm` — runtime blobs
- `rex_defs.inc`, `rex_ir.inc` — constants and IR definitions

## Known Gotchas

- `advance` is a MACRO (`%macro advance 0` → `call lex_next`), not a function. Never write `call advance`.
- `advance` clobbers all caller-saved registers (rax, rcx, rdx, r8-r11). Reload from memory after.
- NASM local label scope: never insert code between a function's `.done: ret` and its internal local labels.
- `ir_emit_record` clobbers rax, rcx, r8. Push/pop all three plus rdi in EMIT_IR macro.
- `est_x86_size` returns 0 for unhandled opcodes — this corrupts label offsets. All opcodes need size estimates.
- r14/r15 are reserved from the register allocator (r14 = type propagation, r15 = loop pin).

## Stop Condition

All tests pass (`make test` shows 0 failures) AND no bug patterns found in scan.
