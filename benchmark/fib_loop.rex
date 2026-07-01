prot fib(int n):
    if n <= 1:
        return n
    return @fib(n - 1) + @fib(n - 2)

int i = 0
int sum = 0
while i < 10000:
    :sum = sum + @fib(20)
    :i = i + 1
output sum
