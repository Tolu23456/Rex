// T1 normal case: protocol with 1-6 params, return value
prot add(int a, int b) -> int:
    return a + b

prot many(int a, int b, int c, int d, int e, int f) -> int:
    return a + b + c + d + e + f

output @add(5, 7)
output @many(1, 2, 3, 4, 5, 6)
