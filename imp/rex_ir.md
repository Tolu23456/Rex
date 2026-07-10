# Rex IR — Intermediate Representation Specification

**Status:** Design document — not yet implemented  
**Purpose:** Replace direct byte emission in `codegen.asm` with a structured IR
layer that enables optimization passes, register allocation, and faster compiled output.

---

## 1. Motivation

The current Rex compiler emits raw x86-64 machine bytes directly from the parser.
Every variable load is a `mov rax, [VAR_STORAGE_BASE + idx*64]`, every binary
operation pushes and pops through memory.  There is no register allocation, no
constant folding, no dead-store elimination.  A program like:

```rex
int x = 3
int y = 4
int z
:z = x + y
output z
```

currently compiles to roughly:

```
mov qword [0x440000 + 0*64], 3     ; store x
mov qword [0x440000 + 1*64], 4     ; store y
mov rax, [0x440000 + 0*64]         ; load x
push rax
mov rax, [0x440000 + 1*64]         ; load y
pop rbx
add rax, rbx
mov [0x440000 + 2*64], rax         ; store z
mov rax, [0x440000 + 2*64]         ; load z again
mov rdi, rax
call rt_pri
```

With a Rex IR layer and a constant-folding pass, this entire block reduces to:

```
mov rdi, 7
call rt_pri
```

The IR layer sits between the parser and final byte emission.  The parser writes
IR records instead of machine bytes.  Optimization passes transform the IR.
A final x86 emission pass converts IR to machine code.

---

## 2. Pipeline (New)

```
source.rex
    │
    ▼
[ lexer + parser ]         unchanged — still produces the same parse events
    │
    ▼  writes IR records
[ ir_buffer ]              fixed-size 32-byte records, up to IR_MAX entries
    │
    ▼
[ Pass 1: Constant Fold ]  evaluate compile-time constant expressions → IR_NOP
[ Pass 2: Dead Store ]     eliminate stores never read → IR_NOP
[ Pass 3: Load Coalesce ]  collapse adjacent load/store of same var → IR_NOP
[ Pass 4: Reg Allocate ]   map virtual registers → physical registers / spill slots
[ Pass 5: Peephole ]       collapse adjacent instruction pairs (push+pop, etc.)
    │
    ▼
[ x86 emission pass ]      convert IR records to machine bytes into out_buffer
    │
    ▼
[ headers + runtime ]      unchanged
    │
    ▼
  ELF binary
```

---

## 3. IR Record Layout

Each IR instruction is exactly **32 bytes**.  The buffer is a flat array of
these records (`ir_buffer resb IR_MAX * 32`).  A single `ir_idx` counter
(qword) tracks the next free record slot.

```
offset  size  field     description
──────  ────  ────────  ────────────────────────────────────────────────────────
  0       1   opcode    IR_* constant (see Section 5)
  1       1   type      TYPE_* constant: result type of this instruction
  2       2   dst       destination virtual register (0 = no destination)
  4       2   src1      first source virtual register (0 = unused)
  6       2   src2      second source virtual register (0 = unused)
  8       8   imm       immediate: integer/float bits / var_idx / label_id /
                        proto_idx / rt_blob_id depending on opcode
 16       8   aux       auxiliary immediate: condition code / string length /
                        loop step / second var_idx / arg count
 24       4   flags     IR_FLAG_* bitmask (see Section 6)
 28       4   _pad      reserved — must be zero
──────  ────  ────────  ────────────────────────────────────────────────────────
                        total: 32 bytes per record
```

### Field summary

| Field  | Width | Notes |
|--------|-------|-------|
| opcode | 1 B   | Up to 256 distinct operations |
| type   | 1 B   | TYPE_INT / TYPE_FLOAT / TYPE_BOOL / TYPE_COMPLEX / TYPE_STR / TYPE_SEQ / TYPE_DICT / TYPE_VOID |
| dst    | 2 B   | Virtual register number; 0 = none |
| src1   | 2 B   | Virtual register number; 0 = none |
| src2   | 2 B   | Virtual register number; 0 = none |
| imm    | 8 B   | Primary immediate; interpretation depends on opcode |
| aux    | 8 B   | Secondary immediate; interpretation depends on opcode |
| flags  | 4 B   | Metadata flags (const-folded, spilled, etc.) |
| _pad   | 4 B   | Reserved |

