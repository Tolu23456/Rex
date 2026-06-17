// bench_arith: Integer arithmetic loop
// Target: Rex >= 98% of raw NASM speed
// 2 billion iterations of a 64-bit LCG-like loop

int :sum = 0
for :i in 0..2000000000:
    :sum = sum + i * 3 - i / 7 + i % 13
output sum
