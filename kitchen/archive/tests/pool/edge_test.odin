//+test


package pool_tests

import "core:mem"
import "core:sync"
import "core:testing"
import "core:thread"
import "core:time"

import pool_pkg "../../pool"

// ----------------------------------------------------------------------------
// Context types for threaded tests
// ----------------------------------------------------------------------------

// _Put_Wakes_Ctx holds shared state for test_pool_get_timeout_put_wakes.
_Put_Wakes_Ctx :: struct {
	pool:  ^pool_pkg.Pool(Test_Itm),
	itm:   ^Test_Itm,
	ready: sync.Sema,
}

// _Destroy_Wakes_Ctx holds shared state for test_pool_get_timeout_destroy_wakes.
_Destroy_Wakes_Ctx :: struct {
	pool:  ^pool_pkg.Pool(Test_Itm),
	ready: sync.Sema,
}

// _N_Pool_Ctx holds state for one thread in multi-waiter pool tests.
_N_Pool_Ctx :: struct {
	pool:    ^pool_pkg.Pool(Test_Itm),
	idx:     int,
	started: ^sync.Sema,
	done:    ^sync.Sema,
	result:  pool_pkg.Pool_Status,
	got:     Maybe(^Test_Itm),
}

// _Stress_Ctx holds state for stress test threads.
_Stress_Ctx :: struct {
	pool:  ^pool_pkg.Pool(Test_Itm),
	start: ^sync.Sema,
	done:  ^sync.Sema,
}

// _Max_Race_Ctx holds state for max-limit racing test threads.
_Max_Race_Ctx :: struct {
	pool:  ^pool_pkg.Pool(Test_Itm),
	start: ^sync.Sema,
	done:  ^sync.Sema,
}

// _Shutdown_Ctx holds state for shutdown race test threads.
_Shutdown_Ctx :: struct {
	pool:  ^pool_pkg.Pool(Test_Itm),
	start: ^sync.Sema,
	done:  ^sync.Sema,
}

// _Idempotent_Ctx holds state for idempotent destroy test threads.
_Idempotent_Ctx :: struct {
	pool:  ^pool_pkg.Pool(Test_Itm),
	start: ^sync.Sema,
}

// ----------------------------------------------------------------------------
// Moved from pool_test.odin: timeout and multi-waiter tests
// ----------------------------------------------------------------------------

@(test)
test_pool_get_timeout_elapsed :: proc(t: ^testing.T) {
	p: pool_pkg.Pool(Test_Itm)
	pool_pkg.init(&p, hooks = pool_pkg.T_Hooks(Test_Itm){})
	defer pool_pkg.destroy(&p)

	// Empty pool, .Pool_Only, short timeout — nobody puts, should expire with .Pool_Empty.
	m: Maybe(^Test_Itm)
	status := pool_pkg.get(&p, &m, .Pool_Only, time.Millisecond)
	testing.expect(t, m == nil, "itm should be nil after timeout")
	testing.expect(t, status == .Pool_Empty, "status should be .Pool_Empty after timeout")
}

@(test)
test_pool_get_timeout_put_wakes :: proc(t: ^testing.T) {
	p: pool_pkg.Pool(Test_Itm)
	pool_pkg.init(&p, hooks = pool_pkg.T_Hooks(Test_Itm){})
	defer pool_pkg.destroy(&p)

	// Pre-allocate an item to put back from the second thread.
	m: Maybe(^Test_Itm)
	pool_pkg.get(&p, &m)
	testing.expect(t, m != nil, "initial get should return non-nil")
	if m == nil {
		return
	}

	ctx := _Put_Wakes_Ctx {
		pool = &p,
		itm  = m.?,
	}

	th := thread.create_and_start_with_data(
	&ctx,
	proc(data: rawptr) {
		c := (^_Put_Wakes_Ctx)(data)
		// Signal the waiter that we're ready, then put the item back.
		sync.sema_post(&c.ready)
		time.sleep(5 * time.Millisecond)
		c_itm_opt: Maybe(^Test_Itm) = c.itm
		pool_pkg.put(c.pool, &c_itm_opt)
	},
	)

	// Wait until the thread is running, then block on get with a long timeout.
	sync.sema_wait(&ctx.ready)
	got: Maybe(^Test_Itm)
	status := pool_pkg.get(&p, &got, .Pool_Only, time.Second)
	thread.join(th)
	thread.destroy(th)

	testing.expect(t, got != nil, "get should return non-nil after put wakes it")
	testing.expect(t, status == .Ok, "status should be .Ok")
	if got != nil {
		free(got.?, (got.?).allocator)
	}
}

