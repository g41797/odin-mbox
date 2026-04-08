// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

/*
Building Blocks for Modular Monoliths in Odin.

Block 1 — PolyNode + MayItem: item and ownership.

Block 2 — Mailbox: move items between threads.

Block 3 — Pool: reuse items.

Block 4 — Infrastructure as items: mailboxes and pools are items too.

Open the next block only when you need it.

[[Documentation;https://g41797.github.io/matryoshka/]]
*/
package matryoshka
