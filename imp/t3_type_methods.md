# T3 Report — Type Methods & Casts

**Status:** Complete  
**Regression:** 37/37 baseline → **42/42** (5 new test files)  
**Build:** `make clean && make rexc` — clean

---

## 1. What was implemented

### `str(x)` casts — `parser/parser.asm` `.cast_to_str`
`str(int)`, `str(float)`, `str(bool)`, `str(char)`, `str(byte)`, `str(str)` (no-op).
Maps to existing cast infrastructure via new IR ops:

| Source | IR |
|---|---|
| int    | `IR_ITOS`  → `rt_conv.bin @0x141` (to_dec) |
| float  | `IR_FTOS`  → `rt_conv.bin @0x196` (ftos) |
| bool   | `IR_BTOS`  → `rt_conv.bin @0x63A` |
| char   | `IR_CTOS`  → `rt_conv.bin @0x66D` (1-char string) |
| byte   | `IR_CTOS`  → raw single byte (see §6) |

### `int pow` — method + standalone
- `n.pow(m)` → `IR_POW_I` → `rt_math.bin @0x185` (int_pow); arg must be `int`.
- `pow(a, b)`: both `int` → `IR_POW_I` (int result); both `float` → `IR_POW_F`
  (`rt_math.bin @0x53`); mixed → **compile error** (Rex has no implicit coercion).
- Negative exponent → 0 (integer truncation; see §6).

### `bool` methods
- `.str()` → `IR_BTOS` ("true"/"neutral"/"false", Łukasiewicz tri-state).

### `char` methods
- Conversions: `.str()` (`IR_CTOS`), `.int()`, `.byte()`, `.digit()` (int 0–9, −1 if not digit).
- Predicates: `.alpha()`, `.alnum()`, `.whitespace()`, `.punct()`, `.printable()`, `.ascii()`
  (via existing `IR_IS_*` emitters), plus existing `is_upper`/`is_lower` predicates.
- Transforms: `.upper()` / `.lower()` (`IR_TO_UPPER` / `IR_TO_LOWER`).
- Both `is_alpha` and `alpha` spellings accepted (aliases in the dispatch).

### `byte` methods
- `.str()` (`IR_CTOS`, raw single byte), `.int()`, `.char()` (zero-extend → int / char).
- `.bit(n)` → `IR_BYTE_BIT` (bool; arg must be int), `.rotate_left(n)` / `.rotate_right(n)`
  → `IR_BYTE_ROL` / `IR_BYTE_ROR` (inline `rol/ror al,cl`, 8-bit rotate).
- `.hex()` → `IR_BYTE_HEX` (`rt_conv.bin @0x67E`, 2-char lowercase), `.bin()` → `IR_BYTE_BIN`
  (`rt_conv.bin @0x6B7`, 8-char), `.zero()`, `.ascii()`.

### Standalone builtins
`alpha`, `alnum`, `digit` (int), `upper`, `lower`, `whitespace`, `punct`, `printable`,
`ascii`, `hex`, `bin`, `oct`, `zero`, `positive`, `negative`, `even`, `odd`, `nan`,
`inf`, `finite`. Reuse existing IR (char predicates, `IR_TO_HEX_STR`/`IR_TO_BIN_STR`/
`IR_TO_OCT_STR`, `IR_IS_ZERO_F`/`IR_IS_POS_F`/`IR_IS_NEG_F`, `IR_CMP_BOOL`, …).

### Lexer / parser integration
`.str()` / `.int()` / `.byte()` / `.char()` method names lex as `TOK_TYPE`; `.pp_loop`
now accepts `TOK_TYPE` after a dot so these method names dispatch correctly.

---

## 2. Codegen changes — `codegen/codegen.asm`

- **need-scan** routes `ITOS/FTOS/STOI/STOF/BTOS/CTOS/BYTE_HEX/BYTE_BIN` → `.set_conv`,
  `POW_I` → `.set_math`.
- **Dispatch jumps** added after `IR_TO_OCT_STR` for all 12 new opcodes.
- **12 emitters** appended after the jump-patch resolver, before `resolve_proto_patches`
  (`cge_itos_op`, `cge_ftos_op`, `cge_stoi_op`, `cge_stof_op`, `cge_btos_op`,
  `cge_ctos_op`, `cge_pow_i_op`, `cge_byte_bit_op`, `cge_byte_rol_op`,
  `cge_byte_ror_op`, `cge_byte_hex_op`, `cge_byte_bin_op`). Each ends
  `store_dst_spill` + `jmp codegen_emit_all.next_ir`.

---

## 3. Pre-existing bugs fixed (uncovered by this task)

These were latent — nothing in the baseline suite exercised them.

