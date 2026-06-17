// T5 composition: mutual protocols (A calls B calls C)
prot A(int n):
    output 100 + n
    if n > 0:
        @B(n - 1)

prot B(int n):
    output 200 + n
    if n > 0:
        @C(n - 1)

prot C(int n):
    output 300 + n
    if n > 0:
        @A(n - 1)

@A(3)
