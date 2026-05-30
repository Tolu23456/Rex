// rex_fib.rex — recursive Fibonacci benchmark
// Rex compiles each prot to a direct CALL/RET pair with no prologue overhead
// beyond the SysV ABI register stores emitted for the two parameters.

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
