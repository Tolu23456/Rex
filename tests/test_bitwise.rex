// test_bitwise.rex — bitwise operators: &, |, ^, ~, <<, >>
int a
:a = 0b1100
int b
:b = 0b1010

// These test the bitwise ops work syntactically
int band
:band = a & b
output band

int bor
:bor = a | b
output bor

int bxor
:bxor = a ^ b
output bxor

int shl
:shl = a << 1
output shl

int shr
:shr = a >> 1
output shr
