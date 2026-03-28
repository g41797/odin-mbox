//+test
package tests_layer1

import matryoshka "../.."
import "core:testing"

@(test)
test_poly_node_zero_value :: proc(t: ^testing.T) {
	n: matryoshka.PolyNode
	testing.expect(t, n.id == 0, "zero-value PolyNode must have id == 0")
	testing.expect(t, n.node.prev == nil, "zero-value node.prev must be nil")
	testing.expect(t, n.node.next == nil, "zero-value node.next must be nil")
}

@(test)
test_maybe_nil_semantics :: proc(t: ^testing.T) {
	m: Maybe(^matryoshka.PolyNode)
	testing.expect(t, m == nil, "zero-value Maybe must be nil")
	n: matryoshka.PolyNode
	m = &n
	testing.expect(t, m != nil, "Maybe set to non-nil pointer must not be nil")
	testing.expect(t, m.? == &n, "Maybe.? must return the stored pointer")
}

@(test)
test_offset_zero_cast :: proc(t: ^testing.T) {
	// Verify that embedding PolyNode at offset 0 makes (^PolyNode)(item) safe.
	Item :: struct {
		using poly: matryoshka.PolyNode, // offset 0
		value:      int,
	}
	item: Item
	item.id = 1
	item.value = 42
	// Cast to ^PolyNode — safe because PolyNode is at offset 0
	poly := (^matryoshka.PolyNode)(&item)
	testing.expect(t, poly.id == 1, "cast to ^PolyNode must preserve id")
	// Cast back — safe because id is known
	back := (^Item)(poly)
	testing.expect(t, back.value == 42, "cast back to ^Item must preserve value")
}

@(test)
test_id_zero_is_uninitialized :: proc(t: ^testing.T) {
	// id == 0 means the node was never stamped.
	// Callers must check id != 0 before use.
	n: matryoshka.PolyNode
	testing.expect(t, n.id == 0, "uninitialized PolyNode has id == 0 (invalid)")
	n.id = 1
	testing.expect(t, n.id != 0, "after stamping, id must be != 0")
}
