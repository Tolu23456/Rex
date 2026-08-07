// ++/-- prefix and postfix statements (grammar.md §13, design.md §5.7)
int x = 5
++x
output(x)
--x
output(x)
x++
output(x)
x--
output(x)

// Works on immutable vars without a ':' sigil (self-evident mutation)
int n = 10
n++
output(n)
++n
output(n)

// Float increments must use a float 1.0 (not int 1)
float f = 1.5
++f
output(f)
--f
output(f)

byte b = 9
++b
output(b)

// Inside blocks and loops
int y = 0
for i in 0..3:
    ++y
output(y)
if true:
    y++
output(y)
