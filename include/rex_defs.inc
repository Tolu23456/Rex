; Rex Compiler Constants and Definitions

; Token Types
TOK_EOF         equ 0
TOK_IDENT       equ 1
TOK_INT_LIT     equ 2
TOK_FLOAT_LIT   equ 3
TOK_STR_LIT     equ 4
TOK_BOOL_LIT    equ 5  ; true, false, neutral
TOK_CHAR_LIT    equ 6
TOK_ERROR       equ 7  ; unrecognized character

; Keywords
TOK_TYPE        equ 10 ; int, float, bool, str, char, byte
TOK_OUTPUT      equ 11 ; output
TOK_PROT        equ 12 ; prot
TOK_RETURN      equ 13 ; return
TOK_CONST       equ 14 ; const
TOK_TYPE_KW     equ 15 ; type
TOK_STRUCT      equ 16 ; struct
TOK_ENUM        equ 17 ; enum
TOK_TUP         equ 18 ; tup

; Operators / Sigils
TOK_COLON       equ 20 ; :
TOK_ASSIGN      equ 21 ; =
TOK_PLUS        equ 22 ; +
TOK_MINUS       equ 23 ; -
TOK_STAR        equ 24 ; *
TOK_SLASH       equ 25 ; /
TOK_LPAREN      equ 26 ; (
TOK_RPAREN      equ 27 ; )
TOK_MOD         equ 28 ; %
TOK_AND         equ 29 ; &
TOK_EQ          equ 50 ; ==
TOK_NE          equ 51 ; !=
TOK_LT          equ 52 ; <
TOK_GT          equ 53 ; >
TOK_LE          equ 54 ; <=
TOK_GE          equ 55 ; >=
TOK_DOTDOT      equ 56 ; ..
TOK_LSHIFT      equ 57 ; <<
TOK_RSHIFT      equ 58 ; >>
TOK_TILDE       equ 59 ; ~
TOK_PLUSPLUS     equ 60 ; ++
TOK_MINUSMINUS   equ 61 ; --
TOK_ARROW       equ 62 ; ->
TOK_OR          equ 33 ; |
TOK_XOR         equ 34 ; ^
TOK_LBRACKET    equ 35 ; [
TOK_RBRACKET    equ 36 ; ]
TOK_LBRACE      equ 37 ; {
TOK_RBRACE      equ 38 ; }
TOK_COMMA       equ 39 ; ,
TOK_DOT         equ 40 ; .
TOK_NULL        equ 41 ; null
TOK_QUESTION    equ 42 ; ?
TOK_QQ          equ 43 ; ??
TOK_BOOL_AND    equ 44 ; and (bool keyword)
TOK_BOOL_OR     equ 45 ; or  (bool keyword)
TOK_BOOL_NOT    equ 46 ; not (bool keyword)

; Control Flow Keywords
TOK_IF          equ 70 ; if
TOK_ELIF        equ 71 ; elif
TOK_ELSE        equ 72 ; else
TOK_FOR         equ 73 ; for
TOK_WHILE       equ 74 ; while
TOK_EACH        equ 75 ; each
TOK_REPEAT      equ 76 ; repeat
TOK_IN          equ 77 ; in
TOK_STEP        equ 78 ; step
TOK_STOP        equ 79 ; stop
TOK_SKIP        equ 80 ; skip
TOK_PASS        equ 81 ; pass
TOK_IS          equ 82 ; is
TOK_IS_NOT      equ 83 ; is not
TOK_SWITCH      equ 84 ; switch
TOK_TRY         equ 85 ; try
TOK_EXCEPT      equ 86 ; except
TOK_FINALLY     equ 87 ; finally
TOK_RAISE       equ 88 ; raise
TOK_SWAP        equ 89 ; swap
TOK_ABS         equ 90 ; abs
TOK_FLIP        equ 91 ; flip
TOK_LEN         equ 92 ; len
TOK_SCOPE       equ 93 ; scope
TOK_ASSERT      equ 94 ; assert
TOK_UNREACHABLE equ 95 ; unreachable
TOK_MODULE      equ 96 ; module
TOK_USE         equ 97 ; use
TOK_DECORATOR   equ 98 ; decorator
TOK_FN          equ 99 ; fn (function literals)
TOK_HASH        equ 100 ; hash
TOK_CARRY       equ 101 ; carry
TOK_OVERFLOW    equ 102 ; overflow
TOK_RAND        equ 103 ; rand
TOK_WHEN        equ 104 ; when
TOK_WITH        equ 105 ; with
TOK_OPEN        equ 106 ; open
TOK_AS          equ 107 ; as
TOK_AT          equ 108 ; @ (protocol call prefix)

