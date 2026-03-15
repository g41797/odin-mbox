package examples

import mbox "../mbox"
import pool_pkg "../pool"
import list "core:container/intrusive/list"

// Master owns a pool and a mailbox together.
// One struct. One shutdown call. No leaks.
Master :: struct {
	pool:  pool_pkg.Pool(Msg),
	inbox: mbox.Mailbox(Msg),
}

// master_init is now a factory proc that demonstrates Idiom 11: errdefer-dispose.
// [itc: errdefer-dispose]
create_master :: proc(initial_msgs: int, max_msgs: int) -> (m: ^Master, ok: bool) {
	raw := new(Master) // [itc: heap-master]
	// If new fails, we return (nil, false) — ok is false (zero value).
	if raw == nil { return }

	m_opt: Maybe(^Master) = raw
	// named return 'ok' is checked at exit time.
	// if post-init setup fails, dispose cleans up the partially-init master.
	defer if !ok { master_dispose(&m_opt) }

	init_ok, _ := pool_pkg.init(&raw.pool, initial_msgs = initial_msgs, max_msgs = max_msgs, reset = nil)
	if !init_ok { return }

	// ... potential further setup ...

	m = raw
	ok = true
	return
}

// master_shutdown closes the inbox, returns undelivered messages to the pool, then destroys the pool.
//
// Order matters:
// - Return messages to pool BEFORE destroy.
// - Calling destroy first would make the returned pointers invalid.
master_shutdown :: proc(m: ^Master) {
	remaining, _ := mbox.close(&m.inbox)
	for node := list.pop_front(&remaining); node != nil; node = list.pop_front(&remaining) {
		msg := container_of(node, Msg, "node")
		msg_opt: Maybe(^Msg) = msg
		ptr, accepted := pool_pkg.put(&m.pool, &msg_opt) // back to pool, not freed
		if !accepted && ptr != nil {
			p_opt: Maybe(^Msg) = ptr
			_msg_dispose(&p_opt) // [itc: foreign-dispose]
		}
	}
	pool_pkg.destroy(&m.pool)
}

// master_dispose shuts down and frees a heap-allocated Master.
// Follows the ^Maybe(^T) contract: nil inner is a no-op; sets inner to nil on return.
master_dispose :: proc(m: ^Maybe(^Master)) { // [itc: dispose-contract]
	mp, ok := m.?
	if !ok || mp == nil {return}
	master_shutdown(mp)
	free(mp)
	m^ = nil
}

// master_example shows pool + mailbox owned by one heap-allocated struct.
master_example :: proc() -> bool {
	m, ok := create_master(8, 64)
	if !ok {
		return false
	}
	m_opt: Maybe(^Master) = m
	defer master_dispose(&m_opt) // [itc: defer-dispose]

	msg, _ := pool_pkg.get(&m.pool)
	if msg == nil {
		return false
	}
	msg_opt: Maybe(^Msg) = msg // [itc: maybe-container]
	msg_opt.?.data = 42
	if !mbox.send(&m.inbox, &msg_opt) {
		// send failed — return message to pool before dispose
		// msg_opt is still non-nil (send failed, caller retains ownership)
		ptr, accepted := pool_pkg.put(&m.pool, &msg_opt)
		if !accepted && ptr != nil {
			p_opt: Maybe(^Msg) = ptr
			_msg_dispose(&p_opt) // [itc: foreign-dispose]
		}
		return false
	}

	return true
}
