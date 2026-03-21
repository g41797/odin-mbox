/*
Package examples — Layer 1 examples: PolyNode + Maybe

These examples show how to use Layer 1 types in practice:

  - produce_consume: allocate mixed-type items, push to an intrusive list,
    pop and dispatch on id, then free.

  - ownership: use Maybe(^item.PolyNode) as an ownership handle at the
    push/pop boundary.

No pool, no mailbox, no threads — just the Layer 1 vocabulary.
*/
package examples
