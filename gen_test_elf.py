import sys
e_hdr = bytearray([
    0x7F, ord('E'), ord('L'), ord('F'), 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    2, 0, 62, 0, 1, 0, 0, 0,
    0x78, 0x00, 0x40, 0, 0, 0, 0, 0,
    64, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 64, 0, 56, 0, 1, 0, 0, 0, 0, 0, 0, 0
])
p_hdr = bytearray([
    1, 0, 0, 0, 7, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0x40, 0, 0, 0, 0, 0,
    0, 0, 0x40, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0x10, 0, 0, 0, 0, 0, 0
])
code = bytearray([
    0x48, 0xC7, 0xC0, 0x3C, 0x00, 0x00, 0x00,
    0x48, 0x31, 0xFF,
    0x0F, 0x05
])
total_filesz = len(e_hdr) + len(p_hdr) + len(code)
p_hdr[32:40] = total_filesz.to_bytes(8, 'little')
p_hdr[40:48] = total_filesz.to_bytes(8, 'little')
with open("test_elf", "wb") as f:
    f.write(e_hdr)
    f.write(p_hdr)
    f.write(code)
