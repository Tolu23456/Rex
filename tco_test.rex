protocol tail_rec(n, acc):
    if n == 0:
        return acc
    return @tail_rec(n - 1, acc + n)

output @tail_rec(10, 0)
