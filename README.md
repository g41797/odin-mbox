![](kitchen/_logo/DancingMatryoshka.png)

# Matryoshka — Building Blocks for Boring Systems

One block at a time.
Stop when you have enough.

[![CI](https://github.com/g41797/matryoshka/actions/workflows/ci.yml/badge.svg)](https://github.com/g41797/matryoshka/actions/workflows/ci.yml)

---

## Why this exists

Most of my programming career, I built boring systems.

Boring means server-side.\
Long-running.\
Correct over clever.

In open source, I followed the same path:

- [syslogsidecar](https://github.com/g41797/syslogsidecar) in Go
- [tofu](https://github.com/g41797/tofu) in Zig

Matryoshka is the same expedition, in Odin.

It is building blocks for otofu — an Odin port of tofu.

Still joy of programming.

→ [What problems this solves](https://g41797.github.io/matryoshka/)

---

## What Matryoshka really is

- Matryoshka is a set of Russian dolls.
- Each doll works by itself.
- You open only what you need.
- You stop when you have enough.

## Your four dolls

| Doll | What you get | What it gives you |
| ---- | ------------ | ----------------- |
| 1    | PolyNode + MayItem        | ownership visible at every call     |
| 2    | + Mailbox                 | items move, memory stays still      |
| 3    | + Pool                    | allocate once, reuse always         |
| 4    | + Infrastructure as items | infrastructure follows the same rules |

**Rule:** open the next doll only when you feel pain.

---

## Doll 1 — PolyNode + MayItem

Two types.\
One rule.

```odin
PolyNode :: struct {
    using node: list.Node,
    id:         int,
}

MayItem :: ^Maybe(^PolyNode)
```

Every item embeds PolyNode first.

```odin
Chunk :: struct {
    using poly: PolyNode,
    data: [4096]byte,
}
```

Ownership:

```odin
m: MayItem
```

* `m^ == nil` → not yours
* `m^ != nil` → yours

You must:

* give it away
* or clean it up

---

## Doll 2 — Mailbox

Items move between threads.

* `mbox_send` → ownership leaves you
* `mbox_wait_receive` → ownership comes to you

You do not share memory.\
You move ownership.

---

## Doll 3 — Pool

Now you reuse items.

```odin
on_get:
- m^ == nil → create
- m^ != nil → reset

on_put:
- set m^ = nil → destroy
- leave m^ → keep
```

Start simple.\
Add limits later.

---

## Doll 4 — Infrastructure as items

Mailbox is an item.\
Pool is an item.

* you can send them
* you can receive them
* you own them or not

Same rules.

---

## This notation looks strange. Good.

> *Here is Edward Bear, coming downstairs now, bump, bump, bump, on the back of his
> head, behind Christopher Robin. It is, as far as he knows, the only way of coming
> downstairs, but sometimes he feels that there really is another way, if only he
> could stop bumping for a moment and think of it.*
>
> — A.A. Milne, *Winnie-the-Pooh*

I never read the Winnie-the-Pooh book. I found this at the very opening of Steve McConnell's *Software Project Survival Guide*, and it stayed with me.

`^MayItem` — a pointer to an optional pointer — is not normal-looking code.

The key property is **visibility** — ownership state is explicit at every call site.\
The alternatives lose that:

| Approach | What you lose |
|---|---|
| `^^PolyNode` | No convention. `m^ == nil` could mean anything. Ownership invisible. |
| `rawptr + bool` | You manage the flag. Forget it once and you have a bug. Ownership invisible. |

`^MayItem` makes one rule visible at every call site:

- `m^ != nil` — you have it. Transfer, recycle, or free.
- `m^ == nil` — you don't. The API took it, or there was nothing.
- `m == nil` — nil handle. You passed garbage. API returns error.

It will not look normal. It will look consistent.

---

## The same idea with threads (Mailbox)

Doll 2 in practice.\
The ownership rule does not change at thread boundaries.

```odin
import . "path/to/matryoshka"  // dot-import — all names available without prefix
import "core:thread"
import "core:fmt"

worker :: proc(arg: rawptr) {
    mb := (Mailbox)(arg)

    m: MayItem

    if mbox_wait_receive(mb, &m) != .Ok {
        return
    }

    ptr, ok := m.?
    if !ok { return }

    chunk := (^Chunk)(ptr)
    fmt.println(chunk.value)

    free(chunk)
    m^ = nil
}

main :: proc() {
    mb := mbox_new(context.allocator)
    defer {
        m: MayItem = (^PolyNode)(mb)
        mbox_close(mb)
        matryoshka_dispose(&m)
    }

    t: thread.Thread
    thread.create(&t, worker, mb)

    c := new(Chunk)
    c.id = 1
    c.value = 42

    m: MayItem = (^PolyNode)(c)

    if mbox_send(mb, &m) != .Ok {
        free(c)
        return
    }

    thread.join(t)
}
```

---

## One vocabulary everywhere

* get
* fill
* send
* receive
* put back

---

## Takeaway

Threads are hard.\
Matryoshka does not change that.\
It tries to make the bumping less blind.

---

## Credits

Not serious. But not random either.

- "*?*M" — opened my eyes. Predecessor of `^Maybe(^PolyNode)`.
- [mailbox](https://github.com/g41797/mailbox) — this project started as a port of mailbox to Odin.
- [tofu](https://github.com/g41797/tofu) — where these ideas began.

---

Don't shoot the
AI image generator; he's doing his best! 🤖🎨
