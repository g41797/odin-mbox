# odin-itc Poly-Items Design

This document describes how `odin-itc` can support **multiple item kinds in one system** (“poly-items”) while preserving its core principles:

- intrusive items
- zero-copy
- explicit ownership
- no runtime polymorphism

---

# 1. Problem Statement

Current design:

```text
Mailbox($T)
Pool($T)
````

✔ simple
✔ fast
❌ only one item type per flow

---

## Real Need

In real systems we have:

```text
Chunk
Progress
CompressedChunk
Error
Control
```

These must coexist in the same communication flow.

---

## Hard Constraints

* ❌ no dynamic typing
* ❌ no heap-based polymorphism
* ❌ no runtime reflection
* ✅ all types known at compile time
* ✅ still intrusive
* ✅ still zero-copy

---

# 2. Design Options

We explore 3 viable approaches:

---

# Option A — Tagged Union (Recommended Baseline)

## Idea

Wrap all variants into a single union type.

---

## Code

```odin
Message_Kind :: enum {
    Chunk,
    Progress,
    Compressed,
}

Message :: struct {
    next: ^Message,

    kind: Message_Kind,

    union {
        chunk: Chunk_Data,
        progress: Progress_Data,
        compressed: Compressed_Data,
    }
}
```

---

## Mailbox / Pool

```odin
Mailbox_Message :: Mailbox(Message)
Pool_Message    :: Pool(Message)
```

---

## Usage

```odin
msg := pool_get(&msg_pool)

msg.kind = .Chunk
msg.chunk = Chunk_Data{...}

send(&mbox, &msg)
```

---

## Receive

```odin
msg := recv(&mbox)

switch msg.kind {
case .Chunk:
    handle_chunk(msg.chunk)

case .Progress:
    handle_progress(msg.progress)

case .Compressed:
    handle_compressed(msg.compressed)
}

pool.put(&msg_pool, msg)
```

---

## T_HOOKS

```odin
Message_reset :: proc(msg: ^Message) {
    msg.kind = .Chunk // default or zero
}

Message_init :: proc(...) { ... }
Message_destroy :: proc(...) { ... }
```

---

## Pros

* ✔ simple mental model
* ✔ one mailbox for everything
* ✔ explicit handling via `switch`
* ✔ easy to document

---

## Cons

* ❌ large struct (max of all variants)
* ❌ wasted memory for small variants
* ❌ coupling between unrelated message types

---

## Developer Feeling

> “Clear and explicit. Feels like a protocol message.”

---

# Option B — Intrusive Base + Cast (Advanced)

## Idea

All items share a **common base header**, and are cast dynamically.

---

## Code

```odin
Item_Kind :: enum {
    Chunk,
    Progress,
    Compressed,
}

Item_Base :: struct {
    next: ^Item_Base,
    kind: Item_Kind,
}
```

### Concrete Types

```odin
Chunk :: struct {
    base: Item_Base,
    file_id: int,
    data: []u8,
}

Progress :: struct {
    base: Item_Base,
    file_id: int,
    processed: int,
}

Compressed :: struct {
    base: Item_Base,
    file_id: int,
    data: []u8,
}
```

---

## Mailbox / Pool

```odin
Mailbox_Item :: Mailbox(Item_Base)
```

Pools can be:

* per-type
* or unified allocator

---

## Usage

```odin
chunk := pool_chunk.get()
chunk.base.kind = .Chunk

send(&mbox, cast(^Item_Base)chunk)
```

---

## Receive

```odin
item := recv(&mbox)

switch item.kind {
case .Chunk:
    chunk := cast(^Chunk)item
    handle_chunk(chunk)

case .Progress:
    progress := cast(^Progress)item
    handle_progress(progress)
}
```

---

## T_HOOKS

Per-type:

```odin
Chunk_reset :: proc(c: ^Chunk) { ... }
Progress_reset :: proc(p: ^Progress) { ... }
```

Base-level:

```odin
Item_reset :: proc(base: ^Item_Base) {
    // optional generic logic
}
```

---

## Pros

* ✔ no wasted memory
* ✔ true per-type layout
* ✔ closer to intrusive philosophy
* ✔ flexible pools per type

---

## Cons

* ❌ unsafe casts (must trust kind)
* ❌ more boilerplate
* ❌ harder to teach
* ❌ weaker “single type” simplicity

---

## Developer Feeling

> “Low-level, powerful, but I must be careful.”

---

# Option C — Static Variant Set (Type-Level Composition)

## Idea

Define mailbox over a **fixed set of types**, enforced at compile time.

---

## Code (Conceptual)

```odin
MessageSet :: union {
    Chunk,
    Progress,
    Compressed,
}
```

Or:

```odin
Mailbox(Chunk, Progress, Compressed)
```

(Requires helper generics/macros)

---

## Usage

```odin
send_chunk(&mbox, chunk)
send_progress(&mbox, progress)
```

---

## Receive

```odin
msg := recv(&mbox)

match msg {
case Chunk:
case Progress:
case Compressed:
}
```

---

## T_HOOKS

Generated per variant:

```odin
reset_Chunk
reset_Progress
```

---

## Pros

* ✔ strong type safety
* ✔ expressive API
* ✔ no manual casting

---

## Cons

* ❌ requires heavy generic/meta support
* ❌ complex implementation
* ❌ less transparent
* ❌ may fight Odin simplicity

---

## Developer Feeling

> “Nice to use, but feels a bit magical.”

---

# 3. Pools Strategy

Poly-items require clear pool strategy:

---

## Option 1 — Single Pool (Tagged Union)

```text
Pool(Message)
```

✔ simple
❌ memory waste

---

## Option 2 — Per-Type Pools (Recommended with Base)

```text
Pool(Chunk)
Pool(Progress)
Pool(Compressed)
```

✔ efficient
✔ clear lifecycle
✔ matches ownership

---

## Option 3 — Hybrid

* base mailbox
* per-type pools

👉 best balance for Option B

---

# 4. Mailbox Behavior

Mailbox always operates on **one transport type**:

* Option A → `Message`
* Option B → `Item_Base`
* Option C → generated variant type

---

# 5. Recommended Path

### Phase 1 (NOW)

👉 **Option A (Tagged Union)**

* easiest to introduce
* clear semantics
* good documentation story

---

### Phase 2 (ADVANCED USERS)

👉 **Option B (Intrusive Base)**

* better performance
* better memory usage
* closer to itc philosophy

---

### Phase 3 (OPTIONAL)

👉 Option C if ecosystem demands it

---

# 6. New Idioms Introduced

With poly-items, developers will say:

```text
“I’ll send a Chunk”
“I’ll send Progress”
“I’ll handle Compressed”
```

Instead of:

```text
“I’ll send Message(kind=...)”
```

---

# 7. Key Insight

Poly-items are not just a feature.

They enable:

> **Real protocols inside itc**

Where message meaning matters, not just transport.

---

# 8. Final Takeaway

Supporting poly-items must preserve:

* intrusive design
* ownership clarity
* zero-copy movement
* simple mental model

If any solution breaks these —

it does not belong in `odin-itc`.
