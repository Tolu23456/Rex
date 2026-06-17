// bench_str_search: SIMD string search
// Target: Rex >= 200% of strstr
// Search for 4-char needle in 10KB haystack, 100K times

str :haystack = "abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
// Make it ~10KB
for :i in 0..7:
    :haystack = haystack + haystack

str :needle = "XYZ0"
int :count = 0
for :j in 0..100000:
    if @contains(haystack, needle):
        :count = count + 1

output count
