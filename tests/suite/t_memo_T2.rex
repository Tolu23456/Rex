// T2 memo of zero-param prot
int count = 0
#memo
prot once() -> int:
    :count = count + 1
    return count

output @once()
output @once()
output count
