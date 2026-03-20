`# 🧠 The Current ITC Model (your design)

## 1. Core abstraction

Everything is built around:

```text
^Maybe(^PolyNode)
````

This is **not just a container** — it is:

> ✅ the **only ownership signal in the system**

---

## 2. System shape

```text
Thread → Master → Pool + Mailbox
                  ↓
              FlowPolicy
                  ↓
             PolyNode flow
```

### Roles

* **Pool**

  * intrusive storage (free list)
  * MPMC-safe
  * no business logic
  * validates IDs (strict)

* **Mailbox**

  * intrusive queue
  * transfers ownership

* **FlowPolicy (hooks)**

  * the **only place where decisions happen**

---

## 3. Ownership model (the heart)

At any moment:

```text
m^ != nil → you own the item
m^ == nil → you do NOT own it
```

That’s it.

No enums. No return codes. No flags.

---

## 4. Transfer model (uniform across APIs)

All APIs follow the same contract:

| API         | Meaning                         |
| ----------- | ------------------------------- |
| `pool.get`  | gives ownership                 |
| `mbox.send` | transfers ownership             |
| `pool.put`  | attempts to give ownership back |

> ❗ Destruction is **NOT an API**
> ❗ It is a **FlowPolicy decision inside hooks or caller**

---

## 5. `pool_put` — real behavior (final)

```odin
pool_put(p: ^Pool, m: ^Maybe(^PolyNode))
```

### What actually happens:

```text
caller owns m
    ↓
VALIDATE id ∈ pool.ids
    ↓
IF NOT:
    → PANIC (programming error)

ELSE:
    ↓
    pool calls on_put(ctx, ..., &m)
        ↓
    IF m == nil:
        → hook consumed (done)

    ELSE:
        → pool inserts into free list
        → m = nil
```

---

## 6. ID policy (NEW — strict)

Pool is initialized with explicit allowed IDs:

```odin
pool_init(&p, policy, ids = {...}, allocator)
```

### Rules:

```text
id MUST be > 0
id MUST belong to pool.ids
```

### Enforcement:

```text
IF id ∉ pool.ids:
    → PANIC
```

### Rationale:

* no foreign items
* no implicit disposal
* no ambiguity
* safe `defer pool_put`

---

## 7. The missing piece — destruction

Since `pool_dispose` does not exist:

> ❗ destruction MUST happen inside `on_put`:

```text
on_put:
    if limit exceeded:
        dispose(ctx, &m)   → sets m = nil
---

## 8. FlowPolicy (SSOT)

```odin
FlowPolicy :: struct {
    ctx: rawptr,

    factory,
    on_put,
    dispose,
}
```

### Responsibilities:

| Hook    | Responsibility                  |
| ------- | ------------------------------- |
| factory | create item                     |
| on_put  | decide fate (recycle / consume) |
| dispose | destroy item                    |

---

## 9. Final `on_put` contract (CRITICAL)

```text
on_put returns via m:

m == nil     → item consumed (destroyed or taken)
m != nil     → MUST be inserted into pool free list
```

---

## 10. What the Pool is NOT

Your current model explicitly rejects:

* ❌ pool-level decisions
* ❌ return-based signaling
* ❌ implicit disposal
* ❌ foreign item handling
* ❌ embedded wakeup logic

Pool is:

> ✅ mechanical executor of FlowPolicy

---

## 11. Intrusive + type-erased

Everything flows as:

```text
^PolyNode
```

User restores meaning via:

```odin
switch node.id
```

---

## 12. Lifecycle states (implicit)

An item is always in exactly one state:

```text
[ Owned by caller ]
[ In mailbox ]
[ In pool free list ]
[ Destroyed ]
```

Transitions are controlled by:

* Maybe (`m`)
* FlowPolicy hooks

---

## 13. Error prevention strategy

Your goal:

> “I care about less errors”

This model achieves that by:

### ✔ Single ownership channel

No duplication of state

### ✔ No return values

No branching on enums

### ✔ Hooks = single decision point

No split logic

### ✔ Intrusive nodes

No allocation mismatch bugs

### ✔ Fail-fast ID validation

No silent corruption or leaks

---

# 🔥 One-line definition

> ITC is a **type-erased, intrusive ownership pipeline** where
> **FlowPolicy decides fate**, and
> **Maybe encodes ownership**.

---

# ⚠️ Source of past confusion

You had **two models mixed**:

| Old mental model         | New (current) model |
| ------------------------ | ------------------- |
| pool returns result      | ownership in `m^`   |
| pool decides behavior    | hooks decide        |
| foreign pointer returned | ❌ panic             |
| pool.dispose exists      | ❌ removed           |

---

# ✅ Final invariant

```text
There is exactly ONE way to know ownership: m^
```

---

# 🛠 Global fix prompt (apply to ALL docs)

```text
Update all ITC design documents to enforce strict pool semantics and eliminate legacy behavior.

FILES:
- design/sync/new-pool-design-ga-v2.md
- design/sync/new-itc.md
- design/sync/new-idioms.md
- design/sync/poly_mailbox_proposal.md

GOALS:
1. Make pool_put semantics consistent everywhere
2. Remove foreign-item handling completely
3. Enforce strict ID validation
4. Ensure defer pool_put is always safe
5. Align all docs with FlowPolicy-driven destruction

CHANGES:

1. pool_put
- Signature MUST be:
  pool_put(p: ^Pool, m: ^Maybe(^PolyNode))
- NO return value anywhere
- Remove all Put_Result / status enums

2. Foreign items
- REMOVE all mentions of:
  - returning foreign pointer
  - handling foreign items
- REPLACE with:
  IF id ∉ pool.ids → PANIC

3. ID system
- Add to pool_init:
  ids: []int
- Document rules:
  - id > 0
  - id must belong to pool.ids
- Add explicit validation step in pool_put

4. on_put contract
- Standardize everywhere:

  m == nil     → consumed
  m != nil     → MUST be added to free list

- REMOVE any "reject" semantics

5. Disposal
- REMOVE pool_dispose API entirely
- Ensure all destruction is:
  - inside on_put, OR
  - caller-side via FlowPolicy.dispose

6. Idioms fix
- Replace ALL:
  defer pool_dispose(...)
  WITH:
  defer pool_put(...)


7. Safety guarantees
- Add explanation:
  - why defer pool_put is safe
  - why panic is preferred over silent handling

8. Self-containment
- Ensure FlowId (or equivalent) is defined in every doc where used

CONSTRAINTS:
- Do NOT introduce new APIs
- Do NOT reintroduce return values
- Do NOT add pool-level decisions
- Keep Pool fully mechanical

RESULT:
All documents describe ONE consistent model:
- Pool validates + stores
- Hooks decide
- Maybe encodes ownership
- Invalid usage crashes immediately
```

```
```
