; ============================================================
; Rex IR — Intermediate Representation Constants
; include/rex_ir.inc
; ============================================================

; ----------------------------------------------------------------
; IR Record Layout (32 bytes per instruction)
;   [0]      opcode  (1 byte)
;   [1]      type    (1 byte)
;   [2..3]   dst     (2 bytes, word)
;   [4..5]   src1    (2 bytes, word)
;   [6..7]   src2    (2 bytes, word)
;   [8..15]  imm     (8 bytes, qword)
;   [16..23] aux     (8 bytes, qword)
;   [24..27] flags   (4 bytes, dword)
;   [28..31] _pad    (4 bytes)
; ----------------------------------------------------------------
%define IR_RECORD_SIZE      32

%define IR_OFF_OPCODE       0
%define IR_OFF_TYPE         1
%define IR_OFF_DST          2
%define IR_OFF_SRC1         4
%define IR_OFF_SRC2         6
%define IR_OFF_IMM          8
%define IR_OFF_AUX          16
%define IR_OFF_FLAGS        24
%define IR_OFF_PAD          28

; ----------------------------------------------------------------
; Buffer sizing
; ----------------------------------------------------------------
%define IR_MAX              16384
%define IR_BUF_SIZE         (IR_MAX * IR_RECORD_SIZE)
%define VREG_MAX            65535
%define LABEL_MAX           4096
%define SPILL_MAX           64

; ----------------------------------------------------------------
; IR Opcodes — No-op
; ----------------------------------------------------------------
%define IR_NOP              0x00

; ----------------------------------------------------------------
; IR Opcodes — Load/Store (0x01–0x0F)
; ----------------------------------------------------------------
%define IR_LOAD_IMM         0x01    ; dst = imm
%define IR_LOAD_VAR         0x02    ; dst = var[src1]
%define IR_LOAD_DEREF       0x03    ; dst = mem[src1 + imm]
%define IR_STORE_VAR        0x04    ; var[src1] = src2
%define IR_STORE_DEREF      0x05    ; mem[src1 + imm] = src2
%define IR_LOAD_ADDR        0x06    ; dst = &var[src1]
%define IR_LOAD_GLOBAL      0x07    ; dst = global[imm]
%define IR_STORE_GLOBAL     0x08    ; global[imm] = src1
%define IR_LOAD_STRING      0x09    ; dst = ptr to string constant (imm = label)
%define IR_LOAD_COMPLEX     0x0A    ; dst = complex(real=src1, imag=src2)
%define IR_LOAD_CHAR        0x0B    ; dst = char value (imm)
%define IR_LOAD_BYTE        0x0C    ; dst = byte value (imm)
%define IR_LOAD_BOOL        0x0D    ; dst = bool (imm: 0/1)
%define IR_LOAD_NULL        0x0E    ; dst = null

; ----------------------------------------------------------------
; IR Opcodes — Integer Arithmetic (0x11–0x1F)
; ----------------------------------------------------------------
%define IR_ADD              0x11    ; dst = src1 + src2
%define IR_SUB              0x12    ; dst = src1 - src2
%define IR_MUL              0x13    ; dst = src1 * src2
%define IR_DIV              0x14    ; dst = src1 / src2
%define IR_MOD              0x15    ; dst = src1 % src2
%define IR_NEG              0x16    ; dst = -src1
%define IR_ABS              0x17    ; dst = |src1|
%define IR_INC              0x18    ; dst = src1 + 1
%define IR_DEC              0x19    ; dst = src1 - 1
%define IR_POW              0x1A    ; dst = src1 ^ src2
%define IR_SQRT             0x1B    ; dst = sqrt(src1) (float)
%define IR_SIGN             0x1C    ; dst = sign(src1)
%define IR_IDIV             0x1D    ; dst = src1 // src2 (floor div)

