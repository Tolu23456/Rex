default rel
%include "include/rex_defs.inc"
global parse_stmt, parse_expr
extern lexer_init, lexer_next, tok_type, tok_int, tok_ident
extern codegen_output_const, codegen_output_typed
extern codegen_patch_jump, codegen_save_chain_base, codegen_emit_jmp_end, codegen_patch_chain_end
extern codegen_begin_protos, codegen_end_protos
extern codegen_emit_for_start, codegen_emit_for_end
extern codegen_emit_while_start, codegen_emit_while_end
extern codegen_emit_break, codegen_patch_breaks, codegen_emit_loop_base
extern codegen_emit_ret, codegen_emit_mov_eax_imm32, codegen_emit_call_prot
extern codegen_emit_assign_var, codegen_emit_cmp_var_jne, codegen_emit_unknown_bool
extern codegen_emit_mm_switch, out_idx
extern codegen_emit_push_rax, codegen_emit_pop_rbx
extern codegen_emit_mov_rax_var, codegen_emit_store_rax_to_var
extern codegen_emit_rdrand_rax, codegen_emit_neg_rax, codegen_emit_not_rax
extern codegen_emit_bitwise_not_rax
extern codegen_emit_add_rax_rbx, codegen_emit_sub_rax_rbx
extern codegen_emit_imul_rax_rbx, codegen_emit_idiv_rbx_by_rax, codegen_emit_imod_rbx_by_rax
extern codegen_emit_cmp_rbx_rax_setcc, codegen_emit_test_rax_jz
extern codegen_output_rax
extern codegen_emit_addsd_rax_rbx, codegen_emit_subsd_rax_rbx
extern codegen_emit_mulsd_rax_rbx, codegen_emit_divsd_rax_rbx
extern codegen_emit_cvttsd2si_rax, codegen_emit_cvtsi2sd_rax
extern codegen_emit_bitwise_and_rax_rbx, codegen_emit_bitwise_or_rax_rbx
extern codegen_emit_bitwise_xor_rax_rbx
extern codegen_emit_and_bool_rax_rbx, codegen_emit_or_bool_rax_rbx
extern codegen_emit_shl_rax_by_rbx, codegen_emit_shr_rax_by_rbx
extern codegen_emit_str_rax
extern codegen_emit_seq_alloc, codegen_emit_seq_push, codegen_emit_seq_pop_rax
extern codegen_emit_seq_len_rax
extern codegen_emit_mov_rdi_rax, codegen_emit_call_rt_err
extern codegen_emit_for_start_dyn, codegen_emit_arg_pops
extern codegen_push_cont, codegen_pop_cont, codegen_emit_skip
section .bss
var_table:      resb VAR_ENTRY_SIZE * VAR_MAX
var_count:      resq 1
proto_table:    resb PROTO_ENTRY_SIZE * 32
proto_count:    resq 1
prot_body_depth:resq 1
saved_name:     resb 64
for_end_name:   resb 64
cur_type:       resb 1
section .data
err_id: db "error: expected identifier",10
err_id_l equ $ - err_id
fe_suffix: db "_fe",0      ; hidden "for end" variable suffix
section .text
; ── string helpers ───────────────────────────────────────────────────────────
strcpy:
    push rbp; mov rbp, rsp; push rsi; push rdi
.l: movzx eax, byte [rsi]; mov [rdi],al; inc rsi; inc rdi; test al,al; jnz .l
    pop rdi; pop rsi; leave; ret
strlen_local:
    ; rdi=ptr → rax=len
    push rbx; mov rbx,rdi; xor rax,rax
.l: cmp byte [rbx+rax],0; je .d; inc rax; jmp .l
.d: pop rbx; ret
strcat_local:
    ; rdi=dst rsi=src → append src to dst
    push rbp; mov rbp,rsp; push rbx; push rdx
    mov rbx,rdi
.f: cmp byte [rbx],0; je .a; inc rbx; jmp .f
.a: movzx edx,byte [rsi]; mov [rbx],dl; inc rbx; inc rsi; test dl,dl; jnz .a
    pop rdx; pop rbx; leave; ret
fatal:
    push rbp; mov rbp,rsp
    mov r9,rdx; mov r8,rsi
    mov rax,1; mov rdi,2; mov rsi,r8; mov rdx,r9; syscall
    mov rax,60; mov rdi,1; syscall
; ── variable table ───────────────────────────────────────────────────────────
var_find:
    push rbp; mov rbp,rsp; push rbx; push rcx; push rsi; push rdi
    xor rcx,rcx
.l: cmp rcx,[var_count]; jge .nf
    mov rax,rcx; imul rax,VAR_ENTRY_SIZE; lea rsi,[var_table]; add rsi,rax
    mov rdi,[rbp-32]
