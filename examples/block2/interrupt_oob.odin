package examples_block2

import matryoshka "../.."
import list "core:container/intrusive/list"
import "core:fmt"
import "core:thread"

// Receiver waits on main_mb, and when interrupted, consumes oob_mb.
oob_receiver_proc :: proc(t: ^thread.Thread) {
	Context :: struct {
		m:       ^Master,
		main_mb: Mailbox,
		oob_mb:  Mailbox,
	}
	ctx := (^Context)(t.data)
	if ctx == nil {
		return
	}

	for {
		mi: MayItem
		res := matryoshka.mbox_wait_receive(ctx.main_mb, &mi)

		#partial switch res {
		case .Ok:
			// Process main message.
			dtor(&ctx.m.builder, &mi)

		case .Interrupted:
			fmt.println("Receiver: Interrupted, consuming OOB mailbox")
			// Consume OOB mailbox using try_receive_batch.
			batch, b_res := matryoshka.try_receive_batch(ctx.oob_mb)
			if b_res != .Ok {
				continue
			}

			for {
				raw := list.pop_front(&batch)
				if raw == nil {
					break
				}
				poly := (^PolyNode)(raw)
				mi_oob: MayItem = poly
				ptr, _ := mi_oob.?
				if ItemId(ptr.id) == .Event {
					ev := (^Event)(ptr)
					fmt.printfln("Receiver: OOB Event msg=%s", ev.message)
				}
				dtor(&ctx.m.builder, &mi_oob)
			}

		case .Closed:
			return
		}
	}
}

// example_interrupt_oob demonstrates Out-Of-Band signaling.
example_interrupt_oob :: proc() -> bool {
	alloc := context.allocator
	m := newMaster(alloc)
	if m == nil {
		return false
	}
	defer freeMaster(m)

	oob_mb := matryoshka.mbox_new(alloc)
	defer {
		mi_oob: MayItem = (^PolyNode)(oob_mb)
		matryoshka.matryoshka_dispose(&mi_oob)
	}

	Context :: struct {
		m:       ^Master,
		main_mb: Mailbox,
		oob_mb:  Mailbox,
	}
	ctx := Context {
		m       = m,
		main_mb = m.inbox,
		oob_mb  = oob_mb,
	}

	t := thread.create(oob_receiver_proc)
	if t == nil {
		return false
	}
	t.data = &ctx
	thread.start(t)
	defer thread.destroy(t)

	// Sender: Fill OOB mailbox first, then interrupt main mailbox.
	mi := ctor(&m.builder, int(ItemId.Event))
	if mi != nil {
		ptr, _ := mi.?
		ev := (^Event)(ptr)
		ev.message = "Critical update"
		if matryoshka.mbox_send(oob_mb, &mi) != .Ok {
			dtor(&m.builder, &mi)
		}
	}

	// Send the interrupt.
	matryoshka.mbox_interrupt(m.inbox)

	// Give it some time and shutdown.
	rem1 := matryoshka.mbox_close(m.inbox)
	for {
		raw := list.pop_front(&rem1)
		if raw == nil {break}
		item: MayItem = (^PolyNode)(raw)
		dtor(&m.builder, &item)
	}

	thread.join(t)

	// Clean up OOB.
	rem2 := matryoshka.mbox_close(oob_mb)
	for {
		raw := list.pop_front(&rem2)
		if raw == nil {break}
		item: MayItem = (^PolyNode)(raw)
		dtor(&m.builder, &item)
	}

	return true
}
