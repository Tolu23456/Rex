#!/usr/bin/env bash
# run_tests.sh — Rex compiler regression test suite
# Usage: ./run_tests.sh [--verbose]
#
# For each tests/*.rx that has a matching tests/*.expected file,
# compiles the source, runs the binary, and diffs actual vs expected.

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
    local expected_file="${src%.rx}.expected"
    local name
    name=$(basename "$src" .rx)

    if [[ ! -f "$expected_file" ]]; then
        if [[ -f "${src%.rx}.err" ]]; then
            # Negative test: compile must fail with the expected message.
            local err_file="${src%.rx}.err"
            local compile_out compile_rc=0
            compile_out=$("$REXC" "$src" -o "$TMP_BIN" 2>&1) || compile_rc=$?
            if [[ $compile_rc -eq 0 ]]; then
                echo "FAIL $name — expected compile error but succeeded"
                ((FAIL++)) || true
                return
            fi
            if [[ "$compile_out" != *"$(cat "$err_file")"* ]]; then
                echo "FAIL $name — error message mismatch"
                if [[ $VERBOSE -eq 1 ]]; then
                    echo "  expected substring: $(cat "$err_file")"
                    printf '  actual: %s\n' "$compile_out"
                fi
                ((FAIL++)) || true
                return
            fi
            echo "PASS $name"
            ((PASS++)) || true
            return
        fi
        echo "SKIP $name (no .expected file)"
        ((SKIP++)) || true
        return
    fi

    # Compile
    local compile_out compile_rc=0
    compile_out=$("$REXC" "$src" -o "$TMP_BIN" 2>&1) || compile_rc=$?
    if [[ $compile_rc -ne 0 ]]; then
        echo "FAIL $name — compiler exited with code $compile_rc"
        [[ $VERBOSE -eq 1 ]] && echo "  compiler output: $compile_out"
        ((FAIL++)) || true
        return
    fi

    # Run
    local actual run_rc=0
    actual=$("$TMP_BIN" 2>/dev/null) || run_rc=$?
    if [[ $run_rc -ne 0 ]]; then
        echo "FAIL $name — binary exited with code $run_rc"
        [[ $VERBOSE -eq 1 ]] && printf "  actual output:\n%s\n" "$actual"
        ((FAIL++)) || true
        return
    fi

    # Compare (strip trailing newline from actual to match file content)
    local expected
    expected=$(cat "$expected_file")
    # Remove trailing newline from expected for fair comparison
    expected="${expected%$'\n'}"

    if [[ "$actual" == "$expected" ]]; then
        echo "PASS $name"
        ((PASS++)) || true
    else
        echo "FAIL $name"
        if [[ $VERBOSE -eq 1 ]]; then
            diff <(echo "$expected") <(echo "$actual") | sed 's/^/  /' || true
        fi
        ((FAIL++)) || true
    fi
}

echo "=== Rex Compiler Test Suite ==="
echo ""

for f in tests/*.rx; do
    run_one "$f"
done

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped ==="
[[ $FAIL -eq 0 ]]
