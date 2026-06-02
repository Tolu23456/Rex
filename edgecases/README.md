# Rex V5.0 — Edge Case Tests

Each file in this directory targets one or more known issues from `docs/issues.md`.
Run a test by compiling the `.rex` file with `rexc` and executing the output.

| File | Issues | Status |
|------|--------|--------|
| `test_abs.rex` | #29 — abs() CMOVS fix | ✅ Fixed — should pass |
| `test_for_step.rex` | #30 — for step N | ✅ Fixed — should pass |
| `test_skip.rex` | #31 — skip/continue depth | ✅ Fixed — should pass |
| `test_nested_when.rex` | #32 — nested when stack | ✅ Fixed — should pass |
| `test_seq_push_overflow.rex` | #19 — seq push overflow | ✅ Fixed — capacity doubles on overflow via inline grow + rt_alc |
| `test_and_or_short_circuit.rex` | #33 — short-circuit and/or | ✅ Fixed — should pass |
| `test_string_literal_length.rex` | #34 — string truncation | ✅ Fixed — 64+ char strings truncated, no corruption |
| `test_err_types.rex` | #25 — err with non-string | ✅ Fixed — int/bool args print cleanly, no segfault |
| `test_recursive_protocol.rex` | #18 — recursive protocols | ❌ Known bug — prints wrong values |
| `test_for_negative_bounds.rex` | #20 — negative for bounds | ✅ Fixed — should pass |
| `test_var_scope.rex` | #26, #37 — slot reclamation | ✅ Fixed — should pass |
| `test_stop_multiloop.rex` | #22 — stop multi-level | ⚠️ Limitation — stop is innermost only; workaround shown |
| `test_type_propagation.rex` | #4 — type propagation | ✅ Fixed — should pass |

## Running a test

```bash
./rexc edgecases/test_abs.rex -o /tmp/test_abs && /tmp/test_abs
```

## Adding new edge cases

1. Name the file `test_<feature>.rex`.
2. Add a header comment citing the issue number and describing expected vs actual.
3. Use `// expected: X` comments on output lines so results are self-documenting.
4. Update this README with the new row.
