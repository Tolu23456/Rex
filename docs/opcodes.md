# Rex V5.0 — Machine-Code Emit Reference

This file is a **reverse lookup**: for every Rex language construct, it shows
the exact byte sequence the compiler writes into `out_buffer`.

All values are derived directly from `codegen/codegen.asm` and
`include/rex_defs.inc`. Nothing here is estimated or approximated.

Notation used throughout:
```
<addr32>  — 4-byte little-endian absolute address of a var_table slot
<imm32>   — 4-byte little-endian signed immediate
<imm64>   — 8-byte little-endian signed immediate
<rel32>   — 4-byte little-endian PC-relative displacement (relative to next instr)
<setCC>   — 1-byte setCC opcode (see comparison table)
```

---

## 1. Address and Memory Model

```
LOAD_BASE        = 0x00400000   (4 194 304)
VAR_STORAGE_BASE = 0x00440000   (4 456 448)
VAR_ENTRY_SIZE   = 64           (bytes per variable slot)
VAR_MAX          = 256          (maximum variables per compilation unit)
PROTO_ENTRY_SIZE = 48           (bytes per protocol slot)
HEADERS_SIZE     = 120          (64-byte ELF header + 56-byte program header)
RT_TOTAL_SIZE    = 8448         (total runtime blob bytes)
CODE_START       = 8573         (byte offset in output file where user code begins)
```

### Variable Address Formula

```
var_addr(idx) = (idx << 6) + VAR_STORAGE_BASE
             = idx * 64 + 0x00440000
```

`var_addr` fits in 32 bits for all valid indices (0–255).

### Absolute-Address Memory Encoding

Rex accesses variables using the SIB no-base form (`ModRM=04/3C/…, SIB=25`):

| Bytes | Assembly |
|---|---|
| `48 8B 04 25` `<addr32>` | `mov rax, [addr32]` |
| `48 89 04 25` `<addr32>` | `mov [addr32], rax` |
| `48 8B 1C 25` `<addr32>` | `mov rbx, [addr32]` |
| `48 89 1C 25` `<addr32>` | `mov [addr32], rbx` |
| `48 8B 3C 25` `<addr32>` | `mov rdi, [addr32]` |
| `48 89 3C 25` `<addr32>` | `mov [addr32], rdi` |
| `48 81 3C 25` `<addr32>` `<imm32>` | `cmp qword [addr32], imm32` |
| `48 FF 04 25` `<addr32>` | `inc qword [addr32]` |
| `48 FF 0C 25` `<addr32>` | `dec qword [addr32]` |

---

## 2. Internal Emit Helpers (codegen.asm, not emitted into output)

These are compiler-internal routines in the compiler binary itself — they write
bytes into `out_buffer` but are **not** present in the compiled output.

| Routine | Action |
|---|---|
| `emit_b` | append `al` (1 byte) to `out_buffer[out_idx]`; increment `out_idx` by 1; exits with code 1 on overflow (> 131071 bytes) |
| `emit_d` | append `eax` (4 bytes) to `out_buffer[out_idx]`; increment `out_idx` by 4 |
| `emit_q` | append `rax` (8 bytes) to `out_buffer[out_idx]`; increment `out_idx` by 8 |
| `emit_blob` | `rep movsb` copy `rcx` bytes from `rsi` into `out_buffer + out_idx`; increment `out_idx` by `rcx` |

---

## 3. Program Prologue / Epilogue

### File Layout (bytes 0–8572 in output)

```
Offset    Size    Content
──────    ────    ───────────────────────────────────────────────────────────
0         64      ELF64 header  (from `elf_header` in codegen/)
64        56      PT_LOAD program header  (from `program_header`)
120        5      JMP over runtime:  E9 <RT_TOTAL_SIZE:imm32>
125      512      rt_pri_blob   (int printer)
637      512      rt_prs_blob   (string printer)
1149     256      rt_prb_blob   (bool printer)
1405     512      rt_prf_blob   (float printer)
1917     512      rt_prc_blob   (complex printer)
2429    1024      rt_sip_blob   (SipHash-1-3 for dict)
3453    4096      rt_alc_blob   (arena/pool allocator)
7549    1024      rt_prq_blob   (error/stderr printer, exit 1)
8573     ...      USER CODE STARTS HERE
```

