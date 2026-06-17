// bench_seq_push: Dynamic array push/pop
// Target: Rex >= 110% of C vector speed
// 10M pushes into seq[int], then 10M pops

seq[int] :data
for :i in 0..10000000:
    push data i

for :j in 0..10000000:
    pop data

output 1
