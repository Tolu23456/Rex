NASM=/nix/store/kbyq3jx1i16p2rnshkd90rhfgm6anf42-nasm-2.16.03/bin/nasm
LD=ld
OBJS=main/main.o lexer/lexer.o parser/parser.o codegen/codegen.o headers/headers.o runtime/runtime.o
all: rexc
rexc: $(OBJS)
	$(LD) $(OBJS) -o rexc
runtime/runtime.bin: runtime/runtime_src.asm
	$(NASM) -f bin runtime/runtime_src.asm -o runtime/runtime.bin
runtime/runtime.o: runtime/runtime.asm runtime/runtime.bin
	$(NASM) -f elf64 -I include/ runtime/runtime.asm -o runtime/runtime.o
%.o: %.asm
	$(NASM) -f elf64 -I include/ $< -o $@
clean:
	rm -f $(OBJS) rexc output runtime/runtime.bin
