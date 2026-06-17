// T3 large: Kahan summation of 1M floats
// Simplified summation of 1.0 1M times
float sum = 0.0
for i in 0..1000000:
    :sum = sum + 1.0
output sum
