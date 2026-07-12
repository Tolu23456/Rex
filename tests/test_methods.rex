// test_methods.rex
// Tests method dispatch (§3–§4.9): int/float/bool/char methods
//
// Expected output:
//   5
//   1
//   -1
//   true
//   false
//   true
//   false
//   true
//   10
//   2
//   3
//   1.5
//   2.0
//   1.0
//   1.0
//   true
//   false
//   false
//   true

// --- INT methods ---
int n = -5
output(n.abs())

int a = 3
output(a.signum())

int b = -7
output(b.signum())

int z = 0
bool iz = z.is_zero()
output(iz)

int pos = 4
bool ip = pos.is_positive()
output(ip)

int even = 8
bool ie = even.is_even()
output(ie)

int odd = 7
bool io = odd.is_odd()
output(io)

int x = 3
int y = 10
output(x.max(y))

int p = 3
int q = 7
output(p.min(q))

int c = 5
output(c.clamp(1, 10))

// --- FLOAT methods ---
float f = -1.5
output(f.abs())

float g = 1.7
output(g.ceil())

float h = 1.7
output(h.floor())

float sq = 1.0
output(sq.sqrt())

// --- BOOL methods ---
bool tr = true
bool fl = false
bool neu = neutral

output(tr.is_true())
output(fl.is_false())
output(neu.is_decided())
output(tr.is_decided())