; Compound Assignment Operators
TOK_PLUS_EQ     equ 110 ; +=
TOK_MINUS_EQ    equ 111 ; -=
TOK_STAR_EQ     equ 112 ; *=
TOK_SLASH_EQ    equ 113 ; /=
TOK_MOD_EQ      equ 114 ; %=
TOK_AND_EQ      equ 115 ; &=
TOK_OR_EQ       equ 116 ; |=
TOK_XOR_EQ      equ 117 ; ^=
TOK_LSHIFT_EQ   equ 118 ; <<=
TOK_RSHIFT_EQ   equ 119 ; >>=
TOK_DOTDOT_EQ   equ 120 ; ..=
TOK_QQ_DOT      equ 121 ; ?. (null-safe method call)
TOK_SYSCALL     equ 122 ; $ (syscall operator)

; Control Tokens
TOK_NEWLINE     equ 30
TOK_INDENT      equ 31
TOK_DEDENT      equ 32

; Type IDs (matching rex_ir.md)
TYPE_VOID       equ 0
TYPE_INT        equ 1
TYPE_FLOAT      equ 2
TYPE_BOOL       equ 3
TYPE_COMPLEX    equ 4
TYPE_STR        equ 5
TYPE_SEQ        equ 6
TYPE_DICT       equ 7
TYPE_CHAR       equ 8
TYPE_BYTE       equ 9
TYPE_ALIAS      equ 10
TYPE_FILE       equ 10 ; file handle (8-byte heap ptr) — reuses unused alias slot
TYPE_TUP        equ 11
TYPE_ARR        equ 12

; Scopes
SCOPE_GLOBAL    equ 0
SCOPE_LOCAL     equ 1
SCOPE_BLOCK     equ 2

; Symbol Table Entry Layout (64 bytes total)
; Offset  Size  Field
; 0       32    name (null-terminated string)
; 32      4     type_id (dword, TYPE_*)
; 36      1     scope (SCOPE_*)
; 37      1     is_mutable (0 = no, 1 = yes)
; 38      1     is_init (0 = no, 1 = yes)
; 40      4     offset (offset on stack or memory address)
; 44      2     elem_type (container element type, seq/dict/arr)
; 46      1     module id (owning module, design.md §17)
; 47      17    _pad (unused)
SYM_ENTRY_SIZE  equ 64
SYM_MAX         equ 256
SYM_MODULE_OFF  equ 46

; ELF64 Layout Constants
LOAD_BASE        equ 0x00400000
VAR_STORAGE_BASE equ 0x00440000
VAR_ENTRY_SIZE   equ 64
VAR_ENTRY_SIZE_LOG2 equ 6
VAR_MAX          equ 256
HEADERS_SIZE     equ 125       ; 64 ELF header + 56 program header + 5 JMP

