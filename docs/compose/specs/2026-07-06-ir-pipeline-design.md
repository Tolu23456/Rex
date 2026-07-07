# Rex Multi-Pass IR Compiler Pipeline — Design Spec

**Date:** 2026-07-06
**Status:** Approved
**Goal:** Replace single-pass direct x86 emission with a register-based IR and 5 optimization passes to enable self-hosting.

---

## [S1] Problem

The current Rex compiler emits raw x86-64 machine bytes directly from the parser (`codegen_emit_*` functions → `out_buffer`). There is no intermediate representation, no register allocation, no constant folding, and no dead store elimination. Every variable access goes through memory. The CTPE system (`ctpe_ir_buf`) provides compile-time constant folding for individual protocol calls only, not whole-program optimization.

For self-hosting, the compiler must produce optimized output comparable to C at -O0. The IR pipeline is the foundation for this.

## [S2] Architecture

### Current flow
```
parser → codegen_emit_* → out_buffer (raw x86 bytes)
```

### New flow
```
parser → ir_emit_* → ir_buffer (32-byte records)
        ↓
  Pass 1: Constant Folding
  Pass 2: Dead Store Elimination
  Pass 3: Load-Store Coalescing
  Pass 4: Linear Scan Register Allocation
  Pass 5: Peephole
        ↓
  x86 emission → out_buffer (raw x86 bytes)
```

The existing CTPE system (`ctpe_ir_buf`) is independent and stays as-is.

## [S3] New Files

| File | Purpose |
|------|---------|
| `include/rex_ir.inc` | IR opcode constants, record field offsets, flag definitions |
| `irgen/irgen.asm` | IR record emitter, vreg allocator, label allocator |
| `irgen/ir_passes.asm` | Optimization passes 1–5 |
| `irgen/ir_emit_x86.asm` | x86-64 emission from IR records + label resolution |

`codegen/codegen.asm` retains ELF header, runtime blobs, and table management. The `codegen_emit_*` functions are superseded by `ir_emit_*` calls from the parser.

## [S4] IR Record Layout

Each IR instruction is exactly **32 bytes**. Buffer is a flat array (`ir_buffer resb IR_MAX * 32`).

```
offset  size  field     description
  0       1   opcode    IR_* constant (up to 256 operations)
  1       1   type      TYPE_INT / TYPE_FLOAT / TYPE_BOOL / TYPE_COMPLEX / TYPE_STR / TYPE_SEQ / TYPE_DICT / TYPE_VOID
  2       2   dst       destination virtual register (0 = none)
  4       2   src1      first source virtual register (0 = unused)
  6       2   src2      second source virtual register (0 = unused)
  8       8   imm       primary immediate (value / var_idx / label_id / proto_idx / rt_blob_id)
 16       8   aux       secondary immediate (condition code / string length / loop step / arg count)
 24       4   flags     IR_FLAG_CONST | IR_FLAG_DEAD | IR_FLAG_SPILLED | IR_FLAG_LOOP_INV
 28       4   _pad      reserved (must be zero)
```

### Virtual registers

- 16-bit unsigned integers, allocated sequentially by `ir_alloc_vreg`
- No fixed limit (max 65535)
- Mapped to physical registers or spill slots by Pass 4

### Physical registers available

| ID | Register | Notes |
|----|----------|-------|
| 0 | rax | Implicit in mul/div; avoid for long-lived vars |
| 1 | rbx | Callee-saved |
| 2 | rcx | arg4 SysV |
| 3 | rdx | arg3 SysV; implicit in div |
| 4 | rsi | arg2 SysV |
| 5 | rdi | arg1 SysV |
| 6 | r8 | arg5 SysV |
| 7 | r9 | arg6 SysV |
| 8 | r10 | Caller-saved; free for temporaries |
| 9 | r11 | Caller-saved; free for temporaries |
| 10 | r12 | Callee-saved |
| 11 | r13 | Callee-saved |
| 12 | r14 | Reserved (type propagation / accumulator) |
| 13 | r15 | Reserved (loop pin) |

