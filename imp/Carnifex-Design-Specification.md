---
title: "Carnifex: A Region-Generational Ownership Model for Whole-Program Memory Safety in Rex"
author: "Design collaboration: Tolu, with Claude (Anthropic) as co-designer"
date: "July 2026 — Design Specification v1.0"
geometry: margin=1in
fontsize: 11pt
toc: true
toc-depth: 2
numbersections: true
colorlinks: true
linkcolor: blue
---

\newpage

# Abstract

We present **Carnifex**, a static analysis and runtime safety mechanism for the Rex programming language, designed to provide memory- and resource-safety guarantees comparable in spirit to Rust's borrow checker while diverging deliberately in mechanism. Where Rust's checker is a purely static, flow-sensitive prover that rejects any program it cannot verify, Carnifex is a *hybrid* system: it proves safety statically wherever possible and falls back to a cheap, deterministic runtime check — a single generation-counter comparison — wherever static proof is unavailable. Carnifex is built from four orthogonal per-variable properties (pointer, region identity, aliasing capability, and binding discipline) layered on top of Rex's existing configurable memory-management (`mm`) and garbage-collection (`gc`) scopes. Two structural decisions distinguish Carnifex from Rust's model: ownership bindings are *pinned for life* (never transferred between variables, only established at construction), and release points must be *statically identical on every control-flow path*. Together these eliminate two of the three analyses that make Rust's checker difficult to implement — move-checking and unwind-table-based destructor sequencing — while preserving a comparable safety envelope for the subset of Rex's allocation modes (`arena`, `stack`, `pool`, `static`) where dangling references are actually possible. Garbage-collected scopes (`heap`, `gc`) are explicitly outside Carnifex's jurisdiction, as the collector already provides an equivalent guarantee by construction. This document specifies the model in full, compares it formally against Rust's borrow checker, and grounds an implementation roadmap in the current state of the `rexc` compiler's intermediate representation.

\newpage

# Introduction

Rex is a systems programming language compiled directly to x86-64 machine code by a self-hosted compiler (`rexc`) written entirely in NASM assembly, with no dependency on libc or an external backend such as LLVM. As of this writing, `rexc` implements a lexer, parser, symbol/type registry, an IR generator with a register allocator and peephole/constant-folding optimizer, and a direct x86-64 code generator. The intermediate representation is presently scalar and arithmetic-only: it has no opcodes for function calls, structured data, containers, or memory-management scopes. Those features exist today only as design specification.

Rex's design already diverges from mainstream systems languages in several respects relevant to this document:

- Booleans are **tristate** (`true` / `neutral` / `false`), implemented at the IR level as Łukasiewicz ternary logic (`min`/`max` over $\{-1, 0, 1\}$), not as a single bit.
- Memory management is **explicitly configurable per lexical scope** via `use mm <allocator> gc <collector>:` blocks, choosing independently from five allocator strategies (arena, pool, stack, heap, static) and five collector strategies (mark-sweep, reference-counting, generational, incremental, region-based).
- The language already has `#safe`/`#unsafe` decorators gating raw syscalls and pointer arithmetic, structurally analogous to Rust's `unsafe` blocks.
- References may be `null`, guarded at the type level by `?.` and `??` propagation operators, with compiler warnings — but not compile-time rejection — for unchecked use.

This last point is the specific gap that motivated the present work. Nullable references are a well-understood soundness hazard that Rust's `Option<T>` was designed to eliminate at the type level. Rex's existing design does not close this gap, and more broadly, Rex had no mechanism analogous to Rust's ownership/lifetime system to prevent dangling references into `arena`, `stack`, or `pool`-managed memory, where scope exit invalidates an entire allocation in a single bulk operation.

