#!/usr/bin/env bash
# Rex vs C Fair Benchmark Suite — runner
# Compiles all benchmarks, runs each 3 times, prints a results table.
# Both Rex and C use internal clock_gettime(CLOCK_MONOTONIC) timing.

set -e
SUITE_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SUITE_DIR/../.." && pwd)"

echo "============================================================"
echo " Rex vs C Fair Benchmark Suite"
echo " $(date)"
echo "============================================================"
echo ""

# ── Build Rex compiler ────────────────────────────────────────────
echo "[build] Rex compiler..."
cd "$ROOT_DIR" && make -s
REXC="$ROOT_DIR/rexc"
echo "[build] rexc OK"
echo ""

# ── Compile C binaries ────────────────────────────────────────────
echo "[build] C binaries (GCC -O3)..."
GCC=$(command -v gcc)
echo "  GCC: $($GCC --version | head -1)"

$GCC -O3 -o "$SUITE_DIR/b1_arith_c"    "$SUITE_DIR/b1_arith.c"
$GCC -O3 -o "$SUITE_DIR/b2_mul64_c"    "$SUITE_DIR/b2_mul64.c"
$GCC -O3 -o "$SUITE_DIR/b3_calls_c"    "$SUITE_DIR/b3_calls.c"
$GCC -O3 -o "$SUITE_DIR/b6_fib_rec_c"  "$SUITE_DIR/b6_fib_rec.c"
$GCC -O3 -o "$SUITE_DIR/b7_fib_iter_c" "$SUITE_DIR/b7_fib_iter.c"
$GCC -O3 -o "$SUITE_DIR/b9_dynarray_c" "$SUITE_DIR/b9_dynarray.c"
$GCC -O3 -o "$SUITE_DIR/b10_mul_only_c" "$SUITE_DIR/b10_mul_only.c"
$GCC -O3 -o "$SUITE_DIR/b11_add_only_c" "$SUITE_DIR/b11_add_only.c"
echo "[build] C OK"
echo ""

# ── Compile Rex binaries ──────────────────────────────────────────
echo "[build] Rex binaries..."
cd "$ROOT_DIR"
compile_rex() {
    local src="$1" dst="$2"
    "$REXC" "$src" 2>&1
    mv output "$dst"
    chmod +x "$dst"
}
compile_rex "$SUITE_DIR/b1_arith.rex"     "$SUITE_DIR/b1_arith_rex"
compile_rex "$SUITE_DIR/b2_mul64.rex"     "$SUITE_DIR/b2_mul64_rex"
compile_rex "$SUITE_DIR/b3_calls.rex"     "$SUITE_DIR/b3_calls_rex"
compile_rex "$SUITE_DIR/b6_fib_rec.rex"   "$SUITE_DIR/b6_fib_rec_rex"
compile_rex "$SUITE_DIR/b7_fib_iter.rex"  "$SUITE_DIR/b7_fib_iter_rex"
compile_rex "$SUITE_DIR/b9_dynarray.rex"  "$SUITE_DIR/b9_dynarray_rex"
compile_rex "$SUITE_DIR/b10_mul_only.rex" "$SUITE_DIR/b10_mul_only_rex"
compile_rex "$SUITE_DIR/b11_add_only.rex" "$SUITE_DIR/b11_add_only_rex"
echo "[build] Rex OK"
echo ""

# ── Binary sizes ──────────────────────────────────────────────────
echo "------------------------------------------------------------"
echo " Binary Sizes"
echo "------------------------------------------------------------"
printf "%-30s %10s %10s\n" "Benchmark" "Rex (B)" "C (B)"
for b in b1_arith b2_mul64 b3_calls b6_fib_rec b7_fib_iter b9_dynarray b10_mul_only b11_add_only; do
    rx=$(wc -c < "$SUITE_DIR/${b}_rex")
    cc=$(wc -c < "$SUITE_DIR/${b}_c")
    printf "%-30s %10d %10d\n" "$b" "$rx" "$cc"
done
echo ""

# ── Timing helpers ─────────────────────────────────────────────────
# Extracts the "time=NNN.NN ms" field that C programs print.
c_time_ms() {
    local bin="$1"
    "$bin" 2>/dev/null | grep -oP '(?<=time=)[\d.]+' | head -1
}

# For Rex programs that print their internal elapsed ms as the last output line.
rex_int_ms() {
    local bin="$1"
    "$bin" 2>/dev/null | tail -1
}

# Run Rex 3 times using internal clock() (last output line = ms integer).
run3_rex_internal() {
    local label="$1" bin="$2"
    echo "  Rex — $label (internal clock)"
    local t1 t2 t3
    t1=$(rex_int_ms "$bin"); echo "    run1: ${t1} ms"
    t2=$(rex_int_ms "$bin"); echo "    run2: ${t2} ms"
    t3=$(rex_int_ms "$bin"); echo "    run3: ${t3} ms"
    local best avg
    best=$(echo "$t1 $t2 $t3" | awk '{b=$1; if($2<b)b=$2; if($3<b)b=$3; printf "%.0f",b}')
    avg=$(echo  "$t1 $t2 $t3" | awk '{printf "%.0f",($1+$2+$3)/3}')
    echo "    best=${best} ms  avg=${avg} ms"
    REX_BEST=$best; REX_AVG=$avg
}

