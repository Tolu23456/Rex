// runtime step variable (falls back to loop, not folded)
int s = 3
int sum = 0
for i in 0..10 step s:
    :sum = sum + i
output(sum)
output(i)
int cnt = 0
for j in 0..10 step 2:
    :cnt = cnt + 1
output(cnt)
output(j)
