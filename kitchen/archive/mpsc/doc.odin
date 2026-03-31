/*
Package mpsc is a lock-free multi-producer, single-consumer queue.

It uses the [[Vyukov MPSC algorithm; https://int08h.com/post/ode-to-a-vyukov-queue/]].

No locks. No allocations.

Requirement:

Your message struct must have a field named "node" of type list.Node.

	import list "core:container/intrusive/list"

	My_Msg :: struct {
	    node: list.Node,
	    data: int,
	}

Stall state:

pop may return nil even when length > 0.
This happens when a producer has started push but not yet finished linking the node.
Treat nil from pop as "try again". The next call to pop will succeed.

Queue is NOT copyable after init.
The stub sentinel node holds its own address in head and tail.
Copying the struct after init invalidates those pointers.
*/
package mpsc

/*
Note: Some test procedures may appear in the generated documentation.
This is because they are part of the same package to allow for white-box testing.
*/
