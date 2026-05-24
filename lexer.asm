; lexer.asm - Tokenization subsystem
;
; Tracks Python-style indentation via indent_stack (resq 32).
; Emits: TOK_INDENT, TOK_DEDENT, TOK_NEWLINE, TOK_IDENT, TOK_INT_LIT,
;        TOK_TYPE_INT, TOK_ASSIGN, TOK_COLON, TOK_OUTPUT, TOK_IF,
;        TOK_FOR, TOK_IN, TOK_DOTDOT, TOK_EOF.
;
; Exports:
;   lexer_init(rdi=src_buf, rsi=src_len)
;   lexer_next()  — advances token; returns tok_type in rax
;   tok_type, tok_int, tok_ident  (globals read by parser)

global lexer_init
global lexer_next
global tok_type
global tok_int
global tok_ident

%include "rex_defs.inc"

; ─── BSS (lexer state) ───────────────────────────────────────────────────────
section .bss
    lex_src:            resq 1          ; pointer to source buffer
    lex_len:            resq 1          ; source length in bytes
    lex_pos:            resq 1          ; current read position
    at_line_start:      resb 1          ; 1 = next call processes indentation

    indent_stack:       resq 32         ; indent level stack (space counts)
    indent_depth:       resq 1          ; index of top entry (0 = level 0)
    pending_dedents:    resq 1          ; dedents queued to emit

    ; Current token — exported
    tok_type:           resb 1
    tok_int:            resq 1
    tok_ident:          resb 64

; ─── TEXT ────────────────────────────────────────────────────────────────────
section .text

; ── lexer_init ───────────────────────────────────────────────────────────────
lexer_init:
    mov  [rel lex_src], rdi
    mov  [rel lex_len], rsi
    mov  qword [rel lex_pos], 0
    mov  byte  [rel at_line_start], 1   ; process indentation from line 1
    mov  qword [rel indent_depth], 0
    mov  qword [rel pending_dedents], 0
    mov  qword [rel indent_stack], 0    ; indent_stack[0] = 0
    ret

; ── lexer_next ───────────────────────────────────────────────────────────────
; Returns token type in rax; also stores it in tok_type.
lexer_next:
.restart:
    ; ── 1. Emit pending DEDENT tokens ────────────────────────────────────────
    cmp  qword [rel pending_dedents], 0
    jle  .no_pending
    dec  qword [rel pending_dedents]
    mov  byte [rel tok_type], TOK_DEDENT
    mov  rax, TOK_DEDENT
    ret
.no_pending:

    ; ── 2. Indentation handling (start of a new logical line) ────────────────
    cmp  byte [rel at_line_start], 0
    je   .skip_ws

    ; Count leading spaces from current lex_pos
    mov  rcx, [rel lex_pos]            ; count_pos
    mov  rdi, [rel lex_src]
    xor  rbx, rbx                      ; space count
.count_spaces:
    cmp  rcx, [rel lex_len]
    jge  .indent_at_eof
    movzx eax, byte [rdi + rcx]
    cmp  al, ' '
    jne  .count_done
    inc  rbx
    inc  rcx
    jmp  .count_spaces

.count_done:
    ; rcx = pos past spaces, rbx = space count
    ; Check for blank / whitespace-only line
    cmp  rcx, [rel lex_len]
    jge  .indent_at_eof
    movzx eax, byte [rdi + rcx]
    cmp  al, 0x0A                       ; newline → blank line
    je   .blank_line

    ; Content line: commit position, clear at_line_start
    mov  [rel lex_pos], rcx
    mov  byte [rel at_line_start], 0

    ; Compare new level with stack top
    mov  rax, [rel indent_depth]
    lea  rcx, [rel indent_stack]
    mov  rdx, [rcx + rax*8]
    cmp  rbx, rdx
    jg   .more_indent
    jl   .less_indent
    ; Equal — no indent/dedent token; fall through to parse
    jmp  .skip_ws

.more_indent:
    inc  qword [rel indent_depth]
    mov  rax, [rel indent_depth]
    lea  rcx, [rel indent_stack]
    mov  [rcx + rax*8], rbx
    mov  byte [rel tok_type], TOK_INDENT
    mov  rax, TOK_INDENT
    ret

