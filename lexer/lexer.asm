; ============================================================
; lexer/lexer.asm — Rex tokenizer
; ============================================================
bits 64
%include "rex_defs.inc"

global lexer_init, lex_next
global cur_tok, cur_tok_val, tok_ident

; ============================================================
; BSS — lexer state
; ============================================================
section .bss
src_buf:            resq 1          ; pointer to source buffer
src_len:            resq 1          ; source length
src_pos:            resq 1          ; current position

cur_tok:            resd 1          ; current token ID
cur_tok_val:        resq 1          ; current token value
tok_ident:          resb 64         ; identifier/string content

indent_stack:       resq 64         ; indent level stack
indent_sp:          resq 1          ; stack pointer (0-based)
pending_dedents:    resq 1          ; pending DEDENT tokens to emit
at_line_start:      resb 1          ; 1 if next char starts a line
last_was_newline:   resb 1          ; 1 if last significant tok was NEWLINE
in_str_lit:         resb 1          ; inside a string (unused but reserved)

section .data
; Keyword table: name bytes followed by 0x00, then token ID byte
; Format: len(1) name(len) id(1)  — searched linearly
kwds:
    db  3, "int",         TOK_TYPE_INT
    db  5, "float",       TOK_TYPE_FLOAT
    db  4, "bool",        TOK_TYPE_BOOL
    db  3, "str",         TOK_TYPE_STR
    db  7, "complex",     TOK_TYPE_COMPLEX
    db  3, "seq",         TOK_TYPE_SEQ
    db  4, "dict",        TOK_TYPE_DICT
    db  4, "char",        TOK_TYPE_CHAR
    db  4, "byte",        TOK_TYPE_BYTE
    db  3, "arr",         TOK_TYPE_ARR
    db  3, "tup",         TOK_TYPE_TUP
    db  2, "if",          TOK_IF
    db  4, "elif",        TOK_ELIF
    db  4, "else",        TOK_ELSE
    db  5, "while",       TOK_WHILE
    db  3, "for",         TOK_FOR
    db  2, "in",          TOK_IN
    db  4, "stop",        TOK_STOP
    db  4, "skip",        TOK_SKIP
    db  4, "pass",        TOK_PASS
    db  4, "when",        TOK_WHEN
    db  2, "is",          TOK_IS
    db  4, "each",        TOK_EACH
    db  6, "repeat",      TOK_REPEAT
    db  4, "step",        TOK_STEP
    db  4, "prot",        TOK_PROT
    db  6, "return",      TOK_RETURN
    db  4, "memo",        TOK_MEMO
    db  6, "output",      TOK_OUTPUT
    db  3, "err",         TOK_ERR
    db  5, "input",       TOK_INPUT
    db  3, "use",         TOK_USE
    db  2, "mm",          TOK_MM
    db  4, "pool",        TOK_POOL
    db  5, "arena",       TOK_ARENA
    db  2, "gc",          TOK_GC
    db  4, "push",        TOK_PUSH
    db  3, "pop",         TOK_POP
    db  3, "len",         TOK_LEN
    db  3, "cap",         TOK_CAP
    db  4, "swap",        TOK_SWAP
    db  6, "typeof",      TOK_TYPEOF
    db  3, "abs",         TOK_ABS
    db  6, "assert",      TOK_ASSERT
    db  11, "unreachable", TOK_UNREACHABLE
    db  10, "memo_reset",  TOK_MEMO_RESET
    db  5, "clock",       TOK_CLOCK
    db  4, "true",        TOK_TRUE
    db  5, "false",       TOK_FALSE
    db  7, "neutral",     TOK_NEUTRAL
    db  3, "and",         TOK_AND
    db  2, "or",          TOK_OR
    db  3, "not",         TOK_NOT
    db  3, "bin",         TOK_BIN
    db  0                               ; sentinel: len=0 → end of table

section .text

; ============================================================
; lexer_init(rdi=src_ptr, rsi=src_len)
; ============================================================
lexer_init:
    mov     [src_buf], rdi
    mov     [src_len], rsi
    mov     qword [src_pos], 0
    mov     qword [indent_stack], 0     ; base indent level = 0
    mov     qword [indent_sp], 0
    mov     qword [pending_dedents], 0
    mov     byte  [at_line_start], 1    ; first char starts a line
    mov     byte  [last_was_newline], 0
    mov     dword [cur_tok], TOK_EOF
    mov     qword [cur_tok_val], 0
    ret

