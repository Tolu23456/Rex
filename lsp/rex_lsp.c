/*
 * rex_lsp.c — Rex Language Server Protocol (LSP 3.17 / JSON-RPC 2.0 / stdio)
 * Phase 10 of Rex V5.0 build plan.
 * Implementation language: C (bootstrap; Rex rewrites this once io+json stdlib exist).
 *
 * Build:  gcc -O2 -std=c11 -o rex_lsp lsp/rex_lsp.c
 * Start:  rex lsp   (or directly: rex_lsp)
 *
 * All communication is over stdin/stdout using the LSP framing:
 *   Content-Length: N\r\n\r\n<N bytes of UTF-8 JSON>
 *
 * Diagnostics: fork rexc on each file change (debounce 200ms).
 * Log messages go to stderr (editors redirect this to a log file).
 */

#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <ctype.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <time.h>
#include <stdarg.h>

/* ─────────────────────────────────────────────────────────────────────────── */
/* Constants & limits                                                           */
/* ─────────────────────────────────────────────────────────────────────────── */

#define MAX_DOCS         64
#define MAX_URI          2048
#define MAX_DOC_SIZE     (1024 * 1024)   /* 1 MB per document */
#define MAX_DIAG         64
#define JSON_BUF_SIZE    (512 * 1024)
#define READ_BUF_SIZE    (256 * 1024)
#define MAX_PROTOS       512
#define PROTO_NAME_LEN   64
#define PROTO_SIG_LEN    256
#define PROTO_DOC_LEN    512

/* Rex keyword list */
static const char *REX_KEYWORDS[] = {
    "int","float","bool","str","char","byte","seq","dict","set","tup",
    "const","volatile","if","elif","else","for","while","each","repeat",
    "stop","skip","pass","prot","return","when","is","use","mm","gc",
    "arena","pool","true","false","maybe","and","or","not","in","as",
    "output","err","input","push","pop","len","cap","typeof","abs","swap",
    "assert","unreachable","import","from","blast","pipe",
    "#memo","#hot","#inline","#unsafe",
    NULL
};

/* Rex built-in type methods */
typedef struct { const char *type; const char *name; const char *sig; const char *doc; } MethodInfo;

static const MethodInfo REX_METHODS[] = {
    /* str methods */
    {"str","len",    "() -> int",          "Returns the number of characters in the string."},
    {"str","upper",  "() -> str",          "Returns a copy of the string in uppercase."},
    {"str","lower",  "() -> str",          "Returns a copy of the string in lowercase."},
    {"str","trim",   "() -> str",          "Strips leading and trailing whitespace."},
    {"str","split",  "(sep: str) -> seq[str]","Splits on sep; returns a sequence of substrings."},
    {"str","join",   "(parts: seq[str]) -> str","Joins seq elements with this string as separator."},
    {"str","contains","(sub: str) -> bool", "True if substring sub found anywhere in the string."},
    {"str","starts_with","(pre: str) -> bool","True if string begins with pre."},
    {"str","ends_with","(suf: str) -> bool","True if string ends with suf."},
    {"str","find",   "(sub: str) -> int",  "Index of first occurrence of sub, or -1."},
    {"str","replace","(old: str, new: str) -> str","Returns new string with all old replaced by new."},
    {"str","slice",  "(start: int, end: int) -> str","Returns substring [start..end)."},
    {"str","bytes",  "() -> seq[byte]",    "Returns raw UTF-8 byte sequence."},
    {"str","chars",  "() -> seq[char]",    "Returns sequence of Unicode code points."},
    {"str","repeat", "(n: int) -> str",    "Concatenates the string n times."},
    {"str","rev",    "() -> str",          "Returns the string reversed."},
    {"str","is_empty","() -> bool",        "True if len() == 0."},
    {"str","to_int", "() -> int",          "Parses as decimal integer; runtime error if invalid."},
    {"str","to_float","() -> float",       "Parses as floating-point; runtime error if invalid."},
    {"str","format", "(...) -> str",       "Interpolates {} placeholders with arguments."},
    /* seq methods */
    {"seq","len",    "() -> int",          "Number of elements currently in the sequence."},
    {"seq","cap",    "() -> int",          "Current allocated capacity."},
    {"seq","push",   "(val: T) -> void",   "Appends val to the end; grows if needed."},
    {"seq","pop",    "() -> T",            "Removes and returns the last element."},
    {"seq","get",    "(i: int) -> T",      "Returns element at index i (bounds-checked)."},
    {"seq","set",    "(i: int, val: T) -> void","Sets element at index i."},
    {"seq","is_empty","() -> bool",        "True if len() == 0."},
    {"seq","clear",  "() -> void",         "Removes all elements; keeps allocation."},
    {"seq","sort",   "() -> void",         "Sorts in ascending order (introsort)."},
    {"seq","rev",    "() -> void",         "Reverses in-place."},
    {"seq","contains","(val: T) -> bool",  "Linear scan membership test."},
    {"seq","find",   "(val: T) -> int",    "Index of first match, or -1."},
    {"seq","slice",  "(start: int, end: int) -> seq[T]","Returns sub-sequence [start..end)."},
    {"seq","each",   "(fn: T -> void) -> void","Calls fn for every element."},
    {"seq","map",    "(fn: T -> U) -> seq[U]","Returns new seq applying fn to each element."},
    {"seq","filter", "(fn: T -> bool) -> seq[T]","Returns new seq of elements where fn is true."},
    {"seq","reduce", "(fn: (T,T) -> T, init: T) -> T","Folds left with fn."},
    {"seq","sum",    "() -> T",            "Sum of all elements (numeric types only)."},
    {"seq","min",    "() -> T",            "Minimum element."},
    {"seq","max",    "() -> T",            "Maximum element."},
    /* dict methods */
    {"dict","len",   "() -> int",          "Number of key-value pairs."},
    {"dict","get",   "(key: K) -> V",      "Returns value for key; runtime error if absent."},
    {"dict","set",   "(key: K, val: V) -> void","Inserts or updates key."},
    {"dict","has",   "(key: K) -> bool",   "True if key is present."},
    {"dict","del",   "(key: K) -> void",   "Removes key; no-op if absent."},
    {"dict","keys",  "() -> seq[K]",       "Returns all keys as a sequence."},
    {"dict","values","() -> seq[V]",       "Returns all values as a sequence."},
    {"dict","clear", "() -> void",         "Removes all pairs; keeps allocation."},
    {"dict","is_empty","() -> bool",       "True if len() == 0."},
    /* set methods */
    {"set","len",    "() -> int",          "Number of elements."},
    {"set","add",    "(val: T) -> void",   "Insert val; no-op if already present."},
    {"set","remove", "(val: T) -> void",   "Remove val; no-op if absent."},
    {"set","has",    "(val: T) -> bool",   "True if val is in the set."},
    {"set","clear",  "() -> void",         "Remove all; keep allocation."},
    {"set","is_empty","() -> bool",        "True if len() == 0."},
    {"set","union",  "(other: set[T]) -> set[T]","New set with all elements of both."},
    {"set","intersect","(other: set[T]) -> set[T]","New set with elements in both."},
    {"set","diff",   "(other: set[T]) -> set[T]","New set: self minus other."},
    {"set","is_subset","(other: set[T]) -> bool","Every element of self is in other."},
    {"set","is_superset","(other: set[T]) -> bool","Every element of other is in self."},
    {"set","to_seq", "() -> seq[T]",       "Sequence of all members (order unspecified)."},
    {NULL, NULL, NULL, NULL}
};

/* ─────────────────────────────────────────────────────────────────────────── */
/* Document store                                                               */
/* ─────────────────────────────────────────────────────────────────────────── */

typedef struct {
    char  uri[MAX_URI];
    char *text;        /* heap-allocated, NUL-terminated */
    int   text_len;
    int   version;
    int   in_use;
} Document;

static Document docs[MAX_DOCS];

static Document *doc_find(const char *uri) {
    for (int i = 0; i < MAX_DOCS; i++)
        if (docs[i].in_use && strcmp(docs[i].uri, uri) == 0)
            return &docs[i];
    return NULL;
}

