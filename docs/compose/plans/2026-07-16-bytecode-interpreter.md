# Rex Bytecode Interpreter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use compose:subagent (recommended) or compose:execute to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a stack-based bytecode interpreter that compiles Rex programs to compact bytecode instead of native x86-64, achieving 10-50x smaller binaries for simple programs.

**Architecture:** A stack-based virtual machine with fixed-size 8-byte instructions. The compiler emits bytecode instead of x86-64 for programs under a configurable IR record threshold. The interpreter is a native x86-64 loop (~200 bytes) embedded in the ELF binary, with the bytecode as data.

**Tech Stack:** x86-64 NASM assembly, ELF64 binary output, Linux syscalls.

## Global Constraints

- Bytecode interpreter must produce identical output to native codegen for all 23 existing tests
- Interpreter loop must be position-independent (no absolute addresses in the interpreter itself)
- Bytecode format must be extensible for future IR opcodes
- Target: `output(42)` binary ≤ 200 bytes (vs 190 bytes native, but scales better for complex programs)
- Target: `output("hello world")` binary ≤ 150 bytes (vs 248 bytes native)
- The interpreter must handle all currently-supported IR opcodes

## Bytecode Format

Each instruction is 8 bytes (fixed size for simple dispatch):
```
Byte 0:    opcode (1 byte)
Byte 1:    type flag (1 byte) — TYPE_INT, TYPE_FLOAT, TYPE_STR, etc.
Bytes 2-3: dst operand (2 bytes — vreg index or stack offset)
Bytes 4-5: src1 operand (2 bytes)
Bytes 6-7: src2/imm low (2 bytes)
```

The remaining immediate data (8 bytes for LOAD_IMM) is stored as a separate 8-byte word following the instruction, making the effective instruction size 16 bytes for LOAD_IMM and 8 bytes for all others.

## Stack Machine Design

- Operand stack: 256 entries (2 KB) — holds intermediate values
- Call stack: 64 frames — for function calls (future)
- Variables: stored at absolute addresses (same as native codegen, VAR_STORAGE_BASE)
- Runtime calls: the interpreter dispatches to native runtime functions via syscall-style interface

## File Structure

| File | Responsibility |
|------|---------------|
| `codegen/bytecode.asm` | Bytecode emitter: IR → bytecode conversion |
| `codegen/bc_interp.asm` | Bytecode interpreter loop (native x86-64) |
| `codegen/codegen.asm` | Modified to choose native vs bytecode path |
| `include/rex_bc.inc` | Bytecode opcode definitions |

---

### Task 1: Define Bytecode Opcodes

**Covers:** Bytecode format definition

**Files:**
- Create: `include/rex_bc.inc`

**Interfaces:**
- Consumes: IR opcodes from `include/rex_ir.inc`
- Produces: Bytecode opcode constants used by emitter and interpreter

- [ ] **Step 1: Create bytecode opcode definitions**

