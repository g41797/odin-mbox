// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// try_mbox: MPSC queue based mailbox for event loops and worker loops.
//
// The consumer calls try_receive — no blocking, no mutex on the receive path.
// Multiple producers call send concurrently. One consumer calls try_receive.
//
// Not copyable after init. Use init to allocate on the heap.
// WakeUper is optional. Zero value = no notification on send.
//
// Stall: try_receive may return (nil, false) while length > 0.
// This is a property of the Vyukov MPSC queue. Retry on the next call.
// Call close only after all senders have stopped.
package try_mbox
