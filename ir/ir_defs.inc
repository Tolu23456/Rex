; ══════════════════════════════════════════════════════════════════════════════
; ir/ir_defs.inc — Rex V5 NASM IR constants
; 32-byte flat record, 8 optimisation passes, linear scan RA, x86-64 emission
; ══════════════════════════════════════════════════════════════════════════════

; ── IR buffer limits ──────────────────────────────────────────────────────────
IR_MAX          equ 65536       ; max IR records in one compilation unit
IR_RECORD_SIZE  equ 32          ; bytes per record (fixed, cache-line friendly)
VREG_MAX        equ 4096        ; max virtual registers per proto

; ── IR opcodes (field ir_op) ──────────────────────────────────────────────────
; Moves & constants
IR_NOP          equ 0x00        ; no-op / tombstone after DCE
IR_IMM          equ 0x01        ; dst = imm64
IR_MOV          equ 0x02        ; dst = src0
IR_LOAD         equ 0x03        ; dst = [src0 + imm32]  (memory load)
IR_STORE        equ 0x04        ; [src0 + imm32] = src1 (memory store)
IR_LOAD_VAR     equ 0x05        ; dst = var[imm32]       (load from var slot)
IR_STORE_VAR    equ 0x06        ; var[imm32] = src0      (store to var slot)

; Arithmetic (integer)
IR_ADD          equ 0x10        ; dst = src0 + src1
IR_SUB          equ 0x11        ; dst = src0 - src1
IR_MUL          equ 0x12        ; dst = src0 * src1
IR_DIV          equ 0x13        ; dst = src0 / src1 (signed)
IR_MOD          equ 0x14        ; dst = src0 % src1 (signed)
IR_NEG          equ 0x15        ; dst = -src0
IR_ABS          equ 0x16        ; dst = |src0|

; Arithmetic (float)
IR_FADD         equ 0x18        ; dst = src0 +f src1
IR_FSUB         equ 0x19        ; dst = src0 -f src1
IR_FMUL         equ 0x1A        ; dst = src0 *f src1
IR_FDIV         equ 0x1B        ; dst = src0 /f src1
IR_FNEG         equ 0x1C        ; dst = -f src0
IR_ITOF         equ 0x1D        ; dst = (float)src0
IR_FTOI         equ 0x1E        ; dst = (int)src0  (truncate)

; Bitwise
IR_AND          equ 0x20        ; dst = src0 & src1
IR_OR           equ 0x21        ; dst = src0 | src1
IR_XOR          equ 0x22        ; dst = src0 ^ src1
IR_NOT          equ 0x23        ; dst = ~src0
IR_SHL          equ 0x24        ; dst = src0 << src1
IR_SHR          equ 0x25        ; dst = src0 >> src1 (arithmetic)

; Comparisons (produce 0/1 int)
IR_EQ           equ 0x30        ; dst = src0 == src1
IR_NE           equ 0x31        ; dst = src0 != src1
IR_LT           equ 0x32        ; dst = src0 < src1  (signed)
IR_LE           equ 0x33        ; dst = src0 <= src1
IR_GT           equ 0x34        ; dst = src0 > src1
IR_GE           equ 0x35        ; dst = src0 >= src1
IR_FEQ          equ 0x36        ; dst = src0 ==f src1
IR_FNE          equ 0x37        ; dst = src0 !=f src1
IR_FLT          equ 0x38        ; dst = src0 <f src1
IR_FLE          equ 0x39        ; dst = src0 <=f src1

; Control flow
IR_JMP          equ 0x40        ; unconditional jump to label imm32
IR_JZ           equ 0x41        ; jump to imm32 if src0 == 0
IR_JNZ          equ 0x42        ; jump to imm32 if src0 != 0
IR_LABEL        equ 0x43        ; label imm32 (branch target)
IR_CALL         equ 0x44        ; dst = call proto[imm32]  (args in preceding IR_ARG)
IR_ARG          equ 0x45        ; arg src0 for upcoming IR_CALL (position = imm32)
IR_RET          equ 0x46        ; return src0
IR_RET_VOID     equ 0x47        ; return with no value

; String / seq built-ins (map 1:1 to runtime blobs)
IR_STR_AT       equ 0x50        ; dst = byte src0[src1]  (str_at)
IR_STR_LEN      equ 0x51        ; dst = len(src0)
IR_STR_CAT      equ 0x52        ; dst = src0 ++ src1
IR_STR_EQ       equ 0x53        ; dst = src0 == src1  (string equality)
IR_SEQ_PUSH     equ 0x58        ; seq src0 += src1
IR_SEQ_POP      equ 0x59        ; dst = seq src0 pop
IR_SEQ_LEN      equ 0x5A        ; dst = len(seq src0)
IR_SEQ_IDX      equ 0x5B        ; dst = src0[src1]

