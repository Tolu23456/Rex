// Mixed arithmetic promotion (design.md §5.2: "float dominates in mixed
// arithmetic: int + float → float"). The int/byte operand is promoted to float.

output(1 + 2.5)
output(2.5 + 1)
output(1 - 2.5)
output(2.5 - 1)
output(1 * 2.5)
output(2.5 * 2)
output(7.0 / 2)
output(10 / 4.0)
output(1.5 * 2 + 1)
output(2 + 1.5 * 2)

int n = 3
output(n + 0.5)
output(n * 1.5)
output(1.5 * n)
output(n / 2.0)

byte b = 7
output(b + 0.5)
output(b * 1.0)

// Compound assignment promotion: float var op= int/byte RHS
float f = 1.0
:f += 1
output(f)
:f *= 3
output(f)
:f -= 1
output(f)
:f /= 2
output(f)
f += 2.5
output(f)
