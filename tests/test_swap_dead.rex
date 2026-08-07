// Regression: DSE must not kill a store that feeds IR_SWAP_VARS
// (swap reads both memory operands; previously the dead-side store
//  was eliminated and swap exchanged with garbage)
int m = 5
int p = 10
swap(m, p)
output(m)     // p is only ever read by the swap itself

int a = 100
int b = 200
swap(a, b)
output(a)     // only first operand used after swap

int x = 7
int y = 9
swap(x, y)
output(y)     // only second operand used after swap

int i = 1
int j = 2
swap(i, j)
output(i)
output(j)     // both used after swap
