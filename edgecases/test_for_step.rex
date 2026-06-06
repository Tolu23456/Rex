// Edge case: for loop step value
// step comes AFTER the range: for i in start..end step N

// Step 2: should print 0 2 4 6 8
for i in 0..10 step 2:
    output i

// Step 3: should print 0 3 6 9
for j in 0..12 step 3:
    output j

// Step 5: should print 10 15 20 25
for k in 10..30 step 5:
    output k

// Step 1 (default): should print 0 1 2 3 4
for n in 0..5:
    output n

// Dynamic bounds with step
int start = 1
int stop_val = 9
for m in start..stop_val step 2:
    output m        // expected: 1 3 5 7
