---
name: Rex triangular sum fold activation
description: Two bugs prevented the triangular sum fold from ever firing; fixes, encoding, and current benchmark state.
---

## The Two Bugs That Blocked the Fold

### Bug 1: `for :i` parser exited immediately
`parse_for` at parser.asm line 1040 checked `cmp dword [cur_tok], TOK_IDENT`.
With `for :i`, cur_tok = TOK_COLON → jumped to `.for_done` with no loop emitted → segfault.

**Fix**: After `advance` (consume 'for'), skip an optional `:` before the identifier:
```asm
cmp dword [cur_tok], TOK_COLON
jne .for_no_mut_sigil
advance
.for_no_mut_sigil:
```

### Bug 2: O-G 11-byte pattern never fires when i is r15-cached
When the loop counter `i` is pinned to r15 (O-A active), the expression `total + i` generates:
```
48 8B 04 25 <total_addr>   ; mov rax, [total]   (8 bytes)
49 89 C2                   ; mov r10, rax        (3 bytes)  ← push
4C 89 F8                   ; mov rax, r15        (3 bytes)  ← cached i load
4C 89 D3                   ; mov rbx, r10        (3 bytes)  ← pop
48 01 D8                   ; add rax, rbx        (3 bytes)
```
= 20 bytes total. O-G's 11-byte pattern checks tail[-11] = 0x48 (`mov rax,[addr]`).
But tail[-11] = 0x89 (2nd byte of `mov r10,rax`). Pattern fails → fold never activates.

## The Fix: 20-byte r15-accum Peephole

Added at `.check_mem_pattern` in `codegen_emit_store_rax_to_var` (before the existing O-G 11-byte check, now at label `.og_check_11`):

- Guard: `loop_pin_active == 1` and `emit_tail_len >= 20`
- Check tail[-20..-17] = `48 8B 04 25` (mov rax, [abs32])
- Extract addr32 from `out_buffer[out_idx - 16]`
- Verify addr32 == store destination (rdi)
- Check tail[-12..-10] = `49 89 C2` (mov r10, rax)
- Check tail[-9..-7] = `4C 89 F8` (mov rax, r15)
- Check tail[-6..-4] = `4C 89 D3` (mov rbx, r10)
- Check tail[-3..-1] = `48 01 D8` (add rax, rbx)
- Match: roll back 20 bytes, emit `4C 01 3C 25 addr32` (`add [addr], r15`, 8 bytes)
- Set `og_fired_in_body = 1`, `og_rw_addr32 = addr32`

This makes body = 8 bytes → `for_end` sees body size 8 and `og_fired_in_body=1` → triangular sum fold fires.

## Key Encoding Notes

- `add [abs32], r15` = `4C 01 3C 25 addr32` (8 bytes, REX.R=1 for r15, opcode 01, ModRM 3C, SIB 25)
- Triangular delta = `N*(from + to - 1)/2` where N = to - from
- delta fits imm32 → `48 81 04 25 addr32 delta32` (12 bytes)
- delta overflows imm32 → `movabs rax, delta` (10) + `add [addr32], rax` (8) = 18 bytes

## Benchmark Result

```
benchmark/sum.rex:  for i in 0..100000000: total += i
→ fold emits add [total], 4999999950000000 (no loop)
Rex:  ~3ms
C -O3: ~8ms
Rex wins by ~3x (61/61 tests pass)
```

**Why:** Rex has lower startup overhead (no libc init) and both compilers eliminate the loop at compile time.

## What This Does NOT Handle

- `for :total = i + total` (i first, total second) — pattern won't match; add must be `total + i`
- Loops with non-literal bounds (`for i in 0..n:`) — fold only works for static from/to
- While-loop accumulation — no equivalent fold exists for while loops
