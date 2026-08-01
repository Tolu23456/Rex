// inclusive ranges (..=), static steps, and post-loop values
int total = 0
for i in 0..=4:
    :total = total + i
output(total)
int sum = 0
for j in 0..10 step 3:
    :sum = sum + j
output(sum)
int sum2 = 0
for k in 0..=10 step 3:
    :sum2 = sum2 + k
output(sum2)
int last = 0
for m in 0..=4:
    :last = m
output(last)
int last2 = 0
for n in 0..10 step 3:
    :last2 = n
output(last2)
int b = 0
for p in 0..=100:
    :b = b + p
output(b)
int c = 0
for q in 0..100 step 3:
    :c = c + q
output(c)
