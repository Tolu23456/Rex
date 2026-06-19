---
name: Rex Self-Hosting Plan
description: The agreed bootstrap sequence and architecture for making Rex fully self-hosted and portable via RexC and RIC.
---

# Rex Self-Hosting Plan

## Goal
Rex becomes a fully self-contained ecosystem — compiler, runtime, and instruction layer all written in Rex. No dependency on C, LLVM, or external toolchains after bootstrap.

## Bootstrap Sequence

```
Step 1  Rex → x86-64 NASM asm     (current compiler, runs on x86-64 Linux)
Step 2  Write RexC runtime in Rex
Step 3  Compile runtime with Step 1 compiler → native runtime binary
Step 4  Runtime can now execute .rxc files on that machine
Step 5  Compile Rex compiler itself to .rxc using Step 1 compiler
Step 6  Runtime runs the .rxc compiler → Rex is now self-contained
Step 7  Drop x86-64 backend; Rex lives entirely inside its own ecosystem
```

After Step 6, the only bootstrap artifact needed per new platform is a small pre-built native runtime binary — same strategy as Go's bootstrap compiler.

## Layer Architecture

```
Rex source (.rex)
      ↓  Rex compiler (written in Rex)
RexC bytecode (.rxc)       — safe, portable, general purpose
      ↓  RexC runtime (written in Rex)
RIC instructions           — Rex Instruction Code, SIMD-like, performance layer
      ↓  JIT in runtime maps to hardware
Native machine code        — SSE/AVX on x86 | NEON on ARM | SVE on ARM64 | scalar fallback
```

## Components

| Component | Written in | Role |
|---|---|---|
| Rex compiler | Rex (self-hosted) | .rex → .rxc |
| RexC runtime | Rex | loads and executes .rxc |
| RIC JIT layer | Rex | translates RIC ops to native instructions |
| Bootstrap binary | asm/C (temporary) | only needed once per new platform |

## Portability Model
- RexC bytecode (.rxc) is the universal portable artifact
- Any machine with the RexC runtime can run any Rex program
- RIC gives near-assembly performance via JIT without sacrificing portability
- The runtime is the ONLY thing that needs porting to a new platform; it is small and self-contained

## Speed Guarantee
RIC maps 1:1 to hardware vector/compute instructions. With JIT compilation in the runtime, Rex can match assembly speed for compute-intensive workloads. Key conditions:
- Runtime must JIT-compile RIC (not interpret it)
- RIC maps tightly to hardware SIMD primitives
- No unnecessary boxing or heap allocation in hot paths
