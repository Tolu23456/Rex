// multiple accumulators in one loop (sum fold)
int a = 0
int b = 0
for i in 0..10:
    :a = a + i
    :b = b + i
output(a)
output(b)
int t1 = 100
int t2 = 0
int t3 = 50
for j in 0..5:
    :t1 = t1 - j
    :t2 = t2 + j
    :t3 = t3 + j
output(t1)
output(t2)
output(t3)
int u = 0
for k in 0..4:
    :u = u + k
    :u = u + k
output(u)
int s1 = 0
int s2 = 0
for m in 0..100 step 3:
    :s1 = s1 + m
    :s2 = s2 + m
output(s1)
output(s2)