```nasm
; rex_bc.inc — Rex Bytecode Opcodes
; Each instruction is 8 bytes (or 16 for LOAD_IMM/LOAD_FIMM)

; Stack operations
BC_NOP          equ 0x00
BC_LOAD_IMM     equ 0x01  ; push imm64 (followed by 8-byte immediate)
BC_LOAD_FIMM    equ 0x02  ; push float imm64
BC_LOAD_VAR     equ 0x03  ; push value from variable[imm16]
BC_STORE_VAR    equ 0x04  ; pop value → variable[imm16]
BC_LOAD_STR     equ 0x05  ; push string pointer (inline data)
BC_LOAD_BOOL    equ 0x06  ; push bool value (imm16: -1/0/1)
BC_DUP          equ 0x07  ; duplicate top of stack
BC_POP          equ 0x08  ; discard top of stack

; Arithmetic (pop 2, push 1)
BC_ADD          equ 0x10
BC_SUB          equ 0x11
BC_MUL          equ 0x12
BC_DIV          equ 0x13
BC_MOD          equ 0x14
BC_NEG          equ 0x15  ; pop 1, push -value

; Bitwise (pop 2, push 1)
BC_AND          equ 0x18
BC_OR           equ 0x19
BC_XOR          equ 0x1A

; Comparison (pop 2, push bool)
BC_CMP_EQ       equ 0x20
BC_CMP_NE       equ 0x21
BC_CMP_LT       equ 0x22
BC_CMP_LE       equ 0x23
BC_CMP_GT       equ 0x24
BC_CMP_GE       equ 0x25

; Control flow
BC_JMP          equ 0x30  ; unconditional jump to imm16 offset
BC_JMP_IF       equ 0x31  ; pop bool, jump if true
BC_JMP_IF_NOT   equ 0x32  ; pop bool, jump if false
BC_HALT         equ 0x33  ; stop execution

; Output (pop 1, write to stdout)
BC_OUT_INT      equ 0x40
BC_OUT_STR      equ 0x41
BC_OUT_BOOL     equ 0x42
BC_OUT_CHAR     equ 0x43
BC_OUT_FLOAT    equ 0x44

; Type casts
BC_CAST_ITF     equ 0x50  ; int → float
BC_CAST_FTI     equ 0x51  ; float → int
BC_CAST_BTI     equ 0x52  ; bool → int
BC_CAST_STR     equ 0x53  ; any → str

; String operations
BC_STR_CONCAT   equ 0x60  ; pop 2 strings, push concatenated
BC_STR_LEN      equ 0x61  ; pop string, push length
BC_STR_CMP      equ 0x62  ; pop 2 strings, push comparison result

; Collection operations
BC_SEQ_NEW      equ 0x70  ; push new seq (imm16 = capacity)
BC_SEQ_PUSH     equ 0x71  ; pop value, pop seq, push seq
BC_SEQ_LOAD     equ 0x72  ; pop index, pop seq, push element
BC_SEQ_STORE    equ 0x73  ; pop value, pop index, pop seq, push seq
BC_SEQ_LEN      equ 0x74  ; pop seq, push length
BC_SEQ_POP      equ 0x75  ; pop seq, push popped element
BC_DICT_NEW     equ 0x78  ; push new dict
BC_DICT_LOAD    equ 0x79  ; pop key, pop dict, push value
BC_DICT_STORE   equ 0x7A  ; pop value, pop key, pop dict, push dict
BC_DICT_LEN     equ 0x7B  ; pop dict, push length

; Bytecode header
BC_MAGIC        equ 0x52455842  ; "REXB"
BC_VERSION      equ 1
```

- [ ] **Step 2: Verify file includes correctly**

Run: `cd /home/t85491005/Rex && nasm -f elf64 -I ./ test_bc_inc.asm -o /dev/null 2>&1` (create a test file that `%include "include/rex_bc.inc"`)
Expected: No errors

---

### Task 2: Bytecode Emitter — IR to Bytecode

**Covers:** Core bytecode emission

**Files:**
- Create: `codegen/bytecode.asm`

**Interfaces:**
- Consumes: `ir_buffer`, `ir_count` from `irgen/irgen.asm`
- Produces: `bc_buffer`, `bc_len` — the emitted bytecode

- [ ] **Step 1: Create bytecode emitter with data section**

