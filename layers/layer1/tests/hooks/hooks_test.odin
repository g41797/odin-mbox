//+test
package hooks_tests

import "core:testing"
import item "../../item"
import ex   "../../examples/hooks"

@(test)
test_factory_event :: proc(t: ^testing.T) {
	fp := ex.make_flow_policy()
	m := fp.factory(int(ex.ItemId.Event))
	testing.expect(t, m != nil, "factory(Event) must return non-nil")
	ptr, ok := m.?
	testing.expect(t, ok, "Maybe must unwrap")
	testing.expect(t, ptr.id == int(ex.ItemId.Event), "factory must stamp id == Event")
	// Clean up.
	fp.dispose(&m)
}

@(test)
test_factory_sensor :: proc(t: ^testing.T) {
	fp := ex.make_flow_policy()
	m := fp.factory(int(ex.ItemId.Sensor))
	testing.expect(t, m != nil, "factory(Sensor) must return non-nil")
	ptr, ok := m.?
	testing.expect(t, ok, "Maybe must unwrap")
	testing.expect(t, ptr.id == int(ex.ItemId.Sensor), "factory must stamp id == Sensor")
	fp.dispose(&m)
}

@(test)
test_factory_unknown :: proc(t: ^testing.T) {
	fp := ex.make_flow_policy()
	m := fp.factory(99)
	testing.expect(t, m == nil, "factory(unknown id) must return nil")
}

@(test)
test_dispose :: proc(t: ^testing.T) {
	fp := ex.make_flow_policy()
	m := fp.factory(int(ex.ItemId.Event))
	testing.expect(t, m != nil, "factory must succeed before dispose test")
	fp.dispose(&m)
	testing.expect(t, m == nil, "dispose must set handle to nil")
}

@(test)
test_roundtrip :: proc(t: ^testing.T) {
	fp := ex.make_flow_policy()

	// Event roundtrip
	m_ev := fp.factory(int(ex.ItemId.Event))
	testing.expect(t, m_ev != nil, "Event factory must succeed")
	fp.dispose(&m_ev)
	testing.expect(t, m_ev == nil, "Event dispose must nil the handle")

	// Sensor roundtrip
	m_s := fp.factory(int(ex.ItemId.Sensor))
	testing.expect(t, m_s != nil, "Sensor factory must succeed")
	fp.dispose(&m_s)
	testing.expect(t, m_s == nil, "Sensor dispose must nil the handle")
}

@(test)
test_on_get_on_put_nil :: proc(t: ^testing.T) {
	// At Layer 1, on_get and on_put are intentionally nil.
	fp := ex.make_flow_policy()
	testing.expect(t, fp.on_get == nil, "on_get must be nil at Layer 1")
	testing.expect(t, fp.on_put == nil, "on_put must be nil at Layer 1")
}

@(test)
test_dispose_nil_handle :: proc(t: ^testing.T) {
	// dispose must be safe when called with a nil Maybe value (m^ == nil).
	fp := ex.make_flow_policy()
	m: Maybe(^item.PolyNode) = nil
	fp.dispose(&m) // must not crash
	testing.expect(t, m == nil, "dispose on nil handle must leave it nil")
}
