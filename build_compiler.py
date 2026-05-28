import subprocess
import os

# --- Configuration ---
LOAD_BASE = 0x400000
HEADERS_SIZE = 120
VAR_STORAGE_BASE = 0x440000
VAR_ENTRY_SIZE = 64
VAR_MAX = 128

# Runtime sizes
RT_PRI_SIZE = 512
RT_PRS_SIZE = 512
RT_PRB_SIZE = 256
RT_PRF_SIZE = 512
RT_PRC_SIZE = 512
RT_SIP_SIZE = 1024
RT_ALC_SIZE = 4096
RT_PRQ_SIZE = 1024
RT_TOTAL_SIZE = RT_PRI_SIZE + RT_PRS_SIZE + RT_PRB_SIZE + RT_PRF_SIZE + RT_PRC_SIZE + RT_SIP_SIZE + RT_ALC_SIZE + RT_PRQ_SIZE

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
    with open("temp.asm", "w") as f:
        f.write("[bits 64]\ndefault rel\n" + asm_code)
    try:
        res = subprocess.run(["nasm", "-f", "bin", "temp.asm", "-o", "temp.bin"], capture_output=True)
        if res.returncode != 0:
            print(f"NASM Error for {name}:\n{res.stderr.decode()}")
            raise Exception("NASM failed")
        with open("temp.bin", "rb") as f: return f.read()
    finally:
        if os.path.exists("temp.asm"): os.remove("temp.asm")
        if os.path.exists("temp.bin"): os.remove("temp.bin")

# --- Runtime Assembly Blobs ---
rt_pri_asm = r"""
    push rbp; mov rbp, rsp; push rax; push rbx; push rcx; push rdx; push rsi; push rdi
    sub rsp, 64; mov rax, rdi; test rax, rax; jns .pos; neg rax
    mov byte [rsp+63], '-'; mov rax, 1; mov rdi, 1; lea rsi, [rsp+63]; mov rdx, 1; syscall; mov rax, [rbp-56]; neg rax
.pos:
    lea rdi, [rsp+62]; mov byte [rdi], 10; mov rcx, 1; mov rbx, 10
.l1: xor rdx, rdx; div rbx; add dl, '0'; dec rdi; mov [rdi], dl; inc rcx; test rax, rax; jnz .l1
    mov rax, 1; mov rsi, rdi; mov rdx, rcx; mov rdi, 1; syscall; add rsp, 64
    pop rdi; pop rsi; pop rdx; pop rcx; pop rbx; pop rax; leave; ret
"""
rt_prs_asm = r"""
    push rbp; mov rbp, rsp; push rax; push rdx; push rsi; push rdi; mov rsi, rdi; xor rdx, rdx
.l1: cmp byte [rsi+rdx], 0; je .d1; inc rdx; jmp .l1
.d1: test rdx, rdx; jz .nl; mov rax, 1; mov rdi, 1; syscall
.nl: sub rsp, 16; mov byte [rsp], 10; mov rax, 1; mov rdi, 1; mov rsi, rsp; mov rdx, 1; syscall
    add rsp, 16; pop rdi; pop rsi; pop rdx; pop rax; leave; ret
"""
rt_prc_asm = r"""
    push rbp; mov rbp, rsp; push rbx; push r12; push r13; push r14; push r15
    mov r12, rdi; mov r13, rsi; xor r14, r14; xor r15, r15
.l1: cmp byte [r12+r14], 0; je .l2; inc r14; jmp .l1
.l2: cmp byte [r13+r15], 0; je .alloc; inc r15; jmp .l2
.alloc:
    lea rdi, [r14+r15+1]; mov rax, 0x400000 + 120 + 5 + 512 + 512 + 256 + 512 + 512 + 1024; call rax
    mov rbx, rax; mov rdi, rax; mov rsi, r12; mov rcx, r14; cld; rep movsb
    mov rsi, r13; mov rcx, r15; rep movsb; mov byte [rdi], 0; mov rax, rbx
    pop r15; pop r14; pop r13; pop r12; pop rbx; leave; ret
"""
rt_alc_asm = r"""
    jmp .dispatch
.arena:
    push rbp; mov rbp, rsp; push rbx
    mov rax, [rel .ap]; test rax, rax; jnz .aa
    mov rax, 9; xor rdi, rdi; mov rsi, 0x100000; mov rdx, 3; mov r10, 34; mov r8, -1; xor r9, r9; syscall; mov [rel .ap], rax
.aa:
    mov rax, [rel .ap]; add rax, [rel .ao]; add [rel .ao], rdi; pop rbx; leave; ret
.pool:
    push rbp; mov rbp, rsp; push rbx
    mov rax, [rel .pp]; test rax, rax; jnz .pa
    mov rax, 9; xor rdi, rdi; mov rsi, 0x10000; mov rdx, 3; mov r10, 34; mov r8, -1; xor r9, r9; syscall; mov [rel .pp], rax
.pa:
    mov rax, [rel .pp]; add rax, [rel .po]; add qword [rel .po], 64; pop rbx; leave; ret
.dispatch:
    mov rax, [rel .mode]; cmp rax, 1; je .pool; jmp .arena
.ap: dq 0
.ao: dq 0
.pp: dq 0
.po: dq 0
.mode: dq 0
"""
rt_sip_asm = r"""
    push rbp; mov rbp, rsp; push rbx; push r12; push r13; push r14; push r15
    mov r12, [rdx]; mov r13, [rdx+8]; mov r8, 0x736f6d6570736575; xor r8, r12; mov r9, 0x646f72616e646f6d; xor r9, r13
    mov r10, 0x6c7967656e657261; xor r10, r12; mov r11, 0x7465646279746573; xor r11, r13; mov rcx, rsi; shr rcx, 3; jz .f
.l: mov rax, [rdi]; xor r11, rax
%macro S 0
    add r8, r9; add r10, r11; rol r9, 13; rol r11, 16; xor r9, r8; xor r11, r10; rol r8, 32
    add r10, r9; add r8, r11; rol r9, 17; rol r11, 21; xor r9, r10; xor r11, r8; rol r10, 32
%endmacro
    S; S; xor r8, rax; add rdi, 8; dec rcx; jnz .l
.f: mov rax, rsi; shl rax, 56; xor r11, rax; S; S; xor r8, rax; xor r10, 0xff; S; S; S; S
    mov rax, r8; xor rax, r9; xor rax, r10; xor rax, r11; pop r15; pop r14; pop r13; pop r12; pop rbx; leave; ret
"""

