# mbox - Intrusive Inter-Thread Communication for Odin

![Odin](https://img.shields.io/badge/Odin-v0.x-blue)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## A Bit of History, a Bit of Theory

Mailboxes are a fundamental part of the **Actor Model** (originated in 1973). Through the mailbox mechanism, actors can decouple the reception of a message from its elaboration. A mailbox is essentially a thread-safe FIFO data structure that holds messages.

This implementation is inspired by the **iRMX 86™ NUCLEUS** (Intel, 1980), where tasks communicated by visiting mailboxes and waiting for objects. Used this pattern in PL/M-86 and later implemented it in C, C++, C#, Go and Zig, this is the **Odin** version.

## Why?
If your threads run in "Fire and Forget" mode, you don't need a Mailbox. But in real multithreaded applications, threads communicate as a team. 

**mbox** provides:
- **Thread Safety**: Built on `core:sync` primitives.
- **Asynchronous/Unbounded**: Producers don't block; the list grows as needed.
- **Zero Allocations**: Intrusive nodes mean the data *is* the link. No extra heap allocations per message.
- **Contextless**: No dependency on the Odin `context` or a specific allocator.
- **Type Erasure**: Use one mailbox for miscellaneous data types safely.

---

## The "Odin Way": Intrusive Usage

In an intrusive mailbox, the user-defined struct embeds the link node. To work with miscellaneous data types in a single list, we use a **Tagged Header** and `mem.container_of`.



### 1. Define your Messages
```odin
import "mbox"
import "core:mem"

Msg_Kind :: enum {
    Join,
    Chat,
}

// The "Envelope" or "Header"
Envelope :: struct {
    kind: Msg_Kind,
    node: mbox.Node, // The intrusive link
}

Join_Msg :: struct {
    using base: Envelope, // Layout starts with Envelope
    username:   string,
}

```

### 2. Send and Receive

```odin
// Initialize
mb: mbox.Mailbox(mbox.Node)
mbox.mailbox_init(&mb)

// Producer
msg := new(Join_Msg)
msg.kind = .Join
msg.username = "Odin_User"
mbox.mailbox_send(&mb, &msg.node)

// Consumer
node, err := mbox.mailbox_receive(&mb, 100 * time.Millisecond)
if err == .None {
    // Re-hydrate the type from the node pointer
    env := mem.container_of(node, Envelope, "node")
    
    switch env.kind {
    case .Join:
        j := (^Join_Msg)(env)
        fmt.println(j.username)
    }
}

```

---

## API Reference

### Lifecycle

* `mailbox_init(mbox)`: Prepares the mutex and condition variables.
* `mailbox_close(mbox) -> ^T`: Closes the mailbox; returns the head of any remaining unprocessed nodes.
* `mailbox_destroy(mbox, callback)`: Closes the mailbox and executes a cleanup callback for every remaining node.

### Operations

* `mailbox_send(mbox, node)`: Enqueues a node and signals receivers.
* `mailbox_receive(mbox, timeout) -> (^T, Error)`: Dequeues a node. Blocks until data arrives or timeout expires.
* `mailbox_interrupt(mbox)`: Wakes up a waiting receiver thread immediately.
* `mailbox_letters(mbox) -> int`: Returns the current number of messages in the queue (thread-safe).

---
## Documentation
- [Architecture & History](README.md#a-bit-of-history-a-bit-of-theory)
- [Usage Examples](examples.md) — Includes Tagged Messages, Zero-Allocation signals, and Priority patterns.

## License

[MIT](https://www.google.com/search?q=LICENSE)

*First rule of multithreading: If you can do without multithreading - do without.*
