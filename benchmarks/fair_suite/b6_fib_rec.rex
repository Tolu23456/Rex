// B6: Recursive Fibonacci
// Compute fib(42) using naive double recursion (~267 million calls).
// Identical algorithm to b6_fib_rec.c.

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
