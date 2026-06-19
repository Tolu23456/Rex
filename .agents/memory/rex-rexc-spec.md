---
name: RexC Instruction Set Specification
description: Full specification for RexC bytecode format and RIC (Rex Instruction Code) SIMD-like high-performance instruction layer.
---

# RexC Instruction Set Specification

## Overview
RexC (.rxc) is Rex's portable bytecode format. Programs compiled to RexC run on any platform that has the RexC runtime. RIC (Rex Instruction Code) is the high-performance SIMD-like sublayer within RexC for compute-intensive operations.

---

## File Format

```
[4 bytes]  Magic: 0x52 0x45 0x58 0x43  ("REXC")
[2 bytes]  Version: major.minor
[2 bytes]  Flags
[4 bytes]  Entry point offset
[4 bytes]  Constant pool offset
[4 bytes]  Symbol table offset
[N bytes]  Instructions
```

---

## Type System

| Code | Type     | Size    |
|------|----------|---------|
| 0x00 | void     | 0       |
| 0x01 | i8       | 1 byte  |
| 0x02 | i16      | 2 bytes |
| 0x03 | i32      | 4 bytes |
| 0x04 | i64      | 8 bytes |
| 0x05 | u8       | 1 byte  |
| 0x06 | u16      | 2 bytes |
| 0x07 | u32      | 4 bytes |
| 0x08 | u64      | 8 bytes |
| 0x09 | f32      | 4 bytes |
| 0x0A | f64      | 8 bytes |
| 0x0B | bool     | 1 byte  |
| 0x0C | ptr      | 8 bytes |
| 0x0D | str      | ptr+len |

---

## Instruction Encoding

Each instruction:
```
[1 byte]  opcode
[1 byte]  type tag (where applicable)
[N bytes] operands (0–3 register IDs or immediate values)
```

Registers are virtual (unlimited); the runtime allocates physical registers or stack slots.

---

## Core Instructions (0x00–0x3F)

### Control Flow
| Opcode | Mnemonic     | Description                        |
|--------|--------------|------------------------------------|
| 0x00   | nop          | No operation                       |
| 0x01   | halt         | Stop execution                     |
| 0x02   | ret          | Return from function               |
| 0x03   | ret.val r0   | Return value in r0                 |
| 0x04   | call sym     | Call function by symbol            |
| 0x05   | call.r r0    | Call function pointer in r0        |
| 0x06   | jmp label    | Unconditional jump                 |
| 0x07   | jmp.t r0, label  | Jump if r0 is true              |
| 0x08   | jmp.f r0, label  | Jump if r0 is false             |
| 0x09   | jmp.eq r0, r1, label | Jump if r0 == r1            |
| 0x0A   | jmp.ne r0, r1, label | Jump if r0 != r1            |
| 0x0B   | jmp.lt r0, r1, label | Jump if r0 < r1             |
| 0x0C   | jmp.gt r0, r1, label | Jump if r0 > r1             |
| 0x0D   | jmp.le r0, r1, label | Jump if r0 <= r1            |
| 0x0E   | jmp.ge r0, r1, label | Jump if r0 >= r1            |

### Stack & Registers
| Opcode | Mnemonic         | Description                    |
|--------|------------------|--------------------------------|
| 0x10   | push r0          | Push register onto stack       |
| 0x11   | pop r0           | Pop stack into register        |
| 0x12   | mov r0, r1       | Copy r1 into r0                |
| 0x13   | load.imm r0, imm | Load immediate into r0         |
| 0x14   | load.mem r0, [r1]| Load from memory address       |
| 0x15   | store.mem [r0], r1 | Store r1 to memory address   |
| 0x16   | lea r0, sym      | Load address of symbol         |

### Arithmetic (integer)
| Opcode | Mnemonic           | Description          |
|--------|--------------------|----------------------|
| 0x20   | add r0, r1, r2     | r0 = r1 + r2         |
| 0x21   | sub r0, r1, r2     | r0 = r1 - r2         |
| 0x22   | mul r0, r1, r2     | r0 = r1 * r2         |
| 0x23   | div r0, r1, r2     | r0 = r1 / r2         |
| 0x24   | mod r0, r1, r2     | r0 = r1 % r2         |
| 0x25   | neg r0, r1         | r0 = -r1             |
| 0x26   | inc r0             | r0 = r0 + 1          |
| 0x27   | dec r0             | r0 = r0 - 1          |

### Arithmetic (float)
| Opcode | Mnemonic           | Description          |
|--------|--------------------|----------------------|
| 0x28   | fadd r0, r1, r2    | r0 = r1 + r2 (float) |
| 0x29   | fsub r0, r1, r2    | r0 = r1 - r2 (float) |
| 0x2A   | fmul r0, r1, r2    | r0 = r1 * r2 (float) |
| 0x2B   | fdiv r0, r1, r2    | r0 = r1 / r2 (float) |
| 0x2C   | fma  r0, r1, r2, r3| r0 = r1*r2 + r3 (fused multiply-add) |
| 0x2D   | fsqrt r0, r1       | r0 = sqrt(r1)        |
| 0x2E   | fabs  r0, r1       | r0 = abs(r1)         |