---

## 4. Virtual Registers

Virtual registers (vregs) are 16-bit unsigned integers allocated sequentially
by the IR emitter.  A single counter (`vreg_counter`) is incremented each time
a new temporary is needed.  There is no fixed limit — the allocator maps them
to physical registers or spill slots in Pass 4.

| Range    | Meaning |
|----------|---------|
| 0        | No register (void / unused field) |
| 1–65535  | User virtual registers |

The IR emitter in the parser calls `ir_alloc_vreg` to obtain the next free vreg.
The allocator in Pass 4 maps each vreg to one of the 14 general-purpose physical
registers, or to a spill slot on the stack.

### Physical registers available for allocation

| Phys ID | Register | Notes |
|---------|----------|-------|
| 0       | rax      | Implicit in mul/div; avoid for long-lived vars |
| 1       | rbx      | Callee-saved — save/restore across protocol calls |
| 2       | rcx      | arg4 in SysV ABI |
| 3       | rdx      | arg3 in SysV ABI; implicit in div |
| 4       | rsi      | arg2 in SysV ABI |
| 5       | rdi      | arg1 in SysV ABI |
| 6       | r8       | arg5 in SysV ABI |
| 7       | r9       | arg6 in SysV ABI |
| 8       | r10      | Caller-saved; free for temporaries |
| 9       | r11      | Caller-saved; free for temporaries |
| 10      | r12      | Callee-saved |
| 11      | r13      | Callee-saved |
| 12      | r14      | Callee-saved — used by type-propagation; avoid |
| 13      | r15      | Callee-saved |

rsp and rbp are reserved.  r14 is currently used internally for type
propagation in `parse_additive`; avoid assigning user vregs to it until
type propagation is moved into the IR.

---

## 5. Label IDs

Control-flow instructions (`IR_JMP`, `IR_JCC`, `IR_LABEL`) use the `imm`
field to store a **label ID** — a 16-bit sequential integer.  The IR emitter
calls `ir_alloc_label` to obtain a fresh ID.  During the x86 emission pass,
a label-resolution table maps each ID to its byte offset in `out_buffer`.
Forward jumps are patched after the emission pass completes (same mechanism
as the current `jump_patch_stack`, but operating over label IDs rather than
raw buffer positions).

---

## 6. Opcode Table

Opcodes are grouped into 16 categories, each occupying a range of 16 values.

### Type constants (reused from `rex_defs.inc`)

```
TYPE_VOID    equ 0
TYPE_INT     equ 1
TYPE_FLOAT   equ 2
TYPE_BOOL    equ 3
TYPE_COMPLEX equ 4
TYPE_STR     equ 5
TYPE_SEQ     equ 6
TYPE_DICT    equ 7
```

---

### Category 0 — No-op (0x00)

| Opcode   | Value | dst | src1 | src2 | imm | aux | Description |
|----------|-------|-----|------|------|-----|-----|-------------|
| IR_NOP   | 0x00  | —   | —    | —    | —   | —   | Dead slot — produced by optimization passes; ignored by emission pass |

---

### Category 1 — Load / Store (0x01–0x0F)

| Opcode       | Value | dst | src1 | src2 | imm              | aux        | Description |
|--------------|-------|-----|------|------|------------------|------------|-------------|
| IR_LOAD_IMM  | 0x01  | v   | —    | —    | integer value    | —          | `dst ← imm` |
| IR_LOAD_FIMM | 0x02  | v   | —    | —    | float bits       | —          | `dst ← imm` (64-bit IEEE 754 double) |
| IR_LOAD_VAR  | 0x03  | v   | —    | —    | var_idx          | —          | `dst ← var_table[imm]` |
| IR_STORE_VAR | 0x04  | —   | v    | —    | var_idx          | —          | `var_table[imm] ← src1` |
| IR_LOAD_STR  | 0x05  | v   | —    | —    | inline str ptr   | str_len    | `dst ← address of inline string` |
| IR_LOAD_BOOL | 0x06  | v   | —    | —    | 0/1/2            | —          | `dst ← false/true/unknown` (2 triggers rdrand) |
| IR_RDRAND    | 0x07  | v   | —    | —    | —                | —          | `dst ← rdrand` (hardware entropy) |
| IR_LEA_VAR   | 0x08  | v   | —    | —    | var_idx          | —          | `dst ← address of var_table[imm]` (for complex / seq output) |

