// T4 memo reset clears cache
#memo
prot get_val(int n) -> int:
    return n

output @get_val(10)
// memo reset get_val // assuming this syntax from syn.md/tasks
output @get_val(10)
