# Odin doc comment formats

Formats supported in `/* ... */` package and proc doc comments.
Tested against `pkg.odin-lang.org` / `odin doc` output.

---

## Inline formats

| Format | Syntax | Result |
|--------|--------|--------|
| Bold | `**text**` | **text** |
| Italic | `*text*` | *text* |
| Inline code | `` `code` `` | `code` |
| Link | `[[label; url]]` | clickable label |

---

## Block formats

### Paragraph

Blank line separates paragraphs.

### Code block

Tab-indented lines. No fences.

```
	my_var := 42
	fmt.println(my_var)
```

### Section header

`**Section Name**:` on its own line, followed by a blank line.
Used as a visual section break — not a real heading element.

```
**Threading**:

Each thread may have one event loop.
```

### Example block

`Example:` keyword on its own line, then tab-indented code.

```
Example:
	mb: mbox.Mailbox(My_Msg)
	mbox_send(&mb, &msg)
```

### Link

`[[label; url]]` syntax. Spaces around `;` are optional.

```
It uses the [[Vyukov MPSC algorithm; https://int08h.com/post/ode-to-a-vyukov-queue/]].

More examples at [[ examples/nbio ; https://github.com/odin-lang/examples/tree/master/nbio ]].
```

---

## What does NOT work

- `# Heading` — not rendered as heading
- `[text](url)` — Markdown link syntax — shown as-is
- Plain URL — not auto-linked
- `- item` bullet lists — no special rendering

---

## embed_readme — CommonMark, not GFM

The `embed_readme` field in `odin-doc.json` renders the target file with
`libcmark` (standard CommonMark). It is a separate path from `.odin` doc comments.

What works in embedded README:

- Headers: `#`, `##`, etc.
- Bold, italic, inline code
- Links: `[text](url)` — standard Markdown syntax
- Fenced code blocks (` ``` `)
- Bullet lists, blockquotes

What does NOT work (GFM-only):

- Tables `| col |` — no rendering, shown as-is
- Task lists `- [ ]`
- Strikethrough `~~text~~`
- Autolinks

This is why `docs/README.md` exists as a separate CommonMark-safe version of
the root `README.md`. The root README uses GFM tables — do not embed it directly.

When adding content to `docs/README.md`: no tables, no GFM-only syntax.

---

## TODO: README validation script

Need a script to validate that `docs/README.md` (and any other README embedded
via `embed_readme`) contains no GFM-only constructs before pushing.

Check for at minimum:

- Table rows: lines starting with `|`
- Strikethrough: `~~`
- Task list items: `- [ ]` or `- [x]`

Location: `docs/check_readme.sh` or similar.
