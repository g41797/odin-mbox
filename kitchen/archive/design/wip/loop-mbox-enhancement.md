# Loop_Mailbox Enhancement — Design Notes

This file tracks per-stage design decisions and findings.
It is a working document, not a changelog.

---

## Stage 1 — init returns error

**Status**: Done (Session 74)

**Problem**: `init_loop_mailbox` returned nothing. Two failures were silent:
- `loop == nil` — caller passed a bad pointer.
- `nbio.timeout` returned nil — keepalive timer creation failed.

**Fix**: Added `Nbio_Mailbox_Error :: enum { None, Invalid_Loop, Keepalive_Failed }`.
`init_loop_mailbox` now checks both conditions and returns the error.

**Callers updated**: `tests/loop_test.odin` (4 tests), `examples/negotiation.odin`.

**Note**: This enum is interim. Stage 6 moves `Loop_Mailbox` to `loop_mbox/` package,
where the error enum will live permanently without the nbio dependency.

---

## Stage 2 — Verify close_loop keepalive handling

**Status**: Done (Session 74) — no code change.

**Claim**: `close_loop` must remove the keepalive timer outside the mutex,
to avoid calling `nbio.remove` while holding a lock.

**Finding**: Already correct. Current implementation:
1. Locks mutex.
2. Sets `closed = true`, moves list, saves `op := m.keepalive`, clears `m.keepalive`.
3. Unlocks mutex.
4. Calls `nbio.remove(op)` outside the mutex.
5. Calls `nbio.timeout(0, _noop, m.loop)` to wake the loop one last time.

No change needed. Documented and closed.

---

## Stage 3 — mpsc/ package (Vyukov queue)

**Status**: Done (Session 74)

**New files**: `mpsc/queue.odin`, `mpsc/doc.odin`, `mpsc/queue_test.odin`

**Algorithm**: Vyukov MPSC lock-free queue.
- `stub` is an embedded sentinel node. Its address is stored in `head` and `tail` on init.
- `push`: atomic exchange on `head`, then store `next`. The window between these two is the stall window.
- `pop`: consumer-only. Returns nil if empty or in stall state. Recycles stub when the last item is popped.
- `len`: atomic counter incremented by push, decremented by pop.

**Stall state**: pop may return nil while len > 0. A producer has called atomic_exchange but not yet written prev.next. Caller must treat nil as "try again". The next pop call will succeed. Documented in pop's comment.

**Key constraints**:
- Queue is NOT copyable after init (stub address stored in head/tail).
- pop must be called from a single consumer thread only.
- container_of is an Odin builtin — no import needed.

**Tests**: 6 unit tests in `mpsc/queue_test.odin` (same package). All pass.

---

## Stage 4 — wakeup/ package (WakeUper + sema impl)

**Status**: Done (Session 74)

**New files**: `wakeup/wakeup.odin`, `wakeup/doc.odin`, `wakeup/wakeup_test.odin`

**WakeUper**: Value type (copyable). Three fields: `ctx rawptr`, `wake proc(rawptr)`, `close proc(rawptr)`. Zero value is valid — callers must check `wake != nil` before calling. Procs are NOT `#contextless` — users may need `context.logger`.

**sema_wakeup**: Allocates `_Sema_State` (contains `sync.Sema` + stored allocator) on the heap. Returns a WakeUper whose `wake` calls `sema_post`, `close` calls `free`. No `sema_init`/`sema_destroy` needed — `sync.Sema` zero value is valid.

**Odin note**: Semaphore type is `sync.Sema` (not `sync.Semaphore`). Procs: `sema_post`, `sema_wait`, `sema_wait_with_timeout` — all `"contextless"`.

**Tests**: 5 unit tests (zero value, creates, wake signals, close frees, cross-thread example). All pass.

**Edge tests** (`wakeup/edge_test.odin`):
- `test_wake_with_nil_ctx` — nil guard verified (no crash)
- `test_concurrent_wake_signals` — 10 threads wake simultaneously; all signals received
- `test_custom_wakeup` — raw proc WakeUper; wake/close fire correctly
- `test_ctx_persistence` — ctx matches _Sema_State address; stored allocator valid

**Code change**: `_sema_wake` and `_sema_close` now guard `if ctx == nil { return }`.

