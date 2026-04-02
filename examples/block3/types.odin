package examples_block3

import matryoshka "../.."
import ex1 "../block1"
import ex2 "../block2"

// Aliases for matryoshka core types.
PolyNode :: matryoshka.PolyNode
MayItem   :: matryoshka.MayItem
Mailbox   :: matryoshka.Mailbox
Pool      :: matryoshka.Pool
PoolHooks :: matryoshka.PoolHooks

// Aliases for Layer 1 items and builder.
ItemId  :: ex1.ItemId
Event   :: ex1.Event
Sensor  :: ex1.Sensor
Builder :: ex1.Builder

make_builder :: ex1.make_builder
ctor         :: ex1.ctor
dtor         :: ex1.dtor

// Aliases for Layer 2 Master.
Master     :: ex2.Master
newMaster  :: ex2.newMaster
freeMaster :: ex2.freeMaster
