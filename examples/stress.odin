package examples

import mbox "../mbox"
import pool_pkg "../pool"
import list "core:container/intrusive/list"
import "core:sync"
import "core:thread"

// _Stress_Consumer owns all ITC participants for the stress test.
// Heap-allocated so producer and consumer threads can hold its address safely.
@(private)
_Stress_Consumer :: struct {
	pool:  pool_pkg.Pool(Msg),
	inbox: mbox.Mailbox(Msg),
	done:  sync.Sema,
}

@(private)
_stress_consumer_init :: proc(c: ^_Stress_Consumer, n: int) -> bool {
	ok, _ := pool_pkg.init(&c.pool, initial_msgs = n, max_msgs = n, reset = nil)
	return ok
}

@(private)
_stress_consumer_dispose :: proc(c: ^Maybe(^_Stress_Consumer)) { // [itc: dispose-contract]
	cp, ok := c.?
	if !ok || cp == nil {return}
	remaining, _ := mbox.close(&cp.inbox)
	for node := list.pop_front(&remaining); node != nil; node = list.pop_front(&remaining) {
		msg := container_of(node, Msg, "node")
		msg_opt: Maybe(^Msg) = msg
		ptr, accepted := pool_pkg.put(&cp.pool, &msg_opt)
		if !accepted && ptr != nil {
			p_opt: Maybe(^Msg) = ptr
			_msg_dispose(&p_opt) // [itc: foreign-dispose]
		}
	}
	pool_pkg.destroy(&cp.pool)
	free(cp)
	c^ = nil
}

// stress_example shows many producers, one consumer, with pool recycling.
stress_example :: proc() -> bool {
	N :: 10_000
	P :: 10

	sc := new(_Stress_Consumer) // [itc: heap-master]
	if !_stress_consumer_init(sc, N) {
		free(sc)
		return false
	}
	sc_opt: Maybe(^_Stress_Consumer) = sc
	defer _stress_consumer_dispose(&sc_opt) // [itc: defer-dispose]

	// Consumer: receives messages and returns them to the pool.
	consumer_thread := thread.create_and_start_with_data(
		sc,
		proc(data: rawptr) {
			c := (^_Stress_Consumer)(data) // [itc: thread-container]
			count := 0
			for count < N {
				msg, err := mbox.wait_receive(&c.inbox)
				if err == .Closed {
					break
				}
				if err == .None {
					msg_opt: Maybe(^Msg) = msg // [itc: maybe-container]
					// Corrected tag: defer-put only for actual defer calls. 
					// Here we just put back.
					ptr, accepted := pool_pkg.put(&c.pool, &msg_opt)
					if !accepted && ptr != nil {
						p_opt: Maybe(^Msg) = ptr
						_msg_dispose(&p_opt) // [itc: foreign-dispose]
					}
					count += 1
				}
			}
			sync.sema_post(&c.done)
		},
	)

	// P producers: each gets N/P messages from pool and sends them.
	producer_threads := make([]^thread.Thread, P)
	defer delete(producer_threads)
	for i in 0 ..< P {
		producer_threads[i] = thread.create_and_start_with_data(
			sc,
			proc(data: rawptr) {
				c := (^_Stress_Consumer)(data) // [itc: thread-container]
				for _ in 0 ..< N / P {
					msg, _ := pool_pkg.get(&c.pool)
					if msg != nil {
						msg_opt: Maybe(^Msg) = msg // [itc: maybe-container]
						if !mbox.send(&c.inbox, &msg_opt) {
							// msg_opt still non-nil on failure
							ptr, accepted := pool_pkg.put(&c.pool, &msg_opt)
							if !accepted && ptr != nil {
								p_opt: Maybe(^Msg) = ptr
								_msg_dispose(&p_opt) // [itc: foreign-dispose]
							}
						}
					}
				}
			},
		)
	}

	sync.sema_wait(&sc.done)

	// Join all threads before dispose.
	for i in 0 ..< P {
		thread.join(producer_threads[i])
		thread.destroy(producer_threads[i])
	}
	thread.join(consumer_thread)
	thread.destroy(consumer_thread)

	return true
}
