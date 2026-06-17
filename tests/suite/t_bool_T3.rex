// T3 1000 bool operations chained
bool b = true
for i in 0..1000:
    :b = b and true
output b
for i in 0..1000:
    :b = b or false
output b