### Runtime Blob Offsets (relative to start of output file = LOAD_BASE + N)

| Blob | LOAD_BASE offset | Purpose |
|---|---|---|
| `rt_pri_blob` | `LOAD_BASE + 125` | Print int (rdi → stdout) |
| `rt_prs_blob` | `LOAD_BASE + 637` | Print string (rdi → stdout) |
| `rt_prb_blob` | `LOAD_BASE + 1149` | Print bool (rdi → stdout) |
| `rt_prf_blob` | `LOAD_BASE + 1405` | Print float (rdi → stdout) |
| `rt_prc_blob` | `LOAD_BASE + 1917` | Print complex (rdi=addr → stdout) |
| `rt_sip_blob` | `LOAD_BASE + 2429` | SipHash-1-3 dict key hash |
| `rt_alc_blob` | `LOAD_BASE + 3453` | Allocator (arena/pool; rdi=size → rax=ptr) |
| `rt_prq_blob` | `LOAD_BASE + 7549` | Print error string + exit(1) |

### Call Encoding to Runtime

All runtime calls are `E8 <rel32>`. `rel32` is computed at emit time:
```
rel32 = (LOAD_BASE + RT_XX_OFFSET) - (LOAD_BASE + out_idx + 4)
      = RT_XX_OFFSET - out_idx - 4
```

### Program Exit (exit code 0) — `codegen_finish`

Emitted at the very end of user code:

```
48 C7 C0  3C 00 00 00      mov rax, 60          ; SYS_exit
48 31 FF                   xor rdi, rdi          ; exit code 0
0F 05                      syscall
```

Total: **10 bytes**.

After emitting these bytes, `codegen_finish` back-patches the ELF program header:
- `out_buffer[64+32]` ← `out_idx` (PT_LOAD file size)
- `out_buffer[64+40]` ← `out_idx + 0x44000` (PT_LOAD mem size, covers var storage)

### Exit Code 1 — `codegen_emit_exit1` (used by `err`)

```
48 C7 C0  3C 00 00 00      mov rax, 60
48 C7 C7  01 00 00 00      mov rdi, 1
0F 05                      syscall
```

Total: **16 bytes**.

---

## 4. Constant and Variable Loads

### Load 64-bit Integer Constant → rax

Emitted when a literal appears in an expression.

```
48 B8  <imm64>             mov rax, imm64        ; 10 bytes
```

### Load Variable → rax — `codegen_emit_mov_rax_var`

```
48 8B 04 25  <addr32>      mov rax, [var_addr]   ; 8 bytes
```

### Store rax → Variable — `codegen_emit_store_rax_to_var`

```
48 89 04 25  <addr32>      mov [var_addr], rax   ; 8 bytes
```

### Assign Constant to Variable — `codegen_emit_assign_var`

Two-instruction sequence; `rsi` = value:

```
48 B8        <imm64>       mov rax, imm64        ; 10 bytes
48 89 04 25  <addr32>      mov [var_addr], rax   ;  8 bytes
```

Total: **18 bytes**.

### Bool Literal `true` (1) / `false` (0)

Uses the standard constant-load path with `imm64 = 1` or `imm64 = 0`.

### Bool Literal `unknown` — `codegen_emit_unknown_bool` / `codegen_emit_rdrand_rax`

```
0F C7 F0                   rdrand eax            ; 3 bytes
83 E0 01                   and eax, 1            ; 3 bytes
```

Total: **6 bytes**. Result in `rax` (0 or 1).

When used in a declaration, the result is then stored via `mov [var_addr], rax`
(the `89 04 25 <addr32>` pattern without REX.W for the old path; with REX.W from
`codegen_emit_unknown_bool` directly):

```
0F C7 F0                   rdrand eax
83 E0 01                   and eax, 1
89 04 25     <addr32>      mov [var_addr], eax   ; note: 32-bit store, zero-extends
```

---

## 5. Stack Spill / Restore (expression evaluation)

The expression evaluator uses a software stack to hold sub-expression values.
Binary operations follow the pattern: evaluate RHS → push; evaluate LHS (→ rax);
pop RHS → rbx; operate (rax op rbx → rax).

```
50                         push rax              ; 1 byte
5B                         pop rbx               ; 1 byte
```

