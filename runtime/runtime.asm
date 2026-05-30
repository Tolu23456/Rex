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
