package examples_block2

import "core:fmt"
import "core:thread"
import matryoshka "../.."

// request_response_example demonstrates two masters exchanging items.
example_request_response :: proc() -> bool {
	alloc := context.allocator
	m_a := newMaster(alloc)
	m_b := newMaster(alloc)
	if m_a == nil || m_b == nil {
		return false
	}
	defer freeMaster(m_a)
	defer freeMaster(m_b)

	// Thread B: receives request from A, sends response back to A.
	proc_b :: proc(t: ^thread.Thread) {
		// We need to know where to send response.
		// For this example, we'll pass a struct with both.
		Context :: struct {
			me:   ^Master,
			peer: Mailbox,
		}
		ctx := (^Context)(t.data)
		if ctx == nil {
			return
		}

		for {
			mi: MayItem
			if matryoshka.mbox_wait_receive(ctx.me.inbox, &mi) != .Ok {
				return
			}

			ptr, _ := mi.?
			if ItemId(ptr.id) == .Event {
				ev := (^Event)(ptr)
				fmt.printfln("Master B: received Request %d", ev.code)

				// Reuse item for response.
				ev.code += 1000
				ev.message = "Response"

				if matryoshka.mbox_send(ctx.peer, &mi) != .Ok {
					dtor(&ctx.me.builder, &mi)
				}
			} else {
				dtor(&ctx.me.builder, &mi)
			}
		}
	}

	Context :: struct {
		me:   ^Master,
		peer: Mailbox,
	}
	ctx_b := Context{me = m_b, peer = m_a.inbox}

	t_b := thread.create(proc_b)
	if t_b == nil {
		return false
	}
	t_b.data = &ctx_b
	thread.start(t_b)
	defer thread.destroy(t_b)

	// Master A: sends request to B, waits for response.
	mi := ctor(&m_a.builder, int(ItemId.Event))
	if mi != nil {
		ptr, _ := mi.?
		ev := (^Event)(ptr)
		ev.code = 42

		if matryoshka.mbox_send(m_b.inbox, &mi) != .Ok {
			dtor(&m_a.builder, &mi)
			return false
		}
	}

	// Wait for response.
	mi_resp: MayItem
	if matryoshka.mbox_wait_receive(m_a.inbox, &mi_resp) == .Ok {
		ptr, _ := mi_resp.?
		ev := (^Event)(ptr)
		fmt.printfln("Master A: received Response %d", ev.code)
		dtor(&m_a.builder, &mi_resp)
	}

	matryoshka.mbox_close(m_b.inbox)
	thread.join(t_b)

	return true
}
