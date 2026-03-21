package examples_hooks

import item "../../item"
import h    "../../hooks"

// ItemId identifies the concrete type stored behind a PolyNode.
// Values must be > 0; 0 is always invalid (zero value of int).
ItemId :: enum int {
	Event  = 1,
	Sensor = 2,
}

// Event carries a numeric code and a human-readable message.
Event :: struct {
	using poly: item.PolyNode, // offset 0 — required for safe cast
	code:       int,
	message:    string,
}

// Sensor carries a name and a floating-point measurement.
Sensor :: struct {
	using poly: item.PolyNode, // offset 0 — required for safe cast
	name:       string,
	value:      f64,
}

// item_factory allocates and stamps the correct concrete type for id.
// Returns nil for unknown ids.
item_factory :: proc(id: int) -> Maybe(^item.PolyNode) {
	switch ItemId(id) {
	case .Event:
		ev := new(Event)
		ev.poly.id = id
		return Maybe(^item.PolyNode)(&ev.poly)
	case .Sensor:
		s := new(Sensor)
		s.poly.id = id
		return Maybe(^item.PolyNode)(&s.poly)
	case:
		return nil
	}
}

// item_dispose frees internal resources and the node, then sets m^ = nil.
// Safe to call with m == nil or m^ == nil (no-op).
item_dispose :: proc(m: ^Maybe(^item.PolyNode)) {
	if m == nil {
		return
	}
	ptr, ok := m.?
	if !ok {
		return
	}
	switch ItemId(ptr.id) {
	case .Event:
		free((^Event)(ptr))
	case .Sensor:
		free((^Sensor)(ptr))
	case:
		// Unknown id — still free the raw allocation to avoid leaks.
		free(ptr)
	}
	m^ = nil
}

// make_flow_policy returns a FlowPolicy wired for Event + Sensor.
// on_get and on_put are left nil — no backpressure or sanitization at Layer 1.
make_flow_policy :: proc() -> h.FlowPolicy {
	return h.FlowPolicy{
		factory = item_factory,
		dispose = item_dispose,
	}
}
