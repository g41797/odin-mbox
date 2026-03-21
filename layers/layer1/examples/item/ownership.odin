package examples

import list "core:container/intrusive/list"
import item "../../item"

// example_ownership demonstrates Maybe(^item.PolyNode) as an ownership handle.
//
// Push means "hand off" — after push you no longer own the item.
// Pop means "receive" — after pop you own it and must free or transfer it.
//
// These are the same ownership semantics that pool and mailbox use in later layers.
example_ownership :: proc() -> bool {
	l: list.List

	// 1. Allocate and stamp.
	ev := new(Event)
	ev.poly.id = int(ItemId.Event)
	ev.code = 99
	ev.message = "owned"

	// 2. Take ownership via Maybe.
	m: Maybe(^item.PolyNode) = &ev.poly

	// 3. Push to list — ownership transferred; set m to nil (you no longer own it).
	list.push_back(&l, &ev.poly.node)
	m = nil

	// 4. Pop — receive ownership.
	raw := list.pop_front(&l)
	if raw == nil {
		return false
	}
	out: Maybe(^item.PolyNode) = (^item.PolyNode)(raw)

	// 5. Verify, free, and clear the handle.
	ptr, ok := out.?
	if !ok {
		return false
	}
	owned_ev := (^Event)(ptr)
	if owned_ev.code != 99 {
		return false
	}
	free(owned_ev)
	out = nil

	return true
}
