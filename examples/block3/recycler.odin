package examples_block3

import matryoshka "../.."
import list "core:container/intrusive/list"

// master_on_get provides creation and reinitialization logic for the pool.
master_on_get :: proc(ctx: rawptr, id: int, in_pool_count: int, m: ^MayItem) {
	b := (^Builder)(ctx)
	if m^ == nil {
		// Create new item.
		m^ = ctor(b, id)
		// fmt.printfln("Recycler: created new item id=%d", id)
	} else {
		// Reinitialize recycled item.
		ptr, _ := m^.?
		#partial switch ItemId(ptr.id) {
		case .Event:
			ev := (^Event)(ptr)
			ev.code = 0
			ev.message = ""
		case .Sensor:
			s := (^Sensor)(ptr)
			s.name = ""
			s.value = 0.0
		}
		// fmt.printfln("Recycler: reinitialized item id=%d", id)
	}
}

// master_on_put provides policy-based reuse logic.
master_on_put :: proc(ctx: rawptr, in_pool_count: int, m: ^MayItem) {
	// Simple policy: keep everything.
	// fmt.printfln("Recycler: returning item to pool, idle count=%d", in_pool_count)
}

// example_recycler demonstrates basic pool usage with hooks.
example_recycler :: proc() -> bool {
	alloc := context.allocator
	b := make_builder(alloc)

	hooks := PoolHooks {
		ctx    = &b,
		on_get = master_on_get,
		on_put = master_on_put,
	}
	append(&hooks.ids, int(ItemId.Event))
	defer delete(hooks.ids)

	p := matryoshka.pool_new(alloc)
	matryoshka.pool_init(p, &hooks)

	// Round-trip 1: Create.
	mi: MayItem
	if matryoshka.pool_get(p, int(ItemId.Event), .Available_Or_New, &mi) != .Ok {
		return false
	}

	ptr1, _ := mi.?
	matryoshka.pool_put(p, &mi)

	// Round-trip 2: Reuse.
	if matryoshka.pool_get(p, int(ItemId.Event), .Available_Or_New, &mi) != .Ok {
		return false
	}

	ptr2, _ := mi.?
	if ptr1 != ptr2 {
		return false // Should have been reused.
	}

	matryoshka.pool_put(p, &mi)

	// Teardown.
	items, _ := matryoshka.pool_close(p)
	// Consume returned items.
	for {
		raw := list.pop_front(&items)
		if raw == nil {break}
		mi_consume: MayItem = (^PolyNode)(raw)
		dtor(&b, &mi_consume)
	}

	mi_p: MayItem = (^PolyNode)(p)
	matryoshka.matryoshka_dispose(&mi_p)

	return true
}
