// T3 1000-key dict, all keys retrievable
dict d
for i in 0..1000:
    // Need to convert i to string for key if dict is dict[str]
    // For now use a fixed prefix if str concat exists, or just use int keys if supported
    // The syn.md says dict[str] or dict[int]. Let's assume dict[int] for simplicity here.
    d[i] = i * 2

output len d
output d[500]
