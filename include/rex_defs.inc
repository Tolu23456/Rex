; ============================================================
; Rex Bootstrap Compiler — Shared Constants
; include/rex_defs.inc
; ============================================================

; ----------------------------------------------------------------
; ELF / Memory layout
; ----------------------------------------------------------------
%define LOAD_BASE           0x400000
%define VAR_STORAGE_BASE    0x440000
%define VAR_ENTRY_SIZE      64
%define VAR_MAX             256
%define PROTO_ENTRY_SIZE    48
%define PROTO_MAX           128
%define SRC_BUF_SIZE        1048576   ; 1 MB

; ELF header + 2 program headers (LOAD + GNU_STACK)
%define HEADERS_SIZE        176

; ----------------------------------------------------------------
; Runtime blob offsets (absolute file offset = LOAD_BASE + N)
; Layout: 176 B headers | 5 B JMP | blobs ... | user code
; ----------------------------------------------------------------
%define RT_JMP_OFFSET       176
%define RT_PRI_OFFSET       181
%define RT_PRS_OFFSET       693
%define RT_PRB_OFFSET       1205
%define RT_PRF_OFFSET       1461
%define RT_PRC_OFFSET       1973
%define RT_SIP_OFFSET       2485
%define RT_ALC_OFFSET       3509
%define RT_PRQ_OFFSET       7605
%define RT_STR_OFFSET       8629
%define RT_STR_BOOL_OFFSET  (RT_STR_OFFSET + 160)  ; rt_str_bool_blob fixed at byte 160
%define RT_INP_OFFSET       8885
%define RT_STR_CAT_OFFSET   9397      ; string concat blob (NEW)
%define CODE_START          9909      ; 9397 + 512

; JMP rel32 = CODE_START - (RT_JMP_OFFSET + 5) = 9909 - 181 = 9728
%define RT_TOTAL_SIZE       9728

; Runtime blob sizes
%define RT_PRI_SIZE         512
%define RT_PRS_SIZE         512
%define RT_PRB_SIZE         256
%define RT_PRF_SIZE         512
%define RT_PRC_SIZE         512
%define RT_SIP_SIZE         1024
%define RT_ALC_SIZE         4096
%define RT_PRQ_SIZE         1024
%define RT_STR_SIZE         256
%define RT_INP_SIZE         512
%define RT_STR_CAT_SIZE     512       ; string concat blob (NEW)

; Dict entry points inside rt_prq_blob
%define RT_DICT_NEW_OFFSET  7606
%define RT_DICT_SET_OFFSET  7633
%define RT_DICT_GET_OFFSET  7682

; Memo cache pointer array (just above var storage)
%define MEMO_PTR_BASE       0x445000

; ----------------------------------------------------------------
; Static runtime scratch areas (within mapped region)
; Between var table end (0x444000) and memo cache (0x445000):
;   str ring buffer: 8 slots × 32 bytes = 256 bytes at 0x444000
;   str ring index : 1 byte at 0x444100
;   input line buf : 4096 bytes at 0x444200 - 0x445200
; Extended by MEM_EXTRA to cover all scratch areas.
; ----------------------------------------------------------------
%define STR_RING_BASE       0x444000   ; 256 bytes (8 × 32-byte slots)
%define STR_RING_IDX        0x444100   ; 1 byte: ring slot index (mod 8)
%define INPUT_BUF_BASE      0x446000   ; 4096-byte input line buffer
%define INPUT_BUF_MAX       4095       ; max bytes to read

; Extra bytes added to p_memsz beyond p_filesz to cover scratch areas
%define MEM_EXTRA           0x48000

; ----------------------------------------------------------------
; Output buffer size
; ----------------------------------------------------------------
%define OUT_BUF_SIZE        524288    ; 512 KB

; ----------------------------------------------------------------
; Variable table entry layout (64 bytes per entry)
;   [0..31]  name (null-padded, max 32 chars)
;   [32..39] value (qword)
;   [40]     is_init (byte: 0=uninit, 1=init)
;   [41]     is_mutable (byte)
;   [42]     type (byte — see TYPE_* below)
;   [43..63] reserved
; ----------------------------------------------------------------
%define VAR_NAME_OFF        0
%define VAR_VAL_OFF         32
%define VAR_INIT_OFF        40
%define VAR_MUT_OFF         41
%define VAR_TYPE_OFF        42

; ----------------------------------------------------------------
; Protocol table entry layout (48 bytes per entry)
;   [0..31]  name (null-padded)
;   [32..39] out_idx at definition (qword)
;   [40]     param_count (byte)
;   [41..46] param var indices (6 bytes)
;   [47]     ret_type (byte)
; ----------------------------------------------------------------
%define PROTO_NAME_OFF      0
%define PROTO_OUTIDX_OFF    32
%define PROTO_PARAMCNT_OFF  40
%define PROTO_PARAMS_OFF    41
%define PROTO_RETTYPE_OFF   47

; ----------------------------------------------------------------
; Type codes
; ----------------------------------------------------------------
%define TYPE_UNKNOWN        0
%define TYPE_INT            1
%define TYPE_FLOAT          2
%define TYPE_BOOL           3
%define TYPE_COMPLEX        4
%define TYPE_STR            5
%define TYPE_SEQ            6
%define TYPE_DICT           7
%define TYPE_CHAR           8
%define TYPE_BYTE           9

