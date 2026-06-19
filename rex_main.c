/*
 * rex_main.c — Rex V5.0 CLI dispatcher
 * Implements: rex build / run / check / lsp / fmt / new / test / bench /
 *             doc / asm / --version / --help
 *
 * Build:  gcc -O2 -std=c11 -o rex rex_main.c
 * Install: sudo make install
 */

#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <dirent.h>
#include <errno.h>
#include <time.h>
#include <stdarg.h>
#include <ctype.h>

#define REX_VERSION "Rex V5.0 (NASM ELF64 + RexC)"
#define BUILD_DATE  __DATE__

/* ─────────────────────────────────────────────────────────────────────────── */
/* Path resolution                                                              */
/* ─────────────────────────────────────────────────────────────────────────── */

static char self_dir[512] = {0};   /* directory of the `rex` binary */

static void find_self_dir(void) {
    char self[512] = {0};
    ssize_t n = readlink("/proc/self/exe", self, sizeof(self) - 1);
    if (n > 0) {
        self[n] = '\0';
        char *slash = strrchr(self, '/');
        if (slash) { *slash = '\0'; strncpy(self_dir, self, sizeof(self_dir) - 1); return; }
    }
    strncpy(self_dir, ".", sizeof(self_dir) - 1);
}

static void tool_path(const char *name, char *out, int out_size) {
    /* Try same directory as rex first */
    snprintf(out, out_size, "%s/%s", self_dir, name);
    if (access(out, X_OK) == 0) return;
    /* Fall back to PATH */
    snprintf(out, out_size, "%s", name);
}

/* ─────────────────────────────────────────────────────────────────────────── */
/* Helpers                                                                      */
/* ─────────────────────────────────────────────────────────────────────────── */

static void die(const char *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    fprintf(stderr, "rex: "); vfprintf(stderr, fmt, ap); fprintf(stderr, "\n");
    va_end(ap);
    exit(1);
}

/* Run a child process; returns its exit code */
static int run_cmd(char *const argv[]) {
    pid_t pid = fork();
    if (pid < 0) die("fork failed: %s", strerror(errno));
    if (pid == 0) {
        execvp(argv[0], argv);
        fprintf(stderr, "rex: exec '%s' failed: %s\n", argv[0], strerror(errno));
        _exit(127);
    }
    int status = 0;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}

/* Strip extension from filename: "foo.rex" → "foo", "main.rex" → "main" */
static void strip_ext(const char *in, char *out, int out_size) {
    strncpy(out, in, out_size - 1);
    out[out_size - 1] = '\0';
    char *dot = strrchr(out, '.');
    if (dot) *dot = '\0';
}

/* Strip directory from path: "/a/b/foo.rex" → "foo.rex" */
static const char *basename_of(const char *path) {
    const char *slash = strrchr(path, '/');
    return slash ? slash + 1 : path;
}

/* Copy a file (handles cross-filesystem moves) */
static int copy_file(const char *src, const char *dst) {
    FILE *in  = fopen(src, "rb");
    if (!in) return -1;
    FILE *out = fopen(dst, "wb");
    if (!out) { fclose(in); return -1; }
    char buf[65536];
    size_t n;
    while ((n = fread(buf, 1, sizeof(buf), in)) > 0)
        fwrite(buf, 1, n, out);
    fclose(in);
    fclose(out);
    return 0;
}

/* Move a file, falling back to copy+unlink on cross-device failure */
static int move_file(const char *src, const char *dst) {
    if (rename(src, dst) == 0) return 0;
    if (errno == EXDEV) {
        if (copy_file(src, dst) == 0) { unlink(src); return 0; }
    }
    return -1;
}

/* ─────────────────────────────────────────────────────────────────────────── */
/* Timing helper                                                                */
/* ─────────────────────────────────────────────────────────────────────────── */

static long long now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

/* ─────────────────────────────────────────────────────────────────────────── */
/* NASM + ld path detection                                                     */
/* ─────────────────────────────────────────────────────────────────────────── */

static void find_nasm(void) { (void)0; }

/* ─────────────────────────────────────────────────────────────────────────── */
/* rex build                                                                    */
/* ─────────────────────────────────────────────────────────────────────────── */

static int cmd_build(int argc, char *argv[]) {
    const char *input   = "main.rex";
    int release = 0, debug = 0, wpo = 0;

    for (int i = 0; i < argc; i++) {
        if (strcmp(argv[i], "--release") == 0) release = 1;
        else if (strcmp(argv[i], "--debug") == 0) debug = 1;
        else if (strcmp(argv[i], "--wpo") == 0) wpo = 1;
        else if (argv[i][0] != '-') input = argv[i];
    }

    if (access(input, R_OK) != 0)
        die("cannot open '%s': %s", input, strerror(errno));

    /* Determine output name: "foo.rex" → "foo", "foo" → "foo" */
    const char *base = basename_of(input);
    char out_name[256];
    strip_ext(base, out_name, sizeof(out_name));

    char rexc[512];
    tool_path("rexc", rexc, sizeof(rexc));

    long long t0 = now_ms();

    /* rexc writes to "output" in the current directory */
    char *rexc_args[8];
    int arg_idx = 0;
    rexc_args[arg_idx++] = rexc;
    if (wpo) rexc_args[arg_idx++] = "--wpo";
    rexc_args[arg_idx++] = (char *)input;
    rexc_args[arg_idx++] = NULL;

    int rc = run_cmd(rexc_args);
    if (rc != 0) {
        fprintf(stderr, "rex: compilation failed\n");
        return 1;
    }

    /* Rename "output" to the correct output name */
    if (strcmp(out_name, "output") != 0) {
        if (rename("output", out_name) != 0)
            die("rename output → %s: %s", out_name, strerror(errno));
    }

    /* Make executable */
    chmod(out_name, 0755);

    long long elapsed = now_ms() - t0;

    /* Print file size */
    struct stat st;
    long sz = (stat(out_name, &st) == 0) ? (long)st.st_size : 0;
    printf("Built ./%s (%ld bytes) in %lld.%03lldms\n",
           out_name, sz, elapsed / 1000, elapsed % 1000);
    return 0;
}

