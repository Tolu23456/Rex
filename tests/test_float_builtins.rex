// test_float_builtins.rex
// Free float functions (design §4.6/§13.2): ceil, floor, round, trunc,
// fract, sqrt, abs, pow. `ceil` was missing from the free-function dispatch;
// `fract` used to return the trunc result.

output(ceil(1.5))
output(ceil(-1.5))
output(floor(2.7))
output(round(2.6))
output(round(2.4))
output(trunc(-3.7))
output(fract(3.7))
output(sqrt(9.0))
output(abs(-3.5))
output(pow(2, 3))
output(pow(2.0, 3.0))
float a = 3.7
output(fract(a))
output(sqrt(a))
