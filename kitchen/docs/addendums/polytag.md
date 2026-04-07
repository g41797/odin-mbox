# PolyTag — Type Identity

Every item in matryoshka carries a `tag` field.

`tag` is a `rawptr`.

It is not data.
It is identity.

---

## How identity works

Each type gets one private static variable.
That variable lives at file scope — forever.
Its address never changes.

The address of that variable is the tag.

Two items of the same type have the same address in their `tag` field.
Two items of different types have different addresses.

Comparison is a pointer comparison.
No strings. No integers. No registries.

---

## PolyTag

<!-- snippet: polynode.odin:16-19 -->
```odin
PolyTag :: struct {
	_: u8,
}
```

`PolyTag` is the type for tag instances.

The `_: u8` field matters.

In Odin, a zero-size struct has no size.
The compiler may place all zero-size globals at the same address.
That would break identity — every tag would be equal.

The `_: u8` padding byte gives each instance a unique address.

---

## PolyNode

<!-- snippet: polynode.odin:49-52 -->
```odin
PolyNode :: struct {
	using node: list.Node, // intrusive link — .prev, .next
	tag:        rawptr,    // type discriminator, must be != nil
}
```

`tag` must be set before the node is passed to any matryoshka API.

nil is always invalid.
An uninitialized node has `tag == nil`.
That is how you catch missing initialization — immediately.

---

## Pattern

Three steps for each type.

<!-- snippet: examples/block1/types.odin:14-30 -->
```odin
@(private)
event_tag: PolyTag = {}

@(private)
sensor_tag: PolyTag = {}

// EVENT_TAG is the unique tag for Event items.
EVENT_TAG: rawptr = &event_tag

// SENSOR_TAG is the unique tag for Sensor items.
SENSOR_TAG: rawptr = &sensor_tag

// event_is_it_you reports whether tag belongs to an Event.
event_is_it_you :: #force_inline proc(tag: rawptr) -> bool {return tag == EVENT_TAG}

// sensor_is_it_you reports whether tag belongs to a Sensor.
sensor_is_it_you :: #force_inline proc(tag: rawptr) -> bool {return tag == SENSOR_TAG}
```

### Step 1 — private instance

```odin
@(private)
event_tag: PolyTag = {}
```

File scope only.
Never stack. Never heap.

`@(private)` keeps it out of the package API.

### Step 2 — public variable

```odin
EVENT_TAG: rawptr = &event_tag
```

### Step 3 — helper function

```odin
event_is_it_you :: #force_inline proc(tag: rawptr) -> bool {return tag == EVENT_TAG}
```

The helper is optional.
Direct comparison `node.tag == EVENT_TAG` works too.
The helper makes dispatch code easier to read.

---

## Setting the tag

Set the tag once, at creation.

<!-- snippet: examples/block1/builder.odin:19-36 -->
```odin
// ctor allocates the correct type for tag and sets tag.
// Returns nil for unknown tags.
ctor :: proc(b: ^Builder, tag: rawptr) -> MayItem {
	if event_is_it_you(tag) {
		ev := new(Event, b.alloc)
		if ev == nil {
			return nil
		}
		ev^.tag = EVENT_TAG
		return MayItem(&ev.poly)
	} else if sensor_is_it_you(tag) {
		s := new(Sensor, b.alloc)
		if s == nil {
			return nil
		}
		s^.tag = SENSOR_TAG
		return MayItem(&s.poly)
	}
	return nil
}
```

Set the concrete tag — `EVENT_TAG`, not the parameter.

The parameter tells you which type to create.
The field records what the item is.

---

## Checking the tag

Always check before casting.

<!-- snippet: examples/block1/builder.odin:40-56 -->
```odin
// dtor frees internal resources and the node, then sets m^ = nil.
// Safe to call with m == nil or m^ == nil (no-op).
dtor :: proc(b: ^Builder, m: ^MayItem) {
	if m == nil {
		return
	}
	ptr, ok := m^.?
	if !ok {
		return
	}
	if event_is_it_you(ptr.tag) {
		free((^Event)(ptr), b.alloc)
	} else if sensor_is_it_you(ptr.tag) {
		free((^Sensor)(ptr), b.alloc)
	} else {
		panic("unknown tag")
	}
	m^ = nil
}
```

Always use `ptr, ok := m^.?` — the two-value form.
The single-value form panics on nil.

Panic on unknown tag.
Unknown tag on free is a programming error — not a runtime condition.

---

## Advanced — function pointer as tag

The tag is a `rawptr`.
It can hold the address of anything — including a procedure.

```odin
// The destructor IS the tag.
node.tag = cast(rawptr)my_dtor

// Check:
if node.tag == cast(rawptr)my_dtor {
    dtor := (proc(^PolyNode))(node.tag)
    dtor(node)
}
```

Use this when:

- The tag needs to carry behavior, not just identity.
- You want each type to bring its own destructor without a dispatch table.

The tag and the action are one thing.
No lookup. No switch. No table.

---

## Advanced — descriptor struct as tag

The tag can point to a struct that describes the type.

```odin
TypeDesc :: struct {
    name: string,
    size: int,
}

@(private)
chunk_desc := TypeDesc{name = "Chunk", size = size_of(Chunk)}

CHUNK_TAG: rawptr = &chunk_desc

// Access the descriptor:
if node.tag == CHUNK_TAG {
    desc := (^TypeDesc)(node.tag)
    fmt.println(desc.name, desc.size)
}
```

Use this when:

- You need metadata attached to a type (name, size, version).
- Multiple types share a common descriptor shape.
- You want to log or inspect items without knowing their concrete type.

The tag carries identity and data at the same time.
