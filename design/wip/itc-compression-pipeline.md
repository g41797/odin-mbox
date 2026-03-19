# odin-itc Demo: Ownership-Driven Data Flow (Compression Pipeline)

This document shows how to build a simple multi-threaded process using `odin-itc`.

The goal is not to demonstrate APIs, but to show a different way of thinking:

> Developers stop reasoning about locks and start reasoning about  
> **data flow, ownership, and lifecycle**

---

# 1. The Problem (Real Conversation)

```text
Main: I need to compress large files.

Worker: Send me file chunks.

Main: Whole files?

Worker: No, chunks. I process data incrementally.

Main: What happens after I send a chunk?

Worker: I start processing it immediately.

Main: How do I track progress?

Worker: While I work, I’ll report how many bytes I’ve processed.

Main: And the result?

Worker: I’ll send compressed chunks back.

Main: Can I send multiple files?

Worker: Yes. Just mark chunks with a file ID.

Main: So you're processing and communicating at the same time?

Worker: Exactly. Work never blocks communication.
````

---

# 2. The Picture

```text
          +------------------+
          |     Main         |
          | (File Reader)    |
          +------------------+
                    |
                    |  Chunk(file_id, offset)
                    ▼
        =========================
        ||     Mailbox        ||
        =========================
          │        │        │
          ▼        ▼        ▼
     +--------+ +--------+ +--------+
     |Worker 1| |Worker 2| |Worker 3|
     |Compress| |Compress| |Compress|
     +--------+ +--------+ +--------+
          │        │        │
          └────┬───┴───┬────┘
               ▼       ▼
        =========================
        ||     Mailbox        ||
        =========================
                    |
                    ▼
          +------------------+
          |     Main         |
          | (Writer)         |
          +------------------+
```

This is the system.

No shared state. Only moving data.

---

# 3. What Actually Moves

We don’t send “jobs”. We send real data:

```odin
Chunk :: struct {
    next: ^Chunk,
    file_id: int,
    offset:  int,
    data:    []u8,
}

Progress :: struct {
    next: ^Progress,
    file_id: int,
    processed_bytes: int,
}

CompressedChunk :: struct {
    next: ^CompressedChunk,
    file_id: int,
    offset:  int,
    data:    []u8,
}
```

All items are:

* intrusive
* moved by pointer (zero-copy)
* owned by exactly one participant at a time

---

# 4. How Developers Talk

Without `odin-itc`, developers say:

```text
lock this
wait here
signal there
protect shared state
```

With `odin-itc`, the same system becomes:

```text
I’ll get a chunk from the pool
I’ll process it
I’ll send you the result
I’ll return it to the pool
```

> Synchronization still exists — but it is no longer part of the conversation.

---

# 5. The Core Building Blocks

* **Masters** — own logic and state
* **Mailboxes** — move items between participants
* **Pools** — manage lifecycle and reuse
* **Items** — the data that moves

Each has a single responsibility.

---

# 6. Flow (What Actually Happens)

From the outside, the system behaves like this:

```text
Main reads file → creates Chunk → sends

Worker receives Chunk → processes → sends:
    - Progress (while working)
    - CompressedChunk (when ready)

Main receives → writes output → recycles memory
```

Processing and communication are naturally interleaved.

Nothing blocks the whole system.

---

# 7. Ownership (The Rule That Makes It Work)

All transfers follow one rule:

> Ownership must move.

When sending:

```odin
send(mailbox, &item)
```

* If send succeeds → sender loses ownership (`item = nil`)
* If send fails → sender still owns the item

This guarantees:

* no double free
* no lost data
* no shared mutable state

---

# 8. Memory Lifecycle (Pools)

All items follow:

```text
Create → Reset → Use → Recycle → Destroy
```

Pools ensure:

* no constant allocation
* predictable performance
* clear ownership boundaries

---

# 9. What This Is NOT

This system does **not** remove synchronization.

Internally:

* mailboxes may use locks
* operations may block or timeout

But:

> Synchronization is isolated inside well-defined components
> and never leaks into domain logic

---

# 10. What This Changes

Instead of thinking:

```text
Who owns this memory?
Who holds the lock?
Who is waiting?
```

You think:

```text
Where does this chunk go next?
Who owns it now?
When do I return it?
```

---

# 11. Why This Scales

You can extend the system without changing the model:

* more workers → just add Masters
* multiple files → just add file_id
* different processing stages → add more mailboxes
* backpressure → control send/recv behavior

The vocabulary stays the same.

---

# 12. Future Requirement: Poly-Items

Current design:

> Each mailbox and pool operates on a single type `$T`

This is simple and efficient, but introduces a limitation:

* real systems require multiple item kinds
  (Chunk, Progress, Result, etc.)

---

## Requirement

Support **poly-items** under these constraints:

* all possible item types are known at compile time
* no dynamic typing
* no runtime type discovery

---

## Design Direction (to be implemented)

* tagged unions or equivalent
* shared intrusive base layout
* mailbox support for a fixed set of item variants

---

## Impact

This will affect:

* API design
* message handling patterns
* pool organization
* documentation and idioms

---

# 13. Takeaway

This is not just a library.

It is a way to build systems where:

* data moves instead of being shared
* ownership is always clear
* developers speak the same language

```text
“I’ll get a chunk from the pool,
process it,
and send it back.”
```

If that sentence is enough to understand the system,

the model works.

```

---

# ✅ What You Have Now

This is already:

- coherent
- honest
- grounded in real work
- aligned with your philosophy
- extensible (poly-items noted, not forced)

---

# 👉 If You Want Next Iteration

We can later:

1. Add **actual Odin code (compilable skeleton)**
2. Design **poly-item API properly**
3. Improve **diagram into SVG**
4. Add **timeouts / failure semantics explicitly**
5. Tighten wording (make it even sharper, less words)

---
