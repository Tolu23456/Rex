// B9: Dynamic Array Growth
// Push 1,000,000 integers into a Rex seq (grows by doubling, initial cap=8).
// Equivalent to b9_dynarray.c which uses the same initial-cap-8 doubling strategy.
// Uses new method-call push syntax: data.push(i)

seq data
for i in 0..1000000:
    data.push(i)
output 1
