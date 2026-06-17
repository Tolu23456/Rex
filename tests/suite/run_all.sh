#!/bin/bash
PASS=0; FAIL=0
FAILURES=""
for rex_file in tests/suite/t_*.rex; do
  name="${rex_file%.rex}"
  expected="${name}.expected"
  [ -f "$expected" ] || continue
  ./rexc "$rex_file" 2>/dev/null
  if [ $? -ne 0 ]; then
    FAIL=$((FAIL+1))
    FAILURES="$FAILURES\n  FAIL (compile): $rex_file"
    continue
  fi
  actual=$(./output 2>/dev/null)
  exp=$(cat "$expected")
  if [ "$actual" = "$exp" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    FAILURES="$FAILURES\n  FAIL (output): $rex_file"
    FAILURES="$FAILURES\n    expected: $(echo "$exp" | head -3)"
    FAILURES="$FAILURES\n    got:      $(echo "$actual" | head -3)"
  fi
done
echo "${PASS}/$((PASS+FAIL)) tests passed"
if [ -n "$FAILURES" ]; then
  echo -e "$FAILURES"
fi
[ $FAIL -eq 0 ]
