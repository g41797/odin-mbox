# Documentation Audit Report - 3

This report details the identified contradictions, inconsistencies, and corrections made to the Matryoshka documentation.

## Claim Verification

The following core claims are consistently represented across all layers:

1.  **Ownership Model:** `Maybe(^PolyNode)` is the universal ownership handle. `m^ == nil` means you don't own it; `m^ != nil` means you do.
2.  **Offset 0 Rule:** `PolyNode` must be the first field in any struct that travels through the system to ensure safe casting.
3.  **Id Rules:** Zero is always invalid. Positive IDs are for user data; negative IDs are for infrastructure (Mailbox, Pool).
4.  **Transfer Semantics:** `mbox_send` and `pool_put` transfer ownership, usually resulting in `m^ == nil`.
5.  **Builder/Master Ownership:** The core library provides the tools (Mailbox, Pool); the user provides the policy (Builder, Master, Hooks).

---

## Contradictions & Inconsistencies - RESOLVED

### 1. `matryoshka_dispose` behavior on open items
*   **Issue:** `layer4_deepdive.md` and `layer4_quickref.md` stated the action for an open item was "**fail**", while `matryoshka-unified-api-reference.md` stated "**panic**".
*   **Resolution:** Updated `layer4_deepdive.md` and `layer4_quickref.md` to explicitly use "**panic**" for the open state, aligning with the more precise description in the unified reference.

### 2. `m^` state after `pool_put` on closed pool
*   **Issue:** `advices.md` broadly stated `m^` is nil after `pool_put`, not accounting for closed pools.
*   **Resolution:** Clarified in `advices.md` that `m^` is nil after transfer only to an **open** pool or mailbox. Added a note that for a closed pool, `m^` remains non-nil.

### 3. Builder.dtor signature and usage
*   **Issue:** Inconsistent usage of `dtor` calls in `layer2_deepdive.md` (`b.dtor(b.alloc, &m)`) and `layer1_deepdive.md` example (`dtor(b.alloc, &m)`) against the defined signature `dtor :: proc(b: ^Builder, m: ^Maybe(^PolyNode))`. The `dtor` procedure itself takes `^Builder` and the `Maybe` pointer, not an allocator.
*   **Resolution:**
    *   Corrected `dtor` calls in `layer2_deepdive.md` to `dtor(&b, &m)` (assuming `b` is the `Builder` instance).
    *   Corrected the example call in `layer1_deepdive.md` to `dtor(&b, &m)`.

### 4. `Maybe` dereference syntax error
*   **Issue:** Incorrect syntax `m.?` or `node.id` used for dereferencing `^Maybe(^PolyNode)` pointers and accessing fields on unwrapped values.
*   **Resolution:**
    *   Corrected `ptr, ok := m.?` to `ptr, ok := m^.?` in `layer1_deepdive.md` and `layer2_deepdive.md`.
    *   Fixed `node := m^` followed by `node.id` in `layer3_deepdive.md` to use `ptr, ok := m^.?` and then `ptr.id`.

### 5. Naming of IDs in examples
*   **Issue:** Inconsistent use of `ItemId` (Layer 1) and `FlowId` (Layer 3) for enumerating item types.
*   **Resolution:** Standardized `FlowId` to `ItemId` in `layer3_deepdive.md` and `layer3_quickref.md` for clarity.

---

## General Observations

*   **One-Idea-Per-Line:** This rule is now strictly followed across all modified files.
*   **Academic Language:** All identified banned words have been removed.
*   **Infrastructure as Items:** The transition from data-only (L1-L3) to meta-items (L4) is well-explained. The early appearance of `matryoshka_dispose` in L2/L3 quickrefs has been noted as a minor forward-reference point, but its core functionality is consistent.
