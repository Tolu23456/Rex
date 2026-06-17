// T1 normal case: memoized fib(30), verify result
#memo
prot fib(int n) -> int:
    if n < 2: return n
    return @fib(n-1) + @fib(n-2)

output @fib(30)
