// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

package try_mbox

import "base:intrinsics"
import list "core:container/intrusive/list"
import "core:sync"
import "core:testing"
import "core:thread"

N_EP_THREADS :: 10
N_EP_MSGS    :: 1000
N_EP_TOTAL   :: N_EP_THREADS * N_EP_MSGS

N_CS_THREADS :: 5
N_CS_SENDS   :: 200

// _Slab_Ctx holds state for one producer thread in test_concurrent_producers.
_Slab_Ctx :: struct {
	m:     ^Mbox(_TM),
	slab:  []_TM,
	start: ^sync.Sema,
}

// _Send_Ctx holds state for one sender thread in test_close_during_send_race.
_Send_Ctx :: struct {
	m:    ^Mbox(_TM),
	slab: []_TM,
	sent: int, // updated atomically
}

@(test)
test_concurrent_producers :: proc(t: ^testing.T) {
	m := init(_TM)
	defer destroy(m)

	// Allocate message slabs — one per thread so each thread owns its messages.
	slabs := make([][]_TM, N_EP_THREADS)
	defer delete(slabs)
	for i in 0 ..< N_EP_THREADS {
		slabs[i] = make([]_TM, N_EP_MSGS)
		for j in 0 ..< N_EP_MSGS {
			slabs[i][j] = _TM{data = i * N_EP_MSGS + j}
		}
	}
	defer for i in 0 ..< N_EP_THREADS {
		delete(slabs[i])
	}

	start: sync.Sema

	ctxs := make([]_Slab_Ctx, N_EP_THREADS)
	defer delete(ctxs)
	threads := make([]^thread.Thread, N_EP_THREADS)
	defer delete(threads)

	for i in 0 ..< N_EP_THREADS {
		ctxs[i] = _Slab_Ctx{m = m, slab = slabs[i], start = &start}
		threads[i] = thread.create_and_start_with_data(&ctxs[i], proc(data: rawptr) {
			c := (^_Slab_Ctx)(data)
			sync.sema_wait(c.start)
			for i in 0 ..< len(c.slab) {
				send(c.m, &c.slab[i])
			}
		})
	}

	// Release all threads simultaneously.
	for _ in 0 ..< N_EP_THREADS {
		sync.sema_post(&start)
	}

	received := 0
	for received < N_EP_TOTAL {
		_, ok := try_receive(m)
		if ok {
			received += 1
		}
	}

	for i in 0 ..< N_EP_THREADS {
		thread.join(threads[i])
		thread.destroy(threads[i])
	}

	testing.expect(t, received == N_EP_TOTAL, "should receive all 10,000 messages")
	testing.expect(t, length(m) == 0, "queue should be empty after draining")
}

@(test)
test_close_during_send_race :: proc(t: ^testing.T) {
	m := init(_TM)
	defer destroy(m)

	// Allocate message slabs.
	slabs := make([][]_TM, N_CS_THREADS)
	defer delete(slabs)
	for i in 0 ..< N_CS_THREADS {
		slabs[i] = make([]_TM, N_CS_SENDS)
	}
	defer for i in 0 ..< N_CS_THREADS {
		delete(slabs[i])
	}

	ctxs := make([]_Send_Ctx, N_CS_THREADS)
	defer delete(ctxs)
	threads := make([]^thread.Thread, N_CS_THREADS)
	defer delete(threads)

	for i in 0 ..< N_CS_THREADS {
		ctxs[i] = _Send_Ctx{m = m, slab = slabs[i]}
		threads[i] = thread.create_and_start_with_data(&ctxs[i], proc(data: rawptr) {
			c := (^_Send_Ctx)(data)
			for i in 0 ..< len(c.slab) {
				ok := send(c.m, &c.slab[i])
				if ok {
					intrinsics.atomic_add(&c.sent, 1)
				}
			}
		})
	}

	// Close while senders may still be running.
	remaining, was_open := close(m)
	testing.expect(t, was_open, "first close should return was_open=true")

	// Drain the remaining list from close.
	drained := 0
	for {
		node := list.pop_front(&remaining)
		if node == nil {break}
		drained += 1
	}

	for i in 0 ..< N_CS_THREADS {
		thread.join(threads[i])
		thread.destroy(threads[i])
	}

	// After close, send must return false.
	dummy := _TM{data = -1}
	ok := send(m, &dummy)
	testing.expect(t, !ok, "send after close should return false")

	// Accepted count must not exceed total attempted.
	total_sent := 0
	for i in 0 ..< N_CS_THREADS {
		total_sent += intrinsics.atomic_load(&ctxs[i].sent)
	}
	testing.expect(
		t,
		total_sent <= N_CS_THREADS * N_CS_SENDS,
		"total sent should not exceed total attempted",
	)
	// Drained from close remaining list is a subset of total sent.
	testing.expect(t, drained <= total_sent, "drained should not exceed total sent")
}