---

## 6. Integer Arithmetic

All integer ops work on `rax` (LHS after pop, or result) and `rbx` (RHS).

### `+` Addition — `codegen_emit_add_rax_rbx`

```
48 01 D8                   add rax, rbx          ; 3 bytes
```

### `-` Subtraction — `codegen_emit_sub_rax_rbx`

Computes `rbx - rax → rax` (because LHS is in rbx after the pop):

```
48 F7 D8                   neg rax               ; 3 bytes
48 01 D8                   add rax, rbx          ; 3 bytes
```

Total: **6 bytes**.

### `*` Multiplication — `codegen_emit_imul_rax_rbx`

```
48 0F AF C3                imul rax, rbx         ; 4 bytes
```

### `/` Division — `codegen_emit_idiv_rbx_by_rax`

Computes `rbx / rax → rax`:

```
48 89 C1                   mov rcx, rax          ; 3  (save divisor)
48 89 D8                   mov rax, rbx          ; 3  (dividend)
48 99                      cqo                   ; 2  (sign-extend rax → rdx:rax)
48 F7 F9                   idiv rcx              ; 3  (quotient → rax)
```

Total: **11 bytes**.

### `%` Modulo — `codegen_emit_imod_rbx_by_rax`

Same as division but moves `rdx` (remainder) into `rax`:

```
48 89 C1                   mov rcx, rax
48 89 D8                   mov rax, rbx
48 99                      cqo
48 F7 F9                   idiv rcx
48 89 D0                   mov rax, rdx          ; remainder
```

Total: **14 bytes**.

### Unary `-` Negation — `codegen_emit_neg_rax`

```
48 F7 D8                   neg rax               ; 3 bytes
```

---

## 7. Shift Operations

### `<<` Left Shift — `codegen_emit_shl_rax_by_rbx`

`rax` = shift count, `rbx` = value. Result → `rax`.

```
88 C1                      mov cl, al            ; 2  (shift count in cl)
48 89 D8                   mov rax, rbx          ; 3  (load value)
48 D3 E0                   shl rax, cl           ; 3
```

Total: **8 bytes**.

### `>>` Right Shift — `codegen_emit_shr_rax_by_rbx`

```
88 C1                      mov cl, al
48 89 D8                   mov rax, rbx
48 D3 E8                   shr rax, cl
```

Total: **8 bytes**.

---

## 8. Bitwise Operations

### `&` Bitwise AND — `codegen_emit_bitwise_and_rax_rbx`

```
48 21 D8                   and rax, rbx          ; 3 bytes
```

### `|` Bitwise OR — `codegen_emit_bitwise_or_rax_rbx`

```
48 09 D8                   or rax, rbx           ; 3 bytes
```

### `^` Bitwise XOR — `codegen_emit_bitwise_xor_rax_rbx`

```
48 31 D8                   xor rax, rbx          ; 3 bytes
```

### `~` Bitwise NOT — `codegen_emit_bitwise_not_rax`

```
48 F7 D0                   not rax               ; 3 bytes
```

---

## 9. Boolean Operations

### `and` — `codegen_emit_and_bool_rax_rbx`

Short-circuit, normalized to 0/1:

```
48 85 DB                   test rbx, rbx
0F 95 C1                   setnz cl
48 85 C0                   test rax, rax
0F 95 C0                   setnz al
20 C8                      and al, cl
48 0F B6 C0                movzx rax, al
```

Total: **18 bytes**.

### `or` — `codegen_emit_or_bool_rax_rbx`

```
48 09 D8                   or rax, rbx
0F 95 C0                   setnz al
48 0F B6 C0                movzx rax, al
```

Total: **10 bytes**.

### `not` (bool) — `codegen_emit_not_rax`

Flips a 0/1 value using XOR:

```
48 83 F0 01                xor rax, 1            ; 4 bytes
```

### Normalize any value → bool 0/1 — `codegen_emit_normalize_bool_rax`

Used when a non-bool expression is used as a condition:

```
48 85 C0                   test rax, rax
0F 95 C0                   setnz al
48 0F B6 C0                movzx rax, al
```

Total: **10 bytes**.

---

## 10. Comparison Operators

All comparisons use the sequence:

