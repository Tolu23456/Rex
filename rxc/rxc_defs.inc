; rxc_defs.inc — RexC bytecode opcode constants
; Matches the RexC instruction set specification in .agents/memory/rex-rexc-spec.md

; ── Virtual register IDs ──────────────────────────────────────────────────────
RXC_R0   equ 0x00    ; accumulator (maps to rax in x86-64 backend)
RXC_R1   equ 0x01    ; scratch     (maps to rbx in x86-64 backend)
RXC_R2   equ 0x02    ; spill depth 0 (r10)
RXC_R3   equ 0x03    ; spill depth 1 (r11)

; ── File header ───────────────────────────────────────────────────────────────
RXC_MAGIC_0  equ 0x52   ; 'R'
RXC_MAGIC_1  equ 0x45   ; 'E'
RXC_MAGIC_2  equ 0x58   ; 'X'
RXC_MAGIC_3  equ 0x43   ; 'C'
RXC_VERSION_MAJ equ 0x01
RXC_VERSION_MIN equ 0x00
RXC_HEADER_SIZE equ 20  ; 4 magic + 1 vmaj + 1 vmin + 2 flags + 4 entry + 4 const_off + 4 sym_off

; ── Control flow (0x00–0x0F) ─────────────────────────────────────────────────
RXC_NOP      equ 0x00   ; no operands
RXC_HALT     equ 0x01   ; no operands
RXC_RET      equ 0x02   ; no operands (void return)
RXC_RET_VAL  equ 0x03   ; no operands (return r0)
RXC_CALL     equ 0x04   ; [4-byte sym_idx]
RXC_CALL_R   equ 0x05   ; no extra (call address in r0)
RXC_JMP      equ 0x06   ; [4-byte rel32 offset]
RXC_JMP_T    equ 0x07   ; [4-byte rel32] — jump if r0 != 0
RXC_JMP_F    equ 0x08   ; [4-byte rel32] — jump if r0 == 0
RXC_JMP_EQ   equ 0x09   ; [4-byte rel32] — (r0==0 after cmp, same as JMP_F for setcc results)
RXC_JMP_NE   equ 0x0A
RXC_JMP_LT   equ 0x0B
RXC_JMP_GT   equ 0x0C
RXC_JMP_LE   equ 0x0D
RXC_JMP_GE   equ 0x0E

; ── Stack & registers (0x10–0x1F) ────────────────────────────────────────────
RXC_PUSH     equ 0x10   ; [1-byte reg]
RXC_POP      equ 0x11   ; [1-byte reg]
RXC_MOV      equ 0x12   ; [1-byte dst] [1-byte src]
RXC_LOAD_IMM equ 0x13   ; [1-byte dst] [8-byte imm64]
RXC_LOAD_MEM equ 0x14   ; [4-byte slot] → r0
RXC_STORE_MEM equ 0x15  ; r0 → [4-byte slot]
RXC_LEA      equ 0x16   ; [4-byte sym_idx] → r0
RXC_SWAP     equ 0x17   ; swap r0, r1

; ── Integer arithmetic (0x20–0x27) ───────────────────────────────────────────
; All operate r0 = r0 op r1 (accumulator model, no explicit operands)
RXC_ADD      equ 0x20
RXC_SUB      equ 0x21
RXC_MUL      equ 0x22
RXC_DIV      equ 0x23
RXC_MOD      equ 0x24
RXC_NEG      equ 0x25   ; r0 = -r0
RXC_INC      equ 0x26   ; r0 = r0 + 1
RXC_DEC      equ 0x27   ; r0 = r0 - 1

; ── Float arithmetic (0x28–0x2F) ─────────────────────────────────────────────
RXC_FADD     equ 0x28
RXC_FSUB     equ 0x29
RXC_FMUL     equ 0x2A
RXC_FDIV     equ 0x2B
RXC_FMA      equ 0x2C   ; r0 = r0*r1 + r2
RXC_FSQRT    equ 0x2D
RXC_FABS     equ 0x2E
RXC_IABS     equ 0x2F   ; integer absolute value

; ── Bitwise & logic (0x30–0x37) ──────────────────────────────────────────────
RXC_AND      equ 0x30
RXC_OR       equ 0x31
RXC_XOR      equ 0x32
RXC_NOT      equ 0x33   ; r0 = ~r0 (bitwise)
RXC_SHL      equ 0x34
RXC_SHR      equ 0x35   ; logical
RXC_SAR      equ 0x36   ; arithmetic
RXC_LNOT     equ 0x37   ; r0 = !r0 (logical not: 0→1, nonzero→0)

