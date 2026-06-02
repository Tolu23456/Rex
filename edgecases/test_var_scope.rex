// Edge case: var_table slot reclamation after loops and protocols (issues #26, #37)
// Protocol-local variables and for-loop synthetic variables must be reclaimed.
// If slots leak, repeated calls exhaust VAR_MAX (256) and corrupt proto_table.

// Issue #37: for-loop synthetic _fe variable must be reclaimed after each loop
// Run 10 for-loops with the same variable name — should not exhaust var_table
for :i in 0..3:
    output i

for :i in 10..13:
    output i

for :i in 20..23:
    output i

for :i in 30..33:
    output i

for :i in 40..43:
    output i

// All 5 loops reuse the same i and i_fe slots (after fix)
output 100  // expected: 100 (still running, slots not exhausted)

// Issue #26: protocol locals must be reclaimed on each call
protocol count_up(start):
    int local_a = start + 1
    int local_b = start + 2
    return local_b

// Call 5 times — without fix, local_a and local_b accumulate 10 slots
output @count_up(0)     // expected: 2
output @count_up(10)    // expected: 12
output @count_up(20)    // expected: 22
output @count_up(30)    // expected: 32
output @count_up(40)    // expected: 42

output 200  // expected: 200 (var_table still has room)
