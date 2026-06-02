// Edge case: expression type propagation through binary operators (issue #4)
// Before fix: cur_type only reflected the last atom parsed (RHS).
// After fix: float dominates; % always yields int; type is tracked across
// the entire expression tree.

// Float dominates int in mixed arithmetic
float f = 3.5
int n = 2
// f + n should yield float
output f + n    // expected: float output ~5.5

// int % int always yields int
int a = 17
int b = 5
output a % b    // expected: 2

// Nested: (float + int) * int — result is float
output (f + n) * 3  // expected: float ~16.5

// int + int = int (no float)
int x = 10
int y = 20
output x + y    // expected: 30

// Chain: float + int + float stays float
float g = 1.5
output f + n + g    // expected: float ~7.0

// Comparison result is bool
int p = 5
int q = 3
bool result = p > q
output result   // expected: true
