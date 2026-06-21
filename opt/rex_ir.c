#include "rex_ir.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

IRCtx *ir_ctx_new(void) {
    IRCtx *ctx = calloc(1, sizeof(IRCtx));
    if (!ctx) return NULL;
    ctx->cap = 4096;
    ctx->buf = calloc(ctx->cap, sizeof(IRec));
    ctx->str_pool_cap = 65536;
    ctx->str_pool = malloc(ctx->str_pool_cap);
    ctx->raw_pool_cap = 65536;
    ctx->raw_pool = malloc(ctx->raw_pool_cap);
    ctx->const_val   = calloc(VREG_MAX, sizeof(int64_t));
    ctx->const_known = calloc(VREG_MAX, sizeof(uint8_t));
    ctx->lr_start    = calloc(VREG_MAX, sizeof(int32_t));
    ctx->lr_end      = calloc(VREG_MAX, sizeof(int32_t));
    ctx->vreg_counter = 1; /* 0 = "no register" sentinel */
    ctx->label_counter = 1;
    /* init live ranges to -1 */
    for (int i = 0; i < VREG_MAX; i++) {
        ctx->lr_start[i] = -1;
        ctx->lr_end[i]   = -1;
    }
    /* phys_map: all unallocated */
    memset(ctx->phys_map, PR_NONE, sizeof(ctx->phys_map));
    memset(ctx->spill_slot, 0xFF, sizeof(ctx->spill_slot));
    return ctx;
}

void ir_ctx_free(IRCtx *ctx) {
    if (!ctx) return;
    free(ctx->buf);
    free(ctx->str_pool);
    free(ctx->raw_pool);
    free(ctx->const_val);
    free(ctx->const_known);
    free(ctx->lr_start);
    free(ctx->lr_end);
    free(ctx);
}

uint16_t ir_alloc_vreg(IRCtx *ctx) {
    return ctx->vreg_counter++;
}

uint16_t ir_alloc_label(IRCtx *ctx) {
    return ctx->label_counter++;
}

IRec *ir_emit(IRCtx *ctx, uint8_t op, uint8_t type,
              uint16_t dst, uint16_t s1, uint16_t s2,
              int64_t imm, int64_t aux, uint32_t flags) {
    if (ctx->count >= ctx->cap) {
        ctx->cap *= 2;
        ctx->buf = realloc(ctx->buf, ctx->cap * sizeof(IRec));
        if (!ctx->buf) {
            fprintf(stderr, "rex_opt: IR buffer OOM\n");
            ctx->had_error = 1;
            return NULL;
        }
    }
    IRec *r = &ctx->buf[ctx->count++];
    r->opcode = op;
    r->type   = type;
    r->dst    = dst;
    r->src1   = s1;
    r->src2   = s2;
    r->imm    = imm;
    r->aux    = aux;
    r->flags  = flags;
    r->_pad   = 0;
    return r;
}

int ir_add_str(IRCtx *ctx, const char *s, int len) {
    int off = ctx->str_pool_len;
    if (off + len + 1 > ctx->str_pool_cap) {
        ctx->str_pool_cap *= 2;
        ctx->str_pool = realloc(ctx->str_pool, ctx->str_pool_cap);
    }
    memcpy(ctx->str_pool + off, s, len);
    ctx->str_pool[off + len] = 0;
    ctx->str_pool_len += len + 1;
    return off;
}

int ir_add_raw(IRCtx *ctx, const uint8_t *bytes, int len) {
    int off = ctx->raw_pool_len;
    if (off + len > ctx->raw_pool_cap) {
        ctx->raw_pool_cap *= 2;
        ctx->raw_pool = realloc(ctx->raw_pool, ctx->raw_pool_cap);
    }
    memcpy(ctx->raw_pool + off, bytes, len);
    ctx->raw_pool_len += len;
    return off;
}
