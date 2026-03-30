// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

package matryoshka

// PoolHooks defines the user-provided callbacks for managing item lifecycle.
// Recycler is the implementation of these hooks.
PoolHooks :: struct {
	ctx:    rawptr, // User-provided context, passed back to hooks.
	ids:    [dynamic]int, // List of valid Item IDs this pool manages. All must be > 0.
	on_get: proc(ctx: rawptr, id: int, in_pool_count: int, m: ^MayItem), // Called to create or reinit.
	on_put: proc(ctx: rawptr, in_pool_count: int, m: ^MayItem), // Called to keep or dispose.
}

// Pool_Get_Mode determines the behavior of pool_get when no item is available.
Pool_Get_Mode :: enum {
	Available_Or_New, // Use stored item if available, otherwise call on_get to create.
	New_Only,         // Always call on_get with m^ == nil to create a fresh item.
	Available_Only,   // Use stored item only. If empty, return .Not_Available. on_get never called.
}

// Pool_Get_Result is the status code returned by pool acquisition operations.
Pool_Get_Result :: enum {
	Ok,             // Success: item returned in m^.
	Not_Available,  // Available_Only mode: no item was stored in the pool.
	Not_Created,    // on_get was called but did not return an item (m^ is nil).
	Closed,         // The pool is closed.
	Already_In_Use, // Entry contract violation: m^ was not nil on call.
}