Carnifex is the result of a structured design collaboration undertaken to close this gap. Rather than transplanting Rust's borrow checker wholesale, the design process began from an explicit set of constraints supplied by Rex's designer — that the mechanism cover the *whole program*, not merely manually-managed scopes; that aliasing be *permissive* (region-typing style: many readers, one tracked writer) rather than Rust's strict single-writer-xor-many-readers rule; and that the system be *hybrid* rather than purely static, accepting a small runtime cost in exchange for never hard-rejecting a program the way Rust's checker can. Each subsequent design decision — the pinned-ownership model, the ban on cross-variable transfer, the requirement that release points be statically uniform across control-flow paths — was chosen to preserve internal consistency with these initial constraints, and in several cases produced simplifications (elimination of move-checking; unwind-table-free exception safety) that were not anticipated at the outset but fell out naturally from the constraint set.

The name *Carnifex* — Latin for "executioner" — was chosen to pair with *Rex* ("king"): the mechanism that carries out the sentence on invalid references on the King's behalf.

# Related Work

**Rust's borrow checker.** Rust enforces a single invariant — at any program point, a value has either exactly one live mutable reference or any number of live immutable references, and no reference outlives its referent — via a flow-sensitive static analysis (non-lexical lifetimes, NLL) built on region inference. Programs the analysis cannot verify are rejected at compile time. This yields a zero-runtime-cost guarantee but requires the checker to solve a fixpoint dataflow problem, and requires a companion move-checker to track linear ownership transfer, unified informally under the "borrow checker" name but implemented as two distinct passes.

**Vale's generational references.** Vale proposes generational references as a alternative to both garbage collection and borrow-checking: each heap object carries a generation counter, and every reference carries a copy of the generation it observed at creation; a mismatch on dereference indicates the object has been freed and reused, caught at runtime rather than compile time. Carnifex's fallback mechanism is directly descended from this idea, but with one structural optimization: because Rex's `mm` scopes already free memory in region-sized bulk operations rather than object-at-a-time, Carnifex places the generation counter on the *region*, not the *object*, reducing invalidation cost from $O(n)$ counter increments (one per live object) to $O(1)$ (one per region).

**Pony's reference capabilities.** Pony encodes aliasing and (in Pony's case, actor-isolation) discipline directly into the type of a reference (`iso`, `val`, `ref`, `box`, `tag`), checked statically. Carnifex's `capability` field (`read`/`write`) is a much-simplified relative of this idea, deliberately restricted to two states and checked at block granularity rather than Pony's finer capability lattice.

**Cyclone's region-based memory management.** Cyclone pioneered lexically-scoped memory regions with compile-time checking that pointers do not escape their region, using region-annotated types. Carnifex's region tree is structurally similar, but region membership in Carnifex is inferred from allocation site rather than written in the type signature, and unprovable escapes downgrade to a runtime check rather than being rejected outright.

# The Core Representation

Every variable in Rex, under Carnifex, is conceptually a 4-tuple:

$$v = (\text{pointer}, \text{region-id}, \text{capability}, \text{bind})$$

| Field | Domain | Meaning |
|---|---|---|
| `pointer` | machine address | location of the underlying data |
| `region-id` | node in the whole-program lexical scope tree | which allocation-lifetime this data belongs to; **read-only, fixed at allocation time** |
| `capability` | $\{\texttt{read}, \texttt{write}\}$ | aliasing discipline for this binding, surfaced via Rex's existing `:` mutability sigil |
| `bind` | $\{\texttt{owned}, \texttt{free}\}$ | responsibility for release; `owned` is the default, `free` is opt-in |

`region-id` and `capability` govern *whether a dereference is safe*. `bind` governs *who is responsible for reclamation*. The two concerns are orthogonal by design, mirroring the separation Rust maintains between its allocator API and its ownership system — except that in Carnifex both concerns are unified into one per-variable descriptor rather than split across a type-level ownership system and a separate allocator trait.

# The Region Model

## Definition

A **region** is a node in a tree constructed at compile time, isomorphic to the lexical nesting of scopes: one region per block, function body, `use mm/gc:` scope, and one root region for the whole program. This is a purely syntactic construct — it exists identically regardless of which allocator or collector is active for that scope.

## Coupling to allocator mode