```
codegen_emit_cmp_rbx_rax_setcc  (rdi = setCC byte)
```

Emitted bytes:

```
48 39 C3                   cmp rbx, rax          ; 3
0F <setCC> C0              setCC al              ; 3
48 0F B6 C0                movzx rax, al         ; 4
```

Total: **10 bytes**.

### setCC byte by operator

| Operator | Condition | setCC opcode byte |
|---|---|---|
| `==` | equal | `0x94` (sete) |
| `!=` | not equal | `0x95` (setne) |
| `<` | less than (signed) | `0x9C` (setl) |
| `>` | greater than (signed) | `0x9F` (setg) |
| `<=` | less or equal (signed) | `0x9E` (setle) |
| `>=` | greater or equal (signed) | `0x9D` (setge) |

---

## 11. Conditional Branches (`if` / `elif` / `else`)

### Condition → branch-if-false — `codegen_emit_test_rax_jz`

Emitted after evaluating the condition expression into `rax`:

```
48 85 C0                   test rax, rax
0F 84  00 00 00 00         jz  <placeholder:rel32>
```

Total: **9 bytes**. The `<placeholder>` offset is pushed onto `jump_patch_stack`
and back-patched by `codegen_patch_jump` when the block end is known.

### End-of-elif-body forward jump — `codegen_emit_jmp_end`

```
E9  00 00 00 00            jmp  <placeholder:rel32>
```

5 bytes. Offset pushed onto `end_jump_stack`; patched by `codegen_patch_chain_end`.

### Branch-if-true — `codegen_emit_test_rax_jnz`

Used in `and` short-circuit and `while` condition path:

```
48 85 C0                   test rax, rax
0F 85  00 00 00 00         jnz  <placeholder:rel32>
```

Total: **9 bytes**.

### `when`/`is` — `codegen_emit_cmp_var_jne`

Compares a named variable against a compile-time integer constant:

```
48 81 3C 25  <addr32>  <imm32>    cmp qword [var_addr], imm32   ; 12 bytes
0F 85  00 00 00 00                jne  <placeholder:rel32>       ;  6 bytes
```

Total: **18 bytes per `is` case**.

---

## 12. For Loop (Static Bounds)

### Init — counter = 0 (optimised path)

```
31 C0                      xor eax, eax                      ; zero-init: 2 bytes
89 04 25  <addr32>         mov [loop_var_addr], eax          ; 7 bytes
```

### Init — counter = small imm32 (fits in 32 bits)

```
B8  <imm32>                mov eax, imm32                    ; 5 bytes
89 04 25  <addr32>         mov [loop_var_addr], eax          ; 7 bytes
```

### Init — counter = large imm64 (> 0xFFFFFFFF)

```
48 B8  <imm64>             mov rax, imm64                    ; 10 bytes
48 89 04 25  <addr32>      mov [loop_var_addr], rax          ;  8 bytes
```

### Condition Check (loop header — jumped back to each iteration)

```
48 81 3C 25  <addr32>  <imm32>    cmp qword [loop_var_addr], end_val
0F 8D  00 00 00 00                jge  <exit_placeholder:rel32>
```

Total: **18 bytes**. Back-edge of loop jumps to the start of this block.

### Dynamic Bounds (`for N in x..y` where y is a variable)

```
48 8B 04 25  <addr32>      mov rax, [loop_var]
48 3B 04 25  <addr32>      cmp rax, [end_var]
0F 8D  00 00 00 00         jge  <exit_placeholder>
```

Total: **22 bytes**.

### Loop Increment — step = 1 (optimised)

```
48 FF 04 25  <addr32>      inc qword [loop_var_addr]         ; 7 bytes
```

### Loop Increment — step = imm8 (2–127)

```
48 83 04 25  <addr32>  <imm8>    add qword [loop_var_addr], imm8    ; 8 bytes
```

### Loop Increment — step = imm32 (> 127)

```
48 81 04 25  <addr32>  <imm32>   add qword [loop_var_addr], imm32   ; 11 bytes
```

### Back-Jump to Loop Top

```
E9  <rel32>                jmp  loop_start       ; 5 bytes
```

`rel32` = `(LOAD_BASE + loop_start_pc) - (LOAD_BASE + out_idx + 4)`.

---

## 13. While Loop

### Condition

