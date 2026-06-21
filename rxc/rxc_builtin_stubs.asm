; rxc/rxc_builtin_stubs.asm — stub implementations for self-hosting builtins
; in the rexc_rxc bytecode backend.  These emit a RIC HALT opcode (0xFF)
; so the rxc backend cleanly signals "not yet implemented" at runtime.
default rel
%include "include/rex_defs.inc"

global codegen_emit_str_at_rax
global codegen_emit_file_open_inline, codegen_emit_file_read_all_call
global codegen_emit_file_write_inline, codegen_emit_file_close_inline
global codegen_emit_exit_inline, codegen_emit_alloc_inline
global codegen_emit_char_from_rax
global codegen_emit_str_eq_rax, codegen_emit_str_slice_rax

section .text

codegen_emit_str_at_rax:
codegen_emit_file_open_inline:
codegen_emit_file_read_all_call:
codegen_emit_file_write_inline:
codegen_emit_file_close_inline:
codegen_emit_exit_inline:
codegen_emit_alloc_inline:
codegen_emit_char_from_rax:
codegen_emit_str_eq_rax:
codegen_emit_str_slice_rax:
    ret
