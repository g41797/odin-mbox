package examples

import mbox "../mbox"
import list "core:container/intrusive/list"
import "core:sync"
import "core:thread"

// Dice is the object passed between players.
// One allocation. Never replaced during the game.
Dice :: struct {
	node:  list.Node,
	rolls: int,
}

// Player represents a thread at the table.
Player :: struct {
	id:      int,
	in_mb:   ^mbox.Mailbox(Dice),
	next_mb: ^mbox.Mailbox(Dice),
	total:   int,
	done:    ^sync.Sema,
}

@(private)
_Endless_Game_Master :: struct {
	mboxes: [4]mbox.Mailbox(Dice),
	players: [4]Player,
	threads: [4]^thread.Thread,
	done: sync.Sema,
}

@(private)
_endless_game_dispose :: proc(m: ^Maybe(^_Endless_Game_Master)) { // [itc: dispose-contract]
	mp, ok := m.?
	if !ok || mp == nil {return}
	
	for i in 0 ..< 4 {
		remaining, _ := mbox.close(&mp.mboxes[i])
		for node := list.pop_front(&remaining); node != nil; node = list.pop_front(&remaining) {
			dice := (^Dice)(node)
			dice_opt: Maybe(^Dice) = dice
			// Simple dice free
			if mp := dice_opt.?; mp != nil { free(mp) }
		}
	}
	free(mp)
	m^ = nil
}

// endless_game_example shows 4 threads passing a single heap-allocated message in a circle.
//
// Player 1 → Player 2 → Player 3 → Player 4 → Player 1
//
// After 10,000 rolls the game is won.
// The dice is allocated once and freed after all threads exit.
endless_game_example :: proc() -> bool {
	ROLLS :: 10_000
	PLAYERS :: 4

	m := new(_Endless_Game_Master) // [itc: heap-master]
	m_opt: Maybe(^_Endless_Game_Master) = m
	defer _endless_game_dispose(&m_opt) // [itc: defer-dispose]

	for i in 0 ..< PLAYERS {
		m.players[i] = {
			id      = i + 1,
			in_mb   = &m.mboxes[i],
			next_mb = &m.mboxes[(i + 1) % PLAYERS],
			total   = ROLLS,
			done    = &m.done,
		}
	}

	for i in 0 ..< PLAYERS {
		m.threads[i] = thread.create_and_start_with_poly_data(&m.players[i], proc(p: ^Player) { // [itc: thread-container]
			for {
				dice, err := mbox.wait_receive(p.in_mb)
				if err != .None {
					break
				}

				// Player 1 counts each full round.
				if p.id == 1 {
					dice.rolls += 1
				}

				game_done := dice.rolls >= p.total
				dice_opt: Maybe(^Dice) = dice // [itc: maybe-container]
				ok := mbox.send(p.next_mb, &dice_opt)
				if game_done {
					sync.sema_post(p.done)
					return
				}
				if !ok {
					return
				}
			}
		})
	}

	// Allocate the dice on the heap. One object, lives until free() below.
	// Keep the_dice_ptr for post-game inspection — the_dice is nil after send.
	the_dice_ptr := new(Dice)
	the_dice: Maybe(^Dice) = the_dice_ptr // [itc: maybe-container]
	if !mbox.send(&m.mboxes[0], &the_dice) {
		free(the_dice_ptr)
		return false
	}

	sync.sema_wait(&m.done)

	// Shutdown Handled by _endless_game_dispose

	for i in 0 ..< PLAYERS {
		thread.join(m.threads[i])
		thread.destroy(m.threads[i])
	}

	// All threads are done. Check the result.
	result := the_dice_ptr.rolls >= ROLLS
	// Dice might be in a mailbox or held by a thread. 
	// The dispose proc handles the final drain and free.
	return result
}