static Document *doc_open(const char *uri, const char *text, int version) {
    Document *d = doc_find(uri);
    if (!d) {
        for (int i = 0; i < MAX_DOCS; i++) {
            if (!docs[i].in_use) { d = &docs[i]; break; }
        }
    }
    if (!d) return NULL;
    strncpy(d->uri, uri, MAX_URI - 1);
    d->uri[MAX_URI - 1] = '\0';
    free(d->text);
    d->text_len = (int)strlen(text);
    d->text = malloc(d->text_len + 1);
    if (!d->text) return NULL;
    memcpy(d->text, text, d->text_len + 1);
    d->version = version;
    d->in_use  = 1;
    return d;
}

static void doc_close(const char *uri) {
    Document *d = doc_find(uri);
    if (d) { free(d->text); d->text = NULL; d->in_use = 0; }
}

/* Convert URI (file:///path) to filesystem path */
static void uri_to_path(const char *uri, char *path, int path_size) {
    if (strncmp(uri, "file://", 7) == 0) {
        strncpy(path, uri + 7, path_size - 1);
    } else {
        strncpy(path, uri, path_size - 1);
    }
    path[path_size - 1] = '\0';
}

/* Convert filesystem path to URI */

/* ─────────────────────────────────────────────────────────────────────────── */
/* Minimal JSON parser                                                          */
/* ─────────────────────────────────────────────────────────────────────────── */

typedef enum {
    JSON_NULL, JSON_BOOL, JSON_NUMBER, JSON_STRING, JSON_ARRAY, JSON_OBJECT
} JsonType;

typedef struct JsonNode JsonNode;
typedef struct JsonPair JsonPair;

struct JsonPair {
    char     *key;
    JsonNode *val;
    JsonPair *next;
};

struct JsonNode {
    JsonType type;
    union {
        int       b;          /* bool */
        double    n;          /* number */
        char     *s;          /* string (heap, NUL-terminated) */
        JsonNode *arr;        /* first array element */
        JsonPair *obj;        /* first object pair */
    };
    JsonNode *next;           /* next sibling (array) */
};

/* Simple arena for JSON nodes (freed after each request) */
#define JSON_ARENA_SIZE (256 * 1024)
static char  json_arena[JSON_ARENA_SIZE];
static int   json_arena_pos = 0;

static void *json_alloc(int sz) {
    sz = (sz + 7) & ~7;
    if (json_arena_pos + sz > JSON_ARENA_SIZE) return NULL;
    void *p = json_arena + json_arena_pos;
    memset(p, 0, sz);
    json_arena_pos += sz;
    return p;
}

static void json_arena_reset(void) { json_arena_pos = 0; }

typedef struct { const char *p; const char *end; } JsonParser;

static void jp_skip_ws(JsonParser *jp) {
    while (jp->p < jp->end && isspace((unsigned char)*jp->p)) jp->p++;
}

static char *jp_parse_string_raw(JsonParser *jp) {
    if (*jp->p != '"') return NULL;
    jp->p++;
    const char *start = jp->p;
    int len = 0;
    while (jp->p < jp->end && *jp->p != '"') {
        if (*jp->p == '\\') { jp->p++; if (jp->p < jp->end) jp->p++; len++; }
        else { jp->p++; len++; }
    }
    if (jp->p >= jp->end) return NULL;
    jp->p++; /* skip closing " */
    /* Second pass: copy with escape handling */
    char *buf = json_alloc(len + 1);
    if (!buf) return NULL;
    const char *s = start;
    char *d = buf;
    while (s < jp->p - 1) {
        if (*s == '\\') {
            s++;
            switch (*s) {
                case '"':  *d++ = '"';  break;
                case '\\': *d++ = '\\'; break;
                case '/':  *d++ = '/';  break;
                case 'n':  *d++ = '\n'; break;
                case 'r':  *d++ = '\r'; break;
                case 't':  *d++ = '\t'; break;
                case 'b':  *d++ = '\b'; break;
                case 'f':  *d++ = '\f'; break;
                case 'u':
                    /* skip 4 hex digits — output '?' for simplicity */
                    s += 4;
                    *d++ = '?';
                    break;
                default:   *d++ = *s;  break;
            }
            s++;
        } else {
            *d++ = *s++;
        }
    }
    *d = '\0';
    return buf;
}

static JsonNode *jp_parse_value(JsonParser *jp);

static JsonNode *jp_parse_array(JsonParser *jp) {
    jp->p++; /* skip '[' */
    JsonNode *head = NULL, *tail = NULL;
    jp_skip_ws(jp);
    if (*jp->p == ']') { jp->p++; goto done; }
    while (jp->p < jp->end) {
        jp_skip_ws(jp);
        JsonNode *elem = jp_parse_value(jp);
        if (!elem) break;
        if (!head) head = tail = elem;
        else { tail->next = elem; tail = elem; }
        jp_skip_ws(jp);
        if (*jp->p == ',') { jp->p++; continue; }
        if (*jp->p == ']') { jp->p++; break; }
        break;
    }
done:;
    JsonNode *node = json_alloc(sizeof(JsonNode));
    if (!node) return NULL;
    node->type = JSON_ARRAY;
    node->arr  = head;
    return node;
}

static JsonNode *jp_parse_object(JsonParser *jp) {
    jp->p++; /* skip '{' */
    JsonPair *head = NULL, *tail = NULL;
    jp_skip_ws(jp);
    if (*jp->p == '}') { jp->p++; goto done; }
    while (jp->p < jp->end) {
        jp_skip_ws(jp);
        if (*jp->p != '"') break;
        char *key = jp_parse_string_raw(jp);
        if (!key) break;
        jp_skip_ws(jp);
        if (*jp->p != ':') break;
        jp->p++;
        jp_skip_ws(jp);
        JsonNode *val = jp_parse_value(jp);
        if (!val) break;
        JsonPair *pair = json_alloc(sizeof(JsonPair));
        if (!pair) break;
        pair->key = key; pair->val = val;
        if (!head) head = tail = pair;
        else { tail->next = pair; tail = pair; }
        jp_skip_ws(jp);
        if (*jp->p == ',') { jp->p++; continue; }
        if (*jp->p == '}') { jp->p++; break; }
        break;
    }
done:;
    JsonNode *node = json_alloc(sizeof(JsonNode));
    if (!node) return NULL;
    node->type = JSON_OBJECT;
    node->obj  = head;
    return node;
}

static JsonNode *jp_parse_value(JsonParser *jp) {
    jp_skip_ws(jp);
    if (jp->p >= jp->end) return NULL;
    JsonNode *node = json_alloc(sizeof(JsonNode));
    if (!node) return NULL;
    char c = *jp->p;
    if (c == '"') {
        node->type = JSON_STRING;
        node->s    = jp_parse_string_raw(jp);
    } else if (c == '[') {
        /* node slot in arena is abandoned (reset per-request) */
        return jp_parse_array(jp);
    } else if (c == '{') {
        return jp_parse_object(jp);
    } else if (c == 't' && strncmp(jp->p, "true", 4) == 0) {
        node->type = JSON_BOOL; node->b = 1; jp->p += 4;
    } else if (c == 'f' && strncmp(jp->p, "false", 5) == 0) {
        node->type = JSON_BOOL; node->b = 0; jp->p += 5;
    } else if (c == 'n' && strncmp(jp->p, "null", 4) == 0) {
        node->type = JSON_NULL; jp->p += 4;
    } else if (c == '-' || isdigit((unsigned char)c)) {
        node->type = JSON_NUMBER;
        node->n    = strtod(jp->p, (char **)&jp->p);
    } else {
        return NULL;
    }
    return node;
}

static JsonNode *json_parse(const char *text, int len) {
    JsonParser jp = { text, text + len };
    return jp_parse_value(&jp);
}

/* Lookup helpers */
static JsonNode *json_get(JsonNode *obj, const char *key) {
    if (!obj || obj->type != JSON_OBJECT) return NULL;
    for (JsonPair *p = obj->obj; p; p = p->next)
        if (p->key && strcmp(p->key, key) == 0) return p->val;
    return NULL;
}

static const char *json_str(JsonNode *node) {
    if (!node || node->type != JSON_STRING) return "";
    return node->s ? node->s : "";
}

static int json_int(JsonNode *node) {
    if (!node) return 0;
    if (node->type == JSON_NUMBER) return (int)node->n;
    if (node->type == JSON_BOOL)   return node->b;
    return 0;
}

/* ─────────────────────────────────────────────────────────────────────────── */
/* JSON builder (output buffer)                                                 */
/* ─────────────────────────────────────────────────────────────────────────── */

typedef struct {
    char *buf;
    int   len;
    int   cap;
} JBuf;

