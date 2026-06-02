// Edge case: abs() correctness (issue #29 — CMOVNS vs CMOVS)
// Before fix: abs() was always wrong except for abs(0).
// After fix: CMOVS (0x48) is emitted; these should all print correct values.

int a = 5
int b = -3
int c = 0
int d = -100
int e = 2147483647

output abs(a)       // expected: 5
output abs(b)       // expected: 3
output abs(c)       // expected: 0
output abs(d)       // expected: 100
output abs(e)       // expected: 2147483647

// abs of expression
int x = 10
int y = 15
output abs(x - y)   // expected: 5
output abs(y - x)   // expected: 5
