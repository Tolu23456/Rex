default rel
TOK_EOF equ 0
TOK_NEWLINE equ 1
TOK_INDENT equ 2
TOK_DEDENT equ 3
TOK_IDENT equ 4
TOK_INT_LIT equ 5
TOK_TYPE_INT equ 6
TOK_ASSIGN equ 7
TOK_COLON equ 8
TOK_OUTPUT equ 9
TOK_IF equ 10
TOK_FOR equ 11
TOK_IN equ 12
TOK_DOTDOT equ 13
TOK_EQEQ equ 14
TOK_ELSE equ 15
TOK_ELIF equ 16
TOK_WHILE equ 17
TOK_PROT equ 18
TOK_RETURN equ 19
TOK_STOP equ 20
TOK_AT equ 21
TOK_TYPE_FLOAT equ 22
TOK_FLOAT_LIT equ 23
TOK_TYPE_COMPLEX equ 24
TOK_COMPLEX_LIT equ 25
TOK_TYPE_BOOL equ 26
TOK_TRUE equ 27
TOK_FALSE equ 28
TOK_UNKNOWN equ 29
TOK_TYPE_STR equ 30
TOK_STR_LIT equ 31
TOK_PLUS equ 32
TOK_MINUS equ 33
TOK_LBRACK equ 34
TOK_RBRACK equ 35
TOK_LBRACE equ 36
TOK_RBRACE equ 37
TOK_COMMA equ 38
TOK_USE equ 39
TOK_MM equ 40
TOK_GC equ 41
TOK_STAR equ 42
TOK_SLASH equ 43
TOK_PERCENT equ 44
TOK_LPAREN equ 45
TOK_RPAREN equ 46
TOK_LT equ 47
TOK_GT equ 48
TOK_NEQ equ 49
TOK_LTE equ 50
TOK_GTE equ 51
TOK_AMP equ 52
TOK_PIPE equ 53
TOK_CARET equ 54
TOK_TILDE equ 55
TOK_LSHIFT equ 56
TOK_RSHIFT equ 57
TOK_AND equ 58
TOK_OR equ 59
TOK_NOT equ 60
TOK_ERR equ 61
TOK_TYPE_SEQ equ 62
TOK_PUSH equ 63
TOK_POP equ 64
TOK_LEN equ 65
TOK_SKIP equ 66
TOK_PASS equ 67
TOK_EACH equ 68
TOK_WHEN equ 69
TOK_TYPEOF equ 70
TOK_BIN equ 71
TOK_PLUSPLUS   equ 72
TOK_MINUSMINUS equ 73
TOK_SWAP       equ 74
TOK_ABS        equ 75
TOK_CAP        equ 76
TOK_IS         equ 77
TOK_ARROW      equ 78
TOK_STEP       equ 79
TOK_NONE       equ 80
TOK_KEYWORD    equ 81
TOK_AS         equ 82
TOK_REPEAT     equ 83
TOK_UNREACHABLE equ 84
TOK_ASSERT     equ 85
TOK_MEMO        equ 86
TOK_MEMO_RESET  equ 87
TOK_DOT         equ 88
TOK_CLOCK       equ 89
TOK_TYPE_DICT   equ 123