static JBuf jbuf_new(void) {
    JBuf b = { malloc(4096), 0, 4096 };
    if (b.buf) b.buf[0] = '\0';
    return b;
}

static void jbuf_free(JBuf *b) { free(b->buf); b->buf = NULL; b->len = b->cap = 0; }

static void jbuf_grow(JBuf *b, int extra) {
    while (b->len + extra + 1 >= b->cap) {
        b->cap *= 2;
        b->buf  = realloc(b->buf, b->cap);
    }
}

static void jbuf_append(JBuf *b, const char *s) {
    int n = (int)strlen(s);
    jbuf_grow(b, n);
    memcpy(b->buf + b->len, s, n);
    b->len += n;
    b->buf[b->len] = '\0';
}

static void jbuf_appendf(JBuf *b, const char *fmt, ...) {
    char tmp[1024];
    va_list ap; va_start(ap, fmt); vsnprintf(tmp, sizeof(tmp), fmt, ap); va_end(ap);
    jbuf_append(b, tmp);
}

static void jbuf_append_str(JBuf *b, const char *s) {
    jbuf_append(b, "\"");
    for (const char *p = s; *p; p++) {
        switch (*p) {
            case '"':  jbuf_append(b, "\\\""); break;
            case '\\': jbuf_append(b, "\\\\"); break;
            case '\n': jbuf_append(b, "\\n");  break;
            case '\r': jbuf_append(b, "\\r");  break;
            case '\t': jbuf_append(b, "\\t");  break;
            default:
                if ((unsigned char)*p < 0x20) {
                    char esc[8]; snprintf(esc, sizeof(esc), "\\u%04x", (unsigned char)*p);
                    jbuf_append(b, esc);
                } else {
                    char c2[2] = { *p, '\0' };
                    jbuf_append(b, c2);
                }
                break;
        }
    }
    jbuf_append(b, "\"");
}

/* ─────────────────────────────────────────────────────────────────────────── */
/* LSP I/O: read/write JSON-RPC messages                                        */
/* ─────────────────────────────────────────────────────────────────────────── */


/* Read a complete LSP message from stdin. Returns heap-allocated JSON string. */
static char *lsp_read_message(void) {
    /* Read headers until blank line */
    int content_length = -1;
    char header[256];
    while (1) {
        /* Read one line */
        int i = 0;
        while (1) {
            int c = fgetc(stdin);
            if (c == EOF) return NULL;
            if (c == '\n') break;
            if (c != '\r' && i < (int)sizeof(header) - 1)
                header[i++] = (char)c;
        }
        header[i] = '\0';
        if (i == 0) break;  /* blank line: end of headers */
        if (strncmp(header, "Content-Length:", 15) == 0) {
            content_length = atoi(header + 15);
        }
    }
    if (content_length <= 0) return NULL;
    char *body = malloc(content_length + 1);
    if (!body) return NULL;
    int got = 0;
    while (got < content_length) {
        int n = (int)fread(body + got, 1, content_length - got, stdin);
        if (n <= 0) { free(body); return NULL; }
        got += n;
    }
    body[content_length] = '\0';
    return body;
}

/* Send a JSON-RPC response/notification to stdout */
static void lsp_send(const char *json) {
    int len = (int)strlen(json);
    fprintf(stdout, "Content-Length: %d\r\n\r\n%s", len, json);
    fflush(stdout);
}

static void lsp_log(const char *fmt, ...) {
    char msg[1024];
    va_list ap; va_start(ap, fmt); vsnprintf(msg, sizeof(msg), fmt, ap); va_end(ap);
    fprintf(stderr, "[rex-lsp] %s\n", msg);
}

/* Send a JSON-RPC response (with id) */
static void lsp_respond(JsonNode *req, const char *result_json) {
    JsonNode *id_node = json_get(req, "id");
    JBuf b = jbuf_new();
    jbuf_append(&b, "{\"jsonrpc\":\"2.0\",\"id\":");
    if (!id_node || id_node->type == JSON_NULL) {
        jbuf_append(&b, "null");
    } else if (id_node->type == JSON_NUMBER) {
        jbuf_appendf(&b, "%d", (int)id_node->n);
    } else if (id_node->type == JSON_STRING) {
        jbuf_append_str(&b, id_node->s);
    }
    jbuf_append(&b, ",\"result\":");
    jbuf_append(&b, result_json);
    jbuf_append(&b, "}");
    lsp_send(b.buf);
    jbuf_free(&b);
}

/* Send a JSON-RPC error response */
static void lsp_respond_error(JsonNode *req, int code, const char *message) {
    JsonNode *id_node = json_get(req, "id");
    JBuf b = jbuf_new();
    jbuf_append(&b, "{\"jsonrpc\":\"2.0\",\"id\":");
    if (!id_node || id_node->type == JSON_NULL) {
        jbuf_append(&b, "null");
    } else if (id_node->type == JSON_NUMBER) {
        jbuf_appendf(&b, "%d", (int)id_node->n);
    } else {
        jbuf_append(&b, "null");
    }
    jbuf_appendf(&b, ",\"error\":{\"code\":%d,\"message\":", code);
    jbuf_append_str(&b, message);
    jbuf_append(&b, "}}");
    lsp_send(b.buf);
    jbuf_free(&b);
}

/* Send a notification (no id) */
static void lsp_notify(const char *method, const char *params_json) {
    JBuf b = jbuf_new();
    jbuf_append(&b, "{\"jsonrpc\":\"2.0\",\"method\":");
    jbuf_append_str(&b, method);
    jbuf_append(&b, ",\"params\":");
    jbuf_append(&b, params_json);
    jbuf_append(&b, "}");
    lsp_send(b.buf);
    jbuf_free(&b);
}

/* ─────────────────────────────────────────────────────────────────────────── */
/* Protocol (prot) index — built from scanning open documents                   */
/* ─────────────────────────────────────────────────────────────────────────── */

typedef struct {
    char name[PROTO_NAME_LEN];
    char sig[PROTO_SIG_LEN];       /* full signature string: prot foo(int a) -> int */
    char doc[PROTO_DOC_LEN];       /* accumulated /// doc comment */
    char uri[MAX_URI];
    int  line;                     /* 0-indexed */
    int  col;
} ProtoEntry;

static ProtoEntry proto_table[MAX_PROTOS];
static int        proto_count = 0;

/* Scan a document for prot definitions and /// doc comments */
static void scan_protos(const char *uri, const char *text) {
    /* Remove all protos from this URI first */
    int w = 0;
    for (int i = 0; i < proto_count; i++) {
        if (strcmp(proto_table[i].uri, uri) != 0) {
            if (w != i) proto_table[w] = proto_table[i];
            w++;
        }
    }
    proto_count = w;

    const char *p = text;
    int line = 0;
    char doc_buf[PROTO_DOC_LEN] = {0};

    while (*p) {
        /* Collect /// doc comment */
        if (p[0] == '/' && p[1] == '/' && p[2] == '/') {
            const char *start = p + 3;
            if (*start == ' ') start++;
            const char *end = start;
            while (*end && *end != '\n') end++;
            int doclen = (int)(end - start);
            int existing = (int)strlen(doc_buf);
            if (existing + doclen + 2 < PROTO_DOC_LEN) {
                if (existing > 0) { doc_buf[existing] = ' '; existing++; }
                memcpy(doc_buf + existing, start, doclen);
                doc_buf[existing + doclen] = '\0';
            }
            p = end;
            if (*p == '\n') { p++; line++; }
            continue;
        }

        /* Check for "prot " keyword */
        if (strncmp(p, "prot ", 5) == 0 && proto_count < MAX_PROTOS) {
            ProtoEntry *pe = &proto_table[proto_count];
            memset(pe, 0, sizeof(*pe));
            pe->line = line;
            pe->col  = 0;
            strncpy(pe->uri, uri, MAX_URI - 1);
            strncpy(pe->doc, doc_buf, PROTO_DOC_LEN - 1);
            doc_buf[0] = '\0';

            const char *name_start = p + 5;
            const char *name_end   = name_start;
            while (*name_end && (isalnum((unsigned char)*name_end) || *name_end == '_')) name_end++;
            int namelen = (int)(name_end - name_start);
            if (namelen > 0 && namelen < PROTO_NAME_LEN) {
                memcpy(pe->name, name_start, namelen);
                pe->name[namelen] = '\0';
            }

            /* Extract full signature up to newline or body colon */
            const char *sig_end = p;
            while (*sig_end && *sig_end != '\n') sig_end++;
            int siglen = (int)(sig_end - p);
            if (siglen >= PROTO_SIG_LEN) siglen = PROTO_SIG_LEN - 1;
            memcpy(pe->sig, p, siglen);
            pe->sig[siglen] = '\0';

            if (pe->name[0]) proto_count++;
        } else {
            /* Not a doc comment or prot — clear accumulated doc */
            if (*p != '\n' && *p != ' ' && *p != '\t' && *p != '\r') {
                doc_buf[0] = '\0';
            }
        }

        if (*p == '\n') line++;
        p++;
    }
}

/* ─────────────────────────────────────────────────────────────────────────── */
/* Diagnostics — fork rexc, parse stderr, publish                              */
/* ─────────────────────────────────────────────────────────────────────────── */

/* Find rexc binary: same directory as this executable, or on PATH */
static char rexc_path[512] = {0};

static void find_rexc(void) {
    /* Try common locations */
    static const char *candidates[] = {
        "/usr/local/bin/rexc",
        "/usr/bin/rexc",
        "./rexc",
        NULL
    };
    /* Try same dir as this process */
    char self[512];
    ssize_t n = readlink("/proc/self/exe", self, sizeof(self) - 1);
    if (n > 0) {
        self[n] = '\0';
        char *slash = strrchr(self, '/');
        if (slash) {
            *(slash + 1) = '\0';
            snprintf(rexc_path, sizeof(rexc_path), "%srexc", self);
            if (access(rexc_path, X_OK) == 0) return;
        }
    }
    for (int i = 0; candidates[i]; i++) {
        if (access(candidates[i], X_OK) == 0) {
            strncpy(rexc_path, candidates[i], sizeof(rexc_path) - 1);
            return;
        }
    }
    strncpy(rexc_path, "rexc", sizeof(rexc_path) - 1);
}

typedef struct {
    int line;       /* 0-indexed */
    int col;        /* 0-indexed */
    int end_line;
    int end_col;
    int severity;   /* 1=Error 2=Warning 3=Info */
    char message[512];
} Diagnostic;

/* Parse a line from rexc stderr like:
 *   error: expected identifier
 *   rex: file.rex:47: bounds error: ...  (future format)
 * Returns 1 if a diagnostic was extracted */
static int parse_diag_line(const char *line, const char *filename, Diagnostic *diag) {
    memset(diag, 0, sizeof(*diag));
    diag->severity  = 1; /* error by default */
    diag->end_line  = diag->line;
    diag->end_col   = 80;

    /* Format: rex: <file>:<line>: <message> */
    if (strncmp(line, "rex: ", 5) == 0) {
        const char *p = line + 5;
        /* skip filename */
        while (*p && *p != ':') p++;
        if (*p == ':') p++;
        /* parse line number */
        int lineno = 0;
        while (*p && isdigit((unsigned char)*p)) { lineno = lineno*10 + (*p - '0'); p++; }
        if (*p == ':') p++;
        while (*p == ' ') p++;
        diag->line     = lineno > 0 ? lineno - 1 : 0;
        diag->end_line = diag->line;
        strncpy(diag->message, p, 511);
        return 1;
    }

    /* Format: error: <message> */
    if (strncmp(line, "error: ", 7) == 0) {
        strncpy(diag->message, line + 7, 511);
        return 1;
    }
    if (strncmp(line, "Error: ", 7) == 0) {
        strncpy(diag->message, line + 7, 511);
        return 1;
    }
    /* warning: */
    if (strncmp(line, "warning: ", 9) == 0) {
        diag->severity = 2;
        strncpy(diag->message, line + 9, 511);
        return 1;
    }

    /* Any non-empty line from rexc stderr is treated as an error message */
    if (line[0] && line[0] != '\n') {
        strncpy(diag->message, line, 511);
        return 1;
    }
    return 0;
}

static void publish_diagnostics(const char *uri, const char *text) {
    char path[512];
    uri_to_path(uri, path, sizeof(path));

    /* Build rex command: rex check --json path */
    char rex_exe[512];
    snprintf(rex_exe, sizeof(rex_exe), "%s", rexc_path);
    char *slash = strrchr(rex_exe, '/');
    if (slash) { strcpy(slash + 1, "rex"); }
    else        { strcpy(rex_exe, "rex"); }

    /* Write current text to temp file to check it without saving */
    char tmpfile[64];
    snprintf(tmpfile, sizeof(tmpfile), "/tmp/rex_diag_%d.rex", (int)getpid());
    FILE *f = fopen(tmpfile, "w");
    if (!f) return;
    fputs(text, f);
    fclose(f);

    char cmd[1024];
    snprintf(cmd, sizeof(cmd), "%s check --json %s 2>/dev/null", rex_exe, tmpfile);

    FILE *fp = popen(cmd, "r");
    if (!fp) { unlink(tmpfile); return; }

    char *json_out = malloc(JSON_BUF_SIZE);
    if (!json_out) { pclose(fp); unlink(tmpfile); return; }
    int n = (int)fread(json_out, 1, JSON_BUF_SIZE - 1, fp);
    json_out[n] = '\0';
    pclose(fp);
    unlink(tmpfile);

    /* The 'rex check --json' output should be exactly the params for publishDiagnostics */
    if (n > 2 && json_out[0] == '{') {
        /* Need to replace the temp filename in JSON with original URI if rex check
           doesn't handle the filename parameter cleanly.
           Assuming 'rex check --json' returns a full publishDiagnostics notification body. */
        lsp_notify("textDocument/publishDiagnostics", json_out);
    } else {
        /* Fallback to clearing diagnostics if check --json failed or returned nothing */
        char clear_params[1024];
        snprintf(clear_params, sizeof(clear_params), "{\"uri\":\"%s\",\"diagnostics\":[]}", uri);
        lsp_notify("textDocument/publishDiagnostics", clear_params);
    }
    free(json_out);
}

/* ─────────────────────────────────────────────────────────────────────────── */
/* Cursor helpers                                                               */
/* ─────────────────────────────────────────────────────────────────────────── */

/* Get offset into text for (line, character) — both 0-indexed */
static int offset_of(const char *text, int line, int col) {
    int cur_line = 0, cur_col = 0, i = 0;
    while (text[i]) {
        if (cur_line == line && cur_col == col) return i;
        if (text[i] == '\n') { cur_line++; cur_col = 0; }
        else cur_col++;
        i++;
    }
    return i;
}

/* Extract identifier at offset */
static void ident_at(const char *text, int off, char *out, int out_size) {
    out[0] = '\0';
    if (!text[off]) return;
    /* Find start */
    int start = off;
    while (start > 0 && (isalnum((unsigned char)text[start-1]) || text[start-1] == '_'))
        start--;
    /* Find end */
    int end = off;
    while (text[end] && (isalnum((unsigned char)text[end]) || text[end] == '_'))
        end++;
    int len = end - start;
    if (len <= 0 || len >= out_size) return;
    memcpy(out, text + start, len);
    out[len] = '\0';
}

/* Get the character before the cursor (skipping whitespace backwards) */
static char char_before(const char *text, int off) {
    int i = off - 1;
    while (i > 0 && (text[i] == ' ' || text[i] == '\t')) i--;
    return i >= 0 ? text[i] : '\0';
}

/* Find the type of a variable by scanning backwards for its declaration */
static void var_type_at(const char *text, const char *varname, char *type_out, int type_size) {
    type_out[0] = '\0';
    /* Look for patterns: "TYPE varname" */
    static const char *types[] = { "int","float","bool","str","char","byte","seq","dict","set","tup", NULL };
    for (int t = 0; types[t]; t++) {
        /* search for "TYPE varname" in text */
        const char *p = text;
        while ((p = strstr(p, varname)) != NULL) {
            /* check that there's a type keyword before it */
            int vlen = (int)strlen(varname);
            if (p > text && (isalnum((unsigned char)p[-1]) || p[-1] == '_')) { p++; continue; }
            if (isalnum((unsigned char)p[vlen]) || p[vlen] == '_') { p++; continue; }
            /* scan backwards for type */
            const char *back = p - 1;
            while (back > text && (*back == ' ' || *back == '\t')) back--;
            int tlen = (int)strlen(types[t]);
            if (back - tlen + 1 >= text &&
                strncmp(back - tlen + 1, types[t], tlen) == 0 &&
                (back - tlen + 1 == text || !isalnum((unsigned char)*(back - tlen)))) {
                strncpy(type_out, types[t], type_size - 1);
                return;
            }
            p++;
        }
    }
}

