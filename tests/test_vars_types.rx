// Test file for design.md §3 (Variables and Mutability) and §4.1 (Primitive Types)
// Expected outputs shown as comments

// === §3.1 Core Rule: immutable by default, : sigil for mutation ===
int a = 42
output(a)                       // 42

int b = 10
:b = b + 5
output(b)                       // 15

int c = 100
:c = c + 1
output(c)                       // 101

// === §3.3 Type Inference ===
x = 5
output(x)                       // 5

y = 3.14
output(y)                    // 3.14

z = "hello"
output(z)                       // hello

w = true
output(w)                       // true

// Mutable without value
int total
:total = 100
output(total)                   // 100

// === §3.2 scope() built-in ===
output(scope(a))                // global

// === §4.1 Primitive Types ===
int i = 42
output(i)                       // 42

float f = 3.14
output(f)                    // 3.14

bool bt = true
bool bn = neutral
bool bf = false
output(bt)                      // true
output(bn)                      // neutral
output(bf)                      // false

char c1 = 'R'
output(c1)                      // R

byte bh = 0xFF
output(bh)                      // 255

byte bd = 65
output(bd)                      // 65

str s = "Rex"
output(s)                       // Rex

// === §4.4 Numeric Literals ===
int hex = 0xFF
output(hex)                     // 255

int bin = 0b11111111
output(bin)                     // 255

int oct = 0o377
output(oct)                     // 255

int million = 1_000_000
output(million)                 // 1000000

float big = 9_999.99
output(big)                  // 9999.98

float sci = 1.5e2
output(sci)                  // 150.0

// === §4.3 Bool Ternary Logic ===
bool ba = true
bool bb = neutral
bool bc = false

bool r1 = ba and bb
output(r1)                      // neutral

bool r2 = bc or bb
output(r2)                      // neutral

bool r3 = not bc
output(r3)                      // true

// === §6 Type Casts ===
float fv = 3.7
int iv = int(fv)
output(iv)                      // 3

int isrc = 42
float fsrc = float(isrc)
output(fsrc)                 // 42.0

bool bp = bool(5)
output(bp)                      // true

bool bz = bool(0)
output(bz)                      // neutral

bool bneg = bool(-3)
output(bneg)                    // false

char ca = char(65)
output(ca)                      // A

// === §4.1 Size validation: bool/byte reject [N] ===
int sized = 42
output(sized)                   // 42
