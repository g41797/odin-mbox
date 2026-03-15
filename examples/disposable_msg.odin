package examples

import mbox "../mbox"
import pool_pkg "../pool"
import list "core:container/intrusive/list"
import "core:mem"
import "core:strings"
import "core:thread"

// DisposableMsg is a message with an internal heap-allocated field.
// It requires a dispose proc for final cleanup.
// It uses reset for reuse hygiene inside the pool.
DisposableMsg :: struct {
	node:      list.Node,
	allocator: mem.Allocator,
	name:      string, // heap-allocated — must be freed before the struct
}

// disposable_reset clears stale state without freeing internal resources.
// Pool calls it automatically on get (before handing to caller) and on put (before free-list).
// Does NOT free name. Pool reuses the slot.
// [itc: reset-vs-dispose]
disposable_reset :: proc(msg: ^DisposableMsg, _: pool_pkg.Pool_Event) {
	msg.name = ""
}

// disposable_dispose frees all internal resources, then frees the struct.
// Follows the ^Maybe(^T) contract: nil inner is a no-op. Sets inner to nil on return.
// Caller uses this for permanent cleanup. Pool and mailbox never call it.
// [itc: dispose-contract]
disposable_dispose :: proc(msg: ^Maybe(^DisposableMsg)) {
	if msg^ == nil {return}
	ptr := (msg^).?
	if ptr.name != "" {
		delete(ptr.name, ptr.allocator)
	}
	free(ptr, ptr.allocator)
	msg^ = nil
}

@(private)
_Disposable_Master :: struct {
	pool: pool_pkg.Pool(DisposableMsg),
	mb:   mbox.Mailbox(DisposableMsg),
}

@(private)
_disposable_master_dispose :: proc(m: ^Maybe(^_Disposable_Master)) { // [itc: dispose-contract]
	mp, ok := m.?
	if !ok || mp == nil { return }

	// Drain mailbox and return to pool or dispose
	remaining, _ := mbox.close(&mp.mb)
	for node := list.pop_front(&remaining); node != nil; node = list.pop_front(&remaining) {
		msg := container_of(node, DisposableMsg, "node")
		m_opt: Maybe(^DisposableMsg) = msg
		
		// Respect Idiom 6: check if accepted by pool
		ptr, accepted := pool_pkg.put(&mp.pool, &m_opt)
		if !accepted && ptr != nil {
			// Foreign or pool closed: manual dispose [itc: foreign-dispose]
			p_opt: Maybe(^DisposableMsg) = ptr
			disposable_dispose(&p_opt)
		}
	}

	pool_pkg.destroy(&mp.pool)
	free(mp)
	m^ = nil
}

// disposable_msg_example shows a full lifecycle with internal resources:
//   producer: pool.get → fill name → send
//   consumer: receive → process → pool.put (reset clears name automatically)
//
// Also shows the error path: if send fails, defer dispose handles cleanup.
disposable_msg_example :: proc() -> bool {
	m := new(_Disposable_Master) // [itc: heap-master]
	m_opt: Maybe(^_Disposable_Master) = m
	defer _disposable_master_dispose(&m_opt) // [itc: defer-dispose]

	ok, _ := pool_pkg.init(&m.pool, initial_msgs = 4, max_msgs = 0, reset = disposable_reset)
	if !ok {
		return false
	}

	result := false

	// Consumer thread: receives one message, checks the name, puts back to pool.
	t := thread.create_and_start_with_poly_data(m, proc(m: ^_Disposable_Master) { // [itc: thread-container]
		msg, err := mbox.wait_receive(&m.mb)
		if err != .None || msg == nil {
			return
		}
		// process: name is set
		_ = msg.name
		// return to pool — reset runs automatically, clears name
		m_opt: Maybe(^DisposableMsg) = msg
		ptr, accepted := pool_pkg.put(&m.pool, &m_opt) // [itc: defer-put] (using it to check acceptance)
		if !accepted && ptr != nil {
			p_opt: Maybe(^DisposableMsg) = ptr
			disposable_dispose(&p_opt) // [itc: foreign-dispose]
		}
	})

	// Producer: get from pool, fill resources, send.
	msg, status := pool_pkg.get(&m.pool)
	if status != .Ok {
		thread.join(t)
		thread.destroy(t)
		return false
	}

	msg_opt: Maybe(^DisposableMsg) = msg // [itc: maybe-container]
	defer disposable_dispose(&msg_opt) // no-op if send succeeded // [itc: defer-dispose]

	msg_opt.?.name = strings.clone("hello", msg_opt.?.allocator)
	if mbox.send(&m.mb, &msg_opt) {
		result = true
	}
	// if send failed: m is non-nil, defer dispose handles cleanup

	thread.join(t)
	thread.destroy(t)

	return result
}
