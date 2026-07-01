# Rex vs C -O3 Benchmark Results

## Test: Sum 0..99999999

| Metric | C -O3 | Rex (optimized) | Ratio |
|--------|-------|-----------------|-------|
| Time (user) | ~1ms | ~400ms | ~400x |
| Loop instructions | 5 (register) | 6 (memory) | 1.2x |
| Loop bytes | ~14 | ~36 | 2.6x |

## Optimizations Implemented

### 1. Peephole: Memory Operand Fusion
- `push rax; mov rax,[addr]; pop rbx; add rax,rbx` → `add rax,[addr]` (saves 3 instructions)
- `push rax; movabs N,rax; pop rbx; add rax,rbx` → `add rax, imm32` (saves 3 instructions)
- `push rax; movabs N,rax; pop rbx; imul rax,rbx` → `imul rax,rax,imm32` (saves 3 instructions)
- Store fusion: `mov rax,[addr]; add rax,[addr2]; mov [addr],rax` → `add [addr],rax`

### 2. Constant Folding
- Compile-time evaluation of constant integer expressions
- `1 + 2` → `mov rax, 3` (no runtime computation)

### 3. Strength Reduction
- `i * 8` → `shl rax, 3`
- `i * 2` → `lea rax, [rax*2]` or `shl rax, 1`
- `i * 0` → `xor eax, eax`

### 4. Loop Comparison Fusion
- `push; movabs N; pop; cmp; setl; movzx; test; jz` → `cmp [addr], N; jge` (saves 7 instructions)
- All comparison operators: setl/setg/sete/setne/setle/setge

### 5. Increment/Decrement Fusion
- `mov rax,[addr]; push; movabs 1; pop; add; mov [addr],rax` → `incq [addr]` (saves 5 instructions)
- `mov rax,[addr]; push; movabs 1; pop; sub; mov [addr],rax` → `decq [addr]` (saves 5 instructions)

## Generated Loop Code (Sum Benchmark)
```asm
.loop:
    cmpq $100000000, [0x440000]    ; fused comparison (was 9 instructions)
    jge .exit
    mov rax, [0x440000]            ; load i
    add [0x440040], rax            ; fused: sum += i
    incq [0x440000]                ; fused: i++
    jmp .loop
```

## Remaining Bottleneck
All variable access uses absolute memory addresses (0x440000 + offset).
Each memory access costs ~5 cycles vs ~1 cycle for register access.
The loop does 4 memory operations per iteration ≈ 20 cycles.
C's register loop does ~1 cycle per iteration.

**To close the gap further, register-based variable access is needed.**
