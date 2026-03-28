# Concurrency Structure Idioms

These idioms relate to the high-level organization of concurrent programs, focusing on how threads and shared resources are structured for safety and clarity.

---

| Tag | Name | One line |
|-----|------|----------|
| `heap-master` | ITC participants in a heap-allocated struct | Heap-allocate the struct that owns ITC participants when its address is shared with spawned threads. |
| `thread-container` | thread is just a container for its master | A thread proc only casts rawptr to `^Owner`. No ITC participants declared as stack locals. |
| `defer-destroy` | destroy resources at scope exit | Register `defer destroy` for pools/mboxes/loops to guarantee shutdown in all paths. |

### `heap-master` — ITC participants in a heap-allocated struct
**Problem**: Threads must not reference the stack memory of a procedure that might exit before the threads complete.
**Fix**: `new(Master)` — heap-allocate the owner struct that contains the `Pool`, `Mbox`, and other shared resources. Pass a pointer to this struct to your threads. Call a `master_dispose` function after joining all threads to clean up.

### `thread-container` — thread is just a container for its master
**Problem**: Pointers to thread-local stack participants can accidentally escape the thread's frame, leading to use-after-free bugs.
**Fix**: Move all ITC participants (Pools, Mboxes, etc.) into the heap-allocated `Master` struct. The thread procedure should do nothing but cast its `rawptr` argument to a `^Master` and call a `master_run` function. This keeps all shared state centrally managed.
```odin
// The thread procedure is just a thin wrapper
proc(data: rawptr) {
    c := (^Master)(data) // [itc: thread-container]
    master_run(c)        // All logic is in the master
}
```

### `defer-destroy` — destroy resources at scope exit
**Problem**: Resources like pools and mailboxes must be shut down in all code paths to prevent leaks or deadlocks.
**Fix**: Register `destroy` with `defer` immediately after successful initialization. This guarantees the cleanup logic runs even if the function exits early.
```odin
mbox_init(&mb)
defer mbox_destroy(&mb) // [itc: defer-destroy]

pool_init(&p)
defer pool_destroy(&p)
```
