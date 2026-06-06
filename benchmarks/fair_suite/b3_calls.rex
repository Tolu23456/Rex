// B3: Function Call Overhead
// Call increment(x) 200 million times.
// Rex emits an actual CALL/RET pair with push/pop for each in-scope variable.

prot increment(x):
    return x + 1

int :t0 = clock()
int :n = 0
for i in 0..200000000:
    :n = @increment(n)
int :t1 = clock()
output n
output t1 - t0
