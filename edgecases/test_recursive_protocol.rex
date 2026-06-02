// Edge case: recursive protocol calls (issue #18)
// KNOWN BUG: recursive protocols produce wrong results because parameters are
// stored in global var_table slots.  A recursive call overwrites the caller's
// parameter values before the caller resumes.
//
// EXPECTED (correct): fib(10) = 55
// ACTUAL (buggy):     fib(10) = wrong value due to slot overwrite
//
// This test documents the current broken behaviour.  Once per-call stack
// frames are implemented (issue #18), fib(10) must print 55.

protocol fib(n):
    if n <= 1:
        return n
    int a = @fib(n - 1)
    int b = @fib(n - 2)
    return a + b

output @fib(0)      // expected: 0
output @fib(1)      // expected: 1
output @fib(5)      // expected: 5   (currently wrong due to issue #18)
output @fib(10)     // expected: 55  (currently wrong due to issue #18)