/* ─────────────────────────────────────────────────────────────────────────── */
/* LSP method handlers                                                          */
/* ─────────────────────────────────────────────────────────────────────────── */

/* initialize */
static void handle_initialize(JsonNode *req) {
    const char *result =
        "{"
        "\"capabilities\":{"
        "\"textDocumentSync\":{\"openClose\":true,\"change\":1},"
        "\"completionProvider\":{\"triggerCharacters\":[\".\",\"@\",\"{\",\" \"]},"
        "\"hoverProvider\":true,"
        "\"definitionProvider\":true,"
        "\"signatureHelpProvider\":{\"triggerCharacters\":[\"(\",\",\"]},"
        "\"renameProvider\":{\"prepareProvider\":true},"
        "\"documentFormattingProvider\":true,"
        "\"diagnosticProvider\":{\"interFileDependencies\":false,\"workspaceDiagnostics\":false},"
        "\"semanticTokensProvider\":{"
        "\"legend\":{"
        "\"tokenTypes\":[\"namespace\",\"type\",\"class\",\"enum\",\"interface\","
        "\"struct\",\"typeParameter\",\"parameter\",\"variable\",\"property\","
        "\"enumMember\",\"event\",\"function\",\"method\",\"macro\",\"keyword\","
        "\"modifier\",\"comment\",\"string\",\"number\",\"operator\"],"
        "\"tokenModifiers\":[\"declaration\",\"definition\",\"readonly\",\"static\","
        "\"deprecated\",\"abstract\",\"async\",\"modification\",\"documentation\",\"defaultLibrary\"]"
        "},"
        "\"full\":true"
        "}"
        "},"
        "\"serverInfo\":{\"name\":\"rex-lsp\",\"version\":\"5.0\"}"
        "}";
    lsp_respond(req, result);
}

/* textDocument/didOpen */
static void handle_did_open(JsonNode *params) {
    JsonNode *td  = json_get(params, "textDocument");
    if (!td) return;
    const char *uri     = json_str(json_get(td, "uri"));
    const char *text    = json_str(json_get(td, "text"));
    int         version = json_int(json_get(td, "version"));
    Document *d = doc_open(uri, text, version);
    if (!d) return;
    scan_protos(uri, text);
    publish_diagnostics(uri, text);
}

/* textDocument/didChange */
static void handle_did_change(JsonNode *params) {
    JsonNode *td  = json_get(params, "textDocument");
    if (!td) return;
    const char *uri     = json_str(json_get(td, "uri"));
    int         version = json_int(json_get(td, "version"));
    JsonNode   *changes = json_get(params, "contentChanges");
    if (!changes || changes->type != JSON_ARRAY) return;

    Document *d = doc_find(uri);

    /* Apply incremental changes — we use TextDocumentSyncKind.Full (1) so
       each change is the full new text. */
    for (JsonNode *ch = changes->arr; ch; ch = ch->next) {
        const char *new_text = json_str(json_get(ch, "text"));
        d = doc_open(uri, new_text, version);
    }
    if (!d) return;
    scan_protos(uri, d->text);
    publish_diagnostics(uri, d->text);
}

/* textDocument/didClose */
static void handle_did_close(JsonNode *params) {
    JsonNode *td = json_get(params, "textDocument");
    if (!td) return;
    doc_close(json_str(json_get(td, "uri")));
}

/* textDocument/completion */
static void handle_completion(JsonNode *req, JsonNode *params) {
    JsonNode *td  = json_get(params, "textDocument");
    JsonNode *pos = json_get(params, "position");
    if (!td || !pos) { lsp_respond(req, "[]"); return; }

    const char *uri  = json_str(json_get(td, "uri"));
    int         line = json_int(json_get(pos, "line"));
    int         col  = json_int(json_get(pos, "character"));

    Document *d = doc_find(uri);
    const char *text = d ? d->text : "";
    int off = offset_of(text, line, col);

    JBuf items = jbuf_new();
    jbuf_append(&items, "[");
    int first = 1;

#define ITEM(label, kind, detail, doc_str, insert)  do { \
    if (!first) jbuf_append(&items, ",");              \
    jbuf_append(&items, "{\"label\":");                \
    jbuf_append_str(&items, (label));                  \
    jbuf_appendf(&items, ",\"kind\":%d", (kind));      \
    jbuf_append(&items, ",\"detail\":");               \
    jbuf_append_str(&items, (detail));                 \
    jbuf_append(&items, ",\"documentation\":");        \
    jbuf_append_str(&items, (doc_str));                \
    jbuf_append(&items, ",\"insertText\":");           \
    jbuf_append_str(&items, (insert));                 \
    jbuf_append(&items, ",\"insertTextFormat\":2}");   \
    first = 0;                                         \
} while(0)

    /* Determine context: what's before the cursor */
    char prev = (off > 0) ? char_before(text, off) : '\0';

    if (prev == '.') {
        /* Method completion: find type of variable before the dot */
        /* Scan backwards past the dot to find the identifier */
        int scan = off - 1;
        while (scan > 0 && (isspace((unsigned char)text[scan]) || text[scan] == '.')) scan--;
        char varname[64] = {0};
        int vlen = 0;
        while (scan >= 0 && (isalnum((unsigned char)text[scan]) || text[scan] == '_')) {
            if (vlen < 63) varname[vlen++] = text[scan];
            scan--;
        }
        /* Reverse varname */
        for (int i = 0; i < vlen / 2; i++) {
            char t = varname[i]; varname[i] = varname[vlen - 1 - i]; varname[vlen - 1 - i] = t;
        }
        varname[vlen] = '\0';
        char vartype[32] = {0};
        var_type_at(text, varname, vartype, sizeof(vartype));

        /* Emit all methods for the detected type (or all if unknown) */
        for (int i = 0; REX_METHODS[i].name; i++) {
            if (!vartype[0] || strcmp(REX_METHODS[i].type, vartype) == 0) {
                char insert[128];
                /* For methods with params, add snippet placeholder */
                const char *sig = REX_METHODS[i].sig;
                if (strstr(sig, "()")) {
                    snprintf(insert, sizeof(insert), "%s()", REX_METHODS[i].name);
                } else {
                    snprintf(insert, sizeof(insert), "%s($1)", REX_METHODS[i].name);
                }
                ITEM(REX_METHODS[i].name, 2, REX_METHODS[i].sig, REX_METHODS[i].doc, insert);
            }
        }
    } else if (prev == '@') {
        /* Protocol name completion */
        for (int i = 0; i < proto_count; i++) {
            ITEM(proto_table[i].name, 3, proto_table[i].sig, proto_table[i].doc,
                 proto_table[i].name);
        }
    } else if (prev == '{') {
        /* Inside { in string: return all in-scope variables */
        /* Simple scan for local variables in current doc */
        const char *p = text;
        while (p < text + off) {
            if (isalpha((unsigned char)*p) || *p == '_') {
                char name[64]; int len = 0;
                while (p < text + off && (isalnum((unsigned char)*p) || *p == '_')) {
                    if (len < 63) name[len++] = *p;
                    p++;
                }
                name[len] = '\0';
                /* Check if it's a variable (not keyword) */
                int is_kw = 0;
                for (int i = 0; REX_KEYWORDS[i]; i++) {
                    if (strcmp(name, REX_KEYWORDS[i]) == 0) { is_kw = 1; break; }
                }
                if (!is_kw && len > 0) {
                    ITEM(name, 6, "variable", "", name);
                }
            } else {
                p++;
            }
        }
    } else {
        /* Keyword completion */
        for (int i = 0; REX_KEYWORDS[i]; i++) {
            ITEM(REX_KEYWORDS[i], 14, "", "", REX_KEYWORDS[i]);
        }
        /* Also add protocol names */
        for (int i = 0; i < proto_count; i++) {
            char insert[PROTO_NAME_LEN + 8];
            snprintf(insert, sizeof(insert), "@%s($1)", proto_table[i].name);
            ITEM(proto_table[i].name, 3, proto_table[i].sig, proto_table[i].doc, insert);
        }
    }

    jbuf_append(&items, "]");
    lsp_respond(req, items.buf);
    jbuf_free(&items);
#undef ITEM
}