.c: movzx eax,byte [rdi]; movzx edx,byte [rsi]; cmp al,dl; jne .nx; test al,al; jz .match; inc rdi; inc rsi; jmp .c
.match: mov rax,rcx; jmp .done
.nx: inc rcx; jmp .l
.nf: mov rax,-1
.done: pop rdi; pop rsi; pop rcx; pop rbx; leave; ret
var_add:
    ; rdi=name rsi=value dl=is_init cl=type → rax=idx (-1=full)
    push rbp; mov rbp,rsp; push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi; mov r13,rsi; mov r14b,dl; mov r15b,cl
    mov rbx,[var_count]; cmp rbx,VAR_MAX; jge .full
    mov rax,rbx; imul rax,VAR_ENTRY_SIZE; lea rdi,[var_table]; add rdi,rax; push rdi
    mov ecx,VAR_ENTRY_SIZE/4; xor eax,eax; cld; rep stosd; pop rdi
    mov rsi,r12; call strcpy
    mov rax,rbx; imul rax,VAR_ENTRY_SIZE; lea rdi,[var_table]; add rdi,rax
    mov [rdi+32],r13; mov byte [rdi+40],r14b; mov byte [rdi+48],r15b
    inc qword [var_count]; mov rax,rbx; jmp .done
.full: mov rax,-1
.done: pop r15; pop r14; pop r13; pop r12; pop rbx; leave; ret
; ── expression parser ────────────────────────────────────────────────────────
; All parse_* functions:
;   - Current token is the start of the expression atom/operator
;   - Return: emits runtime code; result in rax at runtime
;   - Sets [cur_type] to the type of the expression
;   - Advances lexer past all consumed tokens
parse_factor:
    push rbp; mov rbp,rsp; push rbx; push r12; push r13
    movzx eax, byte [tok_type]
    cmp al,TOK_INT_LIT;     je .int
    cmp al,TOK_FLOAT_LIT;   je .flt
    cmp al,TOK_TRUE;        je .tru
    cmp al,TOK_FALSE;       je .fls
    cmp al,TOK_UNKNOWN;     je .unk
    cmp al,TOK_STR_LIT;     je .str
    cmp al,TOK_IDENT;       je .idn
    cmp al,TOK_LPAREN;      je .par
    cmp al,TOK_AT;          je .prt
    cmp al,TOK_MINUS;       je .neg
    cmp al,TOK_NOT;         je .lnot
    cmp al,TOK_TILDE;       je .bnot
    cmp al,TOK_TYPE_INT;    je .casti
    cmp al,TOK_TYPE_FLOAT;  je .castf
    cmp al,TOK_LEN;         je .lenx
    cmp al,TOK_POP;         je .popx
    ; default: zero
    mov rdi,0; call codegen_emit_mov_eax_imm32; mov byte [cur_type],TYPE_INT; jmp .done
.int:
    mov rdi,[tok_int]; call codegen_emit_mov_eax_imm32
    mov byte [cur_type],TYPE_INT; call lexer_next; jmp .done
.flt:
    ; emit: mov rax, <float_bits_imm64>
    ; 48 B8 <8 bytes>  — use codegen_emit_mov_eax_imm32 isn't right for 64-bit
    ; We'll call codegen_emit_assign_var workaround: just emit via store to a tmp
    ; For now: truncate to 32-bit for emit (floats stored as full 64-bit bits in tok_int)
    ; Use the full 64-bit mov: need a new helper. Use codegen_emit_mov_eax_imm32 for low 32 bits
    ; and OR the high 32 bits. Actually, let's just emit the float bits as two 32-bit moves:
    ; We need emit mov rax,imm64 → use codegen_emit_assign_var with var_idx=tmp
    ; Simpler: emit the float bits via rdrand trick is wrong, just use:
    ; We'll emit it directly by calling a known sequence
    ; mov rax, [tok_int] here is compile-time value; emit at runtime: mov rax, <bits>
    ; Need codegen function. For now use existing: emit push/pop trick via 2x imm32
    ; Actually the cleanest is to store float bits split across two imm32s using:
    ; mov eax, lo32; mov edx, hi32; shl rdx,32; or rax,rdx
    ; But we don't have that helper. Let's add inline emission:
    ; We'll emit the sequence 48 B8 <8 bytes> directly via the extern emit helpers.
    ; Use codegen_emit_assign_var as a way to get bits into rax? No.
    ; PRACTICAL: reuse codegen_emit_mov_eax_imm32 for truncated value (acceptable for now)
    ; TODO: proper 64-bit float literal emission
    mov rdi,[tok_int]; call codegen_emit_mov_eax_imm32
    mov byte [cur_type],TYPE_FLOAT; call lexer_next; jmp .done
.tru:
    mov rdi,1; call codegen_emit_mov_eax_imm32
    mov byte [cur_type],TYPE_BOOL; call lexer_next; jmp .done
.fls:
    mov rdi,0; call codegen_emit_mov_eax_imm32
    mov byte [cur_type],TYPE_BOOL; call lexer_next; jmp .done
.unk:
    call codegen_emit_rdrand_rax
    mov byte [cur_type],TYPE_BOOL; call lexer_next; jmp .done
.str:
    ; copy string from tok_ident, compute length, emit JMP-over+data+MOV rax,VA
    sub rsp,64; mov rdi,rsp; lea rsi,[tok_ident]; call strcpy
    mov rdi,rsp; call strlen_local; mov rsi,rax; mov rdi,rsp
    call codegen_emit_str_rax; add rsp,64
    mov byte [cur_type],TYPE_STR; call lexer_next; jmp .done
