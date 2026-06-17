// T2 fib(0), fib(1), fact(0)
prot fib(int n) -> int:
    if n < 2: return n
    return @fib(n-1) + @fib(n-2)

prot fact(int n) -> int:
    if n < 1: return 1
    return n * @fact(n-1)

output @fib(0)
output @fib(1)
output @fact(0)