; File I/O (self-hosting built-ins)
IR_FILE_OPEN    equ 0x60        ; dst = file_open(src0 path, src1 flags)
IR_FILE_READ    equ 0x61        ; dst = file_read_all(src0 path)
IR_FILE_WRITE   equ 0x62        ; file_write(src0 fd, src1 str)
IR_FILE_CLOSE   equ 0x63        ; file_close(src0 fd)

; System
IR_EXIT         equ 0x70        ; exit(src0)
IR_ALLOC        equ 0x71        ; dst = alloc(src0 bytes)
IR_SYSCALL      equ 0x72        ; dst = syscall(src0 nr, src1..src6 in subsequent ARGs)
IR_PRINT        equ 0x73        ; print src0 (calls rt_pri/prs/prb)

; ── IR record layout (32 bytes, indices in bytes) ─────────────────────────────
; Byte layout:
;   [0]  ir_op      : uint8   opcode (IR_* above)
;   [1]  ir_flags   : uint8   flag bits (see below)
;   [2]  ir_type    : uint8   result type (IR_TYPE_* below)
;   [3]  ir_phys    : uint8   assigned physical reg (0=unassigned, 1..14=reg, 0xFF=spill)
;  [4..7] reserved/pad
;  [8..11] ir_dst   : int32   destination vreg (-1 = no result)
; [12..15] ir_src0  : int32   first source vreg (-1 = unused)
; [16..19] ir_src1  : int32   second source vreg (-1 = unused)
; [20..27] ir_imm   : int64   immediate / label ID / var index
; [28..31] ir_meta  : uint32  pass-specific metadata (e.g., loop depth, use-count)

IR_OFF_OP       equ 0
IR_OFF_FLAGS    equ 1
IR_OFF_TYPE     equ 2
IR_OFF_PHYS     equ 3
IR_OFF_DST      equ 8
IR_OFF_SRC0     equ 12
IR_OFF_SRC1     equ 16
IR_OFF_IMM      equ 20
IR_OFF_META     equ 28

; ── IR flag bits (ir_flags) ───────────────────────────────────────────────────
IRF_DEAD        equ 0x01        ; DCE: record is dead, can be eliminated
IRF_LOOP_INV    equ 0x02        ; LICM: computation is loop-invariant
IRF_STRENGTH_R  equ 0x04        ; SR: strength reduction applied
IRF_CONST       equ 0x08        ; CFP: result is a known compile-time constant
IRF_PINNED      equ 0x10        ; RA: vreg must stay in specific phys reg
IRF_SPILL       equ 0x20        ; RA: vreg has been spilled to stack
IRF_FOLDED      equ 0x40        ; CFP: already constant-folded, skip
IRF_COALESCED   equ 0x80        ; LSC: load-store pair coalesced

; ── IR value types (ir_type) ─────────────────────────────────────────────────
IR_TYPE_INT     equ 0           ; 64-bit signed integer
IR_TYPE_FLOAT   equ 1           ; 64-bit IEEE 754 double
IR_TYPE_STR     equ 2           ; pointer to null-terminated string
IR_TYPE_BOOL    equ 3           ; 0 or 1 integer
IR_TYPE_VOID    equ 4           ; no result
IR_TYPE_PTR     equ 5           ; raw pointer (used by alloc/file)

; ── Physical register IDs (ir_phys) ───────────────────────────────────────────
; 0 = unassigned / any
; x86-64 general-purpose (caller-saved first, then callee-saved):
PHYS_NONE       equ 0
PHYS_RAX        equ 1
PHYS_RCX        equ 2
PHYS_RDX        equ 3
PHYS_RSI        equ 4
PHYS_RDI        equ 5
PHYS_R8         equ 6
PHYS_R9         equ 7
PHYS_R10        equ 8
PHYS_R11        equ 9
; Callee-saved:
PHYS_RBX        equ 10
PHYS_R12        equ 11
PHYS_R13        equ 12
PHYS_R14        equ 13
PHYS_R15        equ 14
PHYS_XMM0       equ 16
PHYS_XMM1       equ 17
PHYS_SPILL      equ 0xFF        ; spilled to stack slot

; ── IR BSS layout (placed in caller module) ────────────────────────────────────
; Modules that use the IR passes declare:
;   ir_buffer:  resb IR_MAX * IR_RECORD_SIZE
;   ir_idx:     resq 1          ; number of IR records currently stored
;   ir_vreg_ctr: resw 1         ; next vreg to allocate
;   ir_label_ctr: resw 1        ; next label ID to allocate
; These are exported by rex_ir_buf.asm.
