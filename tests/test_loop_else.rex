// test_loop_else.rex
// Loop `else:` clause (design §8.6): runs on natural exit, skipped on `stop`.

for i in 0..3:
    output(i)
else:
    output("natural")

for i in 0..3:
    stop
else:
    output("stopped")

int j = 0
while j < 3:
    :j = j + 1
else:
    output("while-natural")

int k = 0
while k < 3:
    stop
else:
    output("while-stopped")

seq[int] nums = [1, 2, 3]
each x in nums:
    output(x)
else:
    output("each-natural")

repeat 2:
    output("r")
else:
    output("repeat-natural")

repeat 2:
    stop
else:
    output("repeat-stopped")

for i in 0..3:
    if i == 1:
        skip
    output(i)
else:
    output("skip-done")

for i in 0..2:
    for j in 0..2:
        output("ij")
    else:
        output("inner-else")
else:
    output("outer-else")
