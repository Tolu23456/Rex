// test_switch.rex
// Tests the switch statement with literal patterns, ranges, and default.
int x = 1
switch x:
    -> 0:
        output("zero")
    -> 1, 2:
        output("one or two")
    -> 3..5:
        output("three to five")
    _:
        output("other")

:x = 4
switch x:
    -> 0:
        output("zero")
    -> 1, 2:
        output("one or two")
    -> 3..5:
        output("three to five")
    _:
        output("other")

:x = 9
switch x:
    -> 0:
        output("zero")
    -> 1, 2:
        output("one or two")
    -> 3..5:
        output("three to five")
    _:
        output("other")

// No default: unmatched values fall through
:x = 42
switch x:
    -> 0:
        output("zero")
    -> 1, 2:
        output("one or two")
output("done")
