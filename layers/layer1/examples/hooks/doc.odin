/*
Package examples_hooks — Layer 1 examples: FlowPolicy for Event + Sensor

Provides a concrete FlowPolicy implementation wired for two item types:

  - Event:  carries a numeric code and a human-readable message.
  - Sensor: carries a name and a floating-point measurement.

make_flow_policy() returns a ready-to-use FlowPolicy with factory and
dispose set; on_get and on_put are nil (no sanitization or backpressure
at Layer 1).

No pool, no invoker — just the hook vocabulary in action.
*/
package examples_hooks
