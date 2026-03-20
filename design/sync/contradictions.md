---
  Contradictions and Inconsistencies Found

  C1 — mbox_close return value: direct contradiction

  new-itc.md:145
  mbox_close :: proc(mb: ^Mailbox)
  No return value. Effects say "receive continues until empty."

  new-idioms.md:283 and poly_mailbox_proposal.md:359
  ▎ "mbox.close atomically empties the queue and returns the head of the remaining list as ^PolyNode."
  head := mbox.close(&mb)  // drain loop uses return value

  Two completely different behaviors. Either close returns the remaining list, or it does not. The drain loop pattern depends on it returning one.

  ---
  C2 — "Pool manages lifecycle" contradicts "Pool is mechanical only"

  new-itc.md:158 section header:
  ▎ # 3. Pool API (lifecycle + reuse)

  new-itc.md:354 one-liner:
  ▎ "Mailbox moves ownership, Pool manages lifecycle, Maybe(^T) enforces correctness."

  Canonical rule: Pool is mechanical only. FlowPolicy manages lifecycle decisions. The section title and the one-liner both contradict this.

  ---
  C3 — pool_put foreign item: id validation order undefined and inconsistent

  new-pool-design-ga-v2.md:64–68 pool_put algorithm:
  1. Retrieves in_pool_count for the node's id.
  2. Calls policy.on_put(...) outside of internal locks.
  3. If m^ is still valid, pushes to free-list and sets m^ = nil.
  No id validation step. on_put is always called.

  poly_mailbox_proposal.md:191–194:
  ▎ "Validates the item's id. If the id is unrecognized (foreign item), the pool does not accept it. If the item is not foreign, the pool calls policy.on_put..."

  id validation happens BEFORE on_put. on_put is NOT called for foreign items.

  These are opposite behaviors. The canonical pool_put algorithm does not mention id validation at all.

  ---
  C4 — on_put comment "To reject" survives in two files

  new-itc.md:192 and poly_mailbox_proposal.md:133:
  // Called during pool_put.
  // To reject, hook disposes and sets m^ = nil.

  new-pool-design-ga-v2.md:40–42 (correctly fixed):
  // Called during pool_put.
  // If hook sets m^ = nil, the Pool forgets the node (consumed).
  // If m^ != nil, the Pool adds it to the free-list.

  "To reject" is the old anti-canonical language. Two files still have it; one was fixed.

  ---
  C5 — API naming inconsistency throughout: dot notation vs underscore

  new-itc.md and new-pool-design-ga-v2.md define APIs with underscores:
  pool_init, pool_get, pool_put, pool_destroy, mbox_init, mbox_send, mbox_wait_receive

  new-idioms.md uses dot notation in most places:
  - Line 272: pool_get
  - Line 394: pool_get
  - Line 530, 720, 831: pool_init
  - Line 832: pool_destroy
  - Line 152, 156: mbox_send
  - Line 825–826: mbox_init, mbox_destroy
  - Line 768: pool_get
  - Line 123: pool_get

  poly_mailbox_proposal.md:
  - Line 175: pool_get
  - Line 155: pool_init

  Same APIs named two different ways across documents.

  ---
  C6 — Wrong hook name: "reset" instead of on_get

  new-idioms.md:93:
  hooks dispatch — factory/reset/dispose called with ctx, routed by id

  Every other location in all four files calls it on_get, not reset. reset does not exist.

  ---
  C7 — dispose-optional says use defer pool_put for permanent disposal

  new-idioms.md:492–494:
  ▎ "flow_dispose is never called automatically by mailbox. Only the caller does it.
  ▎ Fix: Use defer pool_put(&p, &m) (defer-put) or manual drain loops when an item leaves the system permanently."

  pool_put recycles into the free-list — it does NOT permanently dispose. For permanent disposal, flow_dispose must be called. This is the wrong tool for the stated problem.

  ---
  C8 — dispose hook table entry is circular

  new-idioms.md:652:
  | dispose | On pool_destroy or flow_dispose | ...

  flow_dispose IS the dispose hook. Saying the hook is called "on flow_dispose" is circular. The hook is called on pool_destroy. The entry should not reference flow_dispose as
   a trigger for itself.

  ---
  C9 — Missing section 4 in new-itc.md

  Document jumps from # 3. Pool API (line 158) directly to # 5. Unified ownership rules (line 261). Section 4 does not exist. The numbering gap is either a missing section or
  a labeling error.

  ---
  C10 — new-pool-design-ga-v2.md:97 says "manually dispose" without naming flow_dispose

  ▎ "the hook should manually dispose and set m^ = nil to trim the pool."

  All other documents say flow_dispose(ctx, alloc, m) explicitly. This is vague and inconsistent with the convention established elsewhere.

  ---
  C11 — Two near-identical quick reference entries in new-idioms.md

  Lines 373–375:

  ┌───────────────┬────────────────────────────────────────────────────────────┐
  │      Tag      │                        Description                         │
  ├───────────────┼────────────────────────────────────────────────────────────┤
  │ defer-put     │ "Use defer pool_put(&p, &m) as a scope-exit safety net."   │
  ├───────────────┼────────────────────────────────────────────────────────────┤
  │ defer-dispose │ "Use defer pool_put(&p, &m) so cleanup runs in all paths." │
  └───────────────┴────────────────────────────────────────────────────────────┘

  Both entries describe the same operation (defer pool_put) with different tag names. One is a duplicate of the other.

  ---
  C12 — poly_mailbox_proposal.md:330 uses vague "dispose runs"

  Ownership rules table:
  | after send failure | m^ unchanged — caller still holds, dispose runs |

  "dispose runs" — nothing runs automatically. With defer pool_put, pool_put runs. "dispose" is undefined in this context and ambiguous.

  ---
  C13 — flow_dispose defined twice in new-idioms.md

  Identical definition appears at line 418–431 (dispose-contract section) and again at line 683–696 (hook examples section). Redundant duplicate.

  ---
  C14 — Dual defer pool_put in the same m variable in new-itc.md

  new-itc.md:298 registers defer pool_put(&pool, &m) for the sender side.
  new-itc.md:312–313 then calls mbox_wait_receive(&mb, &m) on the SAME m variable, and registers a second defer pool_put(&pool, &m).

  Both defers operate on the same m. The comment acknowledges sender and receiver "would be different" in a real scenario — making this example actively misleading about
  dual-defer behavior.

  ---
  Summary table

  ┌─────┬──────────┬───────────────────────────────────────────────────────┬───────────────────────────────────────────────────────────┐
  │  #  │ Severity │                         Files                         │                           Issue                           │
  ├─────┼──────────┼───────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────┤
  │ C1  │ Critical │ new-itc.md vs new-idioms.md, poly_mailbox_proposal.md │ mbox_close return type contradicts across docs            │
  ├─────┼──────────┼───────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────┤
  │ C2  │ Critical │ new-itc.md                                            │ "Pool manages lifecycle" contradicts mechanical-only rule │
  ├─────┼──────────┼───────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────┤
  │ C3  │ Critical │ new-pool-design-ga-v2.md vs poly_mailbox_proposal.md  │ pool_put id validation order contradicts                  │
  ├─────┼──────────┼───────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────┤
  │ C4  │ High     │ new-itc.md:192, poly_mailbox_proposal.md:133          │ "To reject" language survives in on_put comment           │
  ├─────┼──────────┼───────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────┤
  │ C5  │ High     │ new-idioms.md, poly_mailbox_proposal.md               │ API naming: dot notation vs underscore throughout         │
  ├─────┼──────────┼───────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────┤
  │ C6  │ High     │ new-idioms.md:93                                      │ Hook named "reset" — does not exist                       │
  ├─────┼──────────┼───────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────┤
  │ C7  │ Medium   │ new-idioms.md:492–494                                 │ defer pool_put recommended for permanent disposal         │
  ├─────┼──────────┼───────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────┤
  │ C8  │ Medium   │ new-idioms.md:652                                     │ dispose hook table entry is circular                      │
  ├─────┼──────────┼───────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────┤
  │ C9  │ Medium   │ new-itc.md                                            │ Missing section 4 (numbering jumps 3→5)                   │
  ├─────┼──────────┼───────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────┤
  │ C10 │ Low      │ new-pool-design-ga-v2.md:97                           │ "manually dispose" unnamed — should say flow_dispose      │
  ├─────┼──────────┼───────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────┤
  │ C11 │ Low      │ new-idioms.md:373–375                                 │ defer-put and defer-dispose tags are duplicates           │
  ├─────┼──────────┼───────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────┤
  │ C12 │ Low      │ poly_mailbox_proposal.md:330                          │ "dispose runs" is undefined/vague                         │
  ├─────┼──────────┼───────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────┤
  │ C13 │ Low      │ new-idioms.md:418,683                                 │ flow_dispose defined twice identically                    │
  ├─────┼──────────┼───────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────┤
  │ C14 │ Low      │ new-itc.md:298,313                                    │ Misleading dual defer pool_put on same variable           │
  └─────┴──────────┴───────────────────────────────────────────────────────┴───────────────────────────────────────────────────────────┘
