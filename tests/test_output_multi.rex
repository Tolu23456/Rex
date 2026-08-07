// Multi-argument output test (design.md §15.1)
// output(x, y, ...) prints values space-separated, terminated by a newline.
// sep= and end= are keyword args.

output()
output(1, 2, 3)
output("a", "b", "c", sep="-")
output("loading", end="...")
output("x=", 42, sep="")
output(1, "a", true, 2.5)
output(sep="|", 1, 2)
output(end=";")
output(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
output(2.5, 3, 4)
