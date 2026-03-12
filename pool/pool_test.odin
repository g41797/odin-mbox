package pool

import list "core:container/intrusive/list"
import "core:mem"
import "core:testing"

// Test_Msg is the message type used in all pool tests.
// allocator field is required by the pool where clause.
@(private)
Test_Msg :: struct {
	node:      list.Node,
	allocator: mem.Allocator, // required by pool where clause
	data:      int,
}

// ----------------------------------------------------------------------------
// Helpers
// ----------------------------------------------------------------------------

// failing_allocator always returns Out_Of_Memory.
@(private)
_fail_alloc :: proc(
	allocator_data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (data: []byte, err: mem.Allocator_Error) {
	return nil, .Out_Of_Memory
}

@(private)
failing_allocator :: mem.Allocator{procedure = _fail_alloc, data = nil}

// Counting_Alloc_Data tracks allocations for the counting allocator.
@(private)
Counting_Alloc_Data :: struct {
	max:     int,
	count:   int,
	backing: mem.Allocator,
}

// _counting_alloc succeeds for the first max alloc calls, then returns OOM.
@(private)
_counting_alloc :: proc(
	allocator_data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (data: []byte, err: mem.Allocator_Error) {
	d := (^Counting_Alloc_Data)(allocator_data)
	if mode == .Alloc || mode == .Alloc_Non_Zeroed {
		if d.count >= d.max {
			return nil, .Out_Of_Memory
		}
		d.count += 1
	}
	return d.backing.procedure(d.backing.data, mode, size, alignment, old_memory, old_size, loc)
}

// _test_reset_bits records reset events in msg.data as bit flags:
//   bit 0 (1) = .Get was called
//   bit 1 (2) = .Put was called
// Concurrent-safe: each test uses its own message's data field.
@(private)
_test_reset_bits :: proc(msg: ^Test_Msg, e: Pool_Event) {
	switch e {
	case .Get:
		msg.data |= 1
	case .Put:
		msg.data |= 2
	}
}

// ----------------------------------------------------------------------------
// Existing tests (updated for new API)
// ----------------------------------------------------------------------------

@(test)
test_pool_get_always :: proc(t: ^testing.T) {
	p: Pool(Test_Msg)
	init(&p, reset = nil)
	defer destroy(&p)

	// Empty pool, .Always strategy — must allocate a new message.
	msg, _ := get(&p)
	testing.expect(t, msg != nil, "get(.Always) on empty pool should return non-nil")
	if msg != nil {
		free(msg, msg.allocator)
	}
}

@(test)
test_pool_get_pool_only :: proc(t: ^testing.T) {
	p: Pool(Test_Msg)
	init(&p, reset = nil)
	defer destroy(&p)

	// Empty pool, .Pool_Only — must return nil.
	msg, _ := get(&p, .Pool_Only)
	testing.expect(t, msg == nil, "get(.Pool_Only) on empty pool should return nil")
}

@(test)
test_pool_put_and_get :: proc(t: ^testing.T) {
	p: Pool(Test_Msg)
	init(&p, reset = nil)
	defer destroy(&p)

	// Get a fresh message (sets msg.allocator), put it back, get again.
	orig, _ := get(&p)
	testing.expect(t, orig != nil, "initial get should return non-nil")
	if orig == nil {
		return
	}
	orig.data = 42
	put(&p, orig)

	got, _ := get(&p)
	testing.expect(t, got != nil, "get after put should return non-nil")
	testing.expect(t, got == orig, "get should return the same pointer that was put")
	testing.expect(t, got.data == 42, "data should be preserved after put/get round-trip")
	if got != nil {
		free(got, got.allocator)
	}
}

@(test)
test_pool_respects_max :: proc(t: ^testing.T) {
	p: Pool(Test_Msg)
	init(&p, max_msgs = 2, reset = nil)
	defer destroy(&p)

	// Get 3 messages from pool (sets allocator on each).
	msg1, _ := get(&p)
	msg2, _ := get(&p)
	msg3, _ := get(&p)

	put(&p, msg1) // curr_msgs = 1
	put(&p, msg2) // curr_msgs = 2
	put(&p, msg3) // exceeds max — pool frees msg3

	testing.expect(t, p.curr_msgs == 2, "curr_msgs should stay at max after excess put")
}

@(test)
test_pool_preinit :: proc(t: ^testing.T) {
	p: Pool(Test_Msg)
	init(&p, initial_msgs = 4, reset = nil)
	defer destroy(&p)

	testing.expect(t, p.curr_msgs == 4, "curr_msgs should be 4 after init with initial_msgs=4")

	// All 4 gets should return pre-allocated messages.
	for _ in 0 ..< 4 {
		msg, _ := get(&p, .Pool_Only)
		testing.expect(t, msg != nil, "pre-allocated get should return non-nil")
		if msg != nil {
			free(msg, msg.allocator)
		}
	}

	// Pool is now empty.
	fifth, _ := get(&p, .Pool_Only)
	testing.expect(t, fifth == nil, "pool should be empty after 4 gets")
}

@(test)
test_pool_closed_get :: proc(t: ^testing.T) {
	p: Pool(Test_Msg)
	init(&p, reset = nil)

	// Get a fresh message (sets allocator), put it back into pool.
	msg, _ := get(&p)
	put(&p, msg)

	destroy(&p) // marks closed, frees pool messages

	got, _ := get(&p)
	testing.expect(t, got == nil, "get on closed pool should return nil")
}

@(test)
test_pool_closed_put :: proc(t: ^testing.T) {
	p: Pool(Test_Msg)
	init(&p, reset = nil)
	destroy(&p) // closed

	// Simulate a pool-owned message by setting allocator manually.
	msg := new(Test_Msg)
	msg.allocator = p.allocator // mark as pool-owned so put doesn't treat it as foreign
	put(&p, msg)                // pool is closed — frees msg, returns nil

	testing.expect(t, p.curr_msgs == 0, "curr_msgs should stay 0 after put on closed pool")
}

@(test)
test_pool_nil_put :: proc(t: ^testing.T) {
	p: Pool(Test_Msg)
	init(&p, reset = nil)
	defer destroy(&p)

	put(&p, nil) // no-op
	testing.expect(t, p.curr_msgs == 0, "curr_msgs should stay 0 after put(nil)")
}

@(test)
test_pool_destroy :: proc(t: ^testing.T) {
	p: Pool(Test_Msg)
	init(&p, initial_msgs = 2, reset = nil)

	destroy(&p)

	got, _ := get(&p)
	testing.expect(t, got == nil, "get after destroy should return nil")
	testing.expect(t, p.state == .Closed, "pool should be marked closed after destroy")
}

// ----------------------------------------------------------------------------
// New status tests
// ----------------------------------------------------------------------------

@(test)
test_pool_get_status_ok :: proc(t: ^testing.T) {
	p: Pool(Test_Msg)
	init(&p, initial_msgs = 1, reset = nil)
	defer destroy(&p)

	msg, status := get(&p)
	testing.expect(t, status == .Ok, "status should be .Ok")
	testing.expect(t, msg != nil, "msg should be non-nil")
	if msg != nil {
		free(msg, msg.allocator)
	}
}

@(test)
test_pool_get_status_pool_empty :: proc(t: ^testing.T) {
	p: Pool(Test_Msg)
	init(&p, reset = nil) // empty pool
	defer destroy(&p)

	msg, status := get(&p, .Pool_Only)
	testing.expect(t, status == .Pool_Empty, "status should be .Pool_Empty")
	testing.expect(t, msg == nil, "msg should be nil")
}

@(test)
test_pool_get_status_closed :: proc(t: ^testing.T) {
	p: Pool(Test_Msg)
	init(&p, reset = nil)
	destroy(&p)

	msg, status := get(&p)
	testing.expect(t, status == .Closed, "status should be .Closed")
	testing.expect(t, msg == nil, "msg should be nil")
}

@(test)
test_pool_get_status_uninit :: proc(t: ^testing.T) {
	p: Pool(Test_Msg) // zero value — state is .Uninit

	msg, status := get(&p)
	testing.expect(t, status == .Closed, "uninit pool status should be .Closed")
	testing.expect(t, msg == nil, "msg should be nil")
}

@(test)
test_pool_get_status_oom :: proc(t: ^testing.T) {
	p: Pool(Test_Msg)
	// init with 0 pre-allocs succeeds even with failing allocator
	init(&p, reset = nil, allocator = failing_allocator)
	defer destroy(&p)

	// .Always on empty pool tries to allocate — fails
	msg, status := get(&p)
	testing.expect(t, status == .Out_Of_Memory, "status should be .Out_Of_Memory")
	testing.expect(t, msg == nil, "msg should be nil")
}

// ----------------------------------------------------------------------------
// New init OOM tests
// ----------------------------------------------------------------------------

@(test)
test_pool_init_oom_immediate :: proc(t: ^testing.T) {
	p: Pool(Test_Msg)
	ok, status := init(&p, initial_msgs = 1, reset = nil, allocator = failing_allocator)
	testing.expect(t, !ok, "init should fail")
	testing.expect(t, status == .Out_Of_Memory, "status should be .Out_Of_Memory")
	testing.expect(t, p.state == .Closed, "pool should be .Closed after failed init")
}

@(test)
test_pool_init_oom_partial :: proc(t: ^testing.T) {
	data := Counting_Alloc_Data{max = 2, backing = context.allocator}
	counting := mem.Allocator{procedure = _counting_alloc, data = &data}

	p: Pool(Test_Msg)
	ok, status := init(&p, initial_msgs = 4, reset = nil, allocator = counting)
	testing.expect(t, !ok, "init should fail after 2 successes")
	testing.expect(t, status == .Out_Of_Memory, "status should be .Out_Of_Memory")
	testing.expect(t, p.state == .Closed, "pool should be .Closed after partial OOM")
}

// ----------------------------------------------------------------------------
// New put foreign/own tests
// ----------------------------------------------------------------------------

@(test)
test_pool_put_foreign_returned :: proc(t: ^testing.T) {
	p: Pool(Test_Msg)
	init(&p, reset = nil)
	defer destroy(&p)

	// A message whose allocator field is zero (not from this pool's get).
	foreign_msg := new(Test_Msg) // msg.allocator is zero-value, != p.allocator
	ret := put(&p, foreign_msg)
	testing.expect(t, ret == foreign_msg, "foreign message should be returned to caller")
	if ret != nil {
		free(ret) // caller must free it
	}
}

@(test)
test_pool_put_own_nil_return :: proc(t: ^testing.T) {
	p: Pool(Test_Msg)
	init(&p, reset = nil)
	defer destroy(&p)

	msg, _ := get(&p) // get sets msg.allocator = p.allocator
	testing.expect(t, msg != nil, "get should return non-nil")
	if msg == nil {
		return
	}
	ret := put(&p, msg)
	testing.expect(t, ret == nil, "put of own message should return nil")
}

// ----------------------------------------------------------------------------
// New reset proc tests
// ----------------------------------------------------------------------------

@(test)
test_pool_reset_on_get_recycled :: proc(t: ^testing.T) {
	p: Pool(Test_Msg)
	// Pre-allocate 1 message so first get is from free-list (recycled).
	init(&p, initial_msgs = 1, reset = _test_reset_bits)
	defer destroy(&p)

	msg, _ := get(&p) // recycled from free-list → reset(.Get) sets bit 0
	testing.expect(t, msg != nil, "get should return non-nil")
	if msg != nil {
		testing.expect(t, msg.data & 1 != 0, "get-reset bit should be set (bit 0)")
		testing.expect(t, msg.data & 2 == 0, "put-reset bit should NOT be set")
		free(msg, msg.allocator)
	}
}

@(test)
test_pool_reset_not_on_fresh :: proc(t: ^testing.T) {
	p: Pool(Test_Msg)
	init(&p, reset = _test_reset_bits) // empty pool
	defer destroy(&p)

	msg, _ := get(&p) // fresh allocation — reset must NOT be called
	testing.expect(t, msg != nil, "get should return non-nil")
	if msg != nil {
		testing.expect(t, msg.data == 0, "reset should NOT be called for fresh allocation (data must stay 0)")
		free(msg, msg.allocator)
	}
}

@(test)
test_pool_reset_on_put :: proc(t: ^testing.T) {
	p: Pool(Test_Msg)
	init(&p, reset = _test_reset_bits)
	defer destroy(&p)

	msg, _ := get(&p) // fresh alloc, no reset → data=0
	testing.expect(t, msg != nil, "get should return non-nil")
	if msg == nil {
		return
	}
	msg.data = 0 // ensure clean state

	ret := put(&p, msg) // reset(.Put) sets bit 1 → data=2, then recycled
	testing.expect(t, ret == nil, "put should return nil for own message")

	// Get the recycled message back to inspect data.
	recycled, _ := get(&p) // reset(.Get) sets bit 0 → data=3
	testing.expect(t, recycled != nil, "should get the recycled message back")
	if recycled != nil {
		testing.expect(t, recycled.data & 2 != 0, "put-reset bit should be set (bit 1)")
		free(recycled, recycled.allocator)
	}
}
