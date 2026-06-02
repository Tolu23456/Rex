// Edge case: nested when statements (issue #32)
// Before fix: inner when overwrote when_var_idx global; outer when's subsequent
// is-cases compared against the wrong variable.
// After fix: when_var_stack / when_cnt_stack save and restore context.

int outer = 2
int inner_val = 1

when outer:
    is 1:
        output 10   // should NOT print
    is 2:
        when inner_val:
            is 1:
                output 99   // expected: 99
            is 2:
                output 88   // should NOT print
        // outer when continues — must still see outer==2 context
    is 3:
        output 30   // should NOT print
    else:
        output 0    // should NOT print

// Second nested when with a different structure
int a = 3
int b = 2
when a:
    is 1:
        output 1
    is 3:
        when b:
            is 1:
                output 31
            is 2:
                output 32   // expected: 32
            else:
                output 30
        // outer when must still be in a==3 context; no further cases so done
    else:
        output 0