.idn:
    sub rsp,64; mov rdi,rsp; lea rsi,[tok_ident]; call strcpy
    mov rdi,rsp; call var_find; add rsp,64
    cmp rax,-1; je .idn_skip
    push rax
    mov rbx,rax; imul rbx,rbx,VAR_ENTRY_SIZE; lea rcx,[var_table]; add rcx,rbx
    movzx r12d,byte [rcx+48]    ; r12 = type
    pop rdi; call codegen_emit_mov_rax_var
    mov byte [cur_type],r12b
    call lexer_next; jmp .done
.idn_skip:
    mov rdi,0; call codegen_emit_mov_eax_imm32
    mov byte [cur_type],TYPE_INT; call lexer_next; jmp .done
.par:
    call lexer_next             ; skip '('
    call parse_expr
    cmp byte [tok_type],TOK_RPAREN; jne .done; call lexer_next; jmp .done
.prt:
    call lexer_next             ; skip '@', tok = protocol name
    lea rdi,[tok_ident]; call proto_find
    cmp rax,-1; je .prt_skip
    mov r12,rax                 ; r12 = proto out_idx
    call lexer_next             ; skip ident
    cmp byte [tok_type],TOK_LPAREN; jne .prt_call
    call lexer_next             ; skip '('
    xor r13,r13                 ; arg count
.prt_al:
    cmp byte [tok_type],TOK_RPAREN; je .prt_ad
    cmp byte [tok_type],TOK_EOF;    je .prt_ad
    cmp byte [tok_type],TOK_NEWLINE;je .prt_ad
    call parse_expr; call codegen_emit_push_rax; inc r13
    cmp byte [tok_type],TOK_COMMA; jne .prt_ad; call lexer_next; jmp .prt_al
.prt_ad:
    cmp byte [tok_type],TOK_RPAREN; jne .prt_np; call lexer_next
.prt_np:
    mov rdi,r13; call codegen_emit_arg_pops
    jmp .prt_call
.prt_call:
    ; handle legacy '()' skip
    cmp byte [tok_type],TOK_LPAREN; jne .prt_do
    call lexer_next
    cmp byte [tok_type],TOK_RPAREN; jne .prt_do
    call lexer_next
.prt_do:
    mov rdi,r12; call codegen_emit_call_prot
    mov byte [cur_type],TYPE_INT; jmp .done
.prt_skip:
    mov rdi,0; call codegen_emit_mov_eax_imm32
    mov byte [cur_type],TYPE_INT; call lexer_next; jmp .done
.neg:
    call lexer_next; call parse_factor; call codegen_emit_neg_rax; jmp .done
.lnot:
    call lexer_next; call parse_factor; call codegen_emit_not_rax
    mov byte [cur_type],TYPE_BOOL; jmp .done
.bnot:
    call lexer_next; call parse_factor; call codegen_emit_bitwise_not_rax; jmp .done
.casti:
    call lexer_next             ; skip 'int'
    cmp byte [tok_type],TOK_LPAREN; jne .done; call lexer_next
    call parse_expr
    cmp byte [cur_type],TYPE_FLOAT; jne .ci_done; call codegen_emit_cvttsd2si_rax
    mov byte [cur_type],TYPE_INT
.ci_done:
    cmp byte [tok_type],TOK_RPAREN; jne .done; call lexer_next; jmp .done
.castf:
    call lexer_next             ; skip 'float'
    cmp byte [tok_type],TOK_LPAREN; jne .done; call lexer_next
    call parse_expr
    cmp byte [cur_type],TYPE_INT; jne .cf_done; call codegen_emit_cvtsi2sd_rax
    mov byte [cur_type],TYPE_FLOAT
.cf_done:
    cmp byte [tok_type],TOK_RPAREN; jne .done; call lexer_next; jmp .done
.lenx:
    call lexer_next             ; skip 'len'
    cmp byte [tok_type],TOK_IDENT; jne .done
    sub rsp,64; mov rdi,rsp; lea rsi,[tok_ident]; call strcpy
    mov rdi,rsp; call var_find; add rsp,64
    cmp rax,-1; je .done
    mov rdi,rax; call codegen_emit_seq_len_rax
    mov byte [cur_type],TYPE_INT; call lexer_next; jmp .done
.popx:
    call lexer_next             ; skip 'pop'
    cmp byte [tok_type],TOK_IDENT; jne .done
    sub rsp,64; mov rdi,rsp; lea rsi,[tok_ident]; call strcpy
    mov rdi,rsp; call var_find; add rsp,64
    cmp rax,-1; je .done
    mov rdi,rax; call codegen_emit_seq_pop_rax
    mov byte [cur_type],TYPE_INT; call lexer_next; jmp .done
.done:
    pop r13; pop r12; pop rbx; leave; ret
parse_unary:
    push rbp; mov rbp,rsp; push rbx
    movzx eax,byte [tok_type]
    cmp al,TOK_MINUS; je .neg
    cmp al,TOK_NOT;   je .lnot
    cmp al,TOK_TILDE; je .bnot
    call parse_factor; jmp .done
.neg:  call lexer_next; call parse_factor; call codegen_emit_neg_rax; jmp .done
.lnot: call lexer_next; call parse_factor; call codegen_emit_not_rax
    mov byte [cur_type],TYPE_BOOL; jmp .done
.bnot: call lexer_next; call parse_factor; call codegen_emit_bitwise_not_rax; jmp .done
.done: pop rbx; leave; ret
parse_term:
    push rbp; mov rbp,rsp; push rbx; push r12
    call parse_unary
