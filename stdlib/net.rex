/// net.rex — Network primitives for Rex.

// REQUIRES: syscall intercept ($) — Stage 9
// These protocols provide an interface for network socket operations.

/// socket(domain, type, protocol) -> int
prot socket() -> int:
    return -1

/// connect(sockfd, addr, addrlen) -> int
prot connect() -> int:
    return -1

/// listen(sockfd, backlog) -> int
prot listen() -> int:
    return -1

/// accept(sockfd) -> int
prot accept() -> int:
    return -1

/// send(sockfd, buf) -> int
prot send() -> int:
    return -1

/// recv(sockfd, len) -> str
prot recv() -> str:
    return ""
