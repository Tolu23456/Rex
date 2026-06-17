// bench_arena: Arena allocation
// Target: Rex >= 1000% of malloc (10x)
// 10M allocations of 64 bytes via use mm arena

use mm arena:
    for :i in 0..10000000:
        seq[int] :s
        // Allocate 64 bytes (8 ints)
        for :j in 0..8:
            push s j

output 1
