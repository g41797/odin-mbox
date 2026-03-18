/*
Package mbox provides a blocking inter-thread mailbox for Odin.

Core concepts:
- Zero copies: Messages are linked, not copied.
- Intrusive: Your message struct must have a field named "node" of type list.Node.
- Thread-safe: Safe to use from multiple threads.
- Blocking: wait_receive blocks the calling thread until a message arrives.

Basic requirement:

	import list "core:container/intrusive/list"

	My_Msg :: struct {
		node: list.Node, // required
		data: int,
	}

Idiom reference: design/idioms.md

Typical usage:

	mb: mbox.Mailbox(My_Msg)

	// sender thread:
	mbox.send(&mb, &msg)

	// receiver thread:
	got: Maybe(^My_Msg)
	err := mbox.wait_receive(&mb, &got)

*/
package mbox

/*
Note: Some test procedures may appear in the generated documentation.
This is because they are part of the same package to allow for white-box testing.
*/
