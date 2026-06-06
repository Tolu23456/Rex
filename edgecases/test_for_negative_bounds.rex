// Edge case: negative for-loop bounds (issue #20 — fixed via parse_expr)
// Parser requires ':' on the loop variable (mutation sigil).
// 'step' comes AFTER the range: for :i in start..end step N

// Negative start
for :i in -5..5:
    output i    // expected: -5 -4 -3 -2 -1 0 1 2 3 4

// Negative both bounds
for :j in -3..-1:
    output j    // expected: -3 -2

// Expression bounds with step
int lo = -10
int hi = 10
for :k in lo..hi step 5:
    output k    // expected: -10 -5 0 5

// Empty range (start >= end) — should print nothing
for :m in 5..3:
    output m
