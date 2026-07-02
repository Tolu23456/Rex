prot sum_range(int n):
    int total = 0
    int i = 0
    while i < n:
        :total = total + i
        :i = i + 1
    return total

output @sum_range(1000)
output @sum_range(10000)
output @sum_range(100000)
