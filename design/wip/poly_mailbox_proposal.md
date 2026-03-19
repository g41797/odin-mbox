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
- reset — clears state for reuse per id
- dispose — frees internal resources per id
- flow_send — wraps `^Maybe(^T)` → `^Maybe(^PolyNode)`, calls `mbox.send`
- flow_receive — calls `mbox.wait_receive`, switches on `node.id`, casts to `FlowMsg`

itc provides the pipe. User provides the protocol.

---

## Pool

One pool. Not one pool per type.

### Definition

```odin
Pool_Mode :: enum {
    Always,     // take from free list if available, allocate if empty
    Standalone, // always allocate, never touch free list
    Pool_Only,  // free list only, error if empty — never allocates
}

Pool :: struct {
    free_list:  ^PolyNode,
    ids:        []int,           // supported ids — fixed after init
    hooks:      Pool_Hooks,      // ctx carried inside hooks
    count:      int,
    max:        int,
}

Pool_Hooks :: struct {
    ctx:     rawptr,                                                          // passed to every hook — user context
    factory: proc(ctx: rawptr, id: int) -> (^PolyNode, bool),
    reset:   proc(ctx: rawptr, node: ^PolyNode),
    dispose: proc(ctx: rawptr, m: ^Maybe(^PolyNode)),
    accept:  proc(ctx: rawptr, id: int, current_count: int) -> bool,         // nil = always recycle
}
```

### Init

```odin
// hooks defined at compile time — ctx set at runtime
FLOW_HOOKS :: Pool_Hooks{
    factory = flow_factory,
    reset   = flow_reset,
    dispose = flow_dispose,
}

hooks := FLOW_HOOKS
hooks.ctx = &master                  // runtime — ctx points to Master or any user state

pool.init(&p,
    hooks = hooks,
    ids   = {int(FlowId.Chunk), int(FlowId.Progress)},
)
```

Pool stores the id list and hooks at runtime. Fixed after init.
`ctx` is runtime — cannot be set in a `::` constant.

### Three modes

Mode is a per-call parameter of `get`. Not a pool policy.

| Mode | Behavior |
|---|---|
| `.Always` | take from free list if available, allocate if empty |
| `.Standalone` | always allocate, never touch free list |
| `.Pool_Only` | free list only, error if empty — never allocates |

### get

```odin
m: Maybe(^PolyNode)
pool.get(&p, &m, int(FlowId.Chunk), .Always)
```

Runtime check on entry: `id` must be in `pool.ids` — error if not.
Mode drives allocation strategy for this call.
Pool calls `factory(hooks.ctx, id)` when allocation is needed.
Factory uses `ctx` to reach allocator and any other needed state.
Factory allocates correct concrete type, stamps `node.id = id`, returns `^PolyNode`.
`m^` is non-nil on success.

### put

```odin
pool.put(&p, &m)
```

Checks `m.?.node.id` — must be in `pool.ids`.
Checks allocator via `hooks.ctx` — item allocator must match.
Either mismatch → foreign item → returned to caller → caller calls `pool.dispose`.
Both match → calls `accept(ctx, id, current_count)` outside lock:
- `accept` returns true → reset via hooks, return to free list
- `accept` returns false → treat as foreign — returned to caller → caller calls `pool.dispose`
- `accept` is nil → always recycle (default behavior)

### Pool_Hooks

```odin
// compile-time constant — proc pointers only, no ctx
FLOW_HOOKS :: Pool_Hooks{
    factory = flow_factory,   // allocates per id via ctx
    reset   = flow_reset,     // clears state for reuse per id
    dispose = flow_dispose,   // frees internal resources per id
    accept  = flow_accept,    // nil = always recycle
}

// ctx carries Master — hooks reach allocator and any other state
flow_factory :: proc(ctx: rawptr, id: int) -> (^PolyNode, bool) {
    m := (^Master)(ctx)
    switch FlowId(id) {
    case .Chunk:
        c := new(Chunk, m.allocator)
        if c == nil { return nil, false }
        c.allocator = m.allocator
        c.id = id
        return (^PolyNode)(c), true
    case .Progress:
        p := new(Progress, m.allocator)
        if p == nil { return nil, false }
        p.allocator = m.allocator
        p.id = id
        return (^PolyNode)(p), true
    }
    return nil, false
}

flow_reset :: proc(ctx: rawptr, node: ^PolyNode) {
    switch FlowId(node.id) {
    case .Chunk:    (^Chunk)(node).len = 0
    case .Progress: (^Progress)(node).percent = 0
    }
}

flow_dispose :: proc(ctx: rawptr, m: ^Maybe(^PolyNode)) {
    if m == nil  { return }
    if m^ == nil { return }
    node := m^
    switch FlowId(node.id) {
    case .Chunk:
        c := (^Chunk)(node)
        free(c, c.allocator)
    case .Progress:
        p := (^Progress)(node)
        free(p, p.allocator)
    }
    m^ = nil
}

// accept — limit by count per id
// pool passes current free list count for this id
// nil accept = always recycle
flow_accept :: proc(ctx: rawptr, id: int, current_count: int) -> bool {
    switch FlowId(id) {
    case .Chunk:    return current_count < 400   // max 400 chunks in free list
    case .Progress: return current_count < 128   // max 128 progress items
    }
    return false
}
// For byte-level limits (e.g. 400MB total): user maintains a byte counter
// in ctx, calls pool.dispose manually instead of pool.put when limit exceeded.
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
pool.get(&p, &m, int(FlowId.Chunk), .Always)
defer pool.dispose(&p, &m)         // [itc: defer-dispose] no-op if sent

// fill — cast to concrete type
c := (^Chunk)(m.?)
c.len = fill(c.data[:])

// send — m^ = nil on success, dispose is no-op
mbox.send(&mb, &m)
```

