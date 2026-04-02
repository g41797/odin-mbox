//+test
package tests_block2

import matryoshka "../.."
import ex1 "../../examples/block1"
import list "core:container/intrusive/list"
import "core:testing"
import "core:time"

// Aliases for local usage.
PolyNode :: matryoshka.PolyNode
MayItem   :: matryoshka.MayItem
Mailbox   :: matryoshka.Mailbox

@test
test_mbox_new_dispose :: proc(t: ^testing.T) {
	mb := matryoshka.mbox_new(context.allocator)
	testing.expect(t, mb != nil, "mbox_new should not return nil")
	
	mi: MayItem = (^PolyNode)(mb)
	
	// Must close before dispose.
	matryoshka.mbox_close(mb)
	matryoshka.matryoshka_dispose(&mi)
	
	testing.expect(t, mi == nil, "mi should be nil after matryoshka_dispose")
}

@test
test_mbox_send_receive :: proc(t: ^testing.T) {
	mb := matryoshka.mbox_new(context.allocator)
	defer {
		mi_mb: MayItem = (^PolyNode)(mb)
		matryoshka.mbox_close(mb)
		matryoshka.matryoshka_dispose(&mi_mb)
	}

	// Create an item using Layer 1 builder.
	b := ex1.make_builder(context.allocator)
	mi := ex1.ctor(&b, int(ex1.ItemId.Event))
	testing.expect(t, mi != nil, "ctor should not return nil")

	ptr, _ := mi.?
	ev := (^ex1.Event)(ptr)
	ev.code = 42

	// Send it.
	res_send := matryoshka.mbox_send(mb, &mi)
	testing.expect(t, res_send == .Ok, "mbox_send should return .Ok")
	testing.expect(t, mi == nil, "mi should be nil after successful send")

	// Receive it.
	mi_got: MayItem
	res_recv := matryoshka.mbox_wait_receive(mb, &mi_got, 0)
	testing.expect(t, res_recv == .Ok, "mbox_wait_receive should return .Ok")
	testing.expect(t, mi_got != nil, "mi_got should not be nil after successful receive")

	ptr_got, ok := mi_got.?
	testing.expect(t, ok, "unwrap should succeed")
	ev_got := (^ex1.Event)(ptr_got)
	testing.expect(t, ev_got.code == 42, "received code should match sent code")

	ex1.dtor(&b, &mi_got)
}

@test
test_mbox_fifo :: proc(t: ^testing.T) {
	mb := matryoshka.mbox_new(context.allocator)
	defer {
		mi_mb: MayItem = (^PolyNode)(mb)
		matryoshka.mbox_close(mb)
		matryoshka.matryoshka_dispose(&mi_mb)
	}

	b := ex1.make_builder(context.allocator)
	
	// Send 1, 2, 3.
	for i in 1..=3 {
		mi := ex1.ctor(&b, int(ex1.ItemId.Event))
		ptr, _ := mi.?
		(^ex1.Event)(ptr).code = i
		matryoshka.mbox_send(mb, &mi)
	}

	// Receive 1, 2, 3.
	for i in 1..=3 {
		mi_got: MayItem
		matryoshka.mbox_wait_receive(mb, &mi_got, 0)
		ptr, _ := mi_got.?
		testing.expect(t, (^ex1.Event)(ptr).code == i, "FIFO order mismatch")
		ex1.dtor(&b, &mi_got)
	}
}

@test
test_mbox_timeout :: proc(t: ^testing.T) {
	mb := matryoshka.mbox_new(context.allocator)
	defer {
		mi_mb: MayItem = (^PolyNode)(mb)
		matryoshka.mbox_close(mb)
		matryoshka.matryoshka_dispose(&mi_mb)
	}

	mi: MayItem
	res := matryoshka.mbox_wait_receive(mb, &mi, 10 * time.Millisecond)
	testing.expect(t, res == .Timeout, "empty mbox receive should timeout")
}