@(test)
test_pool_get_timeout_destroy_wakes :: proc(t: ^testing.T) {
	p: pool_pkg.Pool(Test_Itm)
	pool_pkg.init(&p, hooks = pool_pkg.T_Hooks(Test_Itm){})

	ctx := _Destroy_Wakes_Ctx {
		pool = &p,
	}

	th := thread.create_and_start_with_data(
	&ctx,
	proc(data: rawptr) {
		c := (^_Destroy_Wakes_Ctx)(data)
		// Signal the waiter that we're running, then destroy the pool.
		sync.sema_post(&c.ready)
		time.sleep(5 * time.Millisecond)
		pool_pkg.destroy(c.pool)
	},
	)

	// Wait until the thread is running, then block on get with infinite timeout.
	sync.sema_wait(&ctx.ready)
	got: Maybe(^Test_Itm)
	status := pool_pkg.get(&p, &got, .Pool_Only, -1)
	thread.join(th)
	thread.destroy(th)

	testing.expect(t, got == nil, "get should return nil when pool is destroyed")
	testing.expect(t, status == .Closed, "status should be .Closed")
}

// test_pool_many_waiters_partial_fill: 10 threads wait with 2s timeout.
// Put 5 items back after all threads are waiting.
// 5 threads must get .Ok, 5 must get .Pool_Empty.
@(test)
test_pool_many_waiters_partial_fill :: proc(t: ^testing.T) {
	p: pool_pkg.Pool(Test_Itm)
	pool_pkg.init(&p, hooks = pool_pkg.T_Hooks(Test_Itm){})
	defer pool_pkg.destroy(&p)

	N :: 10
	started: sync.Sema
	done: sync.Sema
	ctxs: [N]_N_Pool_Ctx
	threads: [N]^thread.Thread

	for i in 0 ..< N {
		ctxs[i] = _N_Pool_Ctx {
			pool    = &p,
			idx     = i,
			started = &started,
			done    = &done,
		}
		threads[i] = thread.create_and_start_with_data(&ctxs[i], proc(data: rawptr) {
			c := (^_N_Pool_Ctx)(data)
			sync.sema_post(c.started)
			c.result = pool_pkg.get(c.pool, &c.got, .Pool_Only, 2 * time.Second)
			sync.sema_post(c.done)
		})
	}

	// Wait for all threads to be running and ready.
	for _ in 0 ..< N {
		sync.sema_wait(&started)
	}
	time.sleep(20 * time.Millisecond)

	// Allocate 5 fresh items and put them directly into the pool.
	// Using put (not get+put) avoids a race where the main thread's next get
	// would steal the just-signalled item before a waiting thread can take it.
	for _ in 0 ..< 5 {
		itm := new(Test_Itm)
		itm.allocator = context.allocator
		m: Maybe(^Test_Itm) = itm
		pool_pkg.put(&p, &m)
	}

	for _ in 0 ..< N {
		sync.sema_wait(&done)
	}
	for i in 0 ..< N {
		thread.join(threads[i])
		thread.destroy(threads[i])
	}

	ok_count := 0
	empty_count := 0
	for i in 0 ..< N {
		#partial switch ctxs[i].result {
		case .Ok:
			ok_count += 1
			if ctxs[i].got != nil {
				free(ctxs[i].got.?, (ctxs[i].got.?).allocator)
			}
		case .Pool_Empty:
			empty_count += 1
		}
	}
	testing.expect(t, ok_count == 5, "5 threads should get an item")
	testing.expect(t, empty_count == 5, "5 threads should time out with .Pool_Empty")
}

// test_pool_destroy_wakes_all: 10 threads wait with infinite timeout.
// destroy() must wake all 10 with .Closed.
@(test)
test_pool_destroy_wakes_all :: proc(t: ^testing.T) {
	p: pool_pkg.Pool(Test_Itm)
	pool_pkg.init(&p, hooks = pool_pkg.T_Hooks(Test_Itm){})

	N :: 10
	started: sync.Sema
	done: sync.Sema
	ctxs: [N]_N_Pool_Ctx
	threads: [N]^thread.Thread

	for i in 0 ..< N {
		ctxs[i] = _N_Pool_Ctx {
			pool    = &p,
			idx     = i,
			started = &started,
			done    = &done,
		}
		threads[i] = thread.create_and_start_with_data(&ctxs[i], proc(data: rawptr) {
			c := (^_N_Pool_Ctx)(data)
			sync.sema_post(c.started)
			c.result = pool_pkg.get(c.pool, &c.got, .Pool_Only, -1)
			sync.sema_post(c.done)
		})
	}

	// Wait for all threads to be running and ready.
	for _ in 0 ..< N {
		sync.sema_wait(&started)
	}
	time.sleep(20 * time.Millisecond)

	pool_pkg.destroy(&p)

	for _ in 0 ..< N {
		sync.sema_wait(&done)
	}
	for i in 0 ..< N {
		thread.join(threads[i])
		thread.destroy(threads[i])
	}

	closed_count := 0
	for i in 0 ..< N {
		if ctxs[i].result == .Closed {
			closed_count += 1
		}
	}
	testing.expect(t, closed_count == 10, "all 10 threads should get .Closed after destroy")
}

