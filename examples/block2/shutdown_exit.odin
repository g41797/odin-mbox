package examples_block2

import "core:fmt"
import "core:thread"
import matryoshka "../.."

EXIT_ID :: 999

// Worker waits for items.
worker_exit_proc :: proc(t: ^thread.Thread) {
	m := (^Master)(t.data)
	if m == nil {
		return
	}

	for {
		mi: MayItem
		if matryoshka.mbox_wait_receive(m.inbox, &mi) != .Ok {
			return
		}

		ptr, _ := mi.?
		if ptr.id == EXIT_ID {
			fmt.println("Worker: received EXIT message, shutting down")
			dtor(&m.builder, &mi)
			return
		}

		fmt.printfln("Worker: processed data id %d", ptr.id)
		dtor(&m.builder, &mi)
	}
}

// example_shutdown_exit demonstrates shutdown via an exit message.
example_shutdown_exit :: proc() -> bool {
	alloc := context.allocator
	m := newMaster(alloc)
	if m == nil {
		return false
	}
	defer freeMaster(m)

	t := thread.create(worker_exit_proc)
	if t == nil {
		return false
	}
	t.data = m
	thread.start(t)
	defer thread.destroy(t)

	// Send normal data.
	mi_d := ctor(&m.builder, int(ItemId.Event))
	if mi_d != nil {
		if matryoshka.mbox_send(m.inbox, &mi_d) != .Ok {
			dtor(&m.builder, &mi_d)
		}
	}

	// Send exit message.
	// We need a special item for exit, or just any item with a special id.
	// Our builder doesn't know EXIT_ID, so we'll do it manually.
	
	exit_node := new(PolyNode, alloc)
	if exit_node != nil {
		exit_node.id = EXIT_ID
		mi_exit: MayItem = exit_node
		if matryoshka.mbox_send(m.inbox, &mi_exit) != .Ok {
			// Dispose if send failed.
			// matryoshka_dispose needs it to be "closed" if it's infrastructure,
			// but this is just a dummy PolyNode.
			// Actually, just free it.
			free(exit_node, alloc)
		}
	}

	thread.join(t)
	return true
}
