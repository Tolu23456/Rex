// T5 composition: fibonacci + accumulator + output formatted
prot fib(int n) -> int:
    if n < 2:
        return n
    return @fib(n - 1) + @fib(n - 2)

int sum = 0
for i in 0..11:
    int f = @fib(i)
    output f
    :sum = sum + f

output sum