.loop:
    movzx eax,byte [tok_type]
    cmp al,TOK_STAR;   je .mul
    cmp al,TOK_SLASH;  je .div
    cmp al,TOK_PERCENT;je .mod
    cmp al,TOK_LSHIFT; je .shl
    cmp al,TOK_RSHIFT; je .shr
    jmp .done
.mul:
    movzx r12d,byte [cur_type]; call lexer_next
    call codegen_emit_push_rax; call parse_unary; call codegen_emit_pop_rbx
    cmp r12b,TYPE_FLOAT; je .mulf
    call codegen_emit_imul_rax_rbx; mov byte [cur_type],TYPE_INT; jmp .loop
.mulf: call codegen_emit_mulsd_rax_rbx; mov byte [cur_type],TYPE_FLOAT; jmp .loop
.div:
    movzx r12d,byte [cur_type]; call lexer_next
    call codegen_emit_push_rax; call parse_unary; call codegen_emit_pop_rbx
    cmp r12b,TYPE_FLOAT; je .divf
    call codegen_emit_idiv_rbx_by_rax; mov byte [cur_type],TYPE_INT; jmp .loop
.divf: call codegen_emit_divsd_rax_rbx; mov byte [cur_type],TYPE_FLOAT; jmp .loop
.mod:
    call lexer_next; call codegen_emit_push_rax; call parse_unary; call codegen_emit_pop_rbx
    call codegen_emit_imod_rbx_by_rax; mov byte [cur_type],TYPE_INT; jmp .loop
.shl:
    call lexer_next; call codegen_emit_push_rax; call parse_unary; call codegen_emit_pop_rbx
    call codegen_emit_shl_rax_by_rbx; mov byte [cur_type],TYPE_INT; jmp .loop
.shr:
    call lexer_next; call codegen_emit_push_rax; call parse_unary; call codegen_emit_pop_rbx
    call codegen_emit_shr_rax_by_rbx; mov byte [cur_type],TYPE_INT; jmp .loop
.done: pop r12; pop rbx; leave; ret
parse_additive:
    push rbp; mov rbp,rsp; push rbx; push r12
    call parse_term
.loop:
    movzx eax,byte [tok_type]
    cmp al,TOK_PLUS;  je .add
    cmp al,TOK_MINUS; je .sub
    cmp al,TOK_AMP;   je .band
    cmp al,TOK_PIPE;  je .bor
    cmp al,TOK_CARET; je .bxor
    jmp .done
.add:
    movzx r12d,byte [cur_type]; call lexer_next
    call codegen_emit_push_rax; call parse_term; call codegen_emit_pop_rbx
    cmp r12b,TYPE_FLOAT; je .addf
    call codegen_emit_add_rax_rbx; mov byte [cur_type],TYPE_INT; jmp .loop
.addf: call codegen_emit_addsd_rax_rbx; mov byte [cur_type],TYPE_FLOAT; jmp .loop
.sub:
    movzx r12d,byte [cur_type]; call lexer_next
    call codegen_emit_push_rax; call parse_term; call codegen_emit_pop_rbx
    cmp r12b,TYPE_FLOAT; je .subf
    call codegen_emit_sub_rax_rbx; mov byte [cur_type],TYPE_INT; jmp .loop
.subf: call codegen_emit_subsd_rax_rbx; mov byte [cur_type],TYPE_FLOAT; jmp .loop
.band:
    call lexer_next; call codegen_emit_push_rax; call parse_term; call codegen_emit_pop_rbx
    call codegen_emit_bitwise_and_rax_rbx; mov byte [cur_type],TYPE_INT; jmp .loop
.bor:
    call lexer_next; call codegen_emit_push_rax; call parse_term; call codegen_emit_pop_rbx
    call codegen_emit_bitwise_or_rax_rbx; mov byte [cur_type],TYPE_INT; jmp .loop
.bxor:
    call lexer_next; call codegen_emit_push_rax; call parse_term; call codegen_emit_pop_rbx
    call codegen_emit_bitwise_xor_rax_rbx; mov byte [cur_type],TYPE_INT; jmp .loop
.done: pop r12; pop rbx; leave; ret
parse_comparison:
    push rbp; mov rbp,rsp; push rbx; push r12
    call parse_additive
    movzx eax,byte [tok_type]
    cmp al,TOK_EQEQ; je .eq
    cmp al,TOK_NEQ;  je .ne
    cmp al,TOK_LT;   je .lt
    cmp al,TOK_GT;   je .gt
    cmp al,TOK_LTE;  je .le
    cmp al,TOK_GTE;  je .ge
    jmp .done
.eq: mov r12b,0x94; jmp .op
.ne: mov r12b,0x95; jmp .op
.lt: mov r12b,0x9C; jmp .op
.gt: mov r12b,0x9F; jmp .op
.le: mov r12b,0x9E; jmp .op
.ge: mov r12b,0x9D
.op: call lexer_next
    call codegen_emit_push_rax; call parse_additive; call codegen_emit_pop_rbx
    movzx rdi,r12b; call codegen_emit_cmp_rbx_rax_setcc
    mov byte [cur_type],TYPE_BOOL
