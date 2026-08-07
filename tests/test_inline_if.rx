int a = 5
int x = if a > 0: 1 else: -1
output(x)
str label = if a >= 90: "A" else: "B"
output(label)
output(if a == 5: "five" else: "not five")

// else-path string branch (parser regression: used to copy the THEN
// vreg on the else path, only correct by accidental colour coalescing)
str b2 = if a > 50: "big" else: "small"
output(b2)
float f1 = if a > 5: 1.5 else: 2.5
output(f1)
float f2 = if a > 50: 1.5 else: 2.5
output(f2)
