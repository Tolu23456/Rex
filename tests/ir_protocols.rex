prot add(int a, int b):
    return a + b

prot double(int n):
    return n * 2

prot fib(int n):
    if n <= 1:
        return n
    return @fib(n - 1) + @fib(n - 2)

output @add(3, 4)
output @double(5)
output @fib(10)
