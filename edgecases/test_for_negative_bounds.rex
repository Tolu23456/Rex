// Edge case: negative for-loop bounds (issue #20 — now fixed via parse_expr)
// Before fix: tok_int was uint64; a unary minus in range position was discarded,
// so for :i in -5..5 started at 5, not -5.
// After fix: parse_expr handles TOK_MINUS as unary negation.

// Negative start
for :i in -5..5:
    output i    // expected: -5 -4 -3 -2 -1 0 1 2 3 4

// Negative both bounds
for :j in -3..-1:
    output j    // expected: -3 -2

// Expression bounds
int lo = -10
int hi = 10
for :k step 5 in lo..hi:
    output k    // expected: -10 -5 0 5

// Negative step (counting down) — not natively supported by syntax but
// verify that negative bounds with positive step terminates immediately
// if start >= end
for :m in 5..3:
    output m    // expected: nothing (empty range, 5 >= 3)
