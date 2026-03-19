# odin-itc — Update Task

## Your role

You are updating the `odin-itc` repository to reflect a new design for poly-item mailboxes.
Read all context files carefully before making any changes.
Do not break existing APIs. All additions are additive.
Follow the existing code style in each file you touch.

---

## Context files — read these first

These files contain the authoritative design decisions for this task:

- `design/idioms.md` — **replaced with updated version** — authoritative source for all naming, patterns, and idioms
- `design/poly-mailbox-proposal.md` — **new file** — full poly-item design specification
- `design/itc-compression-pipeline.md` — **new file** — updated demo document

Also read these existing files to understand current style and conventions:

- `pool/pool.odin` — current pool implementation
- `pool/doc.odin` — current pool doc comments
- `mbox/mbox.odin` — current mailbox implementation
- `mbox/doc.odin` — current mailbox doc comments
- `mbox/README.md` — current mailbox readme
- `README.md` — root readme
- `design/current-stage.md` — current stage notes
- `examples/lifecycle.odin` — reference example for style
- `examples/master.odin` — reference example for style
- `examples/disposable_itm.odin` — reference example for style
- `tests/pool/` — reference tests for style

---

## What changed — summary

A new poly-item design was specified. Key concepts:

**PolyNode** — intrusive base node for all items traveling through a poly pool or mailbox:
```odin
PolyNode :: struct {
    using node: intrusive.Node,  // offset 0 — queue link
    id: int,                     // user-defined — stamped by factory on acquire
}
```

**Participant types** embed `PolyNode` at offset 0 via `using`:
```odin
Chunk :: struct {
    using poly: PolyNode,   // offset 0 — required
    data: [CHUNK_SIZE]byte,
    len:  int,
}
```

**Pool_Hooks** — all hooks receive `ctx rawptr` as first argument. New `accept` hook for per-id count limiting:
```odin
Pool_Hooks :: struct {
    ctx:     rawptr,
    factory: proc(ctx: rawptr, id: int) -> (^PolyNode, bool),
    reset:   proc(ctx: rawptr, node: ^PolyNode),
    dispose: proc(ctx: rawptr, m: ^Maybe(^PolyNode)),
    accept:  proc(ctx: rawptr, id: int, current_count: int) -> bool,
}
```

**Pool_Mode** — per-call allocation strategy:
```odin
Pool_Mode :: enum {
    Always,     // free list first, allocate if empty
    Standalone, // always allocate, never touch free list
    Pool_Only,  // free list only, error if empty
}
```

**PolyPool** — one pool for all variant types, keyed by id:
```odin
PolyPool :: struct {
    lists:  []FreeList,     // one per registered id
    ids:    []int,
    hooks:  Pool_Hooks,
    mutex:  sync.Mutex,
}

FreeList :: struct {
    head:  ^PolyNode,
    count: int,
}
```

**Ownership contract** — `^Maybe(^PolyNode)` across all APIs. Same as existing `^Maybe(^T)` pattern.

**Golden rule 2** — every item acquired from the pool must be returned via one of:
- `pool_put` — recycle, normal path
- `pool_dispose` — destroy permanently
- `mbox_send` — transfer to receiver who will put or dispose

**Hooks called outside pool mutex** — guaranteed. User responsible for any synchronization inside hooks.

**mbox.close** returns remaining list as `^PolyNode` head. Caller drains via `pool_dispose`.

**accept hook** — per-id count limiting. Pool passes `current_count` for that id's free list. Returns true to recycle, false to treat as foreign. Called outside mutex. nil = always recycle. Byte-level limits are user responsibility.

**backpressure** — via `WakeUper`, no value. Producer switches `id` on wake. No changes to pool or mailbox needed.

---

## Tasks

### Task 1 — design/ directory

**1.1** Replace `design/idioms.md` entirely with the updated version provided.

**1.2** Create `design/poly-mailbox-proposal.md` — copy the proposal file provided.

**1.3** Create `design/itc-compression-pipeline.md` — copy the demo file provided.

**1.4** Update `design/current-stage.md` — append a new section:

```markdown
## Poly-item mailbox — design complete (2026-03)

Designed and documented:

- `PolyNode` — intrusive base node built on `intrusive.Node`, carries `id: int`
- `PolyPool` — one pool for all variant types, per-id free lists
- `Pool_Hooks` with `ctx rawptr` — factory/reset/dispose/accept, all called outside pool mutex
- `Pool_Mode` — per-call allocation strategy: Always / Standalone / Pool_Only
- `accept` hook — per-id count limiting, pool passes current_count
- golden rule 2 — every item must be returned via put, dispose, or send
- backpressure via `WakeUper` — producer switches id on signal
- `mbox.close` — returns remaining list, caller drains via pool_dispose
- hooks called outside pool mutex — user responsible for internal synchronization

See: design/poly-mailbox-proposal.md, design/idioms.md
```

---

### Task 2 — pool/