; ----------------------------------------------------------------
; Token IDs
; ----------------------------------------------------------------
%define TOK_EOF             0
%define TOK_INT_LIT         1
%define TOK_FLOAT_LIT       2
%define TOK_IDENT           3
%define TOK_NEWLINE         4
%define TOK_INDENT          5
%define TOK_DEDENT          6
%define TOK_COLON           7
%define TOK_EQ              8
%define TOK_PLUS            9
%define TOK_MINUS           10
%define TOK_STAR            11
%define TOK_SLASH           12
%define TOK_PERCENT         13
%define TOK_AMP             14
%define TOK_PIPE            15
%define TOK_CARET           16
%define TOK_TILDE           17
%define TOK_LSHIFT          18
%define TOK_RSHIFT          19
%define TOK_EQEQ            20
%define TOK_NEQ             21
%define TOK_LT              22
%define TOK_GT              23
%define TOK_LE              24
%define TOK_GE              25
%define TOK_LPAREN          26
%define TOK_RPAREN          27
%define TOK_LBRACKET        28
%define TOK_RBRACKET        29
%define TOK_DOT             30
%define TOK_DOTDOT          31
%define TOK_AT              32
%define TOK_BANG            33
%define TOK_COMMA           34
%define TOK_ARROW           35
%define TOK_QUESTION        36
%define TOK_HASH            37

; Keywords — types
%define TOK_TYPE_INT        40
%define TOK_TYPE_FLOAT      41
%define TOK_TYPE_BOOL       42
%define TOK_TYPE_STR        43
%define TOK_TYPE_COMPLEX    44
%define TOK_TYPE_SEQ        45
%define TOK_TYPE_DICT       46
%define TOK_TYPE_CHAR       47
%define TOK_TYPE_BYTE       48
%define TOK_TYPE_ARR        49
%define TOK_TYPE_TUP        50

; Keywords — control flow
%define TOK_IF              51
%define TOK_ELIF            52
%define TOK_ELSE            53
%define TOK_WHILE           54
%define TOK_FOR             55
%define TOK_IN              56
%define TOK_STOP            57
%define TOK_SKIP            58
%define TOK_PASS            59
%define TOK_WHEN            60
%define TOK_IS              61
%define TOK_EACH            62
%define TOK_REPEAT          63
%define TOK_STEP            64

; Keywords — protocols
%define TOK_PROT            65
%define TOK_RETURN          66
%define TOK_MEMO            67

; Keywords — I/O / misc
%define TOK_OUTPUT          68
%define TOK_ERR             69
%define TOK_INPUT           70
%define TOK_USE             71
%define TOK_MM              72
%define TOK_POOL            73
%define TOK_ARENA           74
%define TOK_GC              75
%define TOK_PUSH            76
%define TOK_POP             77
%define TOK_LEN             78
%define TOK_CAP             79
%define TOK_SWAP            80
%define TOK_TYPEOF          81
%define TOK_ABS             82
%define TOK_ASSERT          83
%define TOK_UNREACHABLE     84
%define TOK_MEMO_RESET      85
%define TOK_CLOCK           86

; Keywords — literals
%define TOK_TRUE            87
%define TOK_FALSE           88
%define TOK_NEUTRAL         89

; Keywords — operators
%define TOK_AND             90
%define TOK_OR              91
%define TOK_NOT             92
%define TOK_BIN             93

; Prefix inc/dec
%define TOK_PLUSPLUS        94
%define TOK_MINUSMINUS      95

; String / char literals (tok_int holds VA of string data in code stream)
%define TOK_STR_LIT         96
%define TOK_CHAR_LIT        97

; Switch statement (design.md §7.2 — value dispatch, replaces old when/is)
%define TOK_SWITCH          100

; Raise / try / except / finally (design.md §9.5)
%define TOK_RAISE           101
%define TOK_TRY             102
%define TOK_EXCEPT          103
%define TOK_FINALLY         104

; Flip keyword (in-place bool negation)
%define TOK_FLIP            105

; Legacy: unknown (random bool via rdrand) — kept for dead-code path in parse_factor
%define TOK_UNKNOWN         99

; ----------------------------------------------------------------
; Stage-9 built-in keywords
; ----------------------------------------------------------------
%define TOK_SIGN            106   ; sign(x) → -1 / 0 / 1
%define TOK_CLZ             107   ; clz(x) → count leading zeros
%define TOK_CEIL            108   ; ceil(x) → SSE roundsd mode 2
%define TOK_FLOOR           109   ; floor(x) → SSE roundsd mode 1
%define TOK_FRACT           110   ; fract(x) → x - floor(x)
%define TOK_REAL            111   ; real(c) → low qword of complex
%define TOK_IMAG            112   ; imag(c) → high qword of complex
%define TOK_CONJ            113   ; conj(c) → negate imag part
%define TOK_RAND            114   ; rand() → 64-bit rdrand
%define TOK_CARRY           115   ; carry → CF flag (0 or 1)
%define TOK_OVERFLOW        116   ; overflow → OF flag (0 or 1)
%define TOK_HASH_KW         118   ; hash(x) → simple hash of x
%define TOK_MATCH           119   ; match (structured when, jump-table opt)
%define TOK_DOLLAR          120   ; $ → direct syscall

; ----------------------------------------------------------------
; ELF constants
; ----------------------------------------------------------------
%define ET_EXEC             2
%define EM_X86_64           62
%define EV_CURRENT          1
%define PT_LOAD             1
%define PT_GNU_STACK        0x6474e551
%define PF_X                1
%define PF_W                2
%define PF_R                4

; ----------------------------------------------------------------
; Linux syscall numbers (x86-64)
; ----------------------------------------------------------------
%define SYS_read            0
%define SYS_write           1
%define SYS_open            2
%define SYS_close           3
%define SYS_mmap            9
%define SYS_exit            60
%define SYS_clock_gettime   228

; ----------------------------------------------------------------
; Parser stack limits
; ----------------------------------------------------------------
%define JUMP_STACK_MAX      64
%define LOOP_STACK_MAX      32
%define SCOPE_STACK_MAX     64
%define FWD_REF_MAX         128
