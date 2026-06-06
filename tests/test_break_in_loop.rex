// test_break_in_loop.rex — stop (break) inside for and while loops
for i in 0..10:
    if i == 3:
        stop
    output i

output 99

int j
:j = 0
while j < 10:
    if j == 4:
        stop
    output j
    :j = j + 1

output 88
