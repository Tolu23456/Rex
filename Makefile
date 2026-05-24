NASM    = nasm
LD      = ld
NASMFLAGS = -f elf64

OBJS = main.o lexer.o parser.o codegen.o headers.o runtime.o

.PHONY: all clean test

all: rexc

rexc: $(OBJS)
	$(LD) $(OBJS) -o rexc

main.o: main.asm rex_defs.inc
	$(NASM) $(NASMFLAGS) main.asm -o main.o

lexer.o: lexer.asm rex_defs.inc
	$(NASM) $(NASMFLAGS) lexer.asm -o lexer.o

parser.o: parser.asm rex_defs.inc
	$(NASM) $(NASMFLAGS) parser.asm -o parser.o

codegen.o: codegen.asm rex_defs.inc
	$(NASM) $(NASMFLAGS) codegen.asm -o codegen.o

headers.o: headers.asm rex_defs.inc
	$(NASM) $(NASMFLAGS) headers.asm -o headers.o

runtime.o: runtime.asm rex_defs.inc
	$(NASM) $(NASMFLAGS) runtime.asm -o runtime.o

clean:
	rm -f $(OBJS) rexc output

test: rexc
	@echo "Compiling test.rex ..."
	./rexc test.rex
	@echo "Running output binary ..."
	./output