---

### Category 2 — Integer Arithmetic (0x11–0x1F)

| Opcode   | Value | dst | src1 | src2 | imm | aux | Description |
|----------|-------|-----|------|------|-----|-----|-------------|
| IR_ADD   | 0x11  | v   | v    | v    | —   | —   | `dst ← src1 + src2` |
| IR_SUB   | 0x12  | v   | v    | v    | —   | —   | `dst ← src1 - src2` |
| IR_MUL   | 0x13  | v   | v    | v    | —   | —   | `dst ← src1 * src2` |
| IR_DIV   | 0x14  | v   | v    | v    | —   | —   | `dst ← src1 / src2` (signed) |
| IR_MOD   | 0x15  | v   | v    | v    | —   | —   | `dst ← src1 % src2` |
| IR_NEG   | 0x16  | v   | v    | —    | —   | —   | `dst ← -src1` |
| IR_ABS   | 0x17  | v   | v    | —    | —   | —   | `dst ← abs(src1)` |
| IR_INC   | 0x18  | v   | v    | —    | —   | —   | `dst ← src1 + 1` → maps to `inc` |
| IR_DEC   | 0x19  | v   | v    | —    | —   | —   | `dst ← src1 - 1` → maps to `dec` |

---

### Category 3 — Float Arithmetic (0x21–0x2F)

| Opcode   | Value | dst | src1 | src2 | imm | aux | Description |
|----------|-------|-----|------|------|-----|-----|-------------|
| IR_FADD  | 0x21  | v   | v    | v    | —   | —   | `dst ← src1 +f src2` (addsd) |
| IR_FSUB  | 0x22  | v   | v    | v    | —   | —   | `dst ← src1 -f src2` (subsd) |
| IR_FMUL  | 0x23  | v   | v    | v    | —   | —   | `dst ← src1 *f src2` (mulsd) |
| IR_FDIV  | 0x24  | v   | v    | v    | —   | —   | `dst ← src1 /f src2` (divsd) |
| IR_FNEG  | 0x25  | v   | v    | —    | —   | —   | `dst ← -f src1` |
| IR_F2I   | 0x26  | v   | v    | —    | —   | —   | `dst ← int(src1)` (cvttsd2si — truncates toward zero) |
| IR_I2F   | 0x27  | v   | v    | —    | —   | —   | `dst ← float(src1)` (cvtsi2sd) |

---

### Category 4 — Bitwise (0x31–0x3F)

| Opcode   | Value | dst | src1 | src2 | imm | aux | Description |
|----------|-------|-----|------|------|-----|-----|-------------|
| IR_BAND  | 0x31  | v   | v    | v    | —   | —   | `dst ← src1 & src2` |
| IR_BOR   | 0x32  | v   | v    | v    | —   | —   | `dst ← src1 \| src2` |
| IR_BXOR  | 0x33  | v   | v    | v    | —   | —   | `dst ← src1 ^ src2` |
| IR_BNOT  | 0x34  | v   | v    | —    | —   | —   | `dst ← ~src1` |
| IR_SHL   | 0x35  | v   | v    | v    | —   | —   | `dst ← src1 << src2` |
| IR_SHR   | 0x36  | v   | v    | v    | —   | —   | `dst ← src1 >> src2` |

---

### Category 5 — Comparison and Boolean (0x41–0x4F)

