package examples

import mbox ".."
import list "core:container/intrusive/list"
import "core:nbio"

// Msg is the shared node type used in all examples.
// Field "node" is required by mbox — fixed name, type list.Node.
Msg :: struct {
	node: list.Node,
	data: int,
}

negotiation_example :: proc() -> bool {
	_ = mbox.Mailbox(Msg){}
	_ = mbox.Loop_Mailbox(Msg){}
	_ = nbio.Event_Loop{}
	return true
}
