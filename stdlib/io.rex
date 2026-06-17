/// io.rex — File and Stream I/O for Rex.

// REQUIRES: syscall intercept ($) — Stage 9
// These protocols provide an interface for interacting with the OS file system.

/// print(s) — Output a string to stdout with a newline.
prot print():
    pass

/// println(s) — Alias for print(s).
prot println():
    pass

/// write(s) — Output a string to stdout without an automatic newline.
prot write():
    pass

/// read_file(path) -> str — Read entire file into a heap-allocated string.
prot read_file() -> str:
    return ""

/// write_file(path, content) — Write string to file (overwrites existing).
prot write_file():
    pass

/// append_file(path, content) — Append string to end of file.
prot append_file():
    pass