| Opcode      | Value | dst | src1 | src2 | imm | aux      | Description |
|-------------|-------|-----|------|------|-----|----------|-------------|
| IR_CMP      | 0x41  | v   | v    | v    | —   | cond_code | `dst ← 1 if src1 <cond> src2 else 0`; aux = condition code (see Section 7) |
| IR_BOOL_AND | 0x42  | v   | v    | v    | —   | —        | `dst ← src1 && src2` (short-circuit: skip src2 eval if src1 false) |
| IR_BOOL_OR  | 0x43  | v   | v    | v    | —   | —        | `dst ← src1 \|\| src2` (short-circuit: skip src2 eval if src1 true) |
| IR_BOOL_NOT | 0x44  | v   | v    | —    | —   | —        | `dst ← !src1` → `xor rax, 1` |

---

### Category 6 — Control Flow (0x51–0x5F)

| Opcode      | Value | dst | src1 | src2 | imm        | aux       | Description |
|-------------|-------|-----|------|------|------------|-----------|-------------|
| IR_LABEL    | 0x51  | —   | —    | —    | label_id   | —         | Define a jump target |
| IR_JMP      | 0x52  | —   | —    | —    | label_id   | —         | Unconditional jump |
| IR_JCC      | 0x53  | —   | v    | —    | label_id   | —         | Jump if src1 == 0 (false) |
| IR_CALL     | 0x54  | v   | —    | —    | proto_idx  | arg_count | Call protocol; args are on the stack in SysV order |
| IR_RET      | 0x55  | —   | v    | —    | —          | —         | Return src1 value from protocol |
| IR_RET_VOID | 0x56  | —   | —    | —    | —          | —         | Void return |
| IR_LOOP_TOP | 0x57  | —   | —    | —    | label_id   | —         | Loop back-edge target (allows optimizer to identify loops) |
| IR_SKIP     | 0x58  | —   | —    | —    | depth      | —         | Break N loop levels (imm = N; 1 = innermost) |

---

### Category 7 — Output / Runtime (0x61–0x6F)

| Opcode          | Value | dst | src1 | src2 | imm | aux | Description |
|-----------------|-------|-----|------|------|-----|-----|-------------|
| IR_OUT_INT      | 0x61  | —   | v    | —    | —   | —   | Print int (call rt_pri_blob) |
| IR_OUT_FLOAT    | 0x62  | —   | v    | —    | —   | —   | Print float (call rt_prf_blob) |
| IR_OUT_BOOL     | 0x63  | —   | v    | —    | —   | —   | Print bool (call rt_prb_blob) |
| IR_OUT_STR      | 0x64  | —   | v    | —    | —   | —   | Print string (call rt_prs_blob) |
| IR_OUT_COMPLEX  | 0x65  | —   | v    | —    | —   | —   | Print complex (call rt_prc_blob; passes address) |
| IR_ERR          | 0x66  | —   | v    | —    | —   | —   | Runtime error + halt (call rt_err_blob) |
| IR_HALT         | 0x67  | —   | —    | —    | —   | —   | sys_exit(0) |
| IR_MM_SWITCH    | 0x68  | —   | —    | —    | mode| —   | Switch allocator mode (0=arena, 1=pool) |

---

### Category 8 — Collection Operations (0x71–0x7F)

| Opcode       | Value | dst | src1 | src2 | imm      | aux | Description |
|--------------|-------|-----|------|------|----------|-----|-------------|
| IR_SEQ_ALLOC | 0x71  | v   | —    | —    | var_idx  | —   | Allocate new seq; `dst` receives heap ptr; also stored to var |
| IR_SEQ_PUSH  | 0x72  | —   | v    | —    | var_idx  | —   | Push src1 onto seq at var_idx |
| IR_SEQ_POP   | 0x73  | v   | —    | —    | var_idx  | —   | `dst ← pop` from seq at var_idx |
| IR_SEQ_LEN   | 0x74  | v   | —    | —    | var_idx  | —   | `dst ← len` of seq at var_idx |
| IR_SEQ_CAP   | 0x75  | v   | —    | —    | var_idx  | —   | `dst ← cap` of seq at var_idx |
| IR_DICT_NEW  | 0x76  | v   | —    | —    | var_idx  | —   | Allocate new dict |
| IR_DICT_SET  | 0x77  | —   | v    | v    | var_idx  | —   | `dict[var_idx][src1_key] ← src2_val` |
| IR_DICT_GET  | 0x78  | v   | v    | —    | var_idx  | —   | `dst ← dict[var_idx][src1_key]` |

