; test_full.rex
int age
:age = 56

prot greet_user(None) -> str:
    return :"Hello, User"

for :i in 0..10:
    output i

if :age >= 10:
    output age

use mm 2 gc 1:
    @data = @[10, 20, 30]
    output data

dict d = {"name": "Rex"}
complex c = 12j
unknown_val = unknown
if :unknown_val:
    output :"Random choice"
