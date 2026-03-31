---

## The problem

Multiple threads touching the same data at the same time — dangerous.
Not because threads are evil.
Because **two hands on the same thing** at the same time: who frees it? who modifies it?

The answer isn't locks.
Locks are "two hands, careful coordination."
**The answer is: one hand at a time. Always.**

Move. Don't share.

---

## The new question

When you move something — send it, put it, throw it through —
**did it go? or is it still here?**

You need to know. Right now. Without asking anyone.

---

## The portal

An exchange point. A portal.
You put the item in.

Two outcomes:

- **Went through.** The other side has it. **Your hand: empty.**
- **Portal closed.** It never went through. **Your hand: still full.**

You don't ask. You look at your hand.
**You need one check. Empty or gone. That is all.**

---

## The illusionist difference

Normal magic: item disappears. You don't know where. You can't check.

This magic: item disappears **and your hand visibly empties.**
The mechanics betray the trick.
You always know.

**`^Maybe(^T)` gives you that check.** That is what a plain pointer cannot.
The portal reaches into your hand and empties it. You see it happen.

---

## Two portals. One hand. One rule.

**Mailbox — portal to another thread:**

- Send success → hand empties. Item is on the other side.
- Send fail (closed) → hand stays full. Still yours.
- Receive → hand fills. Item arrived.

**Pool — portal to a depot:**

- Put success → hand empties. Item is stored.
- Put fail (closed) → hand stays full. Still yours.
- Get success → hand fills. Item came from the depot.
- Get fail → hand stays empty. Nothing arrived.

---

## Same hand. Two portals. One rule:

> Full = yours. Empty = went through, or nothing came.

No exceptions.

---

*`^Maybe(^T)` — Maybe finally has a job only it can do.*

---