/* textDocument/hover */
static void handle_hover(JsonNode *req, JsonNode *params) {
    JsonNode *td  = json_get(params, "textDocument");
    JsonNode *pos = json_get(params, "position");
    if (!td || !pos) { lsp_respond(req, "null"); return; }

    const char *uri  = json_str(json_get(td, "uri"));
    int         line = json_int(json_get(pos, "line"));
    int         col  = json_int(json_get(pos, "character"));

    Document *d = doc_find(uri);
    if (!d) { lsp_respond(req, "null"); return; }

    int off = offset_of(d->text, line, col);
    char ident[64] = {0};
    ident_at(d->text, off, ident, sizeof(ident));

    JBuf result = jbuf_new();

    /* Check if it's a keyword */
    int is_kw = 0;
    for (int i = 0; REX_KEYWORDS[i]; i++) {
        if (strcmp(ident, REX_KEYWORDS[i]) == 0) { is_kw = 1; break; }
    }

    /* Check if it's a protocol */
    int is_proto = 0;
    for (int i = 0; i < proto_count; i++) {
        if (strcmp(proto_table[i].name, ident) == 0) {
            jbuf_append(&result, "{\"contents\":{\"kind\":\"markdown\",\"value\":");
            char md[PROTO_SIG_LEN + PROTO_DOC_LEN + 64];
            snprintf(md, sizeof(md), "```rex\n%s\n```\n%s", proto_table[i].sig, proto_table[i].doc);
            jbuf_append_str(&result, md);
            jbuf_append(&result, "}}");
            is_proto = 1;
            break;
        }
    }

    if (!is_proto) {
        if (is_kw) {
            /* Type keyword hover */
            jbuf_append(&result, "{\"contents\":{\"kind\":\"markdown\",\"value\":");
            char md[128];
            snprintf(md, sizeof(md), "**`%s`** — Rex keyword", ident);
            jbuf_append_str(&result, md);
            jbuf_append(&result, "}}");
        } else if (isdigit((unsigned char)ident[0]) || (ident[0] == '-' && isdigit((unsigned char)ident[1]))) {
            /* Literal hover */
            jbuf_append(&result, "{\"contents\":{\"kind\":\"markdown\",\"value\":");
            char md[128];
            if (strchr(ident, '.')) {
                snprintf(md, sizeof(md), "```rex\nfloat\n```\nValue: %s", ident);
            } else {
                long long val = strtoll(ident, NULL, 0);
                snprintf(md, sizeof(md), "```rex\nint\n```\nDecimal: %lld\nHex: 0x%llx", val, val);
            }
            jbuf_append_str(&result, md);
            jbuf_append(&result, "}}");
        } else if (ident[0]) {
            /* Variable hover: find its type */
            char vartype[32] = {0};
            var_type_at(d->text, ident, vartype, sizeof(vartype));
            jbuf_append(&result, "{\"contents\":{\"kind\":\"markdown\",\"value\":");
            char md[128];
            if (vartype[0])
                snprintf(md, sizeof(md), "```rex\n%s %s\n```", vartype, ident);
            else
                snprintf(md, sizeof(md), "```rex\n%s\n```", ident);
            jbuf_append_str(&result, md);
            jbuf_append(&result, "}}");
        } else {
            jbuf_append(&result, "null");
        }
    }

    lsp_respond(req, result.buf);
    jbuf_free(&result);
}

/* textDocument/definition */
static void handle_definition(JsonNode *req, JsonNode *params) {
    JsonNode *td  = json_get(params, "textDocument");
    JsonNode *pos = json_get(params, "position");
    if (!td || !pos) { lsp_respond(req, "null"); return; }

    const char *uri  = json_str(json_get(td, "uri"));
    int         line = json_int(json_get(pos, "line"));
    int         col  = json_int(json_get(pos, "character"));

    Document *d = doc_find(uri);
    if (!d) { lsp_respond(req, "null"); return; }

    int off = offset_of(d->text, line, col);
    char ident[64] = {0};
    ident_at(d->text, off, ident, sizeof(ident));
    if (!ident[0]) { lsp_respond(req, "null"); return; }

    /* Find prot definition in proto_table */
    for (int i = 0; i < proto_count; i++) {
        if (strcmp(proto_table[i].name, ident) == 0) {
            JBuf result = jbuf_new();
            jbuf_append(&result, "{\"uri\":");
            jbuf_append_str(&result, proto_table[i].uri);
            jbuf_appendf(&result,
                ",\"range\":{\"start\":{\"line\":%d,\"character\":%d},"
                "\"end\":{\"line\":%d,\"character\":%d}}}",
                proto_table[i].line, 0,
                proto_table[i].line, (int)strlen(proto_table[i].sig));
            lsp_respond(req, result.buf);
            jbuf_free(&result);
            return;
        }
    }

    /* Also scan all open documents for variable declarations */
    for (int di = 0; di < MAX_DOCS; di++) {
        if (!docs[di].in_use) continue;
        const char *dtxt = docs[di].text;
        int cur_line = 0;
        const char *p = dtxt;
        while (*p) {
            /* Look for "TYPE ident" patterns */
            const char *found = strstr(p, ident);
            if (!found) break;
            /* Check it's a declaration (preceded by a type keyword) */
            if (found > dtxt && (isalnum((unsigned char)found[-1]) || found[-1] == '_')) {
                /* part of another identifier — skip */
                p = found + 1; continue;
            }
            int flen = (int)strlen(ident);
            if (isalnum((unsigned char)found[flen]) || found[flen] == '_') {
                p = found + 1; continue;
            }
            /* Count line for this offset */
            cur_line = 0;
            for (const char *q = dtxt; q < found; q++)
                if (*q == '\n') cur_line++;
            JBuf result = jbuf_new();
            jbuf_append(&result, "{\"uri\":");
            jbuf_append_str(&result, docs[di].uri);
            jbuf_appendf(&result,
                ",\"range\":{\"start\":{\"line\":%d,\"character\":0},"
                "\"end\":{\"line\":%d,\"character\":80}}}",
                cur_line, cur_line);
            lsp_respond(req, result.buf);
            jbuf_free(&result);
            return;
        }
    }

    lsp_respond(req, "null");
}

/* textDocument/signatureHelp */
static void handle_signature_help(JsonNode *req, JsonNode *params) {
    JsonNode *td  = json_get(params, "textDocument");
    JsonNode *pos = json_get(params, "position");
    if (!td || !pos) { lsp_respond(req, "null"); return; }

    const char *uri  = json_str(json_get(td, "uri"));
    int         line = json_int(json_get(pos, "line"));
    int         col  = json_int(json_get(pos, "character"));

    Document *d = doc_find(uri);
    if (!d) { lsp_respond(req, "null"); return; }

    int off = offset_of(d->text, line, col);

    /* Scan backwards to find the opening '(' and protocol name */
    int depth = 0;
    int comma_count = 0;
    int paren_off = off - 1;
    while (paren_off >= 0) {
        char c = d->text[paren_off];
        if (c == ')') depth++;
        else if (c == '(' && depth > 0) depth--;
        else if (c == '(' && depth == 0) break;
        else if (c == ',' && depth == 0) comma_count++;
        paren_off--;
    }

    if (paren_off < 0) { lsp_respond(req, "null"); return; }

    /* Scan backwards from paren_off to find the protocol name */
    int name_end = paren_off;
    while (name_end > 0 && (isalnum((unsigned char)d->text[name_end-1]) || d->text[name_end-1] == '_'))
        name_end--;
    /* Check for '@' prefix */
    if (name_end > 0 && d->text[name_end-1] == '@') name_end--;

    char proto_name[64] = {0};
    int pname_len = paren_off - name_end;
    if (pname_len > 0 && pname_len < 63) {
        memcpy(proto_name, d->text + name_end, pname_len);
        proto_name[pname_len] = '\0';
        /* strip leading '@' if it's there */
        if (proto_name[0] == '@') {
            memmove(proto_name, proto_name + 1, pname_len);
            pname_len--;
        }
    }

    /* Find in proto_table */
    for (int i = 0; i < proto_count; i++) {
        if (strcmp(proto_table[i].name, proto_name) == 0) {
            JBuf result = jbuf_new();
            jbuf_append(&result, "{\"signatures\":[{\"label\":");
            jbuf_append_str(&result, proto_table[i].sig);
            jbuf_append(&result, ",\"documentation\":");
            jbuf_append_str(&result, proto_table[i].doc);
            jbuf_append(&result, ",\"parameters\":[");

            /* Extract parameters from signature to create character offsets */
            const char *s = proto_table[i].sig;
            const char *p_start = strchr(s, '(');
            const char *p_end = strrchr(s, ')');
            if (p_start && p_end && p_end > p_start + 1) {
                const char *curr = p_start + 1;
                int param_idx = 0;
                while (curr < p_end) {
                    while (curr < p_end && isspace((unsigned char)*curr)) curr++;
                    const char *p_item_start = curr;
                    while (curr < p_end && *curr != ',') curr++;
                    const char *p_item_end = curr;
                    if (p_item_end > p_item_start) {
                        if (param_idx > 0) jbuf_append(&result, ",");
                        jbuf_appendf(&result, "{\"label\":[%d,%d]}",
                                     (int)(p_item_start - s), (int)(p_item_end - s));
                        param_idx++;
                    }
                    if (*curr == ',') curr++;
                }
            }
            jbuf_append(&result, "]}]");
            jbuf_appendf(&result, ",\"activeSignature\":0,\"activeParameter\":%d}", comma_count);
            lsp_respond(req, result.buf);
            jbuf_free(&result);
            return;
        }
    }

    lsp_respond(req, "null");
}

