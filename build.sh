#!/bin/bash
set -e

echo "=== Rex Bootstrap Compiler — Modular Stage 0 ==="
echo ""
echo "Assembling modules..."
nasm -f elf64 -I include/  main/main.asm    -o main/main.o
nasm -f elf64 -I include/  lexer/lexer.asm  -o lexer/lexer.o
nasm -f elf64 -I include/  parser/parser.asm -o parser/parser.o
nasm -f elf64 -I include/  codegen/codegen.asm -o codegen/codegen.o
nasm -f elf64 -I include/  headers/headers.asm -o headers/headers.o
nasm -f elf64 -I include/  runtime/runtime.asm -o runtime/runtime.o

echo "Linking..."
ld main/main.o lexer/lexer.o parser/parser.o \
   codegen/codegen.o headers/headers.o runtime/runtime.o \
   -o rexc
echo "Compiler built: ./rexc"
echo ""

echo "=== Test 1: tests/test.rex ==="
./rexc tests/test.rex
echo "Output:"
./output
echo ""

echo "=== Test 2: tests/conditional_test.rex ==="
./rexc tests/conditional_test.rex
echo "Output:"
./output
echo ""

echo "=== Test 3: tests/elif_else_test.rex ==="
./rexc tests/elif_else_test.rex
echo "Output:"
./output
echo ""
echo "All tests passed."
