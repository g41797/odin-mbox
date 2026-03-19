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
    free_list: ^PolyNode,
    allocator: mem.Allocator,
    hooks:     Pool_Hooks,
}
```

---

## Hooks (your lifecycle system)

```odin
Pool_Hooks :: struct {
    factory: proc(mem.Allocator, int) -> (^PolyNode, bool),
    reset:   proc(^PolyNode),
    dispose: proc(^Maybe(^PolyNode)),
}
```

---

## Results

```odin
GetResult :: enum {
    Ok,
    Empty,
    Already_In_Use,
    Alloc_Failed,
}

PutResult :: enum {
    Ok,
    Foreign,
    Already_Empty,
}
```

---

## init / destroy

```odin
pool_init :: proc(
    p: ^Pool,
    allocator: mem.Allocator,
    hooks: Pool_Hooks,
)

pool_destroy :: proc(p: ^Pool)
```

### destroy behavior

* drains free_list
* calls `dispose` on each node

---

## get (acquire ownership)

```odin
pool_get :: proc(
    p: ^Pool,
    id: int,
    out: ^Maybe(^PolyNode),
) -> GetResult
```

---

### Contract

* **Entry**

  * `out == nil` → `.Empty`
  * `out^ != nil` → `.Already_In_Use`
* **Behavior**

  * try free_list
  * else use `factory(id)`
* **Success**

  * `out^ = node`
* **Failure**

  * `out^` unchanged

---

## put (return to pool)

```odin
pool_put :: proc(
    p: ^Pool,
    m: ^Maybe(^PolyNode),
) -> (ptr: ^Maybe(^PolyNode), result: PutResult)
```

---

### Contract

* **Entry**

  * `m == nil` → `.Already_Empty`
  * `m^ == nil` → `.Already_Empty`
* **Behavior**

  * if compatible:

    * call `reset`
    * push to free_list
    * `m^ = nil`
    * return `(nil, .Ok)`
  * else:

    * do NOT consume
    * return `(m, .Foreign)`

---

## put_all (for batch)

```odin
pool_put_all :: proc(
    p: ^Pool,
    m: ^Maybe(^PolyNode),
)
```

* walks linked list
* applies `put` per node

---

---

# 4. Dispose API (global rule)

```odin
dispose :: proc(m: ^Maybe(^PolyNode))
```

### Contract

* safe on:

  * `m == nil`
  * `m^ == nil`
* must:

  * free all resources
  * set `m^ = nil`

---

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
pool_get(&pool, id, &m)
defer dispose(&m)

// use
// fill data

// send
if mbox_send(&mb, &m) != .Ok {
    return // dispose handles cleanup
}

// receive
mbox_wait_receive(&mb, &m)

// process
switch m.?.id {
case .Chunk:
}

// return to pool
ptr, res := pool_put(&pool, &m)
if res == .Foreign && ptr^ != nil {
    dispose(ptr)
}
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