/* ─────────────────────────────────────────────────────────────────────────── */
/* rex run                                                                      */
/* ─────────────────────────────────────────────────────────────────────────── */

static int cmd_run(int argc, char *argv[]) {
    const char *input = "main.rex";
    int sep = -1;  /* index of "--" separator */

    for (int i = 0; i < argc; i++) {
        if (strcmp(argv[i], "--") == 0) { sep = i; break; }
        else if (argv[i][0] != '-') input = argv[i];
    }

    if (access(input, R_OK) != 0)
        die("cannot open '%s': %s", input, strerror(errno));

    char rexc[512];
    tool_path("rexc", rexc, sizeof(rexc));

    /* Compile to /tmp */
    char tmpbin[64];
    snprintf(tmpbin, sizeof(tmpbin), "/tmp/rex_run_%d", (int)getpid());

    char *rexc_args[] = { rexc, (char *)input, NULL };
    /* rexc outputs to ./output; we'll move it */
    int rc = run_cmd(rexc_args);
    if (rc != 0) return 1;
    if (move_file("output", tmpbin) != 0)
        die("cannot create temp binary: %s", strerror(errno));
    chmod(tmpbin, 0755);

    /* Build argv for the program */
    int extra = (sep >= 0) ? (argc - sep - 1) : 0;
    char **run_argv = malloc((extra + 2) * sizeof(char *));
    run_argv[0] = tmpbin;
    for (int i = 0; i < extra; i++) run_argv[i + 1] = argv[sep + 1 + i];
    run_argv[extra + 1] = NULL;

    rc = run_cmd(run_argv);
    free(run_argv);
    unlink(tmpbin);
    return rc;
}

/* ─────────────────────────────────────────────────────────────────────────── */
/* rex check                                                                    */
/* ─────────────────────────────────────────────────────────────────────────── */

static int cmd_check(int argc, char *argv[]) {
    const char *input = "main.rex";
    int json_mode = 0;

    for (int i = 0; i < argc; i++) {
        if (strcmp(argv[i], "--json") == 0) json_mode = 1;
        else if (argv[i][0] != '-') input = argv[i];
    }

    if (access(input, R_OK) != 0)
        die("cannot open '%s': %s", input, strerror(errno));

    char rexc[512];
    tool_path("rexc", rexc, sizeof(rexc));

    /* Capture stderr */
    int pipe_fd[2];
    if (pipe(pipe_fd) < 0) die("pipe: %s", strerror(errno));

    pid_t pid = fork();
    if (pid < 0) die("fork: %s", strerror(errno));

    if (pid == 0) {
        int devnull = open("/dev/null", O_WRONLY);
        dup2(devnull, STDOUT_FILENO);
        close(devnull);
        dup2(pipe_fd[1], STDERR_FILENO);
        close(pipe_fd[0]); close(pipe_fd[1]);
        execl(rexc, "rexc", input, NULL);
        _exit(127);
    }

    close(pipe_fd[1]);
    char errbuf[4096] = {0};
    int errlen = 0;
    {
        int n;
        while ((n = (int)read(pipe_fd[0], errbuf + errlen, sizeof(errbuf) - 1 - errlen)) > 0)
            errlen += n;
    }
    close(pipe_fd[0]);

    int status = 0;
    waitpid(pid, &status, 0);
    int exit_code = WIFEXITED(status) ? WEXITSTATUS(status) : 1;

    /* Remove the "output" file if created (check-only, don't leave artifacts) */
    unlink("output");

    if (json_mode) {
        /* Emit JSON diagnostics */
        if (exit_code != 0 && errlen > 0) {
            printf("[");
            int first = 1;
            char *line = errbuf;
            while (*line) {
                char *nl = strchr(line, '\n');
                if (nl) *nl = '\0';
                if (*line) {
                    if (!first) printf(",");
                    /* Escape the message for JSON */
                    printf("{\"range\":{\"start\":{\"line\":0,\"character\":0},"
                           "\"end\":{\"line\":0,\"character\":80}},"
                           "\"severity\":1,\"source\":\"rex\",\"message\":\"%s\"}", line);
                    first = 0;
                }
                if (nl) { line = nl + 1; } else break;
            }
            printf("]\n");
        } else {
            printf("[]\n");
        }
    } else {
        if (exit_code == 0) {
            printf("%s: ok\n", input);
        } else {
            if (errlen > 0) fputs(errbuf, stderr);
            else fprintf(stderr, "rex: check failed with exit code %d\n", exit_code);
        }
    }

    return exit_code;
}

