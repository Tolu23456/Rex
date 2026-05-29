// test_while_full_expr.rex — while with full expression conditions
int n
:n = 0

while n < 5:
    output n
    :n = n + 1

// While with != condition
int m
:m = 3
while m != 0:
    output m
    :m = m - 1
