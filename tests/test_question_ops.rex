// test_question_ops.rex
// Exercises code paths that follow a '?' token (Bug 1 fix: lexer no longer
// consumes the character after '?' with a spurious read_char).
//
// Expected output:
//   42

int x = 42
output(x)
