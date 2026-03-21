package hooks

import item "../item"

// FlowPolicy is the struct-interface that every pool will call.
// At Layer 1 you define it and provide implementations.
// At Layer 2+ a pool holds a FlowPolicy and calls these procs.
//
// All four fields are optional (nil is valid — no-op for that hook).
// A minimal implementation sets factory and dispose; on_get and on_put
// are left nil when no sanitization or backpressure is needed.
FlowPolicy :: struct {
	// factory allocates and stamps the correct concrete type for id.
	// Returns nil on failure or unknown id.
	factory: proc(id: int) -> Maybe(^item.PolyNode),

	// on_get is called before a recycled item is returned to the caller.
	// Use it to zero or sanitize stale fields. Must NOT free resources.
	on_get:  proc(m: ^Maybe(^item.PolyNode)),

	// on_put is called during pool_put, outside the lock.
	// Set m^ = nil to consume the item (backpressure); otherwise the pool recycles it.
	on_put:  proc(m: ^Maybe(^item.PolyNode)),

	// dispose frees internal resources and the node itself, then sets m^ = nil.
	dispose: proc(m: ^Maybe(^item.PolyNode)),
}
