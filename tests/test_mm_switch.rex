// test_mm_switch.rex — memory manager context switching
use mm pool gc mypool:
    int x
    :x = 42
    output x

use mm arena gc myarena:
    int y
    :y = 99
    output y
