// T4 protocol with wrong arg count
prot add(int a, int b) -> int:
    return a + b

// output @add(1) // should be compile error
output @add(1, 2)
