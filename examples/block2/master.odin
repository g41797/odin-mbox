package examples_block2

import matryoshka "../.."
import "core:mem"
import list "core:container/intrusive/list"

// Master represents a worker context that runs on a thread.
// It owns its inbox (mailbox) and a builder for items.
Master :: struct {
	builder: Builder,
	inbox:   Mailbox,
	alloc:   mem.Allocator,
	// Add other state as needed.
}

// newMaster creates a new Master with a builder and an inbox.
newMaster :: proc(alloc: mem.Allocator) -> ^Master {
	m, err := new(Master, alloc)
	if err != .None {
		return nil
	}
	m.alloc = alloc
	m.builder = make_builder(alloc)
	m.inbox = matryoshka.mbox_new(alloc)
	return m
}

// freeMaster performs clean teardown of a Master.
// It closes the inbox, processes remaining items, and disposes the mailbox.
freeMaster :: proc(m: ^Master) {
	if m == nil {
		return
	}

	// 1. Close inbox and get remaining items.
	// This signals any waiting worker to exit.
	remaining := matryoshka.mbox_close(m.inbox)

	// 2. Process/dispose remaining items.
	for {
		raw := list.pop_front(&remaining)
		if raw == nil {
			break
		}
		poly := (^PolyNode)(raw)
		mi: MayItem = poly
		dtor(&m.builder, &mi)
	}

	// Note: The caller MUST join the worker thread before calling freeMaster.
	// If items were sent AFTER mbox_close was called, they might still be in the mailbox.
	// We call mbox_close again just in case (it is idempotent for the closed flag).
	
	remaining2 := matryoshka.mbox_close(m.inbox)
	for {
		raw := list.pop_front(&remaining2)
		if raw == nil {
			break
		}
		poly := (^PolyNode)(raw)
		mi: MayItem = poly
		dtor(&m.builder, &mi)
	}

	// 3. Dispose the mailbox handle.
	mb_item: MayItem = (^PolyNode)(m.inbox)
	matryoshka.matryoshka_dispose(&mb_item)

	// 4. Free Master memory.
	alloc := m.alloc
	free(m, alloc)
}
