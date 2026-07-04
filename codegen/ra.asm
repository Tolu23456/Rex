; ============================================================
; codegen/ra.asm — SOTA Linear Scan Register Allocator for Rex
;
; ALGORITHM
; ---------
; Interval-based Linear Scan with Conflict Detection (Poletto & Sarkar style)
;
; Phase 1  ra_prescan(rdi=src, rsi=size)
;          Walk source bytes before the main lexer runs.
;          For every identifier, accumulate:
;            - weighted use count: weight += 1 << min(indent_depth, 6)
;            - first/last use byte position (for interval construction)
;            - maximum nesting depth across all uses
;            - raw use count (for density estimation)
;
; Phase 2  ra_linear_scan
;          1. Compute priority per entry:
;               priority = wcount * (1 + max_depth)
;             (favors heavily-used variables in deep loops)
;          2. Sort entries by priority descending (selection sort, N ≤ 256)
;          3. Greedy allocation with interval conflict detection:
;             For each entry in priority order:
;               For each slot 0..3:
;                 Check if any already-assigned variable has an overlapping
;                 interval [first_use, last_use].  If no conflict, assign.
;             Two variables conflict iff:
;               first[i] <= last[j]  AND  first[j] <= last[i]
;
; Phase 3  ra_on_var_add(rdi=var_idx, rsi=name_ptr)
;          Called from var_add() when a variable is declared.
;          Looks up name_ptr in the prescan table; if it was
;          allocated a slot, records:
;            ra_alloc_reg[var_idx] = slot
;            ra_slot_var_va[slot]  = VAR_STORAGE_BASE + idx*64
;
; INTEGRATION (codegen.asm / main.asm)
; -------------------------------------
;   main.asm             — calls ra_prescan before lexer_init,
;                          ra_linear_scan before parse_program
;   codegen.asm          — codegen_emit_mov_rax_var checks ra_alloc_reg
;                          codegen_emit_store_rax_to_var checks ra_alloc_reg
;                          emit_call_abs calls ra_emit_spill/restore_all
;   parser.asm           — calls ra_on_var_add from var_add
;
; REGISTER POOL
; -------------
;   Slot 0 → R8   Slot 1 → R9   Slot 2 → R10   Slot 3 → R11
;   All caller-saved; must be spilled around runtime blob calls
;   (rt_pri, rt_prf, etc. explicitly clobber R8–R11 / syscall clobbers R11).
;
; INSTRUCTION ENCODINGS
; ---------------------
;   Load  mov rax, RN   : 4C 89 {C0,C8,D0,D8}  (REX.W|R + MOV r/m64,r64)
;   Store mov RN,  rax  : 49 89 {C0,C1,C2,C3}  (REX.W|B + MOV r/m64,r64)
;   Spill mov [a], RN   : 4C 89 {04,0C,14,1C} 25 addr32
;   Rest. mov RN,  [a]  : 4C 8B {04,0C,14,1C} 25 addr32
;   Zero  xor RNd,RNd   : 45 31 {C0,C9,D2,DB}
;
; SOTA FEATURES
; -------------
;   [S1] Interval-based conflict detection prevents two simultaneously-live
;        variables from sharing a register, reducing spurious spills.
;   [S2] Priority = wcount × (1 + max_depth) ensures inner-loop variables
;        beat outer-scope temporaries for register slots.
;   [S3] Selection sort on ≤256 entries keeps the sort O(N²) but fast in
;        practice (no allocation, no pointer chasing).
;   [S4] Conditional spill/restore: ra_emit_spill_all only emits store
;        instructions for slots whose ra_slot_var_va is non-zero (occupied).
;   [S5] ra_sync_pinned re-synchronises an RA register after R15/R14
;        loop-counter flushes, preventing stale values in RA slots.
; ============================================================
bits 64
%include "rex_defs.inc"

%define RA_NONE      0xFF    ; slot: variable not register-allocated
%define RA_POOL      4       ; R8..R11
%define RA_NAME_LEN  32      ; max identifier length (matches VAR_ENTRY name field)
%define RA_SCAN_MAX  256     ; max unique identifiers in pre-scan table

; ---- Exports ----
global ra_prescan, ra_linear_scan, ra_on_var_add
global ra_emit_init, ra_emit_spill_all, ra_emit_restore_all, ra_sync_pinned
global ra_alloc_reg, ra_slot_var_va, ra_alloc_done, ra_tmp_slot
global ra_load_modrm, ra_store_modrm, ra_spill_modrm

; ---- Imports ----
extern emit_b, emit_d, var_table, var_count

; ============================================================
; .data — per-slot encoding tables
; ============================================================
section .data

; mov rax, RN  →  4C 89 <modrm>
; ModRM = 11_regN_000  (regN in reg field, REX.R=1 extends to R8–R11, r/m=rax=0)
ra_load_modrm:
    db 0xC0   ; slot 0 = R8:  11_000_000
    db 0xC8   ; slot 1 = R9:  11_001_000
    db 0xD0   ; slot 2 = R10: 11_010_000
    db 0xD8   ; slot 3 = R11: 11_011_000

; mov RN, rax  →  49 89 <modrm>
; ModRM = 11_000_rmN  (rax in reg=0, rmN in r/m field, REX.B=1 extends to R8–R11)
ra_store_modrm:
    db 0xC0   ; slot 0 = R8:  11_000_000
    db 0xC1   ; slot 1 = R9:  11_000_001
    db 0xC2   ; slot 2 = R10: 11_000_010
    db 0xC3   ; slot 3 = R11: 11_000_011

; mov [addr32], RN  →  4C 89 <modrm> 25 addr32
; ModRM = 00_regN_100  (regN in reg field with REX.R=1; r/m=4 → SIB follows)
; SIB = 25 = 00_100_101  (scale=0, index=rsp=4=none, base=rbp=5→disp32 only)
ra_spill_modrm:
    db 0x04   ; slot 0 = R8:  00_000_100
    db 0x0C   ; slot 1 = R9:  00_001_100
    db 0x14   ; slot 2 = R10: 00_010_100
    db 0x1C   ; slot 3 = R11: 00_011_100

; xor RNd, RNd  →  45 31 <modrm>
; ModRM = 11_regN_rmN  (same register in both fields, REX.R=1 and REX.B=1 → 45)
ra_zero_modrm:
    db 0xC0   ; slot 0 = R8d: 11_000_000
    db 0xC9   ; slot 1 = R9d: 11_001_001
    db 0xD2   ; slot 2 = R10d:11_010_010
    db 0xDB   ; slot 3 = R11d:11_011_011

; ============================================================
; .bss — compiler-side state (not emitted into user binary)
; ============================================================
section .bss

; ---- Pre-scan identifier table ----
prescan_names:   resb RA_NAME_LEN * RA_SCAN_MAX   ; 8 KB: NUL-terminated names
prescan_wcount:  resq RA_SCAN_MAX                  ; weighted use count per entry
prescan_nc:      resq 1                            ; number of unique identifiers found
prescan_reg:     resb RA_SCAN_MAX                  ; RA_NONE or slot 0..3 after linear_scan

; ---- [S1] Interval tracking for conflict detection ----
prescan_first:   resq RA_SCAN_MAX                  ; first use byte position in source
prescan_last:    resq RA_SCAN_MAX                  ; last use byte position in source
prescan_ucnt:    resw RA_SCAN_MAX                  ; raw use count (not weighted)
prescan_mdepth:  resb RA_SCAN_MAX                  ; max nesting depth across all uses

; ---- [S2] Sort indices for priority ordering ----
ra_sorted_idx:   resw RA_SCAN_MAX                  ; entry indices sorted by priority

; ---- [S6] Function-call position bitmap (1 byte per source byte, max 64KB) ----
; If prescan_call_map[i] = 1, source byte i is an '@' call operator
RA_CALL_MAP_SIZE equ 65536
prescan_call_map: resb RA_CALL_MAP_SIZE             ; 64 KB: call-position bitmap

; ---- Public allocation outputs ----
ra_alloc_reg:    resb 256          ; var_idx → slot (RA_NONE=0xFF if unallocated)
ra_slot_var_va:  resq RA_POOL      ; slot → runtime var VA (0 = slot unused)
ra_alloc_done:   resb 1            ; set to 1 after ra_linear_scan completes

; ---- Temp slot during linear scan (not a real VA) ----
ra_slot_pidx:    resq RA_POOL      ; slot → prescan entry index (temporary)

; ---- Shared scratch for inline RA checks in codegen.asm ----
ra_tmp_slot:     resb 1            ; temporary slot index during emit sequences

; ============================================================
; .text
; ============================================================
section .text

; ============================================================
; ra_prescan(rdi=src_buf, rsi=src_size)
;
; [S1] Enhanced prescan: walks the source buffer for identifiers
; and accumulates per-variable metrics:
;   - weighted use count (1 << min(depth, 6)) for each occurrence
;   - first/last use byte positions (interval endpoints)
;   - raw use count and maximum nesting depth
;
; Must be called before lexer_init.
; ============================================================
ra_prescan:
    push    rbx
    push    rcx
    push    rdx
    push    r8
    push    r9
    push    r10
    push    r11
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi            ; r12 = src buffer
    mov     r13, rsi            ; r13 = src size
    xor     r14, r14            ; r14 = byte position in source
    xor     r15, r15            ; r15 = current indent depth (0..7)
    mov     qword [prescan_nc], 0

    ; Zero all prescan arrays
    push    rdi
    ; wcount (256 qwords)
    lea     rdi, [prescan_wcount]
    xor     eax, eax
    mov     ecx, RA_SCAN_MAX
    rep     stosq
    ; reg (256 bytes)
    lea     rdi, [prescan_reg]
    mov     al, RA_NONE
    mov     ecx, RA_SCAN_MAX
    rep     stosb
    ; first (256 qwords)
    lea     rdi, [prescan_first]
    xor     eax, eax
    mov     ecx, RA_SCAN_MAX
    rep     stosq
    ; last (256 qwords)
    lea     rdi, [prescan_last]
    mov     ecx, RA_SCAN_MAX
    rep     stosq
    ; ucnt (256 words)
    lea     rdi, [prescan_ucnt]
    mov     ecx, RA_SCAN_MAX
    rep     stosw
    ; mdepth (256 bytes)
    lea     rdi, [prescan_mdepth]
    xor     eax, eax
    mov     ecx, RA_SCAN_MAX
    rep     stosb
    ; [S6] call map (64KB, zero)
    lea     rdi, [prescan_call_map]
    xor     eax, eax
    mov     ecx, RA_CALL_MAP_SIZE / 4
    rep     stosd
    pop     rdi

.next:
    cmp     r14, r13
    jge     .done
    movzx   eax, byte [r12 + r14]

    ; ---- Newline: count indent of next line ----
    cmp     al, 0x0A
    jne     .not_nl
    inc     r14
    xor     rcx, rcx
.count_sp:
    cmp     r14, r13
    jge     .done
    movzx   eax, byte [r12 + r14]
    cmp     al, ' '
    je      .sp_one
    cmp     al, 0x09        ; tab
    je      .sp_one
    jmp     .sp_done
.sp_one:
    inc     rcx
    inc     r14
    jmp     .count_sp
.sp_done:
    shr     rcx, 2          ; depth = spaces / 4
    cmp     rcx, 6
    jle     .depth_ok
    mov     rcx, 6          ; cap at 6
.depth_ok:
    mov     r15, rcx
    jmp     .next

.not_nl:
    ; ---- Comment: skip to end of line ----
    cmp     al, '#'
    jne     .not_comment
.skip_comment:
    inc     r14
    cmp     r14, r13
    jge     .done
    movzx   eax, byte [r12 + r14]
    cmp     al, 0x0A
    jne     .skip_comment
    jmp     .next

.not_comment:
    ; ---- String/char literal: skip ----
    cmp     al, '"'
    je      .str_open
    cmp     al, 0x27        ; single quote
    jne     .not_str
.str_open:
    mov     bl, al          ; bl = closing quote char
    inc     r14
.str_body:
    cmp     r14, r13
    jge     .done
    movzx   eax, byte [r12 + r14]
    inc     r14
    cmp     al, 0x0A
    je      .next           ; unterminated: treat as end
    cmp     al, 0x5C        ; backslash → escape
    je      .str_esc
    cmp     al, bl
    je      .next           ; closing quote
    jmp     .str_body
.str_esc:
    cmp     r14, r13
    jge     .done
    inc     r14             ; skip escaped char
    jmp     .str_body

.not_str:
    ; ---- [S6] Function call operator '@': mark position ----
    cmp     al, '@'
    jne     .not_call
    ; Record call position in bitmap (cap at 64KB)
    cmp     r14, RA_CALL_MAP_SIZE
    jge     .not_call
    mov     byte [prescan_call_map + r14], 1
.not_call:
    ; ---- Identifier start: letter or underscore ----
    cmp     al, '_'
    je      .ident
    cmp     al, 'a'
    jl      .maybe_upper
    cmp     al, 'z'
    jle     .ident
    jmp     .maybe_upper
.maybe_upper:
    cmp     al, 'A'
    jl      .not_ident_start
    cmp     al, 'Z'
    jle     .ident
.not_ident_start:
    inc     r14
    jmp     .next

.ident:
    ; Collect identifier: r9=start, r10=length
    mov     r9, r14
    xor     r10, r10
.ident_loop:
    cmp     r14, r13
    jge     .ident_done
    movzx   eax, byte [r12 + r14]
    ; valid: a-z, A-Z, 0-9, _
    cmp     al, '_'
    je      .ident_ok
    cmp     al, 'a'
    jl      .ident_chk_upper
    cmp     al, 'z'
    jle     .ident_ok
.ident_chk_upper:
    cmp     al, 'A'
    jl      .ident_chk_digit
    cmp     al, 'Z'
    jle     .ident_ok
.ident_chk_digit:
    cmp     al, '0'
    jl      .ident_done
    cmp     al, '9'
    jg      .ident_done
.ident_ok:
    inc     r14
    inc     r10
    cmp     r10, RA_NAME_LEN - 1
    jl      .ident_loop
    ; Name too long: drain the rest
.drain:
    cmp     r14, r13
    jge     .ident_done
    movzx   eax, byte [r12 + r14]
    cmp     al, '_'
    je      .drain_ok
    cmp     al, 'a'
    jl      .drain_chk_up
    cmp     al, 'z'
    jle     .drain_ok
.drain_chk_up:
    cmp     al, 'A'
    jl      .drain_chk_dig
    cmp     al, 'Z'
    jle     .drain_ok
.drain_chk_dig:
    cmp     al, '0'
    jl      .ident_done
    cmp     al, '9'
    jg      .ident_done
.drain_ok:
    inc     r14
    jmp     .drain

.ident_done:
    ; r9=start, r10=length. Find or insert in prescan_names.
    mov     rbx, [prescan_nc]   ; number of entries so far
    xor     rdx, rdx            ; search index
.find_loop:
    cmp     rdx, rbx
    jge     .insert_new
    ; Compare src[r9..r9+r10-1] with prescan_names[rdx*32]
    push    rdx
    imul    rdx, RA_NAME_LEN
    lea     r11, [prescan_names + rdx]
    pop     rdx
    ; Compute src_base = r12 + r9 for character comparison
    push    r8
    lea     r8, [r12 + r9]      ; r8 = src base address
    push    rcx
    xor     rcx, rcx
.cmp_chars:
    cmp     rcx, r10
    jge     .cmp_end_match      ; all chars matched, check NUL
    movzx   eax, byte [r8 + rcx]
    cmp     al, byte [r11 + rcx]
    jne     .cmp_ne
    inc     rcx
    jmp     .cmp_chars
.cmp_end_match:
    ; Stored name must have NUL at position r10
    movzx   eax, byte [r11 + rcx]
    test    al, al
    jz      .cmp_matched        ; full match
.cmp_ne:
    pop     rcx
    pop     r8
    inc     rdx
    jmp     .find_loop

.cmp_matched:
    pop     rcx
    pop     r8
    ; Update wcount[rdx] += 1 << depth
    mov     rax, 1
    mov     rcx, r15            ; depth
    shl     rax, cl             ; weight = 1 << depth
    add     [prescan_wcount + rdx*8], rax
    ; [S1] Update interval: last_use = current position (after ident end)
    mov     rax, r14
    mov     [prescan_last + rdx*8], rax
    ; [S1] Increment raw use count
    inc     word [prescan_ucnt + rdx*2]
    ; [S1] Update max depth
    cmp     r15b, byte [prescan_mdepth + rdx]
    jle     .no_new_depth
    mov     byte [prescan_mdepth + rdx], r15b
.no_new_depth:
    jmp     .next

.insert_new:
    ; New entry — add if table not full
    cmp     rbx, RA_SCAN_MAX
    jge     .next
    ; Copy name to prescan_names[rbx * RA_NAME_LEN]
    push    rcx
    push    rdx
    mov     rdx, rbx
    imul    rdx, RA_NAME_LEN
    lea     r11, [prescan_names + rdx]
    pop     rdx
    ; Compute src_base = r12 + r9 for character copy
    push    r8
    lea     r8, [r12 + r9]      ; r8 = src base address
    xor     rcx, rcx
.copy_name:
    cmp     rcx, r10
    jge     .copy_done
    cmp     rcx, RA_NAME_LEN - 1
    jge     .copy_done
    movzx   eax, byte [r8 + rcx]
    mov     [r11 + rcx], al
    inc     rcx
    jmp     .copy_name
.copy_done:
    mov     byte [r11 + rcx], 0  ; NUL-terminate
    pop     r8
    pop     rcx
    ; Set initial wcount[rbx] = 1 << depth
    mov     rax, 1
    mov     rcx, r15
    shl     rax, cl
    mov     [prescan_wcount + rbx*8], rax
    ; [S1] Set interval endpoints = current position
    mov     rax, r14
    mov     [prescan_first + rbx*8], rax
    mov     [prescan_last + rbx*8], rax
    ; [S1] Raw use count = 1
    mov     word [prescan_ucnt + rbx*2], 1
    ; [S1] Max depth = current depth
    mov     byte [prescan_mdepth + rbx], r15b
    ; prescan_reg[rbx] already = RA_NONE (zeroed above)
    inc     qword [prescan_nc]
    jmp     .next

.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ============================================================
; ra_linear_scan
;
; [S2] Interval-based Linear Scan with Conflict Detection.
;
; 1. Compute priority = wcount * (1 + max_depth) for each entry.
; 2. Sort entries by priority descending (selection sort).
; 3. Greedy allocation: for each entry in priority order, try
;    each slot 0..3.  A slot is viable only if no already-assigned
;    variable has an overlapping [first_use, last_use] interval.
;    First viable slot wins.  If none viable → not allocated.
;
; Must be called after ra_prescan and before the main parse.
; ============================================================
ra_linear_scan:
    push    rbx
    push    rcx
    push    rdx
    push    r8
    push    r9
    push    r10
    push    r11
    push    r12
    push    r13
    push    r14
    push    r15

    mov     rcx, [prescan_nc]   ; number of unique identifiers
    test    rcx, rcx
    jz      .ls_done

    ; ============================================================
    ; Step 1: Build sorted index array by priority (descending)
    ; ============================================================
    ; Initialize ra_sorted_idx[i] = i
    xor     rdx, rdx
.init_idx:
    cmp     rdx, rcx
    jge     .sort_begin
    mov     word [ra_sorted_idx + rdx*2], dx
    inc     rdx
    jmp     .init_idx

.sort_begin:
    ; Selection sort: for i = 0..N-2, find max in [i..N-1], swap to i
    ; r8 = i (outer loop index)
    xor     r8, r8
.sort_outer:
    mov     rax, rcx
    dec     rax
    cmp     r8, rax
    jge     .sort_done

    ; r9 = max_idx (starts at i)
    mov     r9, r8
    ; Compute priority[max_idx]
    movzx   r10d, word [ra_sorted_idx + r9*2]
    mov     rax, [prescan_wcount + r10*8]
    movzx   r11d, byte [prescan_mdepth + r10]
    inc     r11
    imul    rax, r11            ; priority[max_idx]
    mov     r12, rax            ; r12 = max_priority

    ; rdx = j (inner loop)
    mov     rdx, r8
    inc     rdx
.sort_inner:
    cmp     rdx, rcx
    jge     .sort_inner_done
    ; Compute priority[j]
    movzx   r10d, word [ra_sorted_idx + rdx*2]
    mov     rax, [prescan_wcount + r10*8]
    movzx   r11d, byte [prescan_mdepth + r10]
    inc     r11
    imul    rax, r11
    cmp     rax, r12
    jle     .sort_next
    ; New max found
    mov     r9, rdx
    mov     r12, rax
.sort_next:
    inc     rdx
    jmp     .sort_inner
.sort_inner_done:
    ; Swap ra_sorted_idx[i] and ra_sorted_idx[max_idx]
    cmp     r8, r9
    je      .sort_no_swap
    movzx   eax, word [ra_sorted_idx + r8*2]
    movzx   r10d, word [ra_sorted_idx + r9*2]
    mov     word [ra_sorted_idx + r8*2], r10w
    mov     word [ra_sorted_idx + r9*2], ax
.sort_no_swap:
    inc     r8
    jmp     .sort_outer
.sort_done:

    ; ============================================================
    ; Step 2: Greedy allocation with interval conflict detection
    ; ============================================================
    ; Initialize ra_slot_pidx[0..3] = -1 (unoccupied sentinel)
    mov     qword [ra_slot_pidx + 0*8], -1
    mov     qword [ra_slot_pidx + 1*8], -1
    mov     qword [ra_slot_pidx + 2*8], -1
    mov     qword [ra_slot_pidx + 3*8], -1

    ; Process entries in priority order
    ; r13 = sort index
    xor     r13, r13
.alloc_loop:
    cmp     r13, rcx
    jge     .alloc_done

    ; r14 = prescan entry index
    movzx   r14d, word [ra_sorted_idx + r13*2]
    ; Skip if zero uses
    cmp     qword [prescan_wcount + r14*8], 0
    je      .alloc_next

    ; [S6] Skip if interval spans a function call ('@' operator)
    mov     rax, [prescan_first + r14*8]
    mov     rdx, [prescan_last + r14*8]
    ; Clamp to call-map range
    cmp     rax, RA_CALL_MAP_SIZE
    jge     .alloc_next
    cmp     rdx, RA_CALL_MAP_SIZE
    jl      .call_map_ok
    mov     rdx, RA_CALL_MAP_SIZE - 1
.call_map_ok:
    ; Scan call map for first_use..last_use
    push    rcx
    mov     rcx, rax
.call_check:
    cmp     rcx, rdx
    jg      .call_clean
    cmp     byte [prescan_call_map + rcx], 0
    jne     .call_found
    inc     rcx
    jmp     .call_check
.call_found:
    pop     rcx
    jmp     .alloc_next         ; spans a call → don't allocate
.call_clean:
    pop     rcx

    ; Try each slot 0..3
    xor     r15, r15            ; r15 = slot index
.slot_loop:
    cmp     r15, RA_POOL
    jge     .alloc_next         ; no free slot found for this variable

    ; Check if slot is free (sentinel = -1)
    mov     rax, [ra_slot_pidx + r15*8]
    cmp     rax, -1
    jne     .slot_occupied

    ; ---- [S1] Slot is free — check conflicts with all assigned vars ----
    xor     r8, r8              ; r8 = conflict flag
    xor     r9, r9              ; r9 = check index
.conflict_loop:
    cmp     r9, RA_POOL
    jge     .conflict_done
    cmp     r9, r15
    je      .conflict_next      ; skip self
    mov     rax, [ra_slot_pidx + r9*8]
    cmp     rax, -1
    je      .conflict_next      ; slot empty
    ; Interval overlap test:
    ;   conflict = (first[r14] <= last[rax]) AND (first[rax] <= last[r14])
    mov     r10, [prescan_first + r14*8]
    mov     r11, [prescan_last + rax*8]
    cmp     r10, r11
    jg      .conflict_next      ; no overlap: our first > their last
    mov     r10, [prescan_first + rax*8]
    mov     r11, [prescan_last + r14*8]
    cmp     r10, r11
    jg      .conflict_next      ; no overlap: their first > our last
    ; Conflict detected
    mov     r8, 1
    jmp     .conflict_done
.conflict_next:
    inc     r9
    jmp     .conflict_loop
.conflict_done:
    test    r8, r8
    jnz     .slot_occupied      ; conflict → try next slot

    ; No conflict — assign variable to this slot
    mov     [ra_slot_pidx + r15*8], r14
    mov     byte [prescan_reg + r14], r15b
    jmp     .alloc_next

.slot_occupied:
    inc     r15
    jmp     .slot_loop

.alloc_next:
    inc     r13
    jmp     .alloc_loop

.alloc_done:

    ; ============================================================
    ; Step 3: Prepare output arrays
    ; ============================================================
    ; Zero ra_alloc_reg (256 bytes) — will be filled by ra_on_var_add
    push    rdi
    lea     rdi, [ra_alloc_reg]
    mov     al, RA_NONE
    mov     ecx, 256
    rep     stosb
    ; Zero ra_slot_var_va (4 qwords) — will be filled by ra_on_var_add
    lea     rdi, [ra_slot_var_va]
    xor     eax, eax
    mov     ecx, RA_POOL
    rep     stosq
    pop     rdi

    mov     byte [ra_alloc_done], 1

.ls_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ============================================================
; ra_on_var_add(rdi=var_idx, rsi=name_ptr)
;
; Called by var_add() after a new variable is declared.
; Looks up name_ptr in prescan_names; if it has a slot, records:
;   ra_alloc_reg[var_idx] = slot
;   ra_slot_var_va[slot]  = VAR_STORAGE_BASE + var_idx * 64
;
; Only allocates global (non-rbp) integer variables.
; ============================================================
ra_on_var_add:
    push    rbx
    push    rcx
    push    rdx
    push    r8
    push    r9

    ; Search prescan_names for name_ptr match
    mov     r8, rdi             ; r8 = var_idx
    mov     r9, rsi             ; r9 = name_ptr
    mov     rcx, [prescan_nc]
    xor     rdx, rdx            ; rdx = search index
.search:
    cmp     rdx, rcx
    jge     .not_found
    cmp     byte [prescan_reg + rdx], RA_NONE
    je      .search_next        ; this entry wasn't allocated a slot
    ; Compare r9 (name_ptr) with prescan_names[rdx*32]
    push    rdx
    imul    rdx, RA_NAME_LEN
    lea     rbx, [prescan_names + rdx]
    pop     rdx
    push    rcx
    xor     rcx, rcx
.cmp2:
    movzx   eax, byte [r9 + rcx]
    movzx   r11d, byte [rbx + rcx]
    cmp     al, r11b
    jne     .cmp2_ne
    test    al, al
    jz      .cmp2_match         ; both NUL → full match
    inc     rcx
    jmp     .cmp2
.cmp2_ne:
    pop     rcx
.search_next:
    inc     rdx
    jmp     .search

.cmp2_match:
    pop     rcx
    ; Match found: rdx = prescan index, prescan_reg[rdx] = slot
    movzx   eax, byte [prescan_reg + rdx]
    ; Record ra_alloc_reg[var_idx] = slot
    mov     [ra_alloc_reg + r8], al
    ; Record ra_slot_var_va[slot] = VAR_STORAGE_BASE + var_idx*64
    movzx   rdx, al             ; rdx = slot
    mov     rax, r8
    shl     rax, 6              ; var_idx * 64
    add     rax, VAR_STORAGE_BASE
    mov     [ra_slot_var_va + rdx*8], rax

.not_found:
    pop     r9
    pop     r8
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; ============================================================
; ra_emit_init
;
; Emits  xor r8d,r8d; xor r9d,r9d; xor r10d,r10d; xor r11d,r11d
; at the start of the user program (12 bytes total).
; This initializes RA registers to 0, matching the BSS-zeroed
; variable storage.  Called from main.asm after ra_linear_scan.
; ============================================================
ra_emit_init:
    push    rax
    push    rcx
    ; Emit xor RNd, RNd for all 4 slots (unconditional; harmless if unused)
    xor     ecx, ecx
.init_loop:
    cmp     ecx, RA_POOL
    jge     .init_done
    ; Emit: 45 31 <modrm>  (REX.W=0, REX.R=1, REX.B=1 → 45)
    mov     al, 0x45
    call    emit_b
    mov     al, 0x31
    call    emit_b
    movzx   eax, byte [ra_zero_modrm + rcx]
    call    emit_b
    inc     ecx
    jmp     .init_loop
.init_done:
    pop     rcx
    pop     rax
    ret

; ============================================================
; ra_emit_spill_all
;
; [S4] Conditional spill: emits  mov [var_va], RN  only for
; occupied RA slots (ra_slot_var_va[slot] != 0).
;
; Called from emit_call_abs BEFORE the runtime call to protect
; RA registers from being clobbered by the runtime blob.
; Each store is 8 bytes: 4C 89 <modrm> 25 <addr32>
; ============================================================
ra_emit_spill_all:
    push    rax
    push    rbx
    push    rcx
    push    rdx

    xor     ecx, ecx            ; slot 0..3
.spill_loop:
    cmp     ecx, RA_POOL
    jge     .spill_done
    mov     rax, [ra_slot_var_va + rcx*8]
    test    rax, rax
    jz      .spill_next         ; slot unused
    ; Emit: 4C 89 <spill_modrm[slot]> 25 <var_va_low32>
    mov     rdx, rax            ; save var_va
    push    rcx                 ; save slot
    mov     al, 0x4C            ; REX.W|REX.R
    call    emit_b
    mov     al, 0x89            ; MOV r/m64, r64
    call    emit_b
    pop     rcx                 ; restore slot
    push    rcx
    movzx   eax, byte [ra_spill_modrm + rcx]
    call    emit_b
    mov     al, 0x25            ; SIB: disp32 only
    call    emit_b
    mov     eax, edx            ; var_va low 32 bits
    call    emit_d
    pop     rcx
.spill_next:
    inc     ecx
    jmp     .spill_loop
.spill_done:
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    ret

; ============================================================
; ra_emit_restore_all
;
; [S4] Conditional restore: emits  mov RN, [var_va]  only for
; occupied RA slots (ra_slot_var_va[slot] != 0).
;
; Called from emit_call_abs AFTER the runtime call to reload
; RA registers that were clobbered.
; Each load is 8 bytes: 4C 8B <spill_modrm> 25 <addr32>
; ============================================================
ra_emit_restore_all:
    push    rax
    push    rbx
    push    rcx
    push    rdx

    xor     ecx, ecx            ; slot 0..3
.rest_loop:
    cmp     ecx, RA_POOL
    jge     .rest_done
    mov     rax, [ra_slot_var_va + rcx*8]
    test    rax, rax
    jz      .rest_next          ; slot unused
    mov     rdx, rax            ; save var_va
    push    rcx
    ; Emit: 4C 8B <spill_modrm[slot]> 25 <var_va_low32>
    mov     al, 0x4C
    call    emit_b
    mov     al, 0x8B            ; MOV r64, r/m64
    call    emit_b
    pop     rcx
    push    rcx
    movzx   eax, byte [ra_spill_modrm + rcx]
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, edx
    call    emit_d
    pop     rcx
.rest_next:
    inc     ecx
    jmp     .rest_loop
.rest_done:
    pop     rdx
    pop     rcx
    pop     rbx
    pop     rax
    ret

; ============================================================
; ra_sync_pinned(rdi=var_va)
;
; [S5] If var_va refers to a globally RA-allocated variable, emits
;   mov RN, [var_va]
; to synchronise the RA register from memory.
;
; Called after R15/R14 loop-counter flushes in codegen_emit_for_end
; and codegen_emit_while_end, so that RA registers for variables
; that were temporarily held in R15/R14 stay coherent.
;
; Does nothing if:
;   - var_va is -1 (no pinned var)
;   - var_va is not a valid global address
;   - var is not RA-allocated
; ============================================================
ra_sync_pinned:
    push    rax
    push    rcx
    push    rdx

    ; Quick reject: -1 means "no variable"
    cmp     rdi, -1
    je      .sync_done
    ; Must be a valid global var address: >= VAR_STORAGE_BASE
    mov     rax, rdi
    sub     rax, VAR_STORAGE_BASE
    jl      .sync_done
    ; Must be 64-byte aligned
    test    eax, 63
    jnz     .sync_done
    ; var_idx = (var_va - VAR_STORAGE_BASE) >> 6
    shr     rax, 6
    cmp     rax, 256
    jge     .sync_done
    ; Check allocation
    movzx   ecx, byte [ra_alloc_reg + rax]
    cmp     cl, RA_NONE
    je      .sync_done
    ; Emit: 4C 8B <spill_modrm[slot]> 25 <var_va_low32>
    mov     edx, edi            ; var_va low 32 bits
    push    rcx
    mov     al, 0x4C
    call    emit_b
    mov     al, 0x8B
    call    emit_b
    pop     rcx
    push    rcx
    movzx   eax, byte [ra_spill_modrm + rcx]
    call    emit_b
    mov     al, 0x25
    call    emit_b
    mov     eax, edx
    call    emit_d
    pop     rcx
.sync_done:
    pop     rdx
    pop     rcx
    pop     rax
    ret

; ============================================================
; ra_get_slot(rdi=var_va) → rax = slot (RA_NONE if unallocated)
;
; Converts a runtime var VA to a slot index.
; Used by codegen.asm inline checks via call (but the
; performance-critical path uses inline code instead).
; ============================================================
ra_get_slot:
    mov     rax, rdi
    sub     rax, VAR_STORAGE_BASE
    jl      .no_slot
    test    eax, 63
    jnz     .no_slot
    shr     rax, 6
    cmp     rax, 256
    jge     .no_slot
    movzx   eax, byte [ra_alloc_reg + rax]
    ret
.no_slot:
    mov     eax, RA_NONE
    ret
