int :x = 42
int :y = 0
output(x)
output(y)

for :i in 0..10 step 2:
    output(i)

prot greet(None) -> None:
    output(99)

@greet()
