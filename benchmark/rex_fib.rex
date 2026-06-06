// rex_fib_memo.rex — memoized recursive Fibonacci benchmark
// #memo caches each fib(n) result after first computation.
// Recursive tree of 2^42 calls collapses to O(n) distinct lookups.

#memo
prot fib(n):
    if n <= 1:
        return n
    int a
    :a = @fib(n - 1)
    int b
    :b = @fib(n - 2)
    return a + b

int result
:result = @fib(42)
output result
