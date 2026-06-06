// Edge case: stop in nested loops (issue #22)
// stop always breaks the innermost loop only.
// There is currently no syntax to break an outer loop from inside an inner one.
// This test documents the current behaviour and the limitation.

// stop breaks innermost — outer loop continues
for i in 0..4:
    for j in 0..4:
        if j == 2:
            stop        // breaks inner loop when j reaches 2
        output j        // expected per outer iter: 0 1  (j=0 and j=1 only)
    output i            // expected: 0 1 2 3  (outer loop runs fully)

// stop in while inside for — only breaks while
for i in 0..3:
    int x = 0
    while x < 10:
        x = x + 1
        if x == 3:
            stop        // breaks while, not the for
    output x            // expected: 3 3 3  (while stopped at 3 each time)

// LIMITATION: no way to stop outer loop from inner — the following pattern
// requires a flag variable as a workaround:
int done = 0
for i in 0..5:
    if done == 1:
        stop
    for j in 0..5:
        if i == 2 and j == 1:
            done = 1
            stop        // breaks inner
    // outer loop checks done flag at top of next iteration
output done             // expected: 1
output i                // expected: 3  (outer ran one extra iteration after flag set)
