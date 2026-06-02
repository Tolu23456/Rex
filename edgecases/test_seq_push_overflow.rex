// Edge case: seq push beyond initial capacity (issue #19 — now fully fixed)
// Default allocation is 8 slots (80 bytes: 16-byte header + 8*8 data).
// When the 9th element is pushed, the grow path fires:
//   new_cap = old_cap * 2 = 16
//   new_size = 16 + 16*8 = 144 bytes  → rt_alc(144)
//   elements copied via rep movsq
//   var slot updated with new ptr
// Growth is unbounded — each overflow doubles capacity.

seq s = 8       // initial capacity 8

// Push 8 elements (fill to capacity)
push s 1
push s 2
push s 3
push s 4
push s 5
push s 6
push s 7
push s 8

output len(s)   // expected: 8

// Push 9th — triggers grow (cap 8 → 16)
push s 9
output len(s)   // expected: 9

// Push more past 9 to verify continued operation
push s 10
push s 11
push s 12
push s 13
push s 14
push s 15
push s 16

output len(s)   // expected: 16

// Push 17th — triggers grow again (cap 16 → 32)
push s 17
output len(s)   // expected: 17

// Verify values are intact by popping
output pop(s)   // expected: 17
output pop(s)   // expected: 16
output pop(s)   // expected: 15
output pop(s)   // expected: 14
output pop(s)   // expected: 13
output pop(s)   // expected: 12
output pop(s)   // expected: 11
output pop(s)   // expected: 10
output pop(s)   // expected: 9
output pop(s)   // expected: 8
output pop(s)   // expected: 7
output pop(s)   // expected: 6
output pop(s)   // expected: 5
output pop(s)   // expected: 4
output pop(s)   // expected: 3
output pop(s)   // expected: 2
output pop(s)   // expected: 1

output len(s)   // expected: 0