| Bug | Symptom | Fix |
|---|---|---|
| `cge_cpred_emit_load_rax` | Every char predicate (`is_alpha`, `is_digit`, `is_alnum`, `is_space`, `is_upper`, …) returned `false` | Encoded `mov r(src1), rax` (`4C 8B`); corrected to `mov rax, r(src1)` (`4C 89`) |
| `cge_math_pow_op` xmm1 load | `pow(2.0,3.0)` → 1.0 (second arg clobbered xmm0) | modrm `0xC0\|src2` → `0xC8\|src2` (xmm1) |
| `rt_math_pow` algorithm | Garbage results / hung harness (x87 `fscale` double-counted the integer part) | Rewrote using `t=y·log2(x)`, `frac=t−round(t)`, `2^frac·2^round(t)`; kept 80-byte slot @0x53 so all later offsets hold |
| `rt_math_cbrt` stack | Segfault on any `cbrt()` (`push dword 3` pushes 8 bytes in 64-bit, restored with `add rsp,4`) | `add rsp,4` → `add rsp,8` (same length) |
| `rt_math_int_pow` negative exp | Infinite loop (`dec rsi` never reaches 0) | `js .pow_neg` → return 0 |

---

## 4. Hardcoded runtime offsets (verified against blobs)

| Blob | Offset | Function |
|---|---|---|
| rt_conv.bin (1781 B) | 0x48, 0x97, 0xF1 | to_bin, to_hex, to_oct (int) |
| rt_conv.bin | 0x141 | to_dec (int→decimal str) |
| rt_conv.bin | 0x196 | ftos (float→str) |
| rt_conv.bin | 0x39E | stoi (str→int) |
| rt_conv.bin | 0x4BD | stof (str→float) |
| rt_conv.bin | 0x63A | btos (bool→str) |
| rt_conv.bin | 0x66D | ctos (char/byte→1-char str) |
| rt_conv.bin | 0x67E | btohex (byte→hex) |
| rt_conv.bin | 0x6B7 | btobin (byte→bin) |
| rt_math.bin (417 B) | 0x53, 0xA3, 0x112, 0x158, 0x185 | pow_f, cbrt, gcd, lcm, int_pow |

`rt_math.bin` grew 412 → 417 B (int_pow negative-exponent branch); all function
offsets preserved (pow_f padded to its fixed 80-byte slot; cbrt fix same-length).

---

## 5. IR opcodes used (already declared in `include/rex_ir.inc`)

`IR_BTOS=0x91`, `IR_CTOS=0x92`, `IR_POW_I=0x93`, `IR_BYTE_BIT=0x94`,
`IR_BYTE_ROL=0x95`, `IR_BYTE_ROR=0x96`, `IR_BYTE_HEX=0x97`, `IR_BYTE_BIN=0x98`,
`IR_ITOS=0xAC`, `IR_FTOS=0xAD`, `IR_STOI=0xAE`, `IR_STOF=0xAF`.
`IR_STOI`/`IR_STOF` are implemented in codegen but currently unused by the parser
(no `int(str)` / `float(str)` cast path yet) — kept for the design.

---

## 6. Ambiguity resolutions / decisions

- **`char.digit()` returns `int`** (value of '0'–'9', −1 otherwise), per the task
  mandate. The design doc also lists a bool classification form under the same name;
  the int form wins.
- **`str(byte)` → raw single byte** (shared `IR_CTOS` path, same as `char.str()`).
  Bytes >127 print as a raw byte, not UTF-8. Textual forms are available via
  `hex()` / `bin()`.
- **Mixed-type `pow` is a compile error** (`Type mismatch`), consistent with Rex
  rejecting `2.0 + 2`. `int.pow(int)`, `float.pow(float)`, `pow(int,int)`,
  `pow(float,float)`.
- **`int` pow with negative exponent → 0** (integer truncation of x⁻ⁿ).
- **`upper()`/`lower()`** are char transforms; the bool predicates are
  `is_upper()`/`is_lower()` (pre-existing names).
- **`output(char)` emits the raw byte without a trailing newline** — pre-existing
  runtime convention (rt_prc), unchanged.
- **Byte method names** use the design-doc bare forms (`.zero()`, `.ascii()`),
  matching the byte/char method style.

---

## 7. Tests

New files in `tests/` (source + generated `.expected`):
`test_str_cast`, `test_int_pow`, `test_char_methods`, `test_byte_ops`,
`test_type_builtins`.

Suite: **42 passed, 0 failed, 0 skipped** (baseline 37 → 42).

## 8. Limitations

- `str(byte)` raw-byte output for values >127.
- `int` pow overflow wraps silently (best-effort).
- Float `pow` with negative base and non-integer exponent → NaN (x87).
- Not in scope (documented in design but unimplemented): byte `popcount`,
  `leading_zeros`, `trailing_zeros`, `swap_nibbles`; float `atan2`, `log(base)`,
  `log2`, `log10`; standalone `log`/`atan2`; `int(str)` / `float(str)` casts.
