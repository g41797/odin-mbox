package examples_block3

import list "core:container/intrusive/list"
import matryoshka "../.."

// limited_on_put implements a simple backpressure policy.
limited_on_put :: proc(ctx: rawptr, in_pool_count: int, m: ^MayItem) {
	b := (^Builder)(ctx)
	if in_pool_count >= 5 {
		// Drop the item if we have enough idle ones.
		// fmt.printfln("Backpressure: dropping item, pool already has %d", in_pool_count)
		dtor(b, m)
	}
}

// example_backpressure demonstrates pool limits via hooks.
example_backpressure :: proc() -> bool {
	alloc := context.allocator
	b := make_builder(alloc)
	
	hooks := PoolHooks{
		ctx    = &b,
		on_get = master_on_get,
		on_put = limited_on_put,
	}
	append(&hooks.ids, int(ItemId.Event))
	defer delete(hooks.ids)

	p := matryoshka.pool_new(alloc)
	matryoshka.pool_init(p, &hooks)

	// Create and return 10 fresh items.
	// .New_Only always creates a new item — pool accumulates until on_put starts dropping.
	for _ in 0..<10 {
		mi: MayItem
		if matryoshka.pool_get(p, int(ItemId.Event), .New_Only, &mi) == .Ok {
			matryoshka.pool_put(p, &mi)
		}
	}

	// Pool should only have 5 items now.
	nodes, _ := matryoshka.pool_close(p)
	count := 0
	for {
		raw := list.pop_front(&nodes)
		if raw == nil { break }
		mi: MayItem = (^PolyNode)(raw)
		dtor(&b, &mi)
		count += 1
	}

	mi_p: MayItem = (^PolyNode)(p)
	matryoshka.matryoshka_dispose(&mi_p)

	return count == 5
}
