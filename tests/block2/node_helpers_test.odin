//+test
package tests_block2

import "core:testing"
import list "core:container/intrusive/list"
import matryoshka "../.."

@test
test_polynode_reset_nil :: proc(t: ^testing.T) {
	matryoshka.polynode_reset(nil) // must not crash
}

@test
test_polynode_is_linked_nil :: proc(t: ^testing.T) {
	testing.expect(t, !matryoshka.polynode_is_linked(nil), "nil must not be linked")
}

@test
test_polynode_is_linked_fresh :: proc(t: ^testing.T) {
	n: matryoshka.PolyNode
	testing.expect(t, !matryoshka.polynode_is_linked(&n), "fresh node must not be linked")
}

@test
test_polynode_reset_clears_stale :: proc(t: ^testing.T) {
	a: matryoshka.PolyNode
	b: matryoshka.PolyNode
	l: list.List
	list.push_back(&l, &a.node)
	list.push_back(&l, &b.node)
	// After push: a.next = &b.node (non-nil)
	list.pop_front(&l) // pops 'a'; Odin does NOT clear a.next — it stays as &b.node
	testing.expect(t, matryoshka.polynode_is_linked(&a), "node appears linked before reset")
	matryoshka.polynode_reset(&a)
	testing.expect(t, !matryoshka.polynode_is_linked(&a), "node clean after reset")
}
