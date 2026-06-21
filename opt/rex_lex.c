#include "rex_lex.h"
#include <string.h>
#include <stdlib.h>
#include <ctype.h>
#include <stdio.h>
#include <math.h>

void lex_init(Lexer *lx, const char *src, int len) {
    memset(lx, 0, sizeof(Lexer));
    lx->src = src;
    lx->len = len;
    lx->line = 1;
    lx->indent_stack[0] = 0;
    lx->indent_depth = 0;
    lx->pending_newline = 0;
    lx->pending_dedents = 0;
    lx->has_lookahead = 0;
}

static int peek_char(Lexer *lx) {
    if (lx->pos >= lx->len) return -1;
    return (unsigned char)lx->src[lx->pos];
}

static int get_char(Lexer *lx) {
    if (lx->pos >= lx->len) return -1;
    int c = (unsigned char)lx->src[lx->pos++];
    if (c == '\n') lx->line++;
    return c;
}

static void skip_comment(Lexer *lx) {
    while (lx->pos < lx->len && lx->src[lx->pos] != '\n') lx->pos++;
}

/* Keyword table */
typedef struct { const char *kw; TokType tok; } KW;
static KW kw_table[] = {
    {"int",        TOK_TYPE_INT},
    {"float",      TOK_TYPE_FLOAT},
    {"bool",       TOK_TYPE_BOOL},
    {"str",        TOK_TYPE_STR},
    {"complex",    TOK_TYPE_COMPLEX},
    {"seq",        TOK_TYPE_SEQ},
    {"dict",       TOK_TYPE_DICT},
    {"if",         TOK_IF},
    {"else",       TOK_ELSE},
    {"elif",       TOK_ELIF},
    {"while",      TOK_WHILE},
    {"for",        TOK_FOR},
    {"in",         TOK_IN},
    {"prot",       TOK_PROT},
    {"return",     TOK_RETURN},
    {"output",     TOK_OUTPUT},
    {"stop",       TOK_STOP},
    {"skip",       TOK_SKIP},
    {"pass",       TOK_PASS},
    {"each",       TOK_EACH},
    {"when",       TOK_WHEN},
    {"is",         TOK_IS},
    {"and",        TOK_AND},
    {"or",         TOK_OR},
    {"not",        TOK_NOT},
    {"true",       TOK_TRUE},
    {"false",      TOK_FALSE},
    {"unknown",    TOK_UNKNOWN},
    {"push",       TOK_PUSH},
    {"pop",        TOK_POP},
    {"len",        TOK_LEN},
    {"cap",        TOK_CAP},
    {"abs",        TOK_ABS},
    {"swap",       TOK_SWAP},
    {"typeof",     TOK_TYPEOF},
    {"use",        TOK_USE},
    {"mm",         TOK_MM},
    {"gc",         TOK_GC},
    {"err",        TOK_ERR},
    {"step",       TOK_STEP},
    {"as",         TOK_AS},
    {"repeat",     TOK_REPEAT},
    {"assert",     TOK_ASSERT},
    {"memo",       TOK_MEMO},
    {"memo_reset", TOK_MEMO_RESET},
    {"clock",      TOK_CLOCK},
    {"const",      TOK_CONST},
    {"volatile",   TOK_VOLATILE},
    {"show",       TOK_SHOW},
    {"warn",       TOK_WARN},
    {"input",      TOK_INPUT},
    {"flip",       TOK_FLIP},
    {"rand",       TOK_RAND},
    {"none",       TOK_NONE},
    {NULL, 0}
};

static TokType lookup_kw(const char *s) {
    for (int i = 0; kw_table[i].kw; i++)
        if (strcmp(kw_table[i].kw, s) == 0)
            return kw_table[i].tok;
    return TOK_IDENT;
}

static Token make_tok(Lexer *lx, TokType t) {
    Token tok = {0};
    tok.type = t;
    tok.line = lx->line;
    return tok;
}

static Token lex_real_next(Lexer *lx);

Token lex_next(Lexer *lx) {
    if (lx->has_lookahead) {
        lx->has_lookahead = 0;
        return lx->lookahead;
    }
    return lex_real_next(lx);
}

Token lex_peek(Lexer *lx) {
    if (!lx->has_lookahead) {
        lx->lookahead = lex_real_next(lx);
        lx->has_lookahead = 1;
    }
    return lx->lookahead;
}

void lex_consume(Lexer *lx) {
    lex_next(lx);
}

