// rex_sort.rex — bubble sort on a sequence
// Demonstrates seq + indexed access pattern
// NOTE: seq currently does not support random index writes (only push/pop),
// so this documents the intended future syntax once index assignment lands.

seq data
for :i in 0..20000:
    push data i

// bubble sort passes — pending 'each' iterator and index assignment
// for :pass in 0..19999:
//     for :j in 0..19999-pass:
//         if data[j] > data[j+1]:
//             swap data[j] data[j+1]

int n
:n = len data
output n