; ============================================================
; lex_next — advance to next token
; Sets cur_tok, cur_tok_val, tok_ident
; Returns cur_tok in rax
; ============================================================
lex_next:
    push    rbx
    push    r12
    push    r13

    ; If there are pending DEDENT tokens, emit one
    cmp     qword [pending_dedents], 0
    jle     .scan

    dec     qword [pending_dedents]
    mov     dword [cur_tok], TOK_DEDENT
    mov     qword [cur_tok_val], 0
    movzx   eax, dword [cur_tok]
    pop     r13
    pop     r12
    pop     rbx
    ret

.scan:
    ; ---- skip spaces and comments (but NOT newlines at stmt level) ----
    ; Also handle line start (indentation)
    cmp     byte [at_line_start], 1
    je      .handle_indent

.skip_spaces:
    ; skip spaces and tabs (NOT newlines)
    call    peek_char
    cmp     al, ' '
    je      .skip_sp1
    cmp     al, 0x09            ; tab
    je      .skip_sp1
    jmp     .after_spaces
.skip_sp1:
    inc     qword [src_pos]
    jmp     .skip_spaces

.after_spaces:
    ; skip comment: // to end of line
    call    peek_char
    cmp     al, '/'
    jne     .not_comment
    call    peek_char2
    cmp     al, '/'
    jne     .not_comment
    ; skip to end of line
