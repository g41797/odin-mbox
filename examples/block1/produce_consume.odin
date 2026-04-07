package examples_block1

import list "core:container/intrusive/list"
import "core:fmt"
import "core:mem"

// consume_list pops and frees all remaining items in the list.
consume_list :: proc(l: ^list.List, alloc: mem.Allocator) {
	for {
		raw := list.pop_front(l)
		if raw == nil {
			break
		}
		poly := (^PolyNode)(raw)
		if event_is_it_you(poly.tag) {
			free((^Event)(poly), alloc)
		} else if sensor_is_it_you(poly.tag) {
			free((^Sensor)(poly), alloc)
		} else {
			panic("unknown tag")
		}
	}
}

// example_produce_consume allocates a mix of Event and Sensor items,
// pushes them onto an intrusive list, then pops and dispatches on tag.
// Returns true if every item was processed and freed with no leaks.
example_produce_consume :: proc(alloc: mem.Allocator) -> bool {
	l: list.List

	// Consume on any exit path — no-op if list is already empty.
	defer consume_list(&l, alloc)

	// --- Produce: N pairs of (Event, Sensor) ---
	N :: 3
	for i in 0 ..< N {
		ev := new(Event, alloc)
		if ev == nil {
			return false
		}
		ev^.tag = EVENT_TAG
		ev.code = i
		ev.message = "event"
		list.push_back(&l, &ev.poly.node)

		s := new(Sensor, alloc)
		if s == nil {
			return false
		}
		s^.tag = SENSOR_TAG
		s.name = "sensor"
		s.value = f64(i) * 1.5
		list.push_back(&l, &s.poly.node)
	}

	// --- Consume: pop front, dispatch on tag, free ---
	processed := 0
	for {
		raw := list.pop_front(&l)
		if raw == nil {
			break
		}
		poly := (^PolyNode)(raw)

		if event_is_it_you(poly.tag) {
			ev := (^Event)(poly)
			fmt.printfln("Event:  code=%d  message=%s", ev.code, ev.message)
			free(ev, alloc)
		} else if sensor_is_it_you(poly.tag) {
			s := (^Sensor)(poly)
			fmt.printfln("Sensor: name=%s  value=%f", s.name, s.value)
			free(s, alloc)
		} else {
			panic("unknown tag")
		}
		processed += 1
	}

	return processed == N * 2
}
