#!/bin/bash
set -e

echo "=== Rex Bootstrap Compiler ==="
echo ""
echo "Building compiler from source..."
nasm -f elf64 rexc.asm -o rexc.o
ld rexc.o -o rexc
echo "Compiler built successfully: ./rexc"
echo ""
echo "Compiling test.rex..."
./rexc test.rex
echo "Output binary generated: ./output"
echo ""
echo "Running output:"
./output
echo ""
echo "Done."
