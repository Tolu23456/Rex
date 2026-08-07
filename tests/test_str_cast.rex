// test_str_cast.rex
// str() casts for every value type (§6)
//
// Expected output:
//   42
//   -12345
//   0.5
//   3.1400000000000001
//   true
//   false
//   A
//   hello
//   R
//   R
//   true

output(str(42))
output(str(-12345))
output(str(0.5))
output(str(3.14))
output(str(true))
output(str(false))
output(str('A'))
output(str("hello"))

// char -> str
char c = 'R'
output(str(c))

// byte -> str (raw single byte)
byte by = 'R'
output(str(by))

// bool -> str
bool b = true
output(str(b))

// str -> int / str -> float round trips
output(int("42"))
output(int("-17"))
output(int("0x10"))
output(int(" 12"))
output(float("3.5"))
output(float("-2.25"))
output(int(str(100)))
output(float(str(2.5)))
