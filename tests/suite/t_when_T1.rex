// T1 normal case: 3-case when with default
prot check(int n):
    when:
        n == 1: output 10
        n == 2: output 20
        else: output 30

@check(1)
@check(2)
@check(5)
