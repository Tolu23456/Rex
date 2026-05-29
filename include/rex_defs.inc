default rel

; --- Token Types ---
TOK_EOF          equ 0
TOK_NEWLINE      equ 1
TOK_INDENT       equ 2
TOK_DEDENT       equ 3
TOK_IDENT        equ 4
TOK_INT_LIT      equ 5
TOK_TYPE_INT     equ 6
TOK_ASSIGN       equ 7
TOK_COLON        equ 8
TOK_OUTPUT       equ 9
TOK_IF           equ 10
TOK_FOR          equ 11
TOK_IN           equ 12
TOK_DOTDOT       equ 13
TOK_EQEQ         equ 14
TOK_ELSE         equ 15
TOK_ELIF         equ 16
TOK_WHILE        equ 17
TOK_PROT         equ 18
TOK_RETURN       equ 19
TOK_STOP         equ 20
TOK_AT           equ 21
TOK_TYPE_FLOAT   equ 22
TOK_FLOAT_LIT    equ 23
TOK_TYPE_COMPLEX equ 24
TOK_COMPLEX_LIT  equ 25
TOK_TYPE_BOOL    equ 26
TOK_TRUE         equ 27
TOK_FALSE        equ 28
TOK_UNKNOWN      equ 29
TOK_TYPE_STR     equ 30
TOK_STR_LIT      equ 31
TOK_PLUS         equ 32
TOK_MINUS        equ 33
TOK_LBRACK       equ 34
TOK_RBRACK       equ 35
TOK_LBRACE       equ 36
TOK_RBRACE       equ 37
TOK_COMMA        equ 38
TOK_USE          equ 39
TOK_MM           equ 40
TOK_GC           equ 41

; Arithmetic operators (were missing from modular system)
TOK_STAR         equ 42
TOK_SLASH        equ 43
TOK_LPAREN       equ 44
TOK_RPAREN       equ 45

; Dict type
TOK_TYPE_DICT    equ 46

; Comparison operators
TOK_LT           equ 47
TOK_GT           equ 48
TOK_NEQ          equ 49
TOK_LTE          equ 50
TOK_GTE          equ 51

; Bitwise operators
TOK_BAND         equ 52
TOK_BOR          equ 53
TOK_BXOR         equ 54
TOK_BNOT         equ 55
TOK_SHL          equ 56
TOK_SHR          equ 57
TOK_MOD          equ 58

; Stage 4/5/7 additions
TOK_ERR          equ 59
TOK_TYPE_SEQ     equ 60
TOK_PUSH         equ 61
TOK_POP          equ 62
TOK_LEN          equ 63

; --- Value Types ---
TYPE_INT         equ 1
TYPE_FLOAT       equ 2
TYPE_BOOL        equ 3
TYPE_COMPLEX     equ 4
TYPE_STR         equ 5
TYPE_SEQ         equ 6
TYPE_DICT        equ 7

; --- Symbol Table ---
VAR_ENTRY_SIZE   equ 64
VAR_MAX          equ 128

; --- Address Layout ---
VAR_STORAGE_BASE equ 4456448    ; 0x440000
LOAD_BASE        equ 4194304    ; 0x400000
HEADERS_SIZE     equ 120

; --- Runtime Blob Sizes ---
RT_PRI_SIZE      equ 512
RT_PRS_SIZE      equ 512
RT_PRB_SIZE      equ 256
RT_PRF_SIZE      equ 512
RT_PRC_SIZE      equ 512
RT_SIP_SIZE      equ 1024
RT_ALC_SIZE      equ 4096
RT_PRQ_SIZE      equ 1024
RT_ERR_SIZE      equ 128
RT_TOTAL_SIZE    equ 8576

; --- Runtime Entry Offsets (from start of binary) ---
RT_PRI_OFFSET    equ 125
RT_PRS_OFFSET    equ 637
RT_PRB_OFFSET    equ 1149
RT_PRF_OFFSET    equ 1405
RT_PRC_OFFSET    equ 1917
RT_SIP_OFFSET    equ 2429
RT_ALC_OFFSET    equ 3453
RT_PRQ_OFFSET    equ 7549

; --- Dict Runtime Entry Offsets ---
; rt_prq_blob starts at RT_PRQ_OFFSET. First byte is a ret (1 byte),
; then rt_dict_new begins. Offsets verified against runtime.asm assembly.
RT_DICT_NEW_OFFSET equ 7550
RT_DICT_SET_OFFSET equ 7577
RT_DICT_GET_OFFSET equ 7626

; --- Runtime stderr error blob ---
RT_ERR_OFFSET    equ 8573

; --- Misc ---
CODE_START       equ 8701