rsp and rbp reserved. r14 and r15 initially excluded from allocator.

### Label IDs

- 16-bit sequential integers allocated by `ir_alloc_label`
- Used by `IR_JMP`, `IR_JCC`, `IR_LABEL`
- Resolved to byte offsets during x86 emission

## [S5] Opcode Table

### Category 0 — No-op (0x00)

| Opcode | Value | Description |
|--------|-------|-------------|
| IR_NOP | 0x00 | Dead slot; produced by optimization; skipped by emission |

### Category 1 — Load / Store (0x01–0x0F)

| Opcode | Value | dst | src1 | src2 | imm | aux | Description |
|--------|-------|-----|------|------|-----|-----|-------------|
| IR_LOAD_IMM | 0x01 | v | — | — | integer value | — | `dst ← imm` |
| IR_LOAD_FIMM | 0x02 | v | — | — | float bits | — | `dst ← imm` (IEEE 754 double) |
| IR_LOAD_VAR | 0x03 | v | — | — | var_idx | — | `dst ← var_table[imm]` |
| IR_STORE_VAR | 0x04 | — | v | — | var_idx | — | `var_table[imm] ← src1` |
| IR_LOAD_STR | 0x05 | v | — | — | inline str ptr | str_len | `dst ← address of string` |
| IR_LOAD_BOOL | 0x06 | v | — | — | 0/1/2 | — | `dst ← false/true/unknown` |
| IR_RDRAND | 0x07 | v | — | — | — | — | `dst ← rdrand` |
| IR_LEA_VAR | 0x08 | v | — | — | var_idx | — | `dst ← address of var_table[imm]` |

### Category 2 — Integer Arithmetic (0x11–0x1F)

| Opcode | Value | dst | src1 | src2 | Description |
|--------|-------|-----|------|------|-------------|
| IR_ADD | 0x11 | v | v | v | `dst ← src1 + src2` |
| IR_SUB | 0x12 | v | v | v | `dst ← src1 - src2` |
| IR_MUL | 0x13 | v | v | v | `dst ← src1 * src2` |
| IR_DIV | 0x14 | v | v | v | `dst ← src1 / src2` (signed) |
| IR_MOD | 0x15 | v | v | v | `dst ← src1 % src2` |
| IR_NEG | 0x16 | v | v | — | `dst ← -src1` |
| IR_ABS | 0x17 | v | v | — | `dst ← abs(src1)` |
| IR_INC | 0x18 | v | v | — | `dst ← src1 + 1` |
| IR_DEC | 0x19 | v | v | — | `dst ← src1 - 1` |

### Category 3 — Float Arithmetic (0x21–0x2F)

| Opcode | Value | dst | src1 | src2 | Description |
|--------|-------|-----|------|------|-------------|
| IR_FADD | 0x21 | v | v | v | `dst ← src1 +f src2` |
| IR_FSUB | 0x22 | v | v | v | `dst ← src1 -f src2` |
| IR_FMUL | 0x23 | v | v | v | `dst ← src1 *f src2` |
| IR_FDIV | 0x24 | v | v | v | `dst ← src1 /f src2` |
| IR_FNEG | 0x25 | v | v | — | `dst ← -f src1` |
| IR_F2I | 0x26 | v | v | — | `dst ← int(src1)` (cvttsd2si) |
| IR_I2F | 0x27 | v | v | — | `dst ← float(src1)` (cvtsi2sd) |

### Category 4 — Bitwise (0x31–0x3F)

| Opcode | Value | dst | src1 | src2 | Description |
|--------|-------|-----|------|------|-------------|
| IR_BAND | 0x31 | v | v | v | `dst ← src1 & src2` |
| IR_BOR | 0x32 | v | v | v | `dst ← src1 \| src2` |
| IR_BXOR | 0x33 | v | v | v | `dst ← src1 ^ src2` |
| IR_BNOT | 0x34 | v | v | — | `dst ← ~src1` |
| IR_SHL | 0x35 | v | v | v | `dst ← src1 << src2` |
| IR_SHR | 0x36 | v | v | v | `dst ← src1 >> src2` (arithmetic) |