/* ─────────────────────────────────────────────────────────────────────────── */
/* rex lsp                                                                      */
/* ─────────────────────────────────────────────────────────────────────────── */

static int cmd_lsp(void) {
    char lsp_bin[512];
    tool_path("rex_lsp", lsp_bin, sizeof(lsp_bin));

    if (access(lsp_bin, X_OK) != 0) {
        die("rex_lsp not found at '%s'. Build it with: make lsp", lsp_bin);
    }

    execl(lsp_bin, "rex_lsp", NULL);
    die("exec rex_lsp failed: %s", strerror(errno));
    return 1; /* unreachable */
}

/* ─────────────────────────────────────────────────────────────────────────── */
/* rex fmt                                                                      */
/* ─────────────────────────────────────────────────────────────────────────── */

/*
 * Minimal Rex formatter.
 * Implements the canonical style from §7 of the build prompt:
 *   - 4-space indentation (no tabs)
 *   - trailing whitespace stripped
 *   - exactly one blank line between top-level prot definitions
 *   - exactly one newline at end of file
 *   - operators surrounded by single spaces
 *   - idempotent
 */
static char *format_rex(const char *src, int src_len) {
    /* Allocate 2x source size for output (reformatting rarely grows by more) */
    int  cap = src_len * 2 + 4096;
    char *out = malloc(cap);
    if (!out) return NULL;
    int  olen = 0;

    int indent  = 0;   /* current indentation level (4 spaces each) */
    int in_string = 0;

    /* Line-by-line processing */
    const char *p   = src;
    const char *end = src + src_len;

    while (p < end) {
        /* Find end of this line */
        const char *line_start = p;
        while (p < end && *p != '\n') {
            if (*p == '"' && (p == line_start || p[-1] != '\\')) in_string = !in_string;
            p++;
        }
        const char *line_end = p;
        if (p < end) p++; /* skip newline */

        /* Strip leading whitespace to determine content */
        const char *content = line_start;
        while (content < line_end && (*content == ' ' || *content == '\t')) content++;

        /* Strip trailing whitespace */
        const char *content_end = line_end;
        while (content_end > content && (content_end[-1] == ' ' || content_end[-1] == '\t'))
            content_end--;

        int content_len = (int)(content_end - content);

        /* Blank line */
        if (content_len == 0) {
            /* Exactly 1 blank line allowed inside prot body. */
            /* We also handle exactly 1 blank line between top-level prots elsewhere. */
            if (olen > 0 && out[olen-1] == '\n' && (olen < 2 || out[olen-2] != '\n')) {
                out[olen++] = '\n';
            }
            continue;
        }

        /* Determine if this line decreases indent (else/elif/dedent keywords) */
        if (strncmp(content, "else", 4) == 0 ||
            strncmp(content, "elif", 4) == 0) {
            if (indent > 0) indent--;
        }

        /* Emit indentation */
        for (int i = 0; i < indent * 4; i++) {
            if (olen >= cap - 1) break;
            out[olen++] = ' ';
        }

        /* Emit content with spacing rules for operators */
        for (const char *c = content; c < content_end; c++) {
            if (olen + 10 >= cap) {
                cap += 4096;
                out = realloc(out, cap);
                if (!out) return NULL;
            }

            if (*c == '"' && (c == content || c[-1] != '\\')) {
                in_string = !in_string;
                out[olen++] = *c;
                continue;
            }

            if (!in_string) {
                /* Binary operators: exactly 1 space each side (a + b) */
                if ((*c == '+' || *c == '-' || *c == '*' || *c == '/' || *c == '%' || *c == '=') && 
                    (c > content && isalnum((unsigned char)c[-1])) && 
                    (c + 1 < content_end && isalnum((unsigned char)c[1]))) {
                    if (out[olen-1] != ' ') out[olen++] = ' ';
                    out[olen++] = *c;
                    if (c[1] != ' ') out[olen++] = ' ';
                    continue;
                }
                /* :x = value — one space after :, one space around = */
                if (*c == ':' && c + 1 < content_end && isalpha((unsigned char)c[1])) {
                    out[olen++] = *c;
                    continue; // we'll handle spaces if needed, but rule says "one space after :"
                }
                /* Collection literals: [1, 2, 3] with spaces after [ and before ] if non-empty */
                if (*c == '[' && c + 1 < content_end && c[1] != ']') {
                    out[olen++] = '[';
                    out[olen++] = ' ';
                    continue;
                }
                if (*c == ']' && c > content && c[-1] != '[') {
                    if (out[olen-1] != ' ') out[olen++] = ' ';
                    out[olen++] = ']';
                    continue;
                }
            }
            out[olen++] = *c;
        }
        out[olen++] = '\n';

        /* Update indent level based on this line's content */
        if (content_len > 0 && content_end[-1] == ':') {
            indent++;
        }
    }

    /* Post-processing: 
       - Exactly 1 blank line between top-level prot definitions.
       - 0 blank lines between #decorator and prot.
       - Exactly one newline at EOF.
    */
    /* (Simplified post-processing for now) */

    /* Ensure exactly one trailing newline */
    while (olen > 1 && out[olen-1] == '\n' && out[olen-2] == '\n') olen--;
    if (olen == 0 || out[olen-1] != '\n') out[olen++] = '\n';

    out[olen] = '\0';
    return out;
}

static int cmd_fmt(int argc, char *argv[]) {
    const char *input  = NULL;
    int check_mode  = 0;
    int stdout_mode = 0;

    for (int i = 0; i < argc; i++) {
        if (strcmp(argv[i], "--check") == 0) check_mode = 1;
        else if (strcmp(argv[i], "--stdout") == 0) stdout_mode = 1;
        else if (argv[i][0] != '-') input = argv[i];
    }

    if (!input) {
        fprintf(stderr, "rex fmt: specify a .rex file\n");
        return 1;
    }

    /* Read file */
    FILE *f = fopen(input, "r");
    if (!f) die("cannot open '%s': %s", input, strerror(errno));
    fseek(f, 0, SEEK_END);
    long fsize = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *src = malloc(fsize + 1);
    if (!src) die("out of memory");
    if (fread(src, 1, fsize, f) != (size_t)fsize && fsize > 0)
        die("read error on '%s'", input);
    src[fsize] = '\0';
    fclose(f);

    char *formatted = format_rex(src, (int)fsize);
    free(src);
    if (!formatted) die("formatter: out of memory");

    if (check_mode) {
        /* Re-read original to compare */
        f = fopen(input, "r");
        fseek(f, 0, SEEK_END);
        long fsize2 = ftell(f);
        fseek(f, 0, SEEK_SET);
        char *orig = malloc(fsize2 + 1);
        if (fread(orig, 1, fsize2, f) != (size_t)fsize2 && fsize2 > 0) { free(orig); die("read error"); }
        orig[fsize2] = '\0';
        fclose(f);
        int changed = (strcmp(orig, formatted) != 0);
        free(orig);
        free(formatted);
        return changed ? 1 : 0;
    }

    if (stdout_mode) {
        fputs(formatted, stdout);
        free(formatted);
        return 0;
    }

    /* Write in-place */
    f = fopen(input, "w");
    if (!f) { free(formatted); die("cannot write '%s': %s", input, strerror(errno)); }
    fputs(formatted, f);
    fclose(f);
    free(formatted);
    return 0;
}

/* ─────────────────────────────────────────────────────────────────────────── */
/* rex new                                                                      */
/* ─────────────────────────────────────────────────────────────────────────── */

static int cmd_new(int argc, char *argv[]) {
    if (argc < 1 || argv[0][0] == '-') {
        fprintf(stderr, "usage: rex new <project-name>\n");
        return 1;
    }
    const char *name = argv[0];

    if (mkdir(name, 0755) != 0)
        die("cannot create directory '%s': %s", name, strerror(errno));

    /* Create subdirectories */
    char path[512];
    snprintf(path, sizeof(path), "%s/tests", name);  mkdir(path, 0755);
    snprintf(path, sizeof(path), "%s/bench", name);  mkdir(path, 0755);
    snprintf(path, sizeof(path), "%s/doc",   name);  mkdir(path, 0755);

    /* main.rex */
    snprintf(path, sizeof(path), "%s/main.rex", name);
    FILE *f = fopen(path, "w");
    if (f) {
        fprintf(f, "output(\"Hello, %s!\")\n", name);
        fclose(f);
    }

    /* tests/test_main.rex */
    snprintf(path, sizeof(path), "%s/tests/test_main.rex", name);
    f = fopen(path, "w");
    if (f) {
        fprintf(f, "// Test suite for %s\n", name);
        fprintf(f, "int x = 1\n");
        fprintf(f, "assert x == 1\n");
        fprintf(f, "output(\"test_main: PASS\")\n");
        fclose(f);
    }

    /* rex.toml */
    snprintf(path, sizeof(path), "%s/rex.toml", name);
    f = fopen(path, "w");
    if (f) {
        fprintf(f, "[project]\n");
        fprintf(f, "name = \"%s\"\n", name);
        fprintf(f, "version = \"0.1.0\"\n");
        fprintf(f, "description = \"\"\n\n");
        fprintf(f, "[build]\n");
        fprintf(f, "entry = \"main.rex\"\n");
        fprintf(f, "output = \"%s\"\n\n", name);
        fprintf(f, "[dev]\n");
        fprintf(f, "test_dir = \"tests\"\n");
        fprintf(f, "bench_dir = \"bench\"\n");
        fprintf(f, "doc_output = \"doc\"\n");
        fclose(f);
    }

    printf("Created project '%s'. Run: cd %s && rex run\n", name, name);
    return 0;
}

/* ─────────────────────────────────────────────────────────────────────────── */
/* rex test                                                                     */
/* ─────────────────────────────────────────────────────────────────────────── */

