NASM    = nasm
LD      = ld
NFLAGS  = -f elf64 -I include/
BFLAGS  = -f bin  -I include/
LFLAGS  = -static

BIN_DEPS = runtime/rt_pri.bin runtime/rt_prs.bin runtime/rt_prb.bin \
           runtime/rt_prf.bin runtime/rt_prc.bin runtime/rt_sip.bin \
           runtime/rt_alc.bin runtime/rt_prq.bin runtime/rt_str_cat.bin

OBJ = main/main.o lexer/lexer.o parser/parser.o \
      codegen/codegen.o runtime/runtime.o

TARGET = rexc

all: $(TARGET)

$(TARGET): $(OBJ)
	$(LD) $(LFLAGS) -o $@ $^

# ---- Flat binary runtime blobs (stage 1) ----
%.bin: %.asm include/rex_defs.inc
	$(NASM) $(BFLAGS) -o $@ $<

# ---- ELF64 compiler objects (stage 2) ----
runtime/runtime.o: runtime/runtime.asm $(BIN_DEPS) include/rex_defs.inc
	$(NASM) $(NFLAGS) -o $@ $<

main/main.o: main/main.asm include/rex_defs.inc
	$(NASM) $(NFLAGS) -o $@ $<

lexer/lexer.o: lexer/lexer.asm include/rex_defs.inc
	$(NASM) $(NFLAGS) -o $@ $<

parser/parser.o: parser/parser.asm include/rex_defs.inc
	$(NASM) $(NFLAGS) -o $@ $<

codegen/codegen.o: codegen/codegen.asm include/rex_defs.inc
	$(NASM) $(NFLAGS) -o $@ $<

test: all
	@passed=0; failed=0; \
	for f in tests/*.rex tests/edge-cases/*.rex; do \
		[ -f "$$f" ] || continue; \
		name=$$(basename "$$f" .rex); \
		dir=$$(dirname "$$f"); \
		exp="$${dir}/$${name}.expected"; \
		[ -f "$$exp" ] || continue; \
		if ./$(TARGET) "$$f" -o /tmp/rxt 2>/dev/null && \
		   /tmp/rxt > /tmp/rxt_got 2>/dev/null; then \
			want=$$(cat "$$exp"); \
			got=$$(cat /tmp/rxt_got); \
			if [ "$$got" = "$$want" ]; then \
				echo "PASS: $$name"; \
				passed=$$((passed+1)); \
			else \
				echo "FAIL: $$name"; \
				printf "  exp: %s\n  got: %s\n" "$$want" "$$got"; \
				failed=$$((failed+1)); \
			fi; \
		else \
			echo "FAIL: $$name (compile/run error)"; \
			failed=$$((failed+1)); \
		fi; \
	done; \
	echo ""; echo "$$passed passed, $$failed failed"

clean:
	rm -f $(OBJ) $(BIN_DEPS) $(TARGET) /tmp/rxt /tmp/rxt_got

.PHONY: all test clean
