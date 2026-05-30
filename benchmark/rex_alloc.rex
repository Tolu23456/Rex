// rex_alloc.rex — allocation benchmark using Rex pool allocator
// Rex's `use mm pool gc name:` context hot-swaps to a bump-pointer pool.
// All allocations inside the block are O(1) pointer increments.
// The entire pool is reclaimed in a single reset at block exit.

use mm pool gc bench_pool:
    for :i in 0..500000:
        seq s
        push s i

// At this point the pool is reclaimed with a single mov qword[pool_offset], 0
output 1