static Token lex_real_next(Lexer *lx) {
    /* emit pending dedents */
    if (lx->pending_dedents > 0) {
        lx->pending_dedents--;
        return make_tok(lx, TOK_DEDENT);
    }
    /* emit pending newline */
    if (lx->pending_newline) {
        lx->pending_newline = 0;
        return make_tok(lx, TOK_NEWLINE);
    }

top:
    if (lx->pos >= lx->len) return make_tok(lx, TOK_EOF);

    int c = (unsigned char)lx->src[lx->pos];

    /* handle comments */
    if (c == '/' && lx->pos+1 < lx->len && lx->src[lx->pos+1] == '/') {
        skip_comment(lx);
        goto top;
    }
    if (c == '#') {
        /* decorators like #hot #pure — read word after # */
        lx->pos++;
        char deco[32] = {0};
        int di = 0;
        while (lx->pos < lx->len && isalpha((unsigned char)lx->src[lx->pos]) && di < 31)
            deco[di++] = lx->src[lx->pos++];
        Token t = make_tok(lx, TOK_PASS);
        if      (strcmp(deco,"hot")==0)    t.type = TOK_HOT;
        else if (strcmp(deco,"cold")==0)   t.type = TOK_COLD;
        else if (strcmp(deco,"pure")==0)   t.type = TOK_PURE;
        else if (strcmp(deco,"inline")==0) t.type = TOK_INLINE_KW;
        else if (strcmp(deco,"memo")==0)   t.type = TOK_MEMO;
        strncpy(t.sval, deco, 31);
        return t;
    }

    /* newline — handle indentation */
    if (c == '\n') {
        lx->pos++;
        lx->line++;
        /* measure indent of next line */
        int indent = 0;
        while (lx->pos < lx->len) {
            int nc = (unsigned char)lx->src[lx->pos];
            if (nc == ' ')       { indent++;   lx->pos++; }
            else if (nc == '\t') { indent += 4; lx->pos++; }
            else if (nc == '\n') { indent = 0; lx->pos++; lx->line++; } /* blank line */
            else if (nc == '/' && lx->pos+1 < lx->len && lx->src[lx->pos+1]=='/')
                { skip_comment(lx); }
            else if (nc == '#')
                { skip_comment(lx); }
            else break;
        }
        if (lx->pos >= lx->len) return make_tok(lx, TOK_EOF);
        int cur_indent = lx->indent_stack[lx->indent_depth];
        if (indent > cur_indent) {
            lx->indent_depth++;
            lx->indent_stack[lx->indent_depth] = indent;
            lx->pending_newline = 1; /* emit NEWLINE then INDENT? just INDENT */
            return make_tok(lx, TOK_INDENT);
        } else if (indent < cur_indent) {
            /* pop indent levels */
            int dedents = 0;
            while (lx->indent_depth > 0 && lx->indent_stack[lx->indent_depth] > indent) {
                lx->indent_depth--;
                dedents++;
            }
            lx->pending_dedents = dedents - 1;
            lx->pending_newline = 1;
            return make_tok(lx, TOK_DEDENT);
        } else {
            /* same level — emit NEWLINE */
            return make_tok(lx, TOK_NEWLINE);
        }
    }

    /* skip spaces/tabs within a line */
    if (c == ' ' || c == '\t' || c == '\r') {
        lx->pos++;
        goto top;
    }

    /* string literal */
    if (c == '"') {
        lx->pos++;
        Token tok = make_tok(lx, TOK_STR_LIT);
        int i = 0;
        while (lx->pos < lx->len && (unsigned char)lx->src[lx->pos] != '"' && i < TOK_IDENT_MAX-1) {
            int ch = (unsigned char)lx->src[lx->pos++];
            if (ch == '\\') {
                int esc = (unsigned char)lx->src[lx->pos++];
                switch (esc) {
                    case 'n': ch = '\n'; break;
                    case 't': ch = '\t'; break;
                    case 'r': ch = '\r'; break;
                    case '"': ch = '"';  break;
                    case '\\': ch = '\\'; break;
                    default:  ch = esc; break;
                }
            }
            tok.sval[i++] = (char)ch;
        }
        if (lx->pos < lx->len) lx->pos++; /* closing " */
        tok.sval[i] = 0;
        tok.slen = i;
        return tok;
    }

    /* number literal */
    if (isdigit(c)) {
        Token tok = make_tok(lx, TOK_INT_LIT);
        int64_t ival = 0;
        while (lx->pos < lx->len && isdigit((unsigned char)lx->src[lx->pos]))
            ival = ival * 10 + (lx->src[lx->pos++] - '0');
        /* float? */
        if (lx->pos < lx->len && lx->src[lx->pos] == '.') {
            lx->pos++;
            double fval = (double)ival;
            double frac = 0.1;
            while (lx->pos < lx->len && isdigit((unsigned char)lx->src[lx->pos])) {
                fval += (lx->src[lx->pos++] - '0') * frac;
                frac *= 0.1;
            }
            /* exponent */
            if (lx->pos < lx->len && (lx->src[lx->pos]=='e'||lx->src[lx->pos]=='E')) {
                lx->pos++;
                int sign = 1;
                if (lx->pos < lx->len && (lx->src[lx->pos]=='+'||lx->src[lx->pos]=='-'))
                    sign = (lx->src[lx->pos++]=='+') ? 1 : -1;
                int exp = 0;
                while (lx->pos < lx->len && isdigit((unsigned char)lx->src[lx->pos]))
                    exp = exp*10 + (lx->src[lx->pos++]-'0');
                fval *= pow(10.0, sign * exp);
            }
            tok.type = TOK_FLOAT_LIT;
            tok.fval = fval;
            memcpy(&tok.ival, &fval, sizeof(double));
        } else {
            tok.ival = ival;
        }
        return tok;
    }

    /* identifier / keyword */
    if (isalpha(c) || c == '_') {
        Token tok = make_tok(lx, TOK_IDENT);
        int i = 0;
        while (lx->pos < lx->len && (isalnum((unsigned char)lx->src[lx->pos]) || lx->src[lx->pos]=='_') && i < TOK_IDENT_MAX-1)
            tok.sval[i++] = lx->src[lx->pos++];
        tok.sval[i] = 0;
        tok.slen = i;
        tok.type = lookup_kw(tok.sval);
        return tok;
    }

    /* two-character operators */
    lx->pos++;
    if (c == '+') {
        if (peek_char(lx)=='+') { lx->pos++; return make_tok(lx, TOK_PLUSPLUS); }
        return make_tok(lx, TOK_PLUS);
    }
    if (c == '-') {
        if (peek_char(lx)=='>') { lx->pos++; return make_tok(lx, TOK_ARROW); }
        if (peek_char(lx)=='-') { lx->pos++; return make_tok(lx, TOK_MINUSMINUS); }
        return make_tok(lx, TOK_MINUS);
    }
    if (c == '<') {
        if (peek_char(lx)=='<') { lx->pos++; return make_tok(lx, TOK_LSHIFT); }
        if (peek_char(lx)=='=') { lx->pos++; return make_tok(lx, TOK_LTE); }
        return make_tok(lx, TOK_LT);
    }
    if (c == '>') {
        if (peek_char(lx)=='>') { lx->pos++; return make_tok(lx, TOK_RSHIFT); }
        if (peek_char(lx)=='=') { lx->pos++; return make_tok(lx, TOK_GTE); }
        return make_tok(lx, TOK_GT);
    }
    if (c == '=') {
        if (peek_char(lx)=='=') { lx->pos++; return make_tok(lx, TOK_EQEQ); }
        return make_tok(lx, TOK_ASSIGN);
    }
    if (c == '!') {
        if (peek_char(lx)=='=') { lx->pos++; return make_tok(lx, TOK_NEQ); }
        return make_tok(lx, TOK_NOT);
    }
    if (c == '.') {
        if (peek_char(lx)=='.') { lx->pos++; return make_tok(lx, TOK_DOTDOT); }
        return make_tok(lx, TOK_DOT);
    }
    if (c == ':') return make_tok(lx, TOK_COLON);
    if (c == '*') return make_tok(lx, TOK_STAR);
    if (c == '/') return make_tok(lx, TOK_SLASH);
    if (c == '%') return make_tok(lx, TOK_PERCENT);
    if (c == '(') return make_tok(lx, TOK_LPAREN);
    if (c == ')') return make_tok(lx, TOK_RPAREN);
    if (c == '[') return make_tok(lx, TOK_LBRACK);
    if (c == ']') return make_tok(lx, TOK_RBRACK);
    if (c == '{') return make_tok(lx, TOK_LBRACE);
    if (c == '}') return make_tok(lx, TOK_RBRACE);
    if (c == ',') return make_tok(lx, TOK_COMMA);
    if (c == '&') return make_tok(lx, TOK_AMP);
    if (c == '|') return make_tok(lx, TOK_PIPE);
    if (c == '^') return make_tok(lx, TOK_CARET);
    if (c == '~') return make_tok(lx, TOK_TILDE);
    if (c == '@') return make_tok(lx, TOK_AT);

    /* unknown — skip */
    goto top;
}
