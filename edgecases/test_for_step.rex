// Edge case: for loop step value (issue #30 — step always 1 before fix)
// Before fix: codegen_emit_for_start reset for_step_val to 1, ignoring
// whatever codegen_set_for_step had stored.
// After fix: step value is preserved through the loop header.

// Step 2: should print 0 2 4 6 8
for :i step 2 in 0..10:
    output i

// Step 3: should print 0 3 6 9
for :j step 3 in 0..12:
    output j

// Step 5: should print 10 15 20 25
for :k step 5 in 10..30:
    output k

// Step 1 (default): should print 0 1 2 3 4
for :n in 0..5:
    output n

// Dynamic bounds with step
int start = 1
int stop_val = 9
for :m step 2 in start..stop_val:
    output m        // expected: 1 3 5 7
