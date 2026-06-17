// T3 when inside loop 1000 iterations
int sum = 0
for i in 0..1000:
    when:
        i % 2 == 0: :sum = sum + 1
        else: :sum = sum + 2
output sum
