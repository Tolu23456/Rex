nasm -f elf64 rexc.asm -o rexc.o
ld rexc.o -o rexc
echo "Rex Compiler (rexc) built successfully."
