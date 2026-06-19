protocol f(n):
    if n == 0:
        return 0
    return @g(n - 1)

protocol g(n):
    return @f(n)

output @f(10)