For the four manually-managed allocator modes (`arena`, `stack`, `pool`, `static`), a region's *lexical* lifetime and its *physical* lifetime coincide exactly: the region's backing memory is bulk-released in a single operation at scope exit (arena reset, stack-frame pop, pool-slot batch release, or program-exit for `static`). In these modes, "region" and "unit of simultaneous invalidation" are the same fact viewed two ways.

For the two garbage-collected modes (`heap`, `gc`), this coupling is deliberately absent. An object's actual lifetime is governed by reachability, tracked by the active collector (mark-sweep, reference-counting, generational, incremental, or region-based GC — note this is a different, GC-internal notion of "region" from Carnifex's lexical regions), independent of the lexical block in which it was allocated. Consequently, **Carnifex performs no static or runtime checking whatsoever for `heap`/`gc`-scoped data**; the collector already provides an equivalent (in fact typically stronger, in the sense of never requiring a runtime tag check) safety guarantee by construction, and duplicating that guarantee would be pure overhead.

## Immutability of region membership

A variable's `region-id` cannot be reassigned. This is not merely a policy choice but a physical necessity: a region-id records where the allocator actually placed the underlying bytes, and no operation exists (or should exist) that relocates those bytes without an explicit copy. Any attempt to write to `region-id` directly is a compile-time error. The sole sanctioned mechanism for moving a value's *logical* presence from one region to another is to construct an independent copy in the destination region via the `.copy()` hook (Section 8).

The one legitimate exception is internal to garbage collectors that perform generational promotion (moving a surviving object from a young generation to an old one). This is a physical relocation, but it is performed transparently by the collector, which is independently responsible for fixing up all references to the moved object — a guarantee already implied by using a tracing collector at all, and outside Carnifex's scope by the reasoning above.

# The Capability Model

## Rule

Within a single lexical block, a value may have any number of simultaneous `read` (capability) references, or exactly one `write` reference, but not both. This is checked at **block granularity** — a coarser unit than Rust's per-instruction, flow-sensitive check — trading some precision (Carnifex will reject a small number of aliasing patterns Rust's NLL would accept) for a dramatically simpler implementation: no dataflow fixpoint is required, only a per-block scan.

## Surface syntax

Capability is expressed via Rex's pre-existing mutability sigil rather than new syntax: a bare declaration (`str name`) is a `read` capability; a colon-prefixed declaration (`:str name`) is a `write` capability. This is a semantic extension of a sigil that already existed for an adjacent purpose (mutability), rather than a new grammatical construct.

# Ownership and Binding

## Default and opt-in

Every variable is `owned` by default; `free` is an explicit, opt-in annotation. This mirrors Rust's own default (a `let` binding owns its value; borrowing is the opt-in operation via `&`), and was chosen specifically for that consistency with programmer expectations from other ownership-aware languages.

## Pinned ownership: no transfer

An `owned` binding's ownership is **fixed permanently to the variable that first establishes it** and can never be reassigned to another variable. This single rule has three significant, deliberate consequences:

1. **Function parameters are structurally always `free`.** A parameter is a newly-introduced variable; since ownership cannot transfer into it, it can only ever receive a borrowed view, regardless of the caller argument's own bind. This is a *structural* guarantee, not a rule requiring separate enforcement — it follows automatically from the ban on transfer.

2. **Construction is not transfer.** A `return` statement, or a value appearing directly as a function-call argument or collection-literal element, does not move ownership between two *existing* bindings — it establishes ownership for the first time at the point the value lands in its permanent binding (or is released immediately, as an unbound temporary, if it lands nowhere). This distinction — birth versus transfer — is what allows constructors (e.g., a hypothetical `open()` returning a `file`) to hand a freshly-created owned value up to a caller without violating the no-transfer rule.

