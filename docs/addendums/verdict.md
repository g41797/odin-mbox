# matryoshka — Architecture Review (Contradictions + Human Fixes)

Author perspective:
- software architect
- multithreading focus
- Odin-specific reasoning

Reader target:
- mid-level programmer
- not the original author
- not living inside your head

---

# 1. Core Strength (Do NOT lose this)

The system has a **very strong unifying idea**:

- intrusive node
- explicit ownership (`Maybe`)
- ownership transfer instead of sharing

This is good.
This is rare.
This is worth preserving.

---

# 2. Critical Contradictions

## 2.1 "No hidden system" — FALSE

README claims:

> No hidden system.
> No second model.

Reality:

- Builder exists (Layer 1)
- Master exists (Layer 2)
- Recycler exists (Layer 3)
- Internal `_Mbox`, `_Pool` exist (Layer 4)
- ID system is required but implicit
- Destructor (`dtor`) appears out of nowhere

❗ This is a **hidden system**.

### Fix

Replace claim with:

> There is one ownership model.
> There are multiple services built on top of it.

---

## 2.2 "One rule" — MISLEADING

README:

> Everything follows one rule

Reality:

There are at least **five independent rules**:

1. Intrusive layout (offset 0)
2. Ownership via `Maybe`
3. ID semantics (positive vs negative)
4. Lifecycle discipline (send/receive/dispose)
5. Service-specific contracts (Mailbox, Pool, etc.)

These are NOT one rule.

### Fix

Rename to:

> One model. Multiple rules.

---

## 2.3 Pool semantics contradiction

README:

```

on_put:

* set m^ = nil → destroy
* leave m^ → keep

```

But deeper docs imply:

- Pool may enforce limits
- Pool may override decision
- Pool may drop items

❗ Conflict: who decides?

### Reality

There are **two decision layers**:

- user hook (`on_put`)
- pool policy (limits, pressure)

### Fix

Explicit contract:

```

on_put expresses intent
pool enforces policy
final decision is pool’s

```

---

## 2.4 "Nothing is shared" — NOT TRUE

Claim:

> nothing is shared

Reality:

- Mailbox internal queue is shared
- Pool internal lists are shared
- synchronization exists

What you mean:

> user data is not shared

### Fix

Replace with:

> user data is never shared across threads

---

## 2.5 Mailbox ownership vs lifetime

README:

```

mbox_send → ownership leaves you
mbox_receive → ownership comes to you

```

But:

```

mbox_close(mb)
matryoshka_dispose(&m)

```

❗ Missing rule:

- what happens to items still inside mailbox?

Undefined.

### Fix (REQUIRED)

Define clearly:

- drain?
- reject?
- destroy?
- return to sender?

---

## 2.6 Builder vs Recycler overlap

Layer 1:
- Builder creates/destroys

Layer 3:
- Recycler does same in hooks

❗ Concept duplication

### Fix

State explicitly:

```

Recycler replaces Builder in pooled systems
Builder is a special case of Recycler

```

---

## 2.7 "Mailbox is an item" — unsafe abstraction leak

Layer 4:

```

Mailbox :: distinct ^PolyNode

```

But:

- user must NOT pool it
- user must NOT treat it like normal data
- user must close before dispose

❗ So it's NOT a regular item.

### Fix

Define:

```

Infrastructure items follow ownership rules
BUT have additional lifecycle constraints

```

---

# 3. Missing Critical Concepts

## 3.1 Who destroys on failure?

Example:

```

if mbox_send(...) != .Ok {
free(c)
}

```

But in general:

- who owns on partial failure?
- what about `.Closed`?
- `.Interrupted`?

❗ Ownership on error paths is underdefined.

### Fix

Add table:

| operation | result | ownership |
|----------|--------|----------|
| send     | Ok     | mailbox  |
| send     | error  | sender   |
| receive  | Ok     | receiver |
| receive  | no msg | unchanged |

---

## 3.2 Type safety is manual and dangerous

```

chunk := (^Chunk)(ptr)

```

No validation except `id`.

❗ This is a **footgun**.

### Fix

Require pattern:

```

switch ptr.id {
case ChunkId:
...
default:
panic
}

```

Make this mandatory in docs.

---

## 3.3 Lifetime of intrusive node is not stated

You rely on:

```

list.Node inside PolyNode

```

But never explicitly state:

❗ Node MUST NOT be in multiple lists simultaneously

### Fix

Add invariant:

- a PolyNode can be in at most one container at a time

---

## 3.4 Maybe semantics are underspecified

You rely on:

```

m^ = nil

```

But not define:

- is copying allowed?
- is aliasing allowed?
- can two `Maybe` point to same node?

### Fix

State clearly:

```

Maybe is a UNIQUE ownership handle
Copying is transfer, not duplication
Aliasing is forbidden

```

---

## 3.5 Threading guarantees are vague

Mailbox:

- blocking
- interruptible
- multi-producer?

Not clearly stated.

### Fix

Define explicitly:

- MPSC / SPSC / MPMC?
- fairness?
- ordering guarantees?

---

# 4. Human-Level Problems (Mid Programmer View)

## 4.1 Too much philosophy, not enough contracts

You say:

> One idea

User needs:

- exact rules
- exact failure modes
- exact lifecycle

### Fix

For each API:

- preconditions
- postconditions
- ownership transfer
- failure ownership

---

## 4.2 "Simple" but cognitively heavy

You hide complexity behind:

- Maybe
- intrusive layout
- manual casting
- hooks

For mid-level dev this is **NOT simple**.

### Fix

Admit:

> This is a low-level system.
> It trades simplicity for control.

---

## 4.3 Examples are too "happy path"

No examples of:

- failure
- shutdown
- pool pressure
- incorrect usage

### Fix

Add "bad examples" section.

---

## 4.4 Naming confusion

- Builder
- Master
- Recycler

These are **not intuitive names**.

### Fix suggestions:

| Current   | Better |
|----------|--------|
| Builder  | Factory |
| Master   | WorkerContext |
| Recycler | PoolPolicy |

---

# 5. What Should Be Removed

## Remove from README

- "No hidden system"
- "One rule"
- "nothing is shared"

These damage trust.

---

# 6. What Should Be Added (Minimal Set)

Add ONE section:

## "Non-obvious rules"

- intrusive node constraints
- Maybe uniqueness
- ownership on error
- id-based casting
- mailbox close semantics

---

# 7. Final Verdict

## What is excellent

- unified ownership model
- intrusive design
- no shared data paradigm
- layering concept

## What is risky

- implicit rules
- unsafe casting
- lifecycle gaps
- misleading simplicity claims

## What will break users

- undefined shutdown behavior
- unclear ownership on failure
- misuse of Maybe
- treating infrastructure as normal items

---

# 8. One-line summary

This is a **powerful low-level system pretending to be simple**.

Make it **honestly explicit**, and it becomes great.
