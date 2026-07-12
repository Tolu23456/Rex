---
description: Assess Rex compiler completion percentage against design.md. Reports per-section status and overall progress.
---

# Rex Completion Assessment

Analyze how much of the Rex compiler is implemented by comparing `design.md` specifications against actual assembly implementations.

## Instructions

1. Read `design.md` (or `docs/design.md`) to get the full feature specification with all sections.

2. For each major section in design.md, audit the assembly source to determine implementation status:
   - **Fully implemented**: Feature has parser handling, codegen emission, and passes tests
   - **Partially implemented**: Parser or codegen exists but incomplete or untested
   - **Stubbed**: Token/keyword defined but no real logic (e.g., WRAP_PASS, skeleton parser)
   - **Not started**: No code exists

3. Key files to audit:
   - `lexer/lexer.asm` — keyword tokens
   - `parser/parser.asm` — grammar rules and dispatch
   - `codegen/codegen.asm` or `irgen/ir_emit_x86.asm` — code emission
   - `tests/` — test coverage for features

4. Report format:

```
## Rex Implementation Status

| Section | Feature | Status | Notes |
|---------|---------|--------|-------|
| §3 | Variables | ✅ Complete | ... |
| §4.5 | Type methods | 🟡 Partial | ... |
| §15.4 | File I/O | ❌ Not started | ... |

**Overall: ~XX% complete**

### Breakdown by category:
- Compiler pipeline: XX%
- Language features: XX%
- Standard library: XX%
- Optimization: XX%
```

5. Cross-reference with MEMORY.md "Discovered durable knowledge" section for latest status notes.

## Output

A structured completion report with per-section percentages and an overall estimate.
