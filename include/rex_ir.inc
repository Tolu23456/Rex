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
IR_LEA_VAR      equ 0x08

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

; Category 5: Comparison
IR_CMP          equ 0x41

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
IR_HALT         equ 0x67

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
IR_MAX_RECORDS  equ 1024

; IR flags
IR_FLAG_CONST   equ 1
IR_FLAG_DEAD    equ 2
IR_FLAG_SPILLED equ 4
