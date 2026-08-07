// Regression: pass_loop_promote + register allocation
// Nested constant-bound loops (outer loop promotion with an inner loop)
for a in 0..3:
    for b in 0..3:
        output(a, b)
output("nl")

// In-loop constant mutation on a promoted loop
c = 0
for i in 0..3:
    :c = 7
    output(c)
output("cm")