**2.1** `pool/pool.odin` — add new types and proc stubs.

Do not modify or remove existing code. All additions are additive.

Add the following. Use the existing package name and import style:

```odin
// --- Poly pool types ---

PolyNode :: struct {
    using node: intrusive.Node,
    id:         int,
}

Pool_Mode :: enum {
    Always,     // take from free list if available, allocate if empty
    Standalone, // always allocate, never touch free list
    Pool_Only,  // free list only, error if empty — never allocates
}

Pool_Hooks :: struct {
    ctx:     rawptr,
    factory: proc(ctx: rawptr, id: int) -> (^PolyNode, bool),
    reset:   proc(ctx: rawptr, node: ^PolyNode),
    dispose: proc(ctx: rawptr, m: ^Maybe(^PolyNode)),
    accept:  proc(ctx: rawptr, id: int, current_count: int) -> bool,
}

FreeList :: struct {
    head:  ^PolyNode,
    count: int,
}

PolyPool :: struct {
    lists:  []FreeList,
    ids:    []int,
    hooks:  Pool_Hooks,
    mutex:  sync.Mutex,
}
```

Add proc stubs — signatures only, bodies are `unimplemented()` or empty for now:

```odin
poly_pool_init    :: proc(p: ^PolyPool, hooks: Pool_Hooks, ids: []int) -> bool { return false }
poly_pool_destroy :: proc(p: ^PolyPool) {}
poly_pool_get     :: proc(p: ^PolyPool, m: ^Maybe(^PolyNode), id: int, mode: Pool_Mode) -> bool { return false }
poly_pool_put     :: proc(p: ^PolyPool, m: ^Maybe(^PolyNode)) -> ^Maybe(^PolyNode) { return nil }
poly_pool_dispose :: proc(p: ^PolyPool, m: ^Maybe(^PolyNode)) {}
```

**2.2** `pool/doc.odin` — add doc comments for all new types and procs.

Follow the existing doc.odin style exactly. Document:
- `PolyNode` — intrusive base node, offset 0 rule, id stamped by factory
- `Pool_Mode` — each variant
- `Pool_Hooks` — each field including ctx, accept nil behavior
- `FreeList` — internal, one per registered id
- `PolyPool` — one pool for all variant types
- each proc stub — purpose, preconditions, postconditions

**2.3** `tests/pool/` — add `poly_pool_test.odin`

Write tests for the new API surface. Tests should compile and run but may be skipped/pending if implementation is stub. Follow style of existing pool tests. Cover:

- `poly_pool_init` with valid ids
- `poly_pool_init` with empty ids
- `poly_pool_get` with valid id
- `poly_pool_get` with invalid id — expect error
- `poly_pool_put` — recycle path
- `poly_pool_put` — foreign id — expect returned pointer
- `poly_pool_dispose` — nil inner is no-op
- `accept` hook returning false — expect foreign treatment
- golden rule 2 — verify item is nil after successful put

---

### Task 3 — mbox/

**3.1** `mbox/mbox.odin` — no implementation changes needed.

Mailbox already operates on a node type internally. Verify that `send` and `wait_receive` can accept `^Maybe(^PolyNode)` under the existing API or note what adapter is needed. Do not break existing API.

If the existing mailbox is generic `Mailbox($T)`, add a type alias or note:

```odin
// PolyMailbox operates on ^PolyNode — no generics needed
// Use existing Mailbox with T = PolyNode, or use raw mbox with ^PolyNode directly
```

**3.2** `mbox/README.md` — add section at end:

```markdown
## Poly-item mailbox

The mailbox is type-erased — it operates on `^PolyNode` internally.
All concrete type knowledge lives in user code.

Sender:
```odin
m: Maybe(^PolyNode)
poly_pool_get(&p, &m, int(FlowId.Chunk), .Always)
defer poly_pool_dispose(&p, &m)     // no-op if sent
mbox_send(&mb, &m)
```

Receiver:
```odin
m: Maybe(^PolyNode)
mbox_wait_receive(&mb, &m)
defer poly_pool_dispose(&p, &m)     // safety net

switch FlowId(m.?.id) {
case .Chunk:
    c := (^Chunk)(m.?)
    // process
    poly_pool_put(&p, &m)

case .Progress:
    pr := (^Progress)(m.?)
    // update
    poly_pool_put(&p, &m)
}
```

Shutdown — `mbox_close` returns remaining list. Caller drains:
```odin
head := mbox_close(&mb)
node := head
for node != nil {
    next := node.next
    m: Maybe(^PolyNode) = node
    poly_pool_dispose(&p, &m)
    node = next
}
```

See `design/poly-mailbox-proposal.md` for full design.
See `examples/poly_item.odin` for a complete working example.
```

---

### Task 4 — README.md

Update root `README.md`. Add or update the following sections:

