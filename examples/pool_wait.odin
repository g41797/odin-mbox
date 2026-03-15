package examples

import mbox "../mbox"
import pool_pkg "../pool"
import list "core:container/intrusive/list"
import "core:sync"
import "core:thread"

N_PLAYERS :: 6
M_TOKENS  :: 2 // fewer tokens than players — forces waiting

ROUNDS    :: 5

// _Pool_Wait_Collector owns all ITC participants for the pool_wait test.
// Heap-allocated so collector and player threads can hold its address safely.
@(private)
_Pool_Wait_Collector :: struct {
	pool:  pool_pkg.Pool(Msg),
	inbox: mbox.Mailbox(Msg),
	done:  sync.Sema,
}

@(private)
_pool_wait_collector_init :: proc(c: ^_Pool_Wait_Collector) -> bool {
	ok, _ := pool_pkg.init(&c.pool, initial_msgs = M_TOKENS, max_msgs = M_TOKENS, reset = nil)
	return ok
}

@(private)
_pool_wait_collector_dispose :: proc(c: ^Maybe(^_Pool_Wait_Collector)) { // [itc: dispose-contract]
	cp, ok := c.?
	if !ok || cp == nil {return}
	remaining, _ := mbox.close(&cp.inbox)
	for node := list.pop_front(&remaining); node != nil; node = list.pop_front(&remaining) {
		msg := container_of(node, Msg, "node")
		msg_opt: Maybe(^Msg) = msg
		_, _ = pool_pkg.put(&cp.pool, &msg_opt)
	}
	pool_pkg.destroy(&cp.pool)
	free(cp)
	c^ = nil
}

// pool_wait_example shows N players sharing M tokens (M < N).
// Players must wait (pool.get .Pool_Only, timeout=-1) until a token is returned.
pool_wait_example :: proc() -> bool {
	pc := new(_Pool_Wait_Collector) // [itc: heap-master]
	if !_pool_wait_collector_init(pc) {
		free(pc)
		return false
	}
	pc_opt: Maybe(^_Pool_Wait_Collector) = pc
	defer _pool_wait_collector_dispose(&pc_opt) // [itc: defer-dispose]

	// Collector: receives all messages and returns each token to pool.
	collector_thread := thread.create_and_start_with_data(
		pc,
		proc(data: rawptr) {
			c := (^_Pool_Wait_Collector)(data) // [itc: thread-container]
			total :: N_PLAYERS * ROUNDS
			count := 0
			for count < total {
				msg, err := mbox.wait_receive(&c.inbox)
				if err == .Closed {
					break
				}
				if err == .None {
					msg_opt: Maybe(^Msg) = msg // [itc: maybe-container]
					_, _ = pool_pkg.put(&c.pool, &msg_opt) // [itc: defer-put]
					count += 1
				}
			}
			sync.sema_post(&c.done)
		},
	)

	// N_PLAYERS players: each waits for a token, then sends it.
	// Only M_TOKENS tokens exist — excess players block in pool.get until one is returned.
	player_threads := make([]^thread.Thread, N_PLAYERS)
	defer delete(player_threads)
	for i in 0 ..< N_PLAYERS {
		player_threads[i] = thread.create_and_start_with_data(
			pc,
			proc(data: rawptr) {
				c := (^_Pool_Wait_Collector)(data) // [itc: thread-container]
				for _ in 0 ..< ROUNDS {
					msg, status := pool_pkg.get(&c.pool, .Pool_Only, -1)
					if status == .Closed {
						break
					}
					msg_opt: Maybe(^Msg) = msg
					if !mbox.send(&c.inbox, &msg_opt) {
						_, _ = pool_pkg.put(&c.pool, &msg_opt)
					}
				}
			},
		)
	}

	sync.sema_wait(&pc.done)

	// Join all threads before dispose.
	for i in 0 ..< N_PLAYERS {
		thread.join(player_threads[i])
		thread.destroy(player_threads[i])
	}
	thread.join(collector_thread)
	thread.destroy(collector_thread)

	return true
}