3. **The move-checker is eliminated entirely.** Rust's borrow checker is, in practice, two analyses: an aliasing checker and a move checker, the latter responsible for tracking which variable currently owns a value and flagging use-after-move. Because ownership in Carnifex can never move between existing bindings, there is nothing for a move-checker to track. This is, along with the exception-safety simplification in Section 10, the primary implementation-complexity reduction Carnifex achieves relative to Rust's model.

## Statically uniform release points

An `owned` binding's release (Section 8) must occur at a program point that is **identical on every control-flow path** — implicit at the binding's own lexical scope exit, or via an explicit early-release statement (reusing Rex's already-reserved `free` keyword as a statement, distinct from its use as a bind-annotation keyword). A release conditioned on which branch of an `if`/`else` executed is a compile-time error; the programmer must restructure the code so release occurs at a single, unconditional point. This rule is what makes Section 10's exception-safety mechanism implementable without stack-unwinding infrastructure.

# The Generational Fallback

## Mechanism

Wherever Carnifex's static region-containment analysis cannot prove that a `free`-bound reference does not outlive its target region, the reference is silently downgraded — not rejected — to a **generation-tagged reference**: a `(pointer, generation-at-creation)` pair. Each region carries one monotonically-increasing generation counter, incremented once when the region is bulk-released (arena reset, stack-frame pop) or, for `pool` allocations specifically, once per individually-released slot (pool mode frees at slot granularity, not region granularity, and its generation counter is correspondingly per-slot rather than per-region).

Every dereference of a downgraded reference performs one additional load-and-compare against its region's (or slot's) live generation counter. A mismatch raises `DanglingRefError`, a runtime error in the same family as Rex's existing `NullError`, catchable via the language's existing `try`/`except` construct.

## Cost model

Statically provable references — the majority of references in typical code, by the same logic that makes Rust's checker successful in the majority of cases — cost nothing at runtime; the check is fully resolved at compile time. Only the subset the compiler cannot prove pays the one-comparison runtime tax. This is the load-bearing distinction between Carnifex and Rust: **Rust converts an unprovable reference into a compile error; Carnifex converts it into a small, bounded runtime cost.** Neither choice is strictly superior — Rust's is a stronger guarantee when it compiles; Carnifex's never forces the programmer to restructure otherwise-correct code to satisfy the analysis.

## Efficiency relative to prior generational-reference designs

Because Rex's `arena`/`stack` allocators already free memory in region-sized bulk operations, Carnifex's generation counter is placed **per-region**, not per-object as in a naive implementation of the generational-reference idea (cf. Vale, Section 2). Region invalidation is therefore $O(1)$ regardless of how many objects the region contained, rather than $O(n)$ for a scheme that must increment one counter per freed object. `pool` mode, which frees at individual-slot granularity, is the one case retaining a per-slot counter, as bulk invalidation semantics do not apply to it.

# Duplication and Release: The `.copy()` / `.release()` Hooks

## `.copy()`

Rex's design already specifies `.copy()` on several built-in container and string types as producing an independent duplicate. Carnifex generalizes this into a mandatory contract for any `owned` type that is to be copyable: `.copy()` is the sole sanctioned mechanism for producing a second, independent instance of an owned resource — used when a struct or container containing an `owned` field is itself copied, when a value must be promoted from one region to another (Section 4.3), and when plain assignment (Section 11) targets an `owned` destination. A type without a `.copy()` implementation is simply non-copyable, and any composite type containing it inherits that restriction. Trivial (POD) types receive a synthesized `.copy()` (a bitwise copy) with no author effort required; resource-owning types (e.g. a file handle) must define `.copy()` explicitly (e.g., via `dup()`).

## `.release()`

The `Drop` analog: a per-type hook invoked at an `owned` binding's statically-determined release point (Section 6.3). No-op by default for POD types; must be defined explicitly for resource-owning types (e.g., `close()` for a file handle).

## Interaction with existing container semantics