raw_blobs = {
    "rt_pri": get_blob_bytes("rt_pri", rt_pri_asm),
    "rt_prs": get_blob_bytes("rt_prs", rt_prs_asm),
    "rt_prb": b"\xc3", "rt_prf": b"\xc3",
    "rt_prc": get_blob_bytes("rt_prc", rt_prc_asm),
    "rt_sip": get_blob_bytes("rt_sip", rt_sip_asm),
    "rt_alc": get_blob_bytes("rt_alc", rt_alc_asm),
    "rt_prq": b"\xc3",
}

with open("include/rex_defs.inc", "w") as f:
    f.write(f"""default rel\nTOK_EOF equ 0\nTOK_NEWLINE equ 1\nTOK_INDENT equ 2\nTOK_DEDENT equ 3\nTOK_IDENT equ 4\nTOK_INT_LIT equ 5\nTOK_TYPE_INT equ 6\nTOK_ASSIGN equ 7\nTOK_COLON equ 8\nTOK_OUTPUT equ 9\nTOK_IF equ 10\nTOK_FOR equ 11\nTOK_IN equ 12\nTOK_DOTDOT equ 13\nTOK_EQEQ equ 14\nTOK_ELSE equ 15\nTOK_ELIF equ 16\nTOK_WHILE equ 17\nTOK_PROT equ 18\nTOK_RETURN equ 19\nTOK_STOP equ 20\nTOK_AT equ 21\nTOK_TYPE_FLOAT equ 22\nTOK_FLOAT_LIT equ 23\nTOK_TYPE_COMPLEX equ 24\nTOK_COMPLEX_LIT equ 25\nTOK_TYPE_BOOL equ 26\nTOK_TRUE equ 27\nTOK_FALSE equ 28\nTOK_UNKNOWN equ 29\nTOK_TYPE_STR equ 30\nTOK_STR_LIT equ 31\nTOK_PLUS equ 32\nTOK_MINUS equ 33\nTOK_LBRACK equ 34\nTOK_RBRACK equ 35\nTOK_LBRACE equ 36\nTOK_RBRACE equ 37\nTOK_COMMA equ 38\nTOK_USE equ 39\nTOK_MM equ 40\nTOK_GC equ 41\nTYPE_INT equ 1\nTYPE_FLOAT equ 2\nTYPE_BOOL equ 3\nTYPE_COMPLEX equ 4\nTYPE_STR equ 5\nTYPE_SEQ equ 6\nVAR_ENTRY_SIZE equ {VAR_ENTRY_SIZE}\nVAR_MAX equ {VAR_MAX}\nVAR_STORAGE_BASE equ {VAR_STORAGE_BASE}\nLOAD_BASE equ {LOAD_BASE}\nHEADERS_SIZE equ {HEADERS_SIZE}\nRT_PRI_SIZE equ 512\nRT_PRS_SIZE equ 512\nRT_PRB_SIZE equ 256\nRT_PRF_SIZE equ 512\nRT_PRC_SIZE equ 512\nRT_SIP_SIZE equ 1024\nRT_ALC_SIZE equ 4096\nRT_PRQ_SIZE equ 1024\nRT_TOTAL_SIZE equ {RT_TOTAL_SIZE}\nRT_PRI_OFFSET equ {RT_PRI_OFFSET}\nRT_PRS_OFFSET equ {RT_PRS_OFFSET}\nRT_PRB_OFFSET equ {RT_PRB_OFFSET}\nRT_PRF_OFFSET equ {RT_PRF_OFFSET}\nRT_PRC_OFFSET equ {RT_PRC_OFFSET}\nRT_SIP_OFFSET equ {RT_SIP_OFFSET}\nRT_ALC_OFFSET equ {RT_ALC_OFFSET}\nRT_PRQ_OFFSET equ {RT_PRQ_OFFSET}\nCODE_START equ {CODE_START}\n""")

with open("runtime/runtime.asm", "w") as f:
    f.write('default rel\n%include "include/rex_defs.inc"\n')
    for name in raw_blobs: f.write(f"global {name}_blob\n")
    f.write("\nsection .data\n")
    for name, data in raw_blobs.items():
        f.write(f"{name}_blob:\n")
        for i in range(0, len(data), 12):
            f.write("    db " + ", ".join([f"0x{b:02x}" for b in data[i:i+12]]) + "\n")
        f.write(f"    times {name.upper()}_SIZE - ($ - {name}_blob) db 0x90\n")

with open("main/main.asm", "w") as f:
    f.write(r"""default rel
%include "include/rex_defs.inc"
global _start
extern lexer_init, lexer_next, parse_stmt, codegen_write_headers, codegen_init, codegen_finish
extern out_buffer, out_idx, out_name, tok_type
section .bss
src_buffer: resb 65536; src_len: resq 1; src_fd: resq 1; out_fd: resq 1
section .text
_start:
    mov rax, [rsp]; cmp rax, 2; jl .err
    mov rdi, [rsp+16]; mov rax, 2; xor rsi, rsi; xor rdx, rdx; syscall; test rax, rax; js .err
    mov [src_fd], rax; mov rdi, rax; mov rax, 0; lea rsi, [src_buffer]; mov rdx, 65536; syscall; mov [src_len], rax
    mov rax, 3; mov rdi, [src_fd]; syscall; call codegen_write_headers; call codegen_init
    lea rdi, [src_buffer]; mov rsi, [src_len]; call lexer_init; call lexer_next
.l: movzx eax, byte [tok_type]; cmp al, TOK_EOF; je .d; cmp al, TOK_NEWLINE; je .s; call parse_stmt; jmp .l
.s: call lexer_next; jmp .l
.d: call codegen_finish; mov rax, 87; lea rdi, [out_name]; syscall
    mov rax, 2; lea rdi, [out_name]; mov rsi, 0x41; mov rdx, 493; syscall; test rax, rax; js .err; mov [out_fd], rax
    mov rdi, rax; mov rax, 1; lea rsi, [out_buffer]; mov rdx, [out_idx]; syscall; mov rax, 3; mov rdi, [out_fd]; syscall
    mov rax, 60; xor rdi, rdi; syscall
.err: mov rax, 60; mov rdi, 1; syscall
""")

with open("headers/headers.asm", "w") as f:
    f.write(r"""default rel
%include "include/rex_defs.inc"
global elf_header, program_header, out_name
section .data
elf_header:
    db 0x7F, 'E', 'L', 'F', 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0
    dw 2; dw 0x3E; dd 1; dq LOAD_BASE + HEADERS_SIZE; dq 64; dq 0; dd 0; dw 64; dw 56; dw 1; dw 0; dw 0; dw 0
program_header:
    dd 1; dd 7; dq 0; dq LOAD_BASE; dq LOAD_BASE; dq 0x80000; dq 0x80000; dq 0x1000
out_name: db "output", 0
""")

