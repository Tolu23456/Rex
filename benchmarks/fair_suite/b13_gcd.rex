// B13: GCD Euclidean Algorithm
// For each k in 0..1000000 compute two values from LCG seeds,
// then find their GCD using Euclidean algorithm (while + modulo).
// Tests: while loop, modulo operator, integer register usage.
// Rex outputs: checksum on line 1, internal elapsed ms on line 2.

int :t0 = clock()
int :sum = 0
int :a = 0
int :b = 0
int :r = 0
for :k in 0..1000000:
    :a = k * 1234567 + 7654321
    :b = k * 891011 + 1213141
    while b != 0:
        :r = a % b
        :a = b
        :b = r
    :sum = sum + a
int :t1 = clock()
output sum
output t1 - t0
