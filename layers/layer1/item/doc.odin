/*
Package item — Layer 1: PolyNode + Maybe

Layer 1 is the foundation of itc.
It gives you two things:

  - PolyNode: the intrusive node embedded at offset 0 in every itc item.
  - Maybe(^PolyNode): the ownership handle used at every API boundary.

At this layer there is no pool, no mailbox, no threading.
You get the type vocabulary and the ownership contract.
That is enough to define your items, understand casting, and reason about ownership.

Move to Layer 2 when you need lifecycle hooks (factory, dispose).
Move to Layer 3 when you need a pool.
Move to Layer 5 when you need a mailbox.

You enter at the layer you need.
You stop when you have enough.
*/
package item
