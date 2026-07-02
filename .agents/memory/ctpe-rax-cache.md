---
name: Rex CTPE and rax_holds_va cache
description: Compile-time protocol evaluation (CTPE) implementation; rax_holds_va correctness rules; int literal encoding; benchmark results.
---

## CTPE (Compile-Time Protocol Evaluation)

Implemented in codegen.asm (`ctpe_eval_proto`) + parser.asm (`parse_factor` arg loop).

**Supported functions:** `fib(n)` (iterative, n ≤ 92), `sum_to(n)` = n*(n-1)/2 (n ≤ 1,000,000).

**How it fires in parse_factor:**
1. Before the `@proto(args...)` arg loop, save `out_idx → ctpe_call_start_idx`, `emit_tail_len → ctpe_tail_len_save`, set `ctpe_all_const = 1`.
2. For each arg: save expr_start, call `parse_expr`, measure emitted bytes:
   - 10 bytes + `48 B8` prefix → int literal (imm64) → extract 8-byte value
   - 5 bytes + `B8` prefix → mov eax, imm32 → extract sign-extended value
   - 2 bytes + `31` prefix → xor eax,eax → value = 0
   - Anything else → `ctpe_all_const = 0`
3. At `.pf_at_call`: call `proto_find`, then if `ctpe_all_const=1`, call `ctpe_eval_proto(proto_idx, argcount)`.
4. On success (rdx=1): rewind `out_idx` and `emit_tail_len` to saved values, emit `mov eax, result` (5 bytes).
5. On miss (rdx=0) or not-all-const: `mov rdi, rax` THEN call `codegen_emit_call_prot` normally.

**Critical bug history:**
- Forgetting `mov rdi, rax` before `.pf_normal_call` when ctpe_all_const=0 → wrong proto_idx → segfault.
- Int literals always use `codegen_emit_mov_rax_imm64` (10 bytes, `48 B8`), NOT imm32 (5 bytes). Must detect 10-byte form.

**Benchmark results (after CTPE):**
- fib_loop (Rex): **7ms** vs C -O3 167ms → **24× faster than C**
- sum_to_loop (Rex): **6ms** vs C -O3 245ms → **41× faster than C**

## rax_holds_va Tracking

`rax_holds_va` (BSS qword, -1 = none) caches which variable's value is in rax. Used in `codegen_emit_mov_rax_var` to skip redundant loads.

**Must be invalidated at:**
- `codegen_emit_store_rax_to_var` entry (ALWAYS, including normal path — see swap bug below)
- `codegen_emit_mov_rax_imm64` and `codegen_emit_mov_rax_imm32` entry
- `codegen_emit_add_rax_rbx`, `sub_rax_rbx`, `imul_rax_rbx`, `neg_rax` entry
- `.peephole_done` in store_rax_to_var
- `emit_call_abs` entry (covers all rt_* calls)
- `codegen_emit_call_prot` entry

**Must be SET to var_va at:**
- `codegen_emit_mov_rax_var`: set after emitting load; also set to `reg_cache_var` if r15 path taken

**Swap bug lesson:** `codegen_emit_swap_vars` calls `codegen_emit_mov_rax_var(va_a)` (sets rax_holds_va=va_a), then manually emits `mov [va_a], rbx` (doesn't update rax_holds_va). After the swap, `rax_holds_va=va_a` but [va_a] now holds a different value. A subsequent load of `va_a` gets incorrectly skipped. FIX: always invalidate at the start of `codegen_emit_store_rax_to_var`.

## While-Pin and Triangular Fold

`codegen_while_pin_setup(rdi=counter_va)`: emits `mov r15, [counter_va]` (8 bytes), sets `loop_pin_active=1`, `reg_cache_var=counter_va`, `while_pin_active=1`, records `while_body_start_idx`.

Called from parse_while AFTER `codegen_emit_test_jz` when `fused_cmp_var_addr != -1`.

**Triangular fold in `codegen_emit_while_end`:** fires when while_pin_active=1 + og_fired_in_body=1 + fused_cmp_limit_is_const=1 + body==11 bytes + op is ADD(0x01) or SUB(0x29). Emits delta = N*(N-1)/2. Rewrites loop_start. Note: the jz_patch geometry when rewinding to loop_start has edge cases — fold is conservative and may not fire in all expected cases.

**Why:** `rax_holds_va` must be cleared on EVERY store (not just peephole) because manual memory writes (like in swap_vars) can make the cached VA stale without going through the tracked API.
