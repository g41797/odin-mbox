# The Forgotten Doll

Someone found it in the back of a drawer.

It was clean. It worked. Someone had played with it — carefully, with thought.
Then it was set aside. Replaced by something simpler.
Not broken. Just not needed anymore.

This is that doll.

---

## What it was

Picture in README shows 5 dolls, but you did not ask — why are you talking about 4?

Doll 5 was implemented as part of an older version of this project.
Based on `^Maybe(^T)`, still not "famous" `^Maybe(^PolyNode)`.

During moving to `^Maybe(^PolyNode)` I added to Mailbox new API `try_receive_batch` and it solved the problem that mpsc should solve. Almost.
Also I don't like atomics. During stages of troubleshooting I'd like to immediately understand code, I cannot say that I fully understand atomics, so mpsc was thrown away...
but picture remains 😢

---

## The source

Two files. Kept as found.

### `doc.odin`

```odin
/*
Package mpsc is a lock-free multi-producer, single-consumer queue.

Port of [[Vyukov MPSC algorithm; https://int08h.com/post/ode-to-a-vyukov-queue/]].

No locks. No allocations.

Requirement:

Your message struct must have a field named "node" of type list.Node.

	import list "core:container/intrusive/list"

	My_Msg :: struct {
	    node: list.Node,
	    data: int,
	}

pop may return nil even when length > 0.
Treat nil from pop as "try again".
The next call to pop will succeed.

Queue is NOT copyable after init.
*/

package mpsc
```

---

### `queue.odin`

```odin
package mpsc

import "base:intrinsics"
import list "core:container/intrusive/list"

@(private)
_ListNode :: list.Node

// Queue is a lock-free multi-producer, single-consumer queue.
// T must have a field named "node" of type list.Node.
//
Queue :: struct($T: typeid) {
	head: ^list.Node, // producer end — updated atomically by multiple producers
	tail: ^list.Node, // consumer end — updated by single consumer only
	stub: list.Node,  // sentinel node; address used by head and tail
	len:  int,        // item count — updated atomically
}

// Call once before push or pop.
init :: proc(q: ^Queue($T)) where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") == list.Node {
	q.stub.next = nil
	q.head = &q.stub
	q.tail = &q.stub
	q.len = 0
}

// push adds msg to the queue. MT safe.
// nil inner (msg^ == nil) is a no-op and returns false.
// On success: msg^ = nil (ownership transferred to queue), returns true.
push :: proc(q: ^Queue($T), msg: ^Maybe(^T)) -> bool where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") == list.Node {
	if msg == nil {
		return false
	}
	if msg^ == nil {
		return false
	}
	ptr := (msg^).?
	node := &ptr.node
	intrinsics.atomic_store(&node.next, nil)
	prev := intrinsics.atomic_exchange(&q.head, node)
	intrinsics.atomic_store(&prev.next, node)
	intrinsics.atomic_add(&q.len, 1)
	msg^ = nil
	return true
}

// pop removes and returns one message. Call from a SINGLE consumer thread only.
//
// Returns nil in two cases:
//   - Queue is empty.
//   - Stall: a producer has started push but not yet finished linking the node.
//     In a stall, len may be != 0 while pop returns nil.
//     Treat nil as "try again". The next call to pop will return the message.
//
// Wrap the result in Maybe(^T) for lifecycle tracking: m = pop(q)
pop :: proc(q: ^Queue($T)) -> ^T where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") == list.Node {
	tail := q.tail
	next := intrinsics.atomic_load(&tail.next)
	if tail == &q.stub {
		if next == nil {
			return nil // empty
		}
		q.tail = next
		tail = next
		next = intrinsics.atomic_load(&tail.next)
	}
	if next != nil {
		q.tail = next
		intrinsics.atomic_sub(&q.len, 1)
		return container_of(tail, T, "node")
	}
 	head := intrinsics.atomic_load(&q.head)
	if tail != head {
		return nil
	}
	// Single item remaining. Recycle the stub sentinel.
	q.stub.next = nil
	prev := intrinsics.atomic_exchange(&q.head, &q.stub)
	intrinsics.atomic_store(&prev.next, &q.stub)
	next = intrinsics.atomic_load(&tail.next)
	if next != nil {
		q.tail = next
		intrinsics.atomic_sub(&q.len, 1)
		return container_of(tail, T, "node")
	}
	return nil // stall after recycling
}

// length returns the APPROXIMATE number of items in the queue.
// May be != 0 while pop returns nil (stall state — see pop comment).
length :: proc(q: ^Queue($T)) -> int where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") == list.Node {
	return intrinsics.atomic_load(&q.len)
}
```

---

Nobody needs it right now...
