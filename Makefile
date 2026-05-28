NASM=nasm
LD=ld
OBJS=main/main.o lexer/lexer.o parser/parser.o codegen/codegen.o headers/headers.o runtime/runtime.o
all: rexc
rexc: $(OBJS)
	$(LD) $(OBJS) -o rexc
%.o: %.asm
	$(NASM) -f elf64 -I include/ $< -o $@
clean:
	rm -f $(OBJS) rexc output
