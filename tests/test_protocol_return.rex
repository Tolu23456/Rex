// test_protocol_return.rex — protocol return values captured into variables
prot get_answer():
    return 42

prot compute(n):
    return n * n

int answer
:answer = @get_answer()
output answer

int sq
:sq = @compute(7)
output sq

// Direct use in expression
int x
:x = @get_answer() + 8
output x