The condition expression is emitted directly. The back-jump and exit-patch are
identical to the for loop. `codegen_emit_while_start` is a no-op (returns
immediately); the loop-start `out_idx` is captured by the parser before the
condition is emitted.

### Back-Jump — `codegen_emit_while_end`

```
E9  <rel32>                jmp  loop_condition_start    ; 5 bytes
```

---

## 14. `stop` (Break) — `codegen_emit_break`

```
E9  00 00 00 00            jmp  <placeholder:rel32>    ; 5 bytes
```

The placeholder offset is pushed onto `break_jump_stack`. All pending break
placeholders for the current loop are back-patched by `codegen_patch_breaks`
at loop end.

---

## 15. `skip` (Continue) — `codegen_emit_skip`

Emits a direct jump to the loop's condition-check address (stored in
`cont_base_stack` by `codegen_push_cont`):

```
E9  <rel32>                jmp  loop_condition_start    ; 5 bytes
```

`rel32` = `(LOAD_BASE + cont_pc) - (LOAD_BASE + out_idx + 4)`.

---

## 16. Protocol (Function) Definition

### Protocol Skip Jump — `codegen_begin_protos`

Emitted once before the first protocol body (prevents falling into protocol
code during normal execution):

```
E9  00 00 00 00            jmp  <past_all_protos:placeholder>    ; 5 bytes
```

Patched by `codegen_end_protos` once all protocol bodies are emitted.

### `return` (void) — `codegen_emit_ret`

```
C3                         ret                                   ; 1 byte
```

### `return expr` (with value)

Expression is evaluated into `rax` (or `xmm0` for floats via bit-cast through
`rax`). Then:

```
C3                         ret                                   ; 1 byte
```

### Protocol Call — `codegen_emit_call_prot`

```
E8  <rel32>                call  proto_body_start                ; 5 bytes
```

### Argument Passing (push before call, pop inside callee)

Arguments are pushed in **reverse order** before the call. Each argument is
a standard `push rax` (byte `0x50`). Inside the callee, `codegen_emit_arg_pops`
emits the corresponding pops into the ABI registers:

| Position | Register | Pop opcode |
|---|---|---|
| arg 1 | `rdi` | `5F` |
| arg 2 | `rsi` | `5E` |
| arg 3 | `rdx` | `5A` |
| arg 4 | `rcx` | `59` |
| arg 5 | `r8` | `41 58` (2 bytes) |
| arg 6 | `r9` | `41 59` (2 bytes) |

Maximum 6 arguments. Argument 7+ are silently ignored.

### Move rax → rdi (for output / runtime call prep)

```
48 89 C7                   mov rdi, rax                         ; 3 bytes
```

---

## 17. `output` Statement

### `output` of constant int — `codegen_output_const`

```
BF  <imm32>                mov edi, imm32                       ; 5 bytes
E8  <rel32>                call  rt_pri_blob                    ; 5 bytes
```

Total: **10 bytes**.

### `output` of typed variable — `codegen_output_typed`

```
48 8B 3C 25  <addr32>      mov rdi, [var_addr]                  ; 8 bytes
E8  <rel32>                call  rt_pXX_blob                    ; 5 bytes
```

Total: **13 bytes**.

### `output` of expression result in rax — `codegen_output_rax`

```
48 89 C7                   mov rdi, rax                         ; 3 bytes
E8  <rel32>                call  rt_pXX_blob                    ; 5 bytes
```

Total: **8 bytes**.

### Printer selection by type

| Rex type | Blob called |
|---|---|
| `TYPE_INT` (1) | `rt_pri_blob` at `LOAD_BASE + 125` |
| `TYPE_FLOAT` (2) | `rt_prf_blob` at `LOAD_BASE + 1405` |
| `TYPE_BOOL` (3) | `rt_prb_blob` at `LOAD_BASE + 1149` |
| `TYPE_COMPLEX` (4) | `rt_prc_blob` at `LOAD_BASE + 1917` (rdi = address of {real,imag} pair) |
| `TYPE_STR` (5) | `rt_prs_blob` at `LOAD_BASE + 637` |

---

## 18. Float Operations

All float ops use XMM registers via bit-cast through `rax`/`rbx`.
The macro `FLOAT_OP` emits a fixed 19-byte preamble + operation + 5-byte suffix.

