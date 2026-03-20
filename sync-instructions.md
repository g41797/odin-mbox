# sync-instructions.md

## Role & Context
You are a senior systems architect specializing in Odin and high-performance concurrency. Your task is to synchronize three legacy documentation files with the new **Source of Truth (SoT)** for the `odin-itc` library.

### The Files
1.  **Source of Truth**: `design/sync/new-pool-design-ga-v2.md`
2.  **Targets**:
    - `design/sync/new-itc.md`
    - `design/sync/new-idioms.md`
    - `design/sync/poly_mailbox_proposal.md`

## Mandatory Architectural Rules (The "Laws")
If a legacy document contradicts these rules, **the Source of Truth wins.**

1.  **Dumb Mailbox Rule**: Mailboxes are transport only. They have no hooks, no counters, and no awareness of `FlowPolicy`.
2.  **Dynamic ID Rule**: The Pool does not pre-register IDs. It learns them via `pool_get`. If the `factory` hook accepts an ID, the Pool manages it.
3.  **Foreign Item Safety (CRITICAL)**:
    - `pool_put` and the `on_put` hook must return a `Put_Result` enum (`.Ok`, `.Rejected_Limit`, `.Foreign`).
    - **If status is `.Foreign`**: The hook **MUST NOT** dispose of the item and **MUST NOT** set the pointer to `nil`. Ownership remains with the caller.
4.  **Ownership Contract**: Every API uses `^Maybe(^PolyNode)`. A `nil` value always means ownership was transferred/consumed.
5.  **Hygiene Gate**: The `on_get` hook must be present in the `FlowPolicy`. No node leaves the pool without passing through `on_get`.

## Task Instructions
1.  **Update Signatures**: Align all `factory`, `on_get`, and `on_put` signatures across all documents to match the SoT. Ensure `in_pool_count` is passed to hooks.
2.  **Merge Hooks**: Remove the `accept` hook from `poly_mailbox_proposal.md`. Merge its logic into the new `on_put` return status description.
3.  **Clean Structures**: Ensure `PolyNode` is defined simply as `next: ^PolyNode` and `id: int`. Remove `intrusive.Node` embeddings.
4.  **Update Modes**: Ensure all `pool_get` examples use the `Pool_Get_Mode` enum (`.Recycle_Or_Alloc`, `.Alloc_Only`, `.Recycle_Only`).

## Output Format
Rewrite the target files in-place or provide the full text. Maintain the original Markdown formatting and professional "dev-style" tone. Avoid "AI-smell" or marketing fluff.

---

### How to use this with your tools:

* **Claude Code**:
    `claude "Rewrite the files in ./design/sync/ based on the rules in sync-instructions.md"`
* **Aider**:
    `aider ./design/sync/*.md --message "Read sync-instructions.md and apply all changes to the other three files."`
* **Gemini CLI**:
    `gemini-cli "Apply the architectural changes defined in .design/sync/new-pool-design-ga-v2.md to the target files as per .sync-instructions.md"`