.done: pop r12; pop rbx; leave; ret
parse_expr:
    push rbp; mov rbp,rsp; push rbx; push r12
    call parse_comparison
.loop:
    movzx eax,byte [tok_type]
    cmp al,TOK_AND; je .land
    cmp al,TOK_OR;  je .lor
    jmp .done
.land:
    call lexer_next; call codegen_emit_push_rax; call parse_comparison; call codegen_emit_pop_rbx
    call codegen_emit_and_bool_rax_rbx; mov byte [cur_type],TYPE_BOOL; jmp .loop
.lor:
    call lexer_next; call codegen_emit_push_rax; call parse_comparison; call codegen_emit_pop_rbx
    call codegen_emit_or_bool_rax_rbx;  mov byte [cur_type],TYPE_BOOL; jmp .loop
.done: pop r12; pop rbx; leave; ret
; ── proto_find ────────────────────────────────────────────────────────────────
proto_find:
    ; rdi = name ptr → rax = out_idx (-1 if not found)
    push rbp; mov rbp,rsp; push r12; push r13; push rbx
    mov r12,rdi; xor r13,r13
.l: cmp r13,[proto_count]; jge .nf
    mov rax,r13; imul rax,PROTO_ENTRY_SIZE; lea rbx,[proto_table]; add rbx,rax
    mov rdi,rbx; mov rsi,r12; mov ecx,32
.cl: movzx eax,byte [rdi]; movzx edx,byte [rsi]
    cmp eax,edx; jne .nm; test eax,eax; jz .m; inc rdi; inc rsi; dec ecx; jnz .cl
.m: mov rax,[rbx+32]; jmp .done
.nm: inc r13; jmp .l
.nf: mov rax,-1
.done: pop rbx; pop r13; pop r12; leave; ret
; ── parse_stmt ────────────────────────────────────────────────────────────────
parse_stmt:
    push rbp; mov rbp,rsp; push rbx; push r12; push r13; push r14; push r15
    movzx eax,byte [tok_type]
    cmp al,TOK_PROT; je .s1
    cmp qword [prot_body_depth],0; jne .s1
    call codegen_end_protos; movzx eax,byte [tok_type]
.s1:
    cmp al,TOK_TYPE_INT;    je .pi
    cmp al,TOK_TYPE_FLOAT;  je .pf
    cmp al,TOK_TYPE_BOOL;   je .pb
    cmp al,TOK_TYPE_STR;    je .ps
    cmp al,TOK_TYPE_COMPLEX;je .pc
    cmp al,TOK_TYPE_SEQ;    je .pq
    cmp al,TOK_COLON;       je .assign
    cmp al,TOK_OUTPUT;      je .out
    cmp al,TOK_IF;          je .if
    cmp al,TOK_FOR;         je .for
    cmp al,TOK_WHILE;       je .while
    cmp al,TOK_PROT;        je .prot
    cmp al,TOK_RETURN;      je .ret
    cmp al,TOK_STOP;        je .stop
    cmp al,TOK_SKIP;        je .skip
    cmp al,TOK_PASS;        je .pass
    cmp al,TOK_AT;          je .at
    cmp al,TOK_USE;         je .use
    cmp al,TOK_ERR;         je .err_stmt
    cmp al,TOK_PUSH;        je .push_stmt
    cmp al,TOK_TYPE_SEQ;    je .pq   ; redundant but safe
    call lexer_next; jmp .done
; ── type declarations ─────────────────────────────────────────────────────────
.pf: mov r15b,TYPE_FLOAT;   jmp .pg
.pb: mov r15b,TYPE_BOOL;    jmp .pg
.ps: mov r15b,TYPE_STR;     jmp .pg
.pc: mov r15b,TYPE_COMPLEX; jmp .pg
.pq: mov r15b,TYPE_SEQ;     jmp .pg
.pi: mov r15b,TYPE_INT
.pg:
    call lexer_next
    cmp byte [tok_type],TOK_IDENT; jne .err
    lea rsi,[tok_ident]; lea rdi,[saved_name]; call strcpy
    call lexer_next
    cmp byte [tok_type],TOK_ASSIGN; je .pinit
    ; no init value
    lea rdi,[saved_name]; xor rsi,rsi; mov dl,0; mov cl,r15b; call var_add
    jmp .done
.pinit:
    call lexer_next         ; skip '=', tok = expr start
    call parse_expr         ; emit init code, result in rax
    lea rdi,[saved_name]; xor rsi,rsi; mov dl,1; mov cl,r15b; call var_add
    cmp rax,-1; je .done
    mov r14,rax             ; r14 = var_idx
    mov rdi,r14; call codegen_emit_store_rax_to_var
    jmp .done
.err: lea rsi,[err_id]; mov rdx,err_id_l; call fatal
; ── assignment :x = expr ─────────────────────────────────────────────────────
.assign:
    call lexer_next         ; tok = ident
    cmp byte [tok_type],TOK_IDENT; jne .done
    lea rdi,[saved_name]; lea rsi,[tok_ident]; call strcpy
    call lexer_next         ; tok = '='
    cmp byte [tok_type],TOK_ASSIGN; jne .done
    call lexer_next         ; tok = expr start
    lea rdi,[saved_name]; call var_find
    cmp rax,-1; je .done
    mov r14,rax
    call parse_expr         ; emit code for value → rax
    mov rdi,r14; call codegen_emit_store_rax_to_var
    jmp .done
