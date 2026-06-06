// B10: Multiply-only constant folding — 1 billion iterations of x = x*3
// Purpose: demonstrate Rex O-Affine-Mul: binary ladder computes 3^N mod 2^64
// at compile time and emits exactly 2 runtime instructions.
// GCC -O3 cannot fold modular exponentiation of a non-power-of-2 base,
// so it must execute all 1,000,000,000 iterations at runtime.

int :x = 1
for i in 0..1000000000:
    :x = x * 3
output x
