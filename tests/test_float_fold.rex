// test_float_fold.rex
// Tests float constant folding (Bug 7 fix).
// All arithmetic involves constant float operands so the optimizer
// folds them at compile time into LOAD_FIMM records.
//
// Expected output:
//   4.5
//   6.0
//   3.0
//   2.0

float x = 3.0
float y = 1.5

float add_result = x + y
output(add_result)

float two = 2.0
float mul_result = x * two
output(mul_result)

float div_result = mul_result / two
output(div_result)

float one = 1.0
float sub_result = x - one
output(sub_result)
