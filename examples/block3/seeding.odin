package examples_block3

import list "core:container/intrusive/list"
import matryoshka "../.."

// example_seeding demonstrates pre-allocating items in the pool.
example_seeding :: proc() -> bool {
	alloc := context.allocator
	b := make_builder(alloc)
	
	hooks := PoolHooks{
		ctx    = &b,
		on_get = master_on_get,
		on_put = master_on_put,
	}
	append(&hooks.ids, int(ItemId.Event))
	defer delete(hooks.ids)

	p := matryoshka.pool_new(alloc)
	matryoshka.pool_init(p, &hooks)

	// Seed the pool with 10 items.
	// We use .New_Only to force creation of new items even if some were already present.
	for _ in 0..<10 {
		mi: MayItem
		if matryoshka.pool_get(p, int(ItemId.Event), .New_Only, &mi) == .Ok {
			matryoshka.pool_put(p, &mi)
		}
	}

	// Verify that we can get 10 items without creating new ones.
	// (Though Available_Or_New would also call on_get for reinit, 
	// here we just want to see if the pool is full).
	
	items: [10]MayItem
	for i in 0..<10 {
		if matryoshka.pool_get(p, int(ItemId.Event), .Available_Only, &items[i]) != .Ok {
			// Cleanup what we got so far.
			for j in 0..=i { matryoshka.pool_put(p, &items[j]) }
			return false
		}
	}

	for i in 0..<10 {
		matryoshka.pool_put(p, &items[i])
	}

	// Teardown.
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

	return count == 10
}
