#!/bin/bash
PASS=0; FAIL=0
for rex_file in tests/suite/t_*.rex; do
  name="${rex_file%.rex}"
  expected="${name}.expected"
  [ -f "$expected" ] || continue
  ./rexc "$rex_file" -o /tmp/rex_test_out 2>/dev/null && \
  actual=$(/tmp/rex_test_out 2>/dev/null) && \
  [ "$actual" = "$(cat $expected)" ] && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
done
echo "${PASS}/$((PASS+FAIL)) tests passed"
[ $FAIL -eq 0 ]
