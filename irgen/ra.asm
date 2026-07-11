; Rex Graph-Colouring Register Allocator
; written in x86-64 NASM assembly
;
; Replaces the old linear-scan allocator with a Chaitin-Briggs graph-colouring
; allocator.  The algorithm has four phases:
;
;   1. Liveness  — compute vreg_def[v] and gc_last_use[v] from the IR.
;   2. Build     — construct an interference graph as a symmetric bitmap.
;                  Two vregs interfere iff their live ranges overlap.
;   3. Simplify  — repeatedly remove nodes with degree < NUM_PHYS_REGS and
;                  push them onto the colouring stack.  When no such node
;                  exists choose the highest-degree node as a potential spill
;                  and push it anyway (Chaitin-Briggs optimistic colouring).
;   4. Colour    — pop the stack; assign each node the smallest colour not
;                  used by already-coloured neighbours.  If no colour is
;                  free the node is spilled to the stack frame.
;
; Physical registers available (6 total):
;   phys 0 -> r10   phys 1 -> r11   phys 2 -> r12
;   phys 3 -> r13   phys 4 -> r14   phys 5 -> r15
;
; Interface (identical to old allocator):
;   vreg_phys[v]   = phys ID (0-5) or 255 (spilled)
;   vreg_offset[v] = signed stack offset from RBP (only meaningful if spilled)
;   stack_frame_size = total spill frame in bytes (aligned to 8)

%include "include/rex_defs.inc"
%include "include/rex_ir.inc"

; ---------- graph-colouring constants ----------
GRAPHCOL_VMAX   equ 512     ; max vregs handled (must be power of 2)
GRAPHCOL_BPR    equ 64      ; bytes per row = GRAPHCOL_VMAX / 8
NUM_PHYS_REGS   equ 6
UNSET_IDX       equ 0xFFFFFFFF  ; vreg not yet seen in IR

section .bss
    global vreg_phys
    global vreg_offset
    global stack_frame_size

    ; ---- exported results ----
    vreg_phys           resb VREG_MAX       ; vreg -> phys reg (255 = spilled)
    vreg_offset         resd VREG_MAX       ; vreg -> stack offset (if spilled)
    stack_frame_size    resd 1

    ; ---- graph-colouring working tables ----
    ; Liveness
    gc_def              resd GRAPHCOL_VMAX  ; instruction where vreg is defined
    gc_last_use         resd GRAPHCOL_VMAX  ; last instruction that reads this vreg
    ; Interference graph: GRAPHCOL_VMAX × GRAPHCOL_VMAX bits = 32 KiB
    gc_interf           resb GRAPHCOL_VMAX * GRAPHCOL_BPR
    ; Colouring data
    gc_degree           resd GRAPHCOL_VMAX  ; current degree (decremented as nodes removed)
    gc_orig_degree      resd GRAPHCOL_VMAX  ; original degree (for spill cost heuristic)
    gc_color            resb GRAPHCOL_VMAX  ; assigned colour (0-5 = phys, 255 = spilled, 0xFE = uncoloured)
    gc_removed          resb GRAPHCOL_VMAX  ; 1 if removed from graph during simplification
    ; Colouring stack (elimination order)
    gc_stack            resw GRAPHCOL_VMAX
    gc_stack_top        resd 1              ; index into gc_stack (next free slot)

section .text
    global allocate_registers

    extern ir_count
    extern ir_buffer
    extern vreg_counter

; ============================================================
;  Public entry point
; ============================================================
allocate_registers:
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; ---- Phase 0: initialise all tables ----
    ; vreg_phys <- 255 (unallocated)
    mov rcx, VREG_MAX
    lea rdi, [vreg_phys]
    mov al, 255
    rep stosb

    ; vreg_offset <- 0
    mov rcx, VREG_MAX
    lea rdi, [vreg_offset]
    xor eax, eax
    rep stosd

    mov dword [stack_frame_size], 0

    ; gc_def <- UNSET_IDX
    mov rcx, GRAPHCOL_VMAX
    lea rdi, [gc_def]
    mov eax, UNSET_IDX
    rep stosd

    ; gc_last_use <- 0
    mov rcx, GRAPHCOL_VMAX
    lea rdi, [gc_last_use]
    xor eax, eax
    rep stosd

    ; gc_interf <- 0 (clear all interference bits)
    mov rcx, GRAPHCOL_VMAX * GRAPHCOL_BPR
    lea rdi, [gc_interf]
    xor eax, eax
    rep stosb

    ; gc_degree, gc_orig_degree <- 0
    mov rcx, GRAPHCOL_VMAX
    lea rdi, [gc_degree]
    xor eax, eax
    rep stosd
    mov rcx, GRAPHCOL_VMAX
    lea rdi, [gc_orig_degree]
    xor eax, eax
    rep stosd

    ; gc_color <- 0xFE (uncoloured)
    mov rcx, GRAPHCOL_VMAX
    lea rdi, [gc_color]
    mov al, 0xFE
    rep stosb

    ; gc_removed <- 0
    mov rcx, GRAPHCOL_VMAX
    lea rdi, [gc_removed]
    xor eax, eax
    rep stosb

    ; gc_stack_top <- 0
    mov dword [gc_stack_top], 0

    ; ---- Phase 1: liveness (compute gc_def and gc_last_use) ----
    mov r12d, [ir_count]
    test r12d, r12d
    jz .done_alloc

    xor ebx, ebx  ; i = 0
.liveness_loop:
    cmp ebx, r12d
    je .liveness_done

    imul eax, ebx, IR_RECORD_SIZE
    lea r13, [ir_buffer + rax]

    ; dst vreg — record the first instruction that defines it
    movzx eax, word [r13 + 2]
    test ax, ax
    jz .check_src1_live
    cmp eax, GRAPHCOL_VMAX
    jae .check_src1_live
    cmp dword [gc_def + rax * 4], UNSET_IDX
    jne .check_src1_live
    mov [gc_def + rax * 4], ebx   ; first definition

.check_src1_live:
    movzx eax, word [r13 + 4]   ; src1
    test ax, ax
    jz .check_src2_live
    cmp eax, GRAPHCOL_VMAX
    jae .check_src2_live
    mov [gc_last_use + rax * 4], ebx

.check_src2_live:
    movzx eax, word [r13 + 6]   ; src2
    test ax, ax
    jz .liveness_next
    cmp eax, GRAPHCOL_VMAX
    jae .liveness_next
    mov [gc_last_use + rax * 4], ebx

.liveness_next:
    inc ebx
    jmp .liveness_loop

.liveness_done:
    ; ---- Phase 2: build interference graph ----
    ; vreg IDs go from 1 to vreg_counter-1.
    ; Cap at GRAPHCOL_VMAX-1.
    mov r12d, [vreg_counter]
    dec r12d                     ; last vreg ID
    cmp r12d, GRAPHCOL_VMAX - 1
    jbe .build_loop_outer_start
    mov r12d, GRAPHCOL_VMAX - 1  ; clamp

.build_loop_outer_start:
    mov r14d, 1                  ; v1
.build_loop_outer:
    cmp r14d, r12d
    jge .build_done

    ; Skip vregs with no definition (never emitted)
    cmp dword [gc_def + r14 * 4], UNSET_IDX
    je .build_next_outer

    mov r15d, r14d
    inc r15d                     ; v2 starts at v1+1

.build_loop_inner:
    cmp r15d, r12d
    jg .build_next_outer

    cmp dword [gc_def + r15 * 4], UNSET_IDX
    je .build_next_inner

    ; Test range overlap: [def[v1], last[v1]] ∩ [def[v2], last[v2]] ≠ ∅
    ; Overlap iff def1 <= last2 AND def2 <= last1
    mov eax, [gc_def + r14 * 4]
    mov ecx, [gc_last_use + r15 * 4]
    cmp eax, ecx
    jg .build_next_inner          ; def1 > last2 → no overlap

    mov eax, [gc_def + r15 * 4]
    mov ecx, [gc_last_use + r14 * 4]
    cmp eax, ecx
    jg .build_next_inner          ; def2 > last1 → no overlap

    ; They interfere — set bits in both rows
    mov rdi, r14
    mov rsi, r15
    call gc_interf_set
    inc dword [gc_degree + r14 * 4]
    inc dword [gc_orig_degree + r14 * 4]
    inc dword [gc_degree + r15 * 4]
    inc dword [gc_orig_degree + r15 * 4]

.build_next_inner:
    inc r15d
    jmp .build_loop_inner

.build_next_outer:
    inc r14d
    jmp .build_loop_outer

.build_done:
    ; ---- Phase 3: simplification (Chaitin-Briggs) ----
    ; Total active nodes = vreg_counter - 1 (IDs 1..vreg_counter-1, clamped)
    mov r12d, [vreg_counter]
    dec r12d
    cmp r12d, GRAPHCOL_VMAX - 1
    jbe .simplify_loop
    mov r12d, GRAPHCOL_VMAX - 1

.simplify_loop:
    ; Count how many non-removed nodes remain
    xor ebx, ebx    ; remaining count
    mov r14d, 1
.count_remaining:
    cmp r14d, r12d
    jg .count_done
    cmp dword [gc_def + r14 * 4], UNSET_IDX
    je .count_next
    cmp byte [gc_removed + r14], 0
    jne .count_next
    inc ebx
.count_next:
    inc r14d
    jmp .count_remaining
.count_done:
    test ebx, ebx
    jz .simplify_done

    ; Search for a node with current degree < NUM_PHYS_REGS
    mov r14d, 1
    mov r15d, -1    ; best candidate index (-1 = not found)
.find_simple:
    cmp r14d, r12d
    jg .find_simple_done
    cmp dword [gc_def + r14 * 4], UNSET_IDX
    je .find_simple_next
    cmp byte [gc_removed + r14], 0
    jne .find_simple_next
    cmp dword [gc_degree + r14 * 4], NUM_PHYS_REGS
    jl .found_simple
.find_simple_next:
    inc r14d
    jmp .find_simple

.found_simple:
    ; Push this node onto the stack
    mov eax, [gc_stack_top]
    mov [gc_stack + rax * 2], r14w
    inc dword [gc_stack_top]
    mov byte [gc_removed + r14], 1
    ; Decrement degree of all neighbours
    mov rdi, r14
    call gc_decrement_neighbors
    jmp .simplify_loop

.find_simple_done:
    ; No node with degree < k — select potential spill (highest orig_degree)
    mov r14d, 1
    mov r15d, -1       ; best spill candidate (vreg ID)
    mov ebx, -1        ; best degree
.find_spill:
    cmp r14d, r12d
    jg .find_spill_done
    cmp dword [gc_def + r14 * 4], UNSET_IDX
    je .find_spill_next
    cmp byte [gc_removed + r14], 0
    jne .find_spill_next
    mov eax, [gc_orig_degree + r14 * 4]
    cmp eax, ebx
    jle .find_spill_next
    mov ebx, eax
    mov r15d, r14d
.find_spill_next:
    inc r14d
    jmp .find_spill
.find_spill_done:
    cmp r15d, -1
    je .simplify_done  ; nothing left (shouldn't happen)
    ; Push potential spill onto stack
    mov eax, [gc_stack_top]
    mov [gc_stack + rax * 2], r15w
    inc dword [gc_stack_top]
    mov byte [gc_removed + r15], 1
    mov rdi, r15
    call gc_decrement_neighbors
    jmp .simplify_loop

.simplify_done:
    ; ---- Phase 4: colouring (pop stack, assign colours) ----
    ; All removed nodes remain removed; gc_color starts as 0xFE.
.colour_loop:
    cmp dword [gc_stack_top], 0
    je .colour_done

    dec dword [gc_stack_top]
    mov eax, [gc_stack_top]
    movzx ebx, word [gc_stack + rax * 2]  ; vreg to colour

    ; Build used-colour bitmask from already-coloured neighbours
    xor r14d, r14d  ; used_colours bitmask (bits 0-5)
    mov r15d, 1     ; neighbour iterator
.scan_neighbours:
    cmp r15d, r12d
    jg .scan_done
    cmp r15d, ebx
    je .scan_next_nb
    ; Test interference(ebx, r15d)
    mov rdi, rbx
    mov rsi, r15
    call gc_interf_test
    test rax, rax
    jz .scan_next_nb
    ; Neighbour r15d is coloured?
    movzx eax, byte [gc_color + r15]
    cmp al, 0xFE
    je .scan_next_nb
    cmp al, 255
    je .scan_next_nb
    ; It has a colour — mark that colour as used
    mov cl, al
    mov eax, 1
    shl eax, cl
    or r14d, eax
.scan_next_nb:
    inc r15d
    jmp .scan_neighbours

.scan_done:
    ; Find smallest unused colour
    xor ecx, ecx  ; colour candidate
.pick_colour:
    cmp ecx, NUM_PHYS_REGS
    je .must_spill
    mov eax, 1
    shl eax, cl
    test r14d, eax
    jz .colour_assigned
    inc ecx
    jmp .pick_colour

.colour_assigned:
    mov byte [gc_color + rbx], cl
    jmp .colour_loop

.must_spill:
    mov byte [gc_color + rbx], 255
    jmp .colour_loop

.colour_done:
    ; ---- Phase 5: populate vreg_phys and vreg_offset ----
    ; Also assign stack slots for spilled vregs.
    mov r12d, [vreg_counter]
    dec r12d
    cmp r12d, GRAPHCOL_VMAX - 1
    jbe .map_loop
    mov r12d, GRAPHCOL_VMAX - 1

    ; Handle large vreg IDs (>= GRAPHCOL_VMAX) — they are auto-spilled.
    ; vreg_phys is already 255 for them from Phase 0.
    ; We need to assign stack offsets for them too.
    ; (In practice these shouldn't appear for small programs.)

.map_loop:
    mov r14d, 1
.map_each:
    cmp r14d, r12d
    jg .map_done

    ; Skip undefined vregs
    cmp dword [gc_def + r14 * 4], UNSET_IDX
    je .map_next

    movzx eax, byte [gc_color + r14]
    cmp al, 0xFE
    je .map_next  ; uncoloured (no definition reached) — leave as 255

    mov [vreg_phys + r14], al

    ; If spilled, assign a stack slot
    cmp al, 255
    jne .map_next
    mov eax, [stack_frame_size]
    add eax, 8
    mov [stack_frame_size], eax
    neg eax
    mov [vreg_offset + r14 * 4], eax

.map_next:
    inc r14d
    jmp .map_each

.map_done:
    ; Align stack frame to 16 bytes
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
;  Helper: gc_interf_set(v1=rdi, v2=rsi)
;  Sets interference bit in both directions (symmetric).
; ============================================================
gc_interf_set:
    push rcx
    push rdx
    push rax

    ; Set bit interf[v1][v2]
    mov rax, rdi
    imul rax, rax, GRAPHCOL_BPR   ; row base for v1
    mov rdx, rsi
    mov rcx, rdx
    shr rdx, 3                    ; byte offset within row
    and ecx, 7                    ; bit offset
    lea rax, [gc_interf + rax + rdx]
    mov dl, 1
    shl dl, cl
    or [rax], dl

    ; Set bit interf[v2][v1]
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

    pop rax
    pop rdx
    pop rcx
    ret


; ============================================================
;  Helper: gc_interf_test(v1=rdi, v2=rsi)
;  Returns rax = 1 if v1 and v2 interfere, 0 otherwise.
; ============================================================
gc_interf_test:
    mov rax, rdi
    imul rax, rax, GRAPHCOL_BPR
    mov rcx, rsi
    mov rdx, rcx
    shr rdx, 3
    and ecx, 7
    movzx eax, byte [gc_interf + rax + rdx]
    shr eax, cl
    and eax, 1
    ret


; ============================================================
;  Helper: gc_decrement_neighbors(v=rdi)
;  For each non-removed neighbour of v, decrement its current degree.
;
;  Simple O(N) scan: iterates all vregs and checks the interference bit.
;  Previous byte-level bit-loop had an alignment bug where r15 could be
;  left mid-byte after the inner loop, causing bytes to be re-processed.
; ============================================================
gc_decrement_neighbors:
    push rbx
    push r12
    push r13

    mov r12d, edi           ; central node whose neighbours to update

    mov r13d, [vreg_counter]
    dec r13d
    cmp r13d, GRAPHCOL_VMAX - 1
    jbe .dnb_start
    mov r13d, GRAPHCOL_VMAX - 1

.dnb_start:
    mov ebx, 1              ; neighbour candidate v = 1..r13d
.dnb_loop:
    cmp ebx, r13d
    jg .dnb_done

    cmp ebx, r12d
    je .dnb_next            ; skip self

    cmp byte [gc_removed + rbx], 0
    jne .dnb_next           ; skip already-removed nodes

    ; Test interference(r12, v=rbx)
    mov rdi, r12
    mov rsi, rbx
    call gc_interf_test     ; rax = 1 if interfere, else 0
    test rax, rax
    jz .dnb_next

    ; Active neighbour interferes — decrement its current degree
    dec dword [gc_degree + rbx * 4]

.dnb_next:
    inc ebx
    jmp .dnb_loop

.dnb_done:
    pop r13
    pop r12
    pop rbx
    ret
