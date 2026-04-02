package examples_block4

import matryoshka "../.."
import list "core:container/intrusive/list"

// example_pool_as_item demonstrates passing a Pool as a payload item.
//
// A Pool (p_payload) is wrapped as MayItem, enqueued into mb_channel,
// received, then closed and disposed — showing that infrastructure items
// follow the same ownership rules as data items.
//
// Flow:
//   sender: m = (^PolyNode)(p_payload) → mbox_send(mb_channel, &m)
//   receiver: mbox_wait_receive(mb_channel, &mi) → Pool(ptr) → close → dispose
example_pool_as_item :: proc() -> bool {
	alloc := context.allocator

	// Transport mailbox.
	mb_channel := matryoshka.mbox_new(alloc)
	if mb_channel == nil {
		return false
	}

	// Payload pool to be sent as an item.
	p_payload := matryoshka.pool_new(alloc)
	if p_payload == nil {
		matryoshka.mbox_close(mb_channel)
		mi_ch: MayItem = (^PolyNode)(mb_channel)
		matryoshka.matryoshka_dispose(&mi_ch)
		return false
	}

	// --- Send side ---
	// Wrap p_payload as MayItem and enqueue it into mb_channel.
	m: MayItem = (^PolyNode)(p_payload)
	matryoshka.mbox_send(mb_channel, &m)
	// m^ == nil — ownership of p_payload transferred to the queue.

	// --- Receive side ---
	// Item is already in the queue; mbox_wait_receive returns immediately.
	mi: MayItem
	if matryoshka.mbox_wait_receive(mb_channel, &mi) != .Ok {
		// Defensive: consume any leftover items before disposing.
		ch_r := matryoshka.mbox_close(mb_channel)
		for {
			raw := list.pop_front(&ch_r)
			if raw == nil {break}
			mi_raw: MayItem = (^PolyNode)(raw)
			ptr_raw, _ := mi_raw.?
			if ptr_raw.id == matryoshka.POOL_ID {
				matryoshka.pool_close(Pool(ptr_raw))
				matryoshka.matryoshka_dispose(&mi_raw)
			}
		}
		mi_ch: MayItem = (^PolyNode)(mb_channel)
		matryoshka.matryoshka_dispose(&mi_ch)
		return false
	}

	ptr, valid := mi.?
	if !valid || ptr.id != matryoshka.POOL_ID {
		matryoshka.matryoshka_dispose(&mi)
		matryoshka.mbox_close(mb_channel)
		mi_ch: MayItem = (^PolyNode)(mb_channel)
		matryoshka.matryoshka_dispose(&mi_ch)
		return false
	}

	// Cast back to Pool, close it (nothing was stored in it), and dispose.
	p_recv := Pool(ptr)
	matryoshka.pool_close(p_recv)
	matryoshka.matryoshka_dispose(&mi)
	// mi^ == nil — p_payload memory freed.

	// Tear down the channel (now empty after receive).
	matryoshka.mbox_close(mb_channel)
	mi_ch: MayItem = (^PolyNode)(mb_channel)
	matryoshka.matryoshka_dispose(&mi_ch)

	return true
}