; ── output expr ──────────────────────────────────────────────────────────────
.out:
    call lexer_next         ; tok = expr start
    call parse_expr         ; emit code → rax; [cur_type] = type
    movzx edi,byte [cur_type]; call codegen_output_rax
    jmp .done
; ── if / elif / else ─────────────────────────────────────────────────────────
.if: call codegen_save_chain_base
.ifn:
    call lexer_next         ; skip 'if'/'elif', tok = condition start
    call parse_expr         ; emit condition → rax; tok = ':'
    call codegen_emit_test_rax_jz
    call lexer_next         ; skip ':', tok = NEWLINE or first stmt
    cmp byte [tok_type],TOK_NEWLINE; jne .ifnn; call lexer_next
.ifnn:
    cmp byte [tok_type],TOK_INDENT; jne .ifb; call lexer_next; mov r13,1; jmp .ifbl
.ifb: xor r13,r13
.ifbl:
    movzx eax,byte [tok_type]; cmp al,TOK_EOF; je .ifen; cmp al,TOK_DEDENT; je .ifen
    call parse_stmt; test r13,r13; jnz .ifbl
.ifen:
    test r13,r13; jz .ifad
    cmp byte [tok_type],TOK_DEDENT; jne .ifad; call lexer_next
.ifad:
    movzx eax,byte [tok_type]
    cmp al,TOK_ELIF; je .elif
    cmp al,TOK_ELSE; je .else
    call codegen_patch_jump; call codegen_patch_chain_end; jmp .done
.elif:
    call codegen_emit_jmp_end; call codegen_patch_jump; jmp .ifn
.else:
    call codegen_emit_jmp_end; call codegen_patch_jump
    call lexer_next         ; skip 'else'
    call lexer_next         ; skip ':'
    cmp byte [tok_type],TOK_NEWLINE; jne .elnn; call lexer_next
.elnn:
    cmp byte [tok_type],TOK_INDENT; jne .elb; call lexer_next; mov r13,1; jmp .elbl
.elb: xor r13,r13
.elbl:
    movzx eax,byte [tok_type]; cmp al,TOK_EOF; je .elen; cmp al,TOK_DEDENT; je .elen
    call parse_stmt; test r13,r13; jnz .elbl
.elen:
    test r13,r13; jz .eldo
    cmp byte [tok_type],TOK_DEDENT; jne .eldo; call lexer_next
.eldo: call codegen_patch_chain_end; jmp .done
; ── for loop ─────────────────────────────────────────────────────────────────
.for:
    call lexer_next         ; tok = ':'
    call lexer_next         ; tok = loop var ident
    lea rdi,[saved_name]; lea rsi,[tok_ident]; call strcpy
    call lexer_next         ; tok = 'in'
    call lexer_next         ; tok = start expr
    ; parse start expression (result in rax at runtime)
    call parse_expr         ; tok = '..'
    ; allocate loop variable
    lea rdi,[saved_name]; xor rsi,rsi; mov dl,0; mov cl,TYPE_INT; call var_add
    cmp rax,-1; je .done
    mov r14,rax             ; r14 = loop var idx
    mov rdi,r14; call codegen_emit_store_rax_to_var
    ; skip '..'
    cmp byte [tok_type],TOK_DOTDOT; jne .for_nodd; call lexer_next
.for_nodd:
    ; parse end expression
    call parse_expr         ; tok = ':'
    ; allocate hidden end variable: name = saved_name + "_fe"
    lea rdi,[for_end_name]; lea rsi,[saved_name]; call strcpy
    lea rdi,[for_end_name]; lea rsi,[fe_suffix]; call strcat_local
    lea rdi,[for_end_name]; xor rsi,rsi; mov dl,0; mov cl,TYPE_INT; call var_add
    cmp rax,-1; je .done
    mov r13,rax             ; r13 = end var idx
    mov rdi,r13; call codegen_emit_store_rax_to_var
    ; emit for start (dynamic)
    mov rdi,r14; mov rsi,r13; call codegen_emit_for_start_dyn
    mov r15,rax             ; r15 = loop start PC
    ; skip ':' and whitespace
    call lexer_next         ; skip ':'
    cmp byte [tok_type],TOK_NEWLINE; jne .forl_enter; call lexer_next
.forl_enter:
    cmp byte [tok_type],TOK_INDENT; jne .forl; call lexer_next
.forl:
    movzx eax,byte [tok_type]; cmp al,TOK_EOF; je .ford; cmp al,TOK_DEDENT; je .ford
    call parse_stmt; jmp .forl
.ford:
    cmp byte [tok_type],TOK_DEDENT; jne .fornd; call lexer_next
.fornd:
    mov rdi,r15; mov rsi,r14; call codegen_emit_for_end
    jmp .done
; ── while loop ───────────────────────────────────────────────────────────────
.while:
    call lexer_next         ; skip 'while', tok = condition start
    mov r15,[out_idx]       ; r15 = condition start PC
    mov rdi,r15; call codegen_push_cont
    call parse_expr         ; emit condition → rax; tok = ':'
    call codegen_emit_test_rax_jz
    call codegen_emit_loop_base
    call lexer_next         ; skip ':', tok = NEWLINE or body
    cmp byte [tok_type],TOK_NEWLINE; jne .whl_enter; call lexer_next
