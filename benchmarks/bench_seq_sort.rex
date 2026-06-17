// bench_seq_sort: Sort 1M integers
// Target: Rex >= 105% of C qsort
// Fill seq[int] with 1M pseudorandom ints, rt_seq_sort

seq[int] :data
// Simple LCG for deterministic "random" numbers
int :seed = 12345
for :i in 0..1000000:
    :seed = (seed * 1103515245 + 12345) % 2147483648
    push data seed

// rt_seq_sort is a runtime blob, but in Rex we might just have a protocol
// The task says "rt_seq_sort", we'll assume it's available as a method or protocol.
// Based on session plan, it's a runtime blob.
sort data
output data.len()
