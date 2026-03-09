package mbox

import "base:intrinsics"
import list "core:container/intrusive/list"
import "core:sync"
import "core:time"

// _Node and _Mutex ensure imports are used — required by -vet for generic code.
@(private)
_Node :: list.Node
@(private)
_Mutex :: sync.Mutex
@(private)
_Duration :: time.Duration

Mailbox_Error :: enum {
	None,
	Timeout,
	Closed,
	Interrupted,
}

Mailbox :: struct($T: typeid) {
	mutex:       sync.Mutex,
	cond:        sync.Cond,
	list:        list.List,
	len:         int,
	closed:      bool,
	interrupted: bool,
}

send :: proc(m: ^Mailbox($T), msg: ^T) -> bool where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") == list.Node {
	_ = m
	_ = msg
	return false
}

try_receive :: proc(
	m: ^Mailbox($T),
) -> (
	msg: ^T,
	ok: bool,
) where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") ==
	list.Node {
	_ = m
	return nil, false
}

wait_receive :: proc(
	m: ^Mailbox($T),
	timeout: time.Duration = -1,
) -> (
	msg: ^T,
	err: Mailbox_Error,
) where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") ==
	list.Node {
	_ = m
	_ = timeout
	return nil, .None
}

interrupt :: proc(m: ^Mailbox($T)) where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") == list.Node {
	_ = m
}

close :: proc(m: ^Mailbox($T)) where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") == list.Node {
	_ = m
}

reset :: proc(m: ^Mailbox($T)) where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") == list.Node {
	_ = m
}