---

### Category 9 — Swap / Misc (0x81–0x8F)

| Opcode      | Value | dst | src1 | src2 | imm      | aux      | Description |
|-------------|-------|-----|------|------|----------|----------|-------------|
| IR_SWAP     | 0x81  | —   | —    | —    | var_idx1 | var_idx2 | Swap two variables in-place via xchg |
| IR_TYPEOF   | 0x82  | v   | —    | —    | var_idx  | —        | `dst ← type token of var_idx` (compile-time constant) |

---

### Category 15 — Protocol Markers (0xF0–0xFF)

| Opcode        | Value | imm       | Description |
|---------------|-------|-----------|-------------|
| IR_PROT_ENTRY | 0xF0  | proto_idx | Marks start of a protocol body; used by allocator to reset live-set |
| IR_PROT_EXIT  | 0xF1  | proto_idx | Marks end of a protocol body |

---

## 7. Condition Codes (aux field of IR_CMP)

| Code | Meaning | x86 instruction |
|------|---------|-----------------|
| 0    | ==      | sete            |
| 1    | !=      | setne           |
| 2    | <       | setl            |
| 3    | >       | setg            |
| 4    | <=      | setle           |
| 5    | >=      | setge           |

---

## 8. Flags Field

| Bit | Name              | Meaning |
|-----|-------------------|---------|
| 0   | IR_FLAG_CONST     | Result is a compile-time constant; value is in `imm` (set by constant-folding pass) |
| 1   | IR_FLAG_DEAD      | Instruction has no live readers; emit as IR_NOP (set by dead-store pass) |
| 2   | IR_FLAG_SPILLED   | dst vreg was spilled to stack by register allocator |
| 3   | IR_FLAG_LOOP_INV  | Instruction is loop-invariant; candidate for hoisting |

---

## 9. Optimization Passes

Passes operate over the flat `ir_buffer` array.  Each pass scans linearly,
reads records, and either rewrites them in-place or appends to a scratch buffer
that becomes the new `ir_buffer`.  Passes are cheap enough to run at compile
time — the buffer is at most `IR_MAX * 32` bytes in memory.

---

### Pass 1 — Constant Folding

**When:** After IR emission, before any other pass.

**Algorithm:** Linear scan.  Maintain a small table of `vreg → constant value`
pairs (sized to the number of active vregs, max 256 entries at any one time).

```
for each record r in ir_buffer:
    if r.opcode == IR_LOAD_IMM:
        const_table[r.dst] = r.imm
        r.flags |= IR_FLAG_CONST
    elif r.opcode in {IR_ADD, IR_SUB, IR_MUL, IR_DIV, IR_MOD}:
        if const_table[r.src1] is known AND const_table[r.src2] is known:
            result = eval(r.opcode, const_table[r.src1], const_table[r.src2])
            replace r with IR_LOAD_IMM dst=r.dst imm=result flags=IR_FLAG_CONST
            NOP the IR_LOAD_IMM records for src1 and src2 if they have no
            other live readers
    elif r.opcode in {IR_NEG, IR_ABS}:
        if const_table[r.src1] is known:
            result = eval(r.opcode, const_table[r.src1])
            replace r with IR_LOAD_IMM dst=r.dst imm=result
```

**Example:**

```
IR_LOAD_IMM  v1, 3        →  IR_NOP
IR_LOAD_IMM  v2, 4        →  IR_NOP
IR_ADD       v3, v1, v2   →  IR_LOAD_IMM v3, 7
IR_OUT_INT   v3           →  IR_OUT_INT  v3    (unchanged; uses folded v3)
```

**Savings:** Eliminates entire expression trees for constant-only programs.
A constant `int x = 42; output x` becomes a single `mov edi, 42; call rt_pri`.

