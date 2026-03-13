// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

package try_mbox

import list "core:container/intrusive/list"
import "core:testing"
import wakeup "../wakeup"

// _TM is the test message type used in all try_mbox tests.
_TM :: struct {
	node: list.Node,
	data: int,
}

// _WC is a counter for waker callback tests.
_WC :: struct {
	wake_count:   int,
	close_called: bool,
}

@(private)
_wc_wake :: proc(ctx: rawptr) {
	c := (^_WC)(ctx)
	c.wake_count += 1
}

@(private)
_wc_close :: proc(ctx: rawptr) {
	c := (^_WC)(ctx)
	c.close_called = true
}

@(test)
test_init_destroy :: proc(t: ^testing.T) {
	m := init(_TM)
	testing.expect(t, m != nil, "init should return non-nil")
	destroy(m)
}

@(test)
test_send_try_receive_basic :: proc(t: ^testing.T) {
	m := init(_TM)
	defer destroy(m)
	msg := _TM{data = 42}
	ok := send(m, &msg)
	testing.expect(t, ok, "send should return true")
	got, ok2 := try_receive(m)
	testing.expect(t, ok2, "try_receive should return true")
	testing.expect(t, got != nil && got.data == 42, "received message should have data == 42")
}

@(test)
test_try_receive_empty :: proc(t: ^testing.T) {
	m := init(_TM)
	defer destroy(m)
	got, ok := try_receive(m)
	testing.expect(t, !ok, "try_receive on empty should return false")
	testing.expect(t, got == nil, "try_receive on empty should return nil")
}

@(test)
test_send_closed :: proc(t: ^testing.T) {
	m := init(_TM)
	defer destroy(m)
	_, _ = close(m)
	msg := _TM{data = 1}
	ok := send(m, &msg)
	testing.expect(t, !ok, "send after close should return false")
}

@(test)
test_close_returns_remaining :: proc(t: ^testing.T) {
	m := init(_TM)
	defer destroy(m)
	a := _TM{data = 1}
	b := _TM{data = 2}
	c := _TM{data = 3}
	send(m, &a)
	send(m, &b)
	send(m, &c)
	remaining, was_open := close(m)
	testing.expect(t, was_open, "close should return was_open == true")
	count := 0
	for {
		raw := list.pop_front(&remaining)
		if raw == nil {
			break
		}
		count += 1
	}
	testing.expect(t, count == 3, "close should drain 3 remaining messages")
}

@(test)
test_close_idempotent :: proc(t: ^testing.T) {
	m := init(_TM)
	defer destroy(m)
	_, first := close(m)
	_, second := close(m)
	testing.expect(t, first, "first close should return true")
	testing.expect(t, !second, "second close should return false")
}

@(test)
test_length :: proc(t: ^testing.T) {
	m := init(_TM)
	defer destroy(m)
	testing.expect(t, length(m) == 0, "length should be 0 initially")
	a := _TM{data = 1}
	b := _TM{data = 2}
	send(m, &a)
	send(m, &b)
	testing.expect(t, length(m) == 2, "length should be 2 after 2 sends")
	try_receive(m)
	testing.expect(t, length(m) == 1, "length should be 1 after one try_receive")
}

@(test)
test_waker_called_on_send :: proc(t: ^testing.T) {
	wc: _WC
	waker := wakeup.WakeUper{ctx = rawptr(&wc), wake = _wc_wake}
	m := init(_TM, waker)
	defer destroy(m)
	a := _TM{data = 1}
	b := _TM{data = 2}
	c := _TM{data = 3}
	send(m, &a)
	send(m, &b)
	send(m, &c)
	// wake should be called once per send; 3 sends → count == 3
	testing.expect(t, wc.wake_count == 3, "wake should be called once per send; 3 sends → count == 3")
}

@(test)
test_waker_close_on_close :: proc(t: ^testing.T) {
	wc: _WC
	waker := wakeup.WakeUper{ctx = rawptr(&wc), close = _wc_close}
	m := init(_TM, waker)
	defer destroy(m)
	_, _ = close(m)
	testing.expect(t, wc.close_called, "waker.close should be called on mailbox close")
}

@(test)
test_no_waker :: proc(t: ^testing.T) {
	m := init(_TM) // zero WakeUper
	defer destroy(m)
	msg := _TM{data = 99}
	ok := send(m, &msg)
	testing.expect(t, ok, "send without waker should return true")
	got, ok2 := try_receive(m)
	testing.expect(t, ok2 && got != nil && got.data == 99, "try_receive without waker should work")
}

@(test)
test_try_receive_all_basic :: proc(t: ^testing.T) {
	m := init(_TM)
	defer destroy(m)
	a := _TM{data = 1}
	b := _TM{data = 2}
	c := _TM{data = 3}
	send(m, &a)
	send(m, &b)
	send(m, &c)
	result := try_receive_all(m)
	count := 0
	for {
		node := list.pop_front(&result)
		if node == nil {break}
		count += 1
	}
	testing.expect(t, count == 3, "try_receive_all should return all 3 messages")
	testing.expect(t, length(m) == 0, "queue should be empty after try_receive_all")
}
