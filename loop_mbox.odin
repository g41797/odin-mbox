package mbox

import "base:intrinsics"
import list "core:container/intrusive/list"
import "core:nbio"
import "core:sync"

// _LoopNode, _LoopMutex, _Loop ensure imports are used — required by -vet for generic code.
@(private)
_LoopNode :: list.Node
@(private)
_LoopMutex :: sync.Mutex
@(private)
_Loop :: nbio.Event_Loop

Loop_Mailbox :: struct($T: typeid) {
	mutex:  sync.Mutex,
	list:   list.List,
	len:    int,
	loop:   ^nbio.Event_Loop,
	closed: bool,
}

send_to_loop :: proc(
	m: ^Loop_Mailbox($T),
	msg: ^T,
) -> bool where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") ==
	list.Node {
	_ = m
	_ = msg
	return false
}

try_receive_loop :: proc(
	m: ^Loop_Mailbox($T),
) -> (
	msg: ^T,
	ok: bool,
) where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") ==
	list.Node {
	_ = m
	return nil, false
}

close_loop :: proc(m: ^Loop_Mailbox($T)) where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") == list.Node {
	_ = m
}

stats :: proc(m: ^Loop_Mailbox($T)) -> int where intrinsics.type_has_field(T, "node"),
	intrinsics.type_field_type(T, "node") == list.Node {
	_ = m
	return 0
}
