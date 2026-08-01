// reusing a loop variable name in a second loop reuses the existing symbol
int a = 0
for i in 0..4:
    :a = a + i
output(a)
output(i)
for i in 0..4:
    :a = a + i
output(a)
output(i)
// reusing a name previously declared as a plain int
int j = 0
int b = 0
for j in 1..5:
    :b = b + j
output(b)
output(j)
