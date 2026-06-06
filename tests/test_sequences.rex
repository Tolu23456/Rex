// test_sequences.rex — dynamic sequence: declare, push, len, pop
// Tests both push syntaxes: old-style `push seq val` and new method-call `seq.push(val)`
seq nums

// Old-style push syntax (still supported)
push nums 10
push nums 20

// New method-call push syntax
nums.push(30)

// Output the length
int n
:n = len nums
output n

// Pop values (LIFO)
int v1
:v1 = pop nums
output v1

int v2
:v2 = pop nums
output v2

// Length after pops
int n2
:n2 = len nums
output n2