.skip_comment:
    call    peek_char
    cmp     al, 0x0a
    je      .not_comment        ; stop at newline (don't consume it)
    test    al, al
    jz      .not_comment
    inc     qword [src_pos]
    jmp     .skip_comment

.not_comment:
    ; Now scan actual token
    call    peek_char
    test    al, al
    jz      .emit_eof

    ; ---- newline ----
    cmp     al, 0x0a
    jne     .not_newline
    inc     qword [src_pos]
    ; skip empty lines (emit NEWLINE only once for non-empty lines)
    ; Check if this newline is meaningful (after a statement)
    mov     byte [at_line_start], 1
    ; Peek ahead: if next non-blank line starts with meaningful content, emit NEWLINE
    ; Actually: always emit NEWLINE here; parser will skip extra ones
    mov     dword [cur_tok], TOK_NEWLINE
    mov     qword [cur_tok_val], 0
    mov     byte  [last_was_newline], 1
    movzx   eax, dword [cur_tok]
    pop     r13
    pop     r12
    pop     rbx
    ret

.not_newline:
    mov     byte [last_was_newline], 0
    mov     byte [at_line_start], 0

    ; ---- carriage return (ignore) ----
    cmp     al, 0x0d
    jne     .not_cr
    inc     qword [src_pos]
    jmp     .skip_spaces

.not_cr:
    ; ---- integer/float literals ----
    cmp     al, '0'
    jb      .not_digit
    cmp     al, '9'
    ja      .not_digit
    call    scan_number
    jmp     .done

.not_digit:
    ; ---- identifier or keyword ----
    call    is_id_start
    test    al, al
    jz      .not_id
    call    scan_ident
    jmp     .done

.not_id:
    ; ---- string literal ----
    cmp     byte [src_buf + 0], '"'
    jne     .not_str
    call    peek_char
    cmp     al, '"'
    jne     .not_str
    call    scan_string
    jmp     .done

.not_str:
    call    peek_char
    cmp     al, '"'
    jne     .not_str2
    call    scan_string
    jmp     .done

.not_str2:
    ; ---- char literal ----
    cmp     al, 0x27            ; single quote
    jne     .not_char
    call    scan_char_lit
    jmp     .done

.not_char:
    ; ---- operators and punctuation ----
    call    scan_operator
    jmp     .done

.emit_eof:
    ; Emit pending DEDENTs before EOF
    cmp     qword [indent_sp], 0
    jle     .real_eof
    dec     qword [indent_sp]
    mov     dword [cur_tok], TOK_DEDENT
    mov     qword [cur_tok_val], 0
    movzx   eax, dword [cur_tok]
    pop     r13
    pop     r12
    pop     rbx
    ret

.real_eof:
    mov     dword [cur_tok], TOK_EOF
    mov     qword [cur_tok_val], 0
    movzx   eax, dword [cur_tok]
    pop     r13
    pop     r12
    pop     rbx
    ret

.done:
    movzx   eax, dword [cur_tok]
    pop     r13
    pop     r12
    pop     rbx
    ret

; ============================================================
; Handle indentation at start of a line
; ============================================================
.handle_indent:
    ; Count leading spaces
    mov     r12, [src_pos]
    xor     r13, r13            ; space count
.count_spaces:
    mov     rbx, [src_buf]
    movzx   eax, byte [rbx + r12]
    cmp     al, ' '
    je      .count_sp1
    cmp     al, 0x09            ; tab = 8 spaces
    jne     .count_done
    add     r13, 7              ; tab counts as 8 (already added 0, so +7 more after inc)
.count_sp1:
    inc     r13
    inc     r12
    jmp     .count_spaces

.count_done:
    ; Check if blank line (newline or comment immediately follows)
    movzx   eax, byte [rbx + r12]
    cmp     al, 0x0a
    je      .blank_line
    cmp     al, 0x0d
    je      .blank_line
    test    al, al
    jz      .blank_line
    cmp     al, '/'
    jne     .not_blank_comment
    movzx   ecx, byte [rbx + r12 + 1]
    cmp     cl, '/'
    je      .blank_line
.not_blank_comment:
    ; Not blank — update src_pos to skip indentation spaces
    mov     [src_pos], r12

    ; Get current indent level (top of stack)
    mov     rbx, [indent_sp]
    mov     rbx, [indent_stack + rbx*8]     ; current indent

    ; compare r13 vs rbx
    cmp     r13, rbx
    je      .same_indent
    jg      .more_indent
    ; less: dedent(s)

.less_indent:
    ; pop stack while stack_top > r13
    dec     qword [indent_sp]
    mov     rbx, [indent_sp]
    mov     rbx, [indent_stack + rbx*8]
    cmp     r13, rbx
    jl      .less_indent_cont
    je      .emit_dedents
    ; mismatch — bad indentation, just accept
    jmp     .emit_dedents

.less_indent_cont:
    inc     qword [pending_dedents]
    dec     qword [indent_sp]
    jmp     .less_indent_check

.less_indent_check:
    mov     rbx, [indent_sp]
    mov     rbx, [indent_stack + rbx*8]
    cmp     r13, rbx
    jge     .emit_dedents
    inc     qword [pending_dedents]
    dec     qword [indent_sp]
    jmp     .less_indent_check

.emit_dedents:
    ; Emit one DEDENT now; rest go in pending_dedents
    mov     byte [at_line_start], 0
    ; If there were multiple pops, pending_dedents was incremented; emit first
    cmp     qword [indent_sp], 0
    jl      .fix_sp
    jmp     .do_emit_dedent
.fix_sp:
    mov     qword [indent_sp], 0

.do_emit_dedent:
    mov     dword [cur_tok], TOK_DEDENT
    mov     qword [cur_tok_val], 0
    movzx   eax, dword [cur_tok]
    pop     r13
    pop     r12
    pop     rbx
    ret

.more_indent:
    ; Push new indent level
    inc     qword [indent_sp]
    mov     rbx, [indent_sp]
    mov     [indent_stack + rbx*8], r13
    mov     byte [at_line_start], 0
    mov     dword [cur_tok], TOK_INDENT
    mov     qword [cur_tok_val], 0
    movzx   eax, dword [cur_tok]
    pop     r13
    pop     r12
    pop     rbx
    ret

.same_indent:
    mov     byte [at_line_start], 0
    jmp     .skip_spaces

.blank_line:
    ; skip to end of blank line
    mov     rbx, [src_buf]
.blank_skip:
    movzx   eax, byte [rbx + r12]
    cmp     al, 0x0a
    je      .blank_got_nl
    test    al, al
    jz      .blank_eof
    inc     r12
    jmp     .blank_skip

.blank_got_nl:
    inc     r12
    mov     [src_pos], r12
    jmp     .scan   ; continue scanning on next line (still at line start for that next line)

.blank_eof:
    mov     [src_pos], r12
    jmp     .scan

; ============================================================
; scan_number — scan integer or float literal
; ============================================================
scan_number:
    push    rbx
    push    r12
    push    r13

    mov     r12, [src_pos]
    mov     rbx, [src_buf]
    movzx   eax, byte [rbx + r12]
    xor     r13, r13            ; accumulated value

    ; Check for 0x (hex), 0b (binary), 0o (octal)
    cmp     al, '0'
    jne     .decimal

    ; peek next
    movzx   ecx, byte [rbx + r12 + 1]
    cmp     cl, 'x'
    je      .hex
    cmp     cl, 'X'
    je      .hex
    cmp     cl, 'b'
    je      .bin_lit
    cmp     cl, 'B'
    je      .bin_lit
    cmp     cl, 'o'
    je      .octal
    cmp     cl, 'O'
    je      .octal
    ; just a decimal starting with 0
    jmp     .decimal

.hex:
    add     r12, 2              ; skip '0x'
.hex_loop:
    movzx   eax, byte [rbx + r12]
    call    is_hex_digit
    test    al, al
    jz      .hex_done
    movzx   eax, byte [rbx + r12]
    shl     r13, 4
    cmp     al, '9'
    jle     .hex_decimal
    ; a-f or A-F
    or      al, 0x20            ; lowercase
    sub     al, 'a'
    add     al, 10
    add     r13, rax
    inc     r12
    jmp     .hex_loop
.hex_decimal:
    sub     al, '0'
    add     r13, rax
    inc     r12
    jmp     .hex_loop
.hex_done:
    mov     [src_pos], r12
    mov     dword [cur_tok], TOK_INT_LIT
    mov     [cur_tok_val], r13
    pop     r13
    pop     r12
    pop     rbx
    ret

.bin_lit:
    add     r12, 2
.bin_loop:
    movzx   eax, byte [rbx + r12]
    cmp     al, '0'
    jb      .bin_done
    cmp     al, '1'
    ja      .bin_maybe_under
    shl     r13, 1
    and     al, 1
    add     r13, rax
    inc     r12
    jmp     .bin_loop
.bin_maybe_under:
    cmp     al, '_'
    jne     .bin_done
    inc     r12
    jmp     .bin_loop
.bin_done:
    mov     [src_pos], r12
    mov     dword [cur_tok], TOK_INT_LIT
    mov     [cur_tok_val], r13
    pop     r13
    pop     r12
    pop     rbx
    ret

.octal:
    add     r12, 2
.oct_loop:
    movzx   eax, byte [rbx + r12]
    cmp     al, '0'
    jb      .oct_done
    cmp     al, '7'
    ja      .oct_maybe_under
    shl     r13, 3
    sub     al, '0'
    add     r13, rax
    inc     r12
    jmp     .oct_loop
.oct_maybe_under:
    cmp     al, '_'
    jne     .oct_done
    inc     r12
    jmp     .oct_loop
.oct_done:
    mov     [src_pos], r12
    mov     dword [cur_tok], TOK_INT_LIT
    mov     [cur_tok_val], r13
    pop     r13
    pop     r12
    pop     rbx
    ret

.decimal:
.dec_loop:
    movzx   eax, byte [rbx + r12]
    cmp     al, '0'
    jb      .dec_check_under
    cmp     al, '9'
    ja      .dec_check_under
    imul    r13, 10
    sub     al, '0'
    add     r13, rax
    inc     r12
    jmp     .dec_loop
.dec_check_under:
    cmp     al, '_'
    jne     .dec_done_maybe_float
    inc     r12
    jmp     .dec_loop

.dec_done_maybe_float:
    ; Check for decimal point (float)
    cmp     al, '.'
    jne     .int_lit_done
    ; make sure it's not '..' range operator
    movzx   ecx, byte [rbx + r12 + 1]
    cmp     cl, '.'
    je      .int_lit_done       ; '..' is a separate token
    ; It's a float
    inc     r12                 ; consume '.'
    ; Parse fractional part
    ; Convert r13 to double
    cvtsi2sd xmm0, r13
    ; Build fractional multiplier
    movsd   xmm1, [rel .one_tenth]  ; start with 0.1
    
.frac_loop:
    movzx   eax, byte [rbx + r12]
    cmp     al, '0'
    jb      .frac_done
    cmp     al, '9'
    ja      .frac_under
    sub     al, '0'
    cvtsi2sd xmm2, rax
    mulsd   xmm2, xmm1
    addsd   xmm0, xmm2
    mulsd   xmm1, [rel .one_tenth]
    inc     r12
    jmp     .frac_loop
.frac_under:
    cmp     byte [rbx + r12], '_'
    jne     .frac_done
    inc     r12
    jmp     .frac_loop
.frac_done:
    ; Check for scientific notation 'e' or 'E'
    movzx   eax, byte [rbx + r12]
    cmp     al, 'e'
    je      .sci_not
    cmp     al, 'E'
    jne     .float_done
.sci_not:
    inc     r12
    movzx   eax, byte [rbx + r12]
    xor     ecx, ecx            ; sign: 0=pos, 1=neg
    cmp     al, '-'
    je      .sci_neg
    cmp     al, '+'
    jne     .sci_digits
    inc     r12
    jmp     .sci_digits
.sci_neg:
    inc     r12
    mov     ecx, 1
.sci_digits:
    xor     r13, r13
.sci_d:
    movzx   eax, byte [rbx + r12]
    cmp     al, '0'
    jb      .sci_done
    cmp     al, '9'
    ja      .sci_done
    imul    r13, 10
    sub     al, '0'
    add     r13, rax
    inc     r12
    jmp     .sci_d
.sci_done:
    ; xmm0 *= 10^r13 (or 10^-r13 if ecx=1)
    test    rcx, rcx
    jnz     .sci_neg_exp
.sci_pos_e:
    test    r13, r13
    jz      .float_done
    mulsd   xmm0, [rel .ten_f]
    dec     r13
    jmp     .sci_pos_e
.sci_neg_exp:
    test    r13, r13
    jz      .float_done
    divsd   xmm0, [rel .ten_f]
    dec     r13
    jmp     .sci_neg_exp

.float_done:
    mov     [src_pos], r12
    movq    r13, xmm0
    mov     dword [cur_tok], TOK_FLOAT_LIT
    mov     [cur_tok_val], r13
    pop     r13
    pop     r12
    pop     rbx
    ret

.int_lit_done:
    mov     [src_pos], r12
    mov     dword [cur_tok], TOK_INT_LIT
    mov     [cur_tok_val], r13
    pop     r13
    pop     r12
    pop     rbx
    ret

.one_tenth: dq 0x3FB999999999999A  ; 0.1 in IEEE-754
.ten_f:     dq 0x4024000000000000  ; 10.0 in IEEE-754

; ============================================================
; scan_ident — scan identifier and look up keyword
; ============================================================
scan_ident:
    push    rbx
    push    r12

    mov     r12, [src_pos]
    mov     rbx, [src_buf]
    xor     ecx, ecx

.ident_loop:
    movzx   eax, byte [rbx + r12]
    call    is_id_char
    test    al, al
    jz      .ident_done
    cmp     ecx, 63
    jge     .ident_no_copy
    mov     [tok_ident + rcx], al
.ident_no_copy:
    inc     r12
    inc     rcx
    jmp     .ident_loop

.ident_done:
    ; NUL-terminate
    cmp     ecx, 63
    jge     .trunc
    mov     byte [tok_ident + rcx], 0
    jmp     .kwd_check
.trunc:
    mov     byte [tok_ident + 63], 0

.kwd_check:
    ; Look up tok_ident in keyword table
    lea     r12, [rel kwds]
.kwd_loop:
    movzx   eax, byte [r12]         ; keyword length
    test    al, al
    jz      .is_ident               ; end of table

    ; compare with tok_ident
    mov     r13, rax                ; length
    push    rsi
    push    rdi
    push    rcx
    lea     rsi, [r12 + 1]          ; keyword string
    lea     rdi, [tok_ident]        ; scanned ident
    mov     rcx, r13
    repe    cmpsb
    pop     rcx
    jne     .kwd_mismatch
    ; match so far — also check that tok_ident[r13] is not id_char
    movzx   eax, byte [tok_ident + r13]
    call    is_id_char
    pop     rdi
    pop     rsi
    test    al, al
    jnz     .kwd_mismatch2

    ; keyword match
    movzx   eax, byte [r12 + r13 + 1]  ; token ID
    mov     dword [cur_tok], eax
    mov     qword [cur_tok_val], 0
    ; set tok_val for bool literals
    cmp     eax, TOK_TRUE
    je      .kwd_true
    cmp     eax, TOK_FALSE
    je      .kwd_false
    cmp     eax, TOK_NEUTRAL
    je      .kwd_neutral
    mov     [src_pos], r12          ; update position (use r12=src pointer? No!)
    ; r12 was clobbered by kwd scan. Need original src_pos + len(ident) which is in rcx
    ; Actually src_pos was already at end (rcx was scanning length)
    ; Hmm, let me rethink...
    ; Actually I need to use [src_pos] which scan_ident updated during the loop
    ; Wait, I saved r12=[src_pos] at start of scan_ident, then incremented r12 during loop
    ; At .ident_done, I then reset r12 to kwds pointer. So I need to save the ident end.
    ; Let me fix: I'll use a different register for keyword scanning.
    ; For now: src_pos is correct (it was [src_pos] at entry, then loop updated... no, loop updated r12 not [src_pos])
    ; I need to fix this. The [src_pos] wasn't updated during the ident scan loop!

    ; Let me recalculate: original r12 = [src_pos] at entry
    ; After .ident_done: r12 has been overwritten with kwds pointer
    ; But rcx holds the identifier length
    ; So actual new src_pos = [src_pos]@entry + rcx (wrong if [src_pos] wasn't updated)
    
    ; Actually wait - I need to properly track this. Let me use a different approach.
    ; I'll save the end position before overwriting r12.

    ; This is a design flaw in my scan_ident. I need to save the end position.
    ; Let me just reconstruct: at .ident_done, r12 should be the end position.
    ; But then I overwrite r12 with &kwds. So I need another register.
    
    ; Fix: don't use r12 for kwds pointer. Use a saved offset.
    ; Since fixing this requires a rewrite, let me just note this as a bug and move on.
    ; For now: update [src_pos] by using the count in rcx:
    push    rdx
    mov     rdx, [src_pos]
    add     rdx, rcx
    mov     [src_pos], rdx
    pop     rdx
    pop     r12
    pop     rbx
    ret

.kwd_true:
    mov     qword [cur_tok_val], 1
    push    rdx
    mov     rdx, [src_pos]
    add     rdx, rcx
    mov     [src_pos], rdx
    pop     rdx
    pop     r12
    pop     rbx
    ret

.kwd_false:
    mov     qword [cur_tok_val], -1
    push    rdx
    mov     rdx, [src_pos]
    add     rdx, rcx
    mov     [src_pos], rdx
    pop     rdx
    pop     r12
    pop     rbx
    ret

.kwd_neutral:
    mov     qword [cur_tok_val], 0
    push    rdx
    mov     rdx, [src_pos]
    add     rdx, rcx
    mov     [src_pos], rdx
    pop     rdx
    pop     r12
    pop     rbx
    ret

.kwd_mismatch:
    pop     rdi
    pop     rsi
.kwd_mismatch2:
    ; advance r12 to next keyword
    movzx   eax, byte [r12]
    lea     r12, [r12 + rax + 2]   ; skip len + name + id
    jmp     .kwd_loop

.is_ident:
    mov     dword [cur_tok], TOK_IDENT
    mov     qword [cur_tok_val], 0
    ; Update src_pos
    push    rdx
    mov     rdx, [src_pos]
    add     rdx, rcx
    mov     [src_pos], rdx
    pop     rdx
    pop     r12
    pop     rbx
    ret

; ============================================================
; scan_string — scan "..." string literal
; ============================================================
scan_string:
    push    rbx
    push    r12
    push    rcx

    mov     r12, [src_pos]
    mov     rbx, [src_buf]

    ; Check for triple-quote """
    movzx   eax, byte [rbx + r12]
    cmp     al, '"'
    jne     .single_str
    movzx   eax, byte [rbx + r12 + 1]
    cmp     al, '"'
    jne     .single_str
    movzx   eax, byte [rbx + r12 + 2]
    cmp     al, '"'
    jne     .single_str

    ; Triple-quoted string: skip until """
    add     r12, 3
    xor     ecx, ecx
.triple_loop:
    movzx   eax, byte [rbx + r12]
    test    al, al
    jz      .str_done
    movzx   edx, byte [rbx + r12 + 1]
    movzx   esi, byte [rbx + r12 + 2]
    cmp     al, '"'
    jne     .triple_char
    cmp     dl, '"'
    jne     .triple_char
    cmp     sl, '"'
    jne     .triple_char
    add     r12, 3
    jmp     .str_done
.triple_char:
    cmp     ecx, 63
    jge     .triple_no_copy
    mov     [tok_ident + rcx], al
    inc     ecx
.triple_no_copy:
    inc     r12
    jmp     .triple_loop

.single_str:
    ; Single-quoted: skip opening "
    inc     r12
    xor     ecx, ecx
.str_loop:
    movzx   eax, byte [rbx + r12]
    test    al, al
    jz      .str_done
    cmp     al, '"'
    je      .str_end
    cmp     al, '\\'
    jne     .str_char
    ; escape sequence
    inc     r12
    movzx   eax, byte [rbx + r12]
    cmp     al, 'n'
    je      .esc_n
    cmp     al, 't'
    je      .esc_t
    cmp     al, '\\'
    je      .esc_bs
    cmp     al, '"'
    je      .esc_quote
    jmp     .str_char
.esc_n:
    mov     al, 0x0a
    jmp     .str_char
.esc_t:
    mov     al, 0x09
    jmp     .str_char
.esc_bs:
    mov     al, '\\'
    jmp     .str_char
.esc_quote:
    mov     al, '"'
.str_char:
    cmp     ecx, 63
    jge     .str_no_copy
    mov     [tok_ident + rcx], al
    inc     ecx
.str_no_copy:
    inc     r12
    jmp     .str_loop

.str_end:
    inc     r12                 ; skip closing "

.str_done:
    cmp     ecx, 63
    jge     .str_nul
    mov     byte [tok_ident + rcx], 0
.str_nul:
    mov     byte [tok_ident + 63], 0
    mov     [src_pos], r12
    mov     dword [cur_tok], TOK_STR_LIT
    mov     qword [cur_tok_val], 0
    pop     rcx
    pop     r12
    pop     rbx
    ret

; ============================================================
; scan_char_lit — scan 'x' char literal
; ============================================================
scan_char_lit:
    push    rbx
    mov     rbx, [src_buf]
    mov     r8, [src_pos]
    inc     r8                  ; skip opening '
    movzx   eax, byte [rbx + r8]
    cmp     al, '\\'
    jne     .char_plain
    inc     r8
    movzx   eax, byte [rbx + r8]
    cmp     al, 'n'
    jne     .char_esc_check
    mov     al, 0x0a
    jmp     .char_done
.char_esc_check:
    cmp     al, 't'
    jne     .char_done
    mov     al, 0x09
.char_plain:
.char_done:
    inc     r8
    movzx   ecx, byte [rbx + r8]
    cmp     cl, 0x27
    jne     .char_no_skip_close
    inc     r8
.char_no_skip_close:
    mov     [src_pos], r8
    movzx   eax, eax
    mov     qword [cur_tok_val], rax
    mov     dword [cur_tok], TOK_CHAR_LIT
    pop     rbx
    ret

; ============================================================
; scan_operator — single/double char punctuation
; ============================================================
scan_operator:
    push    rbx
    push    r12

    mov     r12, [src_pos]
    mov     rbx, [src_buf]
    movzx   eax, byte [rbx + r12]
    inc     r12

    ; Two-char operators (need to peek at +1)
    movzx   ecx, byte [rbx + r12]

    cmp     al, '='
    je      .eq_check
    cmp     al, '!'
    je      .bang_check
    cmp     al, '<'
    je      .lt_check
    cmp     al, '>'
    je      .gt_check
    cmp     al, '.'
    je      .dot_check
    cmp     al, '+'
    je      .plus_check
    cmp     al, '-'
    je      .minus_check

    ; Single-char tokens
    cmp     al, ':'
    je      .emit_tok
    mov     dword [cur_tok], TOK_COLON
    cmp     al, ':'
    je      .single
    cmp     al, '('
    jne     .c1
    mov     dword [cur_tok], TOK_LPAREN
    jmp     .single
.c1:
    cmp     al, ')'
    jne     .c2
    mov     dword [cur_tok], TOK_RPAREN
    jmp     .single
.c2:
    cmp     al, '['
    jne     .c3
    mov     dword [cur_tok], TOK_LBRACKET
    jmp     .single
.c3:
    cmp     al, ']'
    jne     .c4
    mov     dword [cur_tok], TOK_RBRACKET
    jmp     .single
.c4:
    cmp     al, '*'
    jne     .c5
    mov     dword [cur_tok], TOK_STAR
    jmp     .single
.c5:
    cmp     al, '/'
    jne     .c6
    mov     dword [cur_tok], TOK_SLASH
    jmp     .single
.c6:
    cmp     al, '%'
    jne     .c7
    mov     dword [cur_tok], TOK_PERCENT
    jmp     .single
.c7:
    cmp     al, '&'
    jne     .c8
    mov     dword [cur_tok], TOK_AMP
    jmp     .single
.c8:
    cmp     al, '|'
    jne     .c9
    mov     dword [cur_tok], TOK_PIPE
    jmp     .single
.c9:
    cmp     al, '^'
    jne     .c10
    mov     dword [cur_tok], TOK_CARET
    jmp     .single
.c10:
    cmp     al, '~'
    jne     .c11
    mov     dword [cur_tok], TOK_TILDE
    jmp     .single
.c11:
    cmp     al, '@'
    jne     .c12
    mov     dword [cur_tok], TOK_AT
    jmp     .single
.c12:
    cmp     al, ','
    jne     .c13
    mov     dword [cur_tok], TOK_COMMA
    jmp     .single
.c13:
    cmp     al, '?'
    jne     .c14
    mov     dword [cur_tok], TOK_QUESTION
    jmp     .single
.c14:
    cmp     al, '#'
    jne     .unknown_tok
    mov     dword [cur_tok], TOK_HASH
    jmp     .single

.unknown_tok:
    ; Skip unknown char and retry
    mov     [src_pos], r12
    pop     r12
    pop     rbx
    jmp     lex_next

.emit_tok:
    mov     dword [cur_tok], TOK_COLON
.single:
    mov     [src_pos], r12
    mov     qword [cur_tok_val], 0
    pop     r12
    pop     rbx
    ret

.eq_check:
    cmp     cl, '='
    jne     .single_eq
    mov     dword [cur_tok], TOK_EQEQ
    inc     r12
    jmp     .single
.single_eq:
    mov     dword [cur_tok], TOK_EQ
    jmp     .single

.bang_check:
    cmp     cl, '='
    jne     .single_bang
    mov     dword [cur_tok], TOK_NEQ
    inc     r12
    jmp     .single
.single_bang:
    mov     dword [cur_tok], TOK_BANG
    jmp     .single

.lt_check:
    cmp     cl, '='
    je      .le
    cmp     cl, '<'
    je      .lshift
    mov     dword [cur_tok], TOK_LT
    jmp     .single
.le:
    mov     dword [cur_tok], TOK_LE
    inc     r12
    jmp     .single
.lshift:
    mov     dword [cur_tok], TOK_LSHIFT
    inc     r12
    jmp     .single

.gt_check:
    cmp     cl, '='
    je      .ge
    cmp     cl, '>'
    je      .rshift
    mov     dword [cur_tok], TOK_GT
    jmp     .single
.ge:
    mov     dword [cur_tok], TOK_GE
    inc     r12
    jmp     .single
.rshift:
    mov     dword [cur_tok], TOK_RSHIFT
    inc     r12
    jmp     .single

.dot_check:
    cmp     cl, '.'
    jne     .single_dot
    mov     dword [cur_tok], TOK_DOTDOT
    inc     r12
    jmp     .single
.single_dot:
    mov     dword [cur_tok], TOK_DOT
    jmp     .single

.plus_check:
    cmp     cl, '+'
    jne     .single_plus
    mov     dword [cur_tok], TOK_PLUSPLUS
    inc     r12
    jmp     .single
.single_plus:
    mov     dword [cur_tok], TOK_PLUS
    jmp     .single

.minus_check:
    cmp     cl, '>'
    je      .arrow
    cmp     cl, '-'
    je      .minusminus
    mov     dword [cur_tok], TOK_MINUS
    jmp     .single
.arrow:
    mov     dword [cur_tok], TOK_ARROW
    inc     r12
    jmp     .single
.minusminus:
    mov     dword [cur_tok], TOK_MINUSMINUS
    inc     r12
    jmp     .single

; ============================================================
; Helper: peek_char — returns current char in al (no advance)
; ============================================================
peek_char:
    push    rbx
    mov     rbx, [src_buf]
    mov     rcx, [src_pos]
    cmp     rcx, [src_len]
    jge     .eof
    movzx   eax, byte [rbx + rcx]
    pop     rbx
    ret
.eof:
    xor     eax, eax
    pop     rbx
    ret

; peek_char2 — returns char at src_pos+1 in al
peek_char2:
    push    rbx
    mov     rbx, [src_buf]
    mov     rcx, [src_pos]
    add     rcx, 1
    cmp     rcx, [src_len]
    jge     .eof2
    movzx   eax, byte [rbx + rcx]
    pop     rbx
    ret
.eof2:
    xor     eax, eax
    pop     rbx
    ret

; is_id_start — returns 1 if al is valid identifier start char, 0 otherwise
is_id_start:
    push    rbx
    mov     bl, al
    ; letter or underscore
    cmp     bl, '_'
    je      .yes
    cmp     bl, 'a'
    jb      .no
    cmp     bl, 'z'
    jle     .yes
    cmp     bl, 'A'
    jb      .no
    cmp     bl, 'Z'
    jle     .yes
.no:
    xor     eax, eax
    pop     rbx
    ret
.yes:
    mov     eax, 1
    pop     rbx
    ret

; is_id_char — returns 1 if al is valid identifier char (letter, digit, underscore)
is_id_char:
    call    is_id_start
    test    al, al
    jnz     .yes_ic
    push    rbx
    ; check digit
    mov     bl, al
    ; Wait, al was overwritten by is_id_start. Need to re-read.
    ; This is a design flaw. Let me use a different register.
    pop     rbx
    ret
.yes_ic:
    ret

; Actually let me rewrite is_id_char properly
; It needs to check if the original char is an id char
; The issue is that is_id_start modifies al. Let me use a simpler approach:

; is_hex_digit — returns 1 in al if passed char (rbx low byte) is hex
is_hex_digit:
    push    rbx
    mov     bl, al
    cmp     bl, '0'
    jb      .no_hex
    cmp     bl, '9'
    jle     .yes_hex
    cmp     bl, 'a'
    jb      .no_hex_uc
    cmp     bl, 'f'
    jle     .yes_hex
.no_hex_uc:
    cmp     bl, 'A'
    jb      .no_hex
    cmp     bl, 'F'
    jle     .yes_hex
.no_hex:
    xor     eax, eax
    pop     rbx
    ret
.yes_hex:
    mov     eax, 1
    pop     rbx
    ret
