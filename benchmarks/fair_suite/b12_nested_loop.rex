// B12: Nested Loop Accumulation
// Accumulate i*j over a 3000x3000 grid (9 million iterations).
// Tests nested loop register allocation and memory traffic.
// Rex outputs: result on line 1, internal elapsed ms on line 2.

int :t0 = clock()
int :acc = 0
for i in 0..3000:
    for j in 0..3000:
        :acc = acc + i * j
int :t1 = clock()
output acc
output t1 - t0