// ----------------------------------------------------------------------------
// New stress and edge tests
// ----------------------------------------------------------------------------

// test_pool_stress_high_volume: 10 threads each do 1000 get(.Always)+put cycles.
// After all threads complete, destroy and verify no items leaked.
@(test)
test_pool_stress_high_volume :: proc(t: ^testing.T) {
	p: pool_pkg.Pool(Test_Itm)
	pool_pkg.init(&p, hooks = pool_pkg.T_Hooks(Test_Itm){})

	N :: 10
	start: sync.Sema
	done: sync.Sema
	ctxs: [N]_Stress_Ctx
	threads: [N]^thread.Thread

	for i in 0 ..< N {
		ctxs[i] = _Stress_Ctx {
			pool  = &p,
			start = &start,
			done  = &done,
		}
		threads[i] = thread.create_and_start_with_data(&ctxs[i], proc(data: rawptr) {
			c := (^_Stress_Ctx)(data)
			sync.sema_wait(c.start)
			for _ in 0 ..< 1000 {
				m: Maybe(^Test_Itm)
				pool_pkg.get(c.pool, &m)
				pool_pkg.put(c.pool, &m)
			}
			sync.sema_post(c.done)
		})
	}

	// Release all threads simultaneously.
	for _ in 0 ..< N {
		sync.sema_post(&start)
	}
	for _ in 0 ..< N {
		sync.sema_wait(&done)
	}
	for i in 0 ..< N {
		thread.join(threads[i])
		thread.destroy(threads[i])
	}

	pool_pkg.destroy(&p)
	testing.expect(t, p.curr_msgs == 0, "curr_msgs should be 0 after destroy")
}

// test_pool_max_limit_racing: 10 threads concurrently get then put.
// Pool has max_msgs=3. curr_msgs must never exceed cap.
@(test)
test_pool_max_limit_racing :: proc(t: ^testing.T) {
	p: pool_pkg.Pool(Test_Itm)
	pool_pkg.init(&p, initial_msgs = 3, max_msgs = 3, hooks = pool_pkg.T_Hooks(Test_Itm){})

	N :: 10
	start: sync.Sema
	done: sync.Sema
	ctxs: [N]_Max_Race_Ctx
	threads: [N]^thread.Thread

	for i in 0 ..< N {
		ctxs[i] = _Max_Race_Ctx {
			pool  = &p,
			start = &start,
			done  = &done,
		}
		threads[i] = thread.create_and_start_with_data(&ctxs[i], proc(data: rawptr) {
			c := (^_Max_Race_Ctx)(data)
			sync.sema_wait(c.start)
			m: Maybe(^Test_Itm)
			pool_pkg.get(c.pool, &m)
			if m != nil {
				pool_pkg.put(c.pool, &m)
			}
			sync.sema_post(c.done)
		})
	}

	for _ in 0 ..< N {
		sync.sema_post(&start)
	}
	for _ in 0 ..< N {
		sync.sema_wait(&done)
	}
	for i in 0 ..< N {
		thread.join(threads[i])
		thread.destroy(threads[i])
	}

	testing.expect(
		t,
		p.curr_msgs <= 3,
		"curr_msgs should not exceed max_msgs after concurrent puts",
	)
	pool_pkg.destroy(&p)
}