with open("lexer/lexer.asm", "w") as f:
    f.write(r"""default rel
%include "include/rex_defs.inc"
global lexer_init, lexer_next, tok_type, tok_int, tok_ident
section .bss
lex_src: resq 1; lex_len: resq 1; lex_pos: resq 1; at_line_start: resb 1; indent_stack: resq 32; indent_depth: resq 1; pending_dedents: resq 1
tok_type: resb 1; tok_int: resq 1; tok_ident: resb 64
section .text
lexer_init: push rbp; mov rbp, rsp; mov [lex_src], rdi; mov [lex_len], rsi; mov qword [lex_pos], 0; mov byte [at_line_start], 1
    mov qword [indent_depth], 0; mov qword [pending_dedents], 0; mov qword [indent_stack], 0; leave; ret
lexer_next: push rbp; mov rbp, rsp; push rbx; push r12; push r13; push r14; push r15
.r: cmp qword [pending_dedents], 0; jle .n; dec qword [pending_dedents]; mov byte [tok_type], TOK_DEDENT; jmp .done
.n: cmp byte [at_line_start], 0; je .s; mov rcx, [lex_pos]; mov rdi, [lex_src]; xor rbx, rbx
.cs: cmp rcx, [lex_len]; jge .ie; movzx eax, byte [rdi+rcx]; cmp al, ' '; jne .cd; inc rbx; inc rcx; jmp .cs
.cd: cmp rcx, [lex_len]; jge .ie; movzx eax, byte [rdi+rcx]; cmp al, 0x0A; je .bl; mov [lex_pos], rcx; mov byte [at_line_start], 0
    mov rax, [indent_depth]; lea rcx, [indent_stack]; mov rdx, [rcx+rax*8]; cmp rbx, rdx; jg .mi; jl .li; jmp .s
.mi: inc qword [indent_depth]; mov rax, [indent_depth]; lea rcx, [indent_stack]; mov [rcx+rax*8], rbx; mov byte [tok_type], TOK_INDENT; jmp .done
.li: cmp qword [indent_depth], 0; jle .de; mov rax, [indent_depth]; lea rcx, [indent_stack]; mov rdx, [rcx+rax*8]; cmp rdx, rbx; jle .de
    dec qword [indent_depth]; inc qword [pending_dedents]; jmp .li
.de: dec qword [pending_dedents]; mov byte [tok_type], TOK_DEDENT; jmp .done
.bl: inc rcx; mov [lex_pos], rcx; jmp .r
.ie: mov byte [at_line_start], 0; mov [lex_pos], rcx; jmp .r
.s: mov rcx, [lex_pos]; mov rdi, [lex_src]
.sl: cmp rcx, [lex_len]; jge .ee; movzx eax, byte [rdi+rcx]; cmp al, ' '; je .sn; cmp al, 0x09; je .sn; jmp .sd
.sn: inc rcx; jmp .sl
.sd: mov [lex_pos], rcx; cmp rcx, [lex_len]; jge .ee; movzx eax, byte [rdi+rcx]; cmp al, 0x0A; je .enl; cmp al, '"'; je .pstr
    cmp al, '['; je .elb; cmp al, ']'; je .erb; cmp al, '{'; je .elc; cmp al, '}'; je .erc; cmp al, ','; je .ecm; cmp al, '_'; je .pid
    cmp al, 'a'; jl .cup; cmp al, 'z'; jle .pid
.cup: cmp al, 'A'; jl .cdi; cmp al, 'Z'; jle .pid
.cdi: cmp al, '0'; jl .csp; cmp al, '9'; jle .pin
.csp: cmp al, '='; je .eas; cmp al, ':'; je .eco; cmp al, '.'; je .cdd; cmp al, '@'; je .eat; cmp al, '+'; je .epl; cmp al, '-'; je .emi; inc qword [lex_pos]; jmp .r
.elb: inc qword [lex_pos]; mov byte [tok_type], TOK_LBRACK; jmp .done
.erb: inc qword [lex_pos]; mov byte [tok_type], TOK_RBRACK; jmp .done
.elc: inc qword [lex_pos]; mov byte [tok_type], TOK_LBRACE; jmp .done
.erc: inc qword [lex_pos]; mov byte [tok_type], TOK_RBRACE; jmp .done
.ecm: inc qword [lex_pos]; mov byte [tok_type], TOK_COMMA; jmp .done
.pstr: inc qword [lex_pos]; mov rcx, [lex_pos]; mov rdi, [lex_src]; lea rsi, [tok_ident]; xor rbx, rbx
.strl: cmp rcx, [lex_len]; jge .strd; movzx eax, byte [rdi+rcx]; cmp al, '"'; je .strq; mov [rsi+rbx], al; inc rbx; inc rcx; jmp .strl
.strq: inc rcx; .strd: mov byte [rsi+rbx], 0; mov [lex_pos], rcx; mov byte [tok_type], TOK_STR_LIT; jmp .done
.epl: inc qword [lex_pos]; mov byte [tok_type], TOK_PLUS; jmp .done
.emi: inc qword [lex_pos]; mov byte [tok_type], TOK_MINUS; jmp .done
.eat: inc qword [lex_pos]; mov byte [tok_type], TOK_AT; jmp .done
.ee: mov byte [tok_type], TOK_EOF; jmp .done
.enl: inc qword [lex_pos]; mov byte [at_line_start], 1; mov byte [tok_type], TOK_NEWLINE; jmp .done
.eas: mov rcx, [lex_pos]; inc rcx; cmp rcx, [lex_len]; jge .as; movzx eax, byte [rdi+rcx]; cmp al, '='; jne .as
    inc rcx; mov [lex_pos], rcx; mov byte [tok_type], TOK_EQEQ; jmp .done
.as: mov [lex_pos], rcx; mov byte [tok_type], TOK_ASSIGN; jmp .done
.eco: inc qword [lex_pos]; mov byte [tok_type], TOK_COLON; jmp .done
.cdd: mov rcx, [lex_pos]; inc rcx; cmp rcx, [lex_len]; jge .sch; movzx eax, byte [rdi+rcx]; cmp al, '.'; jne .sch
    add qword [lex_pos], 2; mov byte [tok_type], TOK_DOTDOT; jmp .done
.sch: inc qword [lex_pos]; jmp .r
.pid: mov rcx, [lex_pos]; mov rdi, [lex_src]; lea rsi, [tok_ident]; xor rbx, rbx
.id_l: cmp rbx, 63; jge .id_d; cmp rcx, [lex_len]; jge .id_d; movzx eax, byte [rdi+rcx]; cmp al, '_'; je .id_c; cmp al, 'a'; jl .id_up
    cmp al, 'z'; jle .id_c
.id_up: cmp al, 'A'; jl .id_di; cmp al, 'Z'; jle .id_c
.id_di: cmp al, '0'; jl .id_d; cmp al, '9'; jle .id_c; jmp .id_d
.id_c: mov [rsi+rbx], al; inc rbx; inc rcx; jmp .id_l
.id_d: mov byte [rsi+rbx], 0; mov [lex_pos], rcx; call lexer_classify; jmp .done
.pin: mov rcx, [lex_pos]; mov rdi, [lex_src]; xor rbx, rbx
.in_l: cmp rcx, [lex_len]; jge .in_d; movzx eax, byte [rdi+rcx]; cmp al, '0'; jl .in_f; cmp al, '9'; jg .in_f; sub al, '0'
    imul rbx, rbx, 10; movzx rax, al; add rbx, rax; inc rcx; jmp .in_l
.in_f: cmp al, '.'; jne .in_c; cvtsi2sd xmm0, rbx; inc rcx; mov r8, 10; cvtsi2sd xmm2, r8; movsd xmm1, xmm2
.fl_l: cmp rcx, [lex_len]; jge .fl_d; movzx eax, byte [rdi+rcx]; cmp al, '0'; jl .fl_d; cmp al, '9'; jg .fl_d; sub al, '0'
    cvtsi2sd xmm3, rax; divsd xmm3, xmm1; addsd xmm0, xmm3; mulsd xmm1, xmm2; inc rcx; jmp .fl_l
.fl_d: mov [lex_pos], rcx; movq [tok_int], xmm0; mov byte [tok_type], TOK_FLOAT_LIT; jmp .done
.in_c: cmp al, 'j'; jne .in_d; inc rcx; mov [lex_pos], rcx; mov [tok_int], rbx; mov byte [tok_type], TOK_COMPLEX_LIT; jmp .done
.in_d: mov [lex_pos], rcx; mov [tok_int], rbx; mov byte [tok_type], TOK_INT_LIT; jmp .done
.done: pop r15; pop r14; pop r13; pop r12; pop rbx; leave; ret

lexer_classify:
    mov eax, dword [tok_ident]; cmp eax, 0x6c6f6f62; je .kb; cmp eax, 0x616f6c66; jne .nf; cmp byte [tok_ident+4], 't'; je .kf
.nf: cmp eax, 0x706d6f63; jne .ncp; cmp dword [tok_ident+4], 0x78656c; je .kcp
.ncp: cmp eax, 0x00727473; je .ks; cmp eax, 0x65757274; je .kt; cmp eax, 0x736c6166; jne .nfa; cmp byte [tok_ident+4], 'e'; je .kfa
.nfa: cmp eax, 0x6e6b6e75; jne .nu; cmp dword [tok_ident+4], 0x6e776f; je .ku
.nu: cmp eax, 0x00746e69; je .ki; cmp eax, 0x00006669; je .kif; cmp eax, 0x00726f66; je .kfo; cmp eax, 0x00006e69; je .kin
    cmp eax, 0x6C696877; jne .nuse; cmp byte [tok_ident+4], 'e'; je .kwh
.nuse: cmp eax, 0x00657375; je .kuse; cmp eax, 0x00006d6d; je .kmm; cmp eax, 0x00006367; je .kgc
    cmp eax, 0x746F7270; je .kpr; cmp eax, 0x75746572; jne .nr; cmp byte [tok_ident+4], 'r'; jne .nr; cmp byte [tok_ident+5], 'n'; je .kr
.nr: cmp eax, 0x706F7473; je .kso; cmp eax, 0x65736C65; je .kel; cmp eax, 0x66696C65; je .kei; cmp eax, 0x7074756F; jne .kid
    cmp word [tok_ident+4], 0x7475; je .kou
.kid: mov byte [tok_type], TOK_IDENT; ret
.ki: mov byte [tok_type], TOK_TYPE_INT; ret
.kb: mov byte [tok_type], TOK_TYPE_BOOL; ret
.kf: mov byte [tok_type], TOK_TYPE_FLOAT; ret
.kcp: mov byte [tok_type], TOK_TYPE_COMPLEX; ret
.ks: mov byte [tok_type], TOK_TYPE_STR; ret
.kt: mov byte [tok_type], TOK_TRUE; ret
.kfa: mov byte [tok_type], TOK_FALSE; ret
.ku: mov byte [tok_type], TOK_UNKNOWN; ret
.kif: mov byte [tok_type], TOK_IF; ret
.kfo: mov byte [tok_type], TOK_FOR; ret
.kin: mov byte [tok_type], TOK_IN; ret
.kwh: mov byte [tok_type], TOK_WHILE; ret
.kuse: mov byte [tok_type], TOK_USE; ret
.kmm: mov byte [tok_type], TOK_MM; ret
.kgc: mov byte [tok_type], TOK_GC; ret
.kpr: mov byte [tok_type], TOK_PROT; ret
.kr: mov byte [tok_type], TOK_RETURN; ret
.kso: mov byte [tok_type], TOK_STOP; ret
.kel: mov byte [tok_type], TOK_ELSE; ret
.kei: mov byte [tok_type], TOK_ELIF; ret
.kou: mov byte [tok_type], TOK_OUTPUT; ret
""")

