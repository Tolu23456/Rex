// B2: Multiply-only fold, 64-bit constant (PCG-XSH-RR multiplier)
// 1 billion iterations of x = x * 6364136223846793005
// GCC -O3 cannot eliminate this loop (non-power-of-2, needs modular exp).
// Rex O-Affine-Mul-64 computes 6364136223846793005^1000000000 mod 2^64 at
// compile time via binary ladder — emits 2 runtime instructions (movabs + imul).

int :t0 = clock()
int :x = 1
for i in 0..1000000000:
    :x = x * 6364136223846793005
int :t1 = clock()
output x
output t1 - t0