### Bitwise & Logic
| Opcode | Mnemonic           | Description          |
|--------|--------------------|----------------------|
| 0x30   | and r0, r1, r2     | r0 = r1 & r2         |
| 0x31   | or  r0, r1, r2     | r0 = r1 \| r2        |
| 0x32   | xor r0, r1, r2     | r0 = r1 ^ r2         |
| 0x33   | not r0, r1         | r0 = ~r1             |
| 0x34   | shl r0, r1, r2     | r0 = r1 << r2        |
| 0x35   | shr r0, r1, r2     | r0 = r1 >> r2 (logical) |
| 0x36   | sar r0, r1, r2     | r0 = r1 >> r2 (arithmetic) |

### Comparison
| Opcode | Mnemonic           | Description          |
|--------|--------------------|----------------------|
| 0x38   | cmp.eq r0, r1, r2  | r0 = (r1 == r2)      |
| 0x39   | cmp.ne r0, r1, r2  | r0 = (r1 != r2)      |
| 0x3A   | cmp.lt r0, r1, r2  | r0 = (r1 < r2)       |
| 0x3B   | cmp.gt r0, r1, r2  | r0 = (r1 > r2)       |
| 0x3C   | cmp.le r0, r1, r2  | r0 = (r1 <= r2)      |
| 0x3D   | cmp.ge r0, r1, r2  | r0 = (r1 >= r2)      |

---

## Memory Instructions (0x40–0x5F)

| Opcode | Mnemonic              | Description                        |
|--------|-----------------------|------------------------------------|
| 0x40   | alloc r0, r1          | Allocate r1 bytes, address in r0   |
| 0x41   | free r0               | Free allocation at r0              |
| 0x42   | copy r0, r1, r2       | Copy r2 bytes from r1 to r0        |
| 0x43   | zero r0, r1           | Zero r1 bytes at r0                |
| 0x44   | sizeof r0, type       | r0 = size of type in bytes         |
| 0x45   | cast r0, r1, type     | Cast r1 to type, store in r0       |
| 0x46   | field.load r0, r1, n  | Load field n of struct at r1       |
| 0x47   | field.store r0, n, r1 | Store r1 into field n of struct r0 |
| 0x48   | index r0, r1, r2      | r0 = r1[r2] (array indexing)       |
| 0x49   | index.store r0, r1, r2| r0[r1] = r2                        |
| 0x4A   | slice r0, r1, r2, r3  | r0 = r1[r2..r3]                    |
| 0x4B   | len r0, r1            | r0 = length of array/str r1        |

---

## RIC — Rex Instruction Code (0x80–0xFF)

RIC instructions operate on vector registers (v0–v31). The runtime JIT-compiles these to native SIMD instructions per platform.

### Vector Types
| Tag  | Type    | Width      | Maps to               |
|------|---------|------------|-----------------------|
| 0x01 | i8x16   | 128-bit    | SSE2 / NEON           |
| 0x02 | i16x8   | 128-bit    | SSE2 / NEON           |
| 0x03 | i32x4   | 128-bit    | SSE4 / NEON           |
| 0x04 | i64x2   | 128-bit    | SSE4 / NEON           |
| 0x05 | f32x4   | 128-bit    | SSE / NEON            |
| 0x06 | f64x2   | 128-bit    | SSE2 / NEON           |
| 0x07 | i32x8   | 256-bit    | AVX2 / SVE            |
| 0x08 | f32x8   | 256-bit    | AVX / SVE             |
| 0x09 | f64x4   | 256-bit    | AVX / SVE             |
| 0x0A | i32x16  | 512-bit    | AVX-512 / SVE         |
| 0x0B | f32x16  | 512-bit    | AVX-512 / SVE         |

### RIC Arithmetic
| Opcode | Mnemonic                   | Description                      |
|--------|----------------------------|----------------------------------|
| 0x80   | ric.add vtype v0, v1, v2   | Vector add                       |
| 0x81   | ric.sub vtype v0, v1, v2   | Vector subtract                  |
| 0x82   | ric.mul vtype v0, v1, v2   | Vector multiply                  |
| 0x83   | ric.div vtype v0, v1, v2   | Vector divide                    |
| 0x84   | ric.fma vtype v0, v1, v2, v3 | Fused multiply-add: v0 = v1*v2+v3 |
| 0x85   | ric.sqrt vtype v0, v1      | Vector square root               |
| 0x86   | ric.abs  vtype v0, v1      | Vector absolute value            |
| 0x87   | ric.neg  vtype v0, v1      | Vector negate                    |
| 0x88   | ric.min  vtype v0, v1, v2  | Element-wise minimum             |
| 0x89   | ric.max  vtype v0, v1, v2  | Element-wise maximum             |