; ── V5.0 new tokens ───────────────────────────────────────────────────────────
TOK_CONST       equ 90   ; 'const' keyword
TOK_VOLATILE    equ 91   ; 'volatile' keyword
TOK_TYPE_SET    equ 92   ; 'set' type keyword
TOK_TYPE_TUP    equ 93   ; 'tup' type keyword
TOK_TYPE_ARR    equ 94   ; 'arr' type keyword
TOK_FN          equ 95   ; 'fn' lambda keyword
TOK_IMPORT      equ 96   ; 'import' keyword
TOK_FROM        equ 97   ; 'from' keyword
TOK_BLAST       equ 98   ; 'blast' SIMD loop
TOK_MATCH       equ 99   ; 'match' pattern match
TOK_TRY         equ 100  ; 'try' exception
TOK_EXCEPT      equ 101  ; 'except' exception handler
TOK_FINALLY     equ 102  ; 'finally' exception cleanup
TOK_CTX         equ 103  ; 'ctx' named allocator context
TOK_SHOW        equ 104  ; 'show' — output without newline
TOK_WARN        equ 105  ; 'warn' — stderr without exit
TOK_DEBUG_KW    equ 106  ; 'debug' — conditional stderr
TOK_WRITE       equ 107  ; 'write' — output without newline (alias)
TOK_FLUSH       equ 108  ; 'flush' — flush stdout
TOK_INPUT       equ 109  ; 'input' — read line from stdin
TOK_FLIP        equ 110  ; 'flip' — boolean toggle
TOK_RAND        equ 111  ; 'rand' — random value
TOK_FMT         equ 112  ; 'fmt' — string formatting
TOK_DOLLAR      equ 113  ; '$' — syscall intercept
TOK_PIPE_ARROW  equ 114  ; '|>' — pipeline operator
TOK_INTERP_OPEN  equ 115 ; '{' inside string interpolation
TOK_INTERP_CLOSE equ 116 ; '}' inside string interpolation
TOK_CARRY       equ 117  ; 'carry' hardware flag
TOK_OVERFLOW_KW equ 118  ; 'overflow' hardware flag keyword
TOK_HASH_KW     equ 119  ; 'hash' builtin
TOK_OWN         equ 120  ; 'own' ownership transfer
TOK_MOVE_KW     equ 121  ; 'move' move semantics keyword
TOK_ALIGN_KW    equ 122  ; 'align' alignment hint