### Preamble: move `rax` (RHS bits) → `xmm1`, `rbx` (LHS bits) → `xmm0`

```
66 48 0F 6E C8             movq xmm1, rax         ; 5 bytes
66 48 0F 6E C3             movq xmm0, rbx         ; 5 bytes
```

### SSE2 Operation (opcode varies)

```
F2 0F  <opcode>  C1        <op>sd xmm0, xmm1      ; 4 bytes
```

| Rex operator | `<opcode>` | Mnemonic |
|---|---|---|
| `+` | `0x58` | `addsd` |
| `-` | `0x5C` | `subsd` |
| `*` | `0x59` | `mulsd` |
| `/` | `0x5E` | `divsd` |

### Suffix: move `xmm0` result bits → `rax`

```
66 48 0F 7E C0             movq rax, xmm0         ; 5 bytes
```

### Full float binary op: 19 bytes total per operation.

### `int(float_expr)` — `codegen_emit_cvttsd2si_rax`

```
66 48 0F 6E C0             movq xmm0, rax
F2 48 0F 2C C0             cvttsd2si rax, xmm0    ; truncate toward zero
```

Total: **10 bytes**.

### `float(int_expr)` — `codegen_emit_cvtsi2sd_rax`

```
F2 48 0F 2A C0             cvtsi2sd xmm0, rax
66 48 0F 7E C0             movq rax, xmm0
```

Total: **10 bytes**.

---

## 19. String Literal

`codegen_emit_str_rax` inlines the string bytes directly into the code segment
and loads the absolute address into `rax`.

### Emitted layout

```
E9  <len+1:imm32>          jmp  past_string_data         ; 5 bytes
<byte 0> ... <byte N-1>    raw string content            ; N bytes
00                         null terminator               ; 1 byte
48 B8  <addr64>            mov rax, abs_addr_of_data     ; 10 bytes
```

Total: **16 + N bytes** where N = string byte length (max 63).

`addr64 = LOAD_BASE + out_idx_at_string_start + 5` (the byte immediately after
the JMP instruction).

---

## 20. Sequence Operations

### Sequence Header Layout (at allocated pointer)

```
[ptr + 0]   qword   capacity  (initial = 8)
[ptr + 8]   qword   length    (initial = 0)
[ptr + 16]  qword[] elements  (8 bytes each)
```

Initial allocation size: `80` bytes = 16-byte header + 8 × 8-byte slots.

### Allocate Sequence — `codegen_emit_seq_alloc`

```
BF  08 00 00 00  50 00 00 00   mov edi, 80             ; 5 bytes (50 hex = 80 dec)
E8  <rel32>                    call rt_alc_blob         ; 5 bytes
48 C7 00  08 00 00 00          mov qword [rax], 8      ; 7 bytes  (cap = 8)
48 C7 40 08  00 00 00 00       mov qword [rax+8], 0    ; 8 bytes  (len = 0)
48 89 04 25  <addr32>          mov [var_addr], rax      ; 8 bytes
```

Total: **33 bytes**.

### Push to Sequence — `codegen_emit_seq_push`

Fast path (no grow needed): 34 bytes.
Slow path (inline grow triggered): 57 additional bytes before store.

**Fast path:**
```
50                             push rax                          ; save value
48 8B 1C 25  <addr32>         mov rbx, [ptr_addr]               ; load seq ptr
48 8B 4B 08                   mov rcx, [rbx+8]                  ; load len
48 3B 0B                      cmp rcx, [rbx]                    ; len vs cap
72 39                         jb  +57                           ; skip grow if len < cap
```

**Inline grow block (57 bytes):**

