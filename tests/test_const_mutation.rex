// test_const_mutation.rex
// Negative test: mutating a const is rejected at compile time (design §4.17).
const MAX = 5
:MAX = 10
output(MAX)
