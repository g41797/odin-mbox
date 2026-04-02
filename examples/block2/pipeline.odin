package examples_block2

import "core:fmt"
import "core:thread"
import list "core:container/intrusive/list"
import matryoshka "../.."

// Producer: Creates items and sends to next stage.
producer_proc :: proc(t: ^thread.Thread) {
	Context :: struct {
		me:   ^Master,
		next: Mailbox,
	}
	ctx := (^Context)(t.data)
	if ctx == nil {
		return
	}

	for i in 0 ..< 5 {
		mi := ctor(&ctx.me.builder, int(ItemId.Event))
		if mi != nil {
			ptr, _ := mi.?
			ev := (^Event)(ptr)
			ev.code = i
			// fmt.printfln("Producer: sent %d", i)
			if matryoshka.mbox_send(ctx.next, &mi) != .Ok {
				dtor(&ctx.me.builder, &mi)
			}
		}
	}
	// Signalling next stage to close.
	remaining := matryoshka.mbox_close(ctx.next)
	for {
		raw := list.pop_front(&remaining)
		if raw == nil {
			break
		}
		mi: MayItem = (^PolyNode)(raw)
		dtor(&ctx.me.builder, &mi)
	}
}

// Transformer: Receives from stage, transforms, sends to next.
transformer_proc :: proc(t: ^thread.Thread) {
	Context :: struct {
		me:   ^Master,
		next: Mailbox,
	}
	ctx := (^Context)(t.data)
	if ctx == nil {
		return
	}

	for {
		mi: MayItem
		if matryoshka.mbox_wait_receive(ctx.me.inbox, &mi) != .Ok {
			break
		}

		ptr, ok := mi.?
		if ok {
			ev := (^Event)(ptr)
			// fmt.printfln("Transformer: received %d, squaring", ev.code)
			ev.code = ev.code * ev.code
			if matryoshka.mbox_send(ctx.next, &mi) != .Ok {
				dtor(&ctx.me.builder, &mi)
			}
		}
	}
	remaining := matryoshka.mbox_close(ctx.next)
	for {
		raw := list.pop_front(&remaining)
		if raw == nil {
			break
		}
		mi: MayItem = (^PolyNode)(raw)
		dtor(&ctx.me.builder, &mi)
	}
}

// Consumer: Final stage.
consumer_proc :: proc(t: ^thread.Thread) {
	m := (^Master)(t.data)
	if m == nil {
		return
	}
	for {
		mi: MayItem
		if matryoshka.mbox_wait_receive(m.inbox, &mi) != .Ok {
			break
		}
		ptr, ok := mi.?
		if ok {
			ev := (^Event)(ptr)
			fmt.printfln("Consumer: final result %d", ev.code)
		}
		dtor(&m.builder, &mi)
	}
}

// example_pipeline demonstrates a chain of Masters.
example_pipeline :: proc() -> bool {
	alloc := context.allocator
	
	m_prod := newMaster(alloc)
	m_tran := newMaster(alloc)
	m_cons := newMaster(alloc)
	
	defer freeMaster(m_prod)
	defer freeMaster(m_tran)
	defer freeMaster(m_cons)

	Context :: struct {
		me:   ^Master,
		next: Mailbox,
	}
	
	ctx_prod := Context{me = m_prod, next = m_tran.inbox}
	ctx_tran := Context{me = m_tran, next = m_cons.inbox}

	t_cons := thread.create(consumer_proc)
	if t_cons == nil { return false }
	t_cons.data = m_cons
	
	t_tran := thread.create(transformer_proc)
	if t_tran == nil { 
		thread.destroy(t_cons)
		return false 
	}
	t_tran.data = &ctx_tran
	
	t_prod := thread.create(producer_proc)
	if t_prod == nil {
		thread.destroy(t_cons)
		thread.destroy(t_tran)
		return false
	}
	t_prod.data = &ctx_prod

	thread.start(t_cons)
	thread.start(t_tran)
	thread.start(t_prod)

	thread.join(t_prod)
	thread.join(t_tran)
	thread.join(t_cons)

	thread.destroy(t_prod)
	thread.destroy(t_tran)
	thread.destroy(t_cons)

	return true
}