### RIC Bitwise
| Opcode | Mnemonic                   | Description                      |
|--------|----------------------------|----------------------------------|
| 0x8A   | ric.and  vtype v0, v1, v2  | Vector bitwise AND               |
| 0x8B   | ric.or   vtype v0, v1, v2  | Vector bitwise OR                |
| 0x8C   | ric.xor  vtype v0, v1, v2  | Vector bitwise XOR               |
| 0x8D   | ric.not  vtype v0, v1      | Vector bitwise NOT               |
| 0x8E   | ric.shl  vtype v0, v1, imm | Vector shift left                |
| 0x8F   | ric.shr  vtype v0, v1, imm | Vector shift right               |

### RIC Memory
| Opcode | Mnemonic                     | Description                      |
|--------|------------------------------|----------------------------------|
| 0x90   | ric.load  vtype v0, [r0]     | Load vector from memory          |
| 0x91   | ric.store vtype [r0], v0     | Store vector to memory           |
| 0x92   | ric.load.strided v0, [r0], r1| Load with stride r1              |
| 0x93   | ric.gather v0, [r0], v1      | Gather from scattered addresses  |
| 0x94   | ric.scatter [r0], v0, v1     | Scatter to addresses in v1       |

### RIC Lane & Shuffle
| Opcode | Mnemonic                     | Description                      |
|--------|------------------------------|----------------------------------|
| 0x95   | ric.splat   vtype v0, r0     | Broadcast scalar r0 to all lanes |
| 0x96   | ric.extract r0, vtype v0, imm| Extract lane imm to scalar r0    |
| 0x97   | ric.insert  v0, vtype v1, imm, r0 | Insert r0 into lane imm      |
| 0x98   | ric.shuffle v0, v1, v2, mask | Permute lanes per mask           |
| 0x99   | ric.zip.lo  vtype v0, v1, v2 | Interleave low halves            |
| 0x9A   | ric.zip.hi  vtype v0, v1, v2 | Interleave high halves           |
| 0x9B   | ric.unzip.lo vtype v0, v1, v2| De-interleave even lanes         |
| 0x9C   | ric.unzip.hi vtype v0, v1, v2| De-interleave odd lanes          |

### RIC Reduction
| Opcode | Mnemonic                   | Description                      |
|--------|----------------------------|----------------------------------|
| 0xA0   | ric.sum    r0, vtype v0    | Horizontal sum of all lanes      |
| 0xA1   | ric.prod   r0, vtype v0    | Horizontal product               |
| 0xA2   | ric.hmin   r0, vtype v0    | Horizontal minimum               |
| 0xA3   | ric.hmax   r0, vtype v0    | Horizontal maximum               |
| 0xA4   | ric.dot    r0, vtype v0, v1| Dot product                      |

### RIC Comparison & Mask
| Opcode | Mnemonic                     | Description                      |
|--------|------------------------------|----------------------------------|
| 0xA5   | ric.cmp.eq mask, vtype v0, v1| Lane-wise ==, result is bitmask  |
| 0xA6   | ric.cmp.lt mask, vtype v0, v1| Lane-wise <                      |
| 0xA7   | ric.cmp.gt mask, vtype v0, v1| Lane-wise >                      |
| 0xA8   | ric.blend  v0, v1, v2, mask  | Select lanes from v1 or v2       |
| 0xA9   | ric.movmask r0, vtype v0     | Extract MSB of each lane to int  |

### RIC Conversion
| Opcode | Mnemonic                     | Description                      |
|--------|------------------------------|----------------------------------|
| 0xB0   | ric.cvt vtype_dst v0, vtype_src v1 | Convert vector type         |
| 0xB1   | ric.widen.lo vtype v0, v1    | Widen lower half lanes           |
| 0xB2   | ric.widen.hi vtype v0, v1    | Widen upper half lanes           |
| 0xB3   | ric.narrow  vtype v0, v1, v2 | Narrow two vectors into one      |

---

## I/O & System Instructions (0x60–0x7F)

| Opcode | Mnemonic           | Description                        |
|--------|--------------------|------------------------------------|
| 0x60   | print r0           | Print value in r0                  |
| 0x61   | print.str r0       | Print string at r0                 |
| 0x62   | read r0            | Read input into r0                 |
| 0x63   | open r0, r1, flags | Open file path r1, fd in r0        |
| 0x64   | close r0           | Close file descriptor r0           |
| 0x65   | read.fd r0, fd, r1 | Read r1 bytes from fd into r0      |
| 0x66   | write.fd fd, r0, r1| Write r1 bytes from r0 to fd       |
| 0x67   | exit r0            | Exit with code r0                  |
| 0x68   | argc r0            | Load argument count                |
| 0x69   | argv r0, r1        | Load argument r1 into r0           |
| 0x6A   | time r0            | Load current timestamp             |
| 0x6B   | panic r0           | Panic with message at r0           |

---

## Runtime Behavior

- Virtual registers are unlimited; the runtime assigns physical registers or stack slots per platform
- RIC instructions degrade gracefully: if hardware has no 512-bit SIMD, runtime falls back to 256-bit, then 128-bit, then scalar
- All memory accesses are bounds-checked in debug mode; bounds checks are removed in release mode
- The runtime JIT-compiles RIC to native SIMD — it does NOT interpret RIC instructions
