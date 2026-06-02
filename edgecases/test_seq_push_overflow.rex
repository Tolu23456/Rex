// Edge case: seq push beyond initial capacity (issue #19)
// Default allocation is 8 slots.  Pushing a 9th element should trigger
// the bounds-check guard (ud2 / SIGILL) rather than silently corrupting heap.
//
// EXPECTED BEHAVIOUR (after partial fix):
//   - Pushes 1..8 succeed and print 1 through 8.
//   - Push of 9 fires the ud2 guard → program terminates with SIGILL.
//
// Once a realloc blob is implemented the program should continue
// and print 9 as well.

seq s = 8           // allocate with capacity 8

push s 1
push s 2
push s 3
push s 4
push s 5
push s 6
push s 7
push s 8

// Print the length — should be 8
output len(s)       // expected: 8

// Print all elements by popping
output pop(s)       // expected: 8
output pop(s)       // expected: 7
output pop(s)       // expected: 6
output pop(s)       // expected: 5
output pop(s)       // expected: 4
output pop(s)       // expected: 3
output pop(s)       // expected: 2
output pop(s)       // expected: 1

// Refill and try to overflow
push s 10
push s 20
push s 30
push s 40
push s 50
push s 60
push s 70
push s 80
// This 9th push should trigger SIGILL (ud2 guard)
push s 90           // overflow — should halt here
output 999          // should NOT be reached
