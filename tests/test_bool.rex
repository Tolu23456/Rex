// test_bool.rex — bool type: literals, output, and comparison
bool flag
:flag = true
output flag

bool b2
:b2 = false
output b2

// Bool from comparison
int x
:x = 5
if x == 5:
    bool result
    :result = true
    output result
