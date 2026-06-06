// B14: While-loop Integer Log2 Sum
// For each k in 1..10000000 repeatedly halve k until it reaches 1,
// counting total halvings across all 10M values.
// Tests: while loop, integer division, mixed for+while workload.
// Rex outputs: total step count on line 1, internal elapsed ms on line 2.

int :t0 = clock()
int :total = 0
int :n = 0
for :k in 1..10000001:
    :n = k
    while n > 1:
        :n = n / 2
        :total = total + 1
int :t1 = clock()
output total
output t1 - t0
