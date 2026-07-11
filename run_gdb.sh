#!/bin/bash
gdb -batch -ex "run" -ex "bt" -ex "quit" --args ./rexc tests/test_basic.rex &
PID=$!
sleep 0.5
kill -INT $PID
wait $PID
