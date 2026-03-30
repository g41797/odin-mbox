// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

package matryoshka

// matryoshka_dispose is the only way to teardown infrastructure items.
//
// Entry:
//   - m == nil  → no-op
//   - m^ == nil → no-op
//
// The item must be closed before disposal (mbox_close / pool_close).
// Panics if the item is still open, or if the id is not a known system id.
//
// Exit:
//   - m^ = nil on success
matryoshka_dispose :: proc(m: ^MayItem) {
	if m == nil || m^ == nil {
		return
	}
	ptr, _ := m^.?
	switch ptr.id {
	case MAILBOX_ID:
		_mbox_dispose(m)
	case POOL_ID:
		_pool_dispose(m)
	case:
		panic("matryoshka_dispose: unknown system id or not an infrastructure item")
	}
}
