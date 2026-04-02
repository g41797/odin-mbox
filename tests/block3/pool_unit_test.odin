//+test
package tests_block3

import matryoshka "../.."
import ex1 "../../examples/block1"
import list "core:container/intrusive/list"
import "core:testing"
import "core:thread"
import "core:time"

// Aliases for local usage.
PolyNode :: matryoshka.PolyNode
MayItem :: matryoshka.MayItem
Pool :: matryoshka.Pool
PoolHooks :: matryoshka.PoolHooks

@(test)
test_pool_new_dispose :: proc(t: ^testing.T) {
	p := matryoshka.pool_new(context.allocator)
	testing.expect(t, p != nil, "pool_new should not return nil")

	mi: MayItem = (^PolyNode)(p)

	// Must close before dispose.
	matryoshka.pool_close(p)
	matryoshka.matryoshka_dispose(&mi)

	testing.expect(t, mi == nil, "mi should be nil after matryoshka_dispose")
}

@(test)
test_pool_init :: proc(t: ^testing.T) {
	p := matryoshka.pool_new(context.allocator)
	defer {
		mi: MayItem = (^PolyNode)(p)
		matryoshka.pool_close(p)
		matryoshka.matryoshka_dispose(&mi)
	}

	hooks := PoolHooks {
		on_get = proc(ctx: rawptr, id: int, in_pool_count: int, m: ^MayItem) {},
		on_put = proc(ctx: rawptr, in_pool_count: int, m: ^MayItem) {},
	}
	append(&hooks.ids, int(ex1.ItemId.Event))
	defer delete(hooks.ids)

	matryoshka.pool_init(p, &hooks)
}

@(test)
test_pool_get_new :: proc(t: ^testing.T) {
	p := matryoshka.pool_new(context.allocator)
	defer {
		mi: MayItem = (^PolyNode)(p)
		matryoshka.pool_close(p)
		matryoshka.matryoshka_dispose(&mi)
	}

	b := ex1.make_builder(context.allocator)
	hooks := PoolHooks {
		ctx = &b,
		on_get = proc(ctx: rawptr, id: int, in_pool_count: int, m: ^MayItem) {
			b := (^ex1.Builder)(ctx)
			m^ = ex1.ctor(b, id)
		},
		on_put = proc(ctx: rawptr, in_pool_count: int, m: ^MayItem) {
			b := (^ex1.Builder)(ctx)
			ex1.dtor(b, m)
		},
	}
	append(&hooks.ids, int(ex1.ItemId.Event))
	defer delete(hooks.ids)

	matryoshka.pool_init(p, &hooks)

	mi: MayItem
	res := matryoshka.pool_get(p, int(ex1.ItemId.Event), .Available_Or_New, &mi)
	testing.expect(t, res == .Ok, "pool_get should return .Ok")
	testing.expect(t, mi != nil, "mi should not be nil")

	ptr, _ := mi.?
	testing.expect(t, ptr.id == int(ex1.ItemId.Event), "id should match")

	matryoshka.pool_put(p, &mi)
	testing.expect(t, mi == nil, "mi should be nil after pool_put")
}

@(test)
test_pool_put_get_reuse :: proc(t: ^testing.T) {
	p := matryoshka.pool_new(context.allocator)
	b := ex1.make_builder(context.allocator)
	defer {
		nodes, _ := matryoshka.pool_close(p)
		for {
			raw := list.pop_front(&nodes)
			if raw == nil {break}
			mi_consume: MayItem = (^PolyNode)(raw)
			ex1.dtor(&b, &mi_consume)
		}
		mi_p: MayItem = (^PolyNode)(p)
		matryoshka.matryoshka_dispose(&mi_p)
	}

	hooks := PoolHooks {
		ctx = &b,
		on_get = proc(ctx: rawptr, id: int, in_pool_count: int, m: ^MayItem) {
			if m^ != nil {
				// Reinit logic.
				ptr, _ := m^.?
				ev := (^ex1.Event)(ptr)
				ev.code = 999
				return
			}
			b := (^ex1.Builder)(ctx)
			m^ = ex1.ctor(b, id)
		},
		on_put = proc(ctx: rawptr, in_pool_count: int, m: ^MayItem) {
			// Keep everything.
		},
	}
	append(&hooks.ids, int(ex1.ItemId.Event))
	defer delete(hooks.ids)

	matryoshka.pool_init(p, &hooks)

	mi: MayItem
	matryoshka.pool_get(p, int(ex1.ItemId.Event), .Available_Or_New, &mi)

	ptr1, _ := mi.?
	matryoshka.pool_put(p, &mi)

	matryoshka.pool_get(p, int(ex1.ItemId.Event), .Available_Or_New, &mi)
	ptr2, _ := mi.?

	testing.expect(t, ptr1 == ptr2, "should reuse the same pointer")

	ev := (^ex1.Event)(ptr2)
	testing.expect(t, ev.code == 999, "should have been reinitialized by on_get")

	matryoshka.pool_put(p, &mi)
}