**Edge tests** (`mpsc/edge_test.odin`):
- `test_stub_recycling_explicit` — 5 single-item push/pop cycles; recycling path exercised each time
- `test_pop_all_drains_to_zero` — push 50, pop all, length == 0
- `test_concurrent_push_stress` — 10 producers × 1000 items, 1 consumer; all 10,000 received
- `test_length_consistency` — push 200, verify length == 200, process remaining, verify length == 0

---

## Stage 5 — Pool WakeUper

**Status**: Done (Session 75)

**Purpose**: Allow event-loop callers to receive a wake-up signal when a message
returns to an empty pool, instead of blocking on `sync.Cond`.

**Reference**: Zig port at `tofu/src/ampe/Pool.zig`. Key decisions below diverge
from the original plan after reading the Zig implementation.

### New fields on Pool

```odin
waker:              wakeup.WakeUper  // optional — pass {} for none
empty_was_returned: bool             // set when get(.Pool_Only,0) found empty
```

### `init` change

Added `waker: wakeup.WakeUper = {}` parameter (after `reset`, before `allocator`).
Zero value is the default — existing callers do not need to change.

### `get` change

When strategy is `.Pool_Only` and `timeout == 0` and pool is empty:
sets `p.empty_was_returned = true` before unlocking, then returns `.Pool_Empty`.

### `put` logic (Zig-aligned, plan divergence)

Original plan: wake if `empty_was_returned && waker.wake != nil`.

Zig implementation: wake only when the pool **transitions from empty to non-empty**
(`pool.first == nil` before push) AND `emptyWasReturned`. This avoids spurious
wake calls when a message is put into a non-empty pool.

Odin implementation follows Zig:
```
pool_was_empty := p.list.head == nil   // capture before push
// ... push message, signal cond ...
was_flag := p.empty_was_returned
p.empty_was_returned = false           // always clear
waker := p.waker
// unlock
if pool_was_empty && was_flag && waker.wake != nil {
    waker.wake(waker.ctx)
}
```

Wake is called **outside the mutex** (plan decision, differs from Zig).
This avoids deadlock if `wake` acquires a lock internally.

### `destroy` logic (plan divergence)

Original plan: call `waker.wake` then `waker.close` on destroy.

Zig implementation: does NOT call alerter on `close`. Callers polling with
`get(.Pool_Only, 0)` will get `.Closed` on the next call — no wake needed.

Odin implementation: on destroy, calls only `waker.close(waker.ctx)` (if set),
to free heap resources allocated by `sema_wakeup`. Does NOT call `waker.wake`.

### `-vet` workaround

`wakeup.WakeUper` is used as a concrete struct field in the generic Pool struct.
`@(private) _PoolWaker :: wakeup.WakeUper` alias added to satisfy `-vet`.

### Tests added to `pool_tests/pool_test.odin`

- `test_pool_waker_wakes_on_put` — custom WakeUper with local sema;
  `get(.Pool_Only,0)` sets flag, `put` triggers wake, sema unblocks.
- `test_pool_waker_close_on_destroy` — custom WakeUper with bool flag;
  `destroy` calls `waker.close`, flag becomes true.

---

## Stage 6a — try_mbox Package

**Status**: Done (Session 77)

**What changed**: Renamed `poll_mbox/` → `try_mbox/`. Package rename + function rename. No logic changes.

- `package poll_mbox` → `package try_mbox`
- proc `receive` → `try_receive`
- test names updated: `test_send_receive_basic` → `test_send_try_receive_basic`, `test_receive_empty` → `test_try_receive_empty`
- doc.odin: updated description to reference `try_receive`
- `poll_mbox/` folder deleted

**Why the rename**: `poll` and `pool` differ by one letter. Easy to misread, easy to mistype.
`try_mbox` / `try_receive` — explicit non-blocking attempt.

**10 tests pass**: init_destroy, send_try_receive_basic, try_receive_empty, send_closed, close_returns_remaining, close_idempotent, length, waker_called_on_send, waker_close_on_close, no_waker.

---

## Stage 6b — nbio_mbox factory

**Status**: Done (Session 77)

**What changed**: Replaced `loop_mbox.odin` with `nbio_mbox.odin` (factory only). Migrated callers.

**loop_mbox.odin deleted**. All of `Loop_Mailbox`, `send_to_loop`, `try_receive_loop`, `close_loop`, `stats` are gone.

