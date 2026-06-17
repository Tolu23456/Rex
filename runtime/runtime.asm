default rel
%include "include/rex_defs.inc"
global rt_pri_blob
global rt_prs_blob
global rt_prb_blob
global rt_prf_blob
global rt_prc_blob
global rt_sip_blob
global rt_alc_blob
global rt_prq_blob
global rt_str_cat_blob
global rt_str_eq_blob
global rt_str_find_blob
global rt_str_len_blob
global rt_str_upper_blob
global rt_str_lower_blob
global rt_str_trim_blob
global rt_str_rev_blob
global rt_int2str_blob
global rt_float2str_blob
global rt_str_split_blob
global rt_str_join_blob
global rt_str_starts_blob
global rt_str_ends_blob
global rt_str_contains_blob
global rt_str_slice_blob
global rt_str_replace_blob
global rt_str_count_blob
global rt_str_repeat_blob
global rt_math_sqrt_blob
global rt_math_floor_blob
global rt_math_ceil_blob
global rt_math_abs_f_blob
global rt_math_sin_blob
global rt_math_cos_blob
global rt_math_exp_blob
global rt_math_log_blob
global rt_math_pow_blob
global rt_math_min_blob
global rt_math_max_blob
global rt_bounds_err_blob
global rt_overflow_err_blob
global rt_null_err_blob
global rt_seq_sort_blob
global rt_seq_sum_blob
global rt_seq_min_blob
global rt_seq_max_blob
global rt_seq_contains_blob
global rt_seq_reverse_blob
global rt_heap_alloc_blob
global rt_heap_free_blob
global rt_static_alloc_blob

section .data
rt_pri_blob:
    incbin "runtime/runtime.bin", 0, RT_PRI_SIZE
rt_prs_blob:
    incbin "runtime/runtime.bin", RT_PRI_SIZE, RT_PRS_SIZE
rt_prb_blob:
    incbin "runtime/runtime.bin", RT_PRI_SIZE+RT_PRS_SIZE, RT_PRB_SIZE
rt_prf_blob:
    incbin "runtime/runtime.bin", RT_PRI_SIZE+RT_PRS_SIZE+RT_PRB_SIZE, RT_PRF_SIZE
rt_prc_blob:
    incbin "runtime/runtime.bin", RT_PRI_SIZE+RT_PRS_SIZE+RT_PRB_SIZE+RT_PRF_SIZE, RT_PRC_SIZE
rt_sip_blob:
    incbin "runtime/runtime.bin", RT_PRI_SIZE+RT_PRS_SIZE+RT_PRB_SIZE+RT_PRF_SIZE+RT_PRC_SIZE, RT_SIP_SIZE
rt_alc_blob:
    incbin "runtime/runtime.bin", RT_PRI_SIZE+RT_PRS_SIZE+RT_PRB_SIZE+RT_PRF_SIZE+RT_PRC_SIZE+RT_SIP_SIZE, RT_ALC_SIZE
rt_prq_blob:
    incbin "runtime/runtime.bin", RT_PRI_SIZE+RT_PRS_SIZE+RT_PRB_SIZE+RT_PRF_SIZE+RT_PRC_SIZE+RT_SIP_SIZE+RT_ALC_SIZE, RT_PRQ_SIZE
rt_str_cat_blob:
    incbin "runtime/runtime.bin", RT_STR_CAT_OFFSET-125, RT_STR_CAT_SIZE
rt_str_eq_blob:
    incbin "runtime/runtime.bin", RT_STR_EQ_OFFSET-125, RT_STR_EQ_SIZE
rt_str_find_blob:
    incbin "runtime/runtime.bin", RT_STR_FIND_OFFSET-125, RT_STR_FIND_SIZE
rt_str_len_blob:
    incbin "runtime/runtime.bin", RT_STR_LEN_OFFSET-125, RT_STR_LEN_SIZE
rt_str_upper_blob:
    incbin "runtime/runtime.bin", RT_STR_UPPER_OFFSET-125, RT_STR_UPPER_SIZE
rt_str_lower_blob:
    incbin "runtime/runtime.bin", RT_STR_LOWER_OFFSET-125, RT_STR_LOWER_SIZE
rt_str_trim_blob:
    incbin "runtime/runtime.bin", RT_STR_TRIM_OFFSET-125, RT_STR_TRIM_SIZE
rt_str_rev_blob:
    incbin "runtime/runtime.bin", RT_STR_REV_OFFSET-125, RT_STR_REV_SIZE
rt_int2str_blob:
    incbin "runtime/runtime.bin", RT_INT2STR_OFFSET-125, RT_INT2STR_SIZE
rt_float2str_blob:
    incbin "runtime/runtime.bin", RT_FLOAT2STR_OFFSET-125, RT_FLOAT2STR_SIZE
rt_str_split_blob:
    incbin "runtime/runtime.bin", RT_STR_SPLIT_OFFSET-125, RT_STR_SPLIT_SIZE
rt_str_join_blob:
    incbin "runtime/runtime.bin", RT_STR_JOIN_OFFSET-125, RT_STR_JOIN_SIZE
rt_str_starts_blob:
    incbin "runtime/runtime.bin", RT_STR_STARTS_OFFSET-125, RT_STR_STARTS_SIZE
rt_str_ends_blob:
    incbin "runtime/runtime.bin", RT_STR_ENDS_OFFSET-125, RT_STR_ENDS_SIZE
rt_str_contains_blob:
    incbin "runtime/runtime.bin", RT_STR_CONTAINS_OFFSET-125, RT_STR_CONTAINS_SIZE
rt_str_slice_blob:
    incbin "runtime/runtime.bin", RT_STR_SLICE_OFFSET-125, RT_STR_SLICE_SIZE
rt_str_replace_blob:
    incbin "runtime/runtime.bin", RT_STR_REPLACE_OFFSET-125, RT_STR_REPLACE_SIZE
rt_str_count_blob:
    incbin "runtime/runtime.bin", RT_STR_COUNT_OFFSET-125, RT_STR_COUNT_SIZE
rt_str_repeat_blob:
    incbin "runtime/runtime.bin", RT_STR_REPEAT_OFFSET-125, RT_STR_REPEAT_SIZE
rt_math_sqrt_blob:
    incbin "runtime/runtime.bin", RT_MATH_SQRT_OFFSET-125, RT_MATH_SQRT_SIZE
rt_math_floor_blob:
    incbin "runtime/runtime.bin", RT_MATH_FLOOR_OFFSET-125, RT_MATH_FLOOR_SIZE
rt_math_ceil_blob:
    incbin "runtime/runtime.bin", RT_MATH_CEIL_OFFSET-125, RT_MATH_CEIL_SIZE
rt_math_abs_f_blob:
    incbin "runtime/runtime.bin", RT_MATH_ABS_F_OFFSET-125, RT_MATH_ABS_F_SIZE
rt_math_sin_blob:
    incbin "runtime/runtime.bin", RT_MATH_SIN_OFFSET-125, RT_MATH_SIN_SIZE
rt_math_cos_blob:
    incbin "runtime/runtime.bin", RT_MATH_COS_OFFSET-125, RT_MATH_COS_SIZE
rt_math_exp_blob:
    incbin "runtime/runtime.bin", RT_MATH_EXP_OFFSET-125, RT_MATH_EXP_SIZE
rt_math_log_blob:
    incbin "runtime/runtime.bin", RT_MATH_LOG_OFFSET-125, RT_MATH_LOG_SIZE
rt_math_pow_blob:
    incbin "runtime/runtime.bin", RT_MATH_POW_OFFSET-125, RT_MATH_POW_SIZE
rt_math_min_blob:
    incbin "runtime/runtime.bin", RT_MATH_MIN_OFFSET-125, RT_MATH_MIN_SIZE
rt_math_max_blob:
    incbin "runtime/runtime.bin", RT_MATH_MAX_OFFSET-125, RT_MATH_MAX_SIZE
rt_bounds_err_blob:
    incbin "runtime/runtime.bin", RT_BOUNDS_ERR_OFFSET-125, RT_BOUNDS_ERR_SIZE
rt_overflow_err_blob:
    incbin "runtime/runtime.bin", RT_OVERFLOW_ERR_OFFSET-125, RT_OVERFLOW_ERR_SIZE
rt_null_err_blob:
    incbin "runtime/runtime.bin", RT_NULL_ERR_OFFSET-125, RT_NULL_ERR_SIZE
rt_seq_sort_blob:
    incbin "runtime/runtime.bin", RT_SEQ_SORT_OFFSET-125, RT_SEQ_SORT_SIZE
rt_seq_sum_blob:
    incbin "runtime/runtime.bin", RT_SEQ_SUM_OFFSET-125, RT_SEQ_SUM_SIZE
rt_seq_min_blob:
    incbin "runtime/runtime.bin", RT_SEQ_MIN_OFFSET-125, RT_SEQ_MIN_SIZE
rt_seq_max_blob:
    incbin "runtime/runtime.bin", RT_SEQ_MAX_OFFSET-125, RT_SEQ_MAX_SIZE
rt_seq_contains_blob:
    incbin "runtime/runtime.bin", RT_SEQ_CONTAINS_OFFSET-125, RT_SEQ_CONTAINS_SIZE
rt_seq_reverse_blob:
    incbin "runtime/runtime.bin", RT_SEQ_REVERSE_OFFSET-125, RT_SEQ_REVERSE_SIZE
rt_heap_alloc_blob:
    incbin "runtime/runtime.bin", RT_HEAP_ALLOC_OFFSET-125, RT_HEAP_ALLOC_SIZE
rt_heap_free_blob:
    incbin "runtime/runtime.bin", RT_HEAP_FREE_OFFSET-125, RT_HEAP_FREE_SIZE
rt_static_alloc_blob:
    incbin "runtime/runtime.bin", RT_STATIC_ALLOC_OFFSET-125, RT_STATIC_ALLOC_SIZE