; ── V5.0 decorator tokens (emitted by #-handler) ─────────────────────────────
TOK_PURE        equ 130  ; '#pure'
TOK_TOTAL       equ 131  ; '#total'
TOK_HOT         equ 132  ; '#hot'
TOK_COLD        equ 133  ; '#cold'
TOK_SAFE_KW     equ 134  ; '#safe'
TOK_UNSAFE      equ 135  ; '#unsafe'
TOK_INLINE_KW   equ 136  ; '#inline'

; ── Type system constants ─────────────────────────────────────────────────────
MEMO_PTR_BASE   equ 0x445000   ; base addr for per-proto memo pointers (after var table ends at 0x444000)
MEMO_TABLE_ENTRIES equ 1024    ; entries per memo table (int64, -1=uncached)
TYPE_INT     equ 1
TYPE_FLOAT   equ 2
TYPE_BOOL    equ 3
TYPE_COMPLEX equ 4
TYPE_STR     equ 5
TYPE_SEQ     equ 6
TYPE_TUP     equ 7   ; V5.0 tuple type
TYPE_SET     equ 8   ; V5.0 set type
TYPE_ARR     equ 9   ; V5.0 fixed-array type
TYPE_PROT    equ 10  ; V5.0 function pointer / lambda type
TYPE_DICT    equ 11  ; V5.0 explicit dict type constant

; ── Variable table layout ─────────────────────────────────────────────────────
; Offset 0..31:  name (32 bytes, NUL-terminated)
; Offset 32:     storage address (8 bytes) — VAR_STORAGE_BASE + idx*8
; Offset 40:     is_init flag (1 byte)
; Offset 41:     is_mutable flag (1 byte) — set when any ':var=' write site seen
; Offset 42:     is_const flag (1 byte)   — V5.0: set by 'const' keyword
; Offset 43:     is_volatile flag (1 byte)— V5.0: set by 'volatile' keyword
; Offset 44:     is_param flag (1 byte)   — set for protocol parameters
; Offset 45:     pad
; Offset 46:     reserved
; Offset 47:     pad
; Offset 48:     type byte (TYPE_INT=1, TYPE_FLOAT=2, etc.)
; Offset 49..63: pad
VAR_ENTRY_SIZE equ 64
VAR_MAX equ 256

; ── Proto table layout ────────────────────────────────────────────────────────
; Offset 0..15:  name (16 bytes, NUL-terminated)
; Offset 16:     param count (1 byte)
; Offset 17:     return type (1 byte)
; Offset 18..23: param types (6 bytes, one per param)
; Offset 24:     has_loop flag (1 byte) — O26
; Offset 25:     is_memo flag (1 byte)
; Offset 26:     is_hot flag (1 byte)   — V5.0: #hot
; Offset 27:     is_cold flag (1 byte)  — V5.0: #cold
; Offset 28:     is_pure flag (1 byte)  — V5.0: #pure
; Offset 29:     is_total flag (1 byte) — V5.0: #total
; Offset 30:     is_unsafe flag (1 byte)— V5.0: #unsafe
; Offset 31:     is_inline flag (1 byte)— V5.0: #inline
; Offset 32..47: pad
PROTO_ENTRY_SIZE equ 48
PROTO_MAX        equ 128  ; expanded from 32

; ── Memory layout ─────────────────────────────────────────────────────────────
VAR_STORAGE_BASE equ 4456448
LOAD_BASE equ 4194304
HEADERS_SIZE equ 176   ; SEC-04/05 fix: 64 (ELF hdr) + 2*56 (PT_LOAD + PT_GNU_STACK)

; ── Runtime blob sizes (existing — do NOT change) ─────────────────────────────
RT_PRI_SIZE equ 512
RT_PRS_SIZE equ 512
RT_PRB_SIZE equ 256
RT_PRF_SIZE equ 512
RT_PRC_SIZE equ 512
RT_SIP_SIZE equ 1024
RT_ALC_SIZE equ 4096
RT_PRQ_SIZE equ 1024

; ── V5.0 new runtime blob sizes ───────────────────────────────────────────────
RT_STR_CAT_SIZE      equ 512
RT_STR_EQ_SIZE       equ 256
RT_STR_FIND_SIZE     equ 512
RT_STR_LEN_SIZE      equ 128
RT_STR_UPPER_SIZE    equ 256
RT_STR_LOWER_SIZE    equ 256
RT_STR_TRIM_SIZE     equ 256
RT_STR_REV_SIZE      equ 256
RT_INT2STR_SIZE      equ 256
RT_FLOAT2STR_SIZE    equ 512
RT_STR_SPLIT_SIZE    equ 512
RT_STR_JOIN_SIZE     equ 512
RT_STR_STARTS_SIZE   equ 256
RT_STR_ENDS_SIZE     equ 256
RT_STR_CONTAINS_SIZE equ 128
RT_STR_SLICE_SIZE    equ 256
RT_STR_REPLACE_SIZE  equ 512
RT_STR_COUNT_SIZE    equ 256
RT_STR_REPEAT_SIZE   equ 256
RT_MATH_SQRT_SIZE    equ 64
RT_MATH_FLOOR_SIZE   equ 64
RT_MATH_CEIL_SIZE    equ 64
RT_MATH_ABS_F_SIZE   equ 64
RT_MATH_SIN_SIZE     equ 128
RT_MATH_COS_SIZE     equ 128
RT_MATH_EXP_SIZE     equ 256
RT_MATH_LOG_SIZE     equ 256
RT_MATH_POW_SIZE     equ 256
RT_MATH_MIN_SIZE     equ 64
RT_MATH_MAX_SIZE     equ 64
RT_BOUNDS_ERR_SIZE   equ 256
RT_OVERFLOW_ERR_SIZE equ 256
RT_NULL_ERR_SIZE     equ 256
RT_SEQ_SORT_SIZE     equ 1024
RT_SEQ_SUM_SIZE      equ 256
RT_SEQ_MIN_SIZE      equ 256
RT_SEQ_MAX_SIZE      equ 256
RT_SEQ_CONTAINS_SIZE equ 256
RT_SEQ_REVERSE_SIZE  equ 256
RT_HEAP_ALLOC_SIZE   equ 1024
RT_HEAP_FREE_SIZE    equ 512
RT_STATIC_ALLOC_SIZE equ 256

; ── Total runtime size (existing blobs only — kept deterministic) ─────────────
RT_TOTAL_SIZE equ 8448   ; original value — new blobs appended after existing

; ── Existing blob offsets (from LOAD_BASE + HEADERS_SIZE) ────────────────────
; SEC-04/05 fix: all offsets increased by +56 because HEADERS_SIZE grew from 120 to 176
; (added one PT_GNU_STACK program header = 56 bytes before the runtime blobs)
RT_PRI_OFFSET equ 181
RT_PRS_OFFSET equ 693
RT_PRB_OFFSET equ 1205
RT_PRF_OFFSET equ 1461
RT_PRC_OFFSET equ 1973
RT_SIP_OFFSET equ 2485
RT_ALC_OFFSET equ 3509
RT_PRQ_OFFSET equ 7605
CODE_START equ 8629

; ── V5.0 new blob offsets (after existing 8448 bytes)
; These are calculated as: EXISTING_OFFSET + RT_TOTAL_SIZE
; Base for new blobs = RT_PRQ_OFFSET + RT_PRQ_SIZE = 7605 + 1024 = 8629
; SEC-04/05: all offsets shifted +56 from original values due to HEADERS_SIZE change.
; CODE_START = 8629 means the user-code JMP is emitted right after the last blob (PRQ).
; New blobs are appended BEFORE the code start by including them in the binary.
; The actual offsets will be recalculated by runtime.asm include order.
; For now, define symbolic offsets for use in codegen dispatch.
RT_STR_CAT_OFFSET      equ CODE_START + 0
RT_STR_EQ_OFFSET       equ RT_STR_CAT_OFFSET    + RT_STR_CAT_SIZE
RT_STR_FIND_OFFSET     equ RT_STR_EQ_OFFSET     + RT_STR_EQ_SIZE
RT_STR_LEN_OFFSET      equ RT_STR_FIND_OFFSET   + RT_STR_FIND_SIZE
RT_STR_UPPER_OFFSET    equ RT_STR_LEN_OFFSET    + RT_STR_LEN_SIZE
RT_STR_LOWER_OFFSET    equ RT_STR_UPPER_OFFSET  + RT_STR_UPPER_SIZE
RT_STR_TRIM_OFFSET     equ RT_STR_LOWER_OFFSET  + RT_STR_LOWER_SIZE
RT_STR_REV_OFFSET      equ RT_STR_TRIM_OFFSET   + RT_STR_TRIM_SIZE
RT_INT2STR_OFFSET      equ RT_STR_REV_OFFSET    + RT_STR_REV_SIZE
RT_FLOAT2STR_OFFSET    equ RT_INT2STR_OFFSET    + RT_INT2STR_SIZE
RT_STR_SPLIT_OFFSET    equ RT_FLOAT2STR_OFFSET  + RT_FLOAT2STR_SIZE
RT_STR_JOIN_OFFSET     equ RT_STR_SPLIT_OFFSET  + RT_STR_SPLIT_SIZE
RT_STR_STARTS_OFFSET   equ RT_STR_JOIN_OFFSET   + RT_STR_JOIN_SIZE
RT_STR_ENDS_OFFSET     equ RT_STR_STARTS_OFFSET + RT_STR_STARTS_SIZE
RT_STR_CONTAINS_OFFSET equ RT_STR_ENDS_OFFSET   + RT_STR_ENDS_SIZE
RT_STR_SLICE_OFFSET    equ RT_STR_CONTAINS_OFFSET + RT_STR_CONTAINS_SIZE
RT_STR_REPLACE_OFFSET  equ RT_STR_SLICE_OFFSET  + RT_STR_SLICE_SIZE
RT_STR_COUNT_OFFSET    equ RT_STR_REPLACE_OFFSET + RT_STR_REPLACE_SIZE
RT_STR_REPEAT_OFFSET   equ RT_STR_COUNT_OFFSET  + RT_STR_COUNT_SIZE
RT_MATH_SQRT_OFFSET    equ RT_STR_REPEAT_OFFSET + RT_STR_REPEAT_SIZE
RT_MATH_FLOOR_OFFSET   equ RT_MATH_SQRT_OFFSET  + RT_MATH_SQRT_SIZE
RT_MATH_CEIL_OFFSET    equ RT_MATH_FLOOR_OFFSET + RT_MATH_FLOOR_SIZE
RT_MATH_ABS_F_OFFSET   equ RT_MATH_CEIL_OFFSET  + RT_MATH_CEIL_SIZE
RT_MATH_SIN_OFFSET     equ RT_MATH_ABS_F_OFFSET + RT_MATH_ABS_F_SIZE
RT_MATH_COS_OFFSET     equ RT_MATH_SIN_OFFSET   + RT_MATH_SIN_SIZE
RT_MATH_EXP_OFFSET     equ RT_MATH_COS_OFFSET   + RT_MATH_COS_SIZE
RT_MATH_LOG_OFFSET     equ RT_MATH_EXP_OFFSET   + RT_MATH_EXP_SIZE
RT_MATH_POW_OFFSET     equ RT_MATH_LOG_OFFSET   + RT_MATH_LOG_SIZE
RT_MATH_MIN_OFFSET     equ RT_MATH_POW_OFFSET   + RT_MATH_POW_SIZE
RT_MATH_MAX_OFFSET     equ RT_MATH_MIN_OFFSET   + RT_MATH_MIN_SIZE
RT_BOUNDS_ERR_OFFSET   equ RT_MATH_MAX_OFFSET   + RT_MATH_MAX_SIZE
RT_OVERFLOW_ERR_OFFSET equ RT_BOUNDS_ERR_OFFSET + RT_BOUNDS_ERR_SIZE
RT_NULL_ERR_OFFSET     equ RT_OVERFLOW_ERR_OFFSET + RT_OVERFLOW_ERR_SIZE
RT_SEQ_SORT_OFFSET     equ RT_NULL_ERR_OFFSET   + RT_NULL_ERR_SIZE
RT_SEQ_SUM_OFFSET      equ RT_SEQ_SORT_OFFSET   + RT_SEQ_SORT_SIZE
RT_SEQ_MIN_OFFSET      equ RT_SEQ_SUM_OFFSET    + RT_SEQ_SUM_SIZE
RT_SEQ_MAX_OFFSET      equ RT_SEQ_MIN_OFFSET    + RT_SEQ_MIN_SIZE
RT_SEQ_CONTAINS_OFFSET equ RT_SEQ_MAX_OFFSET    + RT_SEQ_MAX_SIZE
RT_SEQ_REVERSE_OFFSET  equ RT_SEQ_CONTAINS_OFFSET + RT_SEQ_CONTAINS_SIZE
RT_HEAP_ALLOC_OFFSET   equ RT_SEQ_REVERSE_OFFSET + RT_SEQ_REVERSE_SIZE
RT_HEAP_FREE_OFFSET    equ RT_HEAP_ALLOC_OFFSET + RT_HEAP_ALLOC_SIZE
RT_STATIC_ALLOC_OFFSET equ RT_HEAP_FREE_OFFSET  + RT_HEAP_FREE_SIZE

; New CODE_START after all new blobs are inserted
NEW_CODE_START equ RT_STATIC_ALLOC_OFFSET + RT_STATIC_ALLOC_SIZE

; ── GC/allocator context ─────────────────────────────────────────────────────
GC_MODE_ADDR equ VAR_STORAGE_BASE - 8  ; runtime gc-mode word (written by use gc)

; ── Compiler safety limits ────────────────────────────────────────────────────
MAX_ERRORS equ 20   ; max compiler errors before stopping (RULE 14)
