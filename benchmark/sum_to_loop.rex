prot fib(int n):
    if n <= 1:
        return n
    return @fib(n - 1) + @fib(n - 2)

prot sum_to(int n):
    int s = 0
    int i = 0
    while i < n:
        :s = s + i
        :i = i + 1
    return s

prot pow(int base, int exp):
    int result = 1
    int i = 0
    while i < exp:
        :result = result * base
        :i = i + 1
    return result

int x = 0
int i = 0
while i < 1000000:
    :x = @sum_to(1000)
    :i = i + 1
output x
