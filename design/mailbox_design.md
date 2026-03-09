
# Mailbox Design Document

## 1. Overview
There are two specialized mailbox types. They solve different problems. One is for **blocking threads** (Workers/Clients). The other is for **high-performance loops** (nbio Engine).

## 2. Standard Mailbox (`mbox.odin`)
This mailbox is for regular worker threads.

### Roles
* **Sender:** Any thread.
* **Receiver:** A **Worker Thread** or **Client Thread**. It also may be the sender thread.

### Behavior
* **Producers:** Many threads can send.
* **Consumers:** One or many threads can receive (**Fan-In / Fan-Out**).
* **Blocking:** If empty, the receiver thread sleeps. The OS wakes it when a new message arrives.
* **CPU:** Uses **zero CPU** while blocking.

### API
* **`send(node)`**: Adds data. Signals a thread to wake up.
* **`try_receive()`**: Checks for data. Returns immediately. Never sleeps.
* **`wait_receive(timeout)`**: Sleeps until data arrives or time runs out.
* **`interrupt()`**: Forces all sleeping threads to wake up immediately (status: Interrupted).
* **`close()`**: Stops all new messages. Wakes all current sleepers (status: Closed).



## 3. Loop Mailbox (`loop_mbox.odin`)
This mailbox is for the **nbio thread** (The Engine).

### Roles
* **Sender:** **Client Threads** or **Workers**.
* **Receiver:** **ONLY the I/O Engine (nbio thread).**


### Behavior
* **Producers:** Many threads can send.
* **Consumer:** **Single Receiver only** (The nbio thread).
* **Waking:** When a sender adds data, it wakeups the nbio loop using `nbio.wake_up`.
* **No Blocking:** The nbio thread never sleeps inside the mailbox. It only sleeps inside the `nbio.tick()` kernel call.

### API
* **`send_to_loop(node)`**: Adds data. Triggers a Windows APC or Linux Event to wake the loop.
* **`try_receive()`**: The only way to get data. Used inside the loop "Drain" phase.
* **`close()`**: Stops new messages. The loop thread handles the final cleanup.



## 4. Key Differences

| Feature | `Mailbox` (Standard) | `Loop_Mailbox` (nbio) |
| :--- | :--- | :--- |
| **Thread Type** | Background Worker / Client | I/O Engine (Proactor) |
| **Wait Method** | `sync.cond_wait` | `nbio.tick` (Kernel) |
| **Signal Method** | `sync.cond_signal` | `nbio.wake_up` (Interrupt) |
| **CPU Usage** | Zero when idle | Zero when idle |



## 5. Why Two Types?
1. **Performance:** Standard mailboxes are too slow for I/O loops. They add extra overhead that `nbio` doesn't need.
2. **Safety:** If the I/O thread uses `wait_receive`, the network stops. We prevent this by only providing `try_receive`.
3. **Clean Code:** Each file has one specific job. 


## 6. Summary for Developers
* Use **`Mailbox`** for negotiation between regular threads.
* Use **`Loop_Mailbox`** to send _Commands_ to the main network engine.