; ----------------------------------------------------------------
; IR Opcodes — Float Arithmetic (0x21–0x2F)
; ----------------------------------------------------------------
%define IR_FADD             0x21    ; dst = src1 + src2 (float)
%define IR_FSUB             0x22    ; dst = src1 - src2 (float)
%define IR_FMUL             0x23    ; dst = src1 * src2 (float)
%define IR_FDIV             0x24    ; dst = src1 / src2 (float)
%define IR_FMOD             0x25    ; dst = src1 % src2 (float)
%define IR_FNEG             0x26    ; dst = -src1 (float)
%define IR_FABS             0x27    ; dst = |src1| (float)
%define IR_FLOOR            0x28    ; dst = floor(src1)
%define IR_CEIL             0x29    ; dst = ceil(src1)
%define IR_ROUND            0x2A    ; dst = round(src1)
%define IR_FSQRT            0x2B    ; dst = sqrt(src1)
%define IR_FPOW             0x2C    ; dst = src1 ^ src2 (float)
%define IR_FEXP             0x2D    ; dst = exp(src1)
%define IR_FLN              0x2E    ; dst = ln(src1)

; ----------------------------------------------------------------
; IR Opcodes — Bitwise (0x31–0x3F)
; ----------------------------------------------------------------
%define IR_BAND             0x31    ; dst = src1 & src2
%define IR_BOR              0x32    ; dst = src1 | src2
%define IR_BXOR             0x33    ; dst = src1 ^ src2
%define IR_BNOT             0x34    ; dst = ~src1
%define IR_BSHL             0x35    ; dst = src1 << src2
%define IR_BSHR             0x36    ; dst = src1 >> src2
%define IR_BSHR_S           0x37    ; dst = src1 >> src2 (arithmetic/signed)
%define IR_CLZ              0x38    ; dst = count leading zeros
%define IR_CTZ              0x39    ; dst = count trailing zeros
%define IR_POPCOUNT         0x3A    ; dst = popcount(src1)
%define IR_TZCNT            0x3B    ; dst = count trailing zeros (tzcnt)
%define IR_LZCNT            0x3C    ; dst = count leading zeros (lzcnt)

; ----------------------------------------------------------------
; IR Opcodes — SIMD (0x3D–0x3F)
; ----------------------------------------------------------------
%define IR_SIMD_LOAD        0x3D    ; load 4 ints from [src1+imm] into xmm0
%define IR_SIMD_STORE       0x3E    ; store 4 ints from xmm0 to [dst+imm]
%define IR_SIMD_ADD         0x3F    ; xmm0 = xmm0 + xmm1 (4 int32 parallel)

; ----------------------------------------------------------------
; IR Opcodes — Comparison / Boolean (0x41–0x4F)
; ----------------------------------------------------------------
%define IR_CMP              0x41    ; compare src1 vs src2; set aux=condition
%define IR_TEST             0x42    ; test src1 (set ZF)
%define IR_LNOT             0x43    ; dst = !src1
%define IR_LAND             0x44    ; dst = src1 && src2 (short-circuit not modeled)
%define IR_LOR              0x45    ; dst = src1 || src2
%define IR_LXOR             0x46    ; dst = src1 ^^ src2 (three-valued)
%define IR_MOV              0x47    ; dst = src1

; ----------------------------------------------------------------
; Condition codes (for IR_CMP aux field)
; ----------------------------------------------------------------
%define IR_CC_EQ            0       ; equal
%define IR_CC_NE            1       ; not equal
%define IR_CC_LT            2       ; less than (signed)
%define IR_CC_GT            3       ; greater than (signed)
%define IR_CC_LE            4       ; less or equal (signed)
%define IR_CC_GE            5       ; greater or equal (signed)
%define IR_CC_LTU           6       ; less than (unsigned)
%define IR_CC_GTU           7       ; greater than (unsigned)
%define IR_CC_LEU           8       ; less or equal (unsigned)
%define IR_CC_GEU           9       ; greater or equal (unsigned)

; ----------------------------------------------------------------
; IR Opcodes — Control Flow (0x51–0x5F)
; ----------------------------------------------------------------
%define IR_JMP              0x51    ; unconditional jump to label (imm)
%define IR_JMP_TRUE         0x52    ; jump if src1 is true
%define IR_JMP_FALSE        0x53    ; jump if src1 is false
%define IR_JMP_CMP          0x54    ; jump if CMP condition met (aux=cc)
%define IR_LABEL            0x55    ; define label (imm=label id)
%define IR_CALL             0x56    ; call protocol src1, args in src2..  (imm=arg count)
%define IR_RET              0x57    ; return src1
%define IR_PHI              0x58    ; SSA phi: dst = φ(src1, src2, ...) aux=phi arg count

