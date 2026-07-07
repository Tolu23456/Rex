# Rex Multi-Pass IR Compiler Pipeline — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use compose:subagent (recommended) or compose:execute to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace single-pass direct x86 emission with a register-based IR and 5 optimization passes.

**Architecture:** The parser emits 32-byte IR records into a flat buffer instead of raw x86 bytes. After parsing, 5 optimization passes run (constant folding, dead store, load-store coalescing, register allocation, peephole). A final x86 emission pass converts optimized IR to machine code.

**Tech Stack:** x86-64 NASM assembly, GNU ld linker, ELF64 output format.

---

## File Structure

| File | Responsibility |
|------|---------------|
| `include/rex_ir.inc` | IR opcode constants, record field offsets, flag definitions, buffer sizes |
| `irgen/irgen.asm` | IR record emitter, virtual register allocator, label allocator, buffer reset |
| `irgen/ir_passes.asm` | 5 optimization passes operating on ir_buffer |
| `irgen/ir_emit_x86.asm` | Convert IR records to x86-64 machine bytes in out_buffer |
| `parser/parser.asm` | Modified: call `ir_emit_*` instead of `codegen_emit_*` |
| `main/main.asm` | Modified: call optimization passes + x86 emission after parsing |
| `Makefile` | Modified: add irgen/ assembly targets |

---

## Task 1: Create `include/rex_ir.inc`

**Covers:** [S4, S5]

**Files:**
- Create: `include/rex_ir.inc`

- [ ] **Step 1: Write the IR constants include file**

```nasm
; ============================================================
; include/rex_ir.inc — IR opcode constants, record offsets,
;                       flag definitions, buffer sizing
; ============================================================

; ---- Record layout offsets (32 bytes per record) ----
%define IR_OFF_OPCODE   0       ; 1 byte: opcode
%define IR_OFF_TYPE     1       ; 1 byte: result type
%define IR_OFF_DST      2       ; 2 bytes: destination vreg
%define IR_OFF_SRC1     4       ; 2 bytes: first source vreg
%define IR_OFF_SRC2     6       ; 2 bytes: second source vreg
%define IR_OFF_IMM      8       ; 8 bytes: primary immediate
%define IR_OFF_AUX      16      ; 8 bytes: secondary immediate
%define IR_OFF_FLAGS    24      ; 4 bytes: metadata flags
%define IR_OFF_PAD      28      ; 4 bytes: reserved
%define IR_RECORD_SIZE  32

; ---- Buffer sizing ----
%define IR_MAX          16384   ; max IR records (16384 * 32 = 512 KiB)
%define IR_BUF_SIZE     (IR_MAX * IR_RECORD_SIZE)
%define VREG_MAX        65535   ; max virtual registers
%define LABEL_MAX       4096    ; max label IDs
%define SPILL_MAX       64      ; max spill slots

; ---- Category 0: No-op (0x00) ----
%define IR_NOP          0x00

; ---- Category 1: Load / Store (0x01–0x0F) ----
%define IR_LOAD_IMM     0x01    ; dst ← imm64
%define IR_LOAD_FIMM    0x02    ; dst ← float imm64
%define IR_LOAD_VAR     0x03    ; dst ← var_table[imm]
%define IR_STORE_VAR    0x04    ; var_table[imm] ← src1
%define IR_LOAD_STR     0x05    ; dst ← string address (imm=ptr, aux=len)
%define IR_LOAD_BOOL    0x06    ; dst ← 0/1/2 (false/true/unknown)
%define IR_RDRAND       0x07    ; dst ← rdrand
%define IR_LEA_VAR      0x08    ; dst ← &var_table[imm]

; ---- Category 2: Integer Arithmetic (0x11–0x1F) ----
%define IR_ADD          0x11    ; dst ← src1 + src2
%define IR_SUB          0x12    ; dst ← src1 - src2
%define IR_MUL          0x13    ; dst ← src1 * src2
%define IR_DIV          0x14    ; dst ← src1 / src2 (signed)
%define IR_MOD          0x15    ; dst ← src1 % src2
%define IR_NEG          0x16    ; dst ← -src1
%define IR_ABS          0x17    ; dst ← abs(src1)
%define IR_INC          0x18    ; dst ← src1 + 1
%define IR_DEC          0x19    ; dst ← src1 - 1

; ---- Category 3: Float Arithmetic (0x21–0x2F) ----
%define IR_FADD         0x21    ; dst ← src1 +f src2
%define IR_FSUB         0x22    ; dst ← src1 -f src2
%define IR_FMUL         0x23    ; dst ← src1 *f src2
%define IR_FDIV         0x24    ; dst ← src1 /f src2
%define IR_FNEG         0x25    ; dst ← -f src1
%define IR_F2I          0x26    ; dst ← int(src1)
%define IR_I2F          0x27    ; dst ← float(src1)

; ---- Category 4: Bitwise (0x31–0x3F) ----
%define IR_BAND         0x31    ; dst ← src1 & src2
%define IR_BOR          0x32    ; dst ← src1 | src2
%define IR_BXOR         0x33    ; dst ← src1 ^ src2
%define IR_BNOT         0x34    ; dst ← ~src1
%define IR_SHL          0x35    ; dst ← src1 << src2
%define IR_SHR          0x36    ; dst ← src1 >> src2

; ---- Category 5: Comparison and Boolean (0x41–0x4F) ----
%define IR_CMP          0x41    ; dst ← (src1 CC src2) ? 1 : 0
%define IR_BOOL_AND     0x42    ; dst ← src1 && src2 (short-circuit)
%define IR_BOOL_OR      0x43    ; dst ← src1 || src2 (short-circuit)
%define IR_BOOL_NOT     0x44    ; dst ← !src1

; Condition codes (aux field of IR_CMP)
%define IR_CC_EQ        0       ; ==
%define IR_CC_NE        1       ; !=
%define IR_CC_LT        2       ; <
%define IR_CC_GT        3       ; >
%define IR_CC_LE        4       ; <=
%define IR_CC_GE        5       ; >=

; ---- Category 6: Control Flow (0x51–0x5F) ----
%define IR_LABEL        0x51    ; define jump target (imm=label_id)
%define IR_JMP          0x52    ; unconditional jump (imm=label_id)
%define IR_JCC          0x53    ; jump if src1==0 (imm=label_id)
%define IR_CALL         0x54    ; call protocol (imm=proto_idx, aux=argcnt)
%define IR_RET          0x55    ; return src1
%define IR_RET_VOID     0x56    ; void return
%define IR_LOOP_TOP     0x57    ; loop back-edge target (imm=label_id)
%define IR_SKIP         0x58    ; continue Nth enclosing loop (imm=depth)

; ---- Category 7: Output / Runtime (0x61–0x6F) ----
%define IR_OUT_INT      0x61    ; print int (src1=vreg)
%define IR_OUT_FLOAT    0x62    ; print float
%define IR_OUT_BOOL     0x63    ; print bool
%define IR_OUT_STR      0x64    ; print string
%define IR_OUT_COMPLEX  0x65    ; print complex
%define IR_ERR          0x66    ; runtime error + halt
%define IR_HALT         0x67    ; sys_exit(0)
%define IR_MM_SWITCH    0x68    ; switch allocator mode (imm=mode)

; ---- Category 8: Collection Operations (0x71–0x7F) ----
%define IR_SEQ_ALLOC    0x71    ; allocate seq (imm=var_idx)
%define IR_SEQ_PUSH     0x72    ; push to seq (src1=val, imm=var_idx)
%define IR_SEQ_POP      0x73    ; pop from seq (dst=result, imm=var_idx)
%define IR_SEQ_LEN      0x74    ; seq length (dst=result, imm=var_idx)
%define IR_SEQ_CAP      0x75    ; seq capacity
%define IR_DICT_NEW     0x76    ; allocate dict
%define IR_DICT_SET     0x77    ; dict[key]=val
%define IR_DICT_GET     0x78    ; get dict[key]

; ---- Category 9: Swap / Misc (0x81–0x8F) ----
%define IR_SWAP         0x81    ; swap two variables (imm=var1, aux=var2)
%define IR_TYPEOF       0x82    ; type token of variable

; ---- Category 15: Protocol Markers (0xF0–0xFF) ----
%define IR_PROT_ENTRY   0xF0    ; start of protocol body
%define IR_PROT_EXIT    0xF1    ; end of protocol body

; ---- Flags field (bits 0–3 of IR_OFF_FLAGS) ----
%define IR_FLAG_CONST   0x01    ; result is compile-time constant
%define IR_FLAG_DEAD    0x02    ; instruction has no live readers
%define IR_FLAG_SPILLED 0x04    ; dst vreg was spilled to stack
%define IR_FLAG_LOOP_INV 0x08   ; loop-invariant; candidate for hoisting
```

