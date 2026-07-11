// test_constant_folding.rex
// All arithmetic here involves only literals so constant folding should
// collapse everything into LOAD_IMM records.
//
// Expected output:
//   42
//   100
//   7

// 30 + 12 = 42
int a = 30 + 12
output(a)

// 10 * 10 = 100
int b = 10 * 10
output(b)

// 21 / 3 = 7
int c = 21 / 3
output(c)
