#!/bin/sh
# Rex Bootstrap Compiler — build and test script
set -e

NASM=nasm
LD=ld

echo "=== Building Rex compiler ==="

# Create build directories
mkdir -p runtime main lexer parser codegen include

# Assemble runtime blobs (flat binaries)
echo "Assembling runtime blobs..."
$NASM -f bin -I include/ -o runtime/rt_pri.bin  runtime/rt_pri.asm
$NASM -f bin -I include/ -o runtime/rt_prs.bin  runtime/rt_prs.asm
$NASM -f bin -I include/ -o runtime/rt_prb.bin  runtime/rt_prb.asm
$NASM -f bin -I include/ -o runtime/rt_prf.bin  runtime/rt_prf.asm
$NASM -f bin -I include/ -o runtime/rt_prc.bin  runtime/rt_prc.asm
$NASM -f bin -I include/ -o runtime/rt_sip.bin  runtime/rt_sip.asm
$NASM -f bin -I include/ -o runtime/rt_alc.bin  runtime/rt_alc.asm
$NASM -f bin -I include/ -o runtime/rt_prq.bin  runtime/rt_prq.asm
$NASM -f bin -I include/ -o runtime/rt_str.bin  runtime/rt_str.asm
$NASM -f bin -I include/ -o runtime/rt_inp.bin     runtime/rt_inp.asm
$NASM -f bin -I include/ -o runtime/rt_str_cat.bin runtime/rt_str_cat.asm

# Assemble compiler modules
echo "Assembling compiler modules..."
$NASM -f elf64 -I include/ -o runtime/runtime.o  runtime/runtime.asm
$NASM -f elf64 -I include/ -o codegen/codegen.o   codegen/codegen.asm
$NASM -f elf64 -I include/ -o lexer/lexer.o       lexer/lexer.asm
$NASM -f elf64 -I include/ -o parser/parser.o     parser/parser.asm
$NASM -f elf64 -I include/ -o main/main.o         main/main.asm

# Link
echo "Linking..."
$LD -static -o rexc \
    main/main.o lexer/lexer.o parser/parser.o \
    codegen/codegen.o runtime/runtime.o

echo "=== Build complete: ./rexc ==="

# Run tests if requested
if [ "$1" = "test" ]; then
    echo ""
    echo "=== Running tests ==="
    passed=0
    failed=0
    for f in tests/*.rex; do
        [ -f "$f" ] || continue
        name=$(basename "$f" .rex)
        exp="tests/${name}.expected"
        [ -f "$exp" ] || continue
        if ./rexc "$f" -o /tmp/rex_out 2>/dev/null && /tmp/rex_out 2>/dev/null > /tmp/rex_got; then
            want=$(cat "$exp")
            got=$(cat /tmp/rex_got)
            if [ "$got" = "$want" ]; then
                echo "PASS: $name"
                passed=$((passed+1))
            else
                echo "FAIL: $name"
                echo "  expected: $want"
                echo "  got:      $got"
                failed=$((failed+1))
            fi
        else
            echo "FAIL: $name (compiler or runtime error)"
            failed=$((failed+1))
        fi
    done
    echo ""
    echo "Results: $passed passed, $failed failed"
fi