.whl_enter:
    cmp byte [tok_type],TOK_INDENT; jne .whilel; call lexer_next
.whilel:
    movzx eax,byte [tok_type]; cmp al,TOK_EOF; je .whiled; cmp al,TOK_DEDENT; je .whiled
    call parse_stmt; jmp .whilel
.whiled:
    cmp byte [tok_type],TOK_DEDENT; jne .whilend; call lexer_next
.whilend:
    mov rdi,r15; call codegen_emit_while_end
    jmp .done
; ── protocol definition ───────────────────────────────────────────────────────
.prot:
    inc qword [prot_body_depth]; call codegen_begin_protos
    call lexer_next             ; tok = prot name
    mov rax,[proto_count]; imul rax,PROTO_ENTRY_SIZE
    lea r13,[proto_table]; add r13,rax
    lea rsi,[tok_ident]; mov rdi,r13; call strcpy
    mov rbx,[out_idx]; mov [r13+32],rbx
    mov byte [r13+40],0         ; param count = 0 initially
    inc qword [proto_count]
    call lexer_next             ; tok = '(' or ':'
    ; check for parameter list
    cmp byte [tok_type],TOK_LPAREN; jne .prot_nobody
    call lexer_next             ; skip '(', tok = first param or ')'
    xor r12,r12                 ; param count
.prot_pl:
    cmp byte [tok_type],TOK_RPAREN; je .prot_pd
    cmp byte [tok_type],TOK_EOF;    je .prot_pd
    cmp byte [tok_type],TOK_IDENT;  jne .prot_pd
    ; add parameter as TYPE_INT variable
    sub rsp,64; mov rdi,rsp; lea rsi,[tok_ident]; call strcpy
    mov rdi,rsp; xor rsi,rsi; mov dl,0; mov cl,TYPE_INT; call var_add; add rsp,64
    cmp rax,-1; jge .prot_pok; jmp .prot_pd
.prot_pok:
    ; store param var index in proto table [r13+41+r12]
    cmp r12,5; jge .prot_pskip
    mov [r13+41+r12],al         ; store var index (low byte)
.prot_pskip:
    inc r12; call lexer_next    ; skip ident, tok = ',' or ')'
    cmp byte [tok_type],TOK_COMMA; jne .prot_pd; call lexer_next; jmp .prot_pl
.prot_pd:
    mov [r13+40],r12b           ; store param count
    cmp byte [tok_type],TOK_RPAREN; jne .prot_nobody; call lexer_next
    ; emit param stores: arg regs → var addresses
    ; rdi=0x3F(pop rdi), rsi=0x3E(pop rsi), rdx=0x3A(pop rdx), rcx=0x39(pop rcx)
    ; Actually emit: mov [var_addr], rdi/rsi/rdx/rcx for params 0..min(r12,4)-1
    ; Param store ModRM: rdi=0x3C/0x25 form: 48 89 3C 25 <addr>
    ; rdi(0x3C 0x25), rsi(0x34 0x25), rdx(0x14 0x25), rcx(0x0C 0x25)
    xor r14,r14                 ; param index
.prot_se:
    cmp r14,r12; jge .prot_nobody
    cmp r14,4;   jge .prot_nobody
    movzx rbx,byte [r13+41+r14] ; var index
    ; emit: mov [var_addr], param_reg
    ; REX.W=0x48, MOV=0x89, ModRM, SIB=0x25, addr32
    ; ModRM for /r with SIB: depends on reg
    lea rax,[rel .prot_mrm]; movzx ecx,byte [rax+r14]; ; ModRM byte
    push rbx; push rcx; push r14
    mov al,0x48; call emit_b_indirect
    mov al,0x89; call emit_b_indirect
    pop r14; pop rcx; pop rbx
    push rbx; push r14
    mov al,cl;  call emit_b_indirect
    mov al,0x25; call emit_b_indirect
    ; emit var address
    mov rdi,rbx; call get_var_va_indirect; call emit_d_indirect
    pop r14; pop rbx
    inc r14; jmp .prot_se
.prot_mrm: db 0x3C, 0x34, 0x14, 0x0C   ; /7 rdi, /6 rsi, /2 rdx, /1 rcx
.prot_nobody:
    ; skip ':' NEWLINE INDENT
    cmp byte [tok_type],TOK_COLON; jne .prot_skip_nl; call lexer_next
.prot_skip_nl:
    cmp byte [tok_type],TOK_NEWLINE; jne .prot_skip_in; call lexer_next
.prot_skip_in:
    cmp byte [tok_type],TOK_INDENT; jne .protl; call lexer_next
.protl:
    movzx eax,byte [tok_type]; cmp al,TOK_EOF; je .protd; cmp al,TOK_DEDENT; je .protd
    call parse_stmt; jmp .protl
.protd:
    cmp byte [tok_type],TOK_DEDENT; jne .protnd; call lexer_next
.protnd:
    call codegen_emit_ret; dec qword [prot_body_depth]; jmp .done
