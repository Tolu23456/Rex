// test_err.rex — err statement writes to stderr
int code
:code = 0

if code == 0:
    err "no error code set"

// err with a different message
err "this goes to stderr"

output 1
