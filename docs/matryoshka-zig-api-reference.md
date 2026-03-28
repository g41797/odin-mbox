# matryoshka — Unified API Reference (Zig 0.15.2)

> One ownership model for everything.  
> Data and infrastructure follow the same rules.

---

## Core Types

### PolyNode

The header at **offset 0** in every item.

```zig
pub const PolyNode = struct {
    node: list.Node,
    id: i32, // must be != 0
};
```

All items — user data and infrastructure — embed this first.

---

### Maybe

The ownership handle.

```zig
pub const Maybe = ?*PolyNode;
```

* `m.* == null` → not yours  
* `m.* != null` → yours

You must:

* transfer it
* or dispose it

---

## ID Rules

One field.  
Two ranges.

```zig
// Convention
id == 0   → invalid
id > 0    → user data
id < 0    → infrastructure
```

Example:

```zig
const SystemId = enum(i32) {
    Invalid = 0,
    Mailbox = -1,
    Pool    = -2,
};
```

User must not use negative ids.

---

## Lifecycle

No central factory.

Create directly.  
Dispose through one entry.

All infrastructure items store their allocator internally.

---

### Creation

```zig
pub fn mbox_new(alloc: std.mem.Allocator) Mailbox
pub fn pool_new(alloc: std.mem.Allocator) Pool
```

---

### Disposal

```zig
pub fn matryoshka_dispose(m: ?*Maybe) void
```

Entry:

| Condition       | Result |
| --------------- | ------ |
| `m == null`     | no-op  |
| `m.* == null`   | no-op  |

Algorithm:

* read `m.*.?.id` (if present)
* cast to internal type
* check state

| State  | Action      |
| ------ | ----------- |
| closed | free memory |
| open   | panic       |

Exit:

* `m.* = null` on success

---

## Mailbox API

Moves ownership between threads.

---

### Handle

```zig
pub const Mailbox = *PolyNode;
```

---

### Operations

```zig
pub const SendResult = enum {
    Ok,
    Closed,
    Invalid,
};

pub fn mbox_send(mb: Mailbox, m: *Maybe) SendResult

pub const RecvResult = enum {
    Ok,
    Closed,
    Interrupted,
    Already_In_Use,
    Invalid,
    Timeout,
};

pub fn mbox_wait_receive(
    mb: Mailbox,
    out: *Maybe,
    timeout: time.Duration = -1,
) RecvResult

pub const IntrResult = enum {
    Ok,
    Closed,
    Already_Interrupted,
};

pub fn mbox_interrupt(mb: Mailbox) IntrResult

// Marks mailbox closed.
// Wakes all waiters.
// Returns remaining items. Caller must drain.
pub fn mbox_close(mb: Mailbox) list.List

// Non-blocking drain. Returns (.Interrupted, empty) if flag set — clears flag.
pub fn try_receive_batch(mb: Mailbox) struct { list.List, RecvResult }
```

---

### Ownership rules

Send:

| Result | `m.*` after |
| ------ | ----------- |
| `.Ok`  | `null`      |
| other  | unchanged   |

Receive:

| Result | `out.*` after |
| ------ | ------------- |
| `.Ok`  | non-null      |
| other  | unchanged     |

---

### Notes

* Mailbox is an item
* Mailbox can be sent
* Mailbox must be closed before dispose

---

## Pool API

Provides reuse and policy.

---

### Handle

```zig
pub const Pool = *PolyNode;
```

---

### Initialization

```zig
pub fn pool_init(p: Pool, hooks: *PoolHooks) void
```

Hooks must outlive the pool.

---

### Operations

```zig
pub fn pool_close(p: Pool) struct { list: list.List, hooks: *PoolHooks }

pub const Pool_Get_Mode = enum {
    Available_Or_New,  // use stored item or create
    New_Only,          // always create
    Available_Only,    // stored only — no creation; on_get never called
};

pub const Pool_Get_Result = enum {
    Ok,             // item returned in m.*
    Not_Available,  // Available_Only: nothing stored
    Not_Created,    // on_get returned null
    Closed,         // pool is closed
    Already_In_Use, // m.* != null on entry
};

pub fn pool_get(
    p: Pool,
    id: i32,
    mode: Pool_Get_Mode,
    m: *Maybe,
) Pool_Get_Result

// Wait for stored item only.
// Does not call on_get.
pub fn pool_get_wait(
    p: Pool,
    id: i32,
    m: *Maybe,
    timeout: time.Duration,
) Pool_Get_Result

// Return item to pool.
// Calls on_put.
pub fn pool_put(p: Pool, m: *Maybe) void

// Return chain of items.
pub fn pool_put_all(p: Pool, m: *Maybe) void
```

---

### Ownership rules

Get:

| Result | `m.*` after |
| ------ | ----------- |
| `.Ok`  | non-null    |
| other  | unchanged   |

Put:

| State       | Result           |
| ----------- | ---------------- |
| open pool   | `m.* = null`     |
| closed pool | `m.*` unchanged  |

---

### PoolHooks

```zig
pub const PoolHooks = struct {
    ctx: ?*anyopaque,
    ids: std.ArrayList(i32),   // all > 0
    on_get: *const fn(ctx: ?*anyopaque, id: i32, in_pool_count: usize, m: *Maybe) void,
    on_put: *const fn(ctx: ?*anyopaque, in_pool_count: usize, m: *Maybe) void,
};
```

---

### Hook rules

on_get:

* `m.* == null` → create new item
* `m.* != null` → reinitialize

on_put:

* `m.* == null` → already disposed
* `m.* != null`:

  * keep → pool stores
  * dispose → set `m.* = null`

---

## Infrastructure rules

* Infrastructure uses negative ids
* Infrastructure is not pooled by default
* Infrastructure must be closed before dispose

---

## Summary

* One handle → `Maybe` (`?*PolyNode`)
* One movement → Mailbox
* One reuse → Pool
* One teardown → `matryoshka_dispose`

Everything follows the same rules.