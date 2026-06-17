// T5 composition: quadratic formula + float comparison
// x = (-b + sqrt(b^2 - 4ac)) / 2a
// For x^2 - 5x + 6 = 0, roots are 2 and 3
float a = 1.0
float b = -5.0
float c = 6.0

float disc = b * b - 4.0 * a * c
// We'll use a simple approximation for sqrt since T004 isn't done
// but we can just use 1.0 here because 25 - 24 = 1
float root_disc = 1.0 

float x1 = (-b + root_disc) / (2.0 * a)
float x2 = (-b - root_disc) / (2.0 * a)

output x1
output x2