; Struct construction scratch pool lives in the OUTPUT binary's data segment,
; right after the variable storage area, so the emitted LEA_VAR addresses are
; valid in the running program (the parser's own bss is rexc-process memory).
STRUCT_SCRATCH_BASE equ (VAR_STORAGE_BASE + (VAR_MAX * VAR_ENTRY_SIZE))
STRUCT_SCRATCH_SIZE equ 262144 ; struct construction scratch pool (never reclaimed)

VREG_MAX         equ 65536
SRC_FILE_MAX     equ 65536
OUT_BUF_MAX      equ 131072
VAR_MEM_OFFSET   equ (STRUCT_SCRATCH_BASE - LOAD_BASE) + STRUCT_SCRATCH_SIZE
WHEN_MONITOR_MAX equ 256      ; distinct `when expr` monitors per program
LOOP_MAX_DEPTH   equ 32       ; max nested loop depth for stop/skip tracking

; Protocol Table Layout (proto table entries, grammar.md Section 30)
; Offset  Size  Field
; 0       32    name (null-terminated string)
; 32      8     body_offset (codegen offset of protocol body)
; 40      1     param_count
; 41      1     ret_type tag
; 42      1     ret_count
; 43      1     ret_is_result (0 = no, 1 = result[T])
; 44      1     decorator_mask (bit0=memo,1=pure,2=total,3=inline,4=noinline,5=hot,6=cold,7=unsafe)
; 45      3     reserved
; 48      65    param_var_indices (1 byte per param, 0xFF = unused)
; 113     4     var_low  (lowest var slot offset touched by body)
; 117     4     var_high (one past highest var slot offset touched by body)
; 121     1     ret0_type — concrete return type of return value 0
; 122     1     ret1_type — concrete return type of return value 1 (tuple)
; 123     5     reserved
PROTO_MAX            equ 256
PROTO_ENTRY_SIZE     equ 128
PROTO_NAME_OFF       equ 0
PROTO_BODY_OFF       equ 32
PROTO_PARAM_COUNT_OFF equ 40
PROTO_RET_TYPE_OFF   equ 41
PROTO_RET_COUNT_OFF  equ 42
PROTO_RET_IS_RESULT_OFF equ 43
PROTO_DECORATOR_MASK_OFF equ 44
PROTO_MODULE_OFF     equ 45   ; owning module id (design.md §17)
PROTO_PRIVATE_OFF    equ 46   ; 1 = private (`_` prefix, invisible outside module)
PROTO_DEFINED_OFF    equ 47   ; 1 = body parsed
PROTO_PARAM_VAR_IDX_OFF equ 48
PROTO_RET0_TYPE_OFF  equ 121
PROTO_RET1_TYPE_OFF  equ 122
PROTO_VAR_LOW_OFF    equ 113
PROTO_VAR_HIGH_OFF   equ 117
PROTO_PARAM_UNUSED   equ 0xFF

; Decorator bits
DECOR_MEMOIZE   equ 1<<0
DECOR_PURE      equ 1<<1
DECOR_TOTAL     equ 1<<2
DECOR_INLINE    equ 1<<3
DECOR_NOINLINE  equ 1<<4
DECOR_HOT       equ 1<<5
DECOR_COLD      equ 1<<6
DECOR_UNSAFE    equ 1<<7

; Return type tags
RET_TYPE_NONE    equ 0 ; void / no explicit return type
RET_TYPE_SCALAR  equ 1 ; single scalar type
RET_TYPE_TUPLE   equ 2 ; (T1, T2, ...) multi-return
RET_TYPE_RESULT  equ 3 ; result[T]

; Protocol call argument classification (matches IR_CALL_ARG imm)
CALL_ARG_REG0     equ 0 ; rdi
CALL_ARG_REG1     equ 1 ; rsi
CALL_ARG_REG2     equ 2 ; rdx
CALL_ARG_REG3     equ 3 ; rcx
CALL_ARG_REG4     equ 4 ; r8
CALL_ARG_REG5     equ 5 ; r9
CALL_ARG_STACK    equ 6 ; pushed on stack

; Collection defaults
DICT_INITIAL_CAPACITY equ 16
SEQ_ELEMENT_SIZE equ 8
TYPE_NAME_BUF_SIZE equ 4096

; Module System (design.md §17)
; Module table entry layout (128 bytes)
; Offset  Size  Field
; 0       64    name (null-terminated, max 63)
; 64      1     status (MOD_ST_*)
; 65      1     kind (MOD_KIND_*)
; 66      2     _pad
; 68      8     source buffer ptr (file modules)
; 76      8     source length (file modules)
; 84      4     prescan visiting flag (cycle detection)
; 88      40    _pad
MODULE_MAX          equ 32
MODULE_ENTRY_SIZE   equ 128
MODULE_NAME_MAX     equ 64
MODULE_NAME_OFF     equ 0
MODULE_STATUS_OFF   equ 64
MODULE_KIND_OFF     equ 65
MODULE_SRC_PTR_OFF  equ 68
MODULE_SRC_LEN_OFF  equ 76
MODULE_VISITING_OFF equ 84

MOD_ST_NONE       equ 0
MOD_ST_PRESCANNED equ 1
MOD_ST_PARSED     equ 2

MOD_KIND_MAIN   equ 1
MOD_KIND_INLINE equ 2
MOD_KIND_FILE   equ 3

; Import record table (per-module qualified/selective imports, design.md §17.2)
; Record layout (24 bytes)
; 0       4     source module id (the importing module)
; 4       4     target module id
; 8       8     imported name ptr (pool string; 0 for '*')
; 16      4     imported name len (0 for '*')
; 20      4     is_star (1 = `use m: *`)
IMPORT_MAX         equ 256
IMPORT_ENTRY_SIZE  equ 24
IMPORT_SRC_OFF     equ 0
IMPORT_TGT_OFF     equ 4
IMPORT_NAME_PTR_OFF equ 8
IMPORT_NAME_LEN_OFF equ 16
IMPORT_STAR_OFF    equ 20

; Lexer state save area layout (for cross-buffer module parsing)
LEXSV_SIZE         equ 224
LEXSV_SRC_PTR      equ 0
LEXSV_SRC_LEN      equ 8
LEXSV_SRC_IDX      equ 16
LEXSV_LINE_NUM     equ 24
LEXSV_LINE_START   equ 32
LEXSV_TOK_TYPE     equ 40
LEXSV_TOK_STR_PTR  equ 48
LEXSV_TOK_STR_LEN  equ 56
LEXSV_TOK_IVAL     equ 64
LEXSV_TOK_FVAL     equ 72
LEXSV_PEND_DEDENTS equ 80
LEXSV_AT_LINE_START equ 84
LEXSV_INDENT_LEN   equ 88
LEXSV_INDENT_STACK equ 96
; 96 + 128 = 224
