import subprocess, os, sys

NASM = "/nix/store/kbyq3jx1i16p2rnshkd90rhfgm6anf42-nasm-2.16.03/bin/nasm"
LOAD_BASE        = 0x400000
HEADERS_SIZE     = 120
VAR_STORAGE_BASE = 0x440000
VAR_ENTRY_SIZE   = 64
VAR_MAX          = 128
PROTO_ENTRY_SIZE = 48

RT_PRI_SIZE = 512;  RT_PRS_SIZE = 512;  RT_PRB_SIZE = 256
RT_PRF_SIZE = 512;  RT_PRC_SIZE = 512;  RT_SIP_SIZE = 1024
RT_ALC_SIZE = 4096; RT_PRQ_SIZE = 1024
RT_TOTAL_SIZE = RT_PRI_SIZE+RT_PRS_SIZE+RT_PRB_SIZE+RT_PRF_SIZE+RT_PRC_SIZE+RT_SIP_SIZE+RT_ALC_SIZE+RT_PRQ_SIZE

RT_PRI_OFFSET = HEADERS_SIZE + 5
RT_PRS_OFFSET = RT_PRI_OFFSET + RT_PRI_SIZE
RT_PRB_OFFSET = RT_PRS_OFFSET + RT_PRS_SIZE
RT_PRF_OFFSET = RT_PRB_OFFSET + RT_PRB_SIZE
RT_PRC_OFFSET = RT_PRF_OFFSET + RT_PRF_SIZE
RT_SIP_OFFSET = RT_PRC_OFFSET + RT_PRC_SIZE
RT_ALC_OFFSET = RT_SIP_OFFSET + RT_SIP_SIZE
RT_PRQ_OFFSET = RT_ALC_OFFSET + RT_ALC_SIZE
CODE_START    = RT_PRQ_OFFSET + RT_PRQ_SIZE

def get_blob_bytes(name, asm_code):
    with open("_tmp_blob.asm","w") as f:
        f.write("[bits 64]\ndefault rel\n" + asm_code)
    try:
        res = subprocess.run([NASM,"-f","bin","_tmp_blob.asm","-o","_tmp_blob.bin"],
                             capture_output=True, timeout=15)
        if res.returncode != 0:
            print(f"NASM Error [{name}]:\n{res.stderr.decode()}")
            sys.exit(1)
        with open("_tmp_blob.bin","rb") as f: return f.read()
    finally:
        for p in ["_tmp_blob.asm","_tmp_blob.bin"]:
            if os.path.exists(p): os.remove(p)

# ── Runtime blob sources ───────────────────────────────────────────────────────

rt_pri_asm = r"""
    push rbp; mov rbp, rsp; push rax; push rbx; push rcx; push rdx; push rsi; push rdi
    sub rsp, 64; mov rax, rdi; test rax, rax; jns .pos; neg rax
    mov byte [rsp+63], '-'; mov rax, 1; mov rdi, 1; lea rsi, [rsp+63]; mov rdx, 1; syscall
    mov rax, [rbp-56]; neg rax
.pos:
    lea rdi, [rsp+62]; mov byte [rdi], 10; mov rcx, 1; mov rbx, 10
.l1: xor rdx, rdx; div rbx; add dl, '0'; dec rdi; mov [rdi], dl; inc rcx; test rax, rax; jnz .l1
    mov rax, 1; mov rsi, rdi; mov rdx, rcx; mov rdi, 1; syscall; add rsp, 64
    pop rdi; pop rsi; pop rdx; pop rcx; pop rbx; pop rax; leave; ret
"""

rt_prs_asm = r"""
    push rbp; mov rbp, rsp; push rax; push rdx; push rsi; push rdi
    mov rsi, rdi; xor rdx, rdx
.l1: cmp byte [rsi+rdx], 0; je .d1; inc rdx; jmp .l1
.d1: test rdx, rdx; jz .nl; mov rax, 1; mov rdi, 1; syscall
.nl: sub rsp, 16; mov byte [rsp], 10; mov rax, 1; mov rdi, 1; mov rsi, rsp; mov rdx, 1; syscall
    add rsp, 16; pop rdi; pop rsi; pop rdx; pop rax; leave; ret
"""

rt_prb_asm = r"""
    push rbp; mov rbp, rsp
    test rdi, rdi; jz .f; cmp rdi, 1; jne .u
    mov rax,1; mov rdi,1; lea rsi,[rel .st]; mov rdx,5; syscall; jmp .d
.f: mov rax,1; mov rdi,1; lea rsi,[rel .sf]; mov rdx,6; syscall; jmp .d
.u: mov rax,1; mov rdi,1; lea rsi,[rel .su]; mov rdx,8; syscall
.d: leave; ret
.st: db "true",10
.sf: db "false",10
.su: db "unknown",10
"""

rt_prf_asm = r"""
    push rbp; mov rbp, rsp
    push rbx; push r12; push r13; push r14; push r15
    sub rsp, 64
    lea r15, [rsp]
    test rdi, rdi; jns .pos
    mov byte [r15], '-'; inc r15
    movq xmm0, rdi
    pcmpeqd xmm1, xmm1; psllq xmm1, 63; xorpd xmm0, xmm1
    jmp .ns
.pos: movq xmm0, rdi
.ns:
    cvttsd2si r14, xmm0
    cvtsi2sd xmm1, r14; subsd xmm0, xmm1
    lea r13, [rsp+32]; xor r12, r12; mov rbx, r14
    test rbx, rbx; jnz .il
    mov byte [r13], '0'; inc r12; jmp .id
.il: test rbx, rbx; jz .id
    mov rax, rbx; xor rdx, rdx; mov ecx,10; div rcx
    add dl,'0'; mov [r13+r12],dl; inc r12; mov rbx,rax; jmp .il
.id: dec r12
.ic: movzx eax, byte [r13+r12]; mov [r15],al; inc r15; dec r12; jns .ic
    mov byte [r15],'.'; inc r15
    mov eax,1000000; cvtsi2sd xmm2,rax; mulsd xmm0,xmm2; cvttsd2si r14,xmm0
    add r15,6; mov rbx,r15; dec r15; mov ecx,6
.fl: mov rax,r14; xor rdx,rdx; mov r8d,10; div r8
    add dl,'0'; mov [r15],dl; dec r15; mov r14,rax; dec ecx; jnz .fl
    mov r15,rbx; mov byte [r15],10; inc r15
    lea rsi,[rsp]; mov rdx,r15; sub rdx,rsi; mov rax,1; mov rdi,1; syscall
    add rsp,64; pop r15; pop r14; pop r13; pop r12; pop rbx; leave; ret
"""

rt_prc_asm = r"""
    push rbp; mov rbp, rsp; push rbx; push r12; push r13; push r14; push r15
    mov r12, rdi; mov r13, rsi; xor r14, r14; xor r15, r15
.l1: cmp byte [r12+r14], 0; je .l2; inc r14; jmp .l1
.l2: cmp byte [r13+r15], 0; je .al; inc r15; jmp .l2
.al:
    lea rdi, [r14+r15+1]
    mov rax, """ + f"0x{(LOAD_BASE + RT_ALC_OFFSET):x}" + r"""
    call rax
    mov rbx, rax; mov rdi, rax; mov rsi, r12; mov rcx, r14; cld; rep movsb
    mov rsi, r13; mov rcx, r15; rep movsb; mov byte [rdi], 0; mov rax, rbx
    pop r15; pop r14; pop r13; pop r12; pop rbx; leave; ret
"""

rt_alc_asm = r"""
    jmp .dispatch
.arena:
    push rbp; mov rbp, rsp; push rbx
    mov rax,[rel .ap]; test rax,rax; jnz .aa
    mov rax,9; xor rdi,rdi; mov rsi,0x100000; mov rdx,3; mov r10,34; mov r8,-1; xor r9,r9; syscall
    mov [rel .ap],rax
.aa: mov rax,[rel .ap]; add rax,[rel .ao]; add [rel .ao],rdi; pop rbx; leave; ret
.pool:
    push rbp; mov rbp, rsp; push rbx
    mov rax,[rel .pp]; test rax,rax; jnz .pa
    mov rax,9; xor rdi,rdi; mov rsi,0x10000; mov rdx,3; mov r10,34; mov r8,-1; xor r9,r9; syscall
    mov [rel .pp],rax
.pa: mov rax,[rel .pp]; add rax,[rel .po]; add qword [rel .po],64; pop rbx; leave; ret
.dispatch:
    mov rax,[rel .mode]; cmp rax,1; je .pool; jmp .arena
.ap: dq 0
.ao: dq 0
.pp: dq 0
.po: dq 0
.mode: dq 0
"""

