// B11: Add-only constant folding — 1 billion iterations of x = x+7
// Purpose: demonstrate Rex O-Affine-Add: computes B*N = 7,000,000,000 at compile
// time and emits a single `mov rax, 7000000000 / add r14, rax` (13 bytes).
// GCC -O3 also folds this trivially (constant stride * constant count).
// Both produce the same binary-level result; Rex matches GCC's capability.
// Note: C internal time ≈ 0 ms (folded). Rex wall ≈ 3 ms (ELF startup only).

int :x = 1
for i in 0..1000000000:
    :x = x + 7
output x