.less_indent:
    ; Pop levels until stack_top <= rbx
.dedent_pop:
    cmp  qword [rel indent_depth], 0
    jle  .dedent_emit
    mov  rax, [rel indent_depth]
    lea  rcx, [rel indent_stack]
    mov  rdx, [rcx + rax*8]
    cmp  rdx, rbx
    jle  .dedent_emit
    dec  qword [rel indent_depth]
    inc  qword [rel pending_dedents]
    jmp  .dedent_pop
.dedent_emit:
    ; Emit the first DEDENT; rest sit in pending_dedents
    dec  qword [rel pending_dedents]
    mov  byte [rel tok_type], TOK_DEDENT
    mov  rax, TOK_DEDENT
    ret

.blank_line:
    ; Skip the newline character and restart
    inc  rcx
    mov  [rel lex_pos], rcx
    ; at_line_start stays 1
    jmp  .restart

.indent_at_eof:
    mov  byte [rel at_line_start], 0    ; clear flag — prevents infinite re-entry
    mov  [rel lex_pos], rcx
    jmp  .restart                       ; now falls through skip_ws → emit_eof

    ; ── 3. Skip mid-line whitespace (spaces and tabs) ────────────────────────
.skip_ws:
    mov  rcx, [rel lex_pos]
    mov  rdi, [rel lex_src]
.skip_loop:
    cmp  rcx, [rel lex_len]
    jge  .emit_eof
    movzx eax, byte [rdi + rcx]
    cmp  al, ' '
    je   .skip_next
    cmp  al, 0x09                       ; tab
    je   .skip_next
    jmp  .skip_done
.skip_next:
    inc  rcx
    jmp  .skip_loop
.skip_done:
    mov  [rel lex_pos], rcx

    ; ── 4. Parse the next token ──────────────────────────────────────────────
    cmp  rcx, [rel lex_len]
    jge  .emit_eof

    movzx eax, byte [rdi + rcx]         ; rdi still = lex_src

    cmp  al, 0x0A                       ; newline
    je   .emit_newline

    ; Letter or underscore → identifier / keyword
    cmp  al, '_'
    je   .parse_ident
    cmp  al, 'a'
    jl   .check_upper
    cmp  al, 'z'
    jle  .parse_ident
.check_upper:
    cmp  al, 'A'
    jl   .check_digit
    cmp  al, 'Z'
    jle  .parse_ident

    ; Digit → integer literal
.check_digit:
    cmp  al, '0'
    jl   .check_special
    cmp  al, '9'
    jle  .parse_integer

    ; Special single-character tokens
.check_special:
    cmp  al, '='
    je   .emit_assign
    cmp  al, ':'
    je   .emit_colon
    cmp  al, '.'
    je   .check_dotdot

    ; Unknown character: skip and try again
    inc  qword [rel lex_pos]
    jmp  .restart

    ; ── Token emitters ───────────────────────────────────────────────────────
.emit_eof:
    mov  byte [rel tok_type], TOK_EOF
    xor  eax, eax
    ret

.emit_newline:
    inc  qword [rel lex_pos]
    mov  byte [rel at_line_start], 1
    mov  byte [rel tok_type], TOK_NEWLINE
    mov  rax, TOK_NEWLINE
    ret

.emit_assign:
    inc  qword [rel lex_pos]
    mov  byte [rel tok_type], TOK_ASSIGN
    mov  rax, TOK_ASSIGN
    ret

.emit_colon:
    inc  qword [rel lex_pos]
    mov  byte [rel tok_type], TOK_COLON
    mov  rax, TOK_COLON
    ret

.check_dotdot:
    ; Need two consecutive dots
    mov  rcx, [rel lex_pos]
    inc  rcx
    cmp  rcx, [rel lex_len]
    jge  .skip_char
    movzx eax, byte [rdi + rcx]
    cmp  al, '.'
    jne  .skip_char
    add  qword [rel lex_pos], 2
    mov  byte [rel tok_type], TOK_DOTDOT
    mov  rax, TOK_DOTDOT
    ret

.skip_char:
    inc  qword [rel lex_pos]
    jmp  .restart

    ; ── Parse identifier ─────────────────────────────────────────────────────
