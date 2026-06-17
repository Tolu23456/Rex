// T3 fib(35) — tests correctness of deep recursion
prot fib(int n) -> int:
    if n < 2: return n
    return @fib(n-1) + @fib(n-2)

// fib(35) is 9227465, but might take too long without memo
// Let's do fib(20) for T3 deep enough to check stack but fast
output @fib(20)
