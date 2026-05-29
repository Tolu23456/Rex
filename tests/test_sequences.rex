// test_sequences.rex — dynamic sequence: declare, push, len, pop
seq nums

push nums 10
push nums 20
push nums 30

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
