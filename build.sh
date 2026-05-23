# Rex Bootstrap Build Script (Pure Assembly Automation)
# This script automates the compilation of the Rex compiler using NASM and LD.

nasm -f elf64 main.asm -o main.o
nasm -f elf64 lexer/lexer.asm -o lexer/lexer.o
nasm -f elf64 parser/parser.asm -o parser/parser.o
nasm -f elf64 parser/semant.asm -o parser/semant.o
nasm -f elf64 codegen/codegen.asm -o codegen/codegen.o
nasm -f elf64 runtime/memory.asm -o runtime/memory.o
nasm -f elf64 runtime/random.asm -o runtime/random.o
nasm -f elf64 runtime/siphash.asm -o runtime/siphash.o
nasm -f elf64 runtime/types.asm -o runtime/types.o

ld main.o lexer/lexer.o parser/parser.o parser/semant.o codegen/codegen.o runtime/memory.o runtime/random.o runtime/siphash.o runtime/types.o -o rexc

echo "Rex Compiler (rexc) built successfully."
