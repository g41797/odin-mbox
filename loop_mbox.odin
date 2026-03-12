// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

package mbox

import "base:intrinsics"
import list "core:container/intrusive/list"
import "core:nbio"
import "core:sync"

// _LoopNode, _LoopMutex, _Loop keep -vet happy — it does not count generic field types as import usage.
@(private)
_LoopNode :: list.Node
@(private)
_LoopMutex :: sync.Mutex
@(private)
_Loop :: nbio.Event_Loop

// Loop_Mailbox is a command queue for an nbio event loop.
// It does not block. It uses a no-op timeout to wake tick().
// T must have a field named "node" of type list.Node.
Loop_Mailbox :: struct($T: typeid) {
	mutex:  sync.Mutex,
	list:   list.List,
	len:    int,
	loop:   ^nbio.Event_Loop,
	closed: bool,
}

// _noop is the required callback for nbio.timeout. It does nothing.
@(private)
_noop :: proc(_: ^nbio.Operation) {}

// send_to_loop adds msg to the mailbox and wakes the nbio loop.
// Returns false if the mailbox is closed.
send_to_loop :: proc(
	m: ^Loop_Mailbox($T),
	msg: ^T,
) -> bool where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") ==
	list.Node {
	sync.mutex_lock(&m.mutex)
	if m.closed {
		sync.mutex_unlock(&m.mutex)
		return false
	}
	list.push_back(&m.list, &msg.node)
	m.len += 1
	sync.mutex_unlock(&m.mutex)

	// Schedule a no-op so tick() returns and the caller can drain the mailbox.
	nbio.timeout(0, _noop, m.loop)
	return true
}

// try_receive_loop returns one message without blocking.
// Call in a loop until ok is false to drain the mailbox.
try_receive_loop :: proc(
	m: ^Loop_Mailbox($T),
) -> (
	msg: ^T,
	ok: bool,
) where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") ==
	list.Node {
	sync.mutex_lock(&m.mutex)
	defer sync.mutex_unlock(&m.mutex)
	if m.len == 0 {
		return nil, false
	}
	raw := list.pop_front(&m.list)
	m.len -= 1
	return container_of(raw, T, "node"), true
}

// close_loop prevents new messages, wakes the loop one last time,
// and returns any unprocessed messages as a list.List.
// Returns (remaining, true) on first call; ({}, false) if already closed.
close_loop :: proc(m: ^Loop_Mailbox($T)) -> (remaining: list.List, was_open: bool) where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") == list.Node {
	sync.mutex_lock(&m.mutex)
	if m.closed {
		sync.mutex_unlock(&m.mutex)
		return {}, false
	}
	m.closed = true
	remaining = m.list
	m.list = {}
	m.len = 0
	sync.mutex_unlock(&m.mutex)

	// Wake the loop so it notices the mailbox is closed.
	nbio.timeout(0, _noop, m.loop)
	return remaining, true
}

// stats returns the current number of pending messages.
// Not locked — value is approximate.
stats :: proc(m: ^Loop_Mailbox($T)) -> int where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") == list.Node {
	return m.len
}
