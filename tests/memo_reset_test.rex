memo proto sq(n):
  int x = n * n
  ret x

// First run: cache miss, computes 25, caches it
output @sq(5)
// Second run: cache hit, returns 25
output @sq(5)

// Reset the cache
memo_reset sq

// Third run: cache miss again after reset, computes 25
output @sq(5)
// Fourth run: cache hit again
output @sq(5)
