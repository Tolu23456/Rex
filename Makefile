NASM=/nix/store/kbyq3jx1i16p2rnshkd90rhfgm6anf42-nasm-2.16.03/bin/nasm
LD=ld
CC=gcc
CFLAGS=-O2 -std=c11 -Wall -Wextra -Wno-unused-parameter
OBJS=main/main.o lexer/lexer.o parser/parser.o codegen/codegen.o headers/headers.o runtime/runtime.o
PREFIX=/usr/local

# ── Compiler targets ────────────────────────────────────────────────────────────

all: rexc rex rex_lsp

rexc: $(OBJS)
	$(LD) $(OBJS) -o rexc

runtime/runtime.bin: runtime/runtime_src.asm
	$(NASM) -f bin runtime/runtime_src.asm -o runtime/runtime.bin

runtime/runtime.o: runtime/runtime.asm runtime/runtime.bin
	$(NASM) -f elf64 -I include/ runtime/runtime.asm -o runtime/runtime.o

%.o: %.asm
	$(NASM) -f elf64 -I include/ $< -o $@

# ── LSP server ──────────────────────────────────────────────────────────────────

rex_lsp: lsp/rex_lsp.c
	$(CC) $(CFLAGS) -o rex_lsp lsp/rex_lsp.c

lsp: rex_lsp

# ── rex CLI dispatcher ──────────────────────────────────────────────────────────

rex: rex_main.c
	$(CC) $(CFLAGS) -o rex rex_main.c

# ── Install ─────────────────────────────────────────────────────────────────────
# Usage: sudo make install
# Installs rex, rexc, and rex_lsp to $(PREFIX)/bin

install: all
	install -d $(PREFIX)/bin
	install -m 0755 rexc    $(PREFIX)/bin/rexc
	install -m 0755 rex_lsp $(PREFIX)/bin/rex_lsp
	install -m 0755 rex     $(PREFIX)/bin/rex
	@echo ""
	@echo "Rex V5.0 installed to $(PREFIX)/bin"
	@echo "  rex     — CLI dispatcher  (rex build / run / check / lsp / fmt / ...)"
	@echo "  rexc    — compiler backend"
	@echo "  rex_lsp — LSP server"
	@echo ""
	@echo "Run 'rex --version' to verify the installation."
	@echo "Run 'rex new myapp' to start a new Rex project."

uninstall:
	rm -f $(PREFIX)/bin/rex $(PREFIX)/bin/rexc $(PREFIX)/bin/rex_lsp
	@echo "Rex uninstalled from $(PREFIX)/bin"

# ── Install to user home (no sudo required) ─────────────────────────────────────

install-user: all
	install -d $(HOME)/.local/bin
	install -m 0755 rexc    $(HOME)/.local/bin/rexc
	install -m 0755 rex_lsp $(HOME)/.local/bin/rex_lsp
	install -m 0755 rex     $(HOME)/.local/bin/rex
	@echo ""
	@echo "Rex V5.0 installed to $(HOME)/.local/bin"
	@echo "Make sure $(HOME)/.local/bin is on your PATH."

# ── Clean ────────────────────────────────────────────────────────────────────────

clean:
	rm -f $(OBJS) rexc rex rex_lsp output runtime/runtime.bin

.PHONY: all lsp install uninstall install-user clean
