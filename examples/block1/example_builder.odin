package examples_block1

import "core:mem"

// example_builder creates items via Builder, uses them, and destroys them.
// Returns true if roundtrip succeeds.
example_builder :: proc(alloc: mem.Allocator) -> bool {
	b := make_builder(alloc)

	// Create an Event via ctor.
	m := ctor(&b, int(ItemId.Event))
	ptr, ok := m.?
	if !ok {
		return false
	}

	// Use the item.
	ev := (^Event)(ptr)
	ev.code = 42
	ev.message = "hello"

	// Destroy via dtor — sets m to nil.
	dtor(&b, &m)

	return m == nil
}