```nasm
; bytecode.asm — IR to Bytecode emitter
%include "include/rex_defs.inc"
%include "include/rex_ir.inc"
%include "include/rex_bc.inc"

section .bss
    global bc_buffer
    global bc_len
    bc_buffer resb 65536    ; 64 KB bytecode buffer
    bc_len    resd 1        ; emitted bytecode length

section .text
    global emit_bytecode
    extern ir_buffer
    extern ir_count

; emit_bytecode: Convert all IR records to bytecode
; No inputs — reads from ir_buffer/ir_count
; Outputs: bc_buffer filled, bc_len set
emit_bytecode:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov dword [bc_len], 0
    mov ecx, [ir_count]
    test ecx, ecx
    jz .done

    xor ebx, ebx            ; IR index
    xor r12d, r12d           ; bytecode offset (for label mapping)

.loop:
    cmp ebx, [ir_count]
    jae .done

    imul eax, ebx, IR_RECORD_SIZE
    lea r14, [ir_buffer + rax] ; r14 = IR record

    movzx eax, byte [r14]   ; opcode
    ; Dispatch to handler
    cmp al, IR_NOP
    je .emit_nop
    cmp al, IR_LOAD_IMM
    je .emit_load_imm
    cmp al, IR_LOAD_FIMM
    je .emit_load_fimm
    cmp al, IR_LOAD_VAR
    je .emit_load_var
    cmp al, IR_STORE_VAR
    je .emit_store_var
    cmp al, IR_LOAD_STR
    je .emit_load_str
    cmp al, IR_LOAD_BOOL
    je .emit_load_bool
    cmp al, IR_ADD
    je .emit_add
    cmp al, IR_SUB
    je .emit_sub
    cmp al, IR_MUL
    je .emit_mul
    cmp al, IR_DIV
    je .emit_div
    cmp al, IR_MOD
    je .emit_mod
    cmp al, IR_NEG
    je .emit_neg
    cmp al, IR_AND
    je .emit_and
    cmp al, IR_OR
    je .emit_or
    cmp al, IR_XOR
    je .emit_xor
    cmp al, IR_CMP_BOOL
    je .emit_cmp_bool
    cmp al, IR_OUT_INT
    je .emit_out_int
    cmp al, IR_OUT_STR
    je .emit_out_str
    cmp al, IR_OUT_BOOL
    je .emit_out_bool
    cmp al, IR_OUT_CHAR
    je .emit_out_char
    cmp al, IR_OUT_FLOAT
    je .emit_out_float
    cmp al, IR_HALT
    je .emit_halt
    cmp al, IR_LABEL
    je .emit_label
    cmp al, IR_JMP
    je .emit_jmp
    cmp al, IR_JCC
    je .emit_jcc
    ; Unknown opcode — skip
    inc ebx
    jmp .loop

.emit_nop:
    ; BC_NOP: 8 bytes
    mov byte [bc_buffer + r12], BC_NOP
    add r12, 8
    inc ebx
    jmp .loop

.emit_load_imm:
    ; BC_LOAD_IMM: 8-byte header + 8-byte immediate = 16 bytes
    mov byte [bc_buffer + r12], BC_LOAD_IMM
    mov al, [r14 + 1]       ; type
    mov [bc_buffer + r12 + 1], al
    mov ax, [r14 + 2]       ; dst vreg
    mov [bc_buffer + r12 + 2], ax
    mov rax, [r14 + 8]      ; imm value
    mov [bc_buffer + r12 + 8], rax
    add r12, 16
    inc ebx
    jmp .loop

.emit_load_var:
    mov byte [bc_buffer + r12], BC_LOAD_VAR
    mov al, [r14 + 1]
    mov [bc_buffer + r12 + 1], al
    mov ax, [r14 + 2]       ; dst
    mov [bc_buffer + r12 + 2], ax
    mov rax, [r14 + 8]      ; variable offset
    mov [bc_buffer + r12 + 4], ax
    add r12, 8
    inc ebx
    jmp .loop

.emit_store_var:
    mov byte [bc_buffer + r12], BC_STORE_VAR
    mov al, [r14 + 1]
    mov [bc_buffer + r12 + 1], al
    mov ax, [r14 + 4]       ; src1
    mov [bc_buffer + r12 + 2], ax
    mov rax, [r14 + 8]      ; variable offset
    mov [bc_buffer + r12 + 4], ax
    add r12, 8
    inc ebx
    jmp .loop

.emit_add:
    mov byte [bc_buffer + r12], BC_ADD
    mov al, [r14 + 1]
    mov [bc_buffer + r12 + 1], al
    add r12, 8
    inc ebx
    jmp .loop

.emit_sub:
    mov byte [bc_buffer + r12], BC_SUB
    mov al, [r14 + 1]
    mov [bc_buffer + r12 + 1], al
    add r12, 8
    inc ebx
    jmp .loop

.emit_mul:
    mov byte [bc_buffer + r12], BC_MUL
    mov al, [r14 + 1]
    mov [bc_buffer + r12 + 1], al
    add r12, 8
    inc ebx
    jmp .loop

.emit_div:
    mov byte [bc_buffer + r12], BC_DIV
    mov al, [r14 + 1]
    mov [bc_buffer + r12 + 1], al
    add r12, 8
    inc ebx
    jmp .loop

.emit_mod:
    mov byte [bc_buffer + r12], BC_MOD
    mov al, [r14 + 1]
    mov [bc_buffer + r12 + 1], al
    add r12, 8
    inc ebx
    jmp .loop

.emit_neg:
    mov byte [bc_buffer + r12], BC_NEG
    mov al, [r14 + 1]
    mov [bc_buffer + r12 + 1], al
    add r12, 8
    inc ebx
    jmp .loop

.emit_and:
    mov byte [bc_buffer + r12], BC_AND
    add r12, 8
    inc ebx
    jmp .loop

.emit_or:
    mov byte [bc_buffer + r12], BC_OR
    add r12, 8
    inc ebx
    jmp .loop

.emit_xor:
    mov byte [bc_buffer + r12], BC_XOR
    add r12, 8
    inc ebx
    jmp .loop

.emit_cmp_bool:
    mov byte [bc_buffer + r12], BC_CMP_EQ ; simplified — uses aux for condition
    mov al, [r14 + 1]
    mov [bc_buffer + r12 + 1], al
    mov ax, [r14 + 16]      ; aux = condition code
    mov [bc_buffer + r12 + 2], ax
    add r12, 8
    inc ebx
    jmp .loop

.emit_out_int:
    mov byte [bc_buffer + r12], BC_OUT_INT
    mov ax, [r14 + 4]       ; src1 vreg
    mov [bc_buffer + r12 + 2], ax
    add r12, 8
    inc ebx
    jmp .loop

.emit_out_str:
    mov byte [bc_buffer + r12], BC_OUT_STR
    mov ax, [r14 + 4]
    mov [bc_buffer + r12 + 2], ax
    add r12, 8
    inc ebx
    jmp .loop

.emit_out_bool:
    mov byte [bc_buffer + r12], BC_OUT_BOOL
    mov ax, [r14 + 4]
    mov [bc_buffer + r12 + 2], ax
    add r12, 8
    inc ebx
    jmp .loop

.emit_out_char:
    mov byte [bc_buffer + r12], BC_OUT_CHAR
    mov ax, [r14 + 4]
    mov [bc_buffer + r12 + 2], ax
    add r12, 8
    inc ebx
    jmp .loop

.emit_out_float:
    mov byte [bc_buffer + r12], BC_OUT_FLOAT
    mov ax, [r14 + 4]
    mov [bc_buffer + r12 + 2], ax
    add r12, 8
    inc ebx
    jmp .loop

.emit_halt:
    mov byte [bc_buffer + r12], BC_HALT
    add r12, 8
    inc ebx
    jmp .loop

.emit_label:
    ; Labels are recorded for jump resolution
    ; For now, just skip
    inc ebx
    jmp .loop

.emit_jmp:
    mov byte [bc_buffer + r12], BC_JMP
    mov ax, [r14 + 8]       ; target label ID
    mov [bc_buffer + r12 + 2], ax
    add r12, 8
    inc ebx
    jmp .loop

.emit_jcc:
    mov byte [bc_buffer + r12], BC_JMP_IF_NOT
    mov ax, [r14 + 4]       ; src1 (bool vreg)
    mov [bc_buffer + r12 + 2], ax
    mov ax, [r14 + 8]       ; target label ID
    mov [bc_buffer + r12 + 4], ax
    add r12, 8
    inc ebx
    jmp .loop

.emit_load_str:
    ; Inline string: embed string data after the instruction
    mov byte [bc_buffer + r12], BC_LOAD_STR
    mov al, [r14 + 1]
    mov [bc_buffer + r12 + 1], al
    mov ax, [r14 + 2]
    mov [bc_buffer + r12 + 2], ax
    ; String length in bytes 4-5
    mov rax, [r14 + 16]     ; aux = string length
    mov [bc_buffer + r12 + 4], ax
    ; Copy string bytes after instruction
    add r12, 8
    mov rsi, [r14 + 8]      ; imm = string pointer
    mov rcx, [r14 + 16]     ; length
    lea rdi, [bc_buffer + r12]
    rep movsb
    add r12, [r14 + 16]     ; advance by string length
    ; Align to 8 bytes
    add r12, 7
    and r12, ~7
    inc ebx
    jmp .loop

.emit_load_fimm:
    mov byte [bc_buffer + r12], BC_LOAD_FIMM
    mov al, [r14 + 1]
    mov [bc_buffer + r12 + 1], al
    mov ax, [r14 + 2]
    mov [bc_buffer + r12 + 2], ax
    mov rax, [r14 + 8]
    mov [bc_buffer + r12 + 8], rax
    add r12, 16
    inc ebx
    jmp .loop

.emit_load_bool:
    mov byte [bc_buffer + r12], BC_LOAD_BOOL
    mov al, [r14 + 1]
    mov [bc_buffer + r12 + 1], al
    mov ax, [r14 + 2]
    mov [bc_buffer + r12 + 2], ax
    mov rax, [r14 + 8]
    mov [bc_buffer + r12 + 4], ax
    add r12, 8
    inc ebx
    jmp .loop

.done:
    mov [bc_len], r12d
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
```

