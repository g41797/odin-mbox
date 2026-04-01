# Dialogs

These are real conversations between the Author and AI.

---

## `^MayItem` vs `^^PolyNode`

**The Question:** I designed Matryoshka to use `^MayItem`, but why the extra layer? Can't I just use `^^PolyNode`? It's just two pointers. It's simpler. Why the `Maybe`?

**The Reality:** They are not the same. `^^PolyNode` is just a pointer to a pointer. It gives you two nil states:

- `m == nil` — the handle itself is nil.
- `*m == nil` — the inner pointer is null.

But it has no built-in "is this valid?" check.

`Maybe(T)` in Odin is a tagged union. It adds the `.?` operator and a clear meaning to the state:

| Expression | `^MayItem` | `^^PolyNode` |
|------------|---------------------|--------------|
| `m == nil` | nil handle — a bug | same |
| `m^ == nil` | you do NOT own it | same (but why? who knows.) |
| `m^ != nil` | you own it | same |
| ptr, ok := m^.? | safe unwrap | not possible |
| m^ = nil after send | ownership transferred | could mean anything |

The big deal is the transfer signal. With `^^PolyNode`, setting `*m = nil` just nulls a pointer. It doesn't tell the caller *why*. Did it transfer? Did it fail? Was it never there?

With `^MayItem`, `m^ = nil` is the rule:
- API sets it on success → "I took it, it's mine now."
- API leaves it on failure → "I didn't take it, still yours."
- You check it to know if you need to free it.

This makes deferred cleanup safe.
A cleanup function sees `m^ == nil` and skips the free.
With `^^PolyNode`, you'd have to track that by hand.

**Simpler view:**

```
m == nil      → nil handle        → bug, returns .Invalid
m^ == nil     → nothing inside    → you don't own it
m^ != nil     → item inside       → you own it
```

`^^PolyNode` only has two levels.
You lose the difference between "I gave it away" and "I never had one."

**The Result:** `Maybe` carries the ownership bit for free. And `m^.?` is the safe way to read it.

It puts the rules into the type:
- nil = not yours.
- non-nil = yours.
- `m^.?` = the safe way to check and grab the item in one go.

---

## The `.?` operator

**The Problem:** Two forms of `.?`. Which one is the right one?

**The Rule:** Always use the two-value form.

```odin
ptr, ok := m^.?
```

`ok` is `false` when the inner value is absent.
If `m` itself is nil, `m^` panics before `.?` is reached — that is a programming error.

The single-value form is a trap:

```odin
ptr := m.?
```

It returns the value directly but **panics at runtime if m is nil.** In a multi-threaded app, this is a crash.

| Form | The Rule |
|------|----------|
| `ptr, ok := m.?` | use this — check and extract in one step |
| `ptr := m.?` | don't use this — it will crash your app |

---

> ***Author's note.*** *This dialogue never was. I never was fully sure about `^MayItem`. Still not sure. But it's right.*

---

## The manual way (with `^^PolyNode`)

> *I wanted to skip this. I was convinced to keep it. Here is why `Maybe` wins.*

If you use `^^PolyNode`, you have to add a flag by hand to get the same safety.

It would look like this:

```odin
// Manual equivalent of MayItem
Owned :: struct {
    ptr:   ^PolyNode,
    valid: bool,       // the flag Maybe gives you for free
}
```

Every single time you want to use it:

```odin
m: Owned
if m.valid {
    ptr := m.ptr
    // use ptr
}
```

And every time you hand it over:

```odin
m.ptr   = nil
m.valid = false
```

You'll forget. Or you'll read `m.ptr` while `m.valid` is false.
`Maybe` and the `.?` operator stop you from doing that.

**Summary:**

| | `^MayItem` | `^^PolyNode` + manual flag |
|---|---|---|
| ownership bit | built-in | you maintain it by hand |
| safe extract | `m^.?` — one step | `if valid { use ptr }` — error-prone |
| transfer | `m^ = nil` | two steps, easy to forget |
| compiler help | yes | no |
| memory | same cost | same cost, more noise |