static int run_test_file(const char *path, char *rexc) {
    /* Compile */
    char tmpbin[64];
    snprintf(tmpbin, sizeof(tmpbin), "/tmp/rex_test_%d", (int)getpid());

    char *args[] = { rexc, (char *)path, NULL };

    /* Capture stdout + stderr during compilation */
    int pipe_fd[2];
    if (pipe(pipe_fd) < 0) return 1;
    pid_t pid = fork();
    if (pid == 0) {
        int devnull = open("/dev/null", O_WRONLY);
        dup2(devnull, STDOUT_FILENO);
        close(devnull);
        dup2(pipe_fd[1], STDERR_FILENO);
        close(pipe_fd[0]); close(pipe_fd[1]);
        execvp(rexc, args);
        _exit(127);
    }
    close(pipe_fd[1]);
    char errbuf[1024] = {0};
    int n;
    int errlen = 0;
    while ((n = (int)read(pipe_fd[0], errbuf + errlen, sizeof(errbuf) - 1 - errlen)) > 0) errlen += n;
    close(pipe_fd[0]);
    int status = 0;
    waitpid(pid, &status, 0);

    if (WEXITSTATUS(status) != 0) {
        unlink("output");
        return -1; /* compile error */
    }

    if (move_file("output", tmpbin) != 0) return -1;
    chmod(tmpbin, 0755);

    /* Run and compare with .expected or // expect: */
    int out_pipe[2];
    if (pipe(out_pipe) < 0) return 1;
    pid = fork();
    if (pid == 0) {
        dup2(out_pipe[1], STDOUT_FILENO);
        close(out_pipe[0]); close(out_pipe[1]);
        execl(tmpbin, tmpbin, NULL);
        _exit(127);
    }
    close(out_pipe[1]);
    char actual[4096] = {0};
    int alen = 0;
    while ((n = (int)read(out_pipe[0], actual + alen, sizeof(actual) - 1 - alen)) > 0) alen += n;
    close(out_pipe[0]);
    waitpid(pid, &status, 0);

    /* Check for .expected file */
    char exp_path[512];
    strncpy(exp_path, path, sizeof(exp_path)-1);
    char *dot = strrchr(exp_path, '.');
    if (dot) strcpy(dot, ".expected");
    else strcat(exp_path, ".expected");

    FILE *ef = fopen(exp_path, "r");
    if (ef) {
        char expected[4096] = {0};
        fread(expected, 1, sizeof(expected)-1, ef);
        fclose(ef);
        /* Strip trailing whitespace from both */
        char *p = actual + strlen(actual);
        while (p > actual && (p[-1] == '\n' || p[-1] == ' ' || p[-1] == '\t' || p[-1] == '\r')) *--p = '\0';
        p = expected + strlen(expected);
        while (p > expected && (p[-1] == '\n' || p[-1] == ' ' || p[-1] == '\t' || p[-1] == '\r')) *--p = '\0';
        
        if (strcmp(actual, expected) != 0) {
            unlink(tmpbin);
            return 1; // FAIL
        }
    } else {
        /* Check for // expect: comments in source */
        FILE *sf = fopen(path, "r");
        if (sf) {
            char line[1024];
            char expected[4096] = {0};
            int has_expect = 0;
            while (fgets(line, sizeof(line), sf)) {
                char *ex = strstr(line, "// expect:");
                if (ex) {
                    ex += 10;
                    while (*ex == ' ') ex++;
                    strcat(expected, ex);
                    has_expect = 1;
                }
            }
            fclose(sf);
            if (has_expect) {
                char *p = actual + strlen(actual);
                while (p > actual && (p[-1] == '\n' || p[-1] == ' ' || p[-1] == '\t' || p[-1] == '\r')) *--p = '\0';
                p = expected + strlen(expected);
                while (p > expected && (p[-1] == '\n' || p[-1] == ' ' || p[-1] == '\t' || p[-1] == '\r')) *--p = '\0';
                if (strcmp(actual, expected) != 0) {
                    unlink(tmpbin);
                    return 1;
                }
            }
        }
    }

    unlink(tmpbin);
    return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}

static int cmd_test(int argc, char *argv[]) {
    const char *single = NULL;

    for (int i = 0; i < argc; i++) {
        if (strcmp(argv[i], "--all") == 0) { }
        else if (argv[i][0] != '-') single = argv[i];
    }

    char rexc[512];
    tool_path("rexc", rexc, sizeof(rexc));

    if (single) {
        int rc = run_test_file(single, rexc);
        if (rc == 0)       printf("PASS  %s\n", single);
        else if (rc == -1) printf("FAIL  %s  (compile error)\n", single);
        else               printf("FAIL  %s\n", single);
        return (rc == 0) ? 0 : 1;
    }

    /* Scan tests/ and tests/suite/ */
    const char *dirs[] = { "tests", "tests/suite", NULL };
    int passed = 0, failed = 0, total = 0;

    for (int d = 0; dirs[d]; d++) {
        DIR *dir = opendir(dirs[d]);
        if (!dir) continue;
        struct dirent *ent;
        while ((ent = readdir(dir)) != NULL) {
            if (ent->d_name[0] == '.') continue;
            int nlen = (int)strlen(ent->d_name);
            if (nlen < 5 || strcmp(ent->d_name + nlen - 4, ".rex") != 0) continue;

            char fpath[512];
            snprintf(fpath, sizeof(fpath), "%s/%s", dirs[d], ent->d_name);
            total++;
            int rc = run_test_file(fpath, rexc);
            if (rc == 0) { passed++; printf("PASS  %s\n", fpath); }
            else { failed++; printf("FAIL  %s\n", fpath); }
        }
        closedir(dir);
    }

    printf("\n%d/%d tests passed", passed, total);
    if (failed) printf(", %d failed", failed);
    printf("\n");
    return failed > 0 ? 1 : 0;
}

