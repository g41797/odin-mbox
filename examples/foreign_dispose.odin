package examples

import pool_pkg "../pool"
import list "core:container/intrusive/list"
import "core:mem"
import "core:strings"

// ForeignMsg has a different allocator than the pool.
ForeignMsg :: struct {
	node:      list.Node,
	allocator: mem.Allocator,
	name:      string,
}

foreign_dispose :: proc(msg: ^Maybe(^ForeignMsg)) { // [itc: dispose-contract]
	if msg^ == nil { return }
	ptr := (msg^).?
	delete(ptr.name, ptr.allocator)
	free(ptr, ptr.allocator)
	msg^ = nil
}

// foreign_dispose_example demonstrates Idiom 6: foreign message with resources.
// It shows how pool.put detects an allocator mismatch and returns the pointer
// for manual disposal.
foreign_dispose_example :: proc() -> bool {
	p: pool_pkg.Pool(ForeignMsg)
	pool_pkg.init(&p, initial_msgs = 0, max_msgs = 10, reset = nil)
	defer pool_pkg.destroy(&p)

	// Create a message with a DIFFERENT allocator (e.g., a custom tracking allocator or just a different context).
	// For this test, we'll just use a fresh allocator instance if possible, or simulate by changing the field.
	
	msg := new(ForeignMsg)
	msg.allocator = context.temp_allocator // Different from p.allocator (context.allocator)
	msg.name = strings.clone("i am foreign", msg.allocator)
	
	m_opt: Maybe(^ForeignMsg) = msg // [itc: maybe-container]
	
	// Try to put it into the pool.
	ptr, accepted := pool_pkg.put(&p, &m_opt)
	
	// [itc: foreign-dispose]
	if !accepted && ptr != nil {
		// The pool rejected it because of allocator mismatch.
		// We MUST dispose it manually using its own allocator.
		p_opt: Maybe(^ForeignMsg) = ptr
		foreign_dispose(&p_opt)
		return true
	}

	return false
}
