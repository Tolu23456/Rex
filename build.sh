#!/bin/bash
set -e

echo "=== Rex Bootstrap Compiler — Modular Stage 0 ==="
echo ""
echo "Assembling modules..."
nasm -f elf64 main.asm    -o main.o
nasm -f elf64 lexer.asm   -o lexer.o
nasm -f elf64 parser.asm  -o parser.o
nasm -f elf64 codegen.asm -o codegen.o
nasm -f elf64 headers.asm -o headers.o
nasm -f elf64 runtime.asm -o runtime.o

echo "Linking..."
ld main.o lexer.o parser.o codegen.o headers.o runtime.o -o rexc
echo "Compiler built: ./rexc"
echo ""

echo "Compiling test.rex..."
./rexc test.rex
echo "Output binary generated: ./output"
echo ""

echo "Running output:"
./output
echo ""
echo "Done."
