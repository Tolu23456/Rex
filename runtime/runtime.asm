; ============================================================
; runtime/runtime.asm — Rex runtime blob data (incbin wrappers)
; Assembled as ELF64 object; blobs included as binary data.
; ============================================================
bits 64

global rt_pri_data, rt_prs_data, rt_prb_data, rt_prf_data
global rt_prc_data, rt_sip_data, rt_alc_data, rt_prq_data

section .data

rt_pri_data:
    incbin "runtime/rt_pri.bin"
rt_pri_end:
global rt_pri_size
rt_pri_size: dq rt_pri_end - rt_pri_data

rt_prs_data:
    incbin "runtime/rt_prs.bin"
rt_prs_end:
global rt_prs_size
rt_prs_size: dq rt_prs_end - rt_prs_data

rt_prb_data:
    incbin "runtime/rt_prb.bin"
rt_prb_end:
global rt_prb_size
rt_prb_size: dq rt_prb_end - rt_prb_data

rt_prf_data:
    incbin "runtime/rt_prf.bin"
rt_prf_end:
global rt_prf_size
rt_prf_size: dq rt_prf_end - rt_prf_data

rt_prc_data:
    incbin "runtime/rt_prc.bin"
rt_prc_end:
global rt_prc_size
rt_prc_size: dq rt_prc_end - rt_prc_data

rt_sip_data:
    incbin "runtime/rt_sip.bin"
rt_sip_end:
global rt_sip_size
rt_sip_size: dq rt_sip_end - rt_sip_data

rt_alc_data:
    incbin "runtime/rt_alc.bin"
rt_alc_end:
global rt_alc_size
rt_alc_size: dq rt_alc_end - rt_alc_data

rt_prq_data:
    incbin "runtime/rt_prq.bin"
rt_prq_end:
global rt_prq_size
rt_prq_size: dq rt_prq_end - rt_prq_data
