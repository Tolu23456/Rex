; Rex IR Constants and Structure

; IR Opcodes (Category 0: No-op)
IR_NOP          equ 0x00

; Category 1: Load / Store
IR_LOAD_IMM     equ 0x01
IR_LOAD_FIMM    equ 0x02
IR_LOAD_VAR     equ 0x03
IR_STORE_VAR    equ 0x04
IR_LOAD_STR     equ 0x05
IR_LOAD_BOOL    equ 0x06
IR_LOAD_DEREF_BYTE equ 0x07 ; dst = byte at [src1 + imm]
IR_LEA_VAR      equ 0x08
IR_CAST_ITF     equ 0x09  ; int → float (cvtsi2sd)
IR_CAST_FTI     equ 0x0A  ; float → int (cvttsd2si, truncate toward zero)
IR_CAST_BTI     equ 0x0B  ; bool → int (no-op, same register repr)
IR_CAST_CTI     equ 0x0C  ; char → int (no-op)
IR_CAST_CTB     equ 0x0D  ; char → byte (no-op)
IR_CAST_BCI     equ 0x0E  ; byte → int (no-op)
IR_CAST_BTC     equ 0x0F  ; byte → char (no-op)
IR_NULL_COALESCE equ 0x10 ; dst = src1 != 0 ? src1 : src2 (integer)

; Category 2: Integer Arithmetic
IR_ADD          equ 0x11
IR_SUB          equ 0x12
IR_MUL          equ 0x13
IR_DIV          equ 0x14
IR_MOD          equ 0x15
IR_NEG          equ 0x16
IR_AND          equ 0x1A
IR_OR           equ 0x1B
IR_XOR          equ 0x1C

; Category 2 ext: Integer Math Unary/Binary (0x28–0x2F)
IR_ABS_INT      equ 0x28  ; dst = |src1|
IR_MIN_INT      equ 0x29  ; dst = min(src1, src2)
IR_MAX_INT      equ 0x2A  ; dst = max(src1, src2)
IR_SHL          equ 0x2B  ; dst = src1 << imm  (src2=0→imm, else src2 reg)
IR_SHR          equ 0x2C  ; dst = src1 >> imm  (arithmetic)
IR_SIGNUM       equ 0x2D  ; dst = -1/0/1 for src1 <0/=0/>0
IR_MOV          equ 0x2E  ; dst = src1  (register copy; coalesced by allocator)

; Category 3: Bool Ternary Logic (Łukasiewicz)
IR_BOOL_AND     equ 0x20  ; min(a, b) over {-1, 0, 1}
IR_BOOL_OR      equ 0x21  ; max(a, b) over {-1, 0, 1}
IR_BOOL_NOT     equ 0x22  ; negation: -x

; Category 4: Bit Operations (0x30–0x37)
IR_POPCOUNT     equ 0x30  ; dst = popcount(src1)
IR_CLZ          equ 0x31  ; dst = leading zero bits
IR_CTZ          equ 0x32  ; dst = trailing zero bits
IR_BSWAP        equ 0x33  ; dst = bswap(src1)
IR_ROL          equ 0x34  ; dst = rol(src1, imm/src2)
IR_ROR          equ 0x35  ; dst = ror(src1, imm/src2)
IR_SWAP_NIB     equ 0x36  ; dst = swap nibbles of byte src1
IR_CLZ8         equ 0x37  ; dst = clz of 8-bit value in src1

; Category 4 ext: Float Scalar Math (0x38–0x40)
IR_ABS_FLOAT    equ 0x38  ; dst = |src1|  (float)
IR_MIN_FLOAT    equ 0x3A  ; dst = min(src1, src2)  (float)
IR_MAX_FLOAT    equ 0x3B  ; dst = max(src1, src2)  (float)
IR_CEIL         equ 0x3C  ; dst:int = ceil(src1)
IR_FLOOR        equ 0x3D  ; dst:int = floor(src1)
IR_ROUND        equ 0x3E  ; dst:int = round(src1)
IR_TRUNC_F      equ 0x3F  ; dst:float = trunc(src1)  (toward zero)
IR_SQRT         equ 0x40  ; dst:float = sqrt(src1)

; Category 5: Comparison
IR_CMP          equ 0x41