### Receiver side

```odin
m: Maybe(^PolyNode)
mbox.wait_receive(&mb, &m)
defer pool.dispose(&p, &m)         // [itc: defer-dispose] safety net — fires if put not reached

switch FlowId(m.?.id) {
case .Chunk:
    c := (^Chunk)(m.?)
    process_chunk(c)
    pool.put(&p, &m)               // golden rule 2: must return — m^ = nil on success

case .Progress:
    pr := (^Progress)(m.?)
    update_progress(pr)
    pool.put(&p, &m)               // golden rule 2: must return — m^ = nil on success
}
// every case ends with pool.put — no exit without disposition
```

Receiver switch is user code. itc delivers `^PolyNode` and the `id`. User casts, processes, returns to pool.

---

## Ownership rules

| Event | Rule |
|---|---|
| after `pool.get` | caller owns via `Maybe(^PolyNode)` — inner non-nil |
| after `send` success | `m^` = nil — transfer complete |
| after `send` failure | `m^` unchanged — caller still holds, dispose runs |
| after `wait_receive` | receiver owns via `Maybe(^PolyNode)` — inner non-nil |
| after `pool.put` success | `m^` = nil — returned to pool |
| after `pool.put` foreign | `m^` returned to caller — caller calls `pool.dispose` |
| `defer-dispose` | no-op if transferred or put, frees if stuck |

---

## Runtime checks summary

| Location | Check | On failure |
|---|---|---|
| `pool.get` | id in pool.ids | error |
| `pool.put` | id in pool.ids | foreign — return to caller |
| `pool.put` | allocator matches | foreign — return to caller |
| receiver switch | id known to user | default case — dispose |

No compile-time checking from itc. All checks are runtime.
User is responsible for correctness of casts and switch coverage.

---

## What itc owns

- `PolyNode` shape — `next` + `id`
- pool modes — always / standalone / pool-only — per `get` call
- id list validation at `get` and `put`
- `^Maybe(^PolyNode)` contract across all APIs
- hooks dispatch — factory / reset / dispose / accept called with `ctx`
- hooks called **outside** pool mutex — guaranteed
- `accept` — pool passes `current_count` per id, hook returns yes/no
- `mbox.close` — returns remaining list as `^PolyNode` head

## What user owns

- id enum definition
- union definition
- all hooks implementations — factory / reset / dispose / accept
- hooks locking — user is responsible for any synchronization inside hooks
- count limits per id — expressed in `accept`
- byte-level limits — user responsibility, via manual `pool.dispose` instead of `pool.put`
- flow_send / flow_receive wrappers
- receiver switch and casting
- **must return every item to pool** — via `pool.put`, `pool.dispose`, or `mbox.send`

---

## Golden rules

### Rule 1 — one variable, whole lifetime

One `Maybe(^PolyNode)` variable from `pool.get` to final disposition. Never copy the inner pointer into a second `Maybe`. Same variable through get → send → receive → put → dispose.

### Rule 2 — every item must be returned

Every item acquired from the pool must be returned. No exceptions. No detours.

Three valid endings:

```
pool.put(&p, &m)       // recycle — normal path after processing
pool.dispose(&p, &m)   // destroy — shutdown, foreign, or byte limit exceeded
mbox.send(&mb, &m)     // transfer — receiver will put or dispose
```

There is no fourth option. A forgotten item starves the pool silently over time.

Every case branch of the receiver switch must end with one of these three. No exit without disposition.

---

## Design decisions

### Backpressure

Signal travels on a separate `WakeUper` — pure wake, no value, no data.
Producer checks the backpressure channel before each `pool.get` and decides which `id` to request.
Receiver controls the signal — it knows when it is falling behind.

```
normal:       pool.get(.Chunk, .Always)    → fill → send
backpressure: WakeUper fires              → pool.get(.Progress, .Always) or skip
```

This closes the loop on `id` selection — the `id` passed to `pool.get` changes based on the `WakeUper` signal. No changes to pool or mailbox needed. itc provides the mechanism. User decides the policy.

---

### Hooks and locking

Pool guarantees: hooks are always called **outside** the pool mutex.

```
lock
  decide: recycle from free list or allocate fresh
unlock

factory(ctx, id)           ← outside lock — safe to acquire any lock
reset(ctx, node)           ← outside lock — safe to acquire any lock
accept(ctx, id, count)     ← outside lock — safe to acquire any lock

lock
  if accept → return item to caller / prepend to free list
unlock
```

Same for dispose:

```
lock
  remove from accounting
unlock

dispose(ctx, &m)      ← outside lock — safe to acquire any lock

lock
  update count
unlock
```

**Why**: hooks receive `ctx` which can point to any user state including mutexes. Calling hooks inside the pool mutex would make deadlock trivially easy. Some OS do not support recursive mutexes — no assumption can be made.

**User responsibility**: what happens inside the hook is entirely user's concern. Pool makes no constraints beyond the mutex guarantee.

---

### accept — per-id count limiting

Pool provides per-id count limiting via the `accept` hook.
Pool passes `current_count` — the number of items currently in the free list for that id.
Hook returns true to recycle, false to treat as foreign (caller disposes).

```odin
flow_accept :: proc(ctx: rawptr, id: int, current_count: int) -> bool {
    switch FlowId(id) {
    case .Chunk:    return current_count < 400
    case .Progress: return current_count < 128
    }
    return false
}
```

nil `accept` = always recycle. Default behavior, no limits.

**Byte-level limits**: pool cannot express these — it is type-erased and does not know item sizes. User maintains a byte counter in `ctx` and calls `pool.dispose` manually instead of `pool.put` when the limit is exceeded.
