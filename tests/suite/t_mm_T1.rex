// T1 normal case: use mm arena — allocate seq, verify
use mm arena:
    seq s
    s.push(42)
    output s[0]
output 99