.parse_ident:
    mov  rcx, [rel lex_pos]
    mov  rdi, [rel lex_src]
    lea  rsi, [rel tok_ident]
    xor  rbx, rbx                       ; char count
.ident_loop:
    cmp  rbx, 63
    jge  .ident_done
    cmp  rcx, [rel lex_len]
    jge  .ident_done
    movzx eax, byte [rdi + rcx]
    cmp  al, '_'
    je   .ident_char
    cmp  al, 'a'
    jl   .ident_up
    cmp  al, 'z'
    jle  .ident_char
.ident_up:
    cmp  al, 'A'
    jl   .ident_dig
    cmp  al, 'Z'
    jle  .ident_char
.ident_dig:
    cmp  al, '0'
    jl   .ident_done
    cmp  al, '9'
    jle  .ident_char
    jmp  .ident_done
.ident_char:
    mov  [rsi + rbx], al
    inc  rbx
    inc  rcx
    jmp  .ident_loop
.ident_done:
    mov  byte [rsi + rbx], 0            ; null-terminate
    mov  [rel lex_pos], rcx
    call lexer_classify
    movzx rax, byte [rel tok_type]
    ret

    ; ── Parse integer literal ────────────────────────────────────────────────
.parse_integer:
    mov  rcx, [rel lex_pos]
    mov  rdi, [rel lex_src]
    xor  rbx, rbx                       ; accumulator
.int_loop:
    cmp  rcx, [rel lex_len]
    jge  .int_done
    movzx eax, byte [rdi + rcx]
    cmp  al, '0'
    jl   .int_done
    cmp  al, '9'
    jg   .int_done
    sub  al, '0'
    imul rbx, rbx, 10
    movzx rax, al
    add  rbx, rax
    inc  rcx
    jmp  .int_loop
.int_done:
    mov  [rel lex_pos], rcx
    mov  [rel tok_int], rbx
    mov  byte [rel tok_type], TOK_INT_LIT
    mov  rax, TOK_INT_LIT
    ret

; ── lexer_classify ───────────────────────────────────────────────────────────
; Sets tok_type based on tok_ident string.  No external calls.
lexer_classify:
    ; Load first 4 bytes as a little-endian dword for fast keyword matching.
    ; Memory layout: tok_ident[0]=byte0 (lowest), tok_ident[3]=byte3 (highest).
    ; dword value = byte0 | (byte1<<8) | (byte2<<16) | (byte3<<24)
    mov  eax, dword [rel tok_ident]

    ; "int\0"  → 'i'=0x69, 'n'=0x6E, 't'=0x74, '\0'=0x00
    ;           dword = 0x00746E69
    cmp  eax, 0x00746E69
    je   .kw_int

    ; "if\0\0" → 'i'=0x69, 'f'=0x66, '\0', '\0'
    ;           dword = 0x00006669
    cmp  eax, 0x00006669
    je   .kw_if

    ; "for\0"  → 'f'=0x66, 'o'=0x6F, 'r'=0x72, '\0'=0x00
    ;           dword = 0x00726F66
    cmp  eax, 0x00726F66
    je   .kw_for

    ; "in\0\0" → 'i'=0x69, 'n'=0x6E, '\0', '\0'
    ;           dword = 0x00006E69
    cmp  eax, 0x00006E69
    je   .kw_in

    ; "outp"   → 'o'=0x6F, 'u'=0x75, 't'=0x74, 'p'=0x70
    ;           dword = 0x7074756F
    cmp  eax, 0x7074756F
    jne  .kw_ident
    ; Verify remainder: "ut\0"
    mov  ax, word [rel tok_ident + 4]
    cmp  ax, 0x7475                     ; 'u'=0x75, 't'=0x74 → LE word = 0x7475
    jne  .kw_ident
    cmp  byte [rel tok_ident + 6], 0
    jne  .kw_ident
    mov  byte [rel tok_type], TOK_OUTPUT
    ret

.kw_int:
    mov  byte [rel tok_type], TOK_TYPE_INT
    ret
.kw_if:
    mov  byte [rel tok_type], TOK_IF
    ret
.kw_for:
    mov  byte [rel tok_type], TOK_FOR
    ret
.kw_in:
    mov  byte [rel tok_type], TOK_IN
    ret
.kw_ident:
    mov  byte [rel tok_type], TOK_IDENT
    ret
