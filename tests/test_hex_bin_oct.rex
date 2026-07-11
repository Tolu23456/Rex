// test_hex_bin_oct.rex
// Tests alternative integer literal formats.
//
// Expected output:
//   255
//   255
//   255
//   16

int hex_val = 0xFF
output(hex_val)

int bin_val = 0b11111111
output(bin_val)

int oct_val = 0o377
output(oct_val)

int hex2 = 0x10
output(hex2)