// test_pool_shutdown_race: 5 threads loop get+put while main thread destroys.
// Verifies no panic, no deadlock, state == .Closed after join.
@(test)
test_pool_shutdown_race :: proc(t: ^testing.T) {
	p: pool_pkg.Pool(Test_Itm)
	pool_pkg.init(&p, hooks = pool_pkg.T_Hooks(Test_Itm){})

	N :: 5
	start: sync.Sema
	done: sync.Sema
	ctxs: [N]_Shutdown_Ctx
	threads: [N]^thread.Thread

	for i in 0 ..< N {
		ctxs[i] = _Shutdown_Ctx {
			pool  = &p,
			start = &start,
			done  = &done,
		}
		threads[i] = thread.create_and_start_with_data(&ctxs[i], proc(data: rawptr) {
			c := (^_Shutdown_Ctx)(data)
			sync.sema_wait(c.start)
			for {
				m: Maybe(^Test_Itm)
				status := pool_pkg.get(c.pool, &m)
				if status != .Ok {
					break
				}
				pool_pkg.put(c.pool, &m)
			}
			sync.sema_post(c.done)
		})
	}

	for _ in 0 ..< N {
		sync.sema_post(&start)
	}
	time.sleep(5 * time.Millisecond)
	pool_pkg.destroy(&p)

	for _ in 0 ..< N {
		sync.sema_wait(&done)
	}
	for i in 0 ..< N {
		thread.join(threads[i])
		thread.destroy(threads[i])
	}

	testing.expect(t, p.state == .Closed, "pool should be .Closed after destroy")
}

// test_pool_idempotent_destroy: 10 threads all call destroy simultaneously.
// Verifies no crash, state == .Closed, curr_msgs == 0.
@(test)
test_pool_idempotent_destroy :: proc(t: ^testing.T) {
	p: pool_pkg.Pool(Test_Itm)
	pool_pkg.init(&p, initial_msgs = 5, hooks = pool_pkg.T_Hooks(Test_Itm){})

	N :: 10
	start: sync.Sema
	ctxs: [N]_Idempotent_Ctx
	threads: [N]^thread.Thread

	for i in 0 ..< N {
		ctxs[i] = _Idempotent_Ctx {
			pool  = &p,
			start = &start,
		}
		threads[i] = thread.create_and_start_with_data(&ctxs[i], proc(data: rawptr) {
			c := (^_Idempotent_Ctx)(data)
			sync.sema_wait(c.start)
			pool_pkg.destroy(c.pool)
		})
	}

	for _ in 0 ..< N {
		sync.sema_post(&start)
	}
	for i in 0 ..< N {
		thread.join(threads[i])
		thread.destroy(threads[i])
	}

	testing.expect(t, p.state == .Closed, "pool should be .Closed after concurrent destroys")
	testing.expect(t, p.curr_msgs == 0, "curr_msgs should be 0 after destroy")
}

// test_pool_allocator_integrity: verifies the pool uses its stored allocator for all
// new/free calls, never falling back to context.allocator.
@(test)
test_pool_allocator_integrity :: proc(t: ^testing.T) {
	data := Counting_Alloc_Data {
		max     = 10,
		backing = context.allocator,
	}
	counting := mem.Allocator {
		procedure = _counting_alloc,
		data      = &data,
	}

	p: pool_pkg.Pool(Test_Itm)
	pool_pkg.init(&p, initial_msgs = 3, hooks = pool_pkg.T_Hooks(Test_Itm){}, allocator = counting)
	// init consumed 3 allocs.
	testing.expect(t, data.count == 3, "init with 3 pre-alloc should consume 3 allocs")

	// Drain pre-alloc items from pool — no new allocations.
	m1, m2, m3: Maybe(^Test_Itm)
	pool_pkg.get(&p, &m1, .Pool_Only)
	pool_pkg.get(&p, &m2, .Pool_Only)
	pool_pkg.get(&p, &m3, .Pool_Only)
	testing.expect(t, data.count == 3, "draining pre-alloc should not increase alloc count")

	// Pool is now empty. get(.Always) forces 2 new allocations.
	m4, m5: Maybe(^Test_Itm)
	pool_pkg.get(&p, &m4)
	pool_pkg.get(&p, &m5)
	testing.expect(t, data.count == 5, "2 fresh allocs should bring total to 5")
	testing.expect(t, m4 != nil, "m4 should be non-nil")
	testing.expect(t, m5 != nil, "m5 should be non-nil")

	// Put all 5 back.
	pool_pkg.put(&p, &m1)
	pool_pkg.put(&p, &m2)
	pool_pkg.put(&p, &m3)
	pool_pkg.put(&p, &m4)
	pool_pkg.put(&p, &m5)
	testing.expect(t, p.curr_msgs == 5, "all 5 items should be in pool")

	// destroy frees all 5 via the counting allocator.
	pool_pkg.destroy(&p)
	testing.expect(t, data.count == 5, "alloc count should still be 5 after destroy")
	testing.expect(t, p.curr_msgs == 0, "curr_msgs should be 0 after destroy")
}
