# odin-itc Demo: Ownership-Driven Concurrency (No Locks Job System)

This document demonstrates how to build a simple multi-threaded process using `odin-itc`.

The goal is not to show all features, but to make one thing clear:

> You don’t need mutexes, shared state, or complex synchronization  
> if ownership is explicit and communication is message-based.

---

# 1. The Problem (A Simple Dialog)

```text
Main: I have jobs to process. I want to distribute them.

Worker: Send me a job.

Main: How do I track progress?

Worker: I’ll send progress updates.

Main: What about completion?

Worker: I’ll send a final result.

Main: What if I have many workers?

Worker: Just send jobs to all of us.

Main: Do I need locks?

Worker: No. Just send messages.
````

---

# 2. What We Actually Need

From the dialog, the system must support:

* Sending jobs to workers
* Workers reporting progress
* Workers returning results
* Multiple workers running in parallel
* No shared mutable state
* Clear ownership of data
* Efficient memory reuse

---

# 3. Mapping to `odin-itc`

| Problem Concept | odin-itc Concept |
| --------------- | ---------------- |
| Main            | Master           |
| Worker          | Master           |
| Job             | Item             |
| Progress        | Item             |
| Result          | Item             |
| Communication   | Mailbox          |
| Memory reuse    | Pool             |

---

# 4. Architecture

```text
        THREADS (Execution Containers)
                 │
     ┌───────────┴───────────┐
     ▼                       ▼

 MAIN MASTER         WORKER MASTER (N)

     │                       │
     │ send Job              │
     ├──────────────────────►│

     │                       │ process
     │                       │

     │ receive Progress      │
     ◄───────────────────────┤

     │ receive Result        │
     ◄───────────────────────┤

     │                       │ recycle
```

---

# 5. Core Data (Items)

Items are intrusive and move by pointer (zero-copy).

```odin
Job :: struct {
    next: ^Job,
    id:   int,
    payload: []u8,
}

Progress :: struct {
    next: ^Progress,
    job_id: int,
    current: int,
    total: int,
}

Result :: struct {
    next: ^Result,
    job_id: int,
    success: bool,
}
```

---

# 6. Mailboxes

```text
main_to_workers    (MPSC)
workers_to_main    (MPSC)
```

* Mailboxes **do not own items**
* They only transfer ownership

---

# 7. Pools

```text
job_pool
progress_pool
result_pool
```

Lifecycle:

```text
Create → Reset → Use → Recycle → Destroy
```

---

# 8. Main Master (Skeleton)

```odin
main_loop :: proc(m: ^MainMaster) {
    for {
        // 1. Create job
        job := pool.get(&m.job_pool)
        job.id = next_id()

        // 2. Send job
        send(&m.main_to_workers, &job) // ownership moves

        // 3. Receive messages
        for msg := recv(&m.workers_to_main) {
            switch msg.type {
            case Progress:
                handle_progress(msg)
                pool.put(&m.progress_pool, msg)

            case Result:
                handle_result(msg)
                pool.put(&m.result_pool, msg)
            }
        }
    }
}
```

---

# 9. Worker Master (Skeleton)

```odin
worker_loop :: proc(w: ^WorkerMaster) {
    for {
        job := recv(&w.main_to_workers)

        if job == nil {
            continue
        }

        // Process job
        for i in 0..<10 {
            progress := pool.get(&w.progress_pool)
            progress.job_id = job.id
            progress.current = i
            progress.total = 10

            send(&w.workers_to_main, &progress)
        }

        result := pool.get(&w.result_pool)
        result.job_id = job.id
        result.success = true

        send(&w.workers_to_main, &result)

        // Recycle job
        pool.put(&w.job_pool, job)
    }
}
```

---

# 10. Ownership Rule (Critical)

All sends use:

```odin
send(mailbox, &item)
```

Behavior:

* ✅ If send succeeds → `item = nil` (ownership transferred)
* ❌ If send fails → `item` is unchanged (you still own it)

This guarantees:

* No double free
* No lost messages
* No ambiguity

---

# 11. What We DID NOT Need

Traditional approach requires:

```text
- mutex
- shared queues
- condition variables
- atomic counters
- manual memory tracking
```

With `odin-itc`:

```text
- no shared state
- no locks
- no ownership confusion
- no allocations in hot path
```

---

# 12. Observability (Example Logs)

```text
Main → sent Job#1
Worker#2 → progress Job#1 [3/10]
Worker#2 → progress Job#1 [7/10]
Worker#2 → done Job#1
Main → received Result#1
```

---

# 13. Why This Works

The system is simple because:

* **Ownership moves** instead of being shared
* **Mailboxes isolate concurrency**
* **Pools control lifecycle**
* **Masters own all logic**

No component does more than one job.

---

# 14. Why This Scales

You can extend this without changing the model:

* Add more workers → no redesign
* Add priorities → just another mailbox
* Add routing → more Masters
* Add batching → different Items

---

# 15. The Core Insight

Without `odin-itc`:

```text
Shared memory → coordination problem
```

With `odin-itc`:

```text
Ownership transfer → no coordination needed
```

---

# 16. Takeaway

This is not a framework.

This is a **mental model**:

* Masters own logic
* Items carry data
* Mailboxes move ownership
* Pools control lifecycle

Everything else is composition.

```
```
