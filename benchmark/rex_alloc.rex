// rex_alloc.rex — seq push throughput benchmark
// Pushes 500,000 integers into a single growing sequence.
// The seq grows automatically (inline bump realloc) as needed.
// Measures seq-push throughput: bounds check, store value, inc len.

seq data
for :i in 0..500000:
    push data i
output 1
