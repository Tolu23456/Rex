#!/bin/bash
echo "=== Rex V5.0 Performance Benchmarks ==="
# Ensure rexc exists
if [ ! -f "./rexc" ]; then
    echo "Error: rexc not found in current directory."
    exit 1
fi

# We need uthash.h for the C benchmark
if [ ! -f "benchmarks/uthash.h" ]; then
    curl -sL https://raw.githubusercontent.com/troydhanson/uthash/master/src/uthash.h -o benchmarks/uthash.h
fi

for f in benchmarks/bench_*.c; do
    name=$(basename "$f" .c)
    rex_file="benchmarks/${name}.rex"
    
    if [ ! -f "$rex_file" ]; then
        continue
    fi
    
    echo "Running benchmark: $name"
    
    # compile C
    gcc -O2 -Ibenchmarks -o /tmp/c_bench "$f" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "  C COMPILE FAILED"
        continue
    fi
    
    # compile Rex
    ./rexc "$rex_file" -o /tmp/rex_bench 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "  REX COMPILE FAILED"
        continue
    fi
    
    # Run C
    c_result=$(/tmp/c_bench | head -n 1)
    
    # Run Rex
    # Rex doesn't have internal timing in these scripts, we use time command or outer measurement
    # But the requirement says it should print the ns/op
    # Since Rex doesn't have a timing library yet (T004 math/os), we might need to use a wrapper
    
    t0=$(date +%s%N)
    rex_output=$(/tmp/rex_bench)
    t1=$(date +%s%N)
    
    rex_total_ns=$((t1 - t0))
    
    # Extract iterations from Rex file (simplified)
    iters=$(grep -oE "[0-9]+" "$rex_file" | head -n 1)
    if [ -z "$iters" ]; then iters=1; fi
    
    rex_ns_per_op=$(echo "scale=2; $rex_total_ns / $iters" | bc)
    
    echo "  Rex: $rex_ns_per_op ns/op ($iters ops in $(echo "scale=4; $rex_total_ns / 1000000000" | bc) seconds)"
    echo "  C:   $c_result"
done
