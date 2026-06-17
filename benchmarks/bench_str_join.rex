// bench_str_join: String split/join
// Target: Rex >= 150% of C with malloc
// Split 1000-word string, join back 1000 times

str :word = "word "
str :long_str = ""
for :i in 0..1000:
    :long_str = long_str + word

for :j in 0..1000:
    seq[str] :parts = @split(long_str, " ")
    str :result = @join(parts, "-")

output 1
