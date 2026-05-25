NASM      = nasm
LD        = ld
NASMFLAGS = -f elf64 -I include/

OBJS = main/main.o \
       lexer/lexer.o \
       parser/parser.o \
       codegen/codegen.o \
       headers/headers.o \
       runtime/runtime.o

.PHONY: all clean test

all: rexc

rexc: $(OBJS)
        $(LD) $(OBJS) -o rexc

main/main.o: main/main.asm include/rex_defs.inc
        $(NASM) $(NASMFLAGS) main/main.asm -o main/main.o

lexer/lexer.o: lexer/lexer.asm include/rex_defs.inc
        $(NASM) $(NASMFLAGS) lexer/lexer.asm -o lexer/lexer.o

parser/parser.o: parser/parser.asm include/rex_defs.inc
        $(NASM) $(NASMFLAGS) parser/parser.asm -o parser/parser.o

codegen/codegen.o: codegen/codegen.asm include/rex_defs.inc
        $(NASM) $(NASMFLAGS) codegen/codegen.asm -o codegen/codegen.o

headers/headers.o: headers/headers.asm include/rex_defs.inc
        $(NASM) $(NASMFLAGS) headers/headers.asm -o headers/headers.o

runtime/runtime.o: runtime/runtime.asm include/rex_defs.inc
        $(NASM) $(NASMFLAGS) runtime/runtime.asm -o runtime/runtime.o

clean:
        rm -f $(OBJS) rexc output

test: rexc
        @echo "=== Test 1: tests/test.rex ==="
        ./rexc tests/test.rex
        ./output
        @echo "=== Test 2: tests/conditional_test.rex ==="
        ./rexc tests/conditional_test.rex
        ./output
        @echo "=== Test 3: tests/elif_else_test.rex ==="
        ./rexc tests/elif_else_test.rex
        ./output
        @echo "=== Test 4: tests/for_test.rex ==="
        ./rexc tests/for_test.rex
        ./output
        @echo "=== Test 5: tests/prot_test.rex ==="
        ./rexc tests/prot_test.rex
        ./output
