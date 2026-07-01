---
name: O-G RMW fusion
description: In-place accumulation peephole that fuses result=result OP base loop bodies into a single memory RMW instruction, eliminating load-compute-store triples.
---

## Rule
O-G fires inside `codegen_emit_store_rax_to_var` at `.check_mem_pattern` after the 14-byte imm peephole. Detects `mov rax,[addr]`(8) + 3-byte-OP `rax,r15` in the circular tail, then rolls back 11 bytes and emits `OP [addr],r15` (8 bytes: REX+opcode+ModRM+SIB+abs32).

## Encodings emitted
- ADD: `4C 01 3C 25 <addr32>` (add qword [addr],r15)
- SUB: `4C 29 3C 25 <addr32>` (sub qword [addr],r15)
- OR:  `4C 09 3C 25 <addr32>` (or  qword [addr],r15)
- AND: `4C 21 3C 25 <addr32>` (and qword [addr],r15)
- XOR: `4C 31 3C 25 <addr32>` (xor qword [addr],r15)
- rbx variants (3C→1C): add `48 01 1C 25`, sub `48 29 1C 25`, etc.
- SUB 14-byte form: `mov rax,[addr]`+`neg rax`+`add rax,rbx` → `sub [addr],rbx`

## Interaction with O-A and Pattern A-reg
O-A pins the loop counter in r15. Pattern A-reg in `codegen_emit_add/sub/or/and/xor_rax_rbx` fuses `push rax; mov rax,r15; pop rbx` → `OP rax,r15` (3-byte form). O-G then sees exactly the 11-byte pattern `mov rax,[addr]` + `OP rax,r15` and fires. The interaction is CORRECT and verified: `for i in 0..8: :total = total + i` produces 28.

## 16-byte mem-to-mem extension
Also extended `.og_mem16_check` (the old `.check_mem_pattern` 16-byte sub-check) to handle OR (0x0B→0x09), AND (0x23→0x21), XOR (0x33→0x31) alongside ADD/SUB.

## `:x=0` vs `int x=0` footgun
`:x = 0` is REASSIGNMENT syntax — the variable must already be declared. Using it as a "declaration" produces 0 or wrong results because no var slot is allocated. Always use `int x = 0` / `float x = 0.0` etc. to declare. This is a pre-existing Rex language rule, not an O-G bug.

**Why:** `:x = expr` emits a store to whatever VA `var_find("x")` returns. If x was never declared, var_find returns -1 or a stale slot, producing undefined behaviour.

## Verification
Binary confirmed: `od` scan of compiled `for i in 0..8: :total=total+i` shows `4c 01 3c 25 00 00 44 00` in .text — `add qword [0x440000], r15`. All 57 tests pass.
