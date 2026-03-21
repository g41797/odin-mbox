/*
Package hooks — Layer 1: FlowPolicy struct-interface

FlowPolicy is the hook vocabulary every pool will call in later layers.
At Layer 1 you define it and provide one concrete implementation
(Event + Sensor, wired in examples/hooks).

No pool, no invoker — just the struct definition and proc-pointer types.

Move to Layer 2 when you need a pool that holds and calls a FlowPolicy.
*/
package hooks