**nbio_mbox.odin** (package mbox, root):
- `Nbio_Mailbox_Error` enum kept (`None`, `Invalid_Loop`, `Keepalive_Failed`)
- `_NBio_State` holds `loop`, `keepalive`, `allocator` on heap
- `_nbio_wake`: fires `nbio.timeout(0, _noop, state.loop)` to wake the loop
- `_nbio_close`: removes keepalive, frees state
- `init_nbio_mbox($T, loop, allocator)` → creates WakeUper from `_NBio_State`, calls `try_mbox.init`

**Callers updated**:
- `tests/loop_test.odin`: all 4 tests use `mbox.init_nbio_mbox` + `try_mbox.*` ops
- `examples/negotiation.odin`: same pattern, `loop_mb` is now `^try_mbox.Mbox(Msg)`

**Full regression**: 10 try_mbox + 10 mpsc + 9 wakeup + 36 pool_tests + 31 tests, all green.

---

## Stage 7 — Strategic Analysis + Edge Cases

**Status**: Done (Session 78)

### §9 — Nbio Waker Throttling

**Problem**: Every `send` fired `nbio.timeout(0, _noop, state.loop)` to the cross-thread queue.
Under high-frequency sends the 128-slot queue fills; producers busy-wait.

**Fix**: Added `wake_pending: bool` (atomic) to `_NBio_State`.
`_nbio_wake` now does a CAS false→true. Only fires `nbio.timeout_poly(0, ...)` when CAS succeeds.
The callback `_noop_clear` resets the flag in the event-loop thread after the timeout fires.

This means at most one timeout is queued at a time regardless of how many sends arrive.

**New procs in `nbio_mbox.odin`**:
- `_noop_clear(^nbio.Operation, ^_NBio_State)` — clears `wake_pending`, used with `timeout_poly`

**Kept**: `_noop` used by the keepalive timer (unchanged).

### §10 — try_receive: no internal retry

`try_receive` calls `mpsc.pop` once and returns. No internal retry.

If pop returns nil while length > 0, that is the stall state — a producer finished the
atomic exchange but has not written the next pointer yet. The caller retries on the
next event loop tick. An internal retry would spin-wait, violating the non-blocking contract.

Updated comment in `try_mbox/mbox.odin`.

### §11 — close: no stall retry

`close` calls `mpsc.pop` in a process remaining loop until nil. No retry.

Precondition: all senders have stopped (threads joined). After a thread is joined,
its push is complete — both the atomic exchange and the next-pointer write are done.
No stall window can be open.

Updated comment in `try_mbox/mbox.odin`.

### try_receive_all — batch process remaining

New proc `try_receive_all` in `try_mbox/mbox.odin`. Drains all available messages
into a `list.List` in one call. Returns an empty list on stall or empty queue.
Does not replace `try_receive`.

Test `test_try_receive_all_basic` added to `try_mbox/mbox_test.odin`.

### Edge 4 — try_mbox edge tests

New file `try_mbox/edge_test.odin` (2 tests):
- `test_concurrent_producers` — 10 threads × 1,000 sends; single consumer drains all 10,000.
- `test_close_during_send_race` — 5 threads send while main calls close; no panic, correct counts.

### Edge 5 — nbio_mbox edge tests

`tests/loop_test.odin` (2 new tests):
- `test_loop_invalid_loop` — nil loop → `(nil, .Invalid_Loop)`
- `test_loop_high_freq_send` — 10,000 sends; all received via tick+try_receive.

New file `tests/nbio_mbox_edge_test.odin` (4 tests):
- `test_nbio_throttle_efficiency` — 1,000 sends; tick count < 50 proves wake_pending works.
- `test_nbio_burst_multiproducer` — 20 threads × 5,000 sends = 100,000 total; 100% delivery.
- `test_nbio_pool_constancy` — 10 rounds × 1,000 sends; no memory growth between rounds.
- `test_nbio_late_arrival` — send A, receive A, signal B, receive B; no message lost at flag-reset.

**Test totals after Stage 7**:
- try_mbox: 13 (10 unit + 1 try_receive_all + 2 edge)
- tests: 37 (31 → +2 loop + 4 nbio_edge)
- mpsc: 10 (unchanged)
- wakeup: 9 (unchanged)
- pool_tests: 36 (unchanged)

All 105 tests pass.

---

