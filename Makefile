NASM=/nix/store/kbyq3jx1i16p2rnshkd90rhfgm6anf42-nasm-2.16.03/bin/nasm
LD=ld
CC=gcc
CFLAGS=-O2 -std=c11 -Wall -Wextra -Wno-unused-parameter
IR_OBJS=ir/rex_ir_buf.o ir/pass1_cfp.o ir/pass2_dce.o ir/pass3_dse.o ir/pass4_lsc.o ir/pass5_licm.o ir/pass6_sr.o ir/pass7_ra.o ir/pass8_ph.o ir/rex_ir_x86.o
OBJS=main/main.o lexer/lexer.o parser/parser.o codegen/codegen.o headers/headers.o runtime/runtime.o $(IR_OBJS)
RXC_OBJS=main/main.o lexer/lexer.o parser/parser.o rxc/rxc_codegen.o rxc/rxc_emit.o rxc/rxc_builtin_stubs.o headers/headers.o
PREFIX=/usr/local

# Compiler targets

all: rexc rexc_rxc rex rex_lsp

rexc: $(OBJS)
	$(LD) $(OBJS) -o rexc

# RexC bytecode backend: Rex -> .rxc portable bytecode
rexc_rxc: $(RXC_OBJS)
	$(LD) $(RXC_OBJS) -o rexc_rxc

rxc/rxc_builtin_stubs.o: rxc/rxc_builtin_stubs.asm include/rex_defs.inc
	$(NASM) -f elf64 -I include/ rxc/rxc_builtin_stubs.asm -o rxc/rxc_builtin_stubs.o

rxc/rxc_emit.o: rxc/rxc_emit.asm rxc/rxc_defs.inc include/rex_defs.inc
	$(NASM) -f elf64 -I include/ -I rxc/ rxc/rxc_emit.asm -o rxc/rxc_emit.o

rxc/rxc_codegen.o: rxc/rxc_codegen.asm rxc/rxc_defs.inc include/rex_defs.inc
	$(NASM) -f elf64 -I include/ -I rxc/ rxc/rxc_codegen.asm -o rxc/rxc_codegen.o

runtime/runtime.bin: runtime/runtime_src.asm
	$(NASM) -f bin runtime/runtime_src.asm -o runtime/runtime.bin

runtime/runtime.o: runtime/runtime.asm runtime/runtime.bin
	$(NASM) -f elf64 -I include/ runtime/runtime.asm -o runtime/runtime.o

%.o: %.asm
	$(NASM) -f elf64 -I include/ -I ir/ $< -o $@

ir/%.o: ir/%.asm ir/ir_defs.inc include/rex_defs.inc
	$(NASM) -f elf64 -I include/ -I ir/ $< -o $@

# LSP server

rex_lsp: lsp/rex_lsp.c
	$(CC) $(CFLAGS) -o rex_lsp lsp/rex_lsp.c

lsp: rex_lsp

# rex CLI dispatcher

rex: rex_main.c
	$(CC) $(CFLAGS) -o rex rex_main.c

# Install

install: all
	install -d $(PREFIX)/bin
	install -m 0755 rexc     $(PREFIX)/bin/rexc
	install -m 0755 rexc_rxc $(PREFIX)/bin/rexc_rxc
	install -m 0755 rex_lsp  $(PREFIX)/bin/rex_lsp
	install -m 0755 rex      $(PREFIX)/bin/rex
	@echo "Rex V5.0 installed to $(PREFIX)/bin"

uninstall:
	rm -f $(PREFIX)/bin/rex $(PREFIX)/bin/rexc $(PREFIX)/bin/rex_lsp $(PREFIX)/bin/rexc_rxc
	@echo "Rex uninstalled from $(PREFIX)/bin"

install-user: all
	install -d $(HOME)/.local/bin
	install -m 0755 rexc     $(HOME)/.local/bin/rexc
	install -m 0755 rexc_rxc $(HOME)/.local/bin/rexc_rxc
	install -m 0755 rex_lsp  $(HOME)/.local/bin/rex_lsp
	install -m 0755 rex      $(HOME)/.local/bin/rex
	@echo "Rex V5.0 installed to $(HOME)/.local/bin"

# Clean

clean:
	rm -f $(OBJS) rexc rex rex_lsp output runtime/runtime.bin
	rm -f rxc/rxc_emit.o rxc/rxc_codegen.o rxc/rxc_builtin_stubs.o rexc_rxc
	rm -f $(IR_OBJS)

.PHONY: all lsp install uninstall install-user clean
