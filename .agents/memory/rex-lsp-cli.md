---
name: Rex LSP & CLI toolchain
description: LSP server (C bootstrap), rex CLI dispatcher, Makefile install targets, and key build quirks discovered during Phase 10 implementation.
---

## Files created
- `lsp/rex_lsp.c` — LSP 3.17 / JSON-RPC 2.0 server in C (~1700 lines)
- `rex_main.c` — `rex` CLI dispatcher (build/run/check/lsp/fmt/new/test/bench/doc/asm)
- `editors/rex.lua` — Neovim (nvim-lspconfig)
- `editors/helix_languages.toml` — Helix
- `editors/rex-mode.el` — Emacs (lsp-mode + eglot)
- `editors/zed_languages_rex.json` + `zed_lsp_settings.json` — Zed

## Install targets
- `make install-user` — installs `rex`, `rexc`, `rex_lsp` to `~/.local/bin` (no sudo needed on Replit — `/usr/local/bin` is read-only)
- `make install` — installs to `$(PREFIX)/bin` = `/usr/local/bin` (works on real Linux)
- `rex lsp` dispatches by exec'ing `rex_lsp` from the same directory as `rex`

## rexc output model
- `rexc file.rex` always writes the compiled ELF64 binary to a file named `output` in CWD.
- It emits raw ELF directly — NOT NASM intermediate. No assembler/linker step needed.
- `rex build` renames `./output` to the derived binary name.

## Cross-device rename fix
- Replit's `/tmp` is a separate filesystem from the workspace.
- `rename("output", "/tmp/rex_...")` fails with EXDEV.
- Fixed with `move_file()` helper: try rename first, fall back to copy+unlink on EXDEV.
- Affects: rex run, rex test, rex bench.

## LSP capabilities advertised
- textDocumentSync: Full (change=1)
- completionProvider, hoverProvider, definitionProvider, signatureHelpProvider
- renameProvider (with prepareProvider), documentFormattingProvider
- semanticTokensProvider/full (21 token types, 10 modifiers)
- diagnosticProvider (per-file, no workspace diagnostics)

## Diagnostics architecture
- On didOpen/didChange: fork `rexc <tmpfile>`, capture stderr, parse error lines.
- 200ms debounce NOT implemented (single-threaded server; each change triggers immediately).
- rexc errors currently lack line numbers → reported at line 0. Future: add `--json` mode to rexc.

## Pre-existing test failures (not caused by LSP work)
- `test_dict.rex` — compile error "error: expected identifier" (parser limitation)
- `test_err.rex` — exits 1 intentionally (tests `err()` builtin); test harness counts as fail
- 35/37 tests pass via `rex test --all`

**Why:** The cross-device rename is the most common pitfall when adding temp-file workflows to this codebase. Always use `move_file()`, never bare `rename()`.