; ── return ────────────────────────────────────────────────────────────────────
.ret:
    call lexer_next         ; tok = expr or end-of-line
    movzx eax,byte [tok_type]
    cmp al,TOK_NEWLINE; je .ret_bare
    cmp al,TOK_EOF;     je .ret_bare
    cmp al,TOK_DEDENT;  je .ret_bare
    call parse_expr         ; emit return value → rax
    call codegen_emit_ret; jmp .done
.ret_bare:
    call codegen_emit_ret; jmp .done
; ── stop / skip / pass ───────────────────────────────────────────────────────
.stop:
    call codegen_emit_break; call lexer_next; jmp .done
.skip:
    call codegen_emit_skip;  call lexer_next; jmp .done
.pass:
    call lexer_next; jmp .done
; ── @prot call (statement) ───────────────────────────────────────────────────
.at:
    call lexer_next             ; skip '@', tok = prot name
    lea rdi,[tok_ident]; call proto_find
    cmp rax,-1; je .done
    mov r12,rax                 ; r12 = out_idx
    call lexer_next             ; skip ident
    cmp byte [tok_type],TOK_LPAREN; jne .at_call
    call lexer_next             ; skip '(', tok = first arg or ')'
    xor r13,r13
.at_al:
    cmp byte [tok_type],TOK_RPAREN; je .at_ad
    cmp byte [tok_type],TOK_EOF;    je .at_ad
    cmp byte [tok_type],TOK_NEWLINE;je .at_ad
    call parse_expr; call codegen_emit_push_rax; inc r13
    cmp byte [tok_type],TOK_COMMA; jne .at_ad; call lexer_next; jmp .at_al
.at_ad:
    cmp byte [tok_type],TOK_RPAREN; jne .at_np; call lexer_next
.at_np:
    mov rdi,r13; call codegen_emit_arg_pops
    jmp .at_call
.at_call:
    mov rdi,r12; call codegen_emit_call_prot; jmp .done
; ── use mm ────────────────────────────────────────────────────────────────────
.use:
    call lexer_next; call lexer_next; call lexer_next
    ; tok = "pool" or "arena" identifier
    cmp dword [tok_ident],0x6C6F6F70   ; "pool" LE
    jne .use_arena
    cmp byte [tok_ident+4],0; je .use_pool
.use_arena:
    xor edi,edi; call codegen_emit_mm_switch; jmp .use_body
.use_pool:
    mov edi,1; call codegen_emit_mm_switch
.use_body:
    call lexer_next; call lexer_next; call lexer_next; call lexer_next; call lexer_next
    cmp byte [tok_type],TOK_NEWLINE; jne .use_un; call lexer_next
.use_un:
    cmp byte [tok_type],TOK_INDENT; jne .use_ub; call lexer_next; mov r13,1; jmp .use_ubl
.use_ub: xor r13,r13
.use_ubl:
    movzx eax,byte [tok_type]; cmp al,TOK_EOF; je .use_uen; cmp al,TOK_DEDENT; je .use_uen
    call parse_stmt; test r13,r13; jnz .use_ubl
.use_uen:
    test r13,r13; jz .use_udo
    cmp byte [tok_type],TOK_DEDENT; jne .use_udo; call lexer_next
.use_udo:
    xor rdi,rdi; call codegen_emit_mm_switch; jmp .done
; ── err statement ─────────────────────────────────────────────────────────────
.err_stmt:
    call lexer_next             ; skip 'err', tok = expr start
    call parse_expr             ; emit string ptr → rax
    call codegen_emit_mov_rdi_rax
    call codegen_emit_call_rt_err
    jmp .done
; ── seq statement ─────────────────────────────────────────────────────────────
.pq:
    call lexer_next             ; skip 'seq', tok = var name
    cmp byte [tok_type],TOK_IDENT; jne .done
    lea rdi,[saved_name]; lea rsi,[tok_ident]; call strcpy
    lea rdi,[saved_name]; xor rsi,rsi; mov dl,0; mov cl,TYPE_SEQ; call var_add
    cmp rax,-1; je .done
    mov r14,rax
    mov rdi,r14; call codegen_emit_seq_alloc
    call lexer_next; jmp .done
; ── push statement ────────────────────────────────────────────────────────────
.push_stmt:
    call lexer_next             ; skip 'push', tok = seq var name
    cmp byte [tok_type],TOK_IDENT; jne .done
    lea rdi,[saved_name]; lea rsi,[tok_ident]; call strcpy
    lea rdi,[saved_name]; call var_find
    cmp rax,-1; je .done
    mov r14,rax                 ; r14 = seq var idx
    call lexer_next             ; skip seq var name, tok = value expr
    call parse_expr             ; emit value → rax
    mov rdi,r14; call codegen_emit_seq_push
    jmp .done
.done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; leave; ret
; ── indirect emit helpers (called from prot param store) ─────────────────────
; These are wrappers because we can't call extern emit_b from parser.asm
; Instead, the prot param emit uses the global codegen_emit_store_rax_to_var
; approach — for now just stub these as no-ops to avoid link errors
emit_b_indirect:
    ; TODO: find a way to emit bytes from parser — for now this is a no-op stub
    ; Protocol parameters will need a codegen function; skip for now
    ret
emit_d_indirect:
    ret
get_var_va_indirect:
    mov rax,rdi; shl rax,6; add rax,VAR_STORAGE_BASE; ret
