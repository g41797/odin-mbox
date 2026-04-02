package examples_block2

import matryoshka "../.."
import ex1 "../block1"

// Aliases for matryoshka core types.
PolyNode :: matryoshka.PolyNode
MayItem   :: matryoshka.MayItem
Mailbox   :: matryoshka.Mailbox

// Aliases for Layer 1 items and builder.
ItemId  :: ex1.ItemId
Event   :: ex1.Event
Sensor  :: ex1.Sensor
Builder :: ex1.Builder

make_builder :: ex1.make_builder
ctor         :: ex1.ctor
dtor         :: ex1.dtor

// MAILBOX_ID is used for ID validation tests.
MAILBOX_ID :: matryoshka.MAILBOX_ID