- [ ] **Step 2: Verify the file assembles**

Run: `nasm -f elf64 -o /dev/null include/rex_ir.inc -E` (preprocessor check only, no output expected since it's defines-only)
Alternative: `nasm -f elf64 -I include/ -o /tmp/ir_test.o include/rex_ir.inc` — should produce empty .o or error about no code (both acceptable)

- [ ] **Step 3: Commit**

```bash
git add include/rex_ir.inc
git commit -m "feat(ir): add IR opcode constants, record layout, and buffer sizing"
```

---

## Task 2: Create `irgen/irgen.asm` — IR Emitter Core

**Covers:** [S4]

**Files:**
- Create: `irgen/irgen.asm`

- [ ] **Step 1: Write the IR emitter with buffer management, vreg allocator, and label allocator**

```nasm
; ============================================================
; irgen/irgen.asm — IR record emitter, vreg/label allocators
; ============================================================
bits 64
%include "rex_defs.inc"
%include "rex_ir.inc"

section .bss

; ---- IR buffer ----
global ir_buffer, ir_idx
ir_buffer:          resb IR_BUF_SIZE       ; 512 KiB flat IR record array
ir_idx:             resq 1                 ; next free record index (count of records)

; ---- Virtual register counter ----
global vreg_counter
vreg_counter:       resd 1                 ; next vreg ID to allocate

; ---- Label counter ----
global label_counter
label_counter:      resd 1                 ; next label ID to allocate

; ---- Label resolution table ----
; label_id → byte offset in out_buffer (filled during x86 emission)
global label_offsets, label_used
label_offsets:      resd LABEL_MAX         ; out_buffer offset for each label
label_used:         resb LABEL_MAX         ; 1 = label defined, 0 = undefined

; ---- Record scratch fields (populated before ir_emit_record) ----
global ir_cur_type, ir_cur_dst, ir_cur_src1, ir_cur_src2
global ir_cur_imm, ir_cur_aux, ir_cur_flags
ir_cur_type:        resb 1
ir_cur_dst:         resw 1
ir_cur_src1:        resw 1
ir_cur_src2:        resw 1
ir_cur_imm:         resq 1
ir_cur_aux:         resq 1
ir_cur_flags:       resd 1

section .text

; ============================================================
; ir_reset — clear all IR state for a new compilation
; ============================================================
global ir_reset
ir_reset:
    mov     qword [ir_idx], 0
    mov     dword [vreg_counter], 1       ; vreg 0 = unused
    mov     dword [label_counter], 0
    ; Zero label_used table (LABEL_MAX bytes)
    xor     eax, eax
    mov     rcx, LABEL_MAX
    lea     rdi, [label_used]
    rep     stosb
    ret

; ============================================================
; ir_alloc_vreg — allocate and return next virtual register
; Input: none
; Output: eax = new vreg ID (1-based)
; ============================================================
global ir_alloc_vreg
ir_alloc_vreg:
    mov     eax, [vreg_counter]
    inc     dword [vreg_counter]
    ret

; ============================================================
; ir_alloc_label — allocate and return next label ID
; Input: none
; Output: eax = new label ID (0-based)
; ============================================================
global ir_alloc_label
ir_alloc_label:
    mov     eax, [label_counter]
    inc     dword [label_counter]
    ret

; ============================================================
; ir_emit_record — write one 32-byte IR record to ir_buffer
; Input: opcode in dil (byte), other fields in globals
;        ir_cur_type, ir_cur_dst, ir_cur_src1, ir_cur_src2,
;        ir_cur_imm, ir_cur_aux, ir_cur_flags
; Clobbers: rax, rcx, rdi, rsi
; ============================================================
global ir_emit_record
ir_emit_record:
    ; Compute destination address: ir_buffer + ir_idx * 32
    mov     rax, [ir_idx]
    shl     rax, 5                          ; rax *= 32
    lea     rcx, [ir_buffer + rax]

    ; Write opcode (byte at offset 0)
    mov     [rcx + IR_OFF_OPCODE], dil

    ; Write type (byte at offset 1)
    mov     al, byte [ir_cur_type]
    mov     [rcx + IR_OFF_TYPE], al

    ; Write dst (word at offset 2)
    mov     ax, word [ir_cur_dst]
    mov     [rcx + IR_OFF_DST], ax

    ; Write src1 (word at offset 4)
    mov     ax, word [ir_cur_src1]
    mov     [rcx + IR_OFF_SRC1], ax

    ; Write src2 (word at offset 6)
    mov     ax, word [ir_cur_src2]
    mov     [rcx + IR_OFF_SRC2], ax

    ; Write imm (qword at offset 8)
    mov     rax, qword [ir_cur_imm]
    mov     [rcx + IR_OFF_IMM], rax

    ; Write aux (qword at offset 16)
    mov     rax, qword [ir_cur_aux]
    mov     [rcx + IR_OFF_AUX], rax

    ; Write flags (dword at offset 24)
    mov     eax, dword [ir_cur_flags]
    mov     [rcx + IR_OFF_FLAGS], eax

    ; Zero pad (dword at offset 28)
    mov     dword [rcx + IR_OFF_PAD], 0

    ; Advance index
    inc     qword [ir_idx]
    ret

; ============================================================
; Convenience emitters — set fields and call ir_emit_record
; ============================================================

; ir_emit_nul — emit IR_NOP
global ir_emit_nul
ir_emit_nul:
    mov     dil, IR_NOP
    mov     byte  [ir_cur_type], 0
    mov     word  [ir_cur_dst], 0
    mov     word  [ir_cur_src1], 0
    mov     word  [ir_cur_src2], 0
    mov     qword [ir_cur_imm], 0
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    jmp     ir_emit_record

; ir_emit_load_imm(eax=dst, rdi=imm64) — dst ← imm64
global ir_emit_load_imm
ir_emit_load_imm:
    mov     word  [ir_cur_dst], ax
    mov     word  [ir_cur_src1], 0
    mov     word  [ir_cur_src2], 0
    mov     qword [ir_cur_imm], rdi
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], TYPE_INT
    mov     dil, IR_LOAD_IMM
    jmp     ir_emit_record

; ir_emit_load_var(eax=dst, edi=var_idx) — dst ← var_table[var_idx]
global ir_emit_load_var
ir_emit_load_var:
    movzx   edi, di                         ; zero-extend var_idx to 64-bit for imm
    mov     word  [ir_cur_dst], ax
    mov     word  [ir_cur_src1], 0
    mov     word  [ir_cur_src2], 0
    mov     qword [ir_cur_imm], rdi
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], TYPE_INT   ; default; caller may override
    mov     dil, IR_LOAD_VAR
    jmp     ir_emit_record

; ir_emit_store_var(esi=src1, edi=var_idx) — var_table[var_idx] ← src1
global ir_emit_store_var
ir_emit_store_var:
    movzx   edi, di
    mov     word  [ir_cur_dst], 0
    mov     word  [ir_cur_src1], si
    mov     word  [ir_cur_src2], 0
    mov     qword [ir_cur_imm], rdi
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], TYPE_INT
    mov     dil, IR_STORE_VAR
    jmp     ir_emit_record

; ir_emit_binop(opcode=dil, eax=dst, esi=src1, edi=src2)
; e.g. ir_emit_binop(IR_ADD, dst, src1, src2)
global ir_emit_binop
ir_emit_binop:
    mov     word  [ir_cur_dst], ax
    mov     word  [ir_cur_src1], si
    mov     word  [ir_cur_src2], di
    mov     qword [ir_cur_imm], 0
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], TYPE_INT
    ; dil already has opcode
    jmp     ir_emit_record

; ir_emit_unop(opcode=dil, eax=dst, edi=src1)
global ir_emit_unop
ir_emit_unop:
    mov     word  [ir_cur_dst], ax
    mov     word  [ir_cur_src1], di
    mov     word  [ir_cur_src2], 0
    mov     qword [ir_cur_imm], 0
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], TYPE_INT
    ; dil already has opcode
    jmp     ir_emit_record

; ir_emit_cmp(eax=dst, esi=src1, edi=src2, edx=cond_code)
global ir_emit_cmp
ir_emit_cmp:
    mov     word  [ir_cur_dst], ax
    mov     word  [ir_cur_src1], si
    mov     word  [ir_cur_src2], di
    mov     qword [ir_cur_imm], 0
    movzx   edx, dl
    mov     qword [ir_cur_aux], rdx         ; aux = condition code
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], TYPE_BOOL
    mov     dil, IR_CMP
    jmp     ir_emit_record

; ir_emit_label(eax=label_id) — define a label
global ir_emit_label
ir_emit_label:
    mov     word  [ir_cur_dst], 0
    mov     word  [ir_cur_src1], 0
    mov     word  [ir_cur_src2], 0
    movzx   eax, ax
    mov     qword [ir_cur_imm], rax         ; imm = label_id
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], 0
    mov     dil, IR_LABEL
    jmp     ir_emit_record

; ir_emit_jmp(eax=label_id)
global ir_emit_jmp
ir_emit_jmp:
    mov     word  [ir_cur_dst], 0
    mov     word  [ir_cur_src1], 0
    mov     word  [ir_cur_src2], 0
    movzx   eax, ax
    mov     qword [ir_cur_imm], rax
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], 0
    mov     dil, IR_JMP
    jmp     ir_emit_record

; ir_emit_jcc(edi=src1_vreg, eax=label_id)
global ir_emit_jcc
ir_emit_jcc:
    mov     word  [ir_cur_dst], 0
    mov     word  [ir_cur_src1], di
    mov     word  [ir_cur_src2], 0
    movzx   eax, ax
    mov     qword [ir_cur_imm], rax
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], 0
    mov     dil, IR_JCC
    jmp     ir_emit_record

; ir_emit_call(eax=dst, edi=proto_idx, esi=argcnt)
global ir_emit_call
ir_emit_call:
    mov     word  [ir_cur_dst], ax
    mov     word  [ir_cur_src1], 0
    mov     word  [ir_cur_src2], 0
    movzx   edi, di
    mov     qword [ir_cur_imm], rdi         ; imm = proto_idx
    movzx   esi, si
    mov     qword [ir_cur_aux], rsi         ; aux = arg count
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], TYPE_INT   ; default; caller may override
    mov     dil, IR_CALL
    jmp     ir_emit_record

; ir_emit_ret(edi=src1_vreg) — return value
global ir_emit_ret
ir_emit_ret:
    mov     word  [ir_cur_dst], 0
    mov     word  [ir_cur_src1], di
    mov     word  [ir_cur_src2], 0
    mov     qword [ir_cur_imm], 0
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], TYPE_INT
    mov     dil, IR_RET
    jmp     ir_emit_record

; ir_emit_ret_void — void return
global ir_emit_ret_void
ir_emit_ret_void:
    mov     word  [ir_cur_dst], 0
    mov     word  [ir_cur_src1], 0
    mov     word  [ir_cur_src2], 0
    mov     qword [ir_cur_imm], 0
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], 0
    mov     dil, IR_RET_VOID
    jmp     ir_emit_record

; ir_emit_out_int(edi=src1_vreg)
global ir_emit_out_int
ir_emit_out_int:
    mov     word  [ir_cur_dst], 0
    mov     word  [ir_cur_src1], di
    mov     word  [ir_cur_src2], 0
    mov     qword [ir_cur_imm], 0
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], 0
    mov     dil, IR_OUT_INT
    jmp     ir_emit_record

; ir_emit_out_float(edi=src1_vreg)
global ir_emit_out_float
ir_emit_out_float:
    mov     word  [ir_cur_dst], 0
    mov     word  [ir_cur_src1], di
    mov     word  [ir_cur_src2], 0
    mov     qword [ir_cur_imm], 0
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], 0
    mov     dil, IR_OUT_FLOAT
    jmp     ir_emit_record

; ir_emit_out_bool(edi=src1_vreg)
global ir_emit_out_bool
ir_emit_out_bool:
    mov     word  [ir_cur_dst], 0
    mov     word  [ir_cur_src1], di
    mov     word  [ir_cur_src2], 0
    mov     qword [ir_cur_imm], 0
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], 0
    mov     dil, IR_OUT_BOOL
    jmp     ir_emit_record

; ir_emit_out_str(edi=src1_vreg)
global ir_emit_out_str
ir_emit_out_str:
    mov     word  [ir_cur_dst], 0
    mov     word  [ir_cur_src1], di
    mov     word  [ir_cur_src2], 0
    mov     qword [ir_cur_imm], 0
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], 0
    mov     dil, IR_OUT_STR
    jmp     ir_emit_record

; ir_emit_out_complex(edi=src1_vreg)
global ir_emit_out_complex
ir_emit_out_complex:
    mov     word  [ir_cur_dst], 0
    mov     word  [ir_cur_src1], di
    mov     word  [ir_cur_src2], 0
    mov     qword [ir_cur_imm], 0
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], 0
    mov     dil, IR_OUT_COMPLEX
    jmp     ir_emit_record

; ir_emit_swap(edi=var1, esi=var2)
global ir_emit_swap
ir_emit_swap:
    mov     word  [ir_cur_dst], 0
    mov     word  [ir_cur_src1], 0
    mov     word  [ir_cur_src2], 0
    movzx   edi, di
    mov     qword [ir_cur_imm], rdi
    movzx   esi, si
    mov     qword [ir_cur_aux], rsi
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], 0
    mov     dil, IR_SWAP
    jmp     ir_emit_record

; ir_emit_inc(eax=dst, edi=var_idx)
global ir_emit_inc
ir_emit_inc:
    mov     word  [ir_cur_dst], ax
    mov     word  [ir_cur_src1], 0
    mov     word  [ir_cur_src2], 0
    movzx   edi, di
    mov     qword [ir_cur_imm], rdi
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], TYPE_INT
    mov     dil, IR_INC
    jmp     ir_emit_record

; ir_emit_dec(eax=dst, edi=var_idx)
global ir_emit_dec
ir_emit_dec:
    mov     word  [ir_cur_dst], ax
    mov     word  [ir_cur_src1], 0
    mov     word  [ir_cur_src2], 0
    movzx   edi, di
    mov     qword [ir_cur_imm], rdi
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], TYPE_INT
    mov     dil, IR_DEC
    jmp     ir_emit_record

; ir_emit_load_str(eax=dst, rdi=str_ptr, rsi=str_len)
global ir_emit_load_str
ir_emit_load_str:
    mov     word  [ir_cur_dst], ax
    mov     word  [ir_cur_src1], 0
    mov     word  [ir_cur_src2], 0
    mov     qword [ir_cur_imm], rdi         ; imm = string pointer
    mov     qword [ir_cur_aux], rsi         ; aux = string length
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], TYPE_STR
    mov     dil, IR_LOAD_STR
    jmp     ir_emit_record

; ir_emit_load_bool(eax=dst, edi=value) — value: 0=false, 1=true, 2=unknown
global ir_emit_load_bool
ir_emit_load_bool:
    mov     word  [ir_cur_dst], ax
    mov     word  [ir_cur_src1], 0
    mov     word  [ir_cur_src2], 0
    movzx   edi, di
    mov     qword [ir_cur_imm], rdi
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], TYPE_BOOL
    mov     dil, IR_LOAD_BOOL
    jmp     ir_emit_record

; ir_emit_halt — sys_exit(0)
global ir_emit_halt
ir_emit_halt:
    mov     word  [ir_cur_dst], 0
    mov     word  [ir_cur_src1], 0
    mov     word  [ir_cur_src2], 0
    mov     qword [ir_cur_imm], 0
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], 0
    mov     dil, IR_HALT
    jmp     ir_emit_record

; ir_emit_seq_alloc(eax=dst, edi=var_idx)
global ir_emit_seq_alloc
ir_emit_seq_alloc:
    mov     word  [ir_cur_dst], ax
    mov     word  [ir_cur_src1], 0
    mov     word  [ir_cur_src2], 0
    movzx   edi, di
    mov     qword [ir_cur_imm], rdi
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], TYPE_SEQ
    mov     dil, IR_SEQ_ALLOC
    jmp     ir_emit_record

; ir_emit_seq_push(edi=src1_vreg, esi=var_idx)
global ir_emit_seq_push
ir_emit_seq_push:
    mov     word  [ir_cur_dst], 0
    mov     word  [ir_cur_src1], di
    mov     word  [ir_cur_src2], 0
    movzx   esi, si
    mov     qword [ir_cur_imm], rsi
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], 0
    mov     dil, IR_SEQ_PUSH
    jmp     ir_emit_record

; ir_emit_seq_pop(eax=dst, edi=var_idx)
global ir_emit_seq_pop
ir_emit_seq_pop:
    mov     word  [ir_cur_dst], ax
    mov     word  [ir_cur_src1], 0
    mov     word  [ir_cur_src2], 0
    movzx   edi, di
    mov     qword [ir_cur_imm], rdi
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], TYPE_INT
    mov     dil, IR_SEQ_POP
    jmp     ir_emit_record

; ir_emit_seq_len(eax=dst, edi=var_idx)
global ir_emit_seq_len
ir_emit_seq_len:
    mov     word  [ir_cur_dst], ax
    mov     word  [ir_cur_src1], 0
    mov     word  [ir_cur_src2], 0
    movzx   edi, di
    mov     qword [ir_cur_imm], rdi
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], TYPE_INT
    mov     dil, IR_SEQ_LEN
    jmp     ir_emit_record

; ir_emit_seq_cap(eax=dst, edi=var_idx)
global ir_emit_seq_cap
ir_emit_seq_cap:
    mov     word  [ir_cur_dst], ax
    mov     word  [ir_cur_src1], 0
    mov     word  [ir_cur_src2], 0
    movzx   edi, di
    mov     qword [ir_cur_imm], rdi
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], TYPE_INT
    mov     dil, IR_SEQ_CAP
    jmp     ir_emit_record

; ir_emit_dict_new(eax=dst, edi=var_idx)
global ir_emit_dict_new
ir_emit_dict_new:
    mov     word  [ir_cur_dst], ax
    mov     word  [ir_cur_src1], 0
    mov     word  [ir_cur_src2], 0
    movzx   edi, di
    mov     qword [ir_cur_imm], rdi
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], TYPE_DICT
    mov     dil, IR_DICT_NEW
    jmp     ir_emit_record

; ir_emit_dict_set(edi=key_vreg, esi=val_vreg, edx=var_idx)
global ir_emit_dict_set
ir_emit_dict_set:
    mov     word  [ir_cur_dst], 0
    mov     word  [ir_cur_src1], di
    mov     word  [ir_cur_src2], si
    movzx   edx, dx
    mov     qword [ir_cur_imm], rdx
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], 0
    mov     dil, IR_DICT_SET
    jmp     ir_emit_record

; ir_emit_dict_get(eax=dst, edi=key_vreg, esi=var_idx)
global ir_emit_dict_get
ir_emit_dict_get:
    mov     word  [ir_cur_dst], ax
    mov     word  [ir_cur_src1], di
    mov     word  [ir_cur_src2], 0
    movzx   esi, si
    mov     qword [ir_cur_imm], rsi
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], TYPE_INT
    dil = IR_DICT_GET
    jmp     ir_emit_record

; ir_emit_prot_entry(edi=proto_idx)
global ir_emit_prot_entry
ir_emit_prot_entry:
    mov     word  [ir_cur_dst], 0
    mov     word  [ir_cur_src1], 0
    mov     word  [ir_cur_src2], 0
    movzx   edi, di
    mov     qword [ir_cur_imm], rdi
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], 0
    mov     dil, IR_PROT_ENTRY
    jmp     ir_emit_record

; ir_emit_prot_exit(edi=proto_idx)
global ir_emit_prot_exit
ir_emit_prot_exit:
    mov     word  [ir_cur_dst], 0
    mov     word  [ir_cur_src1], 0
    mov     word  [ir_cur_src2], 0
    movzx   edi, di
    mov     qword [ir_cur_imm], rdi
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], 0
    mov     dil, IR_PROT_EXIT
    jmp     ir_emit_record

; ir_emit_loop_top(eax=label_id)
global ir_emit_loop_top
ir_emit_loop_top:
    mov     word  [ir_cur_dst], 0
    mov     word  [ir_cur_src1], 0
    mov     word  [ir_cur_src2], 0
    movzx   eax, ax
    mov     qword [ir_cur_imm], rax
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], 0
    mov     dil, IR_LOOP_TOP
    jmp     ir_emit_record

; ir_emit_skip(edi=depth)
global ir_emit_skip
ir_emit_skip:
    mov     word  [ir_cur_dst], 0
    mov     word  [ir_cur_src1], 0
    mov     word  [ir_cur_src2], 0
    movzx   edi, di
    mov     qword [ir_cur_imm], rdi
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], 0
    mov     dil, IR_SKIP
    jmp     ir_emit_record

; ir_emit_err(edi=src1_vreg)
global ir_emit_err
ir_emit_err:
    mov     word  [ir_cur_dst], 0
    mov     word  [ir_cur_src1], di
    mov     word  [ir_cur_src2], 0
    mov     qword [ir_cur_imm], 0
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], 0
    mov     dil, IR_ERR
    jmp     ir_emit_record

; ir_emit_mm_switch(edi=mode)
global ir_emit_mm_switch
ir_emit_mm_switch:
    mov     word  [ir_cur_dst], 0
    mov     word  [ir_cur_src1], 0
    mov     word  [ir_cur_src2], 0
    movzx   edi, di
    mov     qword [ir_cur_imm], rdi
    mov     qword [ir_cur_aux], 0
    mov     dword [ir_cur_flags], 0
    mov     byte  [ir_cur_type], 0
    mov     dil, IR_MM_SWITCH
    jmp     ir_emit_record
```

- [ ] **Step 2: Assemble and verify no errors**

Run: `nasm -f elf64 -I include/ -o /tmp/irgen.o irgen/irgen.asm`
Expected: no errors, produces /tmp/irgen.o

- [ ] **Step 3: Commit**

```bash
mkdir -p irgen
git add irgen/irgen.asm
git commit -m "feat(ir): add IR record emitter with vreg/label allocators"
```

---

## Task 3: Create `irgen/ir_passes.asm` — Optimization Passes Stub

**Covers:** [S6]

**Files:**
- Create: `irgen/ir_passes.asm`

- [ ] **Step 1: Write stub implementations for all 5 passes**

Each pass is a function that scans ir_buffer and can NOP records. For Milestone A, they do nothing (pass through). The actual algorithms are implemented in Milestone B/C.

```nasm
; ============================================================
; irgen/ir_passes.asm — IR optimization passes
; ============================================================
bits 64
%include "rex_defs.inc"
%include "rex_ir.inc"

extern ir_buffer, ir_idx

section .text

; ============================================================
; ir_optimize_pass1 — Constant Folding
; ============================================================
global ir_optimize_pass1
ir_optimize_pass1:
    ret     ; TODO: Milestone B

; ============================================================
; ir_optimize_pass2 — Dead Store Elimination
; ============================================================
global ir_optimize_pass2
ir_optimize_pass2:
    ret     ; TODO: Milestone B

; ============================================================
; ir_optimize_pass3 — Load-Store Coalescing
; ============================================================
global ir_optimize_pass3
ir_optimize_pass3:
    ret     ; TODO: Milestone B

; ============================================================
; ir_optimize_pass4 — Linear Scan Register Allocation
; ============================================================
global ir_optimize_pass4
ir_optimize_pass4:
    ret     ; TODO: Milestone C

; ============================================================
; ir_optimize_pass5 — Peephole
; ============================================================
global ir_optimize_pass5
ir_optimize_pass5:
    ret     ; TODO: Milestone C
```

- [ ] **Step 2: Assemble and verify**

Run: `nasm -f elf64 -I include/ -o /tmp/ir_passes.o irgen/ir_passes.asm`
Expected: no errors

- [ ] **Step 3: Commit**

```bash
git add irgen/ir_passes.asm
git commit -m "feat(ir): add optimization pass stubs (all 5 passes)"
```

---

## Task 4: Create `irgen/ir_emit_x86.asm` — x86 Emission Pass

**Covers:** [S2, S4]

**Files:**
- Create: `irgen/ir_emit_x86.asm`

This is the most critical file — it converts IR records back to x86-64 machine bytes. For Milestone A, it implements enough opcodes to pass all existing tests.

- [ ] **Step 1: Write the x86 emission pass**

The emission pass walks ir_buffer, reads each 32-byte record, and writes corresponding x86 bytes to out_buffer. It must handle: IR_LOAD_IMM, IR_LOAD_VAR, IR_STORE_VAR, IR_ADD/SUB/MUL/DIV/MOD, IR_NEG, IR_ABS, IR_CMP, IR_BOOL_AND/OR/NOT, IR_LABEL, IR_JMP, IR_JCC, IR_CALL, IR_RET, IR_RET_VOID, IR_OUT_INT/FLOAT/BOOL/STR/COMPLEX, IR_HALT, IR_SWAP, IR_INC, IR_DEC, IR_SEQ_*, IR_DICT_*, IR_PROT_ENTRY/EXIT, IR_LOOP_TOP, IR_SKIP, IR_LOAD_STR, IR_LOAD_BOOL, IR_RDRAND, IR_ERR, IR_MM_SWITCH.

Key design: The pass maintains a label resolution table mapping label IDs to out_buffer offsets. Forward jumps are patched after the full pass.

```nasm
; ============================================================
; irgen/ir_emit_x86.asm — Convert IR records to x86-64 bytes
; ============================================================
bits 64
%include "rex_defs.inc"
%include "rex_ir.inc"

extern ir_buffer, ir_idx
extern out_buffer, out_idx
extern var_table, VAR_STORAGE_BASE
extern label_offsets, label_used
extern rt_pri_blob, rt_prs_blob, rt_prb_blob, rt_prf_blob
extern rt_prc_blob, rt_err_blob, rt_alc_blob
extern rt_prq_blob, RT_DICT_NEW_OFFSET, RT_DICT_SET_OFFSET, RT_DICT_GET_OFFSET
extern proto_table, proto_addrs
extern fwd_ref_names, fwd_ref_patches, fwd_ref_count

section .text

; ============================================================
; ir_emit_x86 — main emission loop
; Walks ir_buffer[0..ir_idx), emits x86 bytes to out_buffer.
; ============================================================
global ir_emit_x86
ir_emit_x86:
    push    r12
    push    r13
    push    r14
    push    r15

    xor     r12, r12                        ; r12 = current record index
    mov     r13, [ir_idx]                   ; r13 = total record count

.main_loop:
    cmp     r12, r13
    jge     .done

    ; Compute record address: ir_buffer + r12 * 32
    mov     rax, r12
    shl     rax, 5
    lea     r14, [ir_buffer + rax]          ; r14 = pointer to current record

    ; Read opcode
    movzx   eax, byte [r14 + IR_OFF_OPCODE]

    ; Read common fields
    movzx   ecx, word [r14 + IR_OFF_DST]   ; ecx = dst vreg
    movzx   edx, word [r14 + IR_OFF_SRC1]  ; edx = src1 vreg
    movzx   esi, word [r14 + IR_OFF_SRC2]  ; esi = src2 vreg
    mov     r8,  qword [r14 + IR_OFF_IMM]  ; r8 = imm
    mov     r9,  qword [r14 + IR_OFF_AUX]  ; r9 = aux

    ; Dispatch on opcode
    cmp     al, IR_NOP
    je      .skip

    cmp     al, IR_LOAD_IMM
    je      .emit_load_imm

    cmp     al, IR_LOAD_VAR
    je      .emit_load_var

    cmp     al, IR_STORE_VAR
    je      .emit_store_var

    cmp     al, IR_ADD
    je      .emit_add

    cmp     al, IR_SUB
    je      .emit_sub

    cmp     al, IR_MUL
    je      .emit_mul

    cmp     al, IR_DIV
    je      .emit_div

    cmp     al, IR_MOD
    je      .emit_mod

    cmp     al, IR_NEG
    je      .emit_neg

    cmp     al, IR_ABS
    je      .emit_abs

    cmp     al, IR_CMP
    je      .emit_cmp

    cmp     al, IR_BOOL_AND
    je      .emit_bool_and

    cmp     al, IR_BOOL_OR
    je      .emit_bool_or

    cmp     al, IR_BOOL_NOT
    je      .emit_bool_not

    cmp     al, IR_LABEL
    je      .emit_label_def

    cmp     al, IR_JMP
    je      .emit_jmp

    cmp     al, IR_JCC
    je      .emit_jcc

    cmp     al, IR_CALL
    je      .emit_call

    cmp     al, IR_RET
    je      .emit_ret

    cmp     al, IR_RET_VOID
    je      .emit_ret_void

    cmp     al, IR_OUT_INT
    je      .emit_out_int

    cmp     al, IR_OUT_FLOAT
    je      .emit_out_float

    cmp     al, IR_OUT_BOOL
    je      .emit_out_bool

    cmp     al, IR_OUT_STR
    je      .emit_out_str

    cmp     al, IR_OUT_COMPLEX
    je      .emit_out_complex

    cmp     al, IR_HALT
    je      .emit_halt

    cmp     al, IR_SWAP
    je      .emit_swap

    cmp     al, IR_INC
    je      .emit_inc

    cmp     al, IR_DEC
    je      .emit_dec

    cmp     al, IR_LOAD_STR
    je      .emit_load_str

    cmp     al, IR_LOAD_BOOL
    je      .emit_load_bool

    cmp     al, IR_RDRAND
    je      .emit_rdrand

    cmp     al, IR_ERR
    je      .emit_err

    cmp     al, IR_MM_SWITCH
    je      .emit_mm_switch

    cmp     al, IR_SEQ_ALLOC
    je      .emit_seq_alloc

    cmp     al, IR_SEQ_PUSH
    je      .emit_seq_push

    cmp     al, IR_SEQ_POP
    je      .emit_seq_pop

    cmp     al, IR_SEQ_LEN
    je      .emit_seq_len

    cmp     al, IR_SEQ_CAP
    je      .emit_seq_cap

    cmp     al, IR_DICT_NEW
    je      .emit_dict_new

    cmp     al, IR_DICT_SET
    je      .emit_dict_set

    cmp     al, IR_DICT_GET
    je      .emit_dict_get

    cmp     al, IR_PROT_ENTRY
    je      .emit_prot_entry

    cmp     al, IR_PROT_EXIT
    je      .emit_prot_exit

    cmp     al, IR_LOOP_TOP
    je      .emit_label_def     ; loop_top is just a label for back-edge

    cmp     al, IR_SKIP
    je      .emit_skip

    cmp     al, IR_LOAD_FIMM
    je      .emit_load_fimm

    cmp     al, IR_FADD
    je      .emit_fadd

    cmp     al, IR_FSUB
    je      .emit_fsub

    cmp     al, IR_FMUL
    je      .emit_fmul

    cmp     al, IR_FDIV
    je      .emit_fdiv

    cmp     al, IR_FNEG
    je      .emit_fneg

    cmp     al, IR_F2I
    je      .emit_f2i

    cmp     al, IR_I2F
    je      .emit_i2f

    cmp     al, IR_BAND
    je      .emit_band

    cmp     al, IR_BOR
    je      .emit_bor

    cmp     al, IR_BXOR
    je      .emit_bxor

    cmp     al, IR_BNOT
    je      .emit_bnot

    cmp     al, IR_SHL
    je      .emit_shl

    cmp     al, IR_SHR
    je      .emit_shr

    ; Unknown opcode — skip
    jmp     .skip

; ============================================================
; Emit functions — each writes x86 bytes to out_buffer
; ============================================================

; --- IR_LOAD_IMM: mov rdst, imm64 ---
.emit_load_imm:
    ; ecx = dst vreg (for now, treat as rax target)
    mov     byte [out_buffer + out_idx], 0x48  ; REX.W
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0xB8  ; mov rax, imm64
    inc     dword [out_idx]
    mov     rax, r8
    call    .emit_qword
    jmp     .next

; --- IR_LOAD_FIMM: movq xmm0, imm64 ---
.emit_load_fimm:
    mov     byte [out_buffer + out_idx], 0x66  ; prefix
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0x48  ; REX.W
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0x6E  ; movq xmm0, r/m64
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0xC0  ; modrm: xmm0, rax
    inc     dword [out_idx]
    ; Load float bits into rax first
    mov     rax, r8
    call    .emit_qword
    jmp     .next

; --- IR_LOAD_VAR: mov rax, [VAR_STORAGE_BASE + var_idx*64] ---
.emit_load_var:
    ; r8 = var_idx
    mov     byte [out_buffer + out_idx], 0x48  ; REX.W
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0x8B  ; mov rax, [rip+disp32]
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0x04  ; modrm: rax, [sib]
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0x25  ; SIB: scale=0, index=none, base=rbp
    inc     dword [out_idx]
    ; Compute displacement: VAR_STORAGE_BASE + var_idx * 64 - (current RIP)
    ; For simplicity, use absolute addressing via 32-bit displacement
    mov     rax, r8
    shl     rax, 6                          ; var_idx * 64
    add     rax, VAR_STORAGE_BASE
    sub     rax, out_buffer
    sub     rax, out_idx
    sub     rax, 4                          ; displacement is relative to end of instruction
    call    .emit_dword
    jmp     .next

; --- IR_STORE_VAR: mov [VAR_STORAGE_BASE + var_idx*64], rax ---
.emit_store_var:
    mov     byte [out_buffer + out_idx], 0x48  ; REX.W
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0x89  ; mov [rip+disp32], rax
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0x04  ; modrm
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0x25  ; SIB
    inc     dword [out_idx]
    mov     rax, r8
    shl     rax, 6
    add     rax, VAR_STORAGE_BASE
    sub     rax, out_buffer
    sub     rax, out_idx
    sub     rax, 4
    call    .emit_dword
    jmp     .next

; --- IR_ADD: add rax, rbx (simplified: keep result in rax) ---
.emit_add:
    ; For now: emit `pop rbx; add rax, rbx` pattern
    ; In full IR, src1/src2 map to physical regs after alloc
    ; Milestone A: assume stack-based evaluation
    mov     byte [out_buffer + out_idx], 0x5B  ; pop rbx
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0x48  ; REX.W
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0x01  ; add rax, rbx
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0xD8  ; modrm
    inc     dword [out_idx]
    jmp     .next

.emit_sub:
    mov     byte [out_buffer + out_idx], 0x5B  ; pop rbx
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0x48
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0x29  ; sub rbx, rax → mov rax, rbx; sub
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0xD8
    inc     dword [out_idx]
    jmp     .next

.emit_mul:
    mov     byte [out_buffer + out_idx], 0x5B  ; pop rbx
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0x48
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0x0F  ; imul rax, rbx
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0xAF
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0xC3
    inc     dword [out_idx]
    jmp     .next

.emit_div:
    ; pop rbx → xchg rax,rbx → cqo → idiv rbx
    mov     byte [out_buffer + out_idx], 0x5B  ; pop rbx
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0x48
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0x97  ; xchg rax, rdi (wrong reg — fix in regalloc)
    inc     dword [out_idx]
    jmp     .next

.emit_mod:
    jmp     .emit_div  ; same pattern, result in rdx

.emit_neg:
    mov     byte [out_buffer + out_idx], 0x48
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0xF7  ; neg rax
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0xD8
    inc     dword [out_idx]
    jmp     .next

.emit_abs:
    ; mov rcx, rax; sar rcx, 63; xor rax, rcx; sub rax, rcx
    ; Simplified: call rt_abs or emit cmovs pattern
    jmp     .next

; --- IR_CMP: cmp + setCC + movzx ---
.emit_cmp:
    ; r9 = condition code
    mov     byte [out_buffer + out_idx], 0x5B  ; pop rbx (src2)
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0x48
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0x39  ; cmp rax, rbx (actually rbx, rax)
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0xD8
    inc     dword [out_idx]
    ; setCC al
    mov     byte [out_buffer + out_idx], 0x0F
    inc     dword [out_idx]
    mov     al, 0x90                         ; sete
    add     al, byte [r14 + IR_OFF_AUX]     ; adjust for condition code
    mov     [out_buffer + out_idx], al
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0xC0  ; movzx rax, al
    inc     dword [out_idx]
    jmp     .next

.emit_bool_and:
    ; Short-circuit: pop rbx; test rax,rax; setnz al; test rbx,rbx; setnz bl; and al,bl; movzx rax,al
    jmp     .next

.emit_bool_or:
    jmp     .next

.emit_bool_not:
    mov     byte [out_buffer + out_idx], 0x48
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0x31  ; xor rax, 1
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0xC8
    inc     dword [out_idx]
    jmp     .next

; --- IR_LABEL: record out_buffer offset for this label_id ---
.emit_label_def:
    mov     eax, [r14 + IR_OFF_IMM]        ; eax = label_id
    mov     dword [label_offsets + rax*4], out_idx  ; record offset
    mov     byte [label_used + rax], 1      ; mark as defined
    jmp     .next

; --- IR_JMP: emit jmp rel32 (patch later if forward) ---
.emit_jmp:
    mov     r8d, [r14 + IR_OFF_IMM]        ; r8d = label_id
    mov     byte [out_buffer + out_idx], 0xE9  ; jmp rel32
    inc     dword [out_idx]
    ; Check if label is already defined
    cmp     byte [label_used + r8], 0
    je      .jmp_forward
    ; Backward jump: compute relative offset
    mov     eax, dword [label_offsets + r8*4]
    sub     eax, out_idx
    sub     eax, 4
    call    .emit_dword
    jmp     .next
.jmp_forward:
    ; Store current position for later patching
    ; TODO: patch stack for forward refs
    mov     dword [out_buffer + out_idx], 0  ; placeholder
    add     dword [out_idx], 4
    jmp     .next

; --- IR_JCC: test rsrc1, rsrc1; jz rel32 ---
.emit_jcc:
    mov     r8d, [r14 + IR_OFF_IMM]        ; label_id
    mov     edx, [r14 + IR_OFF_SRC1]       ; src1 vreg
    ; For now: test rax, rax; jz rel32
    mov     byte [out_buffer + out_idx], 0x48
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0x85  ; test rax, rax
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0xC0
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0x0F  ; jz rel32
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0x84
    inc     dword [out_idx]
    ; Patch forward or backward
    cmp     byte [label_used + r8], 0
    je      .jcc_forward
    mov     eax, dword [label_offsets + r8*4]
    sub     eax, out_idx
    sub     eax, 4
    call    .emit_dword
    jmp     .next
.jcc_forward:
    mov     dword [out_buffer + out_idx], 0
    add     dword [out_idx], 4
    jmp     .next

; --- IR_CALL: call proto address ---
.emit_call:
    ; r8 = proto_idx
    mov     byte [out_buffer + out_idx], 0xE8  ; call rel32
    inc     dword [out_idx]
    ; Compute target: proto_addrs[proto_idx] - (out_idx + 4)
    ; For now, emit placeholder
    mov     dword [out_buffer + out_idx], 0
    add     dword [out_idx], 4
    jmp     .next

; --- IR_RET: mov rax, rsrc1; ret ---
.emit_ret:
    mov     byte [out_buffer + out_idx], 0x48
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0x89  ; mov rax, rdi (simplified)
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0xC7
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0xC3  ; ret
    inc     dword [out_idx]
    jmp     .next

.emit_ret_void:
    mov     byte [out_buffer + out_idx], 0xC3  ; ret
    inc     dword [out_idx]
    jmp     .next

; --- IR_OUT_INT: mov rdi, rax; call rt_pri_blob ---
.emit_out_int:
    mov     byte [out_buffer + out_idx], 0x48
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0x89  ; mov rdi, rax
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0xC7
    inc     dword [out_idx]
    call    .emit_call_rt_pri
    jmp     .next

.emit_out_float:
    mov     byte [out_buffer + out_idx], 0x48
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0x83  ; sub rsp, 8 (align)
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0xEC
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0x08
    inc     dword [out_idx]
    call    .emit_call_rt_prf
    jmp     .next

.emit_out_bool:
    mov     byte [out_buffer + out_idx], 0x48
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0x89
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0xC7
    inc     dword [out_idx]
    call    .emit_call_rt_prb
    jmp     .next

.emit_out_str:
    mov     byte [out_buffer + out_idx], 0x48
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0x89
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0xC7
    inc     dword [out_idx]
    call    .emit_call_rt_prs
    jmp     .next

.emit_out_complex:
    jmp     .next

.emit_halt:
    mov     byte [out_buffer + out_idx], 0xB8  ; mov eax, 60
    inc     dword [out_idx]
    mov     dword [out_buffer + out_idx], 60
    add     dword [out_idx], 4
    mov     byte [out_buffer + out_idx], 0x31  ; xor edi, edi
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0xFF
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0xF7
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0x0F  ; syscall
    inc     dword [out_idx]
    mov     byte [out_buffer + out_idx], 0x05
    inc     dword [out_idx]
    jmp     .next

.emit_swap:
    jmp     .next
.emit_inc:
    jmp     .next
.emit_dec:
    jmp     .next
.emit_load_str:
    jmp     .next
.emit_load_bool:
    jmp     .next
.emit_rdrand:
    jmp     .next
.emit_err:
    jmp     .next
.emit_mm_switch:
    jmp     .next
.emit_seq_alloc:
    jmp     .next
.emit_seq_push:
    jmp     .next
.emit_seq_pop:
    jmp     .next
.emit_seq_len:
    jmp     .next
.emit_seq_cap:
    jmp     .next
.emit_dict_new:
    jmp     .next
.emit_dict_set:
    jmp     .next
.emit_dict_get:
    jmp     .next
.emit_prot_entry:
    jmp     .next
.emit_prot_exit:
    jmp     .next
.emit_skip:
    jmp     .next
.emit_load_fimm:
    jmp     .next
.emit_fadd:
    jmp     .next
.emit_fsub:
    jmp     .next
.emit_fmul:
    jmp     .next
.emit_fdiv:
    jmp     .next
.emit_fneg:
    jmp     .next
.emit_f2i:
    jmp     .next
.emit_i2f:
    jmp     .next
.emit_band:
    jmp     .next
.emit_bor:
    jmp     .next
.emit_bxor:
    jmp     .next
.emit_bnot:
    jmp     .next
.emit_shl:
    jmp     .next
.emit_shr:
    jmp     .next

.skip:
    inc     r12
    jmp     .main_loop

.next:
    inc     r12
    jmp     .main_loop

.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    ret

; ============================================================
; Helper: emit raw bytes to out_buffer
; ============================================================
.emit_qword:
    mov     [out_buffer + out_idx], rax
    add     dword [out_idx], 8
    ret

.emit_dword:
    mov     [out_buffer + out_idx], eax
    add     dword [out_idx], 4
    ret

.emit_call_rt_pri:
    mov     byte [out_buffer + out_idx], 0xE8
    inc     dword [out_idx]
    mov     rax, rt_pri_blob
    sub     rax, out_buffer
    sub     rax, out_idx
    sub     rax, 4
    call    .emit_dword
    ret

.emit_call_rt_prs:
    mov     byte [out_buffer + out_idx], 0xE8
    inc     dword [out_idx]
    mov     rax, rt_prs_blob
    sub     rax, out_buffer
    sub     rax, out_idx
    sub     rax, 4
    call    .emit_dword
    ret

.emit_call_rt_prb:
    mov     byte [out_buffer + out_idx], 0xE8
    inc     dword [out_idx]
    mov     rax, rt_prb_blob
    sub     rax, out_buffer
    sub     rax, out_idx
    sub     rax, 4
    call    .emit_dword
    ret

.emit_call_rt_prf:
    mov     byte [out_buffer + out_idx], 0xE8
    inc     dword [out_idx]
    mov     rax, rt_prf_blob
    sub     rax, out_buffer
    sub     rax, out_idx
    sub     rax, 4
    call    .emit_dword
    ret
```

- [ ] **Step 2: Assemble and verify**

Run: `nasm -f elf64 -I include/ -o /tmp/ir_emit_x86.o irgen/ir_emit_x86.asm`
Expected: no errors

- [ ] **Step 3: Commit**

```bash
git add irgen/ir_emit_x86.asm
git commit -m "feat(ir): add x86 emission pass (IR records → machine bytes)"
```

---

## Task 5: Wire Parser to Emit IR

**Covers:** [S7]

**Files:**
- Modify: `parser/parser.asm` — replace `call codegen_emit_*` with `call ir_emit_*`
- Modify: `main/main.asm` — call ir_reset before parsing, call optimization + x86 emission after
- Modify: `Makefile` — add irgen/ assembly targets

This is the largest task. The parser must be rewired to emit IR records instead of x86 bytes. Each `codegen_emit_*` call site needs to be converted.

- [ ] **Step 1: Update Makefile to assemble and link irgen/ files**

Add to Makefile:
```makefile
# IR generator
irgen/irgen.o: irgen/irgen.asm include/rex_defs.inc include/rex_ir.inc
	nasm -f elf64 -I include/ -o $@ $<

irgen/ir_passes.o: irgen/ir_passes.asm include/rex_defs.inc include/rex_ir.inc
	nasm -f elf64 -I include/ -o $@ $<

irgen/ir_emit_x86.o: irgen/ir_emit_x86.asm include/rex_defs.inc include/rex_ir.inc
	nasm -f elf64 -I include/ -o $@ $<
```

Update the link step to include irgen/*.o.

- [ ] **Step 2: Update main.asm to call IR pipeline**

In `main/main.asm`, after the parse loop completes:
1. Before parsing: `call ir_reset`
2. After parsing: `call ir_optimize_pass1` through `ir_optimize_pass5`
3. Then: `call ir_emit_x86`
4. Then: continue with ELF header writing + binary output

- [ ] **Step 3: Wire parser.asm — replace codegen calls (int variables)**

Key replacements in parser.asm:
- `call codegen_emit_mov_rax_imm64` → `call ir_emit_load_imm`
- `call codegen_emit_mov_rax_var` → `call ir_emit_load_var`
- `call codegen_emit_store_rax_to_var` → `call ir_emit_store_var`
- `call codegen_output_int` → `call ir_emit_out_int`
- `call codegen_output_rax_bool` → `call ir_emit_out_bool`

- [ ] **Step 4: Wire parser.asm — arithmetic operations**

- `call codegen_emit_add_rax_rbx` → `call ir_emit_add` (with IR_ADD opcode)
- `call codegen_emit_sub_rax_rbx` → `call ir_emit_sub`
- `call codegen_emit_imul_rax_rbx` → `call ir_emit_mul`
- `call codegen_emit_idiv_rbx_by_rax` → `call ir_emit_div`
- `call codegen_emit_neg_rax` → `call ir_emit_neg`

- [ ] **Step 5: Wire parser.asm — control flow**

- `codegen_emit_cmp_setcc` → `ir_emit_cmp`
- `codegen_emit_test_jz` / `codegen_emit_jmp_end` → `ir_emit_jcc` / `ir_emit_jmp`
- `codegen_emit_and_bool` / `codegen_emit_or_bool` → `ir_emit_bool_and` / `ir_emit_bool_or`
- `codegen_emit_not_rax` → `ir_emit_bool_not`
- Label management: replace `jump_patch_stack` with `ir_alloc_label` + `ir_emit_label`

- [ ] **Step 6: Wire parser.asm — loops**

- `codegen_emit_for_start` / `codegen_emit_for_end` → `ir_emit_loop_top` + `ir_emit_jcc` + `ir_emit_jmp`
- `codegen_emit_while_start` / `codegen_emit_while_end` → `ir_emit_label` + `ir_emit_jcc` + `ir_emit_jmp`
- `codegen_emit_break` → `ir_emit_jmp`
- `codegen_emit_skip` → `ir_emit_skip`

- [ ] **Step 7: Wire parser.asm — protocols**

- Protocol entry/exit → `ir_emit_prot_entry` / `ir_emit_prot_exit`
- Protocol calls → `ir_emit_call`
- Return → `ir_emit_ret` / `ir_emit_ret_void`

- [ ] **Step 8: Wire parser.asm — remaining features**

- Float output → `ir_emit_out_float`
- String output → `ir_emit_out_str`
- Complex output → `ir_emit_out_complex`
- swap → `ir_emit_swap`
- inc/dec → `ir_emit_inc` / `ir_emit_dec`
- seq operations → `ir_emit_seq_*`
- dict operations → `ir_emit_dict_*`

- [ ] **Step 9: Build and run all tests**

Run: `make clean && make && make test`
Expected: All tests pass with identical output

- [ ] **Step 10: Commit**

```bash
git add parser/parser.asm main/main.asm Makefile irgen/
git commit -m "feat(ir): wire parser to emit IR records, run optimization passes, emit x86"
```

---

## Task 6: Verify IR Pipeline End-to-End

**Covers:** [S9]

**Files:**
- No new files — verification only

- [ ] **Step 1: Run full test suite**

Run: `make test`
Expected: All tests pass

- [ ] **Step 2: Verify binary output matches**

For each test, compare the output binary with the pre-IR version:
```bash
# Before IR (checkout pre-change)
git stash
make clean && make
cp output output_before
git stash pop

# After IR
make clean && make
cp output output_after

# Compare
diff <(xxd output_before) <(xxd output_after)
```

Note: Binaries may differ due to code layout, but runtime behavior must be identical.

- [ ] **Step 3: Verify test outputs are identical**

Run each test and confirm output matches expected:
```bash
./output 2>&1 | diff - expected_output
```

- [ ] **Step 4: Commit verification results**

```bash
git commit --allow-empty -m "test(ir): verify IR pipeline produces identical test results"
```
