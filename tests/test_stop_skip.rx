// Regression: stop N / skip N depth semantics
// skip 2: continue the outer loop (inner b==2 skipped entirely)
for a in 0..3:
    for b in 0..3:
        if b == 2:
            skip 2
        output("s2", a, b)
output("done")

// stop 2: exit the outer loop
for a in 0..3:
    for b in 0..3:
        if b == 2:
            stop 2
        output("p2", a, b)
output("done")
