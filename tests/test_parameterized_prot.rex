// test_parameterized_prot.rex — protocols with parameters
prot add(a, b):
    int result
    :result = a + b
    return result

prot double(x):
    return x + x

int sum
:sum = @add(3, 4)
output sum

int d
:d = @double(6)
output d

// Call with expression arguments
int base
:base = 10
int res
:res = @add(base, 5)
output res