---

### Pass 2 — Dead Store Elimination

**When:** After Pass 1.

**Algorithm:** Backward scan.  For each `IR_STORE_VAR var_idx`:
- Scan forward from the next record.
- If another `IR_STORE_VAR` to the same `var_idx` is found before any
  `IR_LOAD_VAR` of the same `var_idx`, the first store is dead.
- Replace the first store with `IR_NOP`.

```
for i from len(ir_buffer)-1 down to 0:
    r = ir_buffer[i]
    if r.opcode != IR_STORE_VAR: continue
    var = r.imm
    for j from i+1 to len(ir_buffer)-1:
        if ir_buffer[j].opcode == IR_LOAD_VAR and ir_buffer[j].imm == var:
            break   ; variable is read — store is live
        if ir_buffer[j].opcode == IR_STORE_VAR and ir_buffer[j].imm == var:
            ir_buffer[i] = IR_NOP   ; first store is dead
            break
```

**Example:**

```
IR_STORE_VAR  x, v1   →  IR_NOP         (overwritten before read)
IR_STORE_VAR  x, v2   →  IR_STORE_VAR x, v2   (kept)
IR_LOAD_VAR   v3, x
```

---

### Pass 3 — Load-Store Coalescing

**When:** After Pass 2.

**Algorithm:** Scan for `IR_LOAD_VAR dst, idx` immediately followed by
`IR_STORE_VAR idx, dst` where both refer to the same variable and same vreg.
This is a self-assignment no-op.  Replace both with `IR_NOP`.

Also coalesce: `IR_LOAD_VAR v, x` followed by `IR_OUT_*` using `v` — if `v`
is used only once (just in this output), the load can be folded directly into
the output instruction, saving one register pressure slot.

---

### Pass 4 — Linear Scan Register Allocation

**When:** After Pass 3.  This is the most significant pass.

**Overview:** Map virtual registers (vregs) to physical registers.  When all
14 physical registers are in use, spill the vreg with the furthest next-use
to a stack slot.

**Data structures:**
- `live_ranges[vreg]` — (start_idx, end_idx) of each vreg's live range
- `phys_map[vreg]` — assigned physical register ID (0–13), or 0xFF = spilled
- `active[]` — sorted list of vregs currently assigned to a physical register
- `free_regs` — bitmask of available physical registers

**Algorithm (standard linear scan):**

```
; Phase A: compute live ranges (single forward pass)
for i, r in enumerate(ir_buffer):
    if r.dst  != 0: live_ranges[r.dst].start  = min(live_ranges[r.dst].start, i)
    if r.src1 != 0: live_ranges[r.src1].end   = max(live_ranges[r.src1].end, i)
    if r.src2 != 0: live_ranges[r.src2].end   = max(live_ranges[r.src2].end, i)

; Phase B: assign physical registers
sort vregs by live_ranges[v].start ascending
for each vreg v in sorted order:
    expire_old_intervals(v)          ; free physical regs whose live range ended
    if len(active) == 14:
        spill_at_interval(v)         ; spill vreg with furthest end
    else:
        phys_map[v] = pick_free_reg()
        add v to active (sorted by live_ranges[v].end)
```

**Spill slots:** When a vreg is spilled, `phys_map[v] = 0xFF` and a stack
offset is assigned (`spill_slot[v] = rsp_offset`).  The emission pass emits
`mov [rsp + offset], reg` and `mov reg, [rsp + offset]` at spill/reload points.

**Register preference:** Assign `rax` last (reserved for mul/div operands).
Prefer `r10`–`r15` for long-lived loop variables.  Never assign `r14` (used
by type propagation) until type propagation is moved into the IR.

---

### Pass 5 — Peephole

**When:** After Pass 4, before x86 emission.

**Rules applied in order (repeat until no changes):**

