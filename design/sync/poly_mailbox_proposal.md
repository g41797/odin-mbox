# Poly-item mailbox — design proposal

## Problem

An item traveling through a mailbox contains different data depending on context:

```
Chunk
Progress
CompressedChunk
Error
Control
```

These must coexist in the same communication flow.

Current design assumes one item type per mailbox. That is not enough for real systems.

## Hard constraints

- no dynamic typing
- no heap-based polymorphism
- no runtime reflection
- still intrusive
- still zero-copy
- `^Maybe(^T)` ownership contract unchanged across all APIs

---

## Core insight

itc is the pipe. It passes `^Maybe(^PolyNode)` through.
It knows nothing about concrete item types, unions, or user enums.
All type knowledge lives in user code.

Same pattern as Odin stdlib:
- `thread.create` — `data: rawptr`, user casts
- `mem.Allocator` — `data: rawptr`, procedure table, user routes
- `context.user_ptr` — `rawptr`, user casts

`PolyNode` is a structured `rawptr` — pointer plus a discriminator.

---

## Base node

```odin
PolyNode :: struct {
    next: ^PolyNode,
    id:   int,        // user-defined enum value — stamped by factory on creation
}
```

`id` is an integer. User defines what it means. itc stores and delivers it. Nothing more.

---

## Participant types

Every type that travels through a poly mailbox embeds `PolyNode` first:

```odin
Chunk :: struct {
    using poly: PolyNode,  // offset 0
    data: [CHUNK_SIZE]byte,
    len:  int,
}

Progress :: struct {
    using poly: PolyNode,  // offset 0
    percent: int,
}
```

`using` promotes `next` and `id` directly onto the struct.
Offset 0 rule — enforced by convention. No itc compile-time check.
Whether participant types are themselves intrusive (carry additional nodes) does not matter — itc only requires `PolyNode` at offset 0.

---

## User responsibilities

User defines the id enum and the union next to each other:

```odin
FlowId :: enum { Chunk, Progress }

FlowMsg :: union { ^Chunk, ^Progress }
```

User writes:
- factory — allocates correct concrete type per id, stamps `node.id`
- on_get — clears state for reuse per id
- on_put — implements backpressure logic
- dispose — frees internal resources per id
- flow_send — wraps `^Maybe(^T)` → `^Maybe(^PolyNode)`, calls `mbox_send`
- flow_receive — calls `mbox.wait_receive`, switches on `node.id`, casts to `FlowMsg`

itc provides the pipe. User provides the protocol.

---

## Pool

One pool. Not one pool per type.

### Definition

```odin
Pool_Get_Mode :: enum {
    Recycle_Or_Alloc, // Default: Pop from free-list; if empty, call factory()
    Alloc_Only,       // Standalone: Bypass free-list; always call factory()
    Recycle_Only,     // Pool-Only: Pop from free-list; if empty, return false
}

Pool :: struct {
    // Internal fields for MPMC free-lists, accounting, etc.
    // User interacts via API, not direct field access.
}

FlowPolicy :: struct {
    ctx: rawptr, // User context (e.g., a Master struct or allocator)

    // Called when Get_Mode requires a new allocation.
    // in_pool_count: number of nodes of this 'id' currently in the free-list.
    factory: proc(ctx: rawptr, alloc: mem.Allocator, id: int, in_pool_count: int) -> (^PolyNode, bool),

    // Called BEFORE pool_get returns a recycled node to the user.
    // Use for sanitization/zeroing.
    on_get:  proc(ctx: rawptr, m: ^Maybe(^PolyNode)),

    // Called during pool_put.
    // To reject, hook disposes and sets m^ = nil.
    on_put:  proc(ctx: rawptr, alloc: mem.Allocator, in_pool_count: int, m: ^Maybe(^PolyNode)),

    // Called for every node remaining in the pool during pool_destroy.
    dispose: proc(ctx: rawptr, alloc: mem.Allocator, m: ^Maybe(^PolyNode)),
}
```

### Init

```odin
// policy defined at compile time — ctx set at runtime
FLOW_POLICY :: FlowPolicy{
    factory = flow_factory,
    on_get  = flow_on_get,
    on_put  = flow_on_put,
    dispose = flow_dispose,
}

policy := FLOW_POLICY
policy.ctx = &master // runtime — ctx points to Master or any user state

pool_init(&p, policy, master.allocator)
```

The Pool learns which IDs are supported dynamically via `pool_get` calls that trigger the `factory`.
`ctx` is runtime — cannot be set in a `::` constant.

### Three modes

Mode is a per-call parameter of `get`. Not a pool policy.

| Mode                | Behavior                                          |
|---------------------|---------------------------------------------------|
| `.Recycle_Or_Alloc` | take from free list if available, allocate if empty |
| `.Alloc_Only`       | always allocate, never touch free list          |
| `.Recycle_Only`     | free list only, error if empty — never allocates  |

