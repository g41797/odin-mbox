/** Generated with odin version dev-2026-03 (vendor "odin") Linux_amd64 @ 2026-03-23 05:43:21.877463085 +0000 UTC */
var odin_pkg_data = {
"packages": {
	"loop_mbox": {
		"name": "loop_mbox",
		"collection": "matryoshka",
		"path": "/matryoshka/loop_mbox",
		"entities": [
			{"kind": "t", "name": "Mbox"},
			{"kind": "p", "name": "close"},
			{"kind": "p", "name": "destroy"},
			{"kind": "p", "name": "init"},
			{"kind": "p", "name": "length"},
			{"kind": "p", "name": "send"},
			{"kind": "p", "name": "try_receive_batch"}
		]
	},
	"mbox": {
		"name": "mbox",
		"collection": "matryoshka",
		"path": "/matryoshka/mbox",
		"entities": [
			{"kind": "t", "name": "Mailbox"},
			{"kind": "t", "name": "Mailbox_Error"},
			{"kind": "p", "name": "close"},
			{"kind": "p", "name": "interrupt"},
			{"kind": "p", "name": "send"},
			{"kind": "p", "name": "wait_receive"}
		]
	},
	"examples": {
		"name": "examples",
		"collection": "matryoshka",
		"path": "/matryoshka/examples",
		"entities": [
			{"kind": "c", "name": "DISPOSABLE_ITM_HOOKS"},
			{"kind": "t", "name": "Dice"},
			{"kind": "t", "name": "DisposableItm"},
			{"kind": "t", "name": "Echo_Msg"},
			{"kind": "t", "name": "ForeignItm"},
			{"kind": "t", "name": "Itm"},
			{"kind": "c", "name": "M_TOKENS"},
			{"kind": "t", "name": "Master"},
			{"kind": "c", "name": "N_PLAYERS"},
			{"kind": "t", "name": "Player"},
			{"kind": "c", "name": "ROUNDS"},
			{"kind": "p", "name": "close_example"},
			{"kind": "p", "name": "create_disposable_master"},
			{"kind": "p", "name": "create_echo_server"},
			{"kind": "p", "name": "create_endless_game_master"},
			{"kind": "p", "name": "create_interrupt_master"},
			{"kind": "p", "name": "create_master"},
			{"kind": "p", "name": "create_pool_wait_collector"},
			{"kind": "p", "name": "create_stress_consumer"},
			{"kind": "p", "name": "create_worker"},
			{"kind": "p", "name": "disposable_dispose"},
			{"kind": "p", "name": "disposable_factory"},
			{"kind": "p", "name": "disposable_itm_example"},
			{"kind": "p", "name": "disposable_reset"},
			{"kind": "p", "name": "echo_server_example"},
			{"kind": "p", "name": "endless_game_example"},
			{"kind": "p", "name": "foreign_dispose"},
			{"kind": "p", "name": "foreign_dispose_example"},
			{"kind": "p", "name": "interrupt_example"},
			{"kind": "p", "name": "lifecycle_example"},
			{"kind": "p", "name": "master_dispose"},
			{"kind": "p", "name": "master_example"},
			{"kind": "p", "name": "master_shutdown"},
			{"kind": "p", "name": "negotiation_example"},
			{"kind": "p", "name": "pool_wait_example"},
			{"kind": "p", "name": "stress_example"}
		]
	},
	"mpsc": {
		"name": "mpsc",
		"collection": "matryoshka",
		"path": "/matryoshka/mpsc",
		"entities": [
			{"kind": "t", "name": "Queue"},
			{"kind": "p", "name": "init"},
			{"kind": "p", "name": "length"},
			{"kind": "p", "name": "pop"},
			{"kind": "p", "name": "push"},
			{"kind": "p", "name": "test_concurrent_push_stress"},
			{"kind": "p", "name": "test_example_basic_usage"},
			{"kind": "p", "name": "test_fifo_order"},
			{"kind": "p", "name": "test_init"},
			{"kind": "p", "name": "test_length_consistency"},
			{"kind": "p", "name": "test_pop_all_drains_to_zero"},
			{"kind": "p", "name": "test_pop_empty"},
			{"kind": "p", "name": "test_push_pop_interleaved"},
			{"kind": "p", "name": "test_push_pop_one"},
			{"kind": "p", "name": "test_stub_recycling_explicit"}
		]
	},
	"wakeup": {
		"name": "wakeup",
		"collection": "matryoshka",
		"path": "/matryoshka/wakeup",
		"entities": [
			{"kind": "t", "name": "WakeUper"},
			{"kind": "p", "name": "sema_wakeup"},
			{"kind": "p", "name": "test_concurrent_wake_signals"},
			{"kind": "p", "name": "test_ctx_persistence"},
			{"kind": "p", "name": "test_custom_wakeup"},
			{"kind": "p", "name": "test_example_sema_wakeup"},
			{"kind": "p", "name": "test_sema_close_frees"},
			{"kind": "p", "name": "test_sema_wake_signals"},
			{"kind": "p", "name": "test_sema_wakeup_creates"},
			{"kind": "p", "name": "test_wake_with_nil_ctx"},
			{"kind": "p", "name": "test_zero_value"}
		]
	},
	"pool": {
		"name": "pool",
		"collection": "matryoshka",
		"path": "/matryoshka/pool",
		"entities": [
			{"kind": "t", "name": "Allocation_Strategy"},
			{"kind": "t", "name": "Pool"},
			{"kind": "t", "name": "Pool_Event"},
			{"kind": "t", "name": "Pool_State"},
			{"kind": "t", "name": "Pool_Status"},
			{"kind": "t", "name": "T_Hooks"},
			{"kind": "p", "name": "destroy"},
			{"kind": "p", "name": "destroy_itm"},
			{"kind": "p", "name": "get"},
			{"kind": "p", "name": "init"},
			{"kind": "p", "name": "length"},
			{"kind": "p", "name": "put"}
		]
	},
	"nbio_mbox": {
		"name": "nbio_mbox",
		"collection": "matryoshka",
		"path": "/matryoshka/nbio_mbox",
		"entities": [
			{"kind": "t", "name": "Nbio_Mailbox_Error"},
			{"kind": "t", "name": "Nbio_Wakeuper_Kind"},
			{"kind": "p", "name": "init_nbio_mbox"}
		]
	}}};
