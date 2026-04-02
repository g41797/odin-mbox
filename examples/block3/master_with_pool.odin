package examples_block3

import matryoshka "../.."
import list "core:container/intrusive/list"
import "core:mem"
import "core:thread"
import "core:time"

// Master3 extends Layer 2 Master with a Pool.
Master3 :: struct {
	builder: Builder,
	inbox:   Mailbox,
	pool:    Pool,
	hooks:   PoolHooks,
	alloc:   mem.Allocator,
}

// newMaster3 creates a master with both mailbox and pool.
newMaster3 :: proc(alloc: mem.Allocator) -> ^Master3 {
	m, _ := new(Master3, alloc)
	m.alloc = alloc
	m.builder = make_builder(alloc)
	m.inbox = matryoshka.mbox_new(alloc)
	m.pool = matryoshka.pool_new(alloc)

	m.hooks = PoolHooks {
		ctx    = &m.builder,
		on_get = master_on_get,
		on_put = master_on_put,
	}
	append(&m.hooks.ids, int(ItemId.Event))

	matryoshka.pool_init(m.pool, &m.hooks)

	return m
}

// freeMaster3 performs clean teardown.
freeMaster3 :: proc(m: ^Master3) {
	if m == nil {return}

	// 1. Close pool and consume.
	nodes, _ := matryoshka.pool_close(m.pool)
	for {
		raw := list.pop_front(&nodes)
		if raw == nil {break}
		mi: MayItem = (^PolyNode)(raw)
		dtor(&m.builder, &mi)
	}
	mi_p: MayItem = (^PolyNode)(m.pool)
	matryoshka.matryoshka_dispose(&mi_p)

	// 2. Close mailbox and consume.
	remaining := matryoshka.mbox_close(m.inbox)
	for {
		raw := list.pop_front(&remaining)
		if raw == nil {break}
		mi: MayItem = (^PolyNode)(raw)
		dtor(&m.builder, &mi)
	}
	mi_mb: MayItem = (^PolyNode)(m.inbox)
	matryoshka.matryoshka_dispose(&mi_mb)

	delete(m.hooks.ids)
	alloc := m.alloc
	free(m, alloc)
}

// example_master_with_pool demonstrates a Master using a Pool for its items.
example_master_with_pool :: proc() -> bool {
	alloc := context.allocator
	m := newMaster3(alloc)
	defer freeMaster3(m)

	// Thread proc that receives items and returns them to master's pool.
	worker :: proc(t: ^thread.Thread) {
		m := (^Master3)(t.data)
		for {
			mi: MayItem
			if matryoshka.mbox_wait_receive(m.inbox, &mi) != .Ok {
				break
			}
			// Process...
			// Return to pool.
			matryoshka.pool_put(m.pool, &mi)
		}
	}

	th := thread.create(worker)
	th.data = m
	thread.start(th)
	defer thread.destroy(th)

	// Send 5 items from pool.
	for i in 0 ..< 5 {
		mi: MayItem
		if matryoshka.pool_get(m.pool, int(ItemId.Event), .Available_Or_New, &mi) == .Ok {
			ptr, _ := mi.?
			(^Event)(ptr).code = i
			matryoshka.mbox_send(m.inbox, &mi)
		}
	}

	// Close and join.
	// Since we returned items to the pool, they will be consumeed in freeMaster3.
	// We wait a bit to ensure worker processed them.
	time.sleep(10 * time.Millisecond)

	matryoshka.mbox_close(m.inbox)
	thread.join(th)

	return true
}
