#ifndef REX_IR_H
#define REX_IR_H

#include <stdint.h>
#include <stddef.h>

/* ── IR record: exactly 32 bytes ─────────────────────────────────────────── */
typedef struct {
    uint8_t  opcode;   /* IR_* constant                                      */
    uint8_t  type;     /* TYPE_* constant                                     */
    uint16_t dst;      /* destination virtual register (0 = none)            */
    uint16_t src1;     /* first source virtual register (0 = unused)         */
    uint16_t src2;     /* second source virtual register (0 = unused)        */
    int64_t  imm;      /* primary immediate / var_idx / label_id / proto_idx */
    int64_t  aux;      /* secondary immediate / cond_code / arg_count        */
    uint32_t flags;    /* IR_FLAG_* bitmask                                  */
    uint32_t _pad;     /* reserved — must be zero                            */
} IRec;

/* ── Buffer limits ───────────────────────────────────────────────────────── */
#define IR_MAX          65536
#define VREG_MAX        65536
#define LABEL_MAX       4096
#define SPILL_MAX       256
#define PHYS_REG_COUNT  14

/* ── Type constants ──────────────────────────────────────────────────────── */
#define TYPE_VOID    0
#define TYPE_INT     1
#define TYPE_FLOAT   2
#define TYPE_BOOL    3
#define TYPE_COMPLEX 4
#define TYPE_STR     5
#define TYPE_SEQ     6
#define TYPE_DICT    7

/* ── Flags ───────────────────────────────────────────────────────────────── */
#define IR_FLAG_CONST    (1u << 0)  /* compile-time constant; value in imm    */
#define IR_FLAG_DEAD     (1u << 1)  /* no live readers — safe to NOP          */
#define IR_FLAG_SPILLED  (1u << 2)  /* dst vreg spilled to stack              */
#define IR_FLAG_LOOP_INV (1u << 3)  /* loop-invariant — candidate for LICM    */
#define IR_FLAG_HOISTED  (1u << 4)  /* already hoisted by LICM                */
#define IR_FLAG_STRENGTH (1u << 5)  /* strength-reduced                       */

/* ── Opcodes ─────────────────────────────────────────────────────────────── */

/* Category 0 — meta */
#define IR_NOP        0x00

/* Category 1 — load / store */
#define IR_LOAD_IMM   0x01   /* dst ← imm (integer)              */
#define IR_LOAD_FIMM  0x02   /* dst ← imm (float bits)           */
#define IR_LOAD_VAR   0x03   /* dst ← var[imm]                   */
#define IR_STORE_VAR  0x04   /* var[imm] ← src1                  */
#define IR_LOAD_STR   0x05   /* dst ← &inline_str; aux=len       */
#define IR_LOAD_BOOL  0x06   /* dst ← false/true/unknown         */
#define IR_RDRAND     0x07   /* dst ← rdrand                     */
#define IR_LEA_VAR    0x08   /* dst ← address of var[imm]        */
#define IR_MOV        0x09   /* dst ← src1  (copy)               */

/* Category 2 — integer arithmetic */
#define IR_ADD        0x11
#define IR_SUB        0x12
#define IR_MUL        0x13
#define IR_DIV        0x14
#define IR_MOD        0x15
#define IR_NEG        0x16
#define IR_ABS        0x17
#define IR_INC        0x18
#define IR_DEC        0x19
#define IR_ADD_IMM    0x1A   /* dst ← src1 + imm                 */
#define IR_SUB_IMM    0x1B   /* dst ← src1 - imm                 */
#define IR_MUL_IMM    0x1C   /* dst ← src1 * imm                 */
#define IR_SHL_IMM    0x1D   /* dst ← src1 << imm                */
#define IR_SHR_IMM    0x1E   /* dst ← src1 >> imm (arithmetic)   */

/* Category 3 — float arithmetic */
#define IR_FADD       0x21
#define IR_FSUB       0x22
#define IR_FMUL       0x23
#define IR_FDIV       0x24
#define IR_FNEG       0x25
#define IR_F2I        0x26
#define IR_I2F        0x27

/* Category 4 — bitwise */
#define IR_BAND       0x31
#define IR_BOR        0x32
#define IR_BXOR       0x33
#define IR_BNOT       0x34
#define IR_SHL        0x35
#define IR_SHR        0x36

/* Category 5 — compare / bool */
#define IR_CMP        0x41   /* aux = cond_code: 0==,1!=,2<,3>,4<=,5>= */
#define IR_BOOL_AND   0x42
#define IR_BOOL_OR    0x43
#define IR_BOOL_NOT   0x44

/* Category 6 — control flow */
#define IR_LABEL      0x51   /* define jump target; imm=label_id  */
#define IR_JMP        0x52   /* unconditional; imm=label_id        */
#define IR_JCC        0x53   /* jump if src1==0; imm=label_id      */
#define IR_CALL       0x54   /* call proto imm; aux=arg_count      */
#define IR_RET        0x55   /* return src1                        */
#define IR_RET_VOID   0x56
#define IR_LOOP_TOP   0x57   /* loop back-edge target              */
#define IR_SKIP       0x58   /* break N levels; imm=N              */
#define IR_STOP       0x59   /* break innermost loop               */
#define IR_ARG_PUSH   0x5A   /* push src1 as next call arg         */
#define IR_CALL_RET   0x5B   /* dst ← return value of last call    */

