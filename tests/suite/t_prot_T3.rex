// T3 protocol called 10000 times in loop
prot inc(int n) -> int:
    return n + 1

int x = 0
for i in 0..10000:
    :x = @inc(x)
output x
