// B9: Dynamic Array Growth
// Push 1,000,000 integers into a Rex seq (grows by doubling, initial cap=8).
// Equivalent to b9_dynarray.c which uses the same initial-cap-8 doubling strategy.

seq data
for :i in 0..1000000:
    push data i
output 1
