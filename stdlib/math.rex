/// math.rex — Math functions for Rex.
/// These protocols wrap high-performance runtime blobs (rt_math_*) 
/// added in Rex V5.0. 

/// sqrt(x) — Square root via sqrtsd instruction.
prot sqrt() -> float:
    return 0.0

/// floor(x) — Round down to nearest integer.
prot floor() -> float:
    return 0.0

/// ceil(x) — Round up to nearest integer.
prot ceil() -> float:
    return 0.0

/// abs_f(x) — Floating point absolute value.
prot abs_f() -> float:
    return 0.0

/// sin(x) — Sine via x87 fsin instruction.
prot sin() -> float:
    return 0.0

/// cos(x) — Cosine via x87 fcos instruction.
prot cos() -> float:
    return 0.0

/// exp(x) — Natural exponential e^x.
prot exp() -> float:
    return 0.0

/// log(x) — Natural logarithm ln(x).
prot log() -> float:
    return 0.0

/// pow(x, y) — Power x^y.
prot pow() -> float:
    return 0.0

/// min(a, b) — Minimum of two floats.
prot min() -> float:
    return 0.0

/// max(a, b) — Maximum of two floats.
prot max() -> float:
    return 0.0