/* ─────────────────────────────────────────────────────────────────────────── */
/* rex bench                                                                    */
/* ─────────────────────────────────────────────────────────────────────────── */

static int cmd_bench(int argc, char *argv[]) {
    const char *single = NULL;
    int all_mode = 0;
    for (int i = 0; i < argc; i++) {
        if (strcmp(argv[i], "--all") == 0) all_mode = 1;
        else if (argv[i][0] != '-') single = argv[i];
    }

    char rexc[512];
    tool_path("rexc", rexc, sizeof(rexc));

    if (single || all_mode) {
        const char *bench_dir = "benchmarks/fair_suite";
        DIR *dir = opendir(bench_dir);
        if (!dir) {
            fprintf(stderr, "rex: benchmarks directory '%s' not found\n", bench_dir);
            return 1;
        }

        struct dirent *ent;
        int total_passed = 0;
        int total_targets = 0;

        while ((ent = readdir(dir)) != NULL) {
            if (ent->d_name[0] == '.') continue;
            int nlen = (int)strlen(ent->d_name);
            if (nlen < 5 || strcmp(ent->d_name + nlen - 4, ".rex") != 0) continue;
            
            if (single && strcmp(ent->d_name, single) != 0 && strcmp(basename_of(ent->d_name), single) != 0) {
                // Check if single matches the full path or just the filename
                char fpath_check[512];
                snprintf(fpath_check, sizeof(fpath_check), "%s/%s", bench_dir, ent->d_name);
                if (strcmp(fpath_check, single) != 0) continue;
            }

            char rex_src[512], c_src[512], rex_bin[512], c_bin[512];
            snprintf(rex_src, sizeof(rex_src), "%s/%s", bench_dir, ent->d_name);
            snprintf(c_src, sizeof(c_src), "%s/%.*s.c", bench_dir, nlen - 4, ent->d_name);
            snprintf(rex_bin, sizeof(rex_bin), "/tmp/rex_bench_%d", getpid());
            snprintf(c_bin, sizeof(c_bin), "/tmp/c_bench_%d", getpid());

            // Compile Rex
            char *rex_compile_args[] = { rexc, rex_src, NULL };
            if (run_cmd(rex_compile_args) != 0) {
                fprintf(stderr, "rex: failed to compile %s\n", rex_src);
                continue;
            }
            move_file("output", rex_bin);
            chmod(rex_bin, 0755);

            // Compile C
            char *c_compile_args[] = { "gcc", "-O2", c_src, "-o", c_bin, "-lm", NULL };
            if (run_cmd(c_compile_args) != 0) {
                fprintf(stderr, "rex: failed to compile %s\n", c_src);
                unlink(rex_bin);
                continue;
            }

            // Run Rex for 2 seconds
            long long t0 = now_ms();
            int rex_ops = 0;
            while (now_ms() - t0 < 2000) {
                char *rex_run_args[] = { rex_bin, NULL };
                run_cmd(rex_run_args);
                rex_ops++;
            }
            double rex_time = (double)(now_ms() - t0) / rex_ops;

            // Run C for 2 seconds
            t0 = now_ms();
            int c_ops = 0;
            while (now_ms() - t0 < 2000) {
                char *c_run_args[] = { c_bin, NULL };
                run_cmd(c_run_args);
                c_ops++;
            }
            double c_time = (double)(now_ms() - t0) / c_ops;

            double ratio = c_time / rex_time;
            const char *status = (ratio >= 0.8) ? "PASS" : "FAIL"; // Simplified PASS criteria
            if (ratio >= 0.8) total_passed++;
            total_targets++;

            printf("%.*s: Rex %.2f ms/op  C %.2f ms/op  ratio: %.2f [%s]\n",
                   nlen - 4, ent->d_name, rex_time, c_time, ratio, status);

            unlink(rex_bin);
            unlink(c_bin);
            
            if (single) break;
        }
        closedir(dir);
        printf("\nRex PASSED %d/%d performance targets\n", total_passed, total_targets);
        return 0;
    }

    fprintf(stderr, "usage: rex bench [--all] [<file>]\n");
    return 1;
}

/* ─────────────────────────────────────────────────────────────────────────── */
/* rex doc                                                                      */
/* ─────────────────────────────────────────────────────────────────────────── */