### Category 5 — Comparison and Boolean (0x41–0x4F)

| Opcode | Value | dst | src1 | src2 | aux | Description |
|--------|-------|-----|------|------|-----|-------------|
| IR_CMP | 0x41 | v | v | v | cond_code | `dst ← 1 if src1 <cond> src2 else 0` |
| IR_BOOL_AND | 0x42 | v | v | v | — | Short-circuit and |
| IR_BOOL_OR | 0x43 | v | v | v | — | Short-circuit or |
| IR_BOOL_NOT | 0x44 | v | v | — | — | `dst ← !src1` |

Condition codes (aux field of IR_CMP): 0===, 1=!=, 2=<, 3=>, 4=<=, 5=>=

### Category 6 — Control Flow (0x51–0x5F)

| Opcode | Value | dst | src1 | src2 | imm | aux | Description |
|--------|-------|-----|------|------|-----|-----|-------------|
| IR_LABEL | 0x51 | — | — | — | label_id | — | Define jump target |
| IR_JMP | 0x52 | — | — | — | label_id | — | Unconditional jump |
| IR_JCC | 0x53 | — | v | — | label_id | — | Jump if src1 == 0 |
| IR_CALL | 0x54 | v | — | — | proto_idx | arg_count | Call protocol |
| IR_RET | 0x55 | — | v | — | — | — | Return src1 |
| IR_RET_VOID | 0x56 | — | — | — | — | — | Void return |
| IR_LOOP_TOP | 0x57 | — | — | — | label_id | — | Loop back-edge target |
| IR_SKIP | 0x58 | — | — | — | depth | — | Continue Nth loop |

### Category 7 — Output / Runtime (0x61–0x6F)

| Opcode | Value | src1 | Description |
|--------|-------|------|-------------|
| IR_OUT_INT | 0x61 | v | Print int |
| IR_OUT_FLOAT | 0x62 | v | Print float |
| IR_OUT_BOOL | 0x63 | v | Print bool |
| IR_OUT_STR | 0x64 | v | Print string |
| IR_OUT_COMPLEX | 0x65 | v | Print complex |
| IR_ERR | 0x66 | v | Runtime error + halt |
| IR_HALT | 0x67 | — | sys_exit(0) |
| IR_MM_SWITCH | 0x68 | — | Switch allocator mode |

### Category 8 — Collection Operations (0x71–0x7F)

| Opcode | Value | dst | src1 | src2 | imm | Description |
|--------|-------|-----|------|------|-----|-------------|
| IR_SEQ_ALLOC | 0x71 | v | — | — | var_idx | Allocate seq |
| IR_SEQ_PUSH | 0x72 | — | v | — | var_idx | Push to seq |
| IR_SEQ_POP | 0x73 | v | — | — | var_idx | Pop from seq |
| IR_SEQ_LEN | 0x74 | v | — | — | var_idx | Length of seq |
| IR_SEQ_CAP | 0x75 | v | — | — | var_idx | Capacity of seq |
| IR_DICT_NEW | 0x76 | v | — | — | var_idx | Allocate dict |
| IR_DICT_SET | 0x77 | — | v | v | var_idx | Set dict[key]=val |
| IR_DICT_GET | 0x78 | v | v | — | var_idx | Get dict[key] |

### Category 9 — Swap / Misc (0x81–0x8F)

| Opcode | Value | imm | aux | Description |
|--------|-------|-----|-----|-------------|
| IR_SWAP | 0x81 | var_idx1 | var_idx2 | Swap two variables |
| IR_TYPEOF | 0x82 | var_idx | — | Type token of variable |

### Category 15 — Protocol Markers (0xF0–0xFF)

| Opcode | Value | imm | Description |
|--------|-------|-----|-------------|
| IR_PROT_ENTRY | 0xF0 | proto_idx | Start of protocol body |
| IR_PROT_EXIT | 0xF1 | proto_idx | End of protocol body |

