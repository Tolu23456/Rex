// T1 normal case: fib(10), fact(10)
prot fib(int n) -> int:
    if n < 2: return n
    return @fib(n-1) + @fib(n-2)

prot fact(int n) -> int:
    if n < 2: return 1
    return n * @fact(n-1)

output @fib(10)
output @fact(5)
