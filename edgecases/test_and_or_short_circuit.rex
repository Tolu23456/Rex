// Edge case: and / or short-circuit behaviour (issue #33)
// After fix, and/or are short-circuit:
//   - `false and expr` must NOT evaluate expr
//   - `true or expr` must NOT evaluate expr
// Side-effect detection: use a protocol call that increments a counter.
// If short-circuit works, the counter stays at 0.

int counter = 0

protocol side_effect():
    counter = counter + 1
    return 1

// false and side_effect() — side_effect should NOT run
int r1 = false and @side_effect()
output counter      // expected: 0  (short-circuit: RHS not evaluated)

// true or side_effect() — side_effect should NOT run
int r2 = true or @side_effect()
output counter      // expected: 0  (short-circuit: RHS not evaluated)

// true and side_effect() — side_effect MUST run
int r3 = true and @side_effect()
output counter      // expected: 1  (RHS evaluated)

// false or side_effect() — side_effect MUST run
int r4 = false or @side_effect()
output counter      // expected: 2  (RHS evaluated)

// Chained: false and X and Y — only LHS evaluated, X and Y skipped
int r5 = false and @side_effect() and @side_effect()
output counter      // expected: 2  (no change)

// Nested in if condition
if false and @side_effect():
    output 111      // should NOT print
output counter      // expected: 2
