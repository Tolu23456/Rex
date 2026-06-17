// T4 stack overflow via infinite recursion
prot inf():
    @inf()

// @inf() // should cause stack overflow
output 1