Rex's design document specifies `seq[T].copy()` and `dict[T].copy()` as **shallow** copies. This is unsound once `T` may be `owned`: a shallow copy of a `seq[file]`, for instance, would produce two sequences whose elements both believe themselves the sole owner of the same file descriptor, producing a double-release on independent destruction. Carnifex requires this specification be amended: container `.copy()` must deep-copy (invoking `T.copy()` per element) whenever `T` is `owned`, and may remain shallow only when `T` is `free` or trivially POD. `arr[T, N]`, having a compile-time-constant element count, can implement this deep copy fully unrolled at compile time with no runtime loop; `seq`/`dict`, being dynamically sized, require a runtime loop.

A further, previously unspecified requirement follows from the same reasoning: any mutating removal operation on a container of `owned` elements (`seq.pop()`, `dict.remove(key)`, etc.) must invoke `.release()` on the removed element at the point of removal, not defer it to the container's own eventual release — otherwise the resource becomes unreachable but unreleased, a leak rather than a soundness violation, but a defect nonetheless.

# Container Ownership Accumulation

## The problem

The pinned-ownership rule (Section 6.2), taken without qualification, would forbid `container.push(x)` whenever `x` is an already-existing `owned` binding, since this is precisely a transfer between two existing bindings. Taken strictly, this would restrict owned collections to being fully constructed in a single literal expression, which is impractical for the common case of incremental construction (e.g., accumulating open file handles in a loop).

## Resolution: same-region accumulation

Carnifex resolves this by observing that transfer *within* a single region was never actually unsafe — a region's contents are, by definition, invalidated together (for the `arena`/`stack`/`pool` modes this analysis applies to), so accumulating ownership within that shared boundary changes only *which variable's release logic is responsible for triggering release*, not *when* release occurs. Concretely: `container.push(x)` is permitted whenever `x`'s `region-id` is identical to the container's own birth region. Transfer *across* distinct regions remains forbidden, as that is the case where the source might be invalidated before the accumulating container's own release point arrives.

## Capacity

Because `arena` and `pool` regions have a fixed physical budget, accumulation into a container backed by one of these modes must be bounded by an explicitly declared capacity at the region's point of declaration (e.g., `use mm arena(4096):`). Every allocation within the region — not merely container pushes — draws from and decrements this single shared budget. Where the sequence of accumulating operations is fully static (a compile-time-constant loop bound, or a fixed sequence of literal pushes), the compiler may reject an over-budget program at compile time; where the bound is dynamic, an over-budget accumulation is a compile-time-mandated illegal operation rather than a silently tolerated runtime condition, consistent with the project's decision that regions requiring accumulation must have their maximum size declared up front and checked at every push.

# Exception Safety

## Requirement

When a `raise` unwinds through a lexical scope holding a live `owned` binding, that binding's `.release()` must run during unwinding, exactly as Rust's `Drop` glue runs during a panic unwind.

## Implementation without unwind tables

Rust (and C++) implement this guarantee using stack-unwinding metadata — DWARF call-frame information and per-frame landing pads — interpreted by a runtime unwinder that walks the stack at panic/exception time, consulting tables to determine which destructors to run at each frame. This is substantial infrastructure.

Carnifex does not require it, as a direct consequence of Section 6.3: because every `owned` binding's release point is already required to be a single, statically-identical program location regardless of control flow, the compiler already knows, *at compile time*, for every possible `raise` site, the complete and exact set of live `owned` bindings between that site and its corresponding `except` clause (or program exit, if unhandled). The compiler can therefore emit the necessary `.release()` calls **directly and explicitly at each `raise` site**, in reverse declaration order, immediately before transferring control — the same class of code generation already required for an early `return` crossing scope boundaries, requiring no new runtime data structure and no stack-walking at unwind time.

# Assignment Semantics

Plain assignment, `x = y`, is fully determined by the **destination's** `bind`, independent of the source's:

- **If `x` is `owned`:** `x = y` is defined to mean `x = y.copy()`. Neither aliasing nor transfer is available to an `owned` destination, and `.copy()` is the only remaining sanctioned operation; this is not a special case but a direct consequence of Sections 6.2 and 8.1. If `y`'s type has no `.copy()` implementation, this is a compile-time error. If `x` already held a prior owned value (reassignment, not initialization), that prior value's `.release()` must be invoked before the new copy is bound, to avoid a resource leak.
- **If `x` is `free`:** `x = y` creates a lightweight view sharing `y`'s `(pointer, region-id)`, subject to the ordinary capability check of Section 5. This is the identical mechanism used for passing an argument to a function parameter (Section 6.2, point 1) — plain assignment to a `free` destination and function-call argument-passing are the same operation.

Notably, the same-region accumulation relaxation of Section 9 does **not** extend to bare scalar assignment, even between variables in the same region. Container accumulation was scoped specifically to construction-at-call-site or absorption-into-container-owned-storage, neither of which requires tracking whether the source variable remains valid afterward. Permitting `x = y` to transfer ownership, even within one region, would require exactly that tracking for arbitrary scalar variables — reintroducing a general move-checker, the analysis Carnifex was specifically designed to eliminate. The boundary is therefore held firmly at containers' own mutating methods and does not generalize to assignment.

# Formal Comparison with the Rust Borrow Checker

