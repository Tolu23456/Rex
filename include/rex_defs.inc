; rex_defs.inc - Shared constants for Rex compiler modules

; ─── Token types ────────────────────────────────────────────────────────────
TOK_EOF       equ 0
TOK_NEWLINE   equ 1
TOK_INDENT    equ 2
TOK_DEDENT    equ 3
TOK_IDENT     equ 4
TOK_INT_LIT   equ 5
TOK_TYPE_INT  equ 6
TOK_ASSIGN    equ 7
TOK_COLON     equ 8
TOK_OUTPUT    equ 9
TOK_IF        equ 10
TOK_FOR       equ 11
TOK_IN        equ 12
TOK_DOTDOT    equ 13
TOK_EQEQ      equ 14          ; '==' equality comparison operator
TOK_ELSE      equ 15          ; 'else' keyword
TOK_ELIF      equ 16          ; 'elif' keyword

; ─── Variable table ──────────────────────────────────────────────────────────
VAR_ENTRY_SIZE equ 64   ; bytes per entry:  [0..31]=name, [32..39]=value,
                        ;                   [40]=is_const, [41]=is_init, [42..63]=pad
VAR_MAX        equ 16   ; max variables

; ─── Output binary layout constants ─────────────────────────────────────────
;   [0x00..0x3F]  ELF header        (64 bytes)
;   [0x40..0x77]  Program header    (56 bytes)
;   [0x78..0x7F]  Padding           ( 8 bytes)
;                                  ─────────── total = 128 = HEADERS_SIZE
;   [0x80]        JMP +RT_TOTAL     ( 5 bytes)
;   [0x85]        rt_pri blob       (63 bytes)
;   [0xC4]        rt_prs blob       (13 bytes)
;                                  ─────────── total runtime = 81 bytes
;   [0xD1]        Generated code starts here   (CODE_START = 209)

LOAD_BASE     equ 0x400000
HEADERS_SIZE  equ 128
JMP_SIZE      equ 5
RT_PRI_SIZE   equ 63
RT_PRS_SIZE   equ 13
RT_TOTAL_SIZE equ RT_PRI_SIZE + RT_PRS_SIZE   ; 76

RT_PRI_OFFSET equ HEADERS_SIZE + JMP_SIZE               ; = 133
RT_PRS_OFFSET equ RT_PRI_OFFSET + RT_PRI_SIZE           ; = 196
CODE_START    equ RT_PRS_OFFSET + RT_PRS_SIZE           ; = 209
