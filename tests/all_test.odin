//+test
package tests

import examples "../examples"
import nbio_mbox "../nbio_mbox"
import "core:testing"

// --- example tests ---

@(test)
test_negotiation :: proc(t: ^testing.T) {
	testing.expect(
		t,
		examples.negotiation_example(.Timeout),
		"negotiation_example .Timeout failed",
	)
	testing.expect(t, examples.negotiation_example(), "negotiation_example failed")
	}

	@(test)
	test_foreign_dispose :: proc(t: ^testing.T) {
	testing.expect(t, examples.foreign_dispose_example(), "foreign_dispose_example failed")
	}


// -vet: keep nbio_mbox import used.
@(private)
_AN :: nbio_mbox.Nbio_Wakeuper_Kind

@(test)
test_stress :: proc(t: ^testing.T) {
	testing.expect(t, examples.stress_example(), "stress_example failed")
}

@(test)
test_endless_game :: proc(t: ^testing.T) {
	testing.expect(t, examples.endless_game_example(), "endless_game_example failed")
}

@(test)
test_example_interrupt :: proc(t: ^testing.T) {
	testing.expect(t, examples.interrupt_example(), "interrupt_example failed")
}

@(test)
test_example_close :: proc(t: ^testing.T) {
	testing.expect(t, examples.close_example(), "close_example failed")
}

@(test)
test_example_lifecycle :: proc(t: ^testing.T) {
	testing.expect(t, examples.lifecycle_example(), "lifecycle_example failed")
}

@(test)
test_master_example :: proc(t: ^testing.T) {
	testing.expect(t, examples.master_example(), "master_example failed")
}

@(test)
test_pool_wait :: proc(t: ^testing.T) {
	testing.expect(t, examples.pool_wait_example(), "pool_wait_example failed")
}

@(test)
test_echo_server :: proc(t: ^testing.T) {
	testing.expect(t, examples.echo_server_example(), "echo_server_example failed")
}
