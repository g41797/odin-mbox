//+test
package tests_block2

import "core:testing"
import ex "../../examples/block2"

@test
test_example_readme_worker :: proc(t: ^testing.T) {
	testing.expect(t, ex.example_readme_worker(), "readme_worker example failed")
}

@test
test_example_request_response :: proc(t: ^testing.T) {
	testing.expect(t, ex.example_request_response(), "request_response example failed")
}

@test
test_example_interrupt_oob :: proc(t: ^testing.T) {
	testing.expect(t, ex.example_interrupt_oob(), "interrupt_oob example failed")
}

@test
test_example_fan_in_out :: proc(t: ^testing.T) {
	testing.expect(t, ex.example_fan_in_out(), "fan_in_out example failed")
}

@test
test_example_pipeline :: proc(t: ^testing.T) {
	testing.expect(t, ex.example_pipeline(), "pipeline example failed")
}

@test
test_example_shutdown_exit :: proc(t: ^testing.T) {
	testing.expect(t, ex.example_shutdown_exit(), "shutdown_exit example failed")
}

@test
test_example_batch_processing :: proc(t: ^testing.T) {
	testing.expect(t, ex.example_batch_processing(), "batch_processing example failed")
}