```
51                             push rcx                          ; save old cap
48 8B 3B                      mov rdi, [rbx]                    ; rdi = old cap
48 C1 E7 10                   shl rdi, 4                        ; rdi = old_cap * 16
48 83 C7 10                   add rdi, 16                       ; rdi = new_size
E8  <rel32>                   call rt_alc_blob                   ; rax = new ptr
59                             pop rcx                           ; rcx = old cap
50                             push rax                          ; save new ptr
49 89 CB                      mov r11, rcx                      ; r11 = old cap
49 D1 E3                      shl r11, 1                        ; r11 = new cap
4C 89 18                      mov [rax], r11                    ; [new+0] = new cap
48 89 48 08                   mov [rax+8], rcx                  ; [new+8] = old len
48 8D 78 10                   lea rdi, [rax+16]                 ; dst
48 8D 73 10                   lea rsi, [rbx+16]                 ; src
F3 48 A5                      rep movsq                         ; copy elements
5B                             pop rbx                           ; rbx = new ptr
48 89 1C 25  <addr32>         mov [var_addr], rbx               ; update slot
48 8B 4B 08                   mov rcx, [rbx+8]                  ; reload len
```

**Common tail (store + inc):**
```
58                             pop rax                           ; restore value
48 89 44 CB 10                mov [rbx+rcx*8+16], rax           ; store element
48 FF 43 08                   inc qword [rbx+8]                 ; inc len
```

### Pop from Sequence — `codegen_emit_seq_pop_rax`

```
48 8B 1C 25  <addr32>         mov rbx, [ptr_addr]
48 FF 4B 08                   dec qword [rbx+8]
48 8B 4B 08                   mov rcx, [rbx+8]
48 8B 44 CB 10                mov rax, [rbx+rcx*8+16]
```

Total: **21 bytes**.

### `len` of Sequence — `codegen_emit_seq_len_rax`

```
48 8B 04 25  <addr32>         mov rax, [ptr_addr]       ; load ptr
48 8B 40 08                   mov rax, [rax+8]           ; load len field
```

Total: **12 bytes**.

### `cap` of Sequence — `codegen_emit_cap_rax`

```
48 8B 04 25  <addr32>         mov rax, [ptr_addr]       ; load ptr
48 8B 00                      mov rax, [rax]             ; load cap field
```

Total: **11 bytes**.

---

## 21. `++` and `--`

### `++ ident` — `codegen_emit_inc_var`

```
48 FF 04 25  <addr32>         inc qword [var_addr]       ; 7 bytes
48 8B 04 25  <addr32>         mov rax,  [var_addr]       ; 8 bytes (result in rax)
```

Total: **15 bytes**.

### `-- ident` — `codegen_emit_dec_var`

```
48 FF 0C 25  <addr32>         dec qword [var_addr]       ; 7 bytes
48 8B 04 25  <addr32>         mov rax,  [var_addr]       ; 8 bytes
```

Total: **15 bytes**.

---

## 22. `swap`

### `swap a b` — `codegen_emit_swap_vars`

```
48 8B 04 25  <addr_a>         mov rax, [var_a]
48 8B 1C 25  <addr_b>         mov rbx, [var_b]
48 89 1C 25  <addr_a>         mov [var_a], rbx
48 89 04 25  <addr_b>         mov [var_b], rax
```

Total: **32 bytes**.

---

## 23. `abs(expr)` — `codegen_emit_abs_rax`

Branchless via `cmovs`:

```
48 89 C3                      mov rbx, rax          ; 3  save original
48 F7 D8                      neg rax               ; 3  negate
48 0F 48 C3                   cmovs rax, rbx        ; 4  if SF=1 (was positive), keep original
```

Total: **10 bytes**.

Note: `cmovs` (opcode `0F 48`) moves if the sign flag is set — i.e., if `neg`
set SF, the original was positive (or zero), so we restore it from `rbx`.

---

## 24. `err` Statement — `codegen_emit_call_rt_err`

Loads the error string pointer into `rdi` (from `mov rdi,rax`), then:

```
E8  <rel32>                   call rt_prq_blob    ; stderr + exit(1)
```

`rt_prq_blob` is at `LOAD_BASE + RT_PRQ_OFFSET` = `LOAD_BASE + 7549`.

---

## 25. Memory Manager Switch — `codegen_emit_mm_switch`

Patches the allocator's `.mode` word at runtime:

```
48 C7 05  <rel32>  <imm32>    mov qword [rip + disp], mode
```

- `rel32` = `(LOAD_BASE + RT_ALC_OFFSET + RT_ALC_SIZE - 8) - (LOAD_BASE + out_idx + 8)`
- `imm32` = 0 (arena) or 1 (pool)

Total: **11 bytes**.

`codegen_emit_gc_switch` is a stub that emits **zero bytes** (GC runtime not yet implemented).