/* textDocument/prepareRename */
static void handle_prepare_rename(JsonNode *req, JsonNode *params) {
    JsonNode *td  = json_get(params, "textDocument");
    JsonNode *pos = json_get(params, "position");
    if (!td || !pos) { lsp_respond(req, "null"); return; }

    const char *uri  = json_str(json_get(td, "uri"));
    int         line = json_int(json_get(pos, "line"));
    int         col  = json_int(json_get(pos, "character"));

    Document *d = doc_find(uri);
    if (!d) { lsp_respond(req, "null"); return; }

    int off = offset_of(d->text, line, col);
    char ident[64] = {0};
    ident_at(d->text, off, ident, sizeof(ident));
    if (!ident[0]) { lsp_respond(req, "null"); return; }

    /* Reject keywords and built-in method names */
    for (int i = 0; REX_KEYWORDS[i]; i++) {
        if (strcmp(ident, REX_KEYWORDS[i]) == 0) {
            lsp_respond_error(req, -32600, "Cannot rename a keyword");
            return;
        }
    }

    /* Find the exact column of the identifier start */
    int id_start = off;
    while (id_start > 0 && (isalnum((unsigned char)d->text[id_start-1]) || d->text[id_start-1] == '_'))
        id_start--;
    int id_end = off;
    while (d->text[id_end] && (isalnum((unsigned char)d->text[id_end]) || d->text[id_end] == '_'))
        id_end++;

    JBuf result = jbuf_new();
    jbuf_appendf(&result,
        "{\"range\":{\"start\":{\"line\":%d,\"character\":%d},"
        "\"end\":{\"line\":%d,\"character\":%d}},\"placeholder\":",
        line, (col - (off - id_start)), line, (col - (off - id_start) + (id_end - id_start)));
    jbuf_append_str(&result, ident);
    jbuf_append(&result, "}");
    lsp_respond(req, result.buf);
    jbuf_free(&result);
}

/* textDocument/rename */
static void handle_rename(JsonNode *req, JsonNode *params) {
    JsonNode *td   = json_get(params, "textDocument");
    JsonNode *pos  = json_get(params, "position");
    JsonNode *name = json_get(params, "newName");
    if (!td || !pos || !name) { lsp_respond(req, "null"); return; }

    const char *uri      = json_str(json_get(td, "uri"));
    int         line     = json_int(json_get(pos, "line"));
    int         col      = json_int(json_get(pos, "character"));
    const char *new_name = json_str(name);

    Document *d = doc_find(uri);
    if (!d) { lsp_respond(req, "null"); return; }

    int off = offset_of(d->text, line, col);
    char ident[64] = {0};
    ident_at(d->text, off, ident, sizeof(ident));
    if (!ident[0]) { lsp_respond(req, "null"); return; }

    int ident_len = (int)strlen(ident);

    /* Build workspace edit: find all occurrences in the current document */
    JBuf edits = jbuf_new();
    jbuf_append(&edits, "[");
    int first = 1;

    const char *p = d->text;
    int cur_line = 0, cur_col = 0;
    while (*p) {
        if (strncmp(p, ident, ident_len) == 0) {
            /* Verify word boundary */
            int before_ok = (p == d->text || (!isalnum((unsigned char)p[-1]) && p[-1] != '_'));
            int after_ok  = (!isalnum((unsigned char)p[ident_len]) && p[ident_len] != '_');
            if (before_ok && after_ok) {
                if (!first) jbuf_append(&edits, ",");
                jbuf_appendf(&edits,
                    "{\"range\":{\"start\":{\"line\":%d,\"character\":%d},"
                    "\"end\":{\"line\":%d,\"character\":%d}},\"newText\":",
                    cur_line, cur_col, cur_line, cur_col + ident_len);
                jbuf_append_str(&edits, new_name);
                jbuf_append(&edits, "}");
                first = 0;
            }
        }
        if (*p == '\n') { cur_line++; cur_col = 0; }
        else cur_col++;
        p++;
    }

    jbuf_append(&edits, "]");

    JBuf result = jbuf_new();
    jbuf_append(&result, "{\"changes\":{");
    jbuf_append_str(&result, uri);
    jbuf_append(&result, ":");
    jbuf_append(&result, edits.buf);
    jbuf_append(&result, "}}");

    lsp_respond(req, result.buf);
    jbuf_free(&result);
    jbuf_free(&edits);
}

/* textDocument/formatting */
static void handle_formatting(JsonNode *req, JsonNode *params) {
    JsonNode *td = json_get(params, "textDocument");
    if (!td) { lsp_respond(req, "[]"); return; }

    const char *uri = json_str(json_get(td, "uri"));
    Document *d = doc_find(uri);
    if (!d) { lsp_respond(req, "[]"); return; }

    /* Try to run 'rex fmt --stdout' on the file */
    char tmpfile[64];
    snprintf(tmpfile, sizeof(tmpfile), "/tmp/rex_fmt_%d.rex", (int)getpid());
    FILE *f = fopen(tmpfile, "w");
    if (!f) { lsp_respond(req, "[]"); return; }
    fputs(d->text, f);
    fclose(f);

    /* Build rex command path */
    char rex_path[512];
    snprintf(rex_path, sizeof(rex_path), "%s", rexc_path);
    char *slash = strrchr(rex_path, '/');
    if (slash) { strcpy(slash + 1, "rex"); }
    else        { strcpy(rex_path, "rex"); }

    /* Run rex fmt --stdout tmpfile */
    char cmd[1024];
    snprintf(cmd, sizeof(cmd), "%s fmt --stdout %s 2>/dev/null", rex_path, tmpfile);
    FILE *fp = popen(cmd, "r");
    if (!fp) { unlink(tmpfile); lsp_respond(req, "[]"); return; }

    char *formatted = malloc(MAX_DOC_SIZE);
    int  fmt_len    = 0;
    if (formatted) {
        int n;
        while ((n = (int)fread(formatted + fmt_len, 1, MAX_DOC_SIZE - 1 - fmt_len, fp)) > 0)
            fmt_len += n;
        formatted[fmt_len] = '\0';
    }
    pclose(fp);
    unlink(tmpfile);

    if (!formatted || fmt_len == 0) {
        free(formatted);
        lsp_respond(req, "[]");
        return;
    }

    /* Return a single edit replacing the entire file */
    int lines = 0;
    for (const char *p = d->text; *p; p++) if (*p == '\n') lines++;

    JBuf result = jbuf_new();
    jbuf_appendf(&result,
        "[{\"range\":{\"start\":{\"line\":0,\"character\":0},"
        "\"end\":{\"line\":%d,\"character\":0}},\"newText\":", lines + 1);
    jbuf_append_str(&result, formatted);
    jbuf_append(&result, "}]");

    lsp_respond(req, result.buf);
    jbuf_free(&result);
    free(formatted);
}

/* textDocument/semanticTokens/full */
/* Token type indices matching the legend in initialize */
#define ST_NAMESPACE   0
#define ST_TYPE        1
#define ST_FUNCTION    12
#define ST_METHOD      13
#define ST_MACRO       14
#define ST_KEYWORD     15
#define ST_MODIFIER    16
#define ST_COMMENT     17
#define ST_STRING      18
#define ST_NUMBER      19
#define ST_OPERATOR    20
#define ST_VARIABLE    8

