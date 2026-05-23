; stdlib.rex
; Rex Standard Library (Self-hosted subset)

prot abs(int n) -> int:
    if :n < 0:
        return :n * -1
    return :n

prot max(int a, int b) -> int:
    if :a > :b:
        return :a
    return :b

prot min(int a, int b) -> int:
    if :a < :b:
        return :a
    return :b
