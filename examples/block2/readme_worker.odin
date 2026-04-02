package examples_block2

import "core:fmt"
import "core:thread"
import list "core:container/intrusive/list"
import matryoshka "../.."

// worker_proc is the thread procedure for the worker doll.
worker_proc :: proc(t: ^thread.Thread) {
	m := (^Master)(t.data)
	if m == nil {
		return
	}

	for {
		mi: MayItem
		// mbox_wait_receive blocks until an item is available or closed.
		res := matryoshka.mbox_wait_receive(m.inbox, &mi)

		#partial switch res {
		case .Ok:
			ptr, ok := mi.?
			if !ok {
				continue
			}

			// Process based on id.
			#partial switch ItemId(ptr.id) {
			case .Event:
				ev := (^Event)(ptr)
				fmt.printfln("Worker: received Event code=%d, msg=%s", ev.code, ev.message)
			case .Sensor:
				s := (^Sensor)(ptr)
				fmt.printfln("Worker: received Sensor name=%s, val=%f", s.name, s.value)
			}
			// Dispose item after processing.
			dtor(&m.builder, &mi)

		case .Closed:
			fmt.println("Worker: inbox closed, exiting")
			return

		case:
			fmt.printfln("Worker: unexpected receive result: %v", res)
			return
		}
	}
}

// example_readme_worker demonstrates the simple worker example from README.md.
example_readme_worker :: proc() -> bool {
	alloc := context.allocator
	m := newMaster(alloc)
	if m == nil {
		return false
	}
	defer freeMaster(m)

	// Start worker thread.
	t := thread.create(worker_proc)
	if t == nil {
		return false
	}
	t.data = m
	thread.start(t)
	defer thread.destroy(t)

	// Send an Event.
	mi_e := ctor(&m.builder, int(ItemId.Event))
	if mi_e != nil {
		ptr, _ := mi_e.?
		ev := (^Event)(ptr)
		ev.code = 101
		ev.message = "Hello from main"

		if matryoshka.mbox_send(m.inbox, &mi_e) != .Ok {
			dtor(&m.builder, &mi_e)
		}
	}

	// Send a Sensor.
	mi_s := ctor(&m.builder, int(ItemId.Sensor))
	if mi_s != nil {
		ptr, _ := mi_s.?
		s := (^Sensor)(ptr)
		s.name = "Thermal"
		s.value = 36.6

		if matryoshka.mbox_send(m.inbox, &mi_s) != .Ok {
			dtor(&m.builder, &mi_s)
		}
	}

	// Close inbox to signal worker to exit.
	remaining := matryoshka.mbox_close(m.inbox)
	for {
		raw := list.pop_front(&remaining)
		if raw == nil {
			break
		}
		mi: MayItem = (^PolyNode)(raw)
		dtor(&m.builder, &mi)
	}

	thread.join(t)
	return true
}
