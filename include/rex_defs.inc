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
; 44      20    _pad (unused)
SYM_ENTRY_SIZE  equ 64
SYM_MAX         equ 256

; ELF64 Layout Constants
LOAD_BASE        equ 0x00400000
VAR_STORAGE_BASE equ 0x00440000
VAR_ENTRY_SIZE   equ 64
VAR_ENTRY_SIZE_LOG2 equ 6
VAR_MAX          equ 256
HEADERS_SIZE     equ 125       ; 64 ELF header + 56 program header + 5 JMP

VREG_MAX         equ 65536
SRC_FILE_MAX     equ 65536
OUT_BUF_MAX      equ 131072
VAR_MEM_OFFSET   equ (VAR_STORAGE_BASE - LOAD_BASE) + (VAR_MAX * VAR_ENTRY_SIZE)

; Collection defaults
DICT_INITIAL_CAPACITY equ 16
SEQ_ELEMENT_SIZE equ 8
TYPE_NAME_BUF_SIZE equ 4096
