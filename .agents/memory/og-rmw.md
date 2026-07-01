---
name: O-G RMW fusion
description: In-place accumulation peephole that fuses result=result OP base loop bodies into a single memory RMW instruction, eliminating load-compute-store triples. Includes triangular/anti-sum closed-form folds.
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

## 20-byte r15-accum path (all operators)
The 20-byte path (`total=total OP i` via r14 accumulator) now detects all five `OP rax,rbx` forms:
- Checks tail[-3]=0x48 (REX.W), tail[-2]=opcode ∈ {0x01,0x29,0x09,0x21,0x31}, tail[-1]=0xD8 (ModRM rax,rbx)
- Saves opcode in r9b, emits `4C [opcode] 3C 25 addr32`, sets `og_op_code=r9b`
- **XOR opcode is 0x31** (xor rax,rbx), NOT 0x33 (which is xor rax,[rbx])

## Triangular/anti-sum loop fold
Fires at `for_end` when `og_fired_in_body=1` AND `og_op_code ∈ {0x01, 0x29}` AND body=8 bytes AND loop_pin_active=1 AND N>0.
- OR/AND/XOR bodies: O-G peephole fires (RMW fusion), but **no fold** — no closed-form exists.
- BSS field `og_op_code` (resb 1) stores the operator code.

## ADD fold encoding
- Small delta (fits signed imm32): `48 81 04 25 addr32 imm32` (12 bytes, ModRM /0)
- Large delta: `movabs rax, delta`(10) + `48 01 04 25 addr32`(8) = 18 bytes
- Runtime N: same 7-instruction sequence, `add [addr], rax` at end

## SUB fold encoding (anti-sum)
- Small delta (fits signed imm32): `48 81 2C 25 addr32 imm32` (12 bytes, ModRM /5)
- Large delta: `movabs rax, delta`(10) + `48 29 04 25 addr32`(8) = 18 bytes
- Runtime N: same 7-instruction sequence, `sub [addr], rax` (`48 29 04 25 addr32`) at end

## Formula
`delta = N*(from+to-1)/2` where N=to-from. Same for ADD and SUB — only the emit opcode differs.

## og_op_code state lifecycle
Set in: 20-byte path and `.og_r15_fold_signal`.
Cleared in: codegen_init, for_start (static), for_start_dyn, fe_rolling_done_common, fe_normal_backjump.

## Interaction with O-A and Pattern A-reg
O-A pins the loop counter in r15. Pattern A-reg fuses `push rax; mov rax,r15; pop rbx` → `OP rax,r15` (3-byte form). O-G then sees exactly the 11-byte pattern `mov rax,[addr]` + `OP rax,r15` and fires.

## `:x=0` vs `int x=0` footgun
`:x = expr` is REASSIGNMENT — variable must already be declared. Always use `int x = 0` to declare.

**Why:** `:x = expr` emits a store to whatever VA `var_find("x")` returns. If x was never declared, var_find returns -1 or a stale slot.