run3_c() {
    local label="$1" bin="$2"
    echo "  C   — $label"
    local t1 t2 t3
    t1=$(c_time_ms "$bin"); echo "    run1: ${t1} ms"
    t2=$(c_time_ms "$bin"); echo "    run2: ${t2} ms"
    t3=$(c_time_ms "$bin"); echo "    run3: ${t3} ms"
    local best avg
    best=$(echo "$t1 $t2 $t3" | awk '{
        b=$1; if($2<b)b=$2; if($3<b)b=$3; printf "%.2f", b}')
    avg=$(echo "$t1 $t2 $t3" | awk '{printf "%.2f", ($1+$2+$3)/3}')
    echo "    best=${best} ms  avg=${avg} ms"
    C_BEST=$best; C_AVG=$avg
}

# ── Run benchmarks ────────────────────────────────────────────────

declare -a BN RT CT

run_bench() {
    local idx=$1 name="$2" rex_bin="$3" c_bin="$4"
    echo "------------------------------------------------------------"
    echo " Benchmark $name"
    echo "------------------------------------------------------------"
    run3_rex_internal "$name" "$rex_bin"
    run3_c            "$name" "$c_bin"
    BN[$idx]="$name"
    RT[$idx]=$REX_BEST
    CT[$idx]=$C_BEST
    echo ""
}

run_bench 0 "B1 Arithmetic Throughput (1B iters)" \
    "$SUITE_DIR/b1_arith_rex" "$SUITE_DIR/b1_arith_c"

run_bench 1 "B2 Multiply-fold 64-bit (1B iters)" \
    "$SUITE_DIR/b2_mul64_rex" "$SUITE_DIR/b2_mul64_c"

run_bench 2 "B3 Function Call Overhead (200M calls)" \
    "$SUITE_DIR/b3_calls_rex" "$SUITE_DIR/b3_calls_c"

run_bench 3 "B6 Recursive Fibonacci fib(42)" \
    "$SUITE_DIR/b6_fib_rec_rex" "$SUITE_DIR/b6_fib_rec_c"

run_bench 4 "B7 Iterative Fibonacci (10M × fib80)" \
    "$SUITE_DIR/b7_fib_iter_rex" "$SUITE_DIR/b7_fib_iter_c"

run_bench 5 "B9 Dynamic Array Growth (1M pushes)" \
    "$SUITE_DIR/b9_dynarray_rex" "$SUITE_DIR/b9_dynarray_c"

run_bench 6 "B10 Multiply-only fold (1B iters x*3)" \
    "$SUITE_DIR/b10_mul_only_rex" "$SUITE_DIR/b10_mul_only_c"

run_bench 7 "B11 Add-only fold (1B iters x+7)" \
    "$SUITE_DIR/b11_add_only_rex" "$SUITE_DIR/b11_add_only_c"

# ── Summary table ─────────────────────────────────────────────────
echo "============================================================"
echo " Results Table (best-of-3, ms)"
echo " Both Rex and C: internal clock_gettime(CLOCK_MONOTONIC)"
echo "============================================================"
printf "%-42s %10s %10s %10s %8s\n" "Benchmark" "Rex (ms)" "C (ms)" "Winner" "Ratio"
printf "%-42s %10s %10s %10s %8s\n" "---------" "--------" "------" "------" "-----"

rex_wins=0; c_wins=0; ties=0

for i in 0 1 2 3 4 5 6 7; do
    local_rex="${RT[$i]}"
    local_c="${CT[$i]}"
    name="${BN[$i]}"

    result=$(awk -v r="$local_rex" -v c="$local_c" 'BEGIN {
        r = r+0; c = c+0
        if (r == 0 && c == 0) { print "tie 1.00x"; exit }
        if (r == 0 && c > 0)  { printf "Rex >%.0fx\n", c/0.5; exit }
        if (c == 0 && r > 0)  { printf "C >%.0fx\n",   r/0.5; exit }
        if (r < c) { printf "Rex %.2fx\n", c/r; exit }
        if (c < r) { printf "C %.2fx\n",   r/c; exit }
        print "tie 1.00x"
    }')
    winner=$(echo "$result" | awk '{print $1}')
    ratio=$(echo "$result" | awk '{print $2}')

    printf "%-42s %10s %10s %10s %8s\n" "$name" "${local_rex} ms" "${local_c} ms" "$winner" "$ratio"

    if [ "$winner" = "Rex" ]; then (( rex_wins++ )) || true
    elif [ "$winner" = "C" ]; then (( c_wins++ )) || true
    else (( ties++ )) || true
    fi
done

echo ""
echo "------------------------------------------------------------"
printf "  Rex wins: %d    C wins: %d    Ties: %d\n" $rex_wins $c_wins $ties
echo "------------------------------------------------------------"
echo ""
echo "Note: All times are internal clock_gettime(CLOCK_MONOTONIC)."
echo "      Rex uses the built-in clock() function (syscall 228, inline 55 bytes)."
echo "      C uses clock_gettime() via libc. Neither includes process startup."
echo "      Rex ELF size excludes dynamic linker; C binaries link against libc."
echo "============================================================"
