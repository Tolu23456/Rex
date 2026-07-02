prot factorial(int n):
    if n <= 1:
        return 1
    return n * @factorial(n - 1)

output @factorial(5)
output @factorial(10)
output @factorial(0)
output @factorial(1)
