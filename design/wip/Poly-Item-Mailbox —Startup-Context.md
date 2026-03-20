# ITC Poly-Item Mailbox — Startup Context (Condensed Working State)

## 1. Core idea

ITC is a **transport pipe**, not a framework.

It only moves:

```

^Maybe(^PolyNode)

````

It must NOT know:
- domain types
- business logic
- unions
- meaning of messages

All meaning is outside ITC.

---

## 2. Fundamental object model

### Base intrusive node

```odin
PolyNode :: struct {
    next: ^PolyNode,
    id:   int,   // runtime type identity (tag)
}
````

* `id` = user-defined type identifier
* must be stamped at creation time
* used for runtime dispatch only

---

## 3. Participant types (intrusive)

All message types must embed `PolyNode` at offset 0:

```odin
Chunk :: struct {
    using poly: PolyNode,
    data: [CHUNK_SIZE]byte,
    len:  int,
}

Progress :: struct {
    using poly: PolyNode,
    percent: int,
}
```

Rule:

* `PolyNode` MUST be first field (intrusive contract)

---

## 4. Type system (user-owned)

User defines ALL of the following:

### Identity

```odin
FlowId :: enum {
    Chunk,
    Progress,
}
```

### Structure (compile-time view)

```odin
FlowMsg :: union {
    ^Chunk,
    ^Progress,
}
```

### Important rule

These MUST stay consistent manually:

* `FlowId`
* `FlowMsg`
* pool supported ids

(No auto-sync yet)

---

## 5. Memory model

### One pool (heterogeneous)

```odin
Pool :: struct {
    free_list: ^PolyNode,
    ids:       []int,
    hooks:     Pool_Hooks,
    allocator: mem.Allocator,
}
```

Pool responsibilities:

* reuse memory
* allocate via factory
* validate ids
* reset/dispose via hooks

Pool does NOT know concrete types directly.

---

## 6. Hooks (user-owned logic)

```odin
Pool_Hooks :: struct {
    factory: proc(mem.Allocator, int) -> (^PolyNode, bool),
    reset:   proc(^PolyNode),
    dispose: proc(^Maybe(^PolyNode)),
}
```

Responsibilities:

* factory: create type from id
* reset: clear state
* dispose: free resources safely

---

## 7. Factory pattern (manual tagged polymorphism)

Factory maps `id → concrete type`:

```odin
switch FlowId(id) {
case .Chunk:
    return ^Chunk
case .Progress:
    return ^Progress
}
```

Each object must:

* embed PolyNode
* stamp `node.id = id`

---

## 8. Mailbox

Mailbox is opaque transport:

```odin
Mailbox :: struct {
    queue: ^PolyNode,
}
```

It operates ONLY on:

* `^Maybe(^PolyNode)`

No type knowledge inside ITC.

---

## 9. Ownership model (critical)

| Event            | Meaning               |
| ---------------- | --------------------- |
| pool_get         | caller owns item      |
| send success     | ownership transferred |
| send fail        | caller still owns     |
| receive          | receiver owns         |
| pool.put success | returned to pool      |
| foreign item     | returned to caller    |

`Maybe(^PolyNode)` encodes lifecycle state.

---

## 10. Runtime dispatch model

All type routing is manual:

```odin
switch node.id {
case .Chunk:
case .Progress:
}
```

This is:

* manual tagged polymorphism
* NOT language polymorphism
* NOT reflection

---

## 11. System dependency model

There are 3 coupled projections:

### A — Identity

```odin
FlowId
```

### B — Structure

```odin
FlowMsg (union)
```

### C — Lifecycle

```odin
Pool + factory/reset/dispose
```

Dependencies:

* A → B (must match exactly)
* A → C (controls allocation behavior)
* B ↔ C (must remain consistent manually)

---

## 12. Key constraints

* no dynamic polymorphism
* no reflection
* no hidden allocations inside ITC
* intrusive memory model
* zero-copy transport
* all types known at system design time
* no runtime type registration

---

## 13. Open design issues (future work)

* unify A/B/C into single source of truth
* reduce ownership state complexity
* formalize backpressure integration
* optional poly-item extension (multi-type flows)
* tooling for consistency validation

---

## 14. Mental model summary

ITC =

> “A deterministic transport of intrusive tagged objects with user-defined lifecycle and manual polymorphic dispatch.”

Not:

* framework
* message broker
* type system
* runtime dispatcher
