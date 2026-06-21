#ifndef REX_PARSE_H
#define REX_PARSE_H

#include "rex_ir.h"
#include "rex_lex.h"

/* ── Symbol table entry ──────────────────────────────────────────────────── */
#define SYM_MAX 256

typedef struct {
    char     name[TOK_IDENT_MAX];
    int      var_idx;   /* index into var storage */
    uint8_t  type;      /* TYPE_* */
    uint8_t  is_mut;    /* 1 if declared mutable (:x = ...) */
    uint8_t  is_param;
    uint8_t  scope;     /* scope depth */
} Sym;

/* ── Protocol table entry ────────────────────────────────────────────────── */
#define PROTO_MAX 128

typedef struct {
    char     name[TOK_IDENT_MAX];
    int      proto_idx;
    uint8_t  ret_type;
    uint8_t  param_count;
    uint8_t  param_types[6];
    int      param_var_idx[6];
    int      ir_entry_idx; /* index of IR_PROT_ENTRY record */
    uint16_t entry_label;  /* label_id for prot entry */
    int      is_memo;
    int      is_hot;
    int      is_inline;
} Proto;

/* ── Parse context ───────────────────────────────────────────────────────── */
typedef struct {
    Lexer   *lx;
    IRCtx   *ir;

    /* symbol table */
    Sym      syms[SYM_MAX];
    int      sym_count;
    int      var_count;   /* total variables allocated */
    int      scope;

    /* protocol table */
    Proto    protos[PROTO_MAX];
    int      proto_count;
    int      cur_proto;   /* -1 if at top level */

    /* forward references for protocol calls */
    char     fwd_name[64][TOK_IDENT_MAX];
    int      fwd_ir_idx[64];  /* IR_CALL record index to patch */
    int      fwd_count;

    /* loop stack for stop/skip */
    uint16_t loop_exit_labels[64];
    uint16_t loop_cont_labels[64];
    int      loop_depth;

    /* pending call args */
    uint16_t call_args[16];
    int      call_arg_count;

    int      had_error;
    int      error_count;
} Parser;

Parser *parser_new(Lexer *lx, IRCtx *ir);
void    parser_free(Parser *p);
int     parser_run(Parser *p);  /* returns 0 on success */

#endif /* REX_PARSE_H */
