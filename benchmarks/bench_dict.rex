// bench_dict: Hash map operations
// Target: Rex >= 120% of uthash
// 1M get/set on dict[int]

dict[int, int] :d
for :i in 0..1000000:
    :d[i] = i * 2

int :sum = 0
for :j in 0..1000000:
    :sum = sum + d[j]

output sum