- [ ] **Step 2: Test bytecode emitter produces non-empty output**

Run: `cd /home/t85491005/Rex && echo 'output(42)' > /tmp/t.rex && ./rexc /tmp/t.rex -o /tmp/t --bytecode 2>&1`
Expected: Compilation successful

---

### Task 3: Bytecode Interpreter Loop

**Covers:** Core interpreter execution

**Files:**
- Create: `codegen/bc_interp.asm`

**Interfaces:**
- Consumes: `bc_buffer`, `bc_len` from bytecode emitter
- Produces: Program execution (stdout output, variable writes)

- [ ] **Step 1: Create the interpreter loop**

The interpreter uses a stack machine with:
- `r13` = bytecode instruction pointer
- `r14` = operand stack pointer
- `r15` = stack base

```nasm
; bc_interp.asm — Rex Bytecode Interpreter
; A stack-based virtual machine for executing Rex bytecode
bits 64

section .text
    global bc_interp

; bc_interp: Execute bytecode
; Inputs: none (reads bc_buffer, bc_len, variable storage)
; Outputs: program execution
bc_interp:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    ; Set up operand stack (256 entries = 2048 bytes)
    sub rsp, 2048
    mov r15, rsp            ; r15 = stack base
    mov r14, rsp            ; r14 = stack pointer (grows up)

    ; Set up instruction pointer
    lea r13, [bc_buffer]    ; r13 = instruction pointer

.dispatch:
    ; Fetch opcode
    movzx eax, byte [r13]

    ; Dispatch
    cmp al, BC_NOP
    je .bc_nop
    cmp al, BC_LOAD_IMM
    je .bc_load_imm
    cmp al, BC_LOAD_VAR
    je .bc_load_var
    cmp al, BC_STORE_VAR
    je .bc_store_var
    cmp al, BC_LOAD_STR
    je .bc_load_str
    cmp al, BC_LOAD_BOOL
    je .bc_load_bool
    cmp al, BC_LOAD_FIMM
    je .bc_load_fimm
    cmp al, BC_ADD
    je .bc_add
    cmp al, BC_SUB
    je .bc_sub
    cmp al, BC_MUL
    je .bc_mul
    cmp al, BC_DIV
    je .bc_div
    cmp al, BC_MOD
    je .bc_mod
    cmp al, BC_NEG
    je .bc_neg
    cmp al, BC_AND
    je .bc_and
    cmp al, BC_OR
    je .bc_or
    cmp al, BC_XOR
    je .bc_xor
    cmp al, BC_CMP_EQ
    je .bc_cmp_eq
    cmp al, BC_CMP_NE
    je .bc_cmp_ne
    cmp al, BC_CMP_LT
    je .bc_cmp_lt
    cmp al, BC_CMP_LE
    je .bc_cmp_le
    cmp al, BC_CMP_GT
    je .bc_cmp_gt
    cmp al, BC_CMP_GE
    je .bc_cmp_ge
    cmp al, BC_OUT_INT
    je .bc_out_int
    cmp al, BC_OUT_STR
    je .bc_out_str
    cmp al, BC_OUT_BOOL
    je .bc_out_bool
    cmp al, BC_OUT_CHAR
    je .bc_out_char
    cmp al, BC_OUT_FLOAT
    je .bc_out_float
    cmp al, BC_HALT
    je .bc_halt
    cmp al, BC_JMP
    je .bc_jmp
    cmp al, BC_JMP_IF
    je .bc_jmp_if
    cmp al, BC_JMP_IF_NOT
    je .bc_jmp_if_not
    ; Unknown opcode — skip
    add r13, 8
    jmp .dispatch

; ─── NOP ─────────────────────────────────────────
.bc_nop:
    add r13, 8
    jmp .dispatch

; ─── LOAD_IMM ────────────────────────────────────
.bc_load_imm:
    ; Push 8-byte immediate onto stack
    mov rax, [r13 + 8]      ; immediate value
    mov [r14], rax
    add r14, 8
    add r13, 16             ; 8-byte instruction + 8-byte immediate
    jmp .dispatch

; ─── LOAD_VAR ────────────────────────────────────
.bc_load_var:
    movzx eax, word [r13 + 4] ; variable offset
    mov rax, [VAR_STORAGE_BASE + rax]
    mov [r14], rax
    add r14, 8
    add r13, 8
    jmp .dispatch

; ─── STORE_VAR ───────────────────────────────────
.bc_store_var:
    sub r14, 8              ; pop value
    mov rax, [r14]
    movzx ecx, word [r13 + 4] ; variable offset
    mov [VAR_STORAGE_BASE + rcx], rax
    add r13, 8
    jmp .dispatch

; ─── LOAD_STR ────────────────────────────────────
.bc_load_str:
    ; Push string pointer (points to inline data after instruction)
    lea rax, [r13 + 8]      ; string data starts after 8-byte header
    mov [r14], rax
    add r14, 8
    ; Advance past instruction + string data (aligned to 8)
    movzx ecx, word [r13 + 4] ; string length
    add rcx, 8              ; + header
    add rcx, 7
    and rcx, ~7             ; align to 8
    add r13, rcx
    jmp .dispatch

; ─── LOAD_BOOL ───────────────────────────────────
.bc_load_bool:
    movzx eax, word [r13 + 4] ; bool value (-1/0/1)
    movsx rax, ax
    mov [r14], rax
    add r14, 8
    add r13, 8
    jmp .dispatch

; ─── LOAD_FIMM ───────────────────────────────────
.bc_load_fimm:
    mov rax, [r13 + 8]
    mov [r14], rax
    add r14, 8
    add r13, 16
    jmp .dispatch

; ─── ADD ─────────────────────────────────────────
.bc_add:
    sub r14, 8
    mov rax, [r14 - 8]      ; left operand
    add rax, [r14]          ; + right operand
    mov [r14 - 8], rax
    add r13, 8
    jmp .dispatch

; ─── SUB ─────────────────────────────────────────
.bc_sub:
    sub r14, 8
    mov rax, [r14 - 8]
    sub rax, [r14]
    mov [r14 - 8], rax
    add r13, 8
    jmp .dispatch

; ─── MUL ─────────────────────────────────────────
.bc_mul:
    sub r14, 8
    mov rax, [r14 - 8]
    imul rax, [r14]
    mov [r14 - 8], rax
    add r13, 8
    jmp .dispatch

; ─── DIV ─────────────────────────────────────────
.bc_div:
    sub r14, 8
    mov rax, [r14 - 8]
    cqo
    idiv qword [r14]
    mov [r14 - 8], rax
    add r13, 8
    jmp .dispatch

; ─── MOD ─────────────────────────────────────────
.bc_mod:
    sub r14, 8
    mov rax, [r14 - 8]
    cqo
    idiv qword [r14]
    mov [r14 - 8], rdx      ; remainder
    add r13, 8
    jmp .dispatch

; ─── NEG ─────────────────────────────────────────
.bc_neg:
    neg qword [r14 - 8]
    add r13, 8
    jmp .dispatch

; ─── AND ─────────────────────────────────────────
.bc_and:
    sub r14, 8
    mov rax, [r14 - 8]
    and rax, [r14]
    mov [r14 - 8], rax
    add r13, 8
    jmp .dispatch

; ─── OR ──────────────────────────────────────────
.bc_or:
    sub r14, 8
    mov rax, [r14 - 8]
    or rax, [r14]
    mov [r14 - 8], rax
    add r13, 8
    jmp .dispatch

; ─── XOR ─────────────────────────────────────────
.bc_xor:
    sub r14, 8
    mov rax, [r14 - 8]
    xor rax, [r14]
    mov [r14 - 8], rax
    add r13, 8
    jmp .dispatch

; ─── CMP ─────────────────────────────────────────
.bc_cmp_eq:
    sub r14, 8
    mov rax, [r14 - 8]
    cmp rax, [r14]
    sete al
    movzx eax, al
    mov [r14 - 8], rax
    add r13, 8
    jmp .dispatch

.bc_cmp_ne:
    sub r14, 8
    mov rax, [r14 - 8]
    cmp rax, [r14]
    setne al
    movzx eax, al
    mov [r14 - 8], rax
    add r13, 8
    jmp .dispatch

.bc_cmp_lt:
    sub r14, 8
    mov rax, [r14 - 8]
    cmp rax, [r14]
    setl al
    movzx eax, al
    mov [r14 - 8], rax
    add r13, 8
    jmp .dispatch

.bc_cmp_le:
    sub r14, 8
    mov rax, [r14 - 8]
    cmp rax, [r14]
    setle al
    movzx eax, al
    mov [r14 - 8], rax
    add r13, 8
    jmp .dispatch

.bc_cmp_gt:
    sub r14, 8
    mov rax, [r14 - 8]
    cmp rax, [r14]
    setg al
    movzx eax, al
    mov [r14 - 8], rax
    add r13, 8
    jmp .dispatch

.bc_cmp_ge:
    sub r14, 8
    mov rax, [r14 - 8]
    cmp rax, [r14]
    setge al
    movzx eax, al
    mov [r14 - 8], rax
    add r13, 8
    jmp .dispatch

; ─── OUTPUT ──────────────────────────────────────
.bc_out_int:
    movzx eax, word [r13 + 2] ; vreg index — unused for stack machine
    sub r14, 8
    mov rdi, [r14]          ; value to print
    ; Call rt_pri (print integer)
    ; For now, use inline syscall
    ; ... (emit inline int-to-string + sys_write)
    add r13, 8
    jmp .dispatch

.bc_out_str:
    sub r14, 8
    mov rsi, [r14]          ; string pointer
    ; Find string length (null-terminated)
    xor edx, edx
.str_len:
    cmp byte [rsi + rdx], 0
    je .str_len_done
    inc rdx
    jmp .str_len
.str_len_done:
    mov rax, 1              ; sys_write
    mov rdi, 1              ; stdout
    syscall
    add r13, 8
    jmp .dispatch

.bc_out_bool:
    sub r14, 8
    mov rax, [r14]
    ; Print "true\n", "false\n", or "neutral\n"
    test rax, rax
    jz .bool_neutral
    js .bool_false
    ; true
    lea rsi, [rel .str_true]
    mov rdx, 5
    jmp .bool_write
.bool_false:
    lea rsi, [rel .str_false]
    mov rdx, 6
    jmp .bool_write
.bool_neutral:
    lea rsi, [rel .str_neutral]
    mov rdx, 8
.bool_write:
    mov rax, 1
    mov rdi, 1
    syscall
    add r13, 8
    jmp .dispatch

.bc_out_char:
    sub r14, 8
    mov rax, [r14]
    mov [rsp - 8], al       ; store char on stack
    mov rax, 1
    mov rdi, 1
    lea rsi, [rsp - 8]
    mov rdx, 1
    syscall
    add r13, 8
    jmp .dispatch

.bc_out_float:
    ; Float output — call rt_prf
    sub r14, 8
    movq xmm0, [r14]
    mov rdi, 16             ; default precision
    call rt_prf
    add r13, 8
    jmp .dispatch

; ─── CONTROL FLOW ────────────────────────────────
.bc_jmp:
    movzx eax, word [r13 + 2] ; target offset
    lea r13, [bc_buffer + rax]
    jmp .dispatch

.bc_jmp_if:
    sub r14, 8
    mov rax, [r14]
    test rax, rax
    jz .jmp_if_skip
    movzx eax, word [r13 + 4]
    lea r13, [bc_buffer + rax]
    jmp .dispatch
.jmp_if_skip:
    add r13, 8
    jmp .dispatch

.bc_jmp_if_not:
    sub r14, 8
    mov rax, [r14]
    test rax, rax
    jnz .jmp_if_not_skip
    movzx eax, word [r13 + 4]
    lea r13, [bc_buffer + rax]
    jmp .dispatch
.jmp_if_not_skip:
    add r13, 8
    jmp .dispatch

; ─── HALT ────────────────────────────────────────
.bc_halt:
    ; Clean up and return
    add rsp, 2048
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ─── String constants ────────────────────────────
.str_true: db "true", 10
.str_false: db "false", 10
.str_neutral: db "neutral", 10

; Variable storage base (same as native codegen)
VAR_STORAGE_BASE equ 0x00440000
```

