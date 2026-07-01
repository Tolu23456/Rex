prot pow(int base, int exp):
    int result = 1
    int i = 0
    while i < exp:
        :result = result * base
        :i = i + 1
    return result

output @pow(2, 10)
output @pow(3, 3)
output @pow(5, 0)
