// Edge case: stop in nested loops (issue #22)
// stop always breaks the innermost loop only.
// There is currently no syntax to break an outer loop from inside an inner one.
// This test documents the current behaviour and the limitation.

// stop breaks innermost — outer loop continues
for i_1 in 0..4:
    for j_1 in 0..4:
        if j_1 == 2:
            stop
        output j_1
    output i_1

// expect: 0
// expect: 1
// expect: 0
// expect: 0
// expect: 1
// expect: 1
// expect: 0
// expect: 1
// expect: 2
// expect: 0
// expect: 1
// expect: 3

// stop in while — breaks only the while loop
int x = 0
while x < 5:
    x = x + 1
    if x == 3:
        stop
    output x

// expect: 1
// expect: 2