; ----------------------------------------------------------------
; IR Opcodes — Output / Runtime (0x61–0x6F)
; ----------------------------------------------------------------
%define IR_OUTPUT           0x61    ; output src1 (typed print)
%define IR_OUTPUT_STR       0x62    ; output string at src1
%define IR_OUTPUT_NL        0x63    ; output newline
%define IR_INPUT            0x64    ; dst = read input
%define IR_TYPEOF           0x65    ; dst = type-of src1
%define IR_LEN              0x66    ; dst = len(src1)
%define IR_CONCAT           0x67    ; dst = src1 ++ src2
%define IR_ASSERT           0x68    ; assert src1 (trap if false)
%define IR_CLOCK            0x69    ; dst = clock()
%define IR_RAISE            0x6A    ; raise exception src1

; ----------------------------------------------------------------
; IR Opcodes — Collection Operations (0x71–0x7F)
; ----------------------------------------------------------------
%define IR_SEQ_NEW          0x71    ; dst = new empty sequence
%define IR_SEQ_PUSH         0x72    ; seq[src1] = src2 (append)
%define IR_SEQ_POP          0x73    ; dst = pop last from seq[src1]
%define IR_SEQ_GET          0x74    ; dst = seq[src1][src2]
%define IR_SEQ_SET          0x75    ; seq[src1][src2] = aux
%define IR_SEQ_LEN          0x76    ; dst = len(seq[src1])
%define IR_SEQ_SLICE        0x77    ; dst = seq[src1][src2..aux]
%define IR_SEQ_CONCAT       0x78    ; dst = seq[src1] ++ seq[src2]
%define IR_DICT_NEW         0x79    ; dst = new empty dict
%define IR_DICT_SET         0x7A    ; dict.set(src1, src2, aux)
%define IR_DICT_GET         0x7B    ; dst = dict.get(src1, src2)
%define IR_DICT_KEYS        0x7C    ; dst = dict.keys(src1)
%define IR_DICT_DEL         0x7D    ; dict.del(src1, src2)

; ----------------------------------------------------------------
; IR Opcodes — Swap / Misc (0x81–0x8F)
; ----------------------------------------------------------------
%define IR_SWAP             0x81    ; swap src1 <-> src2
%define IR_CAST             0x82    ; dst = cast(src1, aux=target_type)
%define IR_RESERVE          0x83    ; dst = reserve memory (imm=bytes)
%define IR_FREE             0x84    ; free(src1)
%define IR_MEMO_CHECK       0x85    ; dst = memo hit? (src1=proto_id)
%define IR_MEMO_STORE       0x86    ; memo.store(proto_id=src1, result=src2)
%define IR_SIMD_SUB         0x87    ; xmm0 = xmm0 - xmm1 (4 int32 parallel)

; ----------------------------------------------------------------
; IR Opcodes — Protocol Markers (0xF0–0xFF)
; ----------------------------------------------------------------
%define IR_PROTO_BEGIN      0xF0    ; begin protocol definition (imm=proto id)
%define IR_PROTO_END        0xF1    ; end protocol definition
%define IR_PROTO_PARAM      0xF2    ; declare parameter (imm=param index)
%define IR_MODULE_BEGIN     0xF3    ; begin module
%define IR_MODULE_END       0xF4    ; end module
%define IR_DECORATOR_BEGIN  0xF5    ; begin decorator
%define IR_DECORATOR_END    0xF6    ; end decorator

; ----------------------------------------------------------------
; Flag bits (IR_OFF_FLAGS, dword)
; ----------------------------------------------------------------
%define IR_FLAG_CONST       0x01    ; value is compile-time constant
%define IR_FLAG_DEAD        0x02    ; result unused (dead-code)
%define IR_FLAG_SPILLED     0x04    ; vreg spilled to stack
%define IR_FLAG_LOOP_INV    0x08    ; loop-invariant (hoistable)