rt_sip_asm = r"""
    push rbp; mov rbp, rsp; push rbx; push r12; push r13; push r14; push r15
    mov r12,[rdx]; mov r13,[rdx+8]
    mov r8,0x736f6d6570736575; xor r8,r12; mov r9,0x646f72616e646f6d; xor r9,r13
    mov r10,0x6c7967656e657261; xor r10,r12; mov r11,0x7465646279746573; xor r11,r13
    mov rcx,rsi; shr rcx,3; jz .f
.l: mov rax,[rdi]; xor r11,rax
%macro S 0
    add r8,r9; add r10,r11; rol r9,13; rol r11,16; xor r9,r8; xor r11,r10; rol r8,32
    add r10,r9; add r8,r11; rol r9,17; rol r11,21; xor r9,r10; xor r11,r8; rol r10,32
%endmacro
    S; S; xor r8,rax; add rdi,8; dec rcx; jnz .l
.f: mov rax,rsi; shl rax,56; xor r11,rax; S; S; xor r8,rax; xor r10,0xff; S; S; S; S
    mov rax,r8; xor rax,r9; xor rax,r10; xor rax,r11
    pop r15; pop r14; pop r13; pop r12; pop rbx; leave; ret
"""

# rt_prq: first function = rt_err (write string to stderr)
rt_prq_asm = r"""
    push rbp; mov rbp, rsp; push rbx; push rsi; push rdx; push rdi
    mov rbx, rdi; xor rdx, rdx
.sl: cmp byte [rbx+rdx],0; je .sd; inc rdx; jmp .sl
.sd: test rdx,rdx; jz .nl
    mov rax,1; mov rdi,2; mov rsi,rbx; syscall
.nl: sub rsp,16; mov byte [rsp],10
    mov rax,1; mov rdi,2; lea rsi,[rsp]; mov rdx,1; syscall
    add rsp,16
    pop rdi; pop rdx; pop rsi; pop rbx; leave; ret
"""

print("Compiling runtime blobs...")
raw_blobs = {
    "rt_pri": get_blob_bytes("rt_pri", rt_pri_asm),
    "rt_prs": get_blob_bytes("rt_prs", rt_prs_asm),
    "rt_prb": get_blob_bytes("rt_prb", rt_prb_asm),
    "rt_prf": get_blob_bytes("rt_prf", rt_prf_asm),
    "rt_prc": get_blob_bytes("rt_prc", rt_prc_asm),
    "rt_sip": get_blob_bytes("rt_sip", rt_sip_asm),
    "rt_alc": get_blob_bytes("rt_alc", rt_alc_asm),
    "rt_prq": get_blob_bytes("rt_prq", rt_prq_asm),
}
for name, data in raw_blobs.items():
    size_const = f"RT_{name[3:].upper()}_SIZE"
    max_size = eval(size_const)
    if len(data) > max_size:
        print(f"ERROR: {name} blob {len(data)} bytes > {size_const}={max_size}")
        sys.exit(1)
    print(f"  {name}: {len(data)} bytes / {max_size}")

# ── rex_defs.inc ───────────────────────────────────────────────────────────────
with open("include/rex_defs.inc","w") as f:
    f.write(f"""\
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
TYPE_INT equ 1
TYPE_FLOAT equ 2
TYPE_BOOL equ 3
TYPE_COMPLEX equ 4
TYPE_STR equ 5
TYPE_SEQ equ 6
VAR_ENTRY_SIZE equ {VAR_ENTRY_SIZE}
VAR_MAX equ {VAR_MAX}
PROTO_ENTRY_SIZE equ {PROTO_ENTRY_SIZE}
VAR_STORAGE_BASE equ {VAR_STORAGE_BASE}
LOAD_BASE equ {LOAD_BASE}
HEADERS_SIZE equ {HEADERS_SIZE}
RT_PRI_SIZE equ 512
RT_PRS_SIZE equ 512
RT_PRB_SIZE equ 256
RT_PRF_SIZE equ 512
RT_PRC_SIZE equ 512
RT_SIP_SIZE equ 1024
RT_ALC_SIZE equ 4096
RT_PRQ_SIZE equ 1024
RT_TOTAL_SIZE equ {RT_TOTAL_SIZE}
RT_PRI_OFFSET equ {RT_PRI_OFFSET}
RT_PRS_OFFSET equ {RT_PRS_OFFSET}
RT_PRB_OFFSET equ {RT_PRB_OFFSET}
RT_PRF_OFFSET equ {RT_PRF_OFFSET}
RT_PRC_OFFSET equ {RT_PRC_OFFSET}
RT_SIP_OFFSET equ {RT_SIP_OFFSET}
RT_ALC_OFFSET equ {RT_ALC_OFFSET}
RT_PRQ_OFFSET equ {RT_PRQ_OFFSET}
CODE_START equ {CODE_START}
""")

# ── runtime.asm ────────────────────────────────────────────────────────────────
with open("runtime/runtime.asm","w") as f:
    f.write('default rel\n%include "include/rex_defs.inc"\n')
    for name in raw_blobs: f.write(f"global {name}_blob\n")
    f.write("\nsection .data\n")
    for name, data in raw_blobs.items():
        f.write(f"{name}_blob:\n")
        for i in range(0,len(data),12):
            f.write("    db "+", ".join(f"0x{b:02x}" for b in data[i:i+12])+"\n")
        f.write(f"    times {name.upper()}_SIZE - ($ - {name}_blob) db 0x90\n")

# ── headers.asm ───────────────────────────────────────────────────────────────
with open("headers/headers.asm","w") as f:
    f.write(r"""default rel
%include "include/rex_defs.inc"
global elf_header, program_header, out_name
section .data
elf_header:
    db 0x7F,'E','L','F',2,1,1,0,0,0,0,0,0,0,0,0
    dw 2; dw 0x3E; dd 1; dq LOAD_BASE+HEADERS_SIZE; dq 64; dq 0; dd 0
    dw 64; dw 56; dw 1; dw 0; dw 0; dw 0
program_header:
    dd 1; dd 7; dq 0; dq LOAD_BASE; dq LOAD_BASE; dq 0x80000; dq 0x80000; dq 0x1000
out_name: db "output",0
""")

# ── main.asm ──────────────────────────────────────────────────────────────────
with open("main/main.asm","w") as f:
    f.write(r"""default rel
%include "include/rex_defs.inc"
global _start
extern lexer_init, lexer_next, parse_stmt, codegen_write_headers, codegen_init, codegen_finish
extern out_buffer, out_idx, out_name, tok_type
section .bss
src_buffer: resb 65536
src_len: resq 1
src_fd:  resq 1
out_fd:  resq 1
section .text
_start:
    mov rax, [rsp]; cmp rax, 2; jl .err
    mov rdi, [rsp+16]; mov rax, 2; xor rsi, rsi; xor rdx, rdx; syscall
    test rax, rax; js .err
    mov [src_fd], rax; mov rdi, rax; mov rax, 0; lea rsi, [src_buffer]; mov rdx, 65536; syscall
    mov [src_len], rax; mov rax, 3; mov rdi, [src_fd]; syscall
    call codegen_write_headers; call codegen_init
    lea rdi, [src_buffer]; mov rsi, [src_len]; call lexer_init; call lexer_next
.l: movzx eax, byte [tok_type]; cmp al, TOK_EOF; je .d
    cmp al, TOK_NEWLINE; je .s; call parse_stmt; jmp .l
.s: call lexer_next; jmp .l
.d: call codegen_finish
    mov rax, 87; lea rdi, [out_name]; syscall
    mov rax, 2; lea rdi, [out_name]; mov rsi, 0x41; mov rdx, 493; syscall
    test rax, rax; js .err; mov [out_fd], rax
    mov rdi, rax; mov rax, 1; lea rsi, [out_buffer]; mov rdx, [out_idx]; syscall
    mov rax, 3; mov rdi, [out_fd]; syscall
    mov rax, 60; xor rdi, rdi; syscall
.err: mov rax, 60; mov rdi, 1; syscall
""")

