// Regression: depth-1 skip/stop inside a nested loop
// skip 1: continue the inner loop (b==2 iteration skipped)
for a in 0..2:
    for b in 0..3:
        if b == 2:
            skip 1
        output("k1", a, b)
output("done")

// stop 1: exit only the inner loop
for a in 0..3:
    for b in 0..3:
        if b == 1:
            stop 1
        output("t1", a, b)
output("done")

// stop 3 from the innermost of three loops
for a in 0..3:
    for b in 0..3:
        for c in 0..3:
            if c == 1:
                stop 3
            output(a, b, c)
output("done")