; Category 5 ext: Comparisons producing bool (0x42–0x5F)
; IR_CMP_BOOL: dst:bool = compare(src1, src2|imm), condition in aux
; aux = COND_* constant below; src2=0 → compare with imm field
IR_CMP_BOOL     equ 0x42

; Condition codes for IR_CMP_BOOL aux field
COND_EQ         equ 0
COND_NE         equ 1
COND_LT         equ 2
COND_LE         equ 3
COND_GT         equ 4
COND_GE         equ 5

; Char predicates and transforms (0x43–0x4F)
IR_IS_ALPHA     equ 0x43  ; dst:bool = is letter
IR_IS_DIGIT_C   equ 0x44  ; dst:bool = is decimal digit
IR_IS_ALNUM     equ 0x45  ; dst:bool = is letter or digit
IR_IS_SPACE     equ 0x46  ; dst:bool = is whitespace
IR_IS_PRINT     equ 0x47  ; dst:bool = is printable ASCII (0x20–0x7E)
IR_TO_UPPER     equ 0x48  ; dst:char = uppercase
IR_TO_LOWER     equ 0x49  ; dst:char = lowercase
IR_IS_UPPER     equ 0x4A  ; dst:bool = is uppercase letter
IR_IS_LOWER_C   equ 0x4B  ; dst:bool = is lowercase letter
IR_IS_PUNCT     equ 0x4C  ; dst:bool = printable non-alphanumeric
IR_IS_EVEN      equ 0x4D  ; dst:bool = (src1 % 2 == 0)
IR_IS_ODD       equ 0x4E  ; dst:bool = (src1 % 2 != 0)
IR_TO_DIGIT     equ 0x4F  ; dst:int  = digit value of '0'-'9', else -1

; Float predicates (0x54, 0x56–0x59)
IR_IS_NAN       equ 0x54  ; dst:bool = isNaN(src1)
IR_IS_INF       equ 0x56  ; dst:bool = isInf(src1)
IR_IS_FINITE    equ 0x57  ; dst:bool = isFinite(src1)
IR_IS_ZERO_F    equ 0x58  ; dst:bool = (src1 == 0.0)
IR_IS_POS_F     equ 0x59  ; dst:bool = (src1 > 0.0)
IR_IS_NEG_F     equ 0x5A  ; dst:bool = (src1 < 0.0)

; Category 6: Control Flow
IR_LABEL        equ 0x51
IR_JMP          equ 0x52
IR_JCC          equ 0x53
IR_RET          equ 0x55

; Category 7: Output / Runtime
IR_OUT_INT      equ 0x61
IR_OUT_FLOAT    equ 0x62
IR_OUT_BOOL     equ 0x63
IR_OUT_STR      equ 0x64
IR_OUT_CHAR     equ 0x65  ; print char (1 byte via rt_prc)
IR_HALT         equ 0x67

; Category 8: Collection Operations (0x70-0x7F)
IR_SEQ_NEW      equ 0x70  ; dst = new seq with capacity from imm
IR_SEQ_PUSH     equ 0x71  ; seq_push(seq, value)
IR_SEQ_LOAD     equ 0x72  ; dst = seq[index]
IR_SEQ_STORE    equ 0x73  ; seq[index] = value
IR_SEQ_LEN      equ 0x74  ; dst = len(seq)
IR_ARR_NEW      equ 0x75  ; dst = new arr with size from imm
IR_ARR_LOAD     equ 0x76  ; dst = arr[index]
IR_ARR_STORE    equ 0x77  ; arr[index] = value
IR_SEQ_POP      equ 0x78  ; dst = pop(seq)
IR_SEQ_INSERT   equ 0x79  ; seq.insert(index, value) — void
IR_SEQ_REMOVE   equ 0x7A  ; dst = seq.remove(index)

; Category 8b: Dict Operations (0x7B-0x7F)
IR_DICT_NEW     equ 0x7B  ; dst = new dict
IR_DICT_LOAD    equ 0x7C  ; dst = dict[key]
IR_DICT_STORE   equ 0x7D  ; dict[key] = value
IR_DICT_LEN     equ 0x7E  ; dst = len(dict)

