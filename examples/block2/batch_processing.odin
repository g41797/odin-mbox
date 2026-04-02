package examples_block2

import matryoshka "../.."
import list "core:container/intrusive/list"
import "core:thread"

// Receiver processes items in batches.
batch_receiver_proc :: proc(t: ^thread.Thread) {
	m := (^Master)(t.data)
	if m == nil {
		return
	}

	for {
		// Wait for signal (could be data or interrupt).
		mi: MayItem
		res := matryoshka.mbox_wait_receive(m.inbox, &mi)

		#partial switch res {
		case .Ok:
			// Process the single item received.
			dtor(&m.builder, &mi)

			// Then try to consume everything else currently in the mailbox.
			batch, b_res := matryoshka.try_receive_batch(m.inbox)
			if b_res == .Ok {
				for {
					raw := list.pop_front(&batch)
					if raw == nil {
						break
					}
					poly := (^PolyNode)(raw)
					mi_b: MayItem = poly
					dtor(&m.builder, &mi_b)
				}
			}

		case .Closed:
			return
		case:
			return
		}
	}
}

// example_batch_processing demonstrates batch retrieval using try_receive_batch.
example_batch_processing :: proc() -> bool {
	alloc := context.allocator
	m := newMaster(alloc)
	if m == nil {
		return false
	}
	defer freeMaster(m)

	t := thread.create(batch_receiver_proc)
	if t == nil {
		return false
	}
	t.data = m
	thread.start(t)
	defer thread.destroy(t)

	// Send several items rapidly.
	for _ in 0 ..< 10 {
		mi := ctor(&m.builder, int(ItemId.Event))
		if mi != nil {
			if matryoshka.mbox_send(m.inbox, &mi) != .Ok {
				dtor(&m.builder, &mi)
			}
		}
	}

	remaining := matryoshka.mbox_close(m.inbox)
	for {
		raw := list.pop_front(&remaining)
		if raw == nil {
			break
		}
		mi: MayItem = (^PolyNode)(raw)
		dtor(&m.builder, &mi)
	}

	thread.join(t)
	return true
}