## [S6] Optimization Passes

### Pass 1 — Constant Folding (after IR emission)

Linear scan. Maintain `vreg → constant` table (max 256 entries).

- `IR_LOAD_IMM` → record constant in table
- `IR_ADD/SUB/MUL/DIV/MOD` with both sources constant → replace with `IR_LOAD_IMM` of computed result
- `IR_NEG/ABS` with constant source → replace with `IR_LOAD_IMM`
- `IR_CMP` with both sources constant → replace with `IR_LOAD_IMM` (0 or 1)

### Pass 2 — Dead Store Elimination (after Pass 1)

Backward scan. For each `IR_STORE_VAR var_idx`:
- Scan forward from next record
- If another `IR_STORE_VAR` to same var found before any `IR_LOAD_VAR` of same var → first store is dead → `IR_NOP`

### Pass 3 — Load-Store Coalescing (after Pass 2)

Forward scan:
- `IR_LOAD_VAR v, x` immediately followed by `IR_STORE_VAR x, v` (same var, same vreg) → both `IR_NOP`
- `IR_LOAD_VAR v, x` followed by single-use `IR_OUT_*` using `v` → fuse into direct-from-memory output

### Pass 4 — Linear Scan Register Allocation (after Pass 3)

1. Compute live ranges: forward pass records `(start, end)` for each vreg
2. Sort vregs by start index
3. Assign physical registers using free-list of 14 GPRs
4. When all 14 occupied, spill vreg with furthest next-use to stack slot
5. Reserve r14 (accumulator) and r15 (loop pin) from allocator pool

Spill slots use `rsp`-relative addressing. Emission inserts `mov [rsp+slot], reg` / `mov reg, [rsp+slot]` at spill/reload points.

### Pass 5 — Peephole (after Pass 4, before x86 emission)

Pattern matching on adjacent IR records (repeat until stable):

| Pattern | Replacement |
|---------|-------------|
| Store x,v → Load v2,x (v2 first use) | Replace load with `IR_MOV v2,v`; NOP load |
| Load v,x → Output v (single use) | Fuse into direct-from-memory output |
| `IR_I2F` → `IR_F2I` | Eliminate both; redirect downstream uses |
| `IR_ADD` with constant 1 | Replace with `IR_INC` |
| `IR_SUB` with constant 1 | Replace with `IR_DEC` |
| `IR_MUL` with constant 2 | Replace with `IR_SHL` |

## [S7] Parser Wiring

### IR emission functions (in irgen/irgen.asm)

```
ir_emit_record(opcode, type, dst, src1, src2, imm, aux)  ; write 32-byte record
ir_alloc_vreg() → vreg_id                                  ; allocate next virtual register
ir_alloc_label() → label_id                                ; allocate next label ID
ir_emit_b(byte) / ir_emit_w(word) / ir_emit_d(dword) / ir_emit_q(qword)  ; raw emit within record
```

### Parser changes (in parser/parser.asm)

Replace every `call codegen_emit_*` with the corresponding `call ir_emit_*`. Key mappings:

| Parser call site | New IR emit call |
|---|---|
| `codegen_emit_mov_rax_imm64` | `ir_emit_load_imm` |
| `codegen_emit_mov_rax_var` | `ir_emit_load_var` |
| `codegen_emit_store_rax_to_var` | `ir_emit_store_var` |
| `codegen_emit_add_rax_rbx` | `ir_emit_add` |
| `codegen_emit_sub_rax_rbx` | `ir_emit_sub` |
| `codegen_emit_imul_rax_rbx` | `ir_emit_mul` |
| `codegen_emit_idiv_rbx_by_rax` | `ir_emit_div` |
| `codegen_emit_imod_rbx_by_rax` | `ir_emit_mod` |
| `codegen_emit_neg_rax` | `ir_emit_neg` |
| `codegen_emit_cmp_setcc` | `ir_emit_cmp` |
| `codegen_emit_and_bool` | `ir_emit_bool_and` |
| `codegen_emit_or_bool` | `ir_emit_bool_or` |
| `codegen_emit_not_rax` | `ir_emit_bool_not` |
| `codegen_output_int/float/bool/str/complex` | `ir_emit_out_int/float/bool/str/complex` |
| `codegen_emit_for_start/end` | `ir_emit_loop_top` + `ir_emit_jcc` + `ir_emit_jmp` |
| `codegen_emit_while_start/end` | `ir_emit_label` + `ir_emit_jcc` + `ir_emit_jmp` |
| `codegen_emit_break` | `ir_emit_jmp` |
| Protocol call setup | `ir_emit_call` |
| `return` | `ir_emit_ret` / `ir_emit_ret_void` |
| `codegen_emit_swap_vars` | `ir_emit_swap` |
| `codegen_emit_inc_var / dec_var` | `ir_emit_inc / ir_emit_dec` |

### Main entry point changes (in main/main.asm)

After parsing completes, before writing the binary:

```
1. call ir_optimize_pass1   ; constant folding
2. call ir_optimize_pass2   ; dead store elimination
3. call ir_optimize_pass3   ; load-store coalescing
4. call ir_optimize_pass4   ; register allocation
5. call ir_optimize_pass5   ; peephole
6. call ir_emit_x86         ; convert IR → x86 bytes into out_buffer
```

## [S8] Buffer Sizing

| Symbol | Value | Notes |
|--------|-------|-------|
| IR_MAX | 16384 | 16384 × 32 = 512 KiB |
| VREG_MAX | 65535 | 16-bit vreg field |
| LABEL_MAX | 4096 | 16-bit label IDs |
| SPILL_MAX | 64 | Max simultaneous spill slots |

## [S9] Implementation Phases

### Milestone A — IR Foundation (P1-P4)
Get IR working with zero optimization. All tests pass identically.

- **P1:** Write `include/rex_ir.inc` — all opcode constants and record field offsets
- **P2:** Write `irgen/irgen.asm` — `ir_emit_record`, `ir_alloc_vreg`, `ir_alloc_label`, `ir_reset`
- **P3:** Wire parser to call `ir_emit_*` helpers instead of `codegen_emit_*`; verify IR buffer populated correctly
- **P4:** Write `irgen/ir_emit_x86.asm` — x86 emission pass + label resolution; all tests pass

### Milestone B — Basic Optimizations (P5-P6)

- **P5:** Implement Pass 1 (constant folding); run against test suite
- **P6:** Implement Pass 2 (dead store) + Pass 3 (load-store coalescing)

### Milestone C — Advanced Optimizations (P7-P9)

- **P7:** Implement Pass 4 (linear scan register allocation)
- **P8:** Implement Pass 5 (peephole)
- **P9:** Benchmark: Rex-compiled output vs C at -O0

## [S10] Risk Analysis

**Risk 1: Test regression.** Current codegen has hand-tuned optimizations (O2-O27). IR must produce output at least as fast.
- Mitigation: Milestone A produces IR with zero optimization. All tests must pass identically before adding passes.

**Risk 2: CTPE interaction.** CTPE records its own IR for protocol constant-folding. Must continue working.
- Mitigation: CTPE is independent (`ctpe_ir_buf`). No changes needed.

**Risk 3: Register allocation constraints.** Current codebase uses r14 (accumulator), r15 (pin), r12 (proto params).
- Mitigation: Reserve r14 and r15 from allocator pool initially. Optimize later.

**Risk 4: Label resolution complexity.** Forward jumps in loops, if/elif/else chains, and protocol calls need correct patching.
- Mitigation: Reuse existing patch-stack concept but operate on label IDs. Each label ID maps to exactly one `IR_LABEL` record.

## [S11] Scope Boundary

**In scope:**
- IR buffer, emitter, 5 optimization passes, x86 emission
- All existing features continue working

**Out of scope:**
- New language features
- Changes to CTPE system
- Removal of existing peephole optimizations (O2-O27) during this work