- [ ] **Step 2: Test interpreter with simple bytecode**

Run: manually construct bytecode for `output(42)` and verify it prints "42"

---

### Task 4: Integrate Bytecode Path into Codegen

**Covers:** Choosing native vs bytecode based on program size

**Files:**
- Modify: `codegen/codegen.asm` — add `--bytecode` flag handling

- [ ] **Step 1: Add bytecode mode selection**

In `codegen_init`, check if bytecode mode is enabled. If so, call `emit_bytecode` instead of `codegen_emit_all`.

- [ ] **Step 2: Test bytecode mode with `output(42)`**

Run: `./rexc test.rex -o test --bytecode && ./test`
Expected: Same output as native mode

---

### Task 5: Implement Remaining IR Opcodes in Bytecode

**Covers:** Complete bytecode coverage

- [ ] **Step 1: Add missing opcodes to emitter and interpreter**
  - All arithmetic (ABS_INT, MIN_INT, MAX_INT, SHL, SHR, SIGNUM)
  - All float operations
  - All char predicates
  - All collection operations
  - All string operations
  - All cast operations

- [ ] **Step 2: Run full test suite in bytecode mode**

Run: `./run_tests.sh` (with bytecode flag)
Expected: 23/23 pass

---

### Task 6: Optimize Bytecode Size

**Covers:** Achieve target binary sizes

- [ ] **Step 1: Implement variable-length encoding for common opcodes**
  - Single-byte opcodes for common operations
  - 2-byte opcodes for operations with small immediates

- [ ] **Step 2: Implement bytecode compression**
  - Run-length encoding for zero-filled variable regions
  - String deduplication

- [ ] **Step 3: Measure and verify target sizes**

Run: measure binary sizes for all test programs
Expected: `output(42)` ≤ 200 bytes, `output("hello world")` ≤ 150 bytes

---

### Task 7: Documentation and Integration

**Covers:** User-facing documentation

- [ ] **Step 1: Add `--bytecode` flag to compiler CLI**

- [ ] **Step 2: Update README with bytecode mode description**

- [ ] **Step 3: Add bytecode-specific tests**

---

## Verification Checklist

After all tasks:
1. `make clean && make` — zero warnings
2. `./run_tests.sh` — 23/23 pass (native mode)
3. `./run_tests.sh --bytecode` — 23/23 pass (bytecode mode)
4. `output(42)` native: ~190 bytes
5. `output(42)` bytecode: ≤ 200 bytes
6. `output("hello world")` bytecode: ≤ 150 bytes
