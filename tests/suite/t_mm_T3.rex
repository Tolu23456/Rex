// T3 arena + 100000 pushes in one arena scope
use mm arena:
    seq s
    for i in 0..100000:
        s.push(i)
    output len s
