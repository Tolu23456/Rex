// B7: Iterative Fibonacci
// Compute fib(80) iteratively, repeated 10 million times.
// Tests pure loop + arithmetic throughput with mutable locals.

int :a = 0
int :b = 1
int :c = 0
for :rep in 0..10000000:
    :a = 0
    :b = 1
    for :j in 0..80:
        :c = a + b
        :a = b
        :b = c
output b
