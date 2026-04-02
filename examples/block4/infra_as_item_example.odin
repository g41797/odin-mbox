package examples_block4

import matryoshka "../.."
import list "core:container/intrusive/list"

// example_mailbox_as_item demonstrates passing a Mailbox as a payload item.
//
// A Mailbox (mb_payload) is wrapped as MayItem, enqueued into mb_channel,
// received, then closed and disposed — showing that infrastructure items
// follow the same ownership rules as data items.
//
// Flow:
//   sender: m = (^PolyNode)(mb_payload) → mbox_send(mb_channel, &m)
//   receiver: mbox_wait_receive(mb_channel, &mi) → Mailbox(ptr) → close → dispose
example_mailbox_as_item :: proc() -> bool {
	alloc := context.allocator

	// Transport mailbox.
	mb_channel := matryoshka.mbox_new(alloc)
	if mb_channel == nil {
		return false
	}

	// Payload mailbox to be sent as an item.
	mb_payload := matryoshka.mbox_new(alloc)
	if mb_payload == nil {
		matryoshka.mbox_close(mb_channel)
		mi_ch: MayItem = (^PolyNode)(mb_channel)
		matryoshka.matryoshka_dispose(&mi_ch)
		return false
	}

	// --- Send side ---
	// Wrap mb_payload as MayItem and enqueue it into mb_channel.
	m: MayItem = (^PolyNode)(mb_payload)
	matryoshka.mbox_send(mb_channel, &m)
	// m^ == nil — ownership of mb_payload transferred to the queue.

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
			if ptr_raw.id == matryoshka.MAILBOX_ID {
				matryoshka.mbox_close(Mailbox(ptr_raw))
				matryoshka.matryoshka_dispose(&mi_raw)
			}
		}
		mi_ch: MayItem = (^PolyNode)(mb_channel)
		matryoshka.matryoshka_dispose(&mi_ch)
		return false
	}

	ptr, valid := mi.?
	if !valid || ptr.id != matryoshka.MAILBOX_ID {
		matryoshka.matryoshka_dispose(&mi)
		matryoshka.mbox_close(mb_channel)
		mi_ch: MayItem = (^PolyNode)(mb_channel)
		matryoshka.matryoshka_dispose(&mi_ch)
		return false
	}

	// Cast back to Mailbox, close it (nothing was sent to it), and dispose.
	mb_recv := Mailbox(ptr)
	matryoshka.mbox_close(mb_recv)
	matryoshka.matryoshka_dispose(&mi)
	// mi^ == nil — mb_payload memory freed.

	// Tear down the channel (now empty after receive).
	matryoshka.mbox_close(mb_channel)
	mi_ch: MayItem = (^PolyNode)(mb_channel)
	matryoshka.matryoshka_dispose(&mi_ch)

	return true
}
