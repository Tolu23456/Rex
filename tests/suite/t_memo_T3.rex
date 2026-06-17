// T3 memo with 1000 unique calls
#memo
prot square(int n) -> int:
    return n * n

for i in 0..1000:
    @square(i)

output @square(500)
