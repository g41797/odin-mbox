// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

package mbox

import "base:intrinsics"
import list "core:container/intrusive/list"
import "core:mem"
import "core:nbio"
import "core:time"
import try_mbox "./try_mbox"
import wakeup "./wakeup"

// -vet workarounds: some import usages are not detected in all contexts.
@(private) _NBioList :: list.Node
@(private) _NBioDuration :: time.Duration
@(private) _NBioWaker :: wakeup.WakeUper

// _NBio_State holds the nbio event loop and keepalive timer for one nbio_mbox instance.
@(private)
_NBio_State :: struct {
	loop:         ^nbio.Event_Loop,
	keepalive:    ^nbio.Operation,
	allocator:    mem.Allocator,
	wake_pending: bool, // atomic — guards the cross-thread timeout queue (capacity 128)
}

// _noop is the required no-op callback for nbio operations (used by keepalive timer).
@(private)
_noop :: proc(_: ^nbio.Operation) {}

// _noop_clear clears the wake_pending flag. Runs in the event-loop thread after timeout fires.
@(private)
_noop_clear :: proc(_: ^nbio.Operation, state: ^_NBio_State) {
	intrinsics.atomic_store(&state.wake_pending, false)
}

// _nbio_wake fires a zero-duration timeout to wake the nbio event loop.
// Uses an atomic CAS flag so at most one timeout is queued at a time, preventing
// the 128-slot cross-thread queue from overflowing under high-frequency sends.
@(private)
_nbio_wake :: proc(ctx: rawptr) {
	if ctx == nil {
		return
	}
	state := (^_NBio_State)(ctx)
	// CAS false→true. Returns old value; if old != false, wake already pending — skip.
	if intrinsics.atomic_compare_exchange_strong(&state.wake_pending, false, true) != false {
		return
	}
	nbio.timeout_poly(0, state, _noop_clear, state.loop)
}

// _nbio_close removes the keepalive timer and frees the state.
@(private)
_nbio_close :: proc(ctx: rawptr) {
	if ctx == nil {
		return
	}
	state := (^_NBio_State)(ctx)
	if state.keepalive != nil {
		nbio.remove(state.keepalive)
		state.keepalive = nil
	}
	free(state, state.allocator)
}

// Loop_Mailbox_Error is the error returned by init_nbio_mbox.
Loop_Mailbox_Error :: enum {
	None,
	Invalid_Loop,
	Keepalive_Failed,
}

// init_nbio_mbox allocates a try_mbox.Mbox wired to the nbio event loop.
// Returns (nil, .Invalid_Loop) if loop is nil.
// Returns (nil, .Keepalive_Failed) if keepalive timer or Mbox allocation fails.
// The returned Mbox uses try_mbox.send, try_mbox.try_receive, try_mbox.close, try_mbox.destroy.
init_nbio_mbox :: proc(
	$T: typeid,
	loop: ^nbio.Event_Loop,
	allocator := context.allocator,
) -> (^try_mbox.Mbox(T), Loop_Mailbox_Error) where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") == list.Node {
	if loop == nil {
		return nil, .Invalid_Loop
	}
	state := new(_NBio_State, allocator)
	if state == nil {
		return nil, .Keepalive_Failed
	}
	state.loop = loop
	state.allocator = allocator
	state.keepalive = nbio.timeout(time.Hour * 24, _noop, loop)
	if state.keepalive == nil {
		free(state, allocator)
		return nil, .Keepalive_Failed
	}
	waker := wakeup.WakeUper{ctx = rawptr(state), wake = _nbio_wake, close = _nbio_close}
	m := try_mbox.init(T, waker, allocator)
	if m == nil {
		_nbio_close(rawptr(state))
		return nil, .Keepalive_Failed
	}
	return m, .None
}
