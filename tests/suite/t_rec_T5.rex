// T5 tree-traversal simulation using recursive prot
// We'll simulate a tree with indices: left(i) = 2i+1, right(i) = 2i+2
prot traverse(int i, int max):
    if i >= max: return
    output i
    @traverse(2 * i + 1, max)
    @traverse(2 * i + 2, max)

@traverse(0, 7)
