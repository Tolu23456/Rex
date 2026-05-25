# Rex V5.0 Compiler — Implementation Todo

## Stage 0 — Core Infrastructure (Complete ✅)
- [x] Modular 6-folder architecture: `main/`, `lexer/`, `parser/`, `codegen/`, `headers/`, `runtime/`
- [x] `int x` — mutable variable declaration
- [x] `int x = 42` — immutable constant with inline init
- [x] `:x = N` — mutable assignment + compile-time const guard
- [x] `output x` / `output N` — print variable or int literal
- [x] `if x == N:` — conditional branch with JNE patch stack
- [x] `elif x == N:` — chained elif (multiple allowed)
- [x] `else:` — fallback branch
- [x] Three-level jump-patch architecture (`jump_patch_stack`, `end_jump_stack`, `chain_base_stack`)
- [x] `docs/language_comparison.md` — Rex vs C / C++ / Rust / Zig / Python / JS matrix
- [x] Three passing tests: `test.rex`→42, `conditional_test.rex`→1/2, `elif_else_test.rex`→2/4

---

## Stage 1 — Control Flow Loops (In Progress 🔄)

### 1A. `for :i in 0..N:` range loop
- [ ] `codegen_emit_for_start(rdi=start, rsi=end)` — emit `mov edi, start`, record loop_top, emit `cmp+jge` placeholder; return loop_top
- [ ] `codegen_emit_for_end(rdi=loop_top)` — emit `inc edi; jmp backward`; patch jge; patch breaks
- [ ] `is_loop_var` flag at `var_table[entry+43]` — skip `mov edi` on output/cmp for loop counter
- [ ] `codegen_output_loop_var` — emit only `call rt_pri` (edi already holds loop value)
- [ ] `parse_for` in parser — tokenize `for :i in 0..N:`, register loop var, dispatch codegen

### 1B. `stop` keyword (loop break)
- [ ] `break_jump_stack` / `break_jump_depth` / `break_base_stack` / `break_base_depth` in codegen BSS
- [ ] `codegen_save_break_base` — snapshot `break_jump_depth` for nested loops
- [ ] `codegen_emit_break` — emit `jmp 0` placeholder, push to `break_jump_stack`
- [ ] `codegen_patch_breaks` — bulk-patch all break jmps → current `out_idx`
- [ ] `parse_stop` in parser

### 1C. `while x == N:` loop
- [ ] `TOK_WHILE` token (already lexed ✅)
- [ ] `codegen_emit_while_start(rdi=var_val, rsi=cmp_val, rdx=is_loop_var)` — record loop_top; emit `mov edi+cmp+jne` placeholder; return loop_top
- [ ] `codegen_emit_while_end(rdi=loop_top)` — emit `jmp backward`; patch jne; patch breaks
- [ ] `parse_while` in parser

### 1D. `if :i == N:` inside loop body
- [ ] Update `codegen_emit_cmp_jne` signature: add `rdx=skip_mov_edi` flag
- [ ] Update `parse_if` `.branch_parse_cond` to pass `is_loop_var` in rdx

---

## Stage 2 — Protocols (In Progress 🔄)

### 2A. Protocol definition `prot name():`
- [ ] `TOK_PROT` / `TOK_RETURN` / `TOK_AT` tokens (already lexed ✅)
- [ ] `proto_table` in parser BSS — 32 entries × 40 bytes (32-byte name + 8-byte offset)
- [ ] `proto_count` / `prot_body_depth` in parser BSS
- [ ] `proto_find(rdi=name_ptr)` — search proto_table; return buffer offset or -1
- [ ] `codegen_begin_protos` — emit `E9 00000000` jmp placeholder once; set `prot_jmp_live`
- [ ] `codegen_end_protos` — patch jmp → current `out_idx`; clear `prot_jmp_live` (idempotent, guarded by `prot_body_depth`)
- [ ] `parse_prot` in parser — scan to colon, register in proto_table, emit body, emit implicit `ret`

### 2B. `return N` / `return` inside prot
- [ ] `codegen_emit_ret` — emit `C3`
- [ ] `codegen_emit_mov_eax_imm32(rdi=value)` — emit `B8 imm32`
- [ ] `parse_return` in parser

### 2C. `@name()` standalone call
- [ ] `codegen_emit_call_prot(rdi=prot_offset)` — emit `E8 rel32`
- [ ] `parse_at` in parser — look up proto_table, call `codegen_end_protos`, emit call

---

## Stage 3 — Additional Types

### 3A. `float` type
- [ ] `TOK_TYPE_FLOAT` lexer token
- [ ] `TOK_FLOAT_LIT` lexer token + float literal parse
- [ ] XMM register allocation in codegen (xmm0, xmm1)
- [ ] `rt_prf` blob in `runtime/runtime.asm` — print float + newline
- [ ] `float a = 5.5` inline init
- [ ] `float c; :c = a + b` float arithmetic (addss / addsd)
- [ ] `output wages` for float vars

