* intrusive nodes
* `^Maybe(^T)` everywhere for ownership
* explicit transfer rules
* minimal ambiguity
* error-resistant

No philosophy — just **coherent, consistent API**.

---

# 1. Core types (shared)

```odin
PolyNode :: struct {
    next: ^PolyNode,
    id:   int,
}
```

---

# 2. Mailbox API (transport only)

## Types

```odin
Mailbox :: struct {
    head: ^PolyNode,
    tail: ^PolyNode,
    closed: bool,
}

SendResult :: enum {
    Ok,
    Closed,
    Full,
    Invalid,
    Already_In_Use,
}

RecvResult :: enum {
    Ok,
    Empty,
    Closed,
    Already_In_Use,
}
```

---

## init / destroy

```odin
mbox_init :: proc(mb: ^Mailbox)
mbox_destroy :: proc(mb: ^Mailbox)
```

---

## send (ownership transfer)

```odin
mbox_send :: proc(mb: ^Mailbox, m: ^Maybe(^PolyNode)) -> SendResult
```

### Contract

* **Entry**

  * `m == nil` → `.Invalid`
  * `m^ == nil` → `.Invalid`
* **Success**

  * enqueue node
  * `m^ = nil` (ownership transferred)
* **Failure**

  * `m^` unchanged

---

## push (non-blocking variant)

```odin
mbox_push :: proc(mb: ^Mailbox, m: ^Maybe(^PolyNode)) -> SendResult
```

Same contract as `send`, but must not block.

---

## receive (blocking or wait variant)

```odin
mbox_wait_receive :: proc(mb: ^Mailbox, out: ^Maybe(^PolyNode)) -> RecvResult
```

### Contract

* **Entry**

  * `out == nil` → `.Invalid`
  * `out^ != nil` → `.Already_In_Use`
* **Success**

  * dequeue node
  * `out^ = node` (ownership transferred)
* **Failure**

  * `out^` unchanged

---

## try_receive (non-blocking)

```odin
mbox_try_receive :: proc(mb: ^Mailbox, out: ^Maybe(^PolyNode)) -> RecvResult
```

Returns `.Empty` if no data.

---

## try_receive_batch (optional but powerful)

```odin
mbox_try_receive_batch :: proc(
    mb: ^Mailbox,
    out: ^Maybe(^PolyNode), // becomes head of chain
    count: ^int
) -> RecvResult
```

### Behavior

* returns a **linked chain** of nodes
* `out^` becomes first node
* caller owns entire chain

---

## close

```odin
mbox_close :: proc(mb: ^Mailbox)
```

### Effects

* further send → `.Closed`
* receive continues until empty
* then returns `.Closed`

---

---

# 3. Pool API (lifecycle + reuse)

## Types

```odin
Pool :: struct {
    // Internal fields for MPMC free-lists, accounting, etc.
    // User interacts via API, not direct field access.
}

Pool_Get_Mode :: enum {
    Recycle_Or_Alloc, // Default: Pop from free-list; if empty, call factory()
    Alloc_Only,       // Standalone: Bypass free-list; always call factory()
    Recycle_Only,     // Pool-Only: Pop from free-list; if empty, return false
}
```

---

## FlowPolicy (The Brain)

```odin
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

---

## init / destroy

```odin
pool_init :: proc(p: ^Pool, policy: FlowPolicy, alloc := context.allocator)
pool_destroy :: proc(p: ^Pool)
```

### destroy behavior

*   Drains all free-lists.
*   Calls `policy.dispose` on each node.

---

## get (acquire ownership)

```odin
pool_get :: proc(p: ^Pool, id: int, mode: Pool_Get_Mode, out: ^Maybe(^PolyNode)) -> (ok: bool)
```

### Contract

*   **`Recycle_Or_Alloc`**: Checks free-list first. Calls `on_get` on hit. Calls `factory` on miss.
*   **`Alloc_Only`**: Always calls `factory`.
*   **`Recycle_Only`**: Only checks free-list. Fails if empty.
*   Returns `true` on success, `false` on failure. `out^` is set on success.

---

## put (return to pool)

```odin
pool_put :: proc(p: ^Pool, m: ^Maybe(^PolyNode))
```

### Contract

*   The pool executes the mechanism for returning an item, delegating all lifecycle decisions to `FlowPolicy`.
*   It calls the `on_put` hook from the `FlowPolicy`, which implements the actual logic.
*   After `pool_put`, `m^` is always nil for valid (own) items. If `m^ != nil` after the call, the item was not accepted by the pool (foreign id) — caller still owns it.

---

## put_all (for batch)

```odin
pool_put_all :: proc(
    p: ^Pool,
    m: ^Maybe(^PolyNode),
)
```

*   walks linked list
*   applies `put` per node



---

# 5. Unified ownership rules (applies to ALL APIs)

This is the **core consistency** you built.

---

## Entry states

| State       | Meaning             |
| ----------- | ------------------- |
| `m == nil`  | invalid handle      |
| `m^ == nil` | caller owns nothing |
| `m^ != nil` | caller owns item    |

---

## Exit states

| Result                  | Meaning               |
| ----------------------- | --------------------- |
| `m^ = nil`              | ownership transferred |
| `m^ unchanged`          | transfer failed       |
| `m^ = nil` (error case) | consumed internally   |

---

---

# 6. Full lifecycle (end-to-end)

```odin
m: Maybe(^PolyNode)

// acquire
if !pool_get(&pool, id, .Recycle_Or_Alloc, &m) {
    return // or handle error
}
defer pool_put(&pool, &m) // Safety net: if m^ is non-nil (not transferred), pool_put recycles or on_put disposes

// use
// fill data...
// c := (^Chunk)(m.?); c.len = ...

// send
if mbox_send(&mb, &m) != .Ok {
    return // defer pool_put handles cleanup
}

// receive
// Note: In a real scenario, sender and receiver are in different threads.
// The 'm' variable would be different. This is a conceptual flow.
mbox_wait_receive(&mb, &m)
defer pool_put(&pool, &m) // Safety net for receiver side

// process
switch m.?.id {
case .Chunk:
    // process chunk...
}

// return to pool
pool_put(&pool, &m)
// If m^ != nil here, item is foreign — caller retains ownership
```

---

# 7. What this achieves

### ✔ Single ownership variable

(no aliasing bugs)

### ✔ Uniform API contract

(all functions behave the same)

### ✔ Structural safety

(errors become hard to express)

### ✔ Zero-copy

(no data duplication)

### ✔ Extensible

(types remain external)

---

# 8. One-line system definition

> **Mailbox moves ownership, Pool manages lifecycle, `Maybe(^T)` enforces correctness.**
