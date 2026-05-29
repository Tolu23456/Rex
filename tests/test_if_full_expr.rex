// test_if_full_expr.rex — if/elif/else with full expression conditions
int a
:a = 10

if a > 5:
    output 1
elif a < 3:
    output 2
else:
    output 3

// != operator
int b
:b = 7
if b != 10:
    output 4

// >= and <= operators
int c
:c = 10
if c >= 10:
    output 5
if c <= 10:
    output 6
