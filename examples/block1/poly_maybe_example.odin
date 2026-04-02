package examples_block1

import list "core:container/intrusive/list"

// run_poly_maybe_example demonstrates the core PolyNode + MayItem pattern.
//
// Creates an Event, wraps it in MayItem, transfers it through an intrusive list,
// pops it back, verifies, and frees.
// Returns true on success.
run_poly_maybe_example :: proc() -> bool {
	alloc := context.allocator

	// Allocate and stamp an Event.
	ev := new(Event, alloc)
	if ev == nil {
		return false
	}
	ev^.id = int(ItemId.Event)
	ev.code = 7
	ev.message = "poly-maybe"

	// Take ownership via MayItem.
	m: MayItem = &ev.poly

	// Transfer to intrusive list — ownership leaves m.
	l: list.List
	list.push_back(&l, &ev.poly.node)
	m = nil

	// Pop — regain ownership.
	raw := list.pop_front(&l)
	if raw == nil {
		return false
	}
	out: MayItem = (^PolyNode)(raw)

	// Unwrap and verify.
	ptr, ok := out.?
	if !ok {
		return false
	}
	if ptr.id != int(ItemId.Event) {
		free((^Event)(ptr), alloc)
		return false
	}

	// Free and clear handle.
	free((^Event)(ptr), alloc)
	out = nil

	return true
}
