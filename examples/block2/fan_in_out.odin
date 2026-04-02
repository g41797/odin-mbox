package examples_block2

import "core:fmt"
import "core:thread"
import "core:sync"
import "core:time"
import list "core:container/intrusive/list"
import matryoshka "../.."

// Worker process for fan-in/fan-out.
worker_fan_proc :: proc(t: ^thread.Thread) {
	Context :: struct {
		id:      int,
		me:      ^Master,
		shared:  Mailbox,
		counter: ^int,
	}
	ctx := (^Context)(t.data)
	if ctx == nil {
		return
	}

	for {
		mi: MayItem
		res := matryoshka.mbox_wait_receive(ctx.shared, &mi)

		#partial switch res {
		case .Ok:
			_, ok := mi.?
			if ok {
				sync.atomic_add(ctx.counter, 1)
				// fmt.printfln("Worker %d: processed item %d", ctx.id, ptr.id)
			}
			dtor(&ctx.me.builder, &mi)
		case .Closed:
			return
		case:
			return
		}
	}
}

// example_fan_in_out demonstrates multiple producers and multiple consumers.
example_fan_in_out :: proc() -> bool {
	alloc := context.allocator
	
	// Single shared mailbox.
	shared_mb := matryoshka.mbox_new(alloc)
	
	counter: int
	NUM_WORKERS :: 3
	NUM_ITEMS :: 10

	masters: [NUM_WORKERS]^Master
	threads: [NUM_WORKERS]^thread.Thread
	
	Context :: struct {
		id:      int,
		me:      ^Master,
		shared:  Mailbox,
		counter: ^int,
	}
	contexts: [NUM_WORKERS]Context

	for i in 0 ..< NUM_WORKERS {
		masters[i] = newMaster(alloc)
		contexts[i] = Context{
			id      = i,
			me      = masters[i],
			shared  = shared_mb,
			counter = &counter,
		}
		threads[i] = thread.create(worker_fan_proc)
		if threads[i] != nil {
			threads[i].data = &contexts[i]
			thread.start(threads[i])
		}
	}

	// Wait a bit for threads to start and enter wait_receive.
	time.sleep(10 * time.Millisecond)

	// Producer side: Send items to shared mailbox.
	// We use the first master's builder to avoid leaks on unconsumed items.
	for _ in 0 ..< NUM_ITEMS {
		mi := ctor(&masters[0].builder, int(ItemId.Event))
		if mi != nil {
			if matryoshka.mbox_send(shared_mb, &mi) != .Ok {
				dtor(&masters[0].builder, &mi)
			}
		}
	}

	// Give items some time to be processed before closing.
	for i := 0; i < 100; i += 1 {
		if sync.atomic_load(&counter) == NUM_ITEMS {
			break
		}
		time.sleep(1 * time.Millisecond)
	}

	// Shutdown workers by closing shared mailbox.
	remaining := matryoshka.mbox_close(shared_mb)
	// Dispose any items that were never picked up by workers.
	for {
		raw := list.pop_front(&remaining)
		if raw == nil {
			break
		}
		poly := (^PolyNode)(raw)
		mi: MayItem = poly
		dtor(&masters[0].builder, &mi)
	}

	for i in 0 ..< NUM_WORKERS {
		if threads[i] != nil {
			thread.join(threads[i])
			thread.destroy(threads[i])
		}
		freeMaster(masters[i])
	}

	// Finally dispose the shared mailbox handle.
	mi_mb: MayItem = (^PolyNode)(shared_mb)
	matryoshka.matryoshka_dispose(&mi_mb)

	final_count := sync.atomic_load(&counter)
	fmt.printfln("Fan-in/out: processed %d items", final_count)
	return final_count == NUM_ITEMS
}
