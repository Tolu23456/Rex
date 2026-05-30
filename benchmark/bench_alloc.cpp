#include <cstdio>
#include <ctime>
#include <cstdint>
#include <cstdlib>
#include <vector>
#include <memory>

static double ns(struct timespec a, struct timespec b) {
    return (b.tv_sec - a.tv_sec) * 1e9 + (b.tv_nsec - a.tv_nsec);
}

static constexpr int ALLOCS = 500000;
static constexpr int BLOCK  = 80;

int main() {
    struct timespec t0, t1;
    std::vector<void*> ptrs(ALLOCS);

    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int i = 0; i < ALLOCS; i++) {
        ptrs[i] = ::operator new(BLOCK);
        static_cast<char*>(ptrs[i])[0] = static_cast<char>(i);
    }
    for (int i = 0; i < ALLOCS; i++) ::operator delete(ptrs[i]);
    clock_gettime(CLOCK_MONOTONIC, &t1);

    printf("new/delete x%d (%d bytes each)  time=%.2f ms\n",
           ALLOCS, BLOCK, ns(t0, t1) / 1e6);
    return 0;
}
