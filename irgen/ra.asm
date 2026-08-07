; Rex Graph-Colouring Register Allocator
; written in x86-64 NASM assembly
;
; Algorithm: Chaitin-Briggs optimistic colouring with a low-degree worklist,
;            copy-hint biased colouring, and ratio-based spill cost.
;
; Six phases
; ----------
;   1. Liveness    — single IR scan: gc_def[v], gc_last_use[v], gc_use_count[v].
;                    IR_NOP records are skipped entirely so eliminated instructions
;                    do not create phantom live ranges.
;                    For arithmetic ops (dst = src1 op src2) the pair (dst, src1)
;                    is also recorded as a copy-coalescing hint in gc_copy_hint[].
;   2. Build       — pairwise range-overlap interference graph stored as a
;                    symmetric 512×512-bit bitmap (32 KiB).
;   2.5 Worklist   — seed the simplification worklist with all defined vregs
;                    whose current degree < NUM_PHYS_REGS.
;   3. Simplify    — while nodes remain:
;                      • If worklist non-empty: pop a low-degree node, push to
;                        the colouring stack, mark removed, and call
;                        gc_dn_update() which decrements each neighbour's degree
;                        with a fast BSF-based row scan and re-seeds the worklist
;                        when a neighbour drops below the threshold.
;                      • If worklist empty (all degrees >= k): select the node
;                        with the minimum use_count/(degree+1) ratio as a
;                        potential spill (cross-multiplication avoids division)
;                        and push it to the colouring stack anyway (optimistic).
;   4. Colour      — pop the colouring stack; for each vreg build a used-colour
;                    bitmask by scanning its interference row with BSF, then:
;                      a. If gc_copy_hint[v] names a coloured non-spilled vreg
;                         whose colour is free, assign that colour immediately
;                         (biased colouring — eliminates the src1→dst copy).
;                      b. Otherwise assign the smallest free colour (0-5)
;                         or mark as spilled.
;   5. Map         — populate vreg_phys[] and vreg_offset[]; align spill frame.
;
; Physical register map (NUM_PHYS_REGS = 6)
; The codegen emits phys n as r8+n (REX.W|R|B prefix with n in the register
; field), so the effective mapping is:
;   colour 0 → r8     colour 1 → r9     colour 2 → r10
;   colour 3 → r11    colour 4 → r12    colour 5 → r13
;   (spill temps: phys 6 → r14, phys 7 → r15)
; Colours 0-3 (r8-r11) are preserved by codegen around runtime calls; colours
; 4-5 (r12-r13) are ABI callee-saved.
;
; Spill heuristic
;   Classic Chaitin: minimise use_count / (degree + 1).
;   Implemented without division via cross-multiplication:
;     candidate c is better than current best b iff
;       use_count[c] * (degree[b]+1) < use_count[b] * (degree[c]+1)
;   Max product: 2*IR_MAX_RECORDS * GRAPHCOL_VMAX = 2048 * 512 = 1 048 576
;   which fits comfortably in a 32-bit signed register.
;
; Interface (unchanged from previous version)
;   vreg_phys[v]     = colour (0-5) or 255 (spilled)
;   vreg_offset[v]   = RBP-relative spill slot offset (< 0, spilled only)
;   stack_frame_size = bytes reserved on stack (16-byte aligned)

%include "include/rex_defs.inc"
%include "include/rex_ir.inc"

GRAPHCOL_VMAX   equ 1024        ; max vregs tracked (must be power of 2)
GRAPHCOL_BPR    equ 128         ; bytes per row = GRAPHCOL_VMAX / 8
GRAPHCOL_QPR    equ 16          ; qwords per row = GRAPHCOL_BPR / 8
NUM_PHYS_REGS   equ 6
UNSET_IDX       equ 0xFFFFFFFF  ; sentinel: vreg never defined
COLOR_NONE      equ 0xFE        ; not yet coloured
COLOR_SPILL     equ 0xFF        ; spilled to stack

section .bss

    ; ---- exported interface ----
    global vreg_phys
    global vreg_offset
    global stack_frame_size

    vreg_phys           resb VREG_MAX               ; vreg → colour (255=spilled)
    vreg_offset         resd VREG_MAX               ; vreg → RBP-offset (spilled)
    stack_frame_size    resd 1

    ; ---- liveness tables ----
    gc_def              resd GRAPHCOL_VMAX           ; first-definition instruction index
    gc_last_use         resd GRAPHCOL_VMAX           ; last src-read instruction index
    gc_use_count        resd GRAPHCOL_VMAX           ; total src appearances (spill cost)

    ; ---- copy-coalescing hints (Phase 1, used in Phase 4 biased colouring) ----
    gc_copy_hint        resw GRAPHCOL_VMAX           ; dst vreg → src1 vreg (0 = none)

    ; ---- force-spill flags (vregs live across an IR_CALL) ----
    gc_force_spill      resb GRAPHCOL_VMAX           ; 1 = must be spilled (callee clobbers regs)

    ; ---- force-callee flags (loop-promoted vregs) ----
    ; 1 = only assign callee-saved colours (2-5 = r12-r15) so the cached
    ; loop values survive runtime helper calls (codegen only preserves
    ; r8-r11 around calls; the runtime helpers preserve r12-r15).
    global gc_force_callee
    gc_force_callee     resb GRAPHCOL_VMAX

    ; ---- interference graph (symmetric bitmap) ----
    gc_interf           resb GRAPHCOL_VMAX * GRAPHCOL_BPR   ; 32 KiB

    ; ---- colouring state ----
    gc_degree           resd GRAPHCOL_VMAX           ; current degree
    gc_color            resb GRAPHCOL_VMAX           ; assigned colour
    gc_removed          resb GRAPHCOL_VMAX           ; 1 = removed from graph
    gc_in_wl            resb GRAPHCOL_VMAX           ; 1 = currently in worklist

    ; ---- colouring stack ----
    gc_stack            resw GRAPHCOL_VMAX           ; elimination-order vreg IDs
    gc_stack_top        resd 1

    ; ---- simplification worklist (LIFO) ----
    gc_worklist         resw GRAPHCOL_VMAX           ; low-degree vreg IDs
    gc_wl_len           resd 1

    ; ---- bookkeeping ----
    gc_max_vreg         resd 1                       ; = min(vreg_counter-1, GRAPHCOL_VMAX-1)
    gc_remaining        resd 1                       ; active (non-removed) defined-vreg count

    ; ---- label index map (back-edge live-range extension) ----
    ; gc_label_idx[label_id] = IR index of its LABEL record (0xFFFF = none)
    gc_label_idx        resw IR_MAX_RECORDS

section .text
    global allocate_registers

    extern ir_count
    extern ir_buffer
    extern vreg_counter

; ============================================================
;  allocate_registers — public entry point
; ============================================================
allocate_registers:
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; ----------------------------------------------------------
    ; Phase 0: zero / initialise all tables
    ; ----------------------------------------------------------

    ; vreg_phys ← 255 (all spilled until proved otherwise)
    mov rcx, VREG_MAX
    lea rdi, [vreg_phys]
    mov al, COLOR_SPILL
    rep stosb

    ; vreg_offset ← 0
    mov rcx, VREG_MAX
    lea rdi, [vreg_offset]
    xor eax, eax
    rep stosd

    mov dword [stack_frame_size], 0
    mov dword [gc_stack_top],  0
    mov dword [gc_wl_len],     0
    mov dword [gc_remaining],  0

    ; gc_def ← UNSET_IDX
    mov ecx, GRAPHCOL_VMAX
    lea rdi, [gc_def]
    mov eax, UNSET_IDX
    rep stosd

    ; gc_last_use ← 0
    mov ecx, GRAPHCOL_VMAX
    lea rdi, [gc_last_use]
    xor eax, eax
    rep stosd

    ; gc_use_count ← 0
    mov ecx, GRAPHCOL_VMAX
    lea rdi, [gc_use_count]
    xor eax, eax
    rep stosd

    ; gc_copy_hint ← 0  (no hints yet)
    mov ecx, GRAPHCOL_VMAX
    lea rdi, [gc_copy_hint]
    xor eax, eax
    rep stosw

    ; gc_force_spill ← 0
    mov ecx, GRAPHCOL_VMAX
    lea rdi, [gc_force_spill]
    xor eax, eax
    rep stosb

    ; gc_interf ← 0  (32 KiB; use qwords for speed)
    mov ecx, GRAPHCOL_VMAX * GRAPHCOL_BPR / 8
    lea rdi, [gc_interf]
    xor eax, eax
    rep stosq

    ; gc_degree ← 0
    mov ecx, GRAPHCOL_VMAX
    lea rdi, [gc_degree]
    xor eax, eax
    rep stosd

    ; gc_color ← COLOR_NONE (0xFE)
    mov ecx, GRAPHCOL_VMAX
    lea rdi, [gc_color]
    mov al, COLOR_NONE
    rep stosb

    ; gc_removed, gc_in_wl ← 0
    mov ecx, GRAPHCOL_VMAX
    lea rdi, [gc_removed]
    xor eax, eax
    rep stosb

    mov ecx, GRAPHCOL_VMAX
    lea rdi, [gc_in_wl]
    xor eax, eax
    rep stosb

    ; Compute gc_max_vreg = min(vreg_counter - 1, GRAPHCOL_VMAX - 1)
    mov eax, [vreg_counter]
    dec eax
    cmp eax, GRAPHCOL_VMAX - 1
    jbe .set_max_vreg
    ; Warn: vreg count exceeds graph capacity — excess vregs will be spilled
    mov eax, GRAPHCOL_VMAX - 1
.set_max_vreg:
    mov [gc_max_vreg], eax

    test eax, eax
    jz .done_alloc          ; no vregs at all

    ; ----------------------------------------------------------
    ; Phase 1: liveness + use-count + copy-hint scan
    ; ----------------------------------------------------------
    ; For each non-NOP IR record i:
    ;   if dst  ≠ 0: record first definition
    ;   if src1 ≠ 0: update last-use, increment use_count
    ;   if src2 ≠ 0: update last-use, increment use_count
    ;   if opcode is arithmetic (IR_ADD..IR_XOR or IR_BOOL_AND/OR/NOT):
    ;     record gc_copy_hint[dst] = src1  (biased colouring hint)
    ;
    ; NOP records are skipped so eliminated instructions don't
    ; extend live ranges or inflate use counts.

    mov r12d, [ir_count]
    test r12d, r12d
    jz .build_start         ; no IR → skip to building

    xor ebx, ebx            ; i = 0
.phase1_loop:
    cmp ebx, r12d
    je .phase1_done

    imul eax, ebx, IR_RECORD_SIZE
    lea r13, [ir_buffer + rax]

    movzx eax, byte [r13]           ; opcode
    cmp al, IR_NOP
    je .phase1_next                 ; skip NOP entirely

    ; dst
    movzx eax, word [r13 + 2]      ; dst vreg
    test ax, ax
    jz .p1_src1
    cmp eax, GRAPHCOL_VMAX
    jae .p1_src1
    cmp dword [gc_def + rax * 4], UNSET_IDX
    jne .p1_src1
    mov [gc_def + rax * 4], ebx    ; record first definition
    inc dword [gc_remaining]        ; one more active vreg

.p1_src1:
    movzx eax, word [r13 + 4]      ; src1
    test ax, ax
    jz .p1_src2
    cmp eax, GRAPHCOL_VMAX
    jae .p1_src2
    mov [gc_last_use + rax * 4], ebx
    inc dword [gc_use_count + rax * 4]

.p1_src2:
    ; IR_CALL uses src2 as its SECOND DEFINITION (hi return vreg),
    ; not as a source operand — record the def instead of a use.
    movzx eax, byte [r13]          ; opcode
    cmp al, IR_CALL
    je .p1_call_src2_def

    movzx eax, word [r13 + 6]      ; src2
    test ax, ax
    jz .p1_aux
    cmp eax, GRAPHCOL_VMAX
    jae .p1_aux
    mov [gc_last_use + rax * 4], ebx
    inc dword [gc_use_count + rax * 4]

.p1_call_src2_def:
    movzx eax, word [r13 + 6]      ; src2 (hi return vreg)
    test ax, ax
    jz .p1_aux
    cmp eax, GRAPHCOL_VMAX
    jae .p1_aux
    cmp dword [gc_def + rax * 4], UNSET_IDX
    jne .p1_aux
    mov [gc_def + rax * 4], ebx    ; record first definition
    inc dword [gc_remaining]        ; one more active vreg

.p1_aux:
    ; Track aux vreg for instructions that use aux as a vreg operand
    movzx eax, byte [r13]          ; opcode
    cmp al, IR_SEQ_STORE
    je .p1_aux_track
    cmp al, IR_SEQ_INSERT
    je .p1_aux_track
    cmp al, IR_DICT_STORE
    je .p1_aux_track
    jmp .p1_hint
.p1_aux_track:
    movzx eax, word [r13 + 16]     ; aux vreg (lower 2 bytes of 8-byte field)
    test ax, ax
    jz .p1_hint
    cmp eax, GRAPHCOL_VMAX
    jae .p1_hint
    mov [gc_last_use + rax * 4], ebx
    inc dword [gc_use_count + rax * 4]

.p1_hint:
    ; For ops with dst = f(src1), record copy-coalescing hint: gc_copy_hint[dst] = src1
    ; Biased colouring in Phase 4 will try to assign dst the same colour as src1,
    ; which eliminates the "mov dst_reg, src1_reg" copy emitted by codegen.
    movzx eax, byte [r13]          ; opcode
    ; Binary arithmetic
    cmp al, IR_ADD
    je .p1_do_hint
    cmp al, IR_SUB
    je .p1_do_hint
    cmp al, IR_MUL
    je .p1_do_hint
    cmp al, IR_DIV
    je .p1_do_hint
    cmp al, IR_MOD
    je .p1_do_hint
    cmp al, IR_AND
    je .p1_do_hint
    cmp al, IR_OR
    je .p1_do_hint
    cmp al, IR_XOR
    je .p1_do_hint
    cmp al, IR_BOOL_AND
    je .p1_do_hint
    cmp al, IR_BOOL_OR
    je .p1_do_hint
    ; Unary ops
    cmp al, IR_NEG
    je .p1_do_hint
    cmp al, IR_ABS_INT
    je .p1_do_hint
    cmp al, IR_SIGNUM
    je .p1_do_hint
    cmp al, IR_BOOL_NOT
    je .p1_do_hint
    ; Shifts
    cmp al, IR_SHL
    je .p1_do_hint
    cmp al, IR_SHR
    je .p1_do_hint
    ; Bit ops
    cmp al, IR_POPCOUNT
    je .p1_do_hint
    cmp al, IR_CLZ
    je .p1_do_hint
    cmp al, IR_CTZ
    je .p1_do_hint
    cmp al, IR_BSWAP
    je .p1_do_hint
    cmp al, IR_ROL
    je .p1_do_hint
    cmp al, IR_ROR
    je .p1_do_hint
    cmp al, IR_SWAP_NIB
    je .p1_do_hint
    cmp al, IR_CLZ8
    je .p1_do_hint
    ; Register copy
    cmp al, IR_MOV
    je .p1_do_hint
    ; Float ops
    cmp al, IR_ABS_FLOAT
    je .p1_do_hint
    cmp al, IR_SQRT
    je .p1_do_hint
    cmp al, IR_TRUNC_F
    je .p1_do_hint
    cmp al, IR_CEIL
    je .p1_do_hint
    cmp al, IR_FLOOR
    je .p1_do_hint
    cmp al, IR_ROUND
    je .p1_do_hint
    ; Type casts
    cmp al, IR_CAST_ITF
    je .p1_do_hint
    cmp al, IR_CAST_FTI
    je .p1_do_hint
    cmp al, IR_CAST_BTI
    je .p1_do_hint
    cmp al, IR_CAST_CTI
    je .p1_do_hint
    cmp al, IR_CAST_CTB
    je .p1_do_hint
    cmp al, IR_CAST_BCI
    je .p1_do_hint
    cmp al, IR_CAST_BTC
    je .p1_do_hint
    ; Char predicates
    cmp al, IR_IS_ALPHA
    je .p1_do_hint
    cmp al, IR_IS_DIGIT_C
    je .p1_do_hint
    cmp al, IR_IS_ALNUM
    je .p1_do_hint
    cmp al, IR_IS_SPACE
    je .p1_do_hint
    cmp al, IR_IS_PRINT
    je .p1_do_hint
    cmp al, IR_IS_UPPER
    je .p1_do_hint
    cmp al, IR_IS_LOWER_C
    je .p1_do_hint
    cmp al, IR_IS_PUNCT
    je .p1_do_hint
    cmp al, IR_IS_EVEN
    je .p1_do_hint
    cmp al, IR_IS_ODD
    je .p1_do_hint
    ; Char transforms
    cmp al, IR_TO_UPPER
    je .p1_do_hint
    cmp al, IR_TO_LOWER
    je .p1_do_hint
    cmp al, IR_TO_DIGIT
    je .p1_do_hint
    ; Float predicates
    cmp al, IR_IS_NAN
    je .p1_do_hint
    cmp al, IR_IS_INF
    je .p1_do_hint
    cmp al, IR_IS_FINITE
    je .p1_do_hint
    cmp al, IR_IS_ZERO_F
    je .p1_do_hint
    cmp al, IR_IS_POS_F
    je .p1_do_hint
    cmp al, IR_IS_NEG_F
    je .p1_do_hint
    ; Comparison
    cmp al, IR_CMP_BOOL
    je .p1_do_hint
    jmp .phase1_next

.p1_do_hint:
    movzx ecx, word [r13 + 2]      ; dst vreg
    test cx, cx
    jz .phase1_next
    cmp ecx, GRAPHCOL_VMAX
    jae .phase1_next
    movzx edx, word [r13 + 4]      ; src1 vreg
    test dx, dx
    jz .phase1_next
    cmp edx, GRAPHCOL_VMAX
    jae .phase1_next
    mov [gc_copy_hint + rcx * 2], dx   ; dst → src1 hint

.phase1_next:
    inc ebx
    jmp .phase1_loop

.phase1_done:

    ; ----------------------------------------------------------
    ; Live-range fix: a vreg defined but never used has gc_last_use = 0,
    ; i.e. an empty backwards range [def, 0].  The Phase 2 overlap test
    ; (def[a] <= last[b] && def[b] <= last[a]) would then miss edges to
    ; vregs live across the dead definition, letting a dead load reuse
    ; the colour of an earlier-loaded live vreg and clobber its value
    ; before the use (e.g. pow(4.0, -1.0): the folded-away 1.0/0.0 loads
    ; overwrote the live 4.0 base register).  Clamp the range to the def
    ; point so the def is treated as a write that interferes as usual.
    ; ----------------------------------------------------------
    mov r12d, [gc_max_vreg]
    mov r14d, 1
.range_fix_loop:
    cmp r14d, r12d
    jg .range_fix_done
    cmp dword [gc_def + r14 * 4], UNSET_IDX
    je .range_fix_next
    mov eax, [gc_def + r14 * 4]
    cmp [gc_last_use + r14 * 4], eax
    jae .range_fix_next
    mov [gc_last_use + r14 * 4], eax
.range_fix_next:
    inc r14d
    jmp .range_fix_loop
.range_fix_done:

    ; ----------------------------------------------------------
    ; Phase 1.5: loop back-edge live-range extension
    ; ----------------------------------------------------------
    ; The [def, last_use] interval model cannot represent a value defined
    ; before a loop and used inside it: its interval does not span the
    ; loop back-edge, so an unrelated short-lived vreg defined inside the
    ; loop body may be assigned the same physical register and clobber
    ; the carried value on a later iteration.  Loop promotion hoists
    ; exactly these loads (loop-invariant LOAD_IMM / LOAD_VAR) out of the
    ; loop, leaving their uses inside, which makes the bug observable
    ; (e.g. skip2.rex: the hoisted b=0 constant was clobbered by the b+1
    ; add, so the inner loop restarted at b=3 instead of b=0).
    ;
    ; Fix: for every back-edge (JMP/JCC at index m targeting a LABEL at
    ; index t < m), any vreg defined before t and used at/after t is live
    ; across the whole loop, so extend its gc_last_use to m.  This forces
    ; interference with every in-loop definition and guarantees a distinct
    ; physical register.
    ; ----------------------------------------------------------
    mov ecx, IR_MAX_RECORDS
    lea rdi, [gc_label_idx]
    mov eax, 0xFFFF
    rep stosw

    xor ebx, ebx            ; i = IR record index
.bf_label_scan:
    cmp ebx, [ir_count]
    jae .bf_label_done
    imul eax, ebx, IR_RECORD_SIZE
    lea r13, [ir_buffer + rax]
    movzx eax, byte [r13]
    cmp al, IR_LABEL
    jne .bf_label_next
    movzx eax, word [r13 + 8]        ; label id
    cmp eax, IR_MAX_RECORDS
    jae .bf_label_next
    mov [gc_label_idx + rax * 2], bx
.bf_label_next:
    inc ebx
    jmp .bf_label_scan
.bf_label_done:

    xor ebx, ebx            ; i = IR record index
.bf_jmp_scan:
    cmp ebx, [ir_count]
    jae .bf_done
    imul eax, ebx, IR_RECORD_SIZE
    lea r13, [ir_buffer + rax]
    movzx eax, byte [r13]
    cmp al, IR_JMP
    je .bf_is_backedge
    cmp al, IR_JCC
    jne .bf_jmp_next
.bf_is_backedge:
    movzx eax, word [r13 + 8]        ; target label id
    cmp eax, IR_MAX_RECORDS
    jae .bf_jmp_next
    movzx ecx, word [gc_label_idx + rax * 2]
    cmp ecx, 0xFFFF
    je .bf_jmp_next                  ; unknown label (shouldn't happen)
    cmp ecx, ebx
    jae .bf_jmp_next                 ; forward jump → not a back-edge
    ; ecx = header index t, ebx = back-edge index m
    mov edx, 1                       ; vreg id
.bf_vreg_loop:
    cmp edx, [gc_max_vreg]
    ja .bf_jmp_next
    mov eax, [gc_def + rdx * 4]
    cmp eax, UNSET_IDX
    je .bf_vreg_next
    cmp eax, ecx
    jae .bf_vreg_next                ; defined at/after header → redefined in loop
    mov eax, [gc_last_use + rdx * 4]
    cmp eax, ecx
    jb .bf_vreg_next                 ; dead before the loop → not carried
    cmp eax, ebx
    jae .bf_vreg_next                ; already spans the back-edge
    mov [gc_last_use + rdx * 4], ebx
.bf_vreg_next:
    inc edx
    jmp .bf_vreg_loop
.bf_jmp_next:
    inc ebx
    jmp .bf_jmp_scan
.bf_done:

    ; ----------------------------------------------------------
    ; Force-spill pass: any vreg whose live range [def, last_use]
    ; spans an IR_CALL must be spilled — the callee clobbers all six
    ; physical registers (r10-r15).  Force-spilled vregs are still
    ; placed in the interference graph (they affect neighbours' degrees
    ; during simplification) but are assigned COLOR_SPILL in Phase 4.
    ; ----------------------------------------------------------
    mov ebx, [ir_count]
    test ebx, ebx
    jz .build_start
    xor ebx, ebx            ; i = IR record index
.force_loop:
    cmp ebx, [ir_count]
    jae .force_done
    imul eax, ebx, IR_RECORD_SIZE
    lea r13, [ir_buffer + rax]
    movzx eax, byte [r13]
    cmp al, IR_CALL
    jne .force_next
    ; r13 = IR_CALL record.  Scan all vregs for live ranges spanning it.
    mov edx, 1              ; vreg id
.force_vreg_loop:
    cmp edx, [gc_max_vreg]
    ja .force_next
    mov ecx, [gc_def + rdx * 4]
    cmp ecx, UNSET_IDX
    je .force_vreg_maybe    ; no recorded def → treat as live from index 0
    cmp ecx, ebx
    jae .force_vreg_next    ; defined at/after call → not live before it
    mov ecx, [gc_last_use + rdx * 4]
    cmp ecx, ebx
    jbe .force_vreg_next    ; last used at/before call → not live after it
    mov byte [gc_force_spill + rdx], 1
.force_vreg_next:
    inc edx
    jmp .force_vreg_loop
.force_vreg_maybe:
    mov ecx, [gc_last_use + rdx * 4]
    cmp ecx, ebx
    jbe .force_vreg_next
    mov byte [gc_force_spill + rdx], 1
    jmp .force_vreg_next
.force_next:
    inc ebx
    jmp .force_loop
.force_done:

    ; ----------------------------------------------------------
    ; Phase 2: build interference graph
    ; ----------------------------------------------------------
    ; Two vregs v1 and v2 interfere iff their live ranges overlap:
    ;   [def[v1], last_use[v1]] ∩ [def[v2], last_use[v2]] ≠ ∅
    ; Overlap condition: def[v1] ≤ last_use[v2] AND def[v2] ≤ last_use[v1]
    ;
    ; Only defined vregs (gc_def ≠ UNSET_IDX) are considered.
    ;
    ; Outer loop v1: 1 .. gc_max_vreg-1  (uses jge to stop when v1==gc_max_vreg)
    ; Inner loop v2: v1+1 .. gc_max_vreg (uses jg  to stop when v2>gc_max_vreg)
    ; Together they cover every unique pair exactly once.

.build_start:
    mov r12d, [gc_max_vreg]

    mov r14d, 1             ; v1
.build_outer:
    cmp r14d, r12d
    jge .build_done         ; stop when v1 >= gc_max_vreg (all pairs covered)

    cmp dword [gc_def + r14 * 4], UNSET_IDX
    je .build_next_outer

    mov r15d, r14d
    inc r15d                ; v2 = v1 + 1

.build_inner:
    cmp r15d, r12d
    jg .build_next_outer    ; stop when v2 > gc_max_vreg

    cmp dword [gc_def + r15 * 4], UNSET_IDX
    je .build_next_inner

    ; Overlap test: def[v1] ≤ last[v2]  AND  def[v2] ≤ last[v1]
    mov eax, [gc_def      + r14 * 4]
    mov ecx, [gc_last_use + r15 * 4]
    cmp eax, ecx
    jg .build_next_inner            ; def[v1] > last[v2] → no overlap

    mov eax, [gc_def      + r15 * 4]
    mov ecx, [gc_last_use + r14 * 4]
    cmp eax, ecx
    jg .build_next_inner            ; def[v2] > last[v1] → no overlap

    ; Set interference (both directions)
    mov rdi, r14
    mov rsi, r15
    call gc_interf_set
    inc dword [gc_degree + r14 * 4]
    inc dword [gc_degree + r15 * 4]

.build_next_inner:
    inc r15d
    jmp .build_inner

.build_next_outer:
    inc r14d
    jmp .build_outer

.build_done:

    ; ----------------------------------------------------------
    ; Phase 2.5: seed the simplification worklist
    ; ----------------------------------------------------------
    ; Add every defined, non-removed vreg with degree < NUM_PHYS_REGS.

    mov r12d, [gc_max_vreg]
    mov r14d, 1
.seed_wl:
    cmp r14d, r12d
    jg .seed_wl_done        ; inclusive: processes vregs 1 .. gc_max_vreg

    cmp dword [gc_def + r14 * 4], UNSET_IDX
    je .seed_next
    cmp dword [gc_degree + r14 * 4], NUM_PHYS_REGS
    jge .seed_next

    ; Push r14 to worklist
    mov eax, [gc_wl_len]
    mov [gc_worklist + rax * 2], r14w
    inc dword [gc_wl_len]
    mov byte [gc_in_wl + r14], 1

.seed_next:
    inc r14d
    jmp .seed_wl

.seed_wl_done:

    ; ----------------------------------------------------------
    ; Phase 3: simplification (worklist + optimistic spill)
    ; ----------------------------------------------------------

.simplify_loop:
    cmp dword [gc_remaining], 0
    je .simplify_done

    ; --- Try worklist first ---
    cmp dword [gc_wl_len], 0
    je .find_spill

    ; Pop from LIFO worklist
    dec dword [gc_wl_len]
    mov eax, [gc_wl_len]
    movzx ebx, word [gc_worklist + rax * 2]   ; ebx = vreg

    ; Push to colouring stack
    mov eax, [gc_stack_top]
    mov [gc_stack + rax * 2], bx
    inc dword [gc_stack_top]

    ; Mark removed
    mov byte [gc_removed + rbx], 1
    mov byte [gc_in_wl   + rbx], 0
    dec dword [gc_remaining]

    ; Decrement neighbours + update worklist
    mov rdi, rbx
    call gc_dn_update

    jmp .simplify_loop

    ; --- Spill selection: minimise use_count / (degree+1) ---
    ; Uses cross-multiplication to avoid division:
    ;   candidate c beats best b iff
    ;   use_count[c] * (degree[b]+1) < use_count[b] * (degree[c]+1)
    ;
    ; Registers during scan:
    ;   r12d = gc_max_vreg
    ;   r13d = best vreg ID (-1 = none yet)
    ;   r14d = best use_count   (stored for cross-multiply)
    ;   r15d = best degree      (stored for cross-multiply)
    ;   ecx  = current candidate vreg
    ;   ebx  = scratch for cross-multiply
.find_spill:
    mov r12d, [gc_max_vreg]
    mov r13d, -1
    mov r14d, 0
    mov r15d, 0

    mov ecx, 1
.spill_scan:
    cmp ecx, r12d
    jg .spill_scan_done

    cmp dword [gc_def + rcx * 4], UNSET_IDX
    je .spill_next
    cmp byte [gc_removed + rcx], 0
    jne .spill_next

    cmp r13d, -1
    je .new_best_spill                  ; first candidate — accept immediately

    ; Cross-multiply comparison:
    ;   new_use * (best_deg+1) vs best_use * (new_deg+1)
    mov eax, [gc_use_count + rcx * 4]  ; new_use
    mov edx, [gc_degree    + rcx * 4]  ; new_deg
    lea ebx, [r15 + 1]                 ; best_deg + 1
    imul ebx, eax                      ; ebx = new_use * (best_deg+1)
    lea eax, [rdx + 1]                 ; new_deg + 1
    imul eax, r14d                     ; eax = best_use * (new_deg+1)
    cmp ebx, eax
    jge .spill_next                    ; current >= best → no improvement

.new_best_spill:
    mov r13d, ecx
    mov r14d, [gc_use_count + rcx * 4]
    mov r15d, [gc_degree    + rcx * 4]

.spill_next:
    inc ecx
    jmp .spill_scan

.spill_scan_done:
    cmp r13d, -1
    je .simplify_done           ; no candidate (all removed; shouldn't happen)

    ; Push potential spill to colouring stack
    mov eax, [gc_stack_top]
    mov [gc_stack + rax * 2], r13w
    inc dword [gc_stack_top]

    mov byte [gc_removed + r13], 1
    dec dword [gc_remaining]

    mov rdi, r13
    call gc_dn_update

    jmp .simplify_loop

.simplify_done:

    ; ----------------------------------------------------------
    ; Phase 4: colouring with biased colouring
    ; ----------------------------------------------------------
    ; Pop each vreg from the colouring stack.
    ;
    ; Step A: Scan interference row with BSF to build a bitmask of
    ;         colours used by already-coloured neighbours.
    ;
    ; Step B (biased colouring): If gc_copy_hint[v] names a vreg that
    ;         has already been assigned a valid colour c not in the
    ;         used-colour bitmask, assign c immediately.  This tends to
    ;         assign the same physical register to dst and src1 in
    ;         arithmetic ops, eliminating the src1→dst copy in codegen.
    ;
    ; Step C: Fall back to smallest free colour (0-5) or spill.

    ; Re-clamp gc_max_vreg in case vreg_counter was updated (defensive)
    mov eax, [vreg_counter]
    dec eax
    cmp eax, GRAPHCOL_VMAX - 1
    jbe .set_max2
    mov eax, GRAPHCOL_VMAX - 1
.set_max2:
    mov [gc_max_vreg], eax

.colour_loop:
    cmp dword [gc_stack_top], 0
    je .colour_done

    dec dword [gc_stack_top]
    mov eax, [gc_stack_top]
    movzx ebx, word [gc_stack + rax * 2]    ; vreg being coloured

    ; Force-spilled vregs (live across an IR_CALL) never get a colour
    movzx eax, byte [gc_force_spill + rbx]
    test al, al
    jnz .spill_vreg

    ; Loop-promoted vregs may only use callee-saved colours (2-5 = r12-r15)
    xor r13d, r13d            ; colour floor (0 = no restriction)
    movzx eax, byte [gc_force_callee + rbx]
    test al, al
    jz .cc_nofloor
    mov r13d, 2
.cc_nofloor:

    ; --- Step A: Build used-colour bitmask via BSF row scan ---
    imul eax, ebx, GRAPHCOL_BPR
    lea rsi, [gc_interf + rax]              ; row start
    lea rdi, [rsi + GRAPHCOL_BPR]           ; row end
    xor r14d, r14d                          ; used_colours bitmask
    xor r15d, r15d                          ; bit base (0, 64, 128, …)

.cscan_word:
    cmp rsi, rdi
    je .cscan_done

    mov rax, [rsi]
    add rsi, 8
    test rax, rax
    jz .cscan_next_word

.cscan_bits:
    bsf rcx, rax                            ; rcx = lowest set bit index (0-63)
    lea rdx, [r15 + rcx]                    ; rdx = neighbour vreg ID
    btr rax, rcx                            ; clear that bit

    movzx ecx, byte [gc_color + rdx]        ; neighbour's colour
    cmp cl, COLOR_NONE
    je .cscan_cont
    cmp cl, COLOR_SPILL
    je .cscan_cont
    cmp cl, NUM_PHYS_REGS
    jae .cscan_cont                         ; invalid colour — defensive
    bts r14d, ecx                           ; mark colour as used

.cscan_cont:
    test rax, rax
    jnz .cscan_bits

.cscan_next_word:
    add r15d, 64
    jmp .cscan_word

.cscan_done:
    ; --- Step B: biased colouring — try copy hint first ---
    movzx eax, word [gc_copy_hint + rbx * 2]   ; hint vreg (0 = none)
    test ax, ax
    jz .pick                                    ; no hint → generic assignment

    movzx ecx, byte [gc_color + rax]            ; hint vreg's colour
    cmp cl, COLOR_NONE
    je .pick                                    ; hint not yet coloured
    cmp cl, COLOR_SPILL
    je .pick                                    ; hint was spilled
    cmp cl, NUM_PHYS_REGS
    jae .pick                                   ; invalid — defensive

    ; If force-callee, reject caller-saved hint colours (0-1)
    cmp r13d, 2
    jb .cc_hint_ok
    cmp cl, 2
    jb .pick
.cc_hint_ok:

    ; Check that the hint colour is actually free for this vreg
    mov edx, 1
    shl edx, cl
    test r14d, edx
    jnz .pick                                   ; hint colour taken by a neighbour

    ; Hint colour is free — assign it (this eliminates the src1→dst copy move)
    mov byte [gc_color + rbx], cl
    jmp .colour_loop

    ; --- Step C: generic assignment — smallest free colour ---
.pick:
    mov ecx, r13d                           ; start at floor (0 or 2)
.pick_loop:
    cmp ecx, NUM_PHYS_REGS
    je .spill_vreg
    mov edx, 1
    shl edx, cl
    test r14d, edx
    jz .assign_colour
    inc ecx
    jmp .pick_loop

.assign_colour:
    mov byte [gc_color + rbx], cl
    jmp .colour_loop

.spill_vreg:
    mov byte [gc_color + rbx], COLOR_SPILL
    jmp .colour_loop

.colour_done:

    ; ----------------------------------------------------------
    ; Phase 5: populate vreg_phys[] and vreg_offset[]
    ; ----------------------------------------------------------

    mov r12d, [gc_max_vreg]
    mov r14d, 1
.map_loop:
    cmp r14d, r12d
    jg .map_done

    cmp dword [gc_def + r14 * 4], UNSET_IDX
    je .map_next                ; undefined vreg → leave vreg_phys = 255

    movzx eax, byte [gc_color + r14]
    cmp al, COLOR_NONE
    je .map_next                ; never coloured (shouldn't happen for defined vregs)

    mov [vreg_phys + r14], al   ; store colour (0-5 or 255)

    cmp al, COLOR_SPILL
    jne .map_next

    ; Assign stack spill slot (8 bytes, negative RBP offset)
    mov eax, [stack_frame_size]
    add eax, 8
    mov [stack_frame_size], eax
    neg eax
    mov [vreg_offset + r14 * 4], eax

.map_next:
    inc r14d
    jmp .map_loop

.map_done:
    ; ----------------------------------------------------------
    ; Overflow vregs: vreg ids above gc_max_vreg never entered the
    ; interference graph, so gc_def[] stays UNSET_IDX and Phase 5 left
    ; vreg_phys[] = COLOR_SPILL with no stack slot and no frame setup.
    ; Codegen would then emit [rbp+off] with off = 0 against an
    ; uninitialized rbp → runtime SIGSEGV. Assign a real spill slot to
    ; every vreg that still reads COLOR_SPILL with a zero offset, so the
    ; frame gets sized and the prologue (push rbp/mov rbp,rsp/sub rsp)
    ; is emitted. Spilling overflow vregs is always safe (correctness
    ; over optimality) and prevents silent miscompiles on large programs.
    ; ----------------------------------------------------------
    mov r15d, [vreg_counter]        ; vreg ids are 1 .. vreg_counter-1
    mov r14d, 1
.slot_loop:
    cmp r14d, r15d
    jae .slot_done
    cmp byte [vreg_phys + r14], COLOR_SPILL
    jne .slot_next
    cmp dword [vreg_offset + r14 * 4], 0
    jne .slot_next                  ; already has a slot (Phase 5 assigned it)
    mov eax, [stack_frame_size]
    add eax, 8
    mov [stack_frame_size], eax
    neg eax
    mov [vreg_offset + r14 * 4], eax
.slot_next:
    inc r14d
    jmp .slot_loop
.slot_done:

    ; Align spill frame to 16 bytes
    mov eax, [stack_frame_size]
    add eax, 15
    and eax, -16
    mov [stack_frame_size], eax

.done_alloc:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret


; ============================================================
;  gc_dn_update — decrement neighbours and update worklist
;
;  Input:  rdi = vreg v (just removed from the graph)
;
;  For each non-removed neighbour n of v:
;    • decrement gc_degree[n]
;    • if gc_degree[n] drops below NUM_PHYS_REGS and n is not
;      already in the worklist: push n onto gc_worklist.
;
;  Uses a fast BSF-based scan of v's 512-bit interference row
;  (8 × 64-bit words) — no per-neighbour function call.
; ============================================================
gc_dn_update:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12d, edi               ; central node v

    ; Compute row base and end pointers
    imul eax, r12d, GRAPHCOL_BPR
    lea r13, [gc_interf + rax]  ; r13 = row start
    lea r14, [r13 + GRAPHCOL_BPR] ; r14 = row end
    xor r15d, r15d              ; bit base (0, 64, 128, …)

.dn_word:
    cmp r13, r14
    je .dn_done

    mov rax, [r13]
    add r13, 8
    test rax, rax
    jz .dn_next_word

.dn_bits:
    bsf rbx, rax                ; rbx = bit index within this word (0-63)
    lea rdx, [r15 + rbx]        ; rdx = neighbour vreg ID
    btr rax, rbx                ; clear bit

    cmp edx, r12d
    je .dn_cont                 ; skip self (defensive)

    cmp byte [gc_removed + rdx], 0
    jne .dn_cont                ; skip already-removed neighbours

    ; Decrement this neighbour's current degree
    dec dword [gc_degree + rdx * 4]

    ; If degree just dropped below k and not yet in worklist: add it
    cmp dword [gc_degree + rdx * 4], NUM_PHYS_REGS
    jge .dn_cont
    cmp byte [gc_in_wl + rdx], 0
    jne .dn_cont

    ; Push rdx to the worklist
    mov ecx, [gc_wl_len]
    mov [gc_worklist + rcx * 2], dx
    inc dword [gc_wl_len]
    mov byte [gc_in_wl + rdx], 1

.dn_cont:
    test rax, rax
    jnz .dn_bits

.dn_next_word:
    add r15d, 64
    jmp .dn_word

.dn_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret


; ============================================================
;  gc_interf_set — mark v1 and v2 as interfering (symmetric)
;
;  Input: rdi = v1, rsi = v2
;  Clobbers: rax, rcx, rdx  (caller-saved; callee saves none)
; ============================================================
gc_interf_set:
    ; Set bit gc_interf[v1][v2]
    mov rax, rdi
    imul rax, rax, GRAPHCOL_BPR    ; row offset for v1
    mov rdx, rsi
    mov rcx, rdx
    shr rdx, 3                      ; byte offset of v2 within row
    and ecx, 7                      ; bit offset of v2 within byte
    lea rax, [gc_interf + rax + rdx]
    mov dl, 1
    shl dl, cl
    or [rax], dl

    ; Set bit gc_interf[v2][v1]  (symmetric)
    mov rax, rsi
    imul rax, rax, GRAPHCOL_BPR
    mov rdx, rdi
    mov rcx, rdx
    shr rdx, 3
    and ecx, 7
    lea rax, [gc_interf + rax + rdx]
    mov dl, 1
    shl dl, cl
    or [rax], dl

    ret
