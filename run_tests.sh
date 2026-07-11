#!/usr/bin/env bash
# run_tests.sh — Rex compiler regression test suite
# Usage: ./run_tests.sh [--verbose]
#
# Compiles each .rex test file, runs the binary, and compares output
# against expected values embedded in the test file as "// Expected output:" blocks.

set -euo pipefail
VERBOSE=0
[[ "${1:-}" == "--verbose" ]] && VERBOSE=1

PASS=0
FAIL=0
SKIP=0

REXC="./rexc"
TMP_BIN="/tmp/rex_test_bin"

if [[ ! -x "$REXC" ]]; then
    echo "ERROR: $REXC not found. Run 'make all' first."
    exit 1
fi

run_one() {
    local src="$1"
    local name
    name=$(basename "$src" .rex)

    # Extract expected output lines from the source file.
    # Lines after "// Expected output:" up to the next blank line or non-comment line
    # are used as expected.  They must be of the form "//   <value>".
    local expected
    expected=$(awk '
        /\/\/ Expected output:/ { capture=1; next }
        capture && /^\/\/ / { sub(/^\/\/ +/, ""); print; next }
        capture { capture=0 }
    ' "$src")

    if [[ -z "$expected" ]]; then
        echo "SKIP $name (no expected output)"
        ((SKIP++)) || true
        return
    fi

    # Compile
    local compile_out compile_err compile_rc
    compile_out=$("$REXC" "$src" -o "$TMP_BIN" 2>&1) || compile_rc=$?
    if [[ "${compile_rc:-0}" -ne 0 ]]; then
        echo "FAIL $name — compiler exited with code ${compile_rc:-?}"
        [[ $VERBOSE -eq 1 ]] && echo "  compiler output: $compile_out"
        ((FAIL++)) || true
        return
    fi

    # Run
    local actual run_rc
    actual=$("$TMP_BIN" 2>&1) || run_rc=$?
    if [[ "${run_rc:-0}" -ne 0 ]]; then
        echo "FAIL $name — binary exited with code ${run_rc:-?}"
        [[ $VERBOSE -eq 1 ]] && printf "  actual output:\n%s\n" "$actual"
        ((FAIL++)) || true
        return
    fi

    # Compare
    if [[ "$actual" == "$expected" ]]; then
        echo "PASS $name"
        ((PASS++)) || true
    else
        echo "FAIL $name"
        if [[ $VERBOSE -eq 1 ]]; then
            echo "  Expected:"
            echo "$expected" | sed 's/^/    /'
            echo "  Got:"
            echo "$actual" | sed 's/^/    /'
        fi
        ((FAIL++)) || true
    fi
}

echo "=== Rex Compiler Test Suite ==="
echo ""

for f in tests/*.rex; do
    run_one "$f"
done

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped ==="
[[ $FAIL -eq 0 ]]
