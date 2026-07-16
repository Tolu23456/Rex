// test_seq_remove_val.rex
// Tests seq.remove(i) shifts elements correctly
seq[int] s = [10, 20, 30, 40, 50]

// remove element at index 1 (which is 20)
:s.remove(1)
output(s.len())
// After remove: [10, 30, 40, 50]
output(s.get(0))
output(s.get(1))
output(s.get(2))
output(s.get(3))