**Feature list** — add:
- Poly-item mailbox — multiple item types in one flow, type-erased pool and mailbox
- `Pool_Hooks` with `ctx` — factory/reset/dispose/accept, all called outside pool mutex
- Per-id count limiting via `accept` hook
- Three allocation modes per `pool_get` call — Always / Standalone / Pool_Only

**Golden rules** — add a short section:

```markdown
## Golden rules

**Rule 1 — one variable, whole lifetime**
One `Maybe(^PolyNode)` from `pool_get` to final disposition.
Never copy the inner pointer into a second `Maybe`.

**Rule 2 — every item must be returned**
Every item acquired from the pool must end with one of:
- `pool_put` — recycle
- `pool_dispose` — destroy
- `mbox_send` — transfer

There is no fourth option.
```

**Links** — add:
- `design/poly-mailbox-proposal.md` — full poly-item design
- `design/idioms.md` — idioms reference
- `design/itc-compression-pipeline.md` — compression pipeline demo

---

### Task 5 — examples/

**5.1** Create `examples/poly_item.odin` — complete working example.

Follow the style of `examples/lifecycle.odin` and `examples/master.odin`.

The example must:

- define `FlowId :: enum { Chunk, Progress }`
- define `Chunk` and `Progress` with `using poly: PolyNode` at offset 0
- define `Master` struct with `allocator`, `pool: PolyPool`, `mbox: Mailbox`
- define `FLOW_HOOKS` compile-time constant with factory/reset/dispose/accept
- show `flow_factory` — allocates per id via ctx, stamps node.id
- show `flow_reset` — clears per id
- show `flow_dispose` — frees per id, sets m^ = nil
- show `flow_accept` — returns count < limit per id
- show sender: `poly_pool_get` → fill → `defer poly_pool_dispose` → `mbox_send`
- show receiver: `mbox_wait_receive` → `defer poly_pool_dispose` → switch on id → cast → process → `poly_pool_put`
- show shutdown: `mbox_close` → drain list → `poly_pool_dispose` each → `poly_pool_destroy`
- use `[itc: ...]` tags at relevant lines matching idioms.md

The example must compile. If pool stubs are not implemented yet, use mock data or skip the send/receive loop with a comment.

**5.2** `examples/doc.odin` — add doc entry for `poly_item.odin` following existing style.

---

### Task 6 — docs_site/

**6.1** `docs_site/docs/` — if idioms or design docs are mirrored here, update them to match the new `design/idioms.md`.

**6.2** `docs_site/mkdocs.yml` — add navigation entries if new design files are added to the docs site:

```yaml
- Poly-item mailbox: poly-mailbox-proposal.md
- Compression pipeline demo: itc-compression-pipeline.md
```

---

## Execution order

Execute in this order to minimize conflicts:

```
1.  design/idioms.md                      replace entirely
2.  design/poly-mailbox-proposal.md       new file
3.  design/itc-compression-pipeline.md   new file
4.  design/current-stage.md              append section
5.  pool/pool.odin                        add types and stubs
6.  pool/doc.odin                         add doc comments
7.  tests/pool/poly_pool_test.odin        new test file
8.  mbox/mbox.odin                        check compatibility, note if adapter needed
9.  mbox/README.md                        add poly section
10. README.md                             update features, golden rules, links
11. examples/poly_item.odin               new example
12. examples/doc.odin                     add entry
13. docs_site/                            update if docs are mirrored
```

---

## Hard rules

- Do not remove or modify any existing proc, type, or constant.
- Do not change any existing test.
- Do not change build scripts.
- Follow the existing package declaration and import style in each file.
- Use `[itc: tag]` comments in examples exactly as shown in `design/idioms.md`.
- `ctx` is always the first parameter of every hook proc.
- Hooks are always called outside the pool mutex — document this in doc comments.
- `accept` nil = always recycle — document this.
- Every example must show `defer poly_pool_dispose` immediately after `poly_pool_get`.
- Every receiver switch must show `poly_pool_put` in every case branch.
- `mbox_close` drain loop must use `poly_pool_dispose`, not `free` or `flow_dispose` directly.

---

## Authoritative sources

If anything is ambiguous, these files are the source of truth in this order:

1. `design/poly-mailbox-proposal.md`
2. `design/idioms.md`
3. `design/itc-compression-pipeline.md`
4. Existing code style in the repository

<!--
Complete prompt. Structure:
Context files — exact list of what to read first, split into new files to provide and existing files to read for style.
What changed — concise technical summary with code snippets so the agent does not need to re-derive anything from the design docs.
6 tasks — each broken into numbered subtasks with exact file paths, exact code to add, exact content for new sections. Nothing ambiguous.
Execution order — numbered sequence to minimize conflicts.
Hard rules — non-negotiable constraints listed explicitly so the agent cannot rationalize breaking them.
Authoritative sources — priority order for resolving ambiguity.
When running with Claude Code or Gemini CLI, provide this prompt plus the three output files (idioms.md, poly-mailbox-proposal.md, itc-compression-pipeline.md) as context alongside the repository.
-->