static void handle_semantic_tokens(JsonNode *req, JsonNode *params) {
    JsonNode *td = json_get(params, "textDocument");
    if (!td) { lsp_respond(req, "{\"data\":[]}"); return; }
    const char *uri = json_str(json_get(td, "uri"));
    Document *d = doc_find(uri);
    if (!d) { lsp_respond(req, "{\"data\":[]}"); return; }

    /* Encode tokens as [deltaLine, deltaStartChar, length, tokenType, tokenModifiers] */
    /* We do a simple single-pass scan */
    JBuf data = jbuf_new();
    jbuf_append(&data, "{\"data\":[");
    int first = 1;

    int prev_line = 0, prev_col = 0;
    int cur_line = 0, cur_col = 0;
    const char *p = d->text;

#define EMIT_TOKEN(line, col, len, tt, tm) do {         \
    int dl = (line) - prev_line;                        \
    int dc = (dl == 0) ? (col) - prev_col : (col);     \
    if (!first) jbuf_append(&data, ",");                \
    jbuf_appendf(&data, "%d,%d,%d,%d,%d", dl, dc, len, tt, tm); \
    prev_line = (line); prev_col = (col);               \
    first = 0;                                          \
} while(0)

    while (*p) {
        /* Skip line comments */
        if (p[0] == '/' && p[1] == '/') {
            int start_col = cur_col;
            const char *start = p;
            while (*p && *p != '\n') { p++; cur_col++; }
            int len = (int)(p - start);
            EMIT_TOKEN(cur_line, start_col, len, ST_COMMENT, 0);
            continue;
        }
        /* String literals */
        if (*p == '"') {
            int start_col = cur_col;
            const char *start = p;
            p++; cur_col++;
            while (*p && *p != '"') {
                if (*p == '\\') { p++; cur_col++; }
                p++; cur_col++;
            }
            if (*p == '"') { p++; cur_col++; }
            int len = (int)(p - start);
            EMIT_TOKEN(cur_line, start_col, len, ST_STRING, 0);
            continue;
        }
        /* # decorators: #memo #hot #inline #unsafe */
        if (*p == '#') {
            int start_col = cur_col;
            const char *start = p;
            while (*p && !isspace((unsigned char)*p)) { p++; cur_col++; }
            int len = (int)(p - start);
            EMIT_TOKEN(cur_line, start_col, len, ST_MACRO, 0);
            continue;
        }
        /* @ protocol calls */
        if (*p == '@') {
            int start_col = cur_col;
            p++; cur_col++;
            const char *name_start = p;
            while (*p && (isalnum((unsigned char)*p) || *p == '_')) { p++; cur_col++; }
            int len = (int)(p - name_start) + 1; /* include '@' */
            EMIT_TOKEN(cur_line, start_col, len, ST_FUNCTION, 0);
            continue;
        }
        /* Number literals */
        if (isdigit((unsigned char)*p) || (*p == '-' && isdigit((unsigned char)p[1]))) {
            int start_col = cur_col;
            const char *start = p;
            if (*p == '-') { p++; cur_col++; }
            while (*p && (isxdigit((unsigned char)*p) || *p == '.' || *p == 'x' ||
                          *p == 'b' || *p == 'o' || *p == '_')) { p++; cur_col++; }
            int len = (int)(p - start);
            EMIT_TOKEN(cur_line, start_col, len, ST_NUMBER, 0);
            continue;
        }
        /* Identifiers and keywords */
        if (isalpha((unsigned char)*p) || *p == '_') {
            int start_col = cur_col;
            const char *start = p;
            while (*p && (isalnum((unsigned char)*p) || *p == '_')) { p++; cur_col++; }
            int len = (int)(p - start);
            /* Check if keyword */
            int is_kw = 0;
            static const char *types[] = {"int","float","bool","str","char","byte","seq","dict","set","tup",NULL};
            for (int i = 0; types[i]; i++) {
                if ((int)strlen(types[i]) == len && strncmp(start, types[i], len) == 0) {
                    EMIT_TOKEN(cur_line, start_col, len, ST_TYPE, 0);
                    is_kw = 1; break;
                }
            }
            if (!is_kw) {
                for (int i = 0; REX_KEYWORDS[i]; i++) {
                    if ((int)strlen(REX_KEYWORDS[i]) == len && strncmp(start, REX_KEYWORDS[i], len) == 0) {
                        EMIT_TOKEN(cur_line, start_col, len, ST_KEYWORD, 0);
                        is_kw = 1; break;
                    }
                }
            }
            if (!is_kw) {
                EMIT_TOKEN(cur_line, start_col, len, ST_VARIABLE, 0);
            }
            continue;
        }
        /* Write-site ':' mutation marker */
        if (*p == ':' && (p == d->text || (!isalnum((unsigned char)p[-1]) && p[-1] != '_'))) {
            EMIT_TOKEN(cur_line, cur_col, 1, ST_MODIFIER, 0);
            p++; cur_col++;
            continue;
        }
        /* Newline */
        if (*p == '\n') { cur_line++; cur_col = 0; p++; continue; }
        p++; cur_col++;
    }

    jbuf_append(&data, "]}");
    lsp_respond(req, data.buf);
    jbuf_free(&data);
#undef EMIT_TOKEN
}

/* shutdown */
static void handle_shutdown(JsonNode *req) {
    lsp_respond(req, "null");
}

/* ─────────────────────────────────────────────────────────────────────────── */
/* Main dispatch loop                                                           */
/* ─────────────────────────────────────────────────────────────────────────── */

int main(int argc, char *argv[]) {
    (void)argc; (void)argv;

    /* Set stdin/stdout to binary, unbuffered */
    setvbuf(stdin,  NULL, _IONBF, 0);
    setvbuf(stdout, NULL, _IONBF, 0);

    find_rexc();
    lsp_log("Rex LSP server starting (rexc path: %s)", rexc_path);

    int running     = 1;
    int initialized = 0;
    int shutdown_requested = 0;

    while (running) {
        char *body = lsp_read_message();
        if (!body) break;

        json_arena_reset();
        JsonNode *msg = json_parse(body, (int)strlen(body));
        free(body);

        if (!msg || msg->type != JSON_OBJECT) continue;

        const char *method = json_str(json_get(msg, "method"));
        JsonNode   *params = json_get(msg, "params");
        int         has_id = (json_get(msg, "id") != NULL);

        if (strcmp(method, "initialize") == 0) {
            handle_initialize(msg);
            initialized = 1;
        } else if (strcmp(method, "initialized") == 0) {
            /* notification — no response */
        } else if (strcmp(method, "shutdown") == 0) {
            handle_shutdown(msg);
            shutdown_requested = 1;
        } else if (strcmp(method, "exit") == 0) {
            running = 0;
            exit(shutdown_requested ? 0 : 1);
        } else if (!initialized) {
            if (has_id) lsp_respond_error(msg, -32002, "Server not yet initialized");
        } else if (strcmp(method, "textDocument/didOpen") == 0) {
            if (params) handle_did_open(params);
        } else if (strcmp(method, "textDocument/didChange") == 0) {
            if (params) handle_did_change(params);
        } else if (strcmp(method, "textDocument/didClose") == 0) {
            if (params) handle_did_close(params);
        } else if (strcmp(method, "textDocument/completion") == 0) {
            handle_completion(msg, params ? params : msg);
        } else if (strcmp(method, "textDocument/hover") == 0) {
            handle_hover(msg, params ? params : msg);
        } else if (strcmp(method, "textDocument/definition") == 0) {
            handle_definition(msg, params ? params : msg);
        } else if (strcmp(method, "textDocument/signatureHelp") == 0) {
            handle_signature_help(msg, params ? params : msg);
        } else if (strcmp(method, "textDocument/prepareRename") == 0) {
            handle_prepare_rename(msg, params ? params : msg);
        } else if (strcmp(method, "textDocument/rename") == 0) {
            handle_rename(msg, params ? params : msg);
        } else if (strcmp(method, "textDocument/formatting") == 0) {
            handle_formatting(msg, params ? params : msg);
        } else if (strcmp(method, "textDocument/semanticTokens/full") == 0) {
            handle_semantic_tokens(msg, params ? params : msg);
        } else if (strcmp(method, "$/cancelRequest") == 0 ||
                   strcmp(method, "$/setTrace") == 0) {
            /* Silently ignore */
        } else {
            if (has_id)
                lsp_respond_error(msg, -32601, "Method not found");
        }
    }

    lsp_log("Rex LSP server exiting.");
    return 0;
}
