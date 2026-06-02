// Edge case: string literal length limits (issue #34)
// tok_ident is resb 64; max content is 63 bytes (null-terminated).
// After fix: strings longer than 63 chars are silently truncated at 63 bytes.
// Before fix: overlong strings corrupted adjacent BSS (tok_int, lex_src, etc.)

// Exactly 63 characters — should print in full
str s1 = "123456789012345678901234567890123456789012345678901234567890123"
output s1       // expected: 63-char string above

// Short string — unaffected
str s2 = "hello"
output s2       // expected: hello

// 64-character string — 64th char 'X' must be truncated (silent, no crash)
str s3 = "1234567890123456789012345678901234567890123456789012345678901234"
output s3       // expected: 63 chars (the '4' at position 64 is dropped)

// Verify other variables still work after a long string was lexed
int x = 42
output x        // expected: 42