---

## 26. Forward Jump Slots — `codegen_emit_jmp_get_slot` / `codegen_patch_slot_to_here`

Used internally by the parser for arbitrary forward references:

```
E9  00 00 00 00               jmp  <placeholder>    ; 5 bytes
```

`codegen_emit_jmp_get_slot` returns the `out_idx` of the `<placeholder>` dword.
`codegen_patch_slot_to_here(slot_offset)` writes:

```
out_buffer[slot_offset] = (int32_t)(out_idx - slot_offset - 4)
```

---

## 27. `mov eax, imm32` / `xor eax, eax` — `codegen_emit_mov_eax_imm32`

| Value | Bytes | Assembly |
|---|---|---|
| 0 | `31 C0` | `xor eax, eax` (2 bytes) |
| non-zero | `B8 <imm32>` | `mov eax, imm32` (5 bytes) |

---

## 28. Jump Patch Stacks (compiler data structures, not emitted)

| Stack | Purpose | Depth limit |
|---|---|---|
| `jump_patch_stack` | `if`/`when` condition forward exits | 32 entries |
| `end_jump_stack` | `elif`/`else` end-of-body jumps | 32 entries |
| `chain_base_stack` | marks start of each `if` chain's end-jump group | 32 entries |
| `break_jump_stack` | `stop` forward exits | 32 entries |
| `break_base_stack` | marks start of each loop's break group | 32 entries |
| `cont_base_stack` | continue (back-edge) targets for `skip` | 32 entries |

All stacks share 32-entry depth. Exceeding any stack depth produces undefined
behaviour in the current compiler (no overflow guard beyond `break_jump_stack`).

---

## 29. Quick Byte Pattern Lookup

| Pattern | Meaning |
|---|---|
| `48 B8 XX XX XX XX XX XX XX XX` | `mov rax, imm64` — load 64-bit constant |
| `48 8B 04 25 AA AA AA AA` | `mov rax, [abs32]` — load variable |
| `48 89 04 25 AA AA AA AA` | `mov [abs32], rax` — store variable |
| `48 8B 1C 25 AA AA AA AA` | `mov rbx, [abs32]` — load into scratch |
| `48 89 1C 25 AA AA AA AA` | `mov [abs32], rbx` — store from scratch |
| `48 8B 3C 25 AA AA AA AA` | `mov rdi, [abs32]` — load for call arg |
| `50` | `push rax` — spill to stack |
| `5B` | `pop rbx` — restore from stack |
| `E8 RR RR RR RR` | `call rel32` — call runtime or protocol |
| `E9 RR RR RR RR` | `jmp rel32` — unconditional jump |
| `0F 84 RR RR RR RR` | `jz rel32` — branch-if-false |
| `0F 85 RR RR RR RR` | `jnz rel32` — branch-if-true |
| `0F 8D RR RR RR RR` | `jge rel32` — loop exit (for/while) |
| `48 C7 C0 3C 00 00 00` `48 31 FF` `0F 05` | exit(0) — program end |
| `48 C7 C0 3C 00 00 00` `48 C7 C7 01 00 00 00` `0F 05` | exit(1) — error |
| `0F C7 F0` `83 E0 01` | `rdrand eax; and eax,1` — `unknown` bool |
| `48 F7 D8` | `neg rax` — unary minus |
| `48 F7 D0` | `not rax` — bitwise NOT `~` |
| `48 83 F0 01` | `xor rax, 1` — bool NOT |
| `48 0F AF C3` | `imul rax, rbx` — multiply |
| `48 01 D8` | `add rax, rbx` |
| `48 21 D8` | `and rax, rbx` — bitwise AND |
| `48 09 D8` | `or rax, rbx` — bitwise OR |
| `48 31 D8` | `xor rax, rbx` — bitwise XOR |
| `48 39 C3` `0F XX C0` `48 0F B6 C0` | `cmp rbx,rax; setCC al; movzx rax,al` — compare |
| `48 85 C0` `0F 84 ...` | `test rax,rax; jz` — if-false branch |
| `48 0F 48 C3` | `cmovs rax, rbx` — branchless abs |
| `C3` | `ret` — return from protocol |
| `F3 48 A5` | `rep movsq` — bulk element copy in seq grow |