/* Category 7 — output / runtime */
#define IR_OUT_INT    0x61
#define IR_OUT_FLOAT  0x62
#define IR_OUT_BOOL   0x63
#define IR_OUT_STR    0x64
#define IR_OUT_NEWLN  0x65
#define IR_ERR        0x66
#define IR_HALT       0x67
#define IR_SYSCALL_EXIT 0x68

/* Category 8 — collections */
#define IR_SEQ_ALLOC  0x71
#define IR_SEQ_PUSH   0x72
#define IR_SEQ_POP    0x73
#define IR_SEQ_LEN    0x74
#define IR_SEQ_CAP    0x75
#define IR_DICT_NEW   0x76
#define IR_DICT_SET   0x77
#define IR_DICT_GET   0x78
#define IR_SEQ_IDX    0x79   /* dst ← seq[src2]; imm=var_idx      */
#define IR_SEQ_SET    0x7A   /* seq[src2] ← src1; imm=var_idx     */

/* Category 9 — misc */
#define IR_SWAP       0x81   /* swap var[imm] and var[aux]         */
#define IR_TYPEOF     0x82
#define IR_CLOCK      0x83   /* dst ← clock_ms()                  */
#define IR_FLIP       0x84   /* var[imm] = !var[imm]               */
#define IR_PROT_ENTRY 0xF0   /* marks start of protocol body       */
#define IR_PROT_EXIT  0xF1   /* marks end of protocol body         */
#define IR_RAW_BYTES  0xFF   /* imm=offset into raw_pool; aux=len  */

/* ── Condition codes (aux field of IR_CMP) ───────────────────────────────── */
#define CC_EQ  0
#define CC_NEQ 1
#define CC_LT  2
#define CC_GT  3
#define CC_LTE 4
#define CC_GTE 5

/* ── Physical register IDs ───────────────────────────────────────────────── */
#define PR_RAX  0
#define PR_RBX  1
#define PR_RCX  2
#define PR_RDX  3
#define PR_RSI  4
#define PR_RDI  5
#define PR_R8   6
#define PR_R9   7
#define PR_R10  8
#define PR_R11  9
#define PR_R12  10
#define PR_R13  11
#define PR_R14  12
#define PR_R15  13
#define PR_SPILL 0xFF   /* vreg was spilled to stack slot         */
#define PR_NONE  0xFE   /* unallocated                            */

/* ── IR pass context ─────────────────────────────────────────────────────── */
typedef struct {
    IRec    *buf;          /* IR record array                       */
    int      count;        /* number of records                     */
    int      cap;          /* allocated capacity                    */

    /* virtual register tracking */
    uint16_t vreg_counter; /* next vreg to allocate                 */

    /* label tracking */
    uint16_t label_counter;

    /* register allocator output */
    uint8_t  phys_map[VREG_MAX]; /* vreg → physical reg ID         */
    int32_t  spill_slot[VREG_MAX];/* vreg → stack offset (if spilled)*/
    int      frame_size;   /* total frame bytes needed              */

    /* string pool (inline string literals) */
    char    *str_pool;
    int      str_pool_len;
    int      str_pool_cap;

    /* raw bytes pool (for unsupported constructs — passthrough)    */
    uint8_t *raw_pool;
    int      raw_pool_len;
    int      raw_pool_cap;

    /* live range tables (allocated by regalloc pass) */
    int32_t *lr_start;     /* [vreg] → first IR index where defined  */
    int32_t *lr_end;       /* [vreg] → last IR index where used      */

    /* constant table (allocated by const fold pass) */
    int64_t *const_val;    /* [vreg] → known constant value          */
    uint8_t *const_known;  /* [vreg] → 1 if constant, 0 if unknown   */

    /* loop region stack for LICM */
    int      loop_top_idx[64];
    int      loop_depth;

    /* error flag */
    int      had_error;
} IRCtx;

/* ── API ─────────────────────────────────────────────────────────────────── */
IRCtx  *ir_ctx_new(void);
void    ir_ctx_free(IRCtx *ctx);
uint16_t ir_alloc_vreg(IRCtx *ctx);
uint16_t ir_alloc_label(IRCtx *ctx);
IRec   *ir_emit(IRCtx *ctx, uint8_t op, uint8_t type,
                uint16_t dst, uint16_t s1, uint16_t s2,
                int64_t imm, int64_t aux, uint32_t flags);
int     ir_add_str(IRCtx *ctx, const char *s, int len);
int     ir_add_raw(IRCtx *ctx, const uint8_t *bytes, int len);

/* pass runner — returns 0 on success */
int     ir_run_pass1_cfp(IRCtx *ctx);   /* Constant Fold & Propagate  */
int     ir_run_pass2_dce(IRCtx *ctx);   /* Dead Code Elimination       */
int     ir_run_pass3_dse(IRCtx *ctx);   /* Dead Store Elimination      */
int     ir_run_pass4_lsc(IRCtx *ctx);   /* Load-Store Coalescing       */
int     ir_run_pass5_licm(IRCtx *ctx);  /* Loop Invariant Code Motion  */
int     ir_run_pass6_sr(IRCtx *ctx);    /* Strength Reduction          */
int     ir_run_pass7_ra(IRCtx *ctx);    /* Linear Scan Reg Alloc       */
int     ir_run_pass8_ph(IRCtx *ctx);    /* Peephole Cleanup            */

/* emit x86-64 machine bytes from optimised IR; returns byte count */
int     ir_emit_x86(IRCtx *ctx,
                    uint8_t *out, int out_cap,
                    uint64_t load_base,
                    uint64_t var_base,
                    uint64_t runtime_base);

#endif /* REX_IR_H */
