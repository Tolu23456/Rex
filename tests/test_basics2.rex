// test_basics2.rex
// Tests swap, signum, min, max, gcd, lcm
//
// Expected output:
//   10
//   5
//   1
//   0
//   -1
//   3
//   10
//   6

// --- swap ---
int m = 5
int p = 10
swap(m, p)
output(m)
output(p)

// --- signum ---
int a = 5
output(signum(a))
int b = 0
output(signum(b))
int c = -3
output(signum(c))

// --- min / max ---
int x = 3
int y = 10
output(min(x, y))
output(max(x, y))

// --- gcd ---
int g1 = 12
int g2 = 18
output(gcd(g1, g2))