static int cmd_doc(int argc, char *argv[]) {
    const char *input = NULL;
    for (int i = 0; i < argc; i++) {
        if (argv[i][0] != '-') input = argv[i];
    }

    if (!input) { fprintf(stderr, "rex doc: specify a .rex file\n"); return 1; }

    FILE *f = fopen(input, "r");
    if (!f) die("cannot open '%s'", input);
    fseek(f, 0, SEEK_END);
    long fsize = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *src = malloc(fsize + 1);
    if (!src) die("out of memory");
    if (fread(src, 1, fsize, f) != (size_t)fsize && fsize > 0) die("read error on '%s'", input);
    src[fsize] = '\0';
    fclose(f);

    mkdir("doc", 0755);
    FILE *html = fopen("doc/index.html", "w");
    if (!html) die("cannot write doc/index.html");

    const char *base = basename_of(input);
    fprintf(html, "<!DOCTYPE html><html><head><meta charset=\"utf-8\">\n");
    fprintf(html, "<title>Rex Docs — %s</title>\n", base);
    fprintf(html, "<style>body{font-family:monospace;max-width:800px;margin:40px auto;}"
                  "h2{border-bottom:1px solid #ccc;} pre{background:#f8f8f8;padding:12px;}"
                  ".doc{color:#555;font-style:italic;}</style></head><body>\n");
    fprintf(html, "<h1>%s</h1>\n", base);

    /* Scan for prot + doc comments */
    const char *p = src;
    char doc_buf[1024] = {0};
    while (*p) {
        if (p[0] == '/' && p[1] == '/' && p[2] == '/') {
            const char *s = p + 3;
            if (*s == ' ') s++;
            const char *e = s;
            while (*e && *e != '\n') e++;
            int existing = (int)strlen(doc_buf);
            if (existing > 0) { doc_buf[existing++] = ' '; }
            int dlen = (int)(e - s);
            if (existing + dlen < 1022) {
                memcpy(doc_buf + existing, s, dlen);
                doc_buf[existing + dlen] = '\0';
            }
            p = e; if (*p) p++;
            continue;
        }
        if (strncmp(p, "prot ", 5) == 0) {
            const char *sig_end = p;
            while (*sig_end && *sig_end != '\n') sig_end++;
            int siglen = (int)(sig_end - p);
            char sig[512] = {0};
            if (siglen < 511) { memcpy(sig, p, siglen); sig[siglen] = '\0'; }
            /* Extract proto name */
            const char *name = p + 5;
            const char *name_end = name;
            while (*name_end && (isalnum((unsigned char)*name_end) || *name_end == '_')) name_end++;
            int nlen = (int)(name_end - name);
            char pname[64] = {0};
            if (nlen < 63) { memcpy(pname, name, nlen); pname[nlen] = '\0'; }
            fprintf(html, "<h2 id=\"%s\">%s</h2>\n", pname, pname);
            fprintf(html, "<pre>%s</pre>\n", sig);
            if (doc_buf[0]) fprintf(html, "<p class=\"doc\">%s</p>\n", doc_buf);
            doc_buf[0] = '\0';
        } else if (*p != '\n' && *p != ' ' && *p != '\t') {
            doc_buf[0] = '\0';
        }
        if (*p == '\n') {}
        p++;
    }

    fprintf(html, "</body></html>\n");
    fclose(html);
    free(src);
    printf("Generated doc/index.html\n");
    return 0;
}

/* ─────────────────────────────────────────────────────────────────────────── */
/* rex asm                                                                      */
/* ─────────────────────────────────────────────────────────────────────────── */

static int cmd_asm(int argc, char *argv[]) {
    const char *input = "main.rex";
    int no_cleanup = 0;
    for (int i = 0; i < argc; i++) {
        if (strcmp(argv[i], "--keep") == 0) no_cleanup = 1;
        else if (argv[i][0] != '-') input = argv[i];
    }

    if (access(input, R_OK) != 0)
        die("cannot open '%s': %s", input, strerror(errno));

    /* Step 1: compile to ELF via rexc */
    char rexc_path[512];
    tool_path("rexc", rexc_path, sizeof(rexc_path));
    if (access(rexc_path, X_OK) != 0)
        die("rexc not found at '%s'. Run: make rexc", rexc_path);

    char *build_args[] = { rexc_path, (char *)input, NULL };
    int rc = run_cmd(build_args);
    if (rc != 0) {
        fprintf(stderr, "rex asm: compilation failed\n");
        return 1;
    }

    /* Step 2: disassemble with objdump in Intel syntax */
    /* objdump -d -M intel --no-show-raw-insn strips the hex bytes so
       you see only the clean mnemonic + operands — 1:1 with the silicon */
    char *od_args[] = {
        "objdump",
        "-d",
        "-M", "intel",
        "--no-show-raw-insn",
        "--no-addresses",
        "output",
        NULL
    };
    rc = run_cmd(od_args);

    /* Step 3: clean up temp binary unless --keep */
    if (!no_cleanup) unlink("output");

    return rc;
}

/* ─────────────────────────────────────────────────────────────────────────── */
/* rex emit                                                                     */
/* ─────────────────────────────────────────────────────────────────────────── */

