// Test file for protocol definitions (design.md §7)
// Expected outputs shown as comments

// Simple protocol with two int params, one int return
prot add(int a, int b) -> int:
    return a + b

// Protocol returning a computed value
prot double_it(int n) -> int:
    result_v = n * 2
    return result_v

// Protocol with no return (void)
prot greet(str name):
    output(name)

// Call the protocols
output(@add(3, 4))          // 7
output(@double_it(21))      // 42
@greet("hello")             // hello

// Protocol call nested inside an expression argument
output(@add(@add(1, 2), @double_it(3)))   // 9

// Protocol used in a variable assignment
int r = @add(100, 200)
output(r)                   // 300

// Protocol call as output() argument directly
output(@add(10, 20))        // 30
