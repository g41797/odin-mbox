/*
loop_mbox: MPSC queue based mailbox for event loops and worker loops.

The consumer calls try_receive_batch — no blocking, no mutex on the receive path.
Multiple producers call send concurrently. One consumer calls try_receive_batch.

Not copyable after init. Use init to allocate on the heap.
WakeUper is optional. Zero value = no notification on send.

Stall: try_receive_batch may return an empty list while length > 0.
This is a property of the Vyukov MPSC queue. Retry on the next call.

Correct drain pattern:
  batch := try_receive_batch(m)
  for node := list.pop_front(&batch); node != nil; node = list.pop_front(&batch) {
      msg := (^T)(node)  // valid only when node is the first field of T (offset 0)
      // handle msg — free or return to pool
  }

Thread model:
  init               : any thread
  send               : any thread (multiple producers, MPSC safe)
  try_receive_batch  : consumer thread only — MPSC single-consumer rule
  close              : consumer thread only — drains with mpsc.pop (single-consumer);
                       must be called after all senders have stopped (threads joined)
  destroy            : any thread after close (no concurrent access remains)

Idiom reference: design/idioms.md
*/

package loop_mbox