### get

```odin
m: Maybe(^PolyNode)
ok := pool_get(&p, int(FlowId.Chunk), .Recycle_Or_Alloc, &m)
```

The pool does not pre-register IDs. It learns them dynamically. If an ID is passed to `pool_get` that the `factory` hook does not recognize, allocation fails.
Mode drives the allocation strategy for this call.
Pool calls `factory(policy.ctx, id, ...)` when allocation is needed.
Factory uses `ctx` to reach the allocator and any other needed state.
Factory allocates correct concrete type, stamps `node.id = id`, returns `^PolyNode`.
`m^` is non-nil on success. `ok` is true.

### put

```odin
pool_put(&p, &m)
```

Validates the item's id. If the id is unrecognized (foreign item), the pool does not accept it — `m^` remains non-nil, ownership stays with the caller.
If the item is not foreign, the pool calls `policy.on_put(ctx, alloc, in_pool_count, &m)`.
The `on_put` hook can implement backpressure. To reject an item, the hook must dispose of it and set `m^ = nil`.
If `m^` is still valid after the hook, the pool adds it to the free-list. Sanitization for reuse occurs in the `on_get` hook during the next `pool_get` call.

### FlowPolicy

```odin
// compile-time constant — proc pointers only, no ctx
FLOW_POLICY :: FlowPolicy{
    factory = flow_factory,   // allocates per id via ctx
    on_get  = flow_on_get,    // sanitizes for reuse per id
    on_put  = flow_on_put,    // implements backpressure per id
    dispose = flow_dispose,   // frees internal resources per id
}

// ctx carries Master — hooks reach allocator and any other state
flow_factory :: proc(ctx: rawptr, alloc: mem.Allocator, id: int, in_pool_count: int) -> (^PolyNode, bool) {
    #partial switch FlowId(id) {
    case .Chunk:
        c := new(Chunk, alloc)
        if c == nil { return nil, false }
        c.id = id
        return (^PolyNode)(c), true
    case .Progress:
        p := new(Progress, alloc)
        if p == nil { return nil, false }
        p.id = id
        return (^PolyNode)(p), true
    }
    return nil, false
}

flow_on_get :: proc(ctx: rawptr, m: ^Maybe(^PolyNode)) {
    if m == nil || m^ == nil { return }
    #partial switch FlowId(m.?.id) {
    case .Chunk:    (^Chunk)(m.?).len = 0
    case .Progress: (^Progress)(m.?).percent = 0
    }
}

flow_on_put :: proc(ctx: rawptr, alloc: mem.Allocator, in_pool_count: int, m: ^Maybe(^PolyNode)) {
    if m == nil || m^ == nil { return }
    #partial switch FlowId(m.?.id) {
    case .Chunk:
        if in_pool_count > 400 {
            flow_dispose(ctx, alloc, m) // Consume to enforce limit
        }
    case .Progress:
        if in_pool_count > 128 {
            flow_dispose(ctx, alloc, m) // Consume to enforce limit
        }
    }
}

flow_dispose :: proc(ctx: rawptr, alloc: mem.Allocator, m: ^Maybe(^PolyNode)) {
    if m == nil  { return }
    if m^ == nil { return }
    node := m^
    #partial switch FlowId(node.id) {
    case .Chunk:
        c := (^Chunk)(node)
        free(c, alloc)
    case .Progress:
        p := (^Progress)(node)
        free(p, alloc)
    }
    m^ = nil
}
// For byte-level limits (e.g. 400MB total): user maintains a byte counter
// in ctx, and decides whether to call pool_put or flow_dispose(ctx, alloc, &m).
```

---

## Mailbox

Unchanged internally. Operates on `^PolyNode` only.

```odin
Mailbox :: struct {
    queue: ^PolyNode,
}
```

`send` and `wait_receive` work with `^Maybe(^PolyNode)` — same contract as all itc APIs.

---

## Caller pattern

### Sender side

```odin
// acquire
m: Maybe(^PolyNode)
if pool_get(&p, int(FlowId.Chunk), .Recycle_Or_Alloc, &m) {
    defer pool_put(&p, &m)             // [itc: defer-put] no-op if m^ is nil

    // fill — cast to concrete type
    c := (^Chunk)(m.?)
    c.len = fill(c.data[:])

    // send — m^ = nil on success, pool_put is no-op
    mbox_send(&mb, &m)
}
```

### Receiver side

```odin
m: Maybe(^PolyNode)
mbox.wait_receive(&mb, &m)
defer pool_put(&p, &m)             // [itc: defer-put] safety net — fires if put not reached

switch FlowId(m.?.id) {
case .Chunk:
    c := (^Chunk)(m.?)
    process_chunk(c)
    pool_put(&p, &m)               // golden rule 2: must return — m^ = nil on success

case .Progress:
    pr := (^Progress)(m.?)
    update_progress(pr)
    pool_put(&p, &m)               // golden rule 2: must return — m^ = nil on success
}
// every case ends with pool_put — no exit without disposition
```

