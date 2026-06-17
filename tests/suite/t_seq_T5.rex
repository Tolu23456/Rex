// T5 composition: seq of ints + sum loop + output
seq nums
for i in 1..6:
    nums.push(i)

int sum = 0
for n in nums:
    :sum = sum + n

output sum
