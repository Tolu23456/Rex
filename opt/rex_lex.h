#ifndef REX_LEX_H
#define REX_LEX_H

#include <stdint.h>

/* ── Token types (mirrors include/rex_defs.inc) ──────────────────────────── */
typedef enum {
    TOK_EOF=0, TOK_NEWLINE=1, TOK_INDENT=2, TOK_DEDENT=3,
    TOK_IDENT=4, TOK_INT_LIT=5, TOK_TYPE_INT=6, TOK_ASSIGN=7,
    TOK_COLON=8, TOK_OUTPUT=9, TOK_IF=10, TOK_FOR=11,
    TOK_IN=12, TOK_DOTDOT=13, TOK_EQEQ=14, TOK_ELSE=15,
    TOK_ELIF=16, TOK_WHILE=17, TOK_PROT=18, TOK_RETURN=19,
    TOK_STOP=20, TOK_AT=21, TOK_TYPE_FLOAT=22, TOK_FLOAT_LIT=23,
    TOK_TYPE_COMPLEX=24, TOK_COMPLEX_LIT=25, TOK_TYPE_BOOL=26,
    TOK_TRUE=27, TOK_FALSE=28, TOK_UNKNOWN=29, TOK_TYPE_STR=30,
    TOK_STR_LIT=31, TOK_PLUS=32, TOK_MINUS=33, TOK_LBRACK=34,
    TOK_RBRACK=35, TOK_LBRACE=36, TOK_RBRACE=37, TOK_COMMA=38,
    TOK_USE=39, TOK_MM=40, TOK_GC=41, TOK_STAR=42, TOK_SLASH=43,
    TOK_PERCENT=44, TOK_LPAREN=45, TOK_RPAREN=46, TOK_LT=47,
    TOK_GT=48, TOK_NEQ=49, TOK_LTE=50, TOK_GTE=51, TOK_AMP=52,
    TOK_PIPE=53, TOK_CARET=54, TOK_TILDE=55, TOK_LSHIFT=56,
    TOK_RSHIFT=57, TOK_AND=58, TOK_OR=59, TOK_NOT=60,
    TOK_ERR=61, TOK_TYPE_SEQ=62, TOK_PUSH=63, TOK_POP=64,
    TOK_LEN=65, TOK_SKIP=66, TOK_PASS=67, TOK_EACH=68,
    TOK_WHEN=69, TOK_TYPEOF=70, TOK_BIN=71,
    TOK_PLUSPLUS=72, TOK_MINUSMINUS=73, TOK_SWAP=74,
    TOK_ABS=75, TOK_CAP=76, TOK_IS=77, TOK_ARROW=78,
    TOK_STEP=79, TOK_NONE=80, TOK_KEYWORD=81, TOK_AS=82,
    TOK_REPEAT=83, TOK_UNREACHABLE=84, TOK_ASSERT=85,
    TOK_MEMO=86, TOK_MEMO_RESET=87, TOK_DOT=88, TOK_CLOCK=89,
    TOK_CONST=90, TOK_VOLATILE=91,
    TOK_SHOW=104, TOK_WARN=105, TOK_INPUT=109,
    TOK_FLIP=110, TOK_RAND=111,
    TOK_TYPE_DICT=123,
    TOK_HASH_KW=119,
    /* extra */
    TOK_PURE=130, TOK_HOT=132, TOK_COLD=133, TOK_INLINE_KW=136,
} TokType;

/* ── Token ───────────────────────────────────────────────────────────────── */
#define TOK_IDENT_MAX 64

typedef struct {
    TokType  type;
    int64_t  ival;           /* integer literal value                  */
    double   fval;           /* float literal value                    */
    char     sval[TOK_IDENT_MAX]; /* identifier / string literal        */
    int      slen;
    int      line;
} Token;

/* ── Lexer state ─────────────────────────────────────────────────────────── */
typedef struct {
    const char *src;
    int         pos;
    int         len;
    int         line;
    /* indent stack */
    int         indent_stack[256];
    int         indent_depth;
    int         pending_newline;
    int         pending_dedents;
    Token       lookahead;
    int         has_lookahead;
} Lexer;

void  lex_init(Lexer *lx, const char *src, int len);
Token lex_next(Lexer *lx);
Token lex_peek(Lexer *lx);
void  lex_consume(Lexer *lx);

#endif /* REX_LEX_H */