| Pattern | Replacement |
|---------|-------------|
| `IR_STORE_VAR x, v` followed by `IR_LOAD_VAR v2, x` where v2 is first use of the loaded value | Replace load with `IR_MOV v2, v`; NOP the load |
| `IR_LOAD_VAR v, x` immediately followed by `IR_OUT_INT v` where `v` is live nowhere else | Fuse into `IR_OUT_INT_VAR x` (direct from memory) |
| `IR_I2F v2, v1` followed by `IR_F2I v3, v2` | Replace both with `IR_NOP`; replace downstream uses of v3 with v1 |
| `IR_ADD dst, src, imm_1` where imm_1 is IR_LOAD_IMM 1 | Replace with `IR_INC dst, src` |
| `IR_SUB dst, src, imm_1` where imm_1 is IR_LOAD_IMM 1 | Replace with `IR_DEC dst, src` |
| `IR_MUL dst, src, imm_2` where imm_2 is IR_LOAD_IMM 2 | Replace with `IR_SHL dst, src, 1` |

---

## 10. x86 Emission Map

After all passes, the emission pass walks the IR records and emits machine bytes.
Records with `opcode == IR_NOP` are silently skipped.  This table shows how each
IR opcode maps to x86-64 encoding.

| IR Opcode       | x86-64 Encoding |
|-----------------|-----------------|
| IR_LOAD_IMM     | `mov rdst, imm64` or `xor rdst, rdst` if imm=0 |
| IR_LOAD_VAR     | `mov rdst, [VAR_BASE + var_idx*64]` |
| IR_STORE_VAR    | `mov [VAR_BASE + var_idx*64], rsrc1` |
| IR_LOAD_BOOL(0) | `xor rdst, rdst` |
| IR_LOAD_BOOL(1) | `mov rdst, 1` |
| IR_LOAD_BOOL(2) | `rdrand rdst; and rdst, 1` |
| IR_RDRAND       | `rdrand rdst` |
| IR_ADD          | `mov rdst, rsrc1; add rdst, rsrc2` |
| IR_SUB          | `mov rdst, rsrc1; sub rdst, rsrc2` |
| IR_MUL          | `mov rax, rsrc1; imul rax, rsrc2; mov rdst, rax` |
| IR_DIV          | `mov rax, rsrc1; cqo; idiv rsrc2; mov rdst, rax` |
| IR_MOD          | `mov rax, rsrc1; cqo; idiv rsrc2; mov rdst, rdx` |
| IR_NEG          | `mov rdst, rsrc1; neg rdst` |
| IR_ABS          | `mov rdst, rsrc1; mov tmp, rdst; neg tmp; cmovns rdst, rdst` |
| IR_INC          | `mov rdst, rsrc1; inc rdst` |
| IR_DEC          | `mov rdst, rsrc1; dec rdst` |
| IR_FADD         | `movq xmm0, rsrc1; movq xmm1, rsrc2; addsd xmm0, xmm1; movq rdst, xmm0` |
| IR_BAND         | `mov rdst, rsrc1; and rdst, rsrc2` |
| IR_BOR          | `mov rdst, rsrc1; or rdst, rsrc2` |
| IR_BXOR         | `mov rdst, rsrc1; xor rdst, rsrc2` |
| IR_BNOT         | `mov rdst, rsrc1; not rdst` |
| IR_SHL          | `mov rdst, rsrc1; mov rcx, rsrc2; shl rdst, cl` |
| IR_SHR          | `mov rdst, rsrc1; mov rcx, rsrc2; sar rdst, cl` |
| IR_CMP          | `cmp rsrc1, rsrc2; setCC al; movzx rdst, al` (CC from cond_code) |
| IR_BOOL_NOT     | `mov rdst, rsrc1; xor rdst, 1` |
| IR_JMP          | `jmp [label_id resolved]` |
| IR_JCC          | `test rsrc1, rsrc1; jz [label_id resolved]` |
| IR_LABEL        | Emit no bytes; record current `out_idx` in label table |
| IR_CALL         | Emit arg pops + `call [proto VA]` |
| IR_RET          | `mov rax, rsrc1; ret` |
| IR_RET_VOID     | `ret` |
| IR_OUT_INT      | `mov rdi, rsrc1; call rt_pri_blob` |
| IR_OUT_FLOAT    | `movq xmm0, rsrc1; call rt_prf_blob` |
| IR_OUT_BOOL     | `mov rdi, rsrc1; call rt_prb_blob` |
| IR_OUT_STR      | `mov rdi, rsrc1; call rt_prs_blob` |
| IR_OUT_COMPLEX  | `lea rdi, [var_addr]; call rt_prc_blob` |
| IR_ERR          | `mov rdi, rsrc1; call rt_err_blob` |
| IR_HALT         | `mov eax, 60; xor edi, edi; syscall` |
| IR_MM_SWITCH    | `mov qword [rt_alc_mode], imm` |
| IR_SEQ_ALLOC    | `mov edi, 80; call rt_alc_blob; mov [var_addr], rax` |
| IR_SEQ_PUSH     | `mov rbx, [var_addr]; mov rcx, [rbx+8]; mov [rbx+rcx*8+16], rsrc1; inc qword [rbx+8]` |
| IR_SEQ_POP      | `mov rbx, [var_addr]; dec qword [rbx+8]; mov rcx, [rbx+8]; mov rdst, [rbx+rcx*8+16]` |
| IR_SEQ_LEN      | `mov rbx, [var_addr]; mov rdst, [rbx+8]` |
| IR_SEQ_CAP      | `mov rbx, [var_addr]; mov rdst, [rbx+0]` |
| IR_SWAP         | `mov rax, [var1_addr]; mov rbx, [var2_addr]; xchg rax, rbx; mov [var1_addr], rax; mov [var2_addr], rbx` |

