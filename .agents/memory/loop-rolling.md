---
name: O-H and Loop Rolling
description: Triangular sum fold (total+=i) and constant-mul binary-ladder fold (x*=A); BSS fields, detection, for_end structure, body-length invariants.
---

## BSS fields added

```
for_from_val:         resq 1   ; from_imm saved at for_start
for_to_val:           resq 1   ; to_imm saved at for_start
for_body_start_idx:   resq 1   ; out_idx recorded at END of for_start (= body start)
og_fired_in_body:     resb 1   ; set at .og_r15_ok when loop_pin_active=1 AND op=ADD
og_rw_addr32:         resd 1   ; 32-bit VA of the O-G RMW target
oh_mul_fired_in_body: resb 1   ; set at .abs_store_normal for 15-byte imul pattern
oh_mul_addr32:        resd 1   ; 32-bit VA of the constant-mul target
oh_mul_const:         resq 1   ; multiplier A (sign-extended from imm32)
```

## Where flags are set

- **`for_from_val` / `for_to_val`**: saved at `.emit_jmp_check` (after `loop_pin_active=1`) from r13/r14.
- **`og_fired_in_body`**: set in `codegen_emit_store_rax_to_var` at `.og_r15_ok` when `loop_pin_active=1` AND `r9b==0x01` (ADD). Guards with `je .og_r15_emit` and `jne .og_r15_emit` labels.
- **`oh_mul_fired_in_body`**: set at TOP of `.abs_store_normal` (before the store code). Checks 15-byte tail: `48 8B 04 25 addr`(8) + `48 69 C0 A_imm32`(7). Verifies addr matches `edi` (store dest). Does NOT modify output.
- **`for_body_start_idx`**: recorded just before the final pops in `codegen_emit_for_start`, using `mov r8,[out_idx]; mov [for_body_start_idx],r8`.

## for_end structure

```
codegen_emit_for_end:
  check loop_pin_active → .fe_normal_backjump if 0
  check og_fired_in_body → triangular sum path
    body must be 8 bytes, N>0
    delta = N*(from+to-1)/2 (signed 64-bit)
    rewind out_idx, sub emit_tail_len 8
    if delta fits imm32: 48 81 04 25 addr delta32 (12 bytes)
    else: movabs rax,delta + add [addr],rax (18 bytes)
    → .fe_rolling_done
  check oh_mul_fired_in_body → constant-mul path
    body must be 23 bytes, N>0
    binary ladder: r9=1, r11=A; loop: if N&1: r9*=r11; r11*=r11; N>>=1
    rewind out_idx, sub emit_tail_len 23
    if A^N fits imm32: mov rax,[x]+imul rax,rax,A^N+mov [x],rax (23 bytes)
    else: movabs rax,A^N + imul rax,[x] + mov [x],rax (26 bytes)
    → .fe_rolling_done
  .fe_rolling_done:
    emit mov qword [var_va], to_imm32  (sets loop var to final value)
    clear loop_pin_active, loop_pin_var_va, reg_cache_var, og_fired_in_body, oh_mul_fired_in_body
    call codegen_patch_jump (jge exit), codegen_patch_breaks, codegen_pop_cont
    dec loop_depth
    ret   ← NO back-jump emitted
  .fe_normal_backjump:
    emit jmp to for_cont_addr (normal back-jump)
    patch jge, breaks, cont
    flush r15 if loop_pin_active (O-A)
    clear og_fired_in_body, oh_mul_fired_in_body
    ret
```

## Body-length invariants

- Triangular sum body: exactly **8 bytes** (`4C 01 3C 25 addr32` — the O-G RMW instruction after rolling back the load+add and emitting the fused op).
- Constant-mul body: exactly **23 bytes** (`48 8B 04 25 addr32` + `48 69 C0 A_imm32` + `48 89 04 25 addr32`). Pattern B in `codegen_emit_imul_rax_rbx` must fire (rolls back push+movabs+pop = 12 bytes, emits imul rax,rax,imm32 = 7 bytes) for this size to match.

**Why:** Mixed or conditional bodies produce different sizes and correctly skip rolling. The body-length check is the guard.

## register allocation in for_end rolling section

- r10 = N (and binary-ladder counter)
- r11 = base A (ladder); also temp for from/to arithmetic
- r9  = result A^N (binary-ladder)
- r8  = scratch for body-start/size checks
- r12/r13/r14 = loop_start / jge_patch / var_va (saved by for_end prologue, preserved throughout)
- emit_b only clobbers rax; r8-r15 are safe across emit_b calls.

## Makefile note

After adding edge-case tests, had to update Makefile `test` target to include `tests/edge-cases/*.rex` with `dir=$(dirname $f); exp=${dir}/${name}.expected` pattern. Previously only `tests/*.rex` was scanned.
