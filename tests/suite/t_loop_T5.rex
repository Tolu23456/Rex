// T5 for + accumulate + dict update
dict d
seq s
for i in 0..5:
    s.push(i)

for x in s:
    d[x] = x * x

output d[4]
