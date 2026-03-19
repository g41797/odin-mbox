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
    hooks:      Pool_Hooks,
    allocator:  mem.Allocator,
    count:      int,
    max:        int,
}

Pool_Hooks :: struct {
    factory: proc(allocator: mem.Allocator, id: int) -> (^PolyNode, bool),
    reset:   proc(node: ^PolyNode),
    dispose: proc(m: ^Maybe(^PolyNode)),
}
```

### Init

```odin
pool.init(&p,
    hooks = FLOW_HOOKS,
    ids   = {int(FlowId.Chunk), int(FlowId.Progress)},
)
```

Pool stores the id list at runtime. Fixed after init.

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
Pool calls `factory(allocator, id)` when allocation is needed.
Factory allocates correct concrete type, stamps `node.id = id`, returns `^PolyNode`.
`m^` is non-nil on success.

### put

```odin
pool.put(&p, &m)
```

Checks `m.?.node.id` — must be in `pool.ids`.
Checks `m.?.allocator` — must match pool allocator.
Either mismatch → foreign item → returned to caller → caller disposes.
Both match → reset via hooks, return to free list.

### T_HOOKS

```odin
FLOW_HOOKS :: Pool_Hooks{
    factory = flow_factory,   // allocates per id, stamps node.id
    reset   = flow_reset,     // clears state for reuse per id
    dispose = flow_dispose,   // frees internal resources per id
}

flow_factory :: proc(allocator: mem.Allocator, id: int) -> (^PolyNode, bool) {
    switch FlowId(id) {
    case .Chunk:
        c := new(Chunk, allocator)
        if c == nil { return nil, false }
        c.allocator = allocator
        c.id = id
        return (^PolyNode)(c), true
    case .Progress:
        p := new(Progress, allocator)
        if p == nil { return nil, false }
        p.allocator = allocator
        p.id = id
        return (^PolyNode)(p), true
    }
    return nil, false
}

flow_reset :: proc(node: ^PolyNode) {
    switch FlowId(node.id) {
    case .Chunk:    (^Chunk)(node).len = 0
    case .Progress: (^Progress)(node).percent = 0
    }
}

flow_dispose :: proc(m: ^Maybe(^PolyNode)) {
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
defer flow_dispose(&m)              // [itc: defer-dispose] no-op if sent

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
defer flow_dispose(&m)              // [itc: defer-dispose] no-op if put, disposes if stuck

switch FlowId(m.?.node.id) {
case .Chunk:
    c := (^Chunk)(m.?)
    process_chunk(c)
    pool.put(&p, &m)                // [itc: defer-put] m^ = nil on success

case .Progress:
    pr := (^Progress)(m.?)
    update_progress(pr)
    pool.put(&p, &m)                // [itc: defer-put] m^ = nil on success
}
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
| after `pool.put` foreign | `m^` returned to caller — caller disposes |
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
- hooks dispatch — factory / reset / dispose routed by id

## What user owns

- id enum definition
- union definition
- all hooks implementations — factory / reset / dispose
- flow_send / flow_receive wrappers
- receiver switch and casting
- pool return after processing

---

## Open item — backpressure

Backpressure should inform what gets allocated — chunks, jobs, etc.
When the system is under pressure, the id passed to `pool.get` may change
based on downstream capacity signals.
To be designed separately.
