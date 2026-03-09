# mbox Examples & Patterns

Because `mbox` is **intrusive**, it doesn't just store data; it manages the lifecycle of your objects. These examples demonstrate how to leverage that power for high-performance systems.

## 1. The Tagged Envelope Pattern (Polymorphism)
This is the standard "Actor" way. You define a header that identifies the message type, allowing a single mailbox to handle multiple different data structures.

```odin
package main

import "core:fmt"
import "core:mem"
import "mbox"

// 1. Define message types
Msg_Kind :: enum {
    Process_Image,
    Save_File,
    Shutdown,
}

// 2. The Envelope (The base structure)
Envelope :: struct {
    node: mbox.Node, // Embedded link
    kind: Msg_Kind,
}

// 3. Specific payloads
Image_Msg :: struct {
    using base: Envelope, // Promotion allows msg.kind access
    width:      int,
    height:     int,
    data_ptr:   rawptr,
}

main :: proc() {
    mb: mbox.Mailbox(mbox.Node)
    mbox.mailbox_init(&mb)

    // Sending a specific type
    img := new(Image_Msg)
    img.kind = .Process_Image
    img.width = 1920
    mbox.mailbox_send(&mb, &img.node)

    // Receiving and Re-hydrating
    node, _ := mbox.mailbox_receive(&mb, 0)
    
    // Cast to the base header first
    header := (^Envelope)(node)
    
    switch header.kind {
    case .Process_Image:
        // Recover the full structure
        full_msg := (^Image_Msg)(header)
        fmt.printf("Processing %dx%d image\n", full_msg.width, full_msg.height)
        free(full_msg)
    case .Save_File: // ...
    case .Shutdown:  // ...
    }
}