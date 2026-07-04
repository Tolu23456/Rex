; ============================================================
; codegen/ra.asm — Linear Scan Register Allocator for Rex
;
; OVERVIEW
; --------
; Two-phase approach:
;   Phase 1  ra_prescan(rdi=src, rsi=size)
;            Walk source bytes before the main lexer runs.
;            For every identifier, accumulate a spill-cost weight:
;               weight += 1 << min(indent_depth, 6)
;            giving inner-loop variables exponentially higher priority.
;
;   Phase 2  ra_linear_scan
;            Pick the top-4 identifiers by weight → assign
;            slots 0..3 = R8..R11.  Fills prescan_reg[].
;
;   Phase 3  ra_on_var_add(rdi=var_idx, rsi=name_ptr)
;            Called from var_add() when a variable is declared.
;            Looks up the name in the prescan table; if it was
;            allocated a slot, records:
;               ra_alloc_reg[var_idx] = slot
;               ra_slot_var_va[slot]  = VAR_STORAGE_BASE + idx*64
;
; INTEGRATION (codegen.asm / main.asm)
; -------------------------------------
;   codegen_emit_mov_rax_var   — checks ra_alloc_reg before abs load
;   codegen_emit_store_rax_to_var — checks ra_alloc_reg before abs store
;   emit_call_abs              — calls ra_emit_spill_all / ra_emit_restore_all
;   for/while loop exit        — calls ra_sync_pinned after R15/R14 flush
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

; ---- Public allocation outputs ----
ra_alloc_reg:    resb 256          ; var_idx → slot (RA_NONE=0xFF if unallocated)
ra_slot_var_va:  resq RA_POOL      ; slot → runtime var VA (0 = slot unused)
ra_alloc_done:   resb 1            ; set to 1 after ra_linear_scan completes

; ---- Shared scratch for inline RA checks in codegen.asm ----
ra_tmp_slot:     resb 1            ; temporary slot index during emit sequences

; ============================================================
; .text
; ============================================================
section .text

; ============================================================
; ra_prescan(rdi=src_buf, rsi=src_size)
;
; Scans the source buffer for identifiers and accumulates
; weighted use counts (weight = 1 << min(indent_depth, 6)).
; Does NOT disturb the main lexer — it uses its own cursor.
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

    ; Zero prescan_wcount (256 qwords) and prescan_reg (256 bytes)
    push    rdi
    lea     rdi, [prescan_wcount]
    xor     eax, eax
    mov     ecx, RA_SCAN_MAX
    rep     stosq
    lea     rdi, [prescan_reg]
    mov     al, RA_NONE
    mov     ecx, RA_SCAN_MAX
    rep     stosb
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
    push    rcx
    xor     rcx, rcx
.cmp_chars:
    cmp     rcx, r10
    jge     .cmp_end_match      ; all chars matched, check NUL
    movzx   eax, byte [r12 + r9 + rcx]
    movzx   r8d, byte [r11 + rcx]
    cmp     al, r8b
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
    inc     rdx
    jmp     .find_loop

.cmp_matched:
    pop     rcx
    ; Update wcount[rdx] += 1 << depth
    mov     rax, 1
    mov     rcx, r15            ; depth
    shl     rax, cl             ; weight = 1 << depth
    add     [prescan_wcount + rdx*8], rax
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
    xor     rcx, rcx
.copy_name:
    cmp     rcx, r10
    jge     .copy_done
    cmp     rcx, RA_NAME_LEN - 1
    jge     .copy_done
    movzx   eax, byte [r12 + r9 + rcx]
    mov     [r11 + rcx], al
    inc     rcx
    jmp     .copy_name
.copy_done:
    mov     byte [r11 + rcx], 0  ; NUL-terminate
    pop     rcx
    ; Set initial wcount[rbx] = 1 << depth
    mov     rax, 1
    mov     rcx, r15
    shl     rax, cl
    mov     [prescan_wcount + rbx*8], rax
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
; Selects the top-4 identifiers by prescan_wcount and assigns
; them to slots 0..3 (R8..R11).  Fills prescan_reg[].
; Must be called after ra_prescan and before the main parse.
; ============================================================
ra_linear_scan:
    push    rbx
    push    rcx
    push    rdx
    push    r8
    push    r9
    push    r10

    mov     rcx, [prescan_nc]   ; number of unique identifiers
    test    rcx, rcx
    jz      .ls_done

    ; For each slot 0..3, find the identifier with the highest
    ; wcount that hasn't been assigned yet (mark with prescan_reg != RA_NONE).
    ; Use -1 as the "used" sentinel in a local tmp.
    ; Simple O(N*K) approach: K=4 passes over N entries.
    xor     r10, r10            ; slot index = 0
.slot_loop:
    cmp     r10, RA_POOL
    jge     .ls_done

    ; Find max wcount among entries with prescan_reg[i] == RA_NONE
    mov     qword r9, 0         ; best_wcount = 0
    mov     rbx, -1             ; best_idx = -1
    xor     rdx, rdx            ; i = 0
.scan:
    cmp     rdx, rcx
    jge     .scan_done
    cmp     byte [prescan_reg + rdx], RA_NONE
    jne     .scan_next          ; already assigned
    cmp     qword [prescan_wcount + rdx*8], 0
    je      .scan_next          ; zero weight (never actually used)
    cmp     [prescan_wcount + rdx*8], r9
    jle     .scan_next
    mov     r9, [prescan_wcount + rdx*8]
    mov     rbx, rdx
.scan_next:
    inc     rdx
    jmp     .scan
.scan_done:
    cmp     rbx, -1
    je      .ls_done            ; no more candidates

    ; Assign slot r10 to prescan entry rbx
    mov     r8b, r10b
    mov     [prescan_reg + rbx], r8b

    inc     r10
    jmp     .slot_loop

.ls_done:
    ; Zero ra_alloc_reg (256 bytes) and ra_slot_var_va (4 qwords)
    push    rdi
    lea     rdi, [ra_alloc_reg]
    mov     al, RA_NONE
    mov     ecx, 256
    rep     stosb
    lea     rdi, [ra_slot_var_va]
    xor     eax, eax
    mov     ecx, RA_POOL
    rep     stosq
    pop     rdi

    mov     byte [ra_alloc_done], 1

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
; (Protocol locals use rbp-relative addresses; the emit functions
;  guard against those via var_addr_is_rbp, so double-allocation
;  is harmless but we skip it here for cleanliness.)
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
; Emits  mov [var_va], RN  for each occupied RA slot.
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
; Emits  mov RN, [var_va]  for each occupied RA slot.
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
; If var_va refers to a globally RA-allocated variable, emits
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
