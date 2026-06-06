// Edge case: skip (continue) semantics and depth argument (issue #31)
// skip = continue innermost loop
// skip N = continue the Nth loop from inside (1=innermost, 2=next outer, etc.)

// Basic skip: print only even numbers 0..8
for i in 0..10:
    int r = i % 2
    if r == 1:
        skip
    output i        // expected: 0 2 4 6 8

// skip in while loop
int x = 0
while x < 10:
    x = x + 1
    int m = x % 3
    if m == 0:
        skip
    output x        // expected: 1 2 4 5 7 8 10

// Nested loops — skip 2 skips the outer loop iteration
// The inner variable j goes 0..3; when j==1 skip outer (i)
// Each outer iteration i prints j=0 then skips outer on j=1
for i in 0..4:
    for j in 0..4:
        if j == 1:
            skip 2  // continue the outer for loop
        output j    // expected per outer iter: 0  (then outer continues)
    output i        // should NOT be reached because skip 2 fires at j==1
