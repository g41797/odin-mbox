package examples

import mbox "../mbox"
import "core:thread"
import "core:time"

@(private)
_Interrupt_Master :: struct {
	mb: mbox.Mailbox(Msg),
}

@(private)
_interrupt_dispose :: proc(m: ^Maybe(^_Interrupt_Master)) { // [itc: dispose-contract]
	mp, ok := m.?
	if !ok || mp == nil { return }
	mbox.close(&mp.mb)
	free(mp)
	m^ = nil
}

// interrupt_example shows how to wake up a waiting thread without sending a message.
interrupt_example :: proc() -> bool {
	m := new(_Interrupt_Master) // [itc: heap-master]
	m_opt: Maybe(^_Interrupt_Master) = m
	defer _interrupt_dispose(&m_opt) // [itc: defer-dispose]

	err_result: mbox.Mailbox_Error

	// Start a thread that will wait forever.
	t := thread.create_and_start_with_poly_data2(&m.mb, &err_result, proc(mb: ^mbox.Mailbox(Msg), res: ^mbox.Mailbox_Error) {
		_, err := mbox.wait_receive(mb)
		res^ = err
	})

	// Give it a moment to start waiting.
	time.sleep(10 * time.Millisecond)

	// Wake it up!
	mbox.interrupt(&m.mb)

	thread.join(t)
	thread.destroy(t)

	// It should have been interrupted.
	return err_result == .Interrupted
}
