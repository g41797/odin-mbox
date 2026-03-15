package examples

import mbox "../mbox"
import nbio_mbox "../nbio_mbox"
import loop_mbox "../loop_mbox"
import list "core:container/intrusive/list"
import "core:nbio"
import "core:thread"

// _Worker holds the loop mailbox, reply mailbox, and the result.
// Heap-allocated so the worker thread can hold its address safely.
@(private)
_Worker :: struct {
	loop_mb:  ^loop_mbox.Mbox(Msg),
	reply_mb: mbox.Mailbox(Msg),
	ok:       bool,
}

@(private)
_worker_dispose :: proc(w: ^Maybe(^_Worker)) { // [itc: dispose-contract]
	wp, ok := w.?
	if !ok || wp == nil {return}
	
	// Dispose loop_mb
	if wp.loop_mb != nil {
		remaining_loop, _ := loop_mbox.close(wp.loop_mb)
		for node := list.pop_front(&remaining_loop); node != nil; node = list.pop_front(&remaining_loop) {
			msg := (^Msg)(node)
			msg_opt: Maybe(^Msg) = msg
			_msg_dispose(&msg_opt) // [itc: dispose-optional]
		}
		loop_mbox.destroy(wp.loop_mb)
	}

	// Dispose reply_mb
	remaining, _ := mbox.close(&wp.reply_mb)
	for node := list.pop_front(&remaining); node != nil; node = list.pop_front(&remaining) {
		msg := (^Msg)(node)
		msg_opt: Maybe(^Msg) = msg
		_msg_dispose(&msg_opt) // [itc: dispose-optional]
	}

	free(wp)
	w^ = nil
}

// negotiation_example shows request-reply between a worker thread and an nbio event loop.
//
// Flow:
//   worker  →  loop_mbox  →  nbio loop
//   nbio loop →  Mailbox  →  worker
//
// - Worker allocates a request on the heap, sends it to the loop.
// - Loop receives the request. Reuses it as the reply (increments data, sends back).
// - Worker receives the reply and frees it.
// - One allocation per round-trip. Worker owns the memory start to finish.
negotiation_example :: proc(kind: nbio_mbox.Nbio_Wakeuper_Kind = .UDP) -> bool {
	err := nbio.acquire_thread_event_loop()
	if err != nil {
		return false
	}
	defer nbio.release_thread_event_loop()

	loop := nbio.current_thread_event_loop()

	w := new(_Worker) // [itc: heap-master]
	w_opt: Maybe(^_Worker) = w
	defer _worker_dispose(&w_opt) // [itc: defer-dispose]

	// loop_mb receives requests from the worker.
	init_err: nbio_mbox.Nbio_Mailbox_Error
	w.loop_mb, init_err = nbio_mbox.init_nbio_mbox(Msg, loop, kind)
	if init_err != .None {
		return false
	}

	// Worker: allocates request, sends to loop, waits for reply, frees reply.
	t := thread.create_and_start_with_poly_data(w, proc(w: ^_Worker) { // [itc: thread-container]
		req: Maybe(^Msg) = new(Msg) // [itc: maybe-container]
		req.?.data = 10
		req.?.allocator = context.allocator
		if !loop_mbox.send(w.loop_mb, &req) {
			_msg_dispose(&req)
			return
		}

		// Worker allocated req; loop will send it back as reply.
		reply, recv_err := mbox.wait_receive(&w.reply_mb)
		w.ok = recv_err == .None && reply != nil && reply.data == 11
		if reply != nil {
			reply_opt: Maybe(^Msg) = reply
			_msg_dispose(&reply_opt) // [itc: dispose-optional]
		}
	})

	// Event loop: tick until request arrives, increment data, send back as reply.
	for {
		tick_err := nbio.tick()
		if tick_err != nil {
			break
		}
		nb := loop_mbox.try_receive_batch(w.loop_mb)
		node := list.pop_front(&nb)
		if node != nil {
			// Reuse the received message as the reply.
			// No extra allocation needed. Ownership stays with the worker.
			msg_inner := (^Msg)(node)
			msg: Maybe(^Msg) = msg_inner
			msg.?.data += 1
			if !mbox.send(&w.reply_mb, &msg) {
				_msg_dispose(&msg)
			}
			break
		}
	}

	thread.join(t)
	thread.destroy(t)

	return w.ok
}