---

## 11. Buffer Sizing

| Symbol       | Recommended value | Notes |
|--------------|-------------------|-------|
| `IR_MAX`     | 16384             | 16384 × 32 = 512 KiB; enough for any Rex program |
| `VREG_MAX`   | 65535             | 16-bit vreg field |
| `LABEL_MAX`  | 4096              | 16-bit label IDs; 4096 forward-jump targets |
| `SPILL_MAX`  | 64                | Maximum simultaneous spill slots (rsp-relative) |

---

## 12. New Files

| File                  | Contents |
|-----------------------|----------|
| `irgen/irgen.asm`     | IR record emitter: `ir_emit`, `ir_alloc_vreg`, `ir_alloc_label` |
| `irgen/ir_passes.asm` | Optimization passes 1–5 |
| `irgen/ir_emit_x86.asm` | x86 emission pass + label resolution |
| `include/rex_ir.inc`  | IR opcode constants, record offsets, flag constants |

`codegen/codegen.asm` becomes the **x86 emission pass only** — its current
direct-byte-emitter functions are replaced by their IR equivalents.  The parser
calls `ir_emit_*` functions instead of `codegen_emit_*`.  The top-level
`main.asm` runs all passes after parsing is complete, then calls the x86
emission pass.

---

## 13. Implementation Roadmap

| Phase | Work | Deliverable |
|-------|------|-------------|
| **P1** | Define `include/rex_ir.inc` with all opcode constants and record field offsets | Shared include file |
| **P2** | Write `irgen/irgen.asm`: `ir_emit` (writes one 32-byte record), `ir_alloc_vreg`, `ir_alloc_label`, `ir_reset` | IR emitter |
| **P3** | Wire parser to call `ir_emit_*` helpers instead of `codegen_emit_*`; verify IR buffer is populated correctly | Parser emits IR |
| **P4** | Write x86 emission pass in `irgen/ir_emit_x86.asm`; all tests pass with no optimization yet | Correct output via IR |
| **P5** | Implement Pass 1 (constant folding); run against test suite | First speedup |
| **P6** | Implement Pass 2 (dead store) and Pass 3 (load coalesce) | Cleaner emission |
| **P7** | Implement Pass 4 (linear scan register allocation) | Major speedup |
| **P8** | Implement Pass 5 (peephole) | Binary size reduction |
| **P9** | Benchmark: Rex-compiled output vs equivalent C at -O0 | Baseline comparison |

All work must comply with **Rule L-1** — every file in `irgen/` is pure
x86-64 NASM assembly.