; Category 8c: Extended Seq Operations (0x83-0x8F)
IR_SEQ_FIRST    equ 0x83  ; dst = seq[0]
IR_SEQ_LAST     equ 0x84  ; dst = seq[len-1]
IR_SEQ_CONTAINS equ 0x85  ; dst = bool(seq contains value)
IR_SEQ_INDEX_OF equ 0x86  ; dst = index of value, -1 if not found
IR_SEQ_COPY     equ 0x87  ; dst = copy of seq
IR_SEQ_REVERSE  equ 0x88  ; reverse seq in place
IR_SEQ_SUM      equ 0x89  ; dst = sum of elements
IR_SEQ_MIN      equ 0x8A  ; dst = min element
IR_SEQ_MAX      equ 0x8B  ; dst = max element
IR_SEQ_SLICE    equ 0x8C  ; dst = seq[lo:hi]
IR_SEQ_CLEAR    equ 0x8D  ; clear seq (len=0)
IR_SEQ_RESERVE  equ 0x8E  ; ensure capacity
IR_SEQ_CAP      equ 0x8F  ; dst = capacity
IR_SEQ_COUNT_OF equ 0x90  ; dst = count of value in seq

; Category 9: String Operations (0x80-0x8F)
IR_STR_CONCAT   equ 0x80  ; dst = str1 + str2
IR_STR_LEN      equ 0x81  ; dst = len(str)
IR_STR_CMP      equ 0x82  ; dst = strcmp(str1, str2)

; Category 10: Extended Math (0xA0–0xAF)
IR_SIN          equ 0xA0  ; dst:float = sin(src1:float)
IR_COS          equ 0xA1  ; dst:float = cos(src1:float)
IR_TAN          equ 0xA2  ; dst:float = tan(src1:float)
IR_POW_F        equ 0xA3  ; dst:float = pow(src1:float, src2:float)
IR_CBRT         equ 0xA4  ; dst:float = cbrt(src1:float)
IR_GCD          equ 0xA5  ; dst:int = gcd(src1:int, src2:int)
IR_LCM          equ 0xA6  ; dst:int = lcm(src1:int, src2:int)
IR_SIGNUM_F     equ 0xA7  ; dst:float = signum(src1:float) → -1.0/0.0/1.0
IR_TO_BIN_STR   equ 0xA8  ; dst:str = int→binary string  (e.g. "1010")
IR_TO_HEX_STR   equ 0xA9  ; dst:str = int→hex string     (e.g. "ff")
IR_TO_OCT_STR   equ 0xAA  ; dst:str = int→octal string    (e.g. "77")
IR_SWAP_VARS    equ 0xAB  ; swap values of two stack slots (src1=vreg_a, src2=vreg_b)

; Category 11: Protocol Calls (0xB0-0xB5)
IR_CALL_ARG           equ 0xB0 ; src1=vreg, imm=arg index (0-5=reg, 6+=stack)
IR_CALL               equ 0xB1 ; imm=proto_id, aux=arg_count, dst=lo vreg (0=void), src2=hi vreg (0=none)
IR_PROTO_BEGIN        equ 0xB2 ; imm=proto_id (records prologue offset; aux unused)
IR_SAVE_ARG           equ 0xB3 ; imm=arg index, aux=param var ABSOLUTE offset (write arg into var slot)
IR_SAVE_LOCAL_VAR     equ 0xB4 ; imm=var absolute offset (push [var])
IR_RESTORE_LOCAL_VAR  equ 0xB5 ; imm=var absolute offset (pop [var])

; Category 12: Control-flow extensions (0xC0-0xC1)
IR_WHEN       equ 0xC0 ; dst:bool = monitor(cond) — tri-state state monitor
IR_ABORT      equ 0xC1 ; abort with message (src1 = null-terminated str ptr)

; IR Record Structure (32 bytes per record)
; Offset  Size  Field
; 0       1     opcode
; 1       1     type (TYPE_*)
; 2       2     dst virtual register (vreg)
; 4       2     src1 virtual register
; 6       2     src2 virtual register
; 8       8     imm (immediate / offset / var_idx)
; 16      8     aux (secondary immediate / cond_code)
; 24      4     flags (IR_FLAG_*)
; 28      4     _pad
IR_RECORD_SIZE  equ 32
IR_MAX_RECORDS  equ 4096

; IR flags
IR_FLAG_CONST   equ 1
IR_FLAG_DEAD    equ 2
IR_FLAG_SPILLED equ 4
