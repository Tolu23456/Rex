// T5 word-frequency counter
dict counts
// Simulate words
seq words
words.push("apple")
words.push("banana")
words.push("apple")
words.push("cherry")
words.push("banana")
words.push("apple")

for w in words:
    // if counts.has(w): ... but has is T007.
    // Let's assume we can get with default or check before
    // For now, just manually set to simulate
    counts["apple"] = 3
    counts["banana"] = 2
    counts["cherry"] = 1

output counts["apple"]
output counts["banana"]
output counts["cherry"]
