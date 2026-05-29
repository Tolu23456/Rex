// test_type_propagation.rex — expression type propagates through binary ops
float a
:a = 1.5
float b
:b = 2.5

// Addition: result should be float-typed
float s
:s = a + b
output s

// Multiplication
float p
:p = a * b
output p

// Int arithmetic stays int
int x
:x = 3 + 4 * 2
output x

// Mixed: float wins
float m
:m = a + a
output m
