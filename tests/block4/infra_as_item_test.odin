//+test
package tests_block4

import matryoshka "../.."
import "core:testing"
import ex "../../examples/block4"

// Aliases used across tests in this package.
PolyNode :: matryoshka.PolyNode
MayItem  :: matryoshka.MayItem

@test
test_matryoshka_dispose_mailbox :: proc(t: ^testing.T) {
	mb := matryoshka.mbox_new(context.allocator)
	testing.expect(t, mb != nil, "mbox_new should not return nil")
	matryoshka.mbox_close(mb)
	mi: MayItem = (^PolyNode)(mb)
	matryoshka.matryoshka_dispose(&mi)
	testing.expect(t, mi == nil, "mi should be nil after matryoshka_dispose")
}

@test
test_matryoshka_dispose_pool :: proc(t: ^testing.T) {
	p := matryoshka.pool_new(context.allocator)
	testing.expect(t, p != nil, "pool_new should not return nil")
	matryoshka.pool_close(p)
	mi: MayItem = (^PolyNode)(p)
	matryoshka.matryoshka_dispose(&mi)
	testing.expect(t, mi == nil, "mi should be nil after matryoshka_dispose")
}

@test
test_example_mailbox_as_item :: proc(t: ^testing.T) {
	testing.expect(t, ex.example_mailbox_as_item(), "mailbox_as_item example failed")
}

@test
test_example_pool_as_item :: proc(t: ^testing.T) {
	testing.expect(t, ex.example_pool_as_item(), "pool_as_item example failed")
}
