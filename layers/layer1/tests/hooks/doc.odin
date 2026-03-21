/*
Package hooks_tests — integration tests for Layer 1 hooks examples.

Calls make_flow_policy() and invokes factory and dispose directly,
without a pool.  Verifies that:

  - factory allocates the correct concrete type for known ids.
  - factory returns nil for unknown ids.
  - dispose frees the allocation and sets the handle to nil.
  - roundtrip (factory → dispose) leaves no handle.
*/
package hooks_tests