Receiver switch is user code. itc delivers `^PolyNode` and the `id`. User casts, processes, returns to pool.

---

## Ownership rules

| Event | Rule |
|---|---|
| after `pool_get` | caller owns via `Maybe(^PolyNode)` — inner non-nil |
| after `send` success | `m^` = nil — transfer complete |
| after `send` failure | `m^` unchanged — caller still holds, dispose runs |
| after `wait_receive` | receiver owns via `Maybe(^PolyNode)` — inner non-nil |
| after `pool_put` success | `m^` = nil — returned to pool |
| after `pool_put`, foreign id | `m^` is not `nil` — caller retains ownership |
| `defer-put` | no-op if transferred or put, recycles or disposes if stuck |

---

## Runtime checks summary

| Location | Check | On failure |
|---|---|---|
| `pool_get` | factory can create `id` | error |
| `pool_put` | id is valid (recognized by factory) | foreign — `m^` remains non-nil |
| receiver switch | id known to user | default case — dispose |

No compile-time checking from itc. All checks are runtime.
User is responsible for correctness of casts and switch coverage.

---

## What itc owns

- `PolyNode` shape — `next` + `id`
- pool modes — per `get` call
- `^Maybe(^PolyNode)` contract across all APIs
- hooks dispatch — `factory` / `on_get` / `on_put` / `dispose` called with `ctx`
- hooks called **outside** pool mutex — guaranteed
- `on_put` — pool passes `in_pool_count` per id, hook implements policy
- `mbox.close` — returns remaining list as `^PolyNode` head

## What user owns

- id enum definition
- union definition
- all `FlowPolicy` hooks implementations — `factory`/`on_get`/`on_put`/`dispose`
- hooks locking — user is responsible for any synchronization inside hooks
- count limits per id — expressed in `on_put` hook
- byte-level limits — user responsibility, via manual `flow_dispose(ctx, alloc, &m)` instead of `pool_put`
- flow_send / flow_receive wrappers
- receiver switch and casting
- **must return every item to pool** — via `pool_put`, `flow_dispose`, or `mbox_send`

---

## Golden rules

### Rule 1 — one variable, whole lifetime

One `Maybe(^PolyNode)` variable from `pool_get` to final disposition. Never copy the inner pointer into a second `Maybe`. Same variable through get → send → receive → put → dispose.

### Rule 2 — every item must be returned

Every item acquired from the pool must be returned. No exceptions. No detours.

Three valid endings:

```
pool_put(&p, &m)                       // recycle — normal path after processing
flow_dispose(policy.ctx, alloc, &m)    // destroy — shutdown, foreign, or byte limit exceeded
mbox_send(&mb, &m)                     // transfer — receiver will put or dispose
```

There is no fourth option. A forgotten item starves the pool silently over time.

Every case branch of the receiver switch must end with one of these three. No exit without disposition.

---

## Design decisions

### Backpressure

Backpressure is implemented via the `on_put` hook in `FlowPolicy`.
The pool provides the `in_pool_count` for the specific item `id` to the hook.
The user's `on_put` implementation can then use this count to decide if the pool is over-capacity.

To apply backpressure, the hook consumes the item (by calling `dispose` on it and setting `m^ = nil`) instead of letting the pool recycle it.
This sheds load gracefully when a particular item type is being over-produced relative to consumption.

```odin
// Example on_put with backpressure
flow_on_put :: proc(ctx: rawptr, alloc: mem.Allocator, in_pool_count: int, m: ^Maybe(^PolyNode)) {
    if m == nil || m^ == nil { return } // Defensive nil check
    if m.?.id == int(FlowId.Chunk) && in_pool_count > 400 {
        // Too many chunks; consume this one instead of recycling.
        flow_dispose(ctx, alloc, m)
    }
}
```
This provides a simple, per-ID mechanism for managing memory growth. The policy is entirely in user code.

---

### Hooks and locking

Pool guarantees: hooks are always called **outside** the pool mutex.

```
// pool_get path
lock
  try pop from free-list
unlock

if item was popped {
    on_get(ctx, &m)          ← outside lock
} else {
    factory(ctx, alloc, id, count) ← outside lock
}

// pool_put path
lock
  get count for item id
unlock

on_put(ctx, alloc, count, &m)  ← outside lock

if m^ != nil {
    lock
      prepend to free-list
    unlock
}
```

**Why**: hooks receive `ctx` which can point to any user state including mutexes. Calling hooks inside the pool mutex would make deadlock trivially easy. Some OS do not support recursive mutexes — no assumption can be made.

**User responsibility**: what happens inside the hook is entirely user's concern. Pool makes no constraints beyond the mutex guarantee.
