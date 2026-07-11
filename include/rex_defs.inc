; Rex Compiler Constants and Definitions

; Token Types
TOK_EOF         equ 0
TOK_IDENT       equ 1
TOK_INT_LIT     equ 2
TOK_FLOAT_LIT   equ 3
TOK_STR_LIT     equ 4
TOK_BOOL_LIT    equ 5  ; true, false, neutral
TOK_CHAR_LIT    equ 6

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

; Scopes
SCOPE_GLOBAL    equ 0
SCOPE_LOCAL     equ 1
SCOPE_BLOCK     equ 2

; Symbol Table Entry Layout (64 bytes total)
; Offset  Size  Field
; 0       32    name (null-terminated string)
; 32      1     type (TYPE_*)
; 33      1     scope (SCOPE_*)
; 34      1     is_mutable (0 = no, 1 = yes)
; 35      1     is_init (0 = no, 1 = yes)
; 36      4     offset (offset on stack or memory address)
; 40      24    _pad (unused)
SYM_ENTRY_SIZE  equ 64
SYM_MAX         equ 256

; ELF64 Layout Constants
LOAD_BASE        equ 0x00400000
VAR_STORAGE_BASE equ 0x00440000
VAR_ENTRY_SIZE   equ 64
VAR_ENTRY_SIZE_LOG2 equ 6
VAR_MAX          equ 256
HEADERS_SIZE     equ 120
RT_TOTAL_SIZE    equ 8448
CODE_START       equ 8573

VREG_MAX         equ 65536
SRC_FILE_MAX     equ 65536
OUT_BUF_MAX      equ 131072
VAR_MEM_OFFSET   equ (VAR_STORAGE_BASE - LOAD_BASE) + (VAR_MAX * VAR_ENTRY_SIZE)
