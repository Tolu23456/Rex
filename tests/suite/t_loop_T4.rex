// T4 stop in nested loop
for i in 0..10:
    for j in 0..10:
        if i == 2 and j == 2:
            stop
        output i * 10 + j
    if i == 2:
        stop