; ── Comparison (0x38–0x3F) ───────────────────────────────────────────────────
; Result: r0 = 0 or 1 (bool)
RXC_CMP_EQ   equ 0x38
RXC_CMP_NE   equ 0x39
RXC_CMP_LT   equ 0x3A
RXC_CMP_GT   equ 0x3B
RXC_CMP_LE   equ 0x3C
RXC_CMP_GE   equ 0x3D

; ── Type conversion (0x3E–0x3F) ──────────────────────────────────────────────
RXC_CVTI2F   equ 0x3E   ; convert r0 int → float (r0 and r1 for rbx-cvt variant)
RXC_CVTF2I   equ 0x3F   ; convert r0 float → int

; ── Memory (0x40–0x4F) ───────────────────────────────────────────────────────
RXC_ALLOC    equ 0x40   ; r0 = alloc(r1 bytes)
RXC_FREE     equ 0x41   ; free(r0)
RXC_MEMCPY   equ 0x42
RXC_MEMZERO  equ 0x43
RXC_SIZEOF   equ 0x44   ; [1-byte type] → r0
RXC_CAST     equ 0x45   ; [1-byte type] r0 = cast(r0, type)
RXC_IDX_LOAD equ 0x46   ; r0 = r0[r1]
RXC_IDX_STORE equ 0x47  ; r0[r1] = r0 (r0=base,r1=idx in r2=val — simplified)
RXC_SEQ_ALLOC equ 0x48  ; r0 = new seq
RXC_SEQ_PUSH  equ 0x49  ; seq(r0).push(r1)
RXC_SEQ_POP   equ 0x4A  ; r0 = seq(r0).pop()
RXC_SEQ_LEN   equ 0x4B  ; r0 = len(r0)
RXC_SEQ_ELEM  equ 0x4C  ; r0 = seq(r1)[r0]

; ── I/O & system (0x60–0x6F) ─────────────────────────────────────────────────
RXC_PRINT_INT   equ 0x60  ; print r0 as integer
RXC_PRINT_STR   equ 0x61  ; print r0 as string ptr
RXC_PRINT_FLOAT equ 0x62  ; print r0 as float
RXC_PRINT_BOOL  equ 0x63  ; print r0 as bool
RXC_PRINT_CHAR  equ 0x64  ; print r0 as char (no newline)
RXC_READ_LINE   equ 0x65  ; r0 = read line from stdin
RXC_EXIT        equ 0x67  ; exit(r0)
RXC_PANIC       equ 0x68  ; panic with r0 as msg
RXC_CLOCK_MS    equ 0x69  ; r0 = current time ms
RXC_RAND        equ 0x6A  ; r0 = random int

; ── String ops (0x70–0x7F) ───────────────────────────────────────────────────
RXC_STR_LIT     equ 0x70  ; [4-byte pool_idx] → r0 (load string literal)
RXC_STR_CONCAT  equ 0x71  ; r0 = r0 ++ r1
RXC_INT_TO_STR  equ 0x72  ; r0 = int2str(r0)
RXC_FLOAT_TO_STR equ 0x73 ; r0 = float2str(r0)
RXC_STR_LEN     equ 0x74  ; r0 = len(r0)
RXC_STR_METHOD  equ 0x75  ; [1-byte method_id] — r0 = r0.method()
RXC_SHOW_INT    equ 0x76  ; print r0 as int, no newline
RXC_SHOW_STR    equ 0x77  ; print r0 as str, no newline
RXC_WARN_STR    equ 0x78  ; print r0 to stderr

; ── Frame & function (0xF0–0xFB) ─────────────────────────────────────────────
RXC_FRAME_ENTER  equ 0xF0  ; [1-byte param_cnt] [1-byte local_cnt]
RXC_FRAME_LEAVE  equ 0xF1  ; no operands
RXC_SPILL_SAVE   equ 0xF2  ; [1-byte depth] — save r0 to spill[depth]
RXC_SPILL_LOAD   equ 0xF3  ; [1-byte depth] — load spill[depth] into r1
RXC_FUNC_DEF     equ 0xF4  ; [1-byte namelen] [name bytes] [1-byte param_cnt]
RXC_FUNC_END     equ 0xF5  ; end of function body
RXC_ARG_PUSH     equ 0xF6  ; push r0 as next argument before CALL
RXC_ARG_POP      equ 0xF7  ; [1-byte count] — pop N args into frame slots
RXC_BOOL_NORM    equ 0xF8  ; normalize r0 to 0/1 bool
RXC_UNKNOWN_BOOL equ 0xF9  ; emit unknown/Kleene bool placeholder
RXC_BOUNDS_CHK   equ 0xFA  ; bounds check r0 (index) against r1 (limit)
RXC_OVERFLOW_CHK equ 0xFB  ; overflow check