@test
test_mbox_interrupt :: proc(t: ^testing.T) {
	mb := matryoshka.mbox_new(context.allocator)
	defer {
		mi_mb: MayItem = (^PolyNode)(mb)
		matryoshka.mbox_close(mb)
		matryoshka.matryoshka_dispose(&mi_mb)
	}

	matryoshka.mbox_interrupt(mb)
	
	mi: MayItem
	res := matryoshka.mbox_wait_receive(mb, &mi, 0)
	testing.expect(t, res == .Interrupted, "interrupt should result in .Interrupted")
	
	// Next call should timeout (if empty).
	res2 := matryoshka.mbox_wait_receive(mb, &mi, 0)
	testing.expect(t, res2 == .Timeout, "interrupt flag should be self-clearing")
}

@test
test_mbox_close_returns_remaining :: proc(t: ^testing.T) {
	mb := matryoshka.mbox_new(context.allocator)
	b := ex1.make_builder(context.allocator)

	// Send 2 items.
	mi1 := ex1.ctor(&b, int(ex1.ItemId.Event))
	matryoshka.mbox_send(mb, &mi1)
	mi2 := ex1.ctor(&b, int(ex1.ItemId.Event))
	matryoshka.mbox_send(mb, &mi2)

	remaining := matryoshka.mbox_close(mb)
	count := 0
	for {
		raw := list.pop_front(&remaining)
		if raw == nil { break }
		mi: MayItem = (^PolyNode)(raw)
		ex1.dtor(&b, &mi)
		count += 1
	}
	testing.expect(t, count == 2, "mbox_close should return all remaining items")

	mi_mb: MayItem = (^PolyNode)(mb)
	matryoshka.matryoshka_dispose(&mi_mb)
}

@test
test_mbox_try_receive_batch :: proc(t: ^testing.T) {
	mb := matryoshka.mbox_new(context.allocator)
	defer {
		mi_mb: MayItem = (^PolyNode)(mb)
		matryoshka.mbox_close(mb)
		matryoshka.matryoshka_dispose(&mi_mb)
	}
	b := ex1.make_builder(context.allocator)

	// Send 3 items.
	for _ in 1..=3 {
		mi := ex1.ctor(&b, int(ex1.ItemId.Event))
		matryoshka.mbox_send(mb, &mi)
	}

	batch, res := matryoshka.try_receive_batch(mb)
	testing.expect(t, res == .Ok, "try_receive_batch should return .Ok")
	
	count := 0
	for {
		raw := list.pop_front(&batch)
		if raw == nil { break }
		mi: MayItem = (^PolyNode)(raw)
		ex1.dtor(&b, &mi)
		count += 1
	}
	testing.expect(t, count == 3, "batch should contain all 3 items")
}

@test
test_mbox_invalid_inputs :: proc(t: ^testing.T) {
	mb := matryoshka.mbox_new(context.allocator)
	defer {
		mi_mb: MayItem = (^PolyNode)(mb)
		matryoshka.mbox_close(mb)
		matryoshka.matryoshka_dispose(&mi_mb)
	}

	// Nil MayItem.
	res1 := matryoshka.mbox_send(mb, nil)
	testing.expect(t, res1 == .Invalid, "mbox_send with nil MayItem should return .Invalid")

	// Empty MayItem.
	var_mi: MayItem = nil
	res2 := matryoshka.mbox_send(mb, &var_mi)
	testing.expect(t, res2 == .Invalid, "mbox_send with empty MayItem should return .Invalid")

	// MayItem with id == 0.
	poly0 := new(PolyNode, context.allocator)
	poly0.id = 0
	mi0: MayItem = poly0
	res3 := matryoshka.mbox_send(mb, &mi0)
	testing.expect(t, res3 == .Invalid, "mbox_send with id == 0 should return .Invalid")
	free(poly0)
}
