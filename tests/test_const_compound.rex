// test_const_compound.rex
// Negative test: compound assignment to a const is also rejected.
const MAX = 5
:MAX += 1
output(MAX)
