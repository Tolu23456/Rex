// test_seq_count_index.rex
// seq `.count`/`.index` (design §10.3) plus the older `_of` aliases.

seq[int] nums = [5, 3, 5, 7, 5]
output(nums.count(5))
output(nums.count(9))
output(nums.index(7))
output(nums.index(5))
output(nums.index_of(3))
output(nums.count_of(5))
