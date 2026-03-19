
---

# 0. Core principle of the refactor

We simplify everything to 3 truths:

```text id="kq1m2a"
1. ITC moves pointers (^PolyNode)
2. Ownership is explicit at call boundaries
3. Everything else is just user code
```

No hidden protocol layers inside ITC.

---

# 1. The biggest Odin correction: remove Maybe from ITC core

This is the key change.

## ❌ Current model:

```odin
^Maybe(^PolyNode)
```

## ❗ Odin-perfect model:

```odin
^PolyNode
```

### Why?

Because in Odin-style systems:

> “Transport does not encode ownership semantics in types that hide control flow.”

Instead, ownership is expressed by **return values and explicit API contracts**, not container types inside pointers.

---

## So we split responsibilities:

| Concern           | Location     |
| ----------------- | ------------ |
| pointer existence | ITC          |
| ownership state   | API contract |
| failure           | return codes |

---

# 2. ITC becomes extremely small

## ITC core (final shape)

```odin
PolyNode :: struct {
    next: ^PolyNode,
    id:   int,
}

Mailbox :: struct {
    head: ^PolyNode,
    tail: ^PolyNode,
}
```

No Maybe. No hooks. No lifecycle logic.

---

## Send / Receive (Odin style)

```odin
SendResult :: enum {
    Ok,
    Closed,
    Full,
}
```

### send

```odin
itc_send :: proc(mb: ^Mailbox, n: ^PolyNode) -> SendResult {
    if mb == nil || n == nil {
        return .Closed
    }

    // enqueue
    n.next = nil

    if mb.tail != nil {
        mb.tail.next = n
    } else {
        mb.head = n
    }

    mb.tail = n
    return .Ok
}
```

✔ no Maybe mutation
✔ no hidden ownership encoding
✔ explicit result

---

### receive

```odin
itc_recv :: proc(mb: ^Mailbox) -> (^PolyNode, bool) {
    if mb == nil || mb.head == nil {
        return nil, false
    }

    n := mb.head
    mb.head = n.next

    if mb.head == nil {
        mb.tail = nil
    }

    n.next = nil
    return n, true
}
```

---

# 3. Ownership becomes caller responsibility (Odin style)

Instead of encoding ownership in Maybe, we do:

```odin
n, ok := itc_recv(&mb)
if !ok {
    return
}

// caller now owns n
```

This is very Odin:

> “You are responsible for what you explicitly receive.”

---

# 4. Pool becomes independent (no hooks, no framework inversion)

Your previous design:

* factory
* reset
* dispose hooks
* T_Hooks registry

## Odin version: explicit functions only

```odin
Pool :: struct {
    free_list: ^PolyNode,
    allocator: mem.Allocator,
}
```

---

## get

```odin
pool_get :: proc(p: ^Pool) -> ^PolyNode {
    if p.free_list != nil {
        n := p.free_list
        p.free_list = n.next
        n.next = nil
        return n
    }

    return nil
}
```

---

## put

```odin
pool_put :: proc(p: ^Pool, n: ^PolyNode) {
    if n == nil {
        return
    }

    n.next = p.free_list
    p.free_list = n
}
```

---

## Key Odin simplification:

> No callbacks. No lifecycle injection. No hidden behavior.

---

# 5. Where lifecycle logic goes (IMPORTANT SHIFT)

Instead of Pool owning lifecycle rules:

## BEFORE:

Pool → reset/factory/dispose hooks

## AFTER (Odin style):

Caller owns lifecycle.

Example:

```odin
reset_chunk :: proc(c: ^Chunk) {
    c.len = 0
}
```

And caller does:

```odin
reset_chunk(ptr)
pool_put(&pool, ptr)
```

✔ explicit
✔ no inversion
✔ no hidden behavior

---

# 6. FlowId + dispatch (kept, but simplified)

You still need runtime identity:

```odin
FlowId :: enum {
    Chunk,
    Progress,
}
```

---

## dispatch remains manual (good Odin style)

```odin
switch n.id {
case .Chunk:
    c := (^Chunk)(n)
case .Progress:
    p := (^Progress)(n)
}
```

✔ perfect Odin style
✔ no runtime type system
✔ no reflection

---

# 7. What we REMOVE completely in Odin refactor

These disappear:

### ❌ Maybe(^PolyNode)

→ replaced by explicit return values

### ❌ T_Hooks system

→ replaced by plain functions

### ❌ factory/reset/dispose registry

→ replaced by direct calls

### ❌ ownership encoded in container types

→ replaced by return contracts

---

# 8. What we KEEP (important)

### ✔ intrusive node

```odin
PolyNode { next, id }
```

### ✔ manual dispatch

```odin
switch node.id
```

### ✔ pools

but simplified

### ✔ mailbox queue

but explicit

### ✔ zero-copy transport

absolutely preserved

---

# 9. The new mental model (Odin-perfect)

## ITC is now:

```text id="p9m3zx"
A pointer queue with explicit ownership transfer semantics enforced by API contracts.
```

NOT:

* a type system
* a framework
* a lifecycle engine

---

# 10. Full system flow (clean version)

## send side:

```odin
n := pool_get(&pool)
fill(n)

if itc_send(&mb, n) != .Ok {
    pool_put(&pool, n) // still owned by sender
}
```

---

## receive side:

```odin
n, ok := itc_recv(&mb)
if !ok {
    return
}

switch n.id {
case .Chunk:
    c := (^Chunk)(n)
    process(c)
    reset_chunk(c)
    pool_put(&pool, n)
}
```

---

# 11. Why this is “Odin-perfect”

Because it follows all core Odin instincts:

### ✔ explicit control flow

no hidden state machines

### ✔ no inversion of control

no callbacks, no hooks

### ✔ ownership is visible at call site

no semantic encoding in pointer wrappers

### ✔ simple structs + functions

no framework layer inside library

### ✔ manual dispatch

Odin’s preferred polymorphism model

---

# 12. Trade-off (important honesty)

You lose:

* some safety automation
* centralized lifecycle enforcement
* compile-time coupling checks

You gain:

* extreme clarity
* zero magic
* predictable performance
* easier debugging

---

# 13. If you want next step

We can go deeper in 3 directions:

### A. “Lock-free Odin ITC”

Make mailbox concurrent (SPSC/MPMC) properly

### B. “Memory safety layer (without hooks)”

Add optional debug invariants without runtime cost

### C. “Reintroduce safety without losing Odin purity”

Design a *lightweight FlowSpec validator* that doesn’t become a framework

Just tell me which direction.
