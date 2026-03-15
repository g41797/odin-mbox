package examples

import mbox "../mbox"
import mpsc "../mpsc"
import pool_pkg "../pool"
import list "core:container/intrusive/list"
import "core:mem"
import "core:sync"
import "core:thread"

// Echo_Msg is a message with a reply address.
// Sent from a client to the server; server echoes it back via reply_to.
Echo_Msg :: struct {
	node:      list.Node,
	allocator: mem.Allocator,
	data:      int,
	reply_to:  ^mbox.Mailbox(Echo_Msg),
}

// _Echo_Server owns pool, queue, and sema for the server thread.
// Heap-allocated so the server thread can hold its address safely.
@(private)
_Echo_Server :: struct {
	pool:  pool_pkg.Pool(Echo_Msg),
	q:     mpsc.Queue(Echo_Msg),
	sema:  sync.Sema,
	count: int,
}

@(private)
_echo_server_init :: proc(srv: ^_Echo_Server, n_msgs: int, n_clients: int) -> bool {
	ok, _ := pool_pkg.init(&srv.pool, initial_msgs = n_msgs, max_msgs = n_msgs, reset = nil)
	if !ok {return false}
	mpsc.init(&srv.q)
	srv.count = n_clients
	return true
}

@(private)
_echo_server_dispose :: proc(srv: ^Maybe(^_Echo_Server)) { // [itc: dispose-contract]
	sp, ok := srv.?
	if !ok || sp == nil {return}
	pool_pkg.destroy(&sp.pool)
	free(sp)
	srv^ = nil
}

// _Echo_Client owns the per-client inbox and borrows a pointer to the server.
// Stored in a heap-allocated slice so the address is stable across thread spawning.
@(private)
_Echo_Client :: struct {
	server: ^_Echo_Server,          // borrows server; does not own
	my_id:  int,
	ok:     bool,
	inbox:  mbox.Mailbox(Echo_Msg), // [itc: thread-container] — inbox lives in struct, not thread stack
}

// echo_server_example shows raw mpsc.Queue + sync.Sema — building blocks of loop_mbox.
echo_server_example :: proc() -> bool {
	N_CLIENTS :: 8
	M_MSGS    :: 4 // fewer tokens than clients — forces backpressure

	srv := new(_Echo_Server) // [itc: heap-master]
	if !_echo_server_init(srv, M_MSGS, N_CLIENTS) {
		free(srv)
		return false
	}
	srv_opt: Maybe(^_Echo_Server) = srv
	defer _echo_server_dispose(&srv_opt) // [itc: defer-dispose]

	// Server thread: process exactly N_CLIENTS messages, then exit.
	server_thread := thread.create_and_start_with_data(
		srv,
		proc(data: rawptr) {
			s := (^_Echo_Server)(data) // [itc: thread-container]
			processed := 0
			for processed < s.count {
				sync.sema_wait(&s.sema)
				// Drain all available messages on each wake.
				for {
					node := mpsc.pop(&s.q)
					if node == nil {break}
					msg := (^Echo_Msg)(node)
					reply_to := msg.reply_to
					reply: Maybe(^Echo_Msg) = msg // [itc: maybe-container]
					mbox.send(reply_to, &reply)
					processed += 1
				}
			}
		},
	)

	// Client threads: get token, send to server, wait for echo, verify, return token.
	client_threads := make([]^thread.Thread, N_CLIENTS)
	defer delete(client_threads)
	ctxs := make([]_Echo_Client, N_CLIENTS)
	defer delete(ctxs)

	for i in 0 ..< N_CLIENTS {
		ctxs[i] = _Echo_Client{
			server = srv,
			my_id  = i,
		}
		client_threads[i] = thread.create_and_start_with_data(
			&ctxs[i],
			proc(data: rawptr) {
				c := (^_Echo_Client)(data) // [itc: thread-container]

				// Get a token (blocks if all tokens are in flight — backpressure).
				msg, status := pool_pkg.get(&c.server.pool, .Pool_Only, -1)
				if status != .Ok || msg == nil {
					return
				}

				msg.data = c.my_id
				msg.reply_to = &c.inbox

				// Push to server queue and wake the server.
				m: Maybe(^Echo_Msg) = msg // [itc: maybe-container]
				if !mpsc.push(&c.server.q, &m) {
					// push failed — return token to pool
					ptr, accepted := pool_pkg.put(&c.server.pool, &m)
					if !accepted && ptr != nil {
						// _echo_msg_dispose not defined, using inline free for this example
						// but in real system would follow dispose-contract
						free(ptr, ptr.allocator)
					}
					return
				}
				sync.sema_post(&c.server.sema)

				// Wait for the echo reply.
				reply, err := mbox.wait_receive(&c.inbox)
				if err != .None || reply == nil {
					return
				}
				c.ok = reply.data == c.my_id

				// Return the token to the pool.
				reply_opt: Maybe(^Echo_Msg) = reply // [itc: maybe-container]
				ptr, accepted := pool_pkg.put(&c.server.pool, &reply_opt)
				if !accepted && ptr != nil {
					free(ptr, ptr.allocator) // [itc: foreign-dispose]
				}
			},
		)
	}

	// Wait for all clients and the server to finish.
	thread.join(server_thread)
	thread.destroy(server_thread)

	for i in 0 ..< N_CLIENTS {
		thread.join(client_threads[i])
		thread.destroy(client_threads[i])
	}

	// Check all clients got correct echoes.
	all_ok := true
	for i in 0 ..< N_CLIENTS {
		if !ctxs[i].ok {
			all_ok = false
		}
	}

	return all_ok
}