with open("parser/parser.asm", "w") as f:
    f.write(r"""default rel
%include "include/rex_defs.inc"
global parse_stmt
extern lexer_init, lexer_next, tok_type, tok_int, tok_ident
extern codegen_output_const, codegen_output_typed, codegen_patch_jump, codegen_save_chain_base, codegen_emit_jmp_end, codegen_patch_chain_end
extern codegen_begin_protos, codegen_end_protos, codegen_emit_for_start, codegen_emit_for_end, codegen_emit_while_start, codegen_emit_while_end
extern codegen_emit_break, codegen_patch_breaks, codegen_emit_ret, codegen_emit_mov_eax_imm32, codegen_emit_call_prot, codegen_emit_assign_var, codegen_emit_cmp_var_jne, codegen_emit_unknown_bool
extern codegen_emit_mm_switch, out_idx
section .bss
var_table: resb VAR_ENTRY_SIZE * VAR_MAX; var_count: resq 1; proto_table: resb 40 * 32; proto_count: resq 1; prot_body_depth: resq 1; saved_name: resb 64
section .data
err_id: db "error: expected identifier", 10; err_id_l equ $ - err_id
section .text
strcpy: push rbp; mov rbp, rsp; push rsi; push rdi
.l: movzx eax, byte [rsi]; mov [rdi], al; inc rsi; inc rdi; test al, al; jnz .l
    pop rdi; pop rsi; leave; ret
fatal: push rbp; mov rbp, rsp; mov r9, rdx; mov r8, rsi; mov rax, 1; mov rdi, 2; mov rsi, r8; mov rdx, r9; syscall; mov rax, 60; mov rdi, 1; syscall
var_find: push rbp; mov rbp, rsp; push rbx; push rcx; push rsi; push rdi; xor rcx, rcx
.l: cmp rcx, [var_count]; jge .nf; mov rax, rcx; imul rax, VAR_ENTRY_SIZE; lea rsi, [var_table]; add rsi, rax; mov rdi, [rbp-32]
.c: movzx eax, byte [rdi]; movzx edx, byte [rsi]; cmp al, dl; jne .next; test al, al; jz .match; inc rdi; inc rsi; jmp .c
.match: mov rax, rcx; jmp .done
.next: inc rcx; jmp .l
.nf: mov rax, -1
.done: pop rdi; pop rsi; pop rcx; pop rbx; leave; ret
var_add: push rbp; mov rbp, rsp; push rbx; push r12; push r13; push r14; push r15; mov r12, rdi; mov r13, rsi; mov r14b, dl; mov r15b, cl; mov rbx, [var_count]
    cmp rbx, VAR_MAX; jge .full; mov rax, rbx; imul rax, VAR_ENTRY_SIZE; lea rdi, [var_table]; add rdi, rax; push rdi; mov ecx, VAR_ENTRY_SIZE / 4; xor eax, eax; cld; rep stosd
    pop rdi; mov rsi, r12; call strcpy; mov rax, rbx; imul rax, VAR_ENTRY_SIZE; lea rdi, [var_table]; add rdi, rax; mov [rdi+32], r13; mov byte [rdi+40], r14b; mov byte [rdi+48], r15b; inc qword [var_count]
    mov rax, rbx; jmp .done
.full: mov rax, -1
.done: pop r15; pop r14; pop r13; pop r12; pop rbx; leave; ret
parse_stmt: push rbp; mov rbp, rsp; push rbx; push r12; push r13; push r14; push r15; movzx eax, byte [tok_type]
    cmp al, TOK_PROT; je .s1; cmp qword [prot_body_depth], 0; jne .s1; call codegen_end_protos; movzx eax, byte [tok_type]
.s1: cmp al, TOK_TYPE_INT; je .pi; cmp al, TOK_TYPE_FLOAT; je .pf; cmp al, TOK_TYPE_BOOL; je .pb; cmp al, TOK_TYPE_STR; je .ps
    cmp al, TOK_TYPE_COMPLEX; je .pc; cmp al, TOK_COLON; je .assign; cmp al, TOK_OUTPUT; je .out; cmp al, TOK_IF; je .if
    cmp al, TOK_FOR; je .for; cmp al, TOK_WHILE; je .while; cmp al, TOK_PROT; je .prot; cmp al, TOK_RETURN; je .ret
    cmp al, TOK_STOP; je .stop; cmp al, TOK_AT; je .at; cmp al, TOK_USE; je .use; call lexer_next; jmp .done
.pf: mov r15b, TYPE_FLOAT; jmp .pg
.pb: mov r15b, TYPE_BOOL; jmp .pg
.ps: mov r15b, TYPE_STR; jmp .pg
.pc: mov r15b, TYPE_COMPLEX; jmp .pg
.pi: mov r15b, TYPE_INT
.pg: call lexer_next; cmp byte [tok_type], TOK_IDENT; jne .err; lea rsi, [tok_ident]; lea rdi, [saved_name]; call strcpy; call lexer_next
    cmp byte [tok_type], TOK_ASSIGN; je .pinit; lea rdi, [saved_name]; xor rsi, rsi; mov dl, 0; mov cl, r15b; call var_add; jmp .done
.pinit: call lexer_next; movzx eax, byte [tok_type]; mov r11, [tok_int]; cmp al, TOK_TRUE; jne .nt; mov r11, 1; jmp .nu
.nt: cmp al, TOK_FALSE; jne .nf; mov r11, 0; jmp .nu
.nf: cmp al, TOK_UNKNOWN; jne .nu
.nu: lea rdi, [saved_name]; mov rsi, r11; mov dl, 1; mov cl, r15b; call var_add; mov r14, rax; mov rdi, r14; movzx eax, byte [tok_type]
    cmp al, TOK_UNKNOWN; je .gu; mov rsi, r11; call codegen_emit_assign_var; jmp .gd
.gu: call codegen_emit_unknown_bool
.gd: call lexer_next; jmp .done
.err: lea rsi, [err_id]; mov rdx, err_id_l; call fatal
.assign: call lexer_next; cmp byte [tok_type], TOK_IDENT; jne .done; sub rsp, 64; mov rdi, rsp; lea rsi, [tok_ident]; call strcpy; call lexer_next; call lexer_next
    mov r11, [tok_int]; movzx eax, byte [tok_type]; cmp al, TOK_TRUE; jne .ant; mov r11, 1
.ant: cmp al, TOK_FALSE; jne .anf; mov r11, 0
.anf: mov rdi, rsp; call var_find; cmp rax, -1; je .eas; mov r14, rax; imul rax, rax, VAR_ENTRY_SIZE; lea rcx, [var_table]; add rcx, rax; mov [rcx+32], r11
    mov rdi, r14; movzx eax, byte [tok_type]; cmp al, TOK_UNKNOWN; je .agu; mov rsi, r11; call codegen_emit_assign_var; jmp .ad
.agu: call codegen_emit_unknown_bool
.ad: call lexer_next
.eas: add rsp, 64; jmp .done
.out: call lexer_next; cmp byte [tok_type], TOK_INT_LIT; je .ol; cmp byte [tok_type], TOK_IDENT; jne .done
    sub rsp, 64; mov rdi, rsp; lea rsi, [tok_ident]; call strcpy; mov rdi, rsp; call var_find; cmp rax, -1; je .oer
    mov r14, rax; imul rax, rax, VAR_ENTRY_SIZE; lea rcx, [var_table]; add rcx, rax; mov rdi, r14; movzx esi, byte [rcx+48]; call codegen_output_typed; call lexer_next
.oer: add rsp, 64; jmp .done
.ol: mov rdi, [tok_int]; call codegen_output_const; call lexer_next; jmp .done
.if: call codegen_save_chain_base
.ifn: call lexer_next; sub rsp, 64; mov rdi, rsp; lea rsi, [tok_ident]; call strcpy; mov rdi, rsp; call var_find; cmp rax, -1; je .ife
    mov r14, rax; call lexer_next; call lexer_next; mov r11, [tok_int]; movzx eax, byte [tok_type]; cmp al, TOK_TRUE; jne .ifnt; mov r11, 1
.ifnt: cmp al, TOK_FALSE; jne .ifnf; mov r11, 0
.ifnf: mov rdi, r14; mov rsi, r11; call codegen_emit_cmp_var_jne; add rsp, 64; call lexer_next; call lexer_next; cmp byte [tok_type], TOK_NEWLINE; jne .ifnn; call lexer_next
.ifnn: cmp byte [tok_type], TOK_INDENT; jne .ifb; call lexer_next; mov r13, 1; jmp .ifbl
.ifb: xor r13, r13
.ifbl: movzx eax, byte [tok_type]; cmp al, TOK_EOF; je .ifen; cmp al, TOK_DEDENT; je .ifen; call parse_stmt; test r13, r13; jnz .ifbl
.ifen: test r13, r13; jz .ifad; cmp byte [tok_type], TOK_DEDENT; jne .ifad; call lexer_next
.ifad: movzx eax, byte [tok_type]; cmp al, TOK_ELIF; je .elif; cmp al, TOK_ELSE; je .else; call codegen_patch_jump; call codegen_patch_chain_end; jmp .done
.elif: call codegen_emit_jmp_end; call codegen_patch_jump; jmp .ifn
.else: call codegen_emit_jmp_end; call codegen_patch_jump; call lexer_next; call lexer_next; cmp byte [tok_type], TOK_NEWLINE; jne .elnn; call lexer_next
.elnn: cmp byte [tok_type], TOK_INDENT; jne .elb; call lexer_next; mov r13, 1; jmp .elbl
.elb: xor r13, r13
.elbl: movzx eax, byte [tok_type]; cmp al, TOK_EOF; je .elen; cmp al, TOK_DEDENT; je .elen; call parse_stmt; test r13, r13; jnz .elbl
.elen: test r13, r13; jz .eldo; cmp byte [tok_type], TOK_DEDENT; jne .eldo; call lexer_next
.eldo: call codegen_patch_chain_end; jmp .done
.ife: add rsp, 64; jmp .done
.for: call lexer_next; call lexer_next; sub rsp, 64; mov rdi, rsp; lea rsi, [tok_ident]; call strcpy; call lexer_next; call lexer_next; mov r12, [tok_int]
    call lexer_next; call lexer_next; mov r13, [tok_int]; lea rsi, [rsp]; lea rdi, [saved_name]; call strcpy; lea rdi, [saved_name]; mov rsi, r12; mov dl, 0; mov cl, TYPE_INT; call var_add
    mov r14, rax; mov rdi, r14; mov rsi, r12; mov rdx, r13; call codegen_emit_for_start; mov r15, rax; add rsp, 64; call lexer_next; call lexer_next
.forl: movzx eax, byte [tok_type]; cmp al, TOK_EOF; je .ford; cmp al, TOK_DEDENT; je .ford; call parse_stmt; jmp .forl
.ford: cmp byte [tok_type], TOK_DEDENT; jne .fornd; call lexer_next
.fornd: mov rdi, r15; mov rsi, r14; call codegen_emit_for_end; jmp .done
.while: call lexer_next; mov r15, [out_idx]; sub rsp, 64; mov rdi, rsp; lea rsi, [tok_ident]; call strcpy; mov rdi, rsp; call var_find; cmp rax, -1; je .wer
    mov r14, rax; call lexer_next; call lexer_next; mov r11, [tok_int]; mov rsi, r11; mov rdi, r14; call codegen_emit_cmp_var_jne; add rsp, 64; call lexer_next; call lexer_next
.whilel: movzx eax, byte [tok_type]; cmp al, TOK_EOF; je .whiled; cmp al, TOK_DEDENT; je .whiled; call parse_stmt; jmp .whilel
.whiled: cmp byte [tok_type], TOK_DEDENT; jne .whilend; call lexer_next
.whilend: mov rdi, r15; call codegen_emit_while_end; jmp .done
.wer: add rsp, 64; jmp .done
.prot: inc qword [prot_body_depth]; call codegen_begin_protos; call lexer_next; mov rax, [proto_count]; imul rax, 40; lea r13, [proto_table]; add r13, rax
    lea rsi, [tok_ident]; mov rdi, r13; call strcpy; mov rbx, [out_idx]; mov [r13+32], rbx; inc qword [proto_count]; call lexer_next; call lexer_next; call lexer_next; call lexer_next
.protl: movzx eax, byte [tok_type]; cmp al, TOK_EOF; je .protd; cmp al, TOK_DEDENT; je .protd; call parse_stmt; jmp .protl
.protd: cmp byte [tok_type], TOK_DEDENT; jne .protnd; call lexer_next
.protnd: call codegen_emit_ret; dec qword [prot_body_depth]; jmp .done
.ret: call lexer_next; mov rdi, [tok_int]; call codegen_emit_mov_eax_imm32; call codegen_emit_ret; call lexer_next; jmp .done
.stop: call codegen_emit_break; call lexer_next; jmp .done
.at: call lexer_next; lea rdi, [tok_ident]; call proto_find; cmp rax, -1; je .done; mov rdi, rax; call codegen_emit_call_prot; call lexer_next; call lexer_next; call lexer_next; jmp .done
.use:
    call lexer_next; call lexer_next; call lexer_next; cmp byte [tok_ident], 'p'; sete al; movzx edi, al; call codegen_emit_mm_switch
    call lexer_next; call lexer_next; call lexer_next; call lexer_next; call lexer_next
    cmp byte [tok_type], TOK_NEWLINE; jne .un; call lexer_next
.un: cmp byte [tok_type], TOK_INDENT; jne .ub; call lexer_next; mov r13, 1; jmp .ubl
.ub: xor r13, r13
.ubl: movzx eax, byte [tok_type]; cmp al, TOK_EOF; je .uen; cmp al, TOK_DEDENT; je .uen; call parse_stmt; test r13, r13; jnz .ubl
.uen: test r13, r13; jz .udo; cmp byte [tok_type], TOK_DEDENT; jne .udo; call lexer_next
.udo: xor rdi, rdi; call codegen_emit_mm_switch; jmp .done
.done: pop r15; pop r14; pop r13; pop r12; pop rbx; leave; ret
proto_find: push rbp; mov rbp, rsp; push r12; push r13; push rbx; mov r12, rdi; xor r13, r13
.l: cmp r13, [proto_count]; jge .nf; mov rax, r13; imul rax, 40; lea rbx, [proto_table]; add rbx, rax; mov rdi, rbx; mov rsi, r12; mov ecx, 32
.cl: movzx eax, byte [rdi]; movzx edx, byte [rsi]; cmp eax, edx; jne .nm; test eax, eax; jz .m; inc rdi; inc rsi; dec ecx; jnz .cl
.m: mov rax, [rbx+32]; jmp .done
.nm: inc r13; jmp .l
.nf: mov rax, -1
.done: pop rbx; pop r13; pop r12; leave; ret
""")

with open("codegen/codegen.asm", "w") as f:
    f.write(r"""default rel
%include "include/rex_defs.inc"
global codegen_write_headers, codegen_init, codegen_finish, out_buffer, out_idx
global codegen_output_const, codegen_output_typed, codegen_patch_jump, codegen_save_chain_base, codegen_emit_jmp_end, codegen_patch_chain_end
global codegen_begin_protos, codegen_end_protos, codegen_emit_for_start, codegen_emit_for_end, codegen_emit_while_start, codegen_emit_while_end
global codegen_emit_break, codegen_patch_breaks, codegen_emit_ret, codegen_emit_mov_eax_imm32, codegen_emit_call_prot, codegen_emit_assign_var, codegen_emit_cmp_var_jne, codegen_emit_unknown_bool
global codegen_emit_mm_switch
extern elf_header, program_header, rt_pri_blob, rt_prs_blob, rt_prb_blob, rt_prf_blob, rt_prc_blob, rt_sip_blob, rt_alc_blob, rt_prq_blob
section .bss
out_buffer: resb 131072; out_idx: resq 1; jump_patch_stack: resq 32; jump_patch_depth: resq 1; end_jump_stack: resq 32; end_jump_depth: resq 1; chain_base_stack: resq 32; chain_base_depth: resq 1
break_jump_stack: resq 32; break_jump_depth: resq 1; break_base_stack: resq 32; break_base_depth: resq 1; prot_jmp_idx: resq 1; prot_jmp_live: resb 1
section .text
emit_b: push rbx; push rcx; mov rcx, [out_idx]; lea rbx, [out_buffer]; mov [rbx+rcx], al; inc qword [out_idx]; pop rcx; pop rbx; ret
emit_d: push rbx; push rcx; mov rcx, [out_idx]; lea rbx, [out_buffer]; mov [rbx+rcx], eax; add qword [out_idx], 4; pop rcx; pop rbx; ret
emit_q: push rbx; push rcx; mov rcx, [out_idx]; lea rbx, [out_buffer]; mov [rbx+rcx], rax; add qword [out_idx], 8; pop rcx; pop rbx; ret
emit_blob: push rdi; push rsi; push rcx; push rdx; mov rdx, [out_idx]; lea rdi, [out_buffer]; add rdi, rdx; cld; rep movsb; pop rdx; pop rcx; pop rsi; pop rdi; add qword [out_idx], rcx; ret
get_var_va: mov rax, rdi; shl rax, 6; add rax, VAR_STORAGE_BASE; ret
codegen_write_headers: mov qword [out_idx], 0; lea rsi, [elf_header]; lea rdi, [out_buffer]; mov rcx, 64; cld; rep movsb
    lea rsi, [program_header]; mov rcx, 56; rep movsb; mov qword [out_idx], 120; ret
codegen_init: mov al, 0xE9; call emit_b; mov eax, RT_TOTAL_SIZE; call emit_d
    lea rsi, [rt_pri_blob]; mov rcx, RT_PRI_SIZE; call emit_blob
    lea rsi, [rt_prs_blob]; mov rcx, RT_PRS_SIZE; call emit_blob
    lea rsi, [rt_prb_blob]; mov rcx, RT_PRB_SIZE; call emit_blob
    lea rsi, [rt_prf_blob]; mov rcx, RT_PRF_SIZE; call emit_blob
    lea rsi, [rt_prc_blob]; mov rcx, RT_PRC_SIZE; call emit_blob
    lea rsi, [rt_sip_blob]; mov rcx, RT_SIP_SIZE; call emit_blob
    lea rsi, [rt_alc_blob]; mov rcx, RT_ALC_SIZE; call emit_blob
    lea rsi, [rt_prq_blob]; mov rcx, RT_PRQ_SIZE; call emit_blob; ret
codegen_output_const: mov al, 0xBF; call emit_b; mov eax, edi; call emit_d; mov al, 0xE8; call emit_b
    mov rax, LOAD_BASE + RT_PRI_OFFSET; mov rdx, [out_idx]; add rdx, 4; add rdx, LOAD_BASE; sub rax, rdx; call emit_d; ret
codegen_output_typed: push rsi; push rdi; mov al, 0x48; call emit_b; mov al, 0x8B; call emit_b; mov al, 0x3C; call emit_b; mov al, 0x25; call emit_b; pop rdi; push rdi; call get_var_va; call emit_d
    pop rdi; pop rsi; mov al, 0xE8; call emit_b; mov rax, RT_PRI_OFFSET; cmp sil, TYPE_STR; je .s; cmp sil, TYPE_BOOL; je .b; cmp sil, TYPE_FLOAT; je .f; cmp sil, TYPE_COMPLEX; je .c; jmp .d
.s: mov rax, RT_PRS_OFFSET; jmp .d; .b: mov rax, RT_PRB_OFFSET; jmp .d; .f: mov rax, RT_PRF_OFFSET; jmp .d; .c: mov rax, RT_PRC_OFFSET
.d: add rax, LOAD_BASE; mov rdx, [out_idx]; add rdx, 4; add rdx, LOAD_BASE; sub rax, rdx; call emit_d; ret
codegen_emit_assign_var: push rdi; mov al, 0x48; call emit_b; mov al, 0xB8; call emit_b; mov rax, rsi; call emit_q; mov al, 0x48; call emit_b; mov al, 0x89; call emit_b; mov al, 0x04; call emit_b
    mov al, 0x25; call emit_b; pop rdi; call get_var_va; call emit_d; ret
codegen_emit_unknown_bool: push rdi; mov al, 0x0F; call emit_b; mov al, 0xC7; call emit_b; mov al, 0xF0; call emit_b; mov al, 0x83; call emit_b; mov al, 0xE0; call emit_b; mov al, 0x01; call emit_b
    mov al, 0x89; call emit_b; mov al, 0x04; call emit_b; mov al, 0x25; call emit_b; pop rdi; call get_var_va; call emit_d; ret
codegen_emit_cmp_var_jne: push rsi; push rdi; mov al, 0x48; call emit_b; mov al, 0x81; call emit_b; mov al, 0x3C; call emit_b; mov al, 0x25; call emit_b; pop rdi; call get_var_va; call emit_d
    pop rsi; mov eax, esi; call emit_d; mov al, 0x0F; call emit_b; mov al, 0x85; call emit_b; mov rax, [out_idx]; mov rbx, [jump_patch_depth]; lea rcx, [jump_patch_stack]
    mov [rcx+rbx*8], rax; inc qword [jump_patch_depth]; xor eax, eax; call emit_d; ret
codegen_patch_jump: dec qword [jump_patch_depth]; mov rbx, [jump_patch_depth]; lea rcx, [jump_patch_stack]; mov rdx, [rcx+rbx*8]; mov rax, [out_idx]; sub rax, rdx; sub rax, 4; lea rcx, [out_buffer]; mov [rcx+rdx], eax; ret
codegen_save_chain_base: mov rax, [end_jump_depth]; mov rbx, [chain_base_depth]; lea rcx, [chain_base_stack]; mov [rcx+rbx*8], rax; inc qword [chain_base_depth]; ret
codegen_emit_jmp_end: mov al, 0xE9; call emit_b; mov rax, [out_idx]; mov rbx, [end_jump_depth]; lea rcx, [end_jump_stack]; mov [rcx+rbx*8], rax; inc qword [end_jump_depth]; xor eax, eax; call emit_d; ret
codegen_patch_chain_end: dec qword [chain_base_depth]; mov rbx, [chain_base_depth]; lea rcx, [chain_base_stack]; mov rsi, [rcx+rbx*8]
.l: cmp rsi, [end_jump_depth]; jae .done; lea rcx, [end_jump_stack]; mov rdx, [rcx+rsi*8]; mov rax, [out_idx]; sub rax, rdx; sub rax, 4; lea rcx, [out_buffer]; mov [rcx+rdx], eax; inc rsi; jmp .l
.done: mov [end_jump_depth], rsi; ret
codegen_begin_protos: cmp byte [prot_jmp_live], 0; jne .done; mov al, 0xE9; call emit_b; mov rax, [out_idx]; mov [prot_jmp_idx], rax; xor eax, eax; call emit_d; mov byte [prot_jmp_live], 1
.done: ret
codegen_end_protos: cmp byte [prot_jmp_live], 0; je .done; mov rdx, [prot_jmp_idx]; mov rax, [out_idx]; sub rax, rdx; sub rax, 4; lea rcx, [out_buffer]; mov [rcx+rdx], eax; mov byte [prot_jmp_live], 0
.done: ret
codegen_emit_for_start: push rbx; push r12; push r13; mov r12, rdi; mov r13, rdx; mov al, 0x48; call emit_b; mov al, 0xB8; call emit_b; mov rax, rsi; call emit_q
    mov al, 0x48; call emit_b; mov al, 0x89; call emit_b; mov al, 0x04; call emit_b; mov al, 0x25; call emit_b; mov rdi, r12; call get_var_va; call emit_d; mov rbx, [out_idx]
    mov al, 0x48; call emit_b; mov al, 0x8B; call emit_b; mov al, 0x04; call emit_b; mov al, 0x25; call emit_b; mov rdi, r12; call get_var_va; call emit_d
    mov al, 0x48; call emit_b; mov al, 0x3D; call emit_b; mov rax, r13; call emit_d; mov al, 0x0F; call emit_b; mov al, 0x8D; call emit_b
    mov rax, [out_idx]; mov r13, [jump_patch_depth]; lea rcx, [jump_patch_stack]; mov [rcx+r13*8], rax; inc qword [jump_patch_depth]; xor eax, eax; call emit_d; mov rax, rbx; pop r13; pop r12; pop rbx; ret
codegen_emit_for_end: push rbx; push r12; push r13; mov r12, rdi; mov r13, rsi; mov al, 0x48; call emit_b; mov al, 0x8B; call emit_b; mov al, 0x04; call emit_b; mov al, 0x25; call emit_b
    mov rdi, r13; call get_var_va; call emit_d; mov al, 0x48; call emit_b; mov al, 0xFF; call emit_b; mov al, 0xC0; call emit_b; mov al, 0x48; call emit_b; mov al, 0x89; call emit_b
    mov al, 0x04; call emit_b; mov al, 0x25; call emit_b; mov rdi, r13; call get_var_va; call emit_d; mov al, 0xE9; call emit_b; mov rax, r12; add rax, LOAD_BASE; mov rdx, [out_idx]; add rdx, 4; add rdx, LOAD_BASE; sub rax, rdx; call emit_d
    call codegen_patch_jump; call codegen_patch_breaks; pop r13; pop r12; pop rbx; ret
codegen_emit_while_end: mov al, 0xE9; call emit_b; mov rax, rdi; add rax, LOAD_BASE; mov rdx, [out_idx]; add rdx, 4; add rdx, LOAD_BASE; sub rax, rdx; call emit_d; call codegen_patch_jump; call codegen_patch_breaks; ret
codegen_emit_break: mov al, 0xE9; call emit_b; mov rax, [out_idx]; mov rbx, [break_jump_depth]; lea rcx, [break_jump_stack]; mov [rcx+rbx*8], rax; inc qword [break_jump_depth]; xor eax, eax; call emit_d; ret
codegen_patch_breaks: dec qword [break_base_depth]; mov rbx, [break_base_depth]; lea rcx, [break_base_stack]; mov rsi, [rcx+rbx*8]
.l: cmp rsi, [break_jump_depth]; jae .done; lea rcx, [break_jump_stack]; mov rdx, [rcx+rsi*8]; mov rax, [out_idx]; sub rax, rdx; sub rax, 4; lea rcx, [out_buffer]; mov [rcx+rdx], eax; inc rsi; jmp .l
.done: mov [break_jump_depth], rsi; ret
codegen_emit_ret: mov al, 0xC3; call emit_b; ret
codegen_emit_mov_eax_imm32: mov al, 0xB8; call emit_b; mov eax, edi; call emit_d; ret
codegen_emit_call_prot: mov al, 0xE8; call emit_b; mov rax, rdi; add rax, LOAD_BASE; mov rdx, [out_idx]; add rdx, 4; add rdx, LOAD_BASE; sub rax, rdx; call emit_d; ret
codegen_emit_mm_switch: mov al, 0x48; call emit_b; mov al, 0xC7; call emit_b; mov al, 0x05; call emit_b
    mov rax, LOAD_BASE + RT_ALC_OFFSET + 4096 - 8; mov rdx, [out_idx]; add rdx, 4; sub rax, rdx; call emit_d; mov eax, edi; call emit_d; ret
codegen_finish: mov al, 0x48; call emit_b; mov al, 0xC7; call emit_b; mov al, 0xC0; call emit_b; mov eax, 60; call emit_d; mov al, 0x48; call emit_b; mov al, 0x31; call emit_b; mov al, 0xFF; call emit_b; mov al, 0x0F; call emit_b; mov al, 0x05; call emit_b
    mov rax, [out_idx]; lea rcx, [out_buffer]; mov [rcx + 64 + 32], rax; mov qword [rcx + 64 + 40], 0x80000; ret
""")

with open("Makefile", "w") as f:
    f.write("NASM=nasm\nLD=ld\nOBJS=main/main.o lexer/lexer.o parser/parser.o codegen/codegen.o headers/headers.o runtime/runtime.o\nall: rexc\nrexc: $(OBJS)\n\t$(LD) $(OBJS) -o rexc\n%.o: %.asm\n\t$(NASM) -f elf64 -I include/ $< -o $@\nclean:\n\trm -f $(OBJS) rexc output\n")