### 3B. `complex` type
- [ ] `complex sum_j = 12j` — packed dual 64-bit float (128-bit xmm register)
- [ ] `complex vector_coord = 4.5 + 3.0j` — complex literal
- [ ] Complex arithmetic operations

### 3C. `bool` tri-state type
- [ ] `TOK_TYPE_BOOL` / `TOK_TRUE` / `TOK_FALSE` / `TOK_UNKNOWN` tokens
- [ ] `bool execution_flag = true` / `false` / `unknown` declaration
- [ ] `rdrand` / `sys_getrandom` emission for `unknown` → stochastic runtime branch
- [ ] `if runtime_state:` condition on bool var

### 3D. `str` type
- [ ] `TOK_TYPE_STR` / `TOK_STR_LIT` tokens
- [ ] UTF-8 length-prefixed string storage in var table
- [ ] `str name` mutable declaration
- [ ] `:name = "Rex Builder"` string assignment
- [ ] `output name` string print via `rt_prs`

---

## Stage 4 — Native Collections (SipHash + Open Addressing)

### 4A. Dynamic sequences `@`
- [ ] `@dynamic_seq = @[1, 2, 3]` — dynamic sequence constructor
- [ ] Index read `output :dynamic_seq[0]`
- [ ] Index write `:dynamic_seq[0] = 42`
- [ ] `@fixed_seq = @[1, 2, 3]:3` — fixed-size sequence

### 4B. Dictionaries
- [ ] `dict user_map = {"name": "Rex", "version": 5}` declaration
- [ ] SipHash + open-addressing hash table in `runtime/runtime.asm`
- [ ] Key lookup `output :user_map["name"]`
- [ ] Key write `:user_map["version"] = 6`

### 4C. Sets and Tuples
- [ ] `set explicit_set = <{3, 5, 6, 7}>` declaration
- [ ] `set short_set = :{3, 5, 6, 7}` declaration
- [ ] `tup user_tuple = (string name: "Rex", int age: 15)` typed tuple
- [ ] Tuple field access

---

## Stage 5 — Advanced Protocols

### 5A. Parameterized protocols
- [ ] `prot compute_factorial(int n) -> int:` — int parameter
- [ ] Register-based parameter passing (rdi, rsi, rdx, rcx per sysv ABI)
- [ ] Local variable stack frame allocation inside prot body
- [ ] Recursive call `@compute_factorial(next_val)` with argument

### 5B. Protocol return to variables
- [ ] `:greet = @greet_user()` — runtime result stored in variable
- [ ] `:factorial_res = @compute_factorial(5)` — typed result propagation
- [ ] `output(x)` parenthesized output form

---

## Stage 6 — Memory Allocator Contexts

- [ ] `runtime/memory.asm` — global context index tracker
- [ ] AMM (Automatic Memory Management) — default allocator
- [ ] AGC (Automatic Garbage Collector) — default GC
- [ ] `use mm N gc N:` — indentation-scoped allocator handoff block
  - [ ] `TOK_USE` / `TOK_MM` / `TOK_GC` tokens
  - [ ] Allocator context push/pop on INDENT/DEDENT
  - [ ] All heap allocations within block use specified mm/gc
  - [ ] On DEDENT: restore previous mm/gc context
  - [ ] No cross-block allocator conflicts

---

## Stage 7 — Runtime Hardening

- [ ] Error output to stderr (fd=2) instead of stdout
- [ ] Error categories: `Syntax Error`, `Runtime Error`, `Compilation Error`, `Indentation Error`
- [ ] Stack-frame allocator in codegen — true runtime variables (replace compile-time var table)
- [ ] Variable table growth beyond 16 entries (linear scan → open-addressing hash map)
- [ ] `-o <file>` output flag in main/main.asm
- [ ] Multi-file compilation support

---

## Stage 8 — Speed / Binary Quality

- [x] `docs/language_comparison.md` — language feature matrix
- [ ] `docs/speed_comparison.md` — Rex vs C/C++/Rust/Zig/Python/JS benchmark timings
- [ ] Maintain `< 1 KB` binary size target for compiled output
- [ ] Verify zero-overhead hot paths (no unnecessary syscalls in tight loops)
- [ ] Dead-code elimination pass in codegen

---

## Completed Tests

| Test | Expected | Status |
|---|---|---|
| `tests/test.rex` | `42` | ✅ |
| `tests/conditional_test.rex` | `1\n2` | ✅ |
| `tests/elif_else_test.rex` | `2\n4` | ✅ |
| `tests/for_test.rex` | `0\n1\n2\n3\n4\n99` | 🔄 |
| `tests/prot_test.rex` | `42\n99` | 🔄 |
