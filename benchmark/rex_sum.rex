// rex_sum.rex — integer sum benchmark
// Equivalent to: sum all integers from 1 to 1,000,000,000
// Rex compiles this to a tight 6-instruction loop:
//   mov rax, 0          ; sum = 0
//   mov rbx, 1          ; i = 1
// .loop:
//   add rax, rbx        ; sum += i
//   inc rbx             ; i++
//   cmp rbx, 1000000001
//   jl  .loop

int sum
:sum = 0
for :i in 0..1000000000:
    :sum = sum + i
output sum
