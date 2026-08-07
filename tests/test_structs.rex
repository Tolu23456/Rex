// Test file for design.md §4.12 (Structs): construction, field access,
// nested structs, value semantics, field mutation, value equality.
struct Point:
  int x
  int y

struct Inner:
  int a
  int b

struct Wrap:
  int id
  Inner inner

Point p = Point{x: 1, y: 2}
Point q = Point{x: 1, y: 2}
Point r = Point{x: 1, y: 3}
output(p.x)                     // 1
output(p.y)                     // 2
output(q.x)                     // 1
output(q.y)                     // 2

:p.x = 100
output(p.x)                     // 100
output(q.x)                     // 1  (copy semantics: p and q are independent)

Wrap w1 = Wrap{id: 7, inner: Inner{a: 5, b: 6}}
Wrap w2 = Wrap{id: 7, inner: Inner{a: 5, b: 6}}
Wrap w3 = Wrap{id: 7, inner: Inner{a: 5, b: 9}}
output(w1.id)                   // 7
output(w1.inner.a)              // 5
output(w1.inner.b)              // 6
:w1.inner.b = 99
output(w1.inner.b)              // 99
output(w2.inner.b)              // 6  (nested copy semantics hold)

output(p == q)                  // false (p.x=100 vs q.x=1)
output(r == q)                  // false (y differs)
output(q == r)                  // false
output(q != r)                  // true
output(w1 == w2)                // false (w1.inner.b mutated)
output(w2 == w3)                // false (b differs)
output(p is p)                  // true  (identity)
output(p is q)                  // false (different slots, same-ish value? no: x differs)

Point s = Point{x: 1, y: 2}
output(s == q)                  // true  (equal by value)