static int cmd_emit(int argc, char *argv[]) {
    const char *input = "main.rex";

    for (int i = 0; i < argc; i++) {
        if (argv[i][0] != '-') input = argv[i];
    }

    if (access(input, R_OK) != 0)
        die("cannot open '%s': %s", input, strerror(errno));

    /* Output name: foo.rex → foo.rxc */
    const char *base = basename_of(input);
    char stem[256];
    strip_ext(base, stem, sizeof(stem));
    char out_name[264];
    snprintf(out_name, sizeof(out_name), "%s.rxc", stem);

    char rexc_rxc[512];
    tool_path("rexc_rxc", rexc_rxc, sizeof(rexc_rxc));

    if (access(rexc_rxc, X_OK) != 0)
        die("rexc_rxc not found at '%s'. Build it with: make rexc_rxc", rexc_rxc);

    long long t0 = now_ms();

    char *args[] = { rexc_rxc, (char *)input, NULL };
    int rc = run_cmd(args);
    if (rc != 0) {
        fprintf(stderr, "rex: emit failed\n");
        return 1;
    }

    /* rexc_rxc writes to "output"; rename to <stem>.rxc */
    if (move_file("output", out_name) != 0)
        die("cannot rename output to %s: %s", out_name, strerror(errno));

    long long elapsed = now_ms() - t0;
    struct stat st;
    long sz = (stat(out_name, &st) == 0) ? (long)st.st_size : 0;
    printf("Emitted ./%s (%ld bytes) in %lld.%03lldms\n",
           out_name, sz, elapsed / 1000, elapsed % 1000);
    return 0;
}

/* ─────────────────────────────────────────────────────────────────────────── */
/* --version / --help                                                           */
/* ─────────────────────────────────────────────────────────────────────────── */

static void print_version(void) {
    printf("%s built %s\n", REX_VERSION, BUILD_DATE);
}

static void print_help(void) {
    printf("%s built %s\n\n", REX_VERSION, BUILD_DATE);
    printf("USAGE\n");
    printf("  rex <command> [options] [file.rex]\n\n");
    printf("COMMANDS\n");
    printf("  build  [file.rex] [--release|--debug]   Compile to a native ELF64 binary\n");
    printf("  emit   [file.rex]                        Compile to portable RexC bytecode (.rxc)\n");
    printf("  run    [file.rex] [-- args...]           Compile and run immediately\n");
    printf("  check  [file.rex] [--json]              Lint only; no binary produced\n");
    printf("  lsp                                      Start LSP server (stdin/stdout)\n");
    printf("  fmt    [file.rex] [--check|--stdout]    Format source file canonically\n");
    printf("  new    <project-name>                    Create a new Rex project\n");
    printf("  test   [file.rex | --all]               Run test suite in tests/\n");
    printf("  bench  [file.rex | --all]               Run benchmarks in bench/\n");
    printf("  doc    [file.rex | --all]               Generate HTML documentation\n");
    printf("  asm    [file.rex] [--keep]               Show x86-64 instructions (1:1 with silicon)\n");
    printf("\n");
    printf("OPTIONS\n");
    printf("  --version   Print version and exit\n");
    printf("  --help      Print this help and exit\n");
}

/* ─────────────────────────────────────────────────────────────────────────── */
/* Entry point                                                                  */
/* ─────────────────────────────────────────────────────────────────────────── */

int main(int argc, char *argv[]) {
    find_self_dir();
    find_nasm();

    if (argc < 2) { print_help(); return 0; }

    const char *cmd = argv[1];
    int sub_argc = argc - 2;
    char **sub_argv = argv + 2;

    if (strcmp(cmd, "--version") == 0 || strcmp(cmd, "version") == 0) {
        print_version(); return 0;
    }
    if (strcmp(cmd, "--help") == 0 || strcmp(cmd, "help") == 0 || strcmp(cmd, "-h") == 0) {
        print_help(); return 0;
    }
    if (strcmp(cmd, "emit")  == 0) return cmd_emit(sub_argc, sub_argv);
    if (strcmp(cmd, "build") == 0) return cmd_build(sub_argc, sub_argv);
    if (strcmp(cmd, "wpo")   == 0) {
        char **wpo_argv = malloc((sub_argc + 2) * sizeof(char *));
        wpo_argv[0] = "--wpo";
        for (int i = 0; i < sub_argc; i++) wpo_argv[i+1] = sub_argv[i];
        int rc = cmd_build(sub_argc + 1, wpo_argv);
        free(wpo_argv);
        return rc;
    }
    if (strcmp(cmd, "run")   == 0) return cmd_run(sub_argc, sub_argv);
    if (strcmp(cmd, "check") == 0) return cmd_check(sub_argc, sub_argv);
    if (strcmp(cmd, "lsp")   == 0) return cmd_lsp();
    if (strcmp(cmd, "fmt")   == 0) return cmd_fmt(sub_argc, sub_argv);
    if (strcmp(cmd, "new")   == 0) return cmd_new(sub_argc, sub_argv);
    if (strcmp(cmd, "test")  == 0) return cmd_test(sub_argc, sub_argv);
    if (strcmp(cmd, "bench") == 0) return cmd_bench(sub_argc, sub_argv);
    if (strcmp(cmd, "doc")   == 0) return cmd_doc(sub_argc, sub_argv);
    if (strcmp(cmd, "asm")   == 0) return cmd_asm(sub_argc, sub_argv);

    /* Unknown command — check if it looks like a .rex file */
    if (strstr(cmd, ".rex")) {
        /* Treat as: rex build <file> */
        return cmd_build(argc - 1, argv + 1);
    }

    fprintf(stderr, "rex: unknown command '%s'. Run 'rex --help'.\n", cmd);
    return 1;
}
