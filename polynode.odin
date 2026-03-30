// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

package matryoshka

import list "core:container/intrusive/list"

//////////////////////////////
MayItem :: Maybe(^PolyNode)
//////////////////////////////

// PolyNode is the intrusive node embedded at offset 0 in every matryoshka item.
//
// Embed via `using` at the first field:
//
//   Chunk :: struct {
//       using poly: PolyNode,  // offset 0 — required
//       data: [4096]byte,
//       len:  int,
//   }
//
// With `using`, field access is promoted: chunk.id == chunk.poly.id.
// The cast (^Chunk)(node) is valid only when PolyNode is at offset 0.
// matryoshka has no compile-time check for this — enforced by convention.
//
// id rules:
//   - Must be != 0 after creation.
//   - Zero is always invalid (zero value of int — catches uninitialized nodes).
//   - Ids are user-defined, typically from an enum.
//
// Ownership is tracked via MayItem (alias for Maybe(^PolyNode)) at every API boundary:
//
//   m: MayItem
//
//   m^ == nil   →  not yours (transferred, or nothing here)
//   m^ != nil   →  you own it — must transfer, recycle, or dispose
//   m  == nil   →  nil handle — invalid; API returns error
//
//   list.Node  — one prev/next; a node cannot be in two queues/containers at once.
//   MayItem    — nil/non-nil tells every API who holds the item.
PolyNode :: struct {
	using node: list.Node, // intrusive link — .prev, .next
	id:         int, // type discriminator, must be != 0
}

//////////////////////
// System IDs
//////////////////////
MAILBOX_ID: int : -1
POOL_ID:    int : -2

// polynode_reset clears the intrusive link pointers of n.
// Safe to call with n == nil (no-op).
//
// Infrastructure calls this on every single-item return (mbox_wait_receive, pool_get,
// pool_get_wait). Callers must call it themselves after list.pop_front on batch returns
// (mbox_close, try_receive_batch, pool_close) before passing to mbox_send or pool_put.
polynode_reset :: proc(n: ^PolyNode) {
	if n == nil {return}
	n.prev = nil
	n.next = nil
}

// polynode_is_linked reports whether n is currently linked into a list.
// Returns false if n == nil.
// Used internally as a debug assertion before every insert into infrastructure.
polynode_is_linked :: proc(n: ^PolyNode) -> bool {
	if n == nil {return false}
	return n.prev != nil || n.next != nil
}

