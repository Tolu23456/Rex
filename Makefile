# Rex Compiler Makefile

# Assembler and Linker
ASM=nasm
LD=ld

# Source Directories
LEXER_DIR=lexer
PARSER_DIR=parser
IRGEN_DIR=irgen
CODEGEN_DIR=codegen
MAIN_DIR=main
RUNTIME_DIR=runtime

# Output Compiler Binary
TARGET=rexc

# Runtime Binary Blobs
RT_BINS=$(RUNTIME_DIR)/rt_pri.bin \
	$(RUNTIME_DIR)/rt_prs.bin \
	$(RUNTIME_DIR)/rt_prb.bin \
	$(RUNTIME_DIR)/rt_prf.bin \
	$(RUNTIME_DIR)/rt_prc.bin \
	$(RUNTIME_DIR)/rt_alloc.bin \
	$(RUNTIME_DIR)/rt_seq.bin \
	$(RUNTIME_DIR)/rt_str.bin \
	$(RUNTIME_DIR)/rt_dict.bin

# Compiler Object Files
OBJS=$(MAIN_DIR)/main.o \
	$(LEXER_DIR)/lexer.o \
	$(PARSER_DIR)/type_reg.o \
	$(PARSER_DIR)/symtab.o \
	$(PARSER_DIR)/parser.o \
	$(IRGEN_DIR)/irgen.o \
	$(IRGEN_DIR)/ra.o \
	$(IRGEN_DIR)/opt.o \
	$(CODEGEN_DIR)/codegen.o

.PHONY: all clean runtimes test

all: $(TARGET)

# Compile Runtime ASM to flat binary blobs
$(RUNTIME_DIR)/%.bin: $(RUNTIME_DIR)/%.asm
	$(ASM) -f bin $< -o $@

runtimes: $(RT_BINS)

# Compile Compiler Modules
# Note: codegen.asm depends on runtime bins being generated first (for incbin)
$(CODEGEN_DIR)/codegen.o: $(CODEGEN_DIR)/codegen.asm $(RT_BINS)
	$(ASM) -f elf64 -I ./ $< -o $@

$(LEXER_DIR)/lexer.o: $(LEXER_DIR)/lexer.asm
	$(ASM) -f elf64 -I ./ $< -o $@

$(PARSER_DIR)/symtab.o: $(PARSER_DIR)/symtab.asm
	$(ASM) -f elf64 -I ./ $< -o $@

$(PARSER_DIR)/type_reg.o: $(PARSER_DIR)/type_reg.asm
	$(ASM) -f elf64 -I ./ $< -o $@

$(PARSER_DIR)/parser.o: $(PARSER_DIR)/parser.asm
	$(ASM) -f elf64 -I ./ $< -o $@

$(IRGEN_DIR)/irgen.o: $(IRGEN_DIR)/irgen.asm
	$(ASM) -f elf64 -I ./ $< -o $@

$(IRGEN_DIR)/ra.o: $(IRGEN_DIR)/ra.asm
	$(ASM) -f elf64 -I ./ $< -o $@

$(IRGEN_DIR)/opt.o: $(IRGEN_DIR)/opt.asm
	$(ASM) -f elf64 -I ./ $< -o $@

$(MAIN_DIR)/main.o: $(MAIN_DIR)/main.asm
	$(ASM) -f elf64 -I ./ $< -o $@

# Link the Rex compiler
$(TARGET): runtimes $(OBJS)
	$(LD) -o $(TARGET) $(OBJS)

test: all
	./run_tests.sh

clean:
	rm -f $(RUNTIME_DIR)/*.bin
	rm -f $(LEXER_DIR)/*.o
	rm -f $(PARSER_DIR)/*.o
	rm -f $(IRGEN_DIR)/*.o
	rm -f $(CODEGEN_DIR)/*.o
	rm -f $(MAIN_DIR)/*.o
	rm -f $(TARGET)
	rm -f a.out