## Stage 5b — Pool Hardening

**Status**: Done (Session 76)

**Purpose**: Follow-up fixes and tests before repartitioning.

### Re-init guard

`init` now checks `p.state == .Active` before touching any field.
Returns `(false, .Closed)` immediately if pool is already live.
Prevents silent free-list leak when `init` is called on an active pool.

### `length` proc

New public proc. Returns `p.curr_msgs` under mutex.
Same `where` clause as all other pool procs.
Thread-safe read-only view of the free-list size.

### pool_tests/ restructure

5 heavy threaded tests moved from `pool_test.odin` to new `pool_tests/edge_test.odin`:
`test_pool_get_timeout_elapsed`, `test_pool_get_timeout_put_wakes`,
`test_pool_get_timeout_destroy_wakes`, `test_pool_many_waiters_partial_fill`,
`test_pool_destroy_wakes_all`.

Context types moved with them: `_Put_Wakes_Ctx`, `_Destroy_Wakes_Ctx`, `_N_Pool_Ctx`.

2 new tests added to `pool_test.odin`:
- `test_pool_reinit_active` — guards against double-init.
- `test_pool_length` — verifies length after init, get, put.

5 new stress/edge tests in `edge_test.odin`:
- `test_pool_stress_high_volume` — 10 threads × 1000 get+put cycles. No leaks.
- `test_pool_max_limit_racing` — concurrent puts at cap; curr_msgs stays ≤ max.
- `test_pool_shutdown_race` — 5 threads loop get+put while destroy races. No deadlock.
- `test_pool_idempotent_destroy` — 10 threads call destroy simultaneously. No crash.
- `test_pool_allocator_integrity` — custom counting allocator; all 5 allocs tracked.

**Total**: pool_test.odin 26 + edge_test.odin 10 = 36 tests. All pass.

---


## Stage 7 — Addendum: Use-After-Free Fix + Thread Model

**Status**: Done (Sessions 78–79)

### Problem

`wake_pending` + `timeout_poly` (Session 78) introduced a use-after-free:
`_noop_clear` can fire in the event-loop thread after `_nbio_close` already freed `_NBio_State`.

### Fix 1 — ref_count (Session 78, correct)

`_NBio_State` gets an atomic `ref_count`:
- `init`: `ref_count = 1`
- `_nbio_wake`: `atomic_add(+1)` before queuing timeout
- `_nbio_close`: `atomic_add(-1)`; free only if result == 1 (was last)
- `_noop_clear`: `atomic_add(-1)`; free only if result == 1

`atomic_add` returns the OLD value. `== 1` means "I held the last reference".

### Fix 2 — nbio.tick(0) belongs in _nbio_close (Session 79)

Gemini's patch put `nbio.tick(0)` in every caller's defer block after `close`.
This is wrong: callers should not know about internal callback state.

Correct location: `_nbio_close`, in the `else` branch:
- If `atomic_add(-1) == 1`: no pending callback → free immediately.
- Else: a `_noop_clear` is pending → call `nbio.tick(0)` to process remaining it → it frees state.

`_nbio_close` runs on the event-loop thread (guaranteed: `nbio.remove` panics cross-thread),
so `nbio.tick(0)` is always on the correct thread.

### Thread model

| Operation | Thread |
|-----------|--------|
| `init_nbio_mbox` | any |
| `send` | any — `timeout_poly` uses cross-thread queue |
| `try_receive` | event-loop thread only — MPSC single-consumer |
| `close` | event-loop thread only — `nbio.remove` panics cross-thread |
| `destroy` | event-loop thread (after close) |

`nbio.remove` is not thread-safe: writes to `_impl.flags`, `l.pending` (plain Small_Array),
and reads `l.now` — all without locks.

### Files changed

- `nbio_mbox.odin`: `_nbio_close` else branch + thread model doc comment on `init_nbio_mbox`.
- `try_mbox/doc.odin`: Thread model section added.
- `try_mbox/mbox.odin`: `close` comment — added "Must be called from the consumer thread".
- `tests/loop_test.odin`: Removed 5 `nbio.tick(0)` calls from defer blocks.
- `tests/nbio_mbox_edge_test.odin`: Removed 4 `nbio.tick(0)` calls from defer blocks.
- `examples/negotiation.odin`: Removed 1 `nbio.tick(0)` call from defer block.