# ── lexer.asm ─────────────────────────────────────────────────────────────────
with open("lexer/lexer.asm","w") as f:
    f.write(r"""default rel
%include "include/rex_defs.inc"
global lexer_init, lexer_next, tok_type, tok_int, tok_ident
section .bss
lex_src: resq 1
lex_len: resq 1
lex_pos: resq 1
at_line_start: resb 1
indent_stack: resq 32
indent_depth: resq 1
pending_dedents: resq 1
tok_type: resb 1
tok_int:  resq 1
tok_ident: resb 64
section .text
lexer_init:
    push rbp; mov rbp, rsp
    mov [lex_src], rdi; mov [lex_len], rsi
    mov qword [lex_pos], 0; mov byte [at_line_start], 1
    mov qword [indent_depth], 0; mov qword [pending_dedents], 0
    mov qword [indent_stack], 0
    leave; ret
lexer_next:
    push rbp; mov rbp, rsp
    push rbx; push r12; push r13; push r14; push r15
.r: cmp qword [pending_dedents], 0; jle .n
    dec qword [pending_dedents]; mov byte [tok_type], TOK_DEDENT; jmp .done
.n: cmp byte [at_line_start], 0; je .s
    mov rcx, [lex_pos]; mov rdi, [lex_src]; xor rbx, rbx
.cs: cmp rcx, [lex_len]; jge .ie
    movzx eax, byte [rdi+rcx]; cmp al, ' '; jne .cd; inc rbx; inc rcx; jmp .cs
.cd: cmp rcx, [lex_len]; jge .ie
    movzx eax, byte [rdi+rcx]; cmp al, 0x0A; je .bl
    mov [lex_pos], rcx; mov byte [at_line_start], 0
    mov rax, [indent_depth]; lea rcx, [indent_stack]; mov rdx, [rcx+rax*8]
    cmp rbx, rdx; jg .mi; jl .li; jmp .s
.mi: inc qword [indent_depth]; mov rax, [indent_depth]; lea rcx, [indent_stack]
    mov [rcx+rax*8], rbx; mov byte [tok_type], TOK_INDENT; jmp .done
.li: cmp qword [indent_depth], 0; jle .de
    mov rax, [indent_depth]; lea rcx, [indent_stack]; mov rdx, [rcx+rax*8]
    cmp rdx, rbx; jle .de; dec qword [indent_depth]; inc qword [pending_dedents]; jmp .li
.de: dec qword [pending_dedents]; mov byte [tok_type], TOK_DEDENT; jmp .done
.bl: inc rcx; mov [lex_pos], rcx; jmp .r
.ie: mov byte [at_line_start], 0; mov [lex_pos], rcx; jmp .r
.s: mov rcx, [lex_pos]; mov rdi, [lex_src]
.sl: cmp rcx, [lex_len]; jge .ee
    movzx eax, byte [rdi+rcx]; cmp al, ' '; je .sn; cmp al, 0x09; je .sn; jmp .sd
.sn: inc rcx; jmp .sl
.sd: mov [lex_pos], rcx; cmp rcx, [lex_len]; jge .ee
    movzx eax, byte [rdi+rcx]
    cmp al, 0x0A; je .enl
    cmp al, '"';  je .pstr
    cmp al, '[';  je .elb;  cmp al, ']'; je .erb
    cmp al, '{';  je .elc;  cmp al, '}'; je .erc
    cmp al, ',';  je .ecm
    cmp al, '(';  je .elp;  cmp al, ')'; je .erp
    cmp al, '*';  je .estar
    cmp al, '/';  je .eslash
    cmp al, '%';  je .epct
    cmp al, '<';  je .elt
    cmp al, '>';  je .egt
    cmp al, '!';  je .eexcl
    cmp al, '&';  je .eamp
    cmp al, '|';  je .epipe
    cmp al, '^';  je .ecaret
    cmp al, '~';  je .etilde
    cmp al, '_';  je .pid
    cmp al, 'a';  jl .cup; cmp al, 'z'; jle .pid
.cup: cmp al, 'A'; jl .cdi; cmp al, 'Z'; jle .pid
.cdi: cmp al, '0'; jl .csp; cmp al, '9'; jle .pin
.csp: cmp al, '='; je .eas; cmp al, ':'; je .eco; cmp al, '.'; je .cdd
    cmp al, '@'; je .eat; cmp al, '+'; je .epl; cmp al, '-'; je .emi
    inc qword [lex_pos]; jmp .r
.elb: inc qword [lex_pos]; mov byte [tok_type], TOK_LBRACK; jmp .done
.erb: inc qword [lex_pos]; mov byte [tok_type], TOK_RBRACK; jmp .done
.elc: inc qword [lex_pos]; mov byte [tok_type], TOK_LBRACE; jmp .done
.erc: inc qword [lex_pos]; mov byte [tok_type], TOK_RBRACE; jmp .done
.ecm: inc qword [lex_pos]; mov byte [tok_type], TOK_COMMA;  jmp .done
.elp: inc qword [lex_pos]; mov byte [tok_type], TOK_LPAREN; jmp .done
.erp: inc qword [lex_pos]; mov byte [tok_type], TOK_RPAREN; jmp .done
.estar: inc qword [lex_pos]; mov byte [tok_type], TOK_STAR;  jmp .done
.eslash: inc qword [lex_pos]; mov byte [tok_type], TOK_SLASH; jmp .done
.epct:  inc qword [lex_pos]; mov byte [tok_type], TOK_PERCENT; jmp .done
.eamp:  inc qword [lex_pos]; mov byte [tok_type], TOK_AMP;   jmp .done
.ecaret:inc qword [lex_pos]; mov byte [tok_type], TOK_CARET; jmp .done
.etilde:inc qword [lex_pos]; mov byte [tok_type], TOK_TILDE; jmp .done
.elt:   mov rcx, [lex_pos]; inc rcx; cmp rcx,[lex_len]; jge .lt1
    movzx eax, byte [rdi+rcx]
    cmp al,'='; jne .ltlt; inc rcx; mov [lex_pos],rcx; mov byte [tok_type],TOK_LTE; jmp .done
.ltlt: cmp al,'<'; jne .lt1; inc rcx; mov [lex_pos],rcx; mov byte [tok_type],TOK_LSHIFT; jmp .done
.lt1:  mov [lex_pos],rcx; mov byte [tok_type],TOK_LT; jmp .done
.egt:   mov rcx, [lex_pos]; inc rcx; cmp rcx,[lex_len]; jge .gt1
    movzx eax, byte [rdi+rcx]
    cmp al,'='; jne .gtgt; inc rcx; mov [lex_pos],rcx; mov byte [tok_type],TOK_GTE; jmp .done
.gtgt: cmp al,'>'; jne .gt1; inc rcx; mov [lex_pos],rcx; mov byte [tok_type],TOK_RSHIFT; jmp .done
.gt1:  mov [lex_pos],rcx; mov byte [tok_type],TOK_GT; jmp .done
.eexcl: mov rcx,[lex_pos]; inc rcx; cmp rcx,[lex_len]; jge .eskip
    movzx eax, byte [rdi+rcx]; cmp al,'='; jne .eskip
    inc rcx; mov [lex_pos],rcx; mov byte [tok_type],TOK_NEQ; jmp .done
.eskip: inc qword [lex_pos]; jmp .r
.epipe: mov rcx,[lex_pos]; inc rcx; cmp rcx,[lex_len]; jge .pipe1
    movzx eax, byte [rdi+rcx]; cmp al,'|'; jne .pipe1
    inc rcx; mov [lex_pos],rcx; mov byte [tok_type],TOK_OR; jmp .done
.pipe1: mov [lex_pos],rcx; mov byte [tok_type],TOK_PIPE; jmp .done
.pstr: inc qword [lex_pos]; mov rcx,[lex_pos]; mov rdi,[lex_src]; lea rsi,[tok_ident]; xor rbx,rbx
.strl: cmp rcx,[lex_len]; jge .strd
    movzx eax, byte [rdi+rcx]; cmp al,'"'; je .strq; mov [rsi+rbx],al; inc rbx; inc rcx; jmp .strl
.strq: inc rcx
.strd: mov byte [rsi+rbx],0; mov [lex_pos],rcx; mov byte [tok_type],TOK_STR_LIT; jmp .done
.epl: inc qword [lex_pos]; mov byte [tok_type], TOK_PLUS;  jmp .done
.emi: inc qword [lex_pos]; mov byte [tok_type], TOK_MINUS; jmp .done
.eat: inc qword [lex_pos]; mov byte [tok_type], TOK_AT;    jmp .done
.ee:  mov byte [tok_type], TOK_EOF;  jmp .done
.enl: inc qword [lex_pos]; mov byte [at_line_start],1; mov byte [tok_type],TOK_NEWLINE; jmp .done
.eas: mov rcx,[lex_pos]; inc rcx; cmp rcx,[lex_len]; jge .as
    movzx eax, byte [rdi+rcx]; cmp al,'='; jne .as
    inc rcx; mov [lex_pos],rcx; mov byte [tok_type],TOK_EQEQ; jmp .done
.as:  mov [lex_pos],rcx; mov byte [tok_type],TOK_ASSIGN; jmp .done
.eco: inc qword [lex_pos]; mov byte [tok_type],TOK_COLON; jmp .done
.cdd: mov rcx,[lex_pos]; inc rcx; cmp rcx,[lex_len]; jge .sch
    movzx eax, byte [rdi+rcx]; cmp al,'.'; jne .sch
    add qword [lex_pos],2; mov byte [tok_type],TOK_DOTDOT; jmp .done
.sch: inc qword [lex_pos]; jmp .r
.pid: mov rcx,[lex_pos]; mov rdi,[lex_src]; lea rsi,[tok_ident]; xor rbx,rbx
.id_l: cmp rbx,63; jge .id_d; cmp rcx,[lex_len]; jge .id_d
    movzx eax, byte [rdi+rcx]; cmp al,'_'; je .id_c
    cmp al,'a'; jl .id_up; cmp al,'z'; jle .id_c
.id_up: cmp al,'A'; jl .id_di; cmp al,'Z'; jle .id_c
.id_di: cmp al,'0'; jl .id_d; cmp al,'9'; jle .id_c; jmp .id_d
.id_c: mov [rsi+rbx],al; inc rbx; inc rcx; jmp .id_l
.id_d: mov byte [rsi+rbx],0; mov [lex_pos],rcx; call lexer_classify; jmp .done
.pin: mov rcx,[lex_pos]; mov rdi,[lex_src]; xor rbx,rbx
.in_l: cmp rcx,[lex_len]; jge .in_d
    movzx eax, byte [rdi+rcx]; cmp al,'0'; jl .in_f; cmp al,'9'; jg .in_f
    sub al,'0'; imul rbx,rbx,10; movzx rax,al; add rbx,rax; inc rcx; jmp .in_l
.in_f: cmp al,'.'; jne .in_c
    cvtsi2sd xmm0,rbx; inc rcx; mov r8,10; cvtsi2sd xmm2,r8; movsd xmm1,xmm2
.fl_l: cmp rcx,[lex_len]; jge .fl_d
    movzx eax, byte [rdi+rcx]; cmp al,'0'; jl .fl_d; cmp al,'9'; jg .fl_d
    sub al,'0'; cvtsi2sd xmm3,rax; divsd xmm3,xmm1; addsd xmm0,xmm3; mulsd xmm1,xmm2; inc rcx; jmp .fl_l
.fl_d: mov [lex_pos],rcx; movq [tok_int],xmm0; mov byte [tok_type],TOK_FLOAT_LIT; jmp .done
.in_c: cmp al,'j'; jne .in_d; inc rcx; mov [lex_pos],rcx; mov [tok_int],rbx; mov byte [tok_type],TOK_COMPLEX_LIT; jmp .done
.in_d: mov [lex_pos],rcx; mov [tok_int],rbx; mov byte [tok_type],TOK_INT_LIT; jmp .done
.done: pop r15; pop r14; pop r13; pop r12; pop rbx; leave; ret

lexer_classify:
    mov eax, dword [tok_ident]
    ; bool=0x6c6f6f62 float=0x616f6c66(+t) complex=0x706d6f63(+lex)
    cmp eax,0x6c6f6f62; je .kb
    cmp eax,0x616f6c66; jne .nf; cmp byte [tok_ident+4],'t'; je .kf
.nf: cmp eax,0x706d6f63; jne .ncp; cmp dword [tok_ident+4],0x78656c; je .kcp
.ncp: cmp eax,0x00727473; je .ks
    cmp eax,0x65757274; je .kt
    cmp eax,0x736c6166; jne .nfa; cmp byte [tok_ident+4],'e'; je .kfa
.nfa: cmp eax,0x6e6b6e75; jne .nu; cmp dword [tok_ident+4],0x6e776f; je .ku
.nu: cmp eax,0x00746e69; je .ki
    cmp eax,0x00006669; je .kif
    cmp eax,0x00726f66; je .kfo
    cmp eax,0x00006e69; je .kin
    cmp eax,0x6C696877; jne .nwh; cmp byte [tok_ident+4],'e'; je .kwh
.nwh: cmp eax,0x00657375; je .kuse
    cmp eax,0x00006d6d; je .kmm
    cmp eax,0x00006367; je .kgc
    cmp eax,0x746F7270; je .kpr
    cmp eax,0x75746572; jne .nr; cmp byte [tok_ident+4],'r'; jne .nr; cmp byte [tok_ident+5],'n'; je .kr
.nr: cmp eax,0x706F7473; je .kso
    cmp eax,0x65736C65; je .kel
    cmp eax,0x66696C65; je .kei
    cmp eax,0x7074756F; jne .nout; cmp word [tok_ident+4],0x7475; je .kou
.nout:
    ; new keywords: and or not err seq push pop len skip pass each when typeof bin
    cmp eax,0x00646e61; je .kand    ; "and\0"
    cmp eax,0x0000726f; je .kor     ; "or\0\0"
    cmp eax,0x00746f6e; je .knot    ; "not\0"
    cmp eax,0x00727265; je .kerr    ; "err\0"
    cmp eax,0x00716573; je .kseq    ; "seq\0"
    cmp eax,0x68737570; je .kpush   ; "push"
    cmp eax,0x00706f70; je .kpop    ; "pop\0"
    cmp eax,0x006e656c; je .klen    ; "len\0"
    cmp eax,0x70696b73; je .kskip   ; "skip"
    cmp eax,0x73736170; je .kpass   ; "pass"
    cmp eax,0x68636165; je .keach   ; "each"
    cmp eax,0x6e656877; je .kwhen   ; "when"
    cmp eax,0x65707974; jne .ntype; cmp dword [tok_ident+4],0x666f; je .ktof  ; "typeof"
.ntype:
    cmp eax,0x006e6962; je .kbin    ; "bin\0"
.kid: mov byte [tok_type], TOK_IDENT; ret
.ki:  mov byte [tok_type], TOK_TYPE_INT;     ret
.kb:  mov byte [tok_type], TOK_TYPE_BOOL;    ret
.kf:  mov byte [tok_type], TOK_TYPE_FLOAT;   ret
.kcp: mov byte [tok_type], TOK_TYPE_COMPLEX; ret
.ks:  mov byte [tok_type], TOK_TYPE_STR;     ret
.kt:  mov byte [tok_type], TOK_TRUE;   ret
.kfa: mov byte [tok_type], TOK_FALSE;  ret
.ku:  mov byte [tok_type], TOK_UNKNOWN;ret
.kif: mov byte [tok_type], TOK_IF;     ret
.kfo: mov byte [tok_type], TOK_FOR;    ret
.kin: mov byte [tok_type], TOK_IN;     ret
.kwh: mov byte [tok_type], TOK_WHILE;  ret
.kuse:mov byte [tok_type], TOK_USE;    ret
.kmm: mov byte [tok_type], TOK_MM;     ret
.kgc: mov byte [tok_type], TOK_GC;     ret
.kpr: mov byte [tok_type], TOK_PROT;   ret
.kr:  mov byte [tok_type], TOK_RETURN; ret
.kso: mov byte [tok_type], TOK_STOP;   ret
.kel: mov byte [tok_type], TOK_ELSE;   ret
.kei: mov byte [tok_type], TOK_ELIF;   ret
.kou: mov byte [tok_type], TOK_OUTPUT; ret
.kand: mov byte [tok_type], TOK_AND;   ret
.kor:  mov byte [tok_type], TOK_OR;    ret
.knot: mov byte [tok_type], TOK_NOT;   ret
.kerr: mov byte [tok_type], TOK_ERR;   ret
.kseq: mov byte [tok_type], TOK_TYPE_SEQ; ret
.kpush:mov byte [tok_type], TOK_PUSH;  ret
.kpop: mov byte [tok_type], TOK_POP;   ret
.klen: mov byte [tok_type], TOK_LEN;   ret
.kskip:mov byte [tok_type], TOK_SKIP;  ret
.kpass:mov byte [tok_type], TOK_PASS;  ret
.keach:mov byte [tok_type], TOK_EACH;  ret
.kwhen:mov byte [tok_type], TOK_WHEN;  ret
.ktof: mov byte [tok_type], TOK_TYPEOF;ret
.kbin: mov byte [tok_type], TOK_BIN;   ret
""")

# ── codegen.asm ───────────────────────────────────────────────────────────────
with open("codegen/codegen.asm","w") as f:
    f.write(r"""default rel
%include "include/rex_defs.inc"
global codegen_write_headers, codegen_init, codegen_finish, out_buffer, out_idx
global codegen_output_const, codegen_output_typed, codegen_patch_jump
global codegen_save_chain_base, codegen_emit_jmp_end, codegen_patch_chain_end
global codegen_begin_protos, codegen_end_protos
global codegen_emit_for_start, codegen_emit_for_end
global codegen_emit_while_start, codegen_emit_while_end
global codegen_emit_break, codegen_patch_breaks, codegen_emit_loop_base
global codegen_emit_ret, codegen_emit_mov_eax_imm32, codegen_emit_call_prot
global codegen_emit_assign_var, codegen_emit_cmp_var_jne, codegen_emit_unknown_bool
global codegen_emit_mm_switch
; new emit helpers
global codegen_emit_push_rax, codegen_emit_pop_rbx
global codegen_emit_mov_rax_var, codegen_emit_store_rax_to_var
global codegen_emit_rdrand_rax, codegen_emit_neg_rax, codegen_emit_not_rax
global codegen_emit_bitwise_not_rax
global codegen_emit_add_rax_rbx, codegen_emit_sub_rax_rbx
global codegen_emit_imul_rax_rbx, codegen_emit_idiv_rbx_by_rax, codegen_emit_imod_rbx_by_rax
global codegen_emit_cmp_rbx_rax_setcc, codegen_emit_test_rax_jz
global codegen_output_rax
global codegen_emit_addsd_rax_rbx, codegen_emit_subsd_rax_rbx
global codegen_emit_mulsd_rax_rbx, codegen_emit_divsd_rax_rbx
global codegen_emit_cvttsd2si_rax, codegen_emit_cvtsi2sd_rax
global codegen_emit_bitwise_and_rax_rbx, codegen_emit_bitwise_or_rax_rbx
global codegen_emit_bitwise_xor_rax_rbx
global codegen_emit_and_bool_rax_rbx, codegen_emit_or_bool_rax_rbx
global codegen_emit_shl_rax_by_rbx, codegen_emit_shr_rax_by_rbx
global codegen_emit_str_rax
global codegen_emit_seq_alloc, codegen_emit_seq_push, codegen_emit_seq_pop_rax
global codegen_emit_seq_len_rax
global codegen_emit_mov_rdi_rax, codegen_emit_call_rt_err
global codegen_emit_for_start_dyn, codegen_emit_arg_pops
global codegen_push_cont, codegen_pop_cont, codegen_emit_skip
extern elf_header, program_header
extern rt_pri_blob, rt_prs_blob, rt_prb_blob, rt_prf_blob, rt_prc_blob
extern rt_sip_blob, rt_alc_blob, rt_prq_blob
section .bss
out_buffer:       resb 131072
out_idx:          resq 1
jump_patch_stack: resq 32
jump_patch_depth: resq 1
end_jump_stack:   resq 32
end_jump_depth:   resq 1
chain_base_stack: resq 32
chain_base_depth: resq 1
break_jump_stack: resq 32
break_jump_depth: resq 1
break_base_stack: resq 32
break_base_depth: resq 1
cont_base_stack:  resq 32
cont_base_depth:  resq 1
prot_jmp_idx:     resq 1
prot_jmp_live:    resb 1
section .text
; ── internal emit helpers ────────────────────────────────────────────────────
emit_b: push rbx; push rcx; mov rcx,[out_idx]; lea rbx,[out_buffer]; mov [rbx+rcx],al; inc qword [out_idx]; pop rcx; pop rbx; ret
emit_d: push rbx; push rcx; mov rcx,[out_idx]; lea rbx,[out_buffer]; mov [rbx+rcx],eax; add qword [out_idx],4; pop rcx; pop rbx; ret
emit_q: push rbx; push rcx; mov rcx,[out_idx]; lea rbx,[out_buffer]; mov [rbx+rcx],rax; add qword [out_idx],8; pop rcx; pop rbx; ret
emit_blob:
    push rdi; push rsi; push rcx; push rdx
    mov rdx,[out_idx]; lea rdi,[out_buffer]; add rdi,rdx; cld; rep movsb
    pop rdx; pop rcx; pop rsi; pop rdi; add qword [out_idx],rcx; ret
get_var_va: mov rax,rdi; shl rax,6; add rax,VAR_STORAGE_BASE; ret
; ── headers / init ───────────────────────────────────────────────────────────
codegen_write_headers:
    mov qword [out_idx],0; lea rsi,[elf_header]; lea rdi,[out_buffer]; mov rcx,64; cld; rep movsb
    lea rsi,[program_header]; mov rcx,56; rep movsb; mov qword [out_idx],120; ret
codegen_init:
    mov al,0xE9; call emit_b; mov eax,RT_TOTAL_SIZE; call emit_d
    lea rsi,[rt_pri_blob]; mov rcx,RT_PRI_SIZE; call emit_blob
    lea rsi,[rt_prs_blob]; mov rcx,RT_PRS_SIZE; call emit_blob
    lea rsi,[rt_prb_blob]; mov rcx,RT_PRB_SIZE; call emit_blob
    lea rsi,[rt_prf_blob]; mov rcx,RT_PRF_SIZE; call emit_blob
    lea rsi,[rt_prc_blob]; mov rcx,RT_PRC_SIZE; call emit_blob
    lea rsi,[rt_sip_blob]; mov rcx,RT_SIP_SIZE; call emit_blob
    lea rsi,[rt_alc_blob]; mov rcx,RT_ALC_SIZE; call emit_blob
    lea rsi,[rt_prq_blob]; mov rcx,RT_PRQ_SIZE; call emit_blob; ret
codegen_finish:
    mov al,0x48; call emit_b; mov al,0xC7; call emit_b; mov al,0xC0; call emit_b
    mov eax,60; call emit_d
    mov al,0x48; call emit_b; mov al,0x31; call emit_b; mov al,0xFF; call emit_b
    mov al,0x0F; call emit_b; mov al,0x05; call emit_b
    mov rax,[out_idx]; lea rcx,[out_buffer]
    mov [rcx+64+32],rax; mov qword [rcx+64+40],0x80000; ret
; ── output helpers ───────────────────────────────────────────────────────────
codegen_output_const:
    mov al,0xBF; call emit_b; mov eax,edi; call emit_d
    mov al,0xE8; call emit_b
    mov rax,LOAD_BASE+RT_PRI_OFFSET; mov rdx,[out_idx]; add rdx,4; add rdx,LOAD_BASE; sub rax,rdx; call emit_d; ret
codegen_output_typed:
    push rsi; push rdi
    mov al,0x48; call emit_b; mov al,0x8B; call emit_b; mov al,0x3C; call emit_b; mov al,0x25; call emit_b
    pop rdi; push rdi; call get_var_va; call emit_d; pop rdi; pop rsi
    mov al,0xE8; call emit_b
    mov rax,RT_PRI_OFFSET
    cmp sil,TYPE_STR;     je .s
    cmp sil,TYPE_BOOL;    je .b
    cmp sil,TYPE_FLOAT;   je .f
    cmp sil,TYPE_COMPLEX; je .c
    jmp .d
.s: mov rax,RT_PRS_OFFSET; jmp .d
.b: mov rax,RT_PRB_OFFSET; jmp .d
.f: mov rax,RT_PRF_OFFSET; jmp .d
.c: mov rax,RT_PRC_OFFSET
.d: add rax,LOAD_BASE; mov rdx,[out_idx]; add rdx,4; add rdx,LOAD_BASE; sub rax,rdx; call emit_d; ret
codegen_output_rax:
    ; rdi=type: emit mov rdi,rax then call rt_pXX
    push rdi
    mov al,0x48; call emit_b; mov al,0x89; call emit_b; mov al,0xC7; call emit_b
    pop rsi
    mov al,0xE8; call emit_b
    mov rax,RT_PRI_OFFSET
    cmp sil,TYPE_STR;     je .s
    cmp sil,TYPE_BOOL;    je .b
    cmp sil,TYPE_FLOAT;   je .f
    cmp sil,TYPE_COMPLEX; je .c
    jmp .d
.s: mov rax,RT_PRS_OFFSET; jmp .d
.b: mov rax,RT_PRB_OFFSET; jmp .d
.f: mov rax,RT_PRF_OFFSET; jmp .d
.c: mov rax,RT_PRC_OFFSET
.d: add rax,LOAD_BASE; mov rdx,[out_idx]; add rdx,4; add rdx,LOAD_BASE; sub rax,rdx; call emit_d; ret
; ── assign / bool ────────────────────────────────────────────────────────────
codegen_emit_assign_var:
    push rdi
    mov al,0x48; call emit_b; mov al,0xB8; call emit_b; mov rax,rsi; call emit_q
    mov al,0x48; call emit_b; mov al,0x89; call emit_b; mov al,0x04; call emit_b; mov al,0x25; call emit_b
    pop rdi; call get_var_va; call emit_d; ret
codegen_emit_unknown_bool:
    push rdi
    mov al,0x0F; call emit_b; mov al,0xC7; call emit_b; mov al,0xF0; call emit_b
    mov al,0x83; call emit_b; mov al,0xE0; call emit_b; mov al,0x01; call emit_b
    mov al,0x89; call emit_b; mov al,0x04; call emit_b; mov al,0x25; call emit_b
    pop rdi; call get_var_va; call emit_d; ret
codegen_emit_cmp_var_jne:
    push rsi; push rdi
    mov al,0x48; call emit_b; mov al,0x81; call emit_b; mov al,0x3C; call emit_b; mov al,0x25; call emit_b
    pop rdi; call get_var_va; call emit_d
    pop rsi; mov eax,esi; call emit_d
    mov al,0x0F; call emit_b; mov al,0x85; call emit_b
    mov rax,[out_idx]; mov rbx,[jump_patch_depth]; lea rcx,[jump_patch_stack]
    mov [rcx+rbx*8],rax; inc qword [jump_patch_depth]; xor eax,eax; call emit_d; ret
; ── jump / chain patching ────────────────────────────────────────────────────
codegen_patch_jump:
    dec qword [jump_patch_depth]; mov rbx,[jump_patch_depth]; lea rcx,[jump_patch_stack]
    mov rdx,[rcx+rbx*8]; mov rax,[out_idx]; sub rax,rdx; sub rax,4
    lea rcx,[out_buffer]; mov [rcx+rdx],eax; ret
codegen_save_chain_base:
    mov rax,[end_jump_depth]; mov rbx,[chain_base_depth]; lea rcx,[chain_base_stack]
    mov [rcx+rbx*8],rax; inc qword [chain_base_depth]; ret
codegen_emit_jmp_end:
    mov al,0xE9; call emit_b
    mov rax,[out_idx]; mov rbx,[end_jump_depth]; lea rcx,[end_jump_stack]
    mov [rcx+rbx*8],rax; inc qword [end_jump_depth]; xor eax,eax; call emit_d; ret
codegen_patch_chain_end:
    dec qword [chain_base_depth]; mov rbx,[chain_base_depth]; lea rcx,[chain_base_stack]; mov rsi,[rcx+rbx*8]
.l: cmp rsi,[end_jump_depth]; jae .done
    lea rcx,[end_jump_stack]; mov rdx,[rcx+rsi*8]; mov rax,[out_idx]; sub rax,rdx; sub rax,4
    lea rcx,[out_buffer]; mov [rcx+rdx],eax; inc rsi; jmp .l
.done: mov [end_jump_depth],rsi; ret
; ── protocol jump frame ───────────────────────────────────────────────────────
codegen_begin_protos:
    cmp byte [prot_jmp_live],0; jne .done
    mov al,0xE9; call emit_b; mov rax,[out_idx]; mov [prot_jmp_idx],rax; xor eax,eax; call emit_d
    mov byte [prot_jmp_live],1
.done: ret
codegen_end_protos:
    cmp byte [prot_jmp_live],0; je .done
    mov rdx,[prot_jmp_idx]; mov rax,[out_idx]; sub rax,rdx; sub rax,4
    lea rcx,[out_buffer]; mov [rcx+rdx],eax; mov byte [prot_jmp_live],0
.done: ret
; ── for loop (static bounds) ─────────────────────────────────────────────────
codegen_emit_for_start:
    push rbx; push r12; push r13
    mov r12,rdi; mov r13,rdx
    mov rax,[break_jump_depth]; mov rbx,[break_base_depth]; lea rcx,[break_base_stack]
    mov [rcx+rbx*8],rax; inc qword [break_base_depth]
    ; init loop var
    mov al,0x48; call emit_b; mov al,0xB8; call emit_b; mov rax,rsi; call emit_q
    mov al,0x48; call emit_b; mov al,0x89; call emit_b; mov al,0x04; call emit_b; mov al,0x25; call emit_b
    mov rdi,r12; call get_var_va; call emit_d
    mov rbx,[out_idx]
    ; condition check
    mov al,0x48; call emit_b; mov al,0x8B; call emit_b; mov al,0x04; call emit_b; mov al,0x25; call emit_b
    mov rdi,r12; call get_var_va; call emit_d
    mov al,0x48; call emit_b; mov al,0x3D; call emit_b; mov rax,r13; call emit_d
    mov al,0x0F; call emit_b; mov al,0x8D; call emit_b
    mov rax,[out_idx]; mov r13,[jump_patch_depth]; lea rcx,[jump_patch_stack]
    mov [rcx+r13*8],rax; inc qword [jump_patch_depth]; xor eax,eax; call emit_d
    ; save continue target
    mov rdi,rbx; call codegen_push_cont
    mov rax,rbx; pop r13; pop r12; pop rbx; ret
codegen_emit_for_end:
    push rbx; push r12; push r13
    mov r12,rdi; mov r13,rsi
    mov al,0x48; call emit_b; mov al,0x8B; call emit_b; mov al,0x04; call emit_b; mov al,0x25; call emit_b
    mov rdi,r13; call get_var_va; call emit_d
    mov al,0x48; call emit_b; mov al,0xFF; call emit_b; mov al,0xC0; call emit_b
    mov al,0x48; call emit_b; mov al,0x89; call emit_b; mov al,0x04; call emit_b; mov al,0x25; call emit_b
    mov rdi,r13; call get_var_va; call emit_d
    mov al,0xE9; call emit_b; mov rax,r12; add rax,LOAD_BASE; mov rdx,[out_idx]; add rdx,4; add rdx,LOAD_BASE; sub rax,rdx; call emit_d
    call codegen_patch_jump; call codegen_patch_breaks; call codegen_pop_cont
    pop r13; pop r12; pop rbx; ret
; ── for loop (dynamic bounds) ────────────────────────────────────────────────
codegen_emit_for_start_dyn:
    ; rdi=loop_var_idx rsi=end_var_idx
    push rbx; push r12; push r13; push r14
    mov r12,rdi; mov r13,rsi
    mov rax,[break_jump_depth]; mov r14,[break_base_depth]; lea rcx,[break_base_stack]
    mov [rcx+r14*8],rax; inc qword [break_base_depth]
    mov rbx,[out_idx]
    ; emit: mov rax,[loop_var]
    mov al,0x48; call emit_b; mov al,0x8B; call emit_b; mov al,0x04; call emit_b; mov al,0x25; call emit_b
    mov rdi,r12; call get_var_va; call emit_d
    ; emit: cmp rax,[end_var]
    mov al,0x48; call emit_b; mov al,0x3B; call emit_b; mov al,0x04; call emit_b; mov al,0x25; call emit_b
    mov rdi,r13; call get_var_va; call emit_d
    ; emit: jge .exit
    mov al,0x0F; call emit_b; mov al,0x8D; call emit_b
    mov rax,[out_idx]; mov r14,[jump_patch_depth]; lea rcx,[jump_patch_stack]
    mov [rcx+r14*8],rax; inc qword [jump_patch_depth]; xor eax,eax; call emit_d
    mov rdi,rbx; call codegen_push_cont
    mov rax,rbx; pop r14; pop r13; pop r12; pop rbx; ret
; ── while loop ───────────────────────────────────────────────────────────────
codegen_emit_while_start:
    ; legacy stub — no-op (while now saves its own PC)
    ret
codegen_emit_while_end:
    ; rdi = loop_start_pc
    mov al,0xE9; call emit_b
    mov rax,rdi; add rax,LOAD_BASE; mov rdx,[out_idx]; add rdx,4; add rdx,LOAD_BASE; sub rax,rdx; call emit_d
    call codegen_patch_jump; call codegen_patch_breaks; call codegen_pop_cont; ret
codegen_emit_loop_base:
    mov rax,[break_jump_depth]; mov rbx,[break_base_depth]; lea rcx,[break_base_stack]
    mov [rcx+rbx*8],rax; inc qword [break_base_depth]; ret
; ── break / continue ─────────────────────────────────────────────────────────
codegen_emit_break:
    mov al,0xE9; call emit_b
    mov rax,[out_idx]; mov rbx,[break_jump_depth]; lea rcx,[break_jump_stack]
    mov [rcx+rbx*8],rax; inc qword [break_jump_depth]; xor eax,eax; call emit_d; ret
codegen_patch_breaks:
    dec qword [break_base_depth]; mov rbx,[break_base_depth]; lea rcx,[break_base_stack]; mov rsi,[rcx+rbx*8]
.l: cmp rsi,[break_jump_depth]; jae .done
    lea rcx,[break_jump_stack]; mov rdx,[rcx+rsi*8]; mov rax,[out_idx]; sub rax,rdx; sub rax,4
    lea rcx,[out_buffer]; mov [rcx+rdx],eax; inc rsi; jmp .l
.done: mov [break_jump_depth],rsi; ret
codegen_push_cont:
    mov rax,[cont_base_depth]; lea rcx,[cont_base_stack]; mov [rcx+rax*8],rdi
    inc qword [cont_base_depth]; ret
codegen_pop_cont:
    cmp qword [cont_base_depth],0; je .done; dec qword [cont_base_depth]
.done: ret
codegen_emit_skip:
    ; emit jmp to cont_base_stack top
    mov rax,[cont_base_depth]; test rax,rax; jz .done
    dec rax; lea rcx,[cont_base_stack]; mov rdi,[rcx+rax*8]
    mov al,0xE9; call emit_b
    mov rax,rdi; add rax,LOAD_BASE; mov rdx,[out_idx]; add rdx,4; add rdx,LOAD_BASE; sub rax,rdx; call emit_d
.done: ret
; ── protocol helpers ─────────────────────────────────────────────────────────
codegen_emit_ret:
    mov al,0xC3; call emit_b; ret
codegen_emit_mov_eax_imm32:
    mov al,0xB8; call emit_b; mov eax,edi; call emit_d; ret
codegen_emit_call_prot:
    mov al,0xE8; call emit_b
    mov rax,rdi; add rax,LOAD_BASE; mov rdx,[out_idx]; add rdx,4; add rdx,LOAD_BASE; sub rax,rdx; call emit_d; ret
codegen_emit_arg_pops:
    ; rdi=count; emit pop instructions in order: pop_regs[count-1..0]
    push rbx; push rcx
    mov rbx,rdi; mov rcx,rbx; cmp rcx,4; jle .ok; mov rcx,4
.ok: test rcx,rcx; jz .done
    dec rcx
    lea rax,[rel .pop_bytes]; movzx eax,byte [rax+rcx]; call emit_b
    jmp .ok
.done: pop rcx; pop rbx; ret
.pop_bytes: db 0x5F, 0x5E, 0x5A, 0x59   ; pop rdi, rsi, rdx, rcx
; ── memory manager ───────────────────────────────────────────────────────────
codegen_emit_mm_switch:
    mov al,0x48; call emit_b; mov al,0xC7; call emit_b; mov al,0x05; call emit_b
    mov rax,LOAD_BASE+RT_ALC_OFFSET+4096-8; mov rdx,[out_idx]; add rdx,4; sub rax,rdx; call emit_d
    mov eax,edi; call emit_d; ret
; ── expression emit helpers ──────────────────────────────────────────────────
codegen_emit_push_rax:
    mov al,0x50; call emit_b; ret
codegen_emit_pop_rbx:
    mov al,0x5B; call emit_b; ret
codegen_emit_mov_rax_var:
    ; rdi=var_idx emit: mov rax,[var_addr]
    push rdi
    mov al,0x48; call emit_b; mov al,0x8B; call emit_b; mov al,0x04; call emit_b; mov al,0x25; call emit_b
    pop rdi; call get_var_va; call emit_d; ret
codegen_emit_store_rax_to_var:
    ; rdi=var_idx emit: mov [var_addr],rax
    push rdi
    mov al,0x48; call emit_b; mov al,0x89; call emit_b; mov al,0x04; call emit_b; mov al,0x25; call emit_b
    pop rdi; call get_var_va; call emit_d; ret
codegen_emit_rdrand_rax:
    ; rdrand eax; and eax,1
    mov al,0x0F; call emit_b; mov al,0xC7; call emit_b; mov al,0xF0; call emit_b
    mov al,0x83; call emit_b; mov al,0xE0; call emit_b; mov al,0x01; call emit_b; ret
codegen_emit_neg_rax:
    mov al,0x48; call emit_b; mov al,0xF7; call emit_b; mov al,0xD8; call emit_b; ret
codegen_emit_not_rax:
    ; xor rax,1
    mov al,0x48; call emit_b; mov al,0x83; call emit_b; mov al,0xF0; call emit_b; mov al,0x01; call emit_b; ret
codegen_emit_bitwise_not_rax:
    mov al,0x48; call emit_b; mov al,0xF7; call emit_b; mov al,0xD0; call emit_b; ret
codegen_emit_add_rax_rbx:
    ; add rax,rbx
    mov al,0x48; call emit_b; mov al,0x01; call emit_b; mov al,0xD8; call emit_b; ret
codegen_emit_sub_rax_rbx:
    ; rbx-rax: neg rax; add rax,rbx
    mov al,0x48; call emit_b; mov al,0xF7; call emit_b; mov al,0xD8; call emit_b
    mov al,0x48; call emit_b; mov al,0x01; call emit_b; mov al,0xD8; call emit_b; ret
codegen_emit_imul_rax_rbx:
    ; imul rax,rbx
    mov al,0x48; call emit_b; mov al,0x0F; call emit_b; mov al,0xAF; call emit_b; mov al,0xC3; call emit_b; ret
codegen_emit_idiv_rbx_by_rax:
    ; rbx/rax → rax: mov rcx,rax; mov rax,rbx; cqo; idiv rcx
    mov al,0x48; call emit_b; mov al,0x89; call emit_b; mov al,0xC1; call emit_b
    mov al,0x48; call emit_b; mov al,0x89; call emit_b; mov al,0xD8; call emit_b
    mov al,0x48; call emit_b; mov al,0x99; call emit_b
    mov al,0x48; call emit_b; mov al,0xF7; call emit_b; mov al,0xF9; call emit_b; ret
codegen_emit_imod_rbx_by_rax:
    ; rbx%rax → rax (via rdx after idiv)
    mov al,0x48; call emit_b; mov al,0x89; call emit_b; mov al,0xC1; call emit_b
    mov al,0x48; call emit_b; mov al,0x89; call emit_b; mov al,0xD8; call emit_b
    mov al,0x48; call emit_b; mov al,0x99; call emit_b
    mov al,0x48; call emit_b; mov al,0xF7; call emit_b; mov al,0xF9; call emit_b
    mov al,0x48; call emit_b; mov al,0x89; call emit_b; mov al,0xD0; call emit_b; ret
codegen_emit_cmp_rbx_rax_setcc:
    ; rdi=setCC byte; emit: cmp rbx,rax; setCC al; movzx rax,al
    push rdi
    mov al,0x48; call emit_b; mov al,0x39; call emit_b; mov al,0xC3; call emit_b
    mov al,0x0F; call emit_b; pop rax; call emit_b; mov al,0xC0; call emit_b
    mov al,0x48; call emit_b; mov al,0x0F; call emit_b; mov al,0xB6; call emit_b; mov al,0xC0; call emit_b; ret
codegen_emit_test_rax_jz:
    ; emit: test rax,rax; jz placeholder (0F 84)
    mov al,0x48; call emit_b; mov al,0x85; call emit_b; mov al,0xC0; call emit_b
    mov al,0x0F; call emit_b; mov al,0x84; call emit_b
    mov rax,[out_idx]; mov rbx,[jump_patch_depth]; lea rcx,[jump_patch_stack]
    mov [rcx+rbx*8],rax; inc qword [jump_patch_depth]; xor eax,eax; call emit_d; ret
; ── float emit ───────────────────────────────────────────────────────────────
; All float ops: rax=rhs bits, rbx=lhs bits → movq xmm1,rax; movq xmm0,rbx; op; movq rax,xmm0
%macro FLOAT_OP 1
    mov al,0x66; call emit_b; mov al,0x48; call emit_b; mov al,0x0F; call emit_b; mov al,0x6E; call emit_b; mov al,0xC8; call emit_b
    mov al,0x66; call emit_b; mov al,0x48; call emit_b; mov al,0x0F; call emit_b; mov al,0x6E; call emit_b; mov al,0xC3; call emit_b
    mov al,0xF2; call emit_b; mov al,0x0F; call emit_b; mov al,%1; call emit_b; mov al,0xC1; call emit_b
    mov al,0x66; call emit_b; mov al,0x48; call emit_b; mov al,0x0F; call emit_b; mov al,0x7E; call emit_b; mov al,0xC0; call emit_b
%endmacro
codegen_emit_addsd_rax_rbx: FLOAT_OP 0x58; ret
codegen_emit_subsd_rax_rbx: FLOAT_OP 0x5C; ret
codegen_emit_mulsd_rax_rbx: FLOAT_OP 0x59; ret
codegen_emit_divsd_rax_rbx: FLOAT_OP 0x5E; ret
codegen_emit_cvttsd2si_rax:
    ; movq xmm0,rax; cvttsd2si rax,xmm0
    mov al,0x66; call emit_b; mov al,0x48; call emit_b; mov al,0x0F; call emit_b; mov al,0x6E; call emit_b; mov al,0xC0; call emit_b
    mov al,0xF2; call emit_b; mov al,0x48; call emit_b; mov al,0x0F; call emit_b; mov al,0x2C; call emit_b; mov al,0xC0; call emit_b; ret
codegen_emit_cvtsi2sd_rax:
    ; cvtsi2sd xmm0,rax; movq rax,xmm0
    mov al,0xF2; call emit_b; mov al,0x48; call emit_b; mov al,0x0F; call emit_b; mov al,0x2A; call emit_b; mov al,0xC0; call emit_b
    mov al,0x66; call emit_b; mov al,0x48; call emit_b; mov al,0x0F; call emit_b; mov al,0x7E; call emit_b; mov al,0xC0; call emit_b; ret
; ── bitwise emit ─────────────────────────────────────────────────────────────
codegen_emit_bitwise_and_rax_rbx:
    mov al,0x48; call emit_b; mov al,0x21; call emit_b; mov al,0xD8; call emit_b; ret
codegen_emit_bitwise_or_rax_rbx:
    mov al,0x48; call emit_b; mov al,0x09; call emit_b; mov al,0xD8; call emit_b; ret
codegen_emit_bitwise_xor_rax_rbx:
    mov al,0x48; call emit_b; mov al,0x31; call emit_b; mov al,0xD8; call emit_b; ret
codegen_emit_and_bool_rax_rbx:
    ; test rbx,rbx; setnz cl; test rax,rax; setnz al; and al,cl; movzx rax,al
    mov al,0x48; call emit_b; mov al,0x85; call emit_b; mov al,0xDB; call emit_b
    mov al,0x0F; call emit_b; mov al,0x95; call emit_b; mov al,0xC1; call emit_b
    mov al,0x48; call emit_b; mov al,0x85; call emit_b; mov al,0xC0; call emit_b
    mov al,0x0F; call emit_b; mov al,0x95; call emit_b; mov al,0xC0; call emit_b
    mov al,0x20; call emit_b; mov al,0xC8; call emit_b
    mov al,0x48; call emit_b; mov al,0x0F; call emit_b; mov al,0xB6; call emit_b; mov al,0xC0; call emit_b; ret
codegen_emit_or_bool_rax_rbx:
    ; or rax,rbx; setnz al; movzx rax,al
    mov al,0x48; call emit_b; mov al,0x09; call emit_b; mov al,0xD8; call emit_b
    mov al,0x0F; call emit_b; mov al,0x95; call emit_b; mov al,0xC0; call emit_b
    mov al,0x48; call emit_b; mov al,0x0F; call emit_b; mov al,0xB6; call emit_b; mov al,0xC0; call emit_b; ret
codegen_emit_shl_rax_by_rbx:
    ; mov cl,al; mov rax,rbx; shl rax,cl
    mov al,0x88; call emit_b; mov al,0xC1; call emit_b
    mov al,0x48; call emit_b; mov al,0x89; call emit_b; mov al,0xD8; call emit_b
    mov al,0x48; call emit_b; mov al,0xD3; call emit_b; mov al,0xE0; call emit_b; ret
codegen_emit_shr_rax_by_rbx:
    mov al,0x88; call emit_b; mov al,0xC1; call emit_b
    mov al,0x48; call emit_b; mov al,0x89; call emit_b; mov al,0xD8; call emit_b
    mov al,0x48; call emit_b; mov al,0xD3; call emit_b; mov al,0xE8; call emit_b; ret
; ── string / sequence / error ────────────────────────────────────────────────
codegen_emit_str_rax:
    ; rdi=str_ptr rsi=len: emit JMP-over + bytes + null + MOV rax,VA
    push rbx; push r12; push r13; push r14; push r15
    mov r12,rdi; mov r13,rsi
    mov al,0xE9; call emit_b
    mov rbx,[out_idx]; xor eax,eax; call emit_d
    mov r14,[out_idx]; add r14,LOAD_BASE
    xor r15,r15
.sl: cmp r15,r13; jge .sd
    movzx eax,byte [r12+r15]; call emit_b; inc r15; jmp .sl
.sd: xor eax,eax; call emit_b
    ; patch JMP rel32
    mov rdx,[out_idx]; sub rdx,rbx; sub rdx,4
    lea rax,[out_buffer]; mov [rax+rbx],edx
    ; emit: mov rax,r14
    mov al,0x48; call emit_b; mov al,0xB8; call emit_b; mov rax,r14; call emit_q
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret
codegen_emit_seq_alloc:
    ; rdi=var_idx: alloc seq (80 bytes), set cap=8 len=0, store ptr
    push rdi
    mov al,0xBF; call emit_b; mov eax,80; call emit_d
    mov al,0xE8; call emit_b
    mov rax,LOAD_BASE+RT_ALC_OFFSET; mov rdx,[out_idx]; add rdx,4; add rdx,LOAD_BASE; sub rax,rdx; call emit_d
    ; mov qword [rax],8
    mov al,0x48; call emit_b; mov al,0xC7; call emit_b; mov al,0x00; call emit_b; mov eax,8; call emit_d
    ; mov qword [rax+8],0
    mov al,0x48; call emit_b; mov al,0xC7; call emit_b; mov al,0x40; call emit_b; mov al,0x08; call emit_b; xor eax,eax; call emit_d
    ; mov [var_addr],rax
    mov al,0x48; call emit_b; mov al,0x89; call emit_b; mov al,0x04; call emit_b; mov al,0x25; call emit_b
    pop rdi; call get_var_va; call emit_d; ret
codegen_emit_seq_push:
    ; rdi=var_idx; value in rax: push rax;load ptr→rbx;load len→rcx;pop rax;store;inc len
    push rdi
    mov al,0x50; call emit_b   ; push rax (save value)
    mov al,0x48; call emit_b; mov al,0x8B; call emit_b; mov al,0x1C; call emit_b; mov al,0x25; call emit_b
    pop rdi; push rdi; call get_var_va; call emit_d  ; mov rbx,[ptr_addr]
    mov al,0x48; call emit_b; mov al,0x8B; call emit_b; mov al,0x4B; call emit_b; mov al,0x08; call emit_b  ; mov rcx,[rbx+8]
    mov al,0x58; call emit_b   ; pop rax (restore value)
    ; mov [rbx+rcx*8+16],rax  → 48 89 44 CB 10
    mov al,0x48; call emit_b; mov al,0x89; call emit_b; mov al,0x44; call emit_b; mov al,0xCB; call emit_b; mov al,0x10; call emit_b
    ; inc qword [rbx+8] → 48 FF 43 08
    mov al,0x48; call emit_b; mov al,0xFF; call emit_b; mov al,0x43; call emit_b; mov al,0x08; call emit_b
    pop rdi; ret
codegen_emit_seq_pop_rax:
    ; rdi=var_idx: dec len, load last element → rax
    push rdi
    mov al,0x48; call emit_b; mov al,0x8B; call emit_b; mov al,0x1C; call emit_b; mov al,0x25; call emit_b
    pop rdi; push rdi; call get_var_va; call emit_d  ; mov rbx,[ptr_addr]
    ; dec qword [rbx+8] → 48 FF 4B 08
    mov al,0x48; call emit_b; mov al,0xFF; call emit_b; mov al,0x4B; call emit_b; mov al,0x08; call emit_b
    ; mov rcx,[rbx+8] → 48 8B 4B 08
    mov al,0x48; call emit_b; mov al,0x8B; call emit_b; mov al,0x4B; call emit_b; mov al,0x08; call emit_b
    ; mov rax,[rbx+rcx*8+16] → 48 8B 44 CB 10
    mov al,0x48; call emit_b; mov al,0x8B; call emit_b; mov al,0x44; call emit_b; mov al,0xCB; call emit_b; mov al,0x10; call emit_b
    pop rdi; ret
codegen_emit_seq_len_rax:
    ; rdi=var_idx: mov rax,[ptr_addr]; mov rax,[rax+8]
    push rdi
    mov al,0x48; call emit_b; mov al,0x8B; call emit_b; mov al,0x04; call emit_b; mov al,0x25; call emit_b
    pop rdi; push rdi; call get_var_va; call emit_d
    ; mov rax,[rax+8] → 48 8B 40 08
    mov al,0x48; call emit_b; mov al,0x8B; call emit_b; mov al,0x40; call emit_b; mov al,0x08; call emit_b
    pop rdi; ret
codegen_emit_mov_rdi_rax:
    ; mov rdi,rax → 48 89 C7
    mov al,0x48; call emit_b; mov al,0x89; call emit_b; mov al,0xC7; call emit_b; ret
codegen_emit_call_rt_err:
    ; call rt_err (first function in rt_prq_blob = RT_PRQ_OFFSET)
    mov al,0xE8; call emit_b
    mov rax,LOAD_BASE+RT_PRQ_OFFSET; mov rdx,[out_idx]; add rdx,4; add rdx,LOAD_BASE; sub rax,rdx; call emit_d; ret
""")

# ── parser.asm ────────────────────────────────────────────────────────────────
with open("parser/parser.asm","w") as f:
    f.write(r"""default rel
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
""")

# ── Makefile ──────────────────────────────────────────────────────────────────
with open("Makefile","w") as f:
    f.write(f"""NASM={NASM}
LD=ld
OBJS=main/main.o lexer/lexer.o parser/parser.o codegen/codegen.o headers/headers.o runtime/runtime.o
all: rexc
rexc: $(OBJS)
\t$(LD) $(OBJS) -o rexc
%.o: %.asm
\t$(NASM) -f elf64 -I include/ $< -o $@
clean:
\trm -f $(OBJS) rexc output
""")

print("Done. All source files regenerated.")
print(f"  RT_PRB_OFFSET = {RT_PRB_OFFSET}  RT_PRF_OFFSET = {RT_PRF_OFFSET}  RT_PRQ_OFFSET = {RT_PRQ_OFFSET}")
print(f"  CODE_START = {CODE_START}")