| Dimension | Rust Borrow Checker | Carnifex |
|---|---|---|
| Analysis class | Purely static; rejects unprovable programs | Hybrid: static-first, runtime-fallback |
| Underlying technique | Flow-sensitive dataflow (NLL), per-instruction | Region-tree containment + generation counters, per-block |
| Aliasing rule | Exactly one writer XOR many readers | Many readers + one tracked writer (region-typing) |
| Granularity of aliasing check | Instruction-level | Block-level |
| Ownership transfer | Permitted via `move`; requires a dedicated move-checker | **Disallowed between existing bindings**; established only at construction |
| Move-checker required | Yes | **No** — eliminated by pinned ownership |
| Duplication contract | `Clone` trait | `.copy()` (shared with Rex's pre-existing container-copy convention) |
| Release contract | `Drop` trait, flow-sensitive (handles partial/conditional moves) | `.release()`, requires statically uniform release point on all paths |
| Exception/panic safety | Stack-unwinding tables (DWARF CFI, landing pads) required | **No unwind tables required** — release calls emitted directly at each raise site, by construction |
| Scope of applicability | Entire language (single memory model) | Applies fully only to manually-managed `mm` scopes (`arena`/`stack`/`pool`/`static`); GC-managed scopes are out of scope by design |
| Cost when static proof fails | Compile error; program must be restructured | One generation-counter comparison per unprovable dereference |
| Cyclic data structures | Requires `Rc`/`Weak` (reference counting) for owning-cycle avoidance | Owning tree + `free`-bound back-edges, checked via generation tags |
| Soundness maturity | ~10 years of formal work (Stacked Borrows, Polonius, Miri) | Whiteboard design; not yet implemented or mechanically verified |

## Interpretation

Carnifex does not prove a strictly stronger theorem than Rust's borrow checker; it proves a related but distinct guarantee — bounded by region and generation identity rather than precise, per-reference computed lifetimes — and trades a bounded amount of static precision for the elimination of two of the borrow checker's three constituent analyses (move-checking and unwind-table-based destructor sequencing), while never forcing rejection of a program the analysis cannot fully verify. Whether this constitutes an improvement depends on which of two properties is valued more highly: Rust's unconditional zero-runtime-cost guarantee for all provably-safe references, or Carnifex's guarantee of never requiring code restructuring to satisfy the analysis, at the cost of a small number of runtime checks.

# Implementation Status and Roadmap

As of this specification, `rexc`'s intermediate representation (defined in `include/rex_ir.inc`) supports only scalar arithmetic, comparison, and control-flow opcodes (`IR_LOAD_IMM` through `IR_HALT`); there are no opcodes yet for function calls, structured data, containers, or `mm`/`gc` scopes. Carnifex must therefore be implemented concurrently with, not subsequent to, the addition of that scaffolding. Two concrete findings from the current IR inform the roadmap:

1. **Encoding space is available without growing the IR record.** The current 32-byte IR record has an unused 4-byte `_pad` field at offset 28, sufficient to encode a region-id, and its existing 4-byte `flags` field (currently using only bits for `IR_FLAG_CONST`, `IR_FLAG_DEAD`, `IR_FLAG_SPILLED`) has unused bits available for `IR_FLAG_OWNED` and a release-obligation marker.

2. **The existing dead-store-elimination pass (`pass_dead_store_elimination`) is unsound in its current form once `owned` bindings exist.** A store to a variable that is never subsequently read is presently eligible for elimination as dead code. An `owned` binding carries a release obligation independent of whether its value is read, exactly analogous to Rust's `Drop` running even for an unused binding; eliminating such a store would silently skip the corresponding `.release()` call. This pass requires an explicit exclusion for any store flagged `IR_FLAG_OWNED`, regardless of subsequent liveness.

A further favorable finding: `pass_apply_aliases`, which already follows alias chains for existing optimization purposes, is directly reusable as the substrate for Carnifex's capability (read/write aliasing) tracking, rather than requiring a new alias-analysis pass to be built independently.

# Limitations and Open Problems

The following are identified but not resolved by this specification:

- **Generic/parametric owned types.** The interaction between Carnifex's `bind` field and a not-yet-designed generics system is unexamined.
- **Closures.** Rex has no closure or lambda construct at present; the question of what capturing an `owned` binding by a closure would mean is deferred until closures are designed.
- **Recursive-structure release depth.** A structurally-recursive owned type (e.g., a linked list modeled as nested owned struct fields) releases via recursive `.release()` calls by the mechanism as specified, which risks stack overflow for long chains — a known issue in comparable Rust code, typically addressed with a hand-written iterative destructor. Whether `rexc` should synthesize an iterative release path automatically for such types is unresolved.
- **Generation counter wraparound.** Long-running programs with very frequent region invalidation (e.g., a `pool`-mode region in a hot loop) require a defined wraparound behavior for the generation counter; none is yet specified.
- **No mechanical verification.** Unlike Rust's borrow checker, which has been the subject of substantial formal-methods scrutiny (Stacked Borrows, Polonius, and automated checking via Miri), Carnifex's soundness argument in this document is informal. Formal verification, or at minimum a reference implementation exercised against an adversarial test suite, is necessary before the design can be considered validated rather than merely internally consistent.

# Conclusion

Carnifex demonstrates that a memory-safety mechanism distinct from Rust's borrow checker — hybrid rather than purely static, permissive rather than strict in its aliasing rule, and structurally simpler by construction (no move-checker, no unwind-table infrastructure) — can be derived from a small set of initial design constraints without ad hoc special-casing, each subsequent design decision (pinned ownership, statically-uniform release points, same-region accumulation, destination-determined assignment semantics) following as a consequence of earlier ones rather than as an independent patch. The model's soundness argument is presently informal and its implementation nonexistent; both are necessary next steps before Carnifex can be considered validated. The specification given here is intended to serve as the reference for that implementation work.

# References

1. Matsakis, N. D., & Klock, F. S. (2014). *The Rust Language*. ACM SIGAda Ada Letters.
2. Jung, R., et al. (2018). *RustBelt: Securing the Foundations of the Rust Programming Language*. POPL.
3. Jung, R., et al. (2020). *Stacked Borrows: An Aliasing Model for Rust*. POPL.
4. Weiss, A., et al. (2019). *Oxide: The Essence of Rust*. arXiv:1903.00982.
5. Evan Ovadia. *Vale Language: Generational References and Region Borrow Checking*. vale.dev.
6. Clebsch, S., et al. (2015). *Deny Capabilities for Safe, Fast Actors*. AGERE!
7. Grossman, D., et al. (2002). *Region-Based Memory Management in Cyclone*. PLDI.
8. Rex Language Design Document, `imp/design.md`, `imp/mm.md`, `imp/grammar.md` — Tolu23456/Rex repository.

