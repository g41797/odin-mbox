//+test
package tests_block3

import "core:testing"
import ex "../../examples/block3"

@test
test_example_recycler :: proc(t: ^testing.T) {
	testing.expect(t, ex.example_recycler(), "recycler example failed")
}

@test
test_example_seeding :: proc(t: ^testing.T) {
	testing.expect(t, ex.example_seeding(), "seeding example failed")
}

@test
test_example_backpressure :: proc(t: ^testing.T) {
	testing.expect(t, ex.example_backpressure(), "backpressure example failed")
}

@test
test_example_master_with_pool :: proc(t: ^testing.T) {
	testing.expect(t, ex.example_master_with_pool(), "master_with_pool example failed")
}