@(test)
test_pool_on_put_policy :: proc(t: ^testing.T) {
	p := matryoshka.pool_new(context.allocator)
	b := ex1.make_builder(context.allocator)
	defer {
		nodes, _ := matryoshka.pool_close(p)
		for {
			raw := list.pop_front(&nodes)
			if raw == nil {break}
			mi_consume: MayItem = (^PolyNode)(raw)
			ex1.dtor(&b, &mi_consume)
		}
		mi_p: MayItem = (^PolyNode)(p)
		matryoshka.matryoshka_dispose(&mi_p)
	}

	hooks := PoolHooks {
		ctx = &b,
		on_get = proc(ctx: rawptr, id: int, in_pool_count: int, m: ^MayItem) {
			b := (^ex1.Builder)(ctx)
			m^ = ex1.ctor(b, id)
		},
		on_put = proc(ctx: rawptr, in_pool_count: int, m: ^MayItem) {
			if in_pool_count >= 1 {
				// Dispose if we already have one.
				b := (^ex1.Builder)(ctx)
				ex1.dtor(b, m)
			}
		},
	}
	append(&hooks.ids, int(ex1.ItemId.Event))
	defer delete(hooks.ids)

	matryoshka.pool_init(p, &hooks)

	mi1, mi2: MayItem
	matryoshka.pool_get(p, int(ex1.ItemId.Event), .Available_Or_New, &mi1)
	matryoshka.pool_get(p, int(ex1.ItemId.Event), .Available_Or_New, &mi2)

	matryoshka.pool_put(p, &mi1) // Stored (count becomes 1).
	matryoshka.pool_put(p, &mi2) // Disposed by on_put (in_pool_count was 1).

	testing.expect(t, mi2 == nil, "mi2 should be nil because on_put disposed it")

	// Try to get again. Should only get one from pool.
	res := matryoshka.pool_get(p, int(ex1.ItemId.Event), .Available_Only, &mi1)
	testing.expect(t, res == .Ok, "should get the stored item")

	res = matryoshka.pool_get(p, int(ex1.ItemId.Event), .Available_Only, &mi2)
	testing.expect(t, res == .Not_Available, "pool should be empty now")

	matryoshka.pool_put(p, &mi1)
}

@(test)
test_pool_get_wait :: proc(t: ^testing.T) {
	p := matryoshka.pool_new(context.allocator)
	b := ex1.make_builder(context.allocator)
	defer {
		nodes, _ := matryoshka.pool_close(p)
		for {
			raw := list.pop_front(&nodes)
			if raw == nil {break}
			mi_consume: MayItem = (^PolyNode)(raw)
			ex1.dtor(&b, &mi_consume)
		}
		mi_p: MayItem = (^PolyNode)(p)
		matryoshka.matryoshka_dispose(&mi_p)
	}

	hooks := PoolHooks {
		ctx = &b,
		on_get = proc(ctx: rawptr, id: int, in_pool_count: int, m: ^MayItem) {
			b := (^ex1.Builder)(ctx)
			m^ = ex1.ctor(b, id)
		},
		on_put = proc(ctx: rawptr, in_pool_count: int, m: ^MayItem) {},
	}
	append(&hooks.ids, int(ex1.ItemId.Event))
	defer delete(hooks.ids)

	matryoshka.pool_init(p, &hooks)

	// In a separate thread, put an item into the pool after a delay.
	worker :: proc(t: ^thread.Thread) {
		args := (^struct {
				p: Pool,
				b: ^ex1.Builder,
			})(t.data)
		time.sleep(50 * time.Millisecond)
		mi := ex1.ctor(args.b, int(ex1.ItemId.Event))
		matryoshka.pool_put(args.p, &mi)
	}

	args := struct {
		p: Pool,
		b: ^ex1.Builder,
	}{p, &b}
	th := thread.create(worker)
	th.data = &args
	thread.start(th)
	defer thread.destroy(th)

	mi: MayItem
	res := matryoshka.pool_get_wait(p, int(ex1.ItemId.Event), &mi, 500 * time.Millisecond)
	testing.expect(t, res == .Ok, "pool_get_wait should eventually succeed")
	testing.expect(t, mi != nil, "should have acquired an item")

	thread.join(th)
	matryoshka.pool_put(p, &mi)
}

@(test)
test_pool_close_returns_all :: proc(t: ^testing.T) {
	p := matryoshka.pool_new(context.allocator)
	b := ex1.make_builder(context.allocator)
	hooks := PoolHooks {
		ctx = &b,
		on_get = proc(ctx: rawptr, id: int, in_pool_count: int, m: ^MayItem) {
			b := (^ex1.Builder)(ctx)
			m^ = ex1.ctor(b, id)
		},
		on_put = proc(ctx: rawptr, in_pool_count: int, m: ^MayItem) {},
	}
	append(&hooks.ids, int(ex1.ItemId.Event))
	defer delete(hooks.ids)

	matryoshka.pool_init(p, &hooks)

	// Put 3 items.
	for _ in 1 ..= 3 {
		mi := ex1.ctor(&b, int(ex1.ItemId.Event))
		matryoshka.pool_put(p, &mi)
	}

	items, h := matryoshka.pool_close(p)
	testing.expect(t, h == &hooks, "should return registered hooks")

	count := 0
	for {
		raw := list.pop_front(&items)
		if raw == nil {break}
		mi: MayItem = (^PolyNode)(raw)
		ex1.dtor(&b, &mi)
		count += 1
	}
	testing.expect(t, count == 3, "should return all 3 items")

	mi_p: MayItem = (^PolyNode)(p)
	matryoshka.matryoshka_dispose(&mi_p)
}
