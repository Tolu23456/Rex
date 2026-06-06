// B10: Multiply-only constant folding — 1 billion iterations of x = x*3
// O-Affine-Mul: binary ladder computes 3^N mod 2^64 at compile time;
// emits exactly 2 runtime instructions. GCC -O3 runs all 1B iterations.
// Rex outputs: result on line 1, internal elapsed ms on line 2.

int :t0 = clock()
int :x = 1
for i in 0..1000000000:
    :x = x * 3
int :t1 = clock()
output x
output t1 - t0
