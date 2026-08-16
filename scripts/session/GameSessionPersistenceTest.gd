extends Node

const GAME_SESSION_SCENE := preload("res://scenes/GameSession.tscn")
const PREPARATION_SERVICE := preload(
	"res://scripts/session/CityPreparationService.gd"
)
const DEBUG_PANEL_SCRIPT := preload(
	"res://scripts/ui/debug/DebugPanel.gd"
)

var failure_count: int = 0


class FakePreparationThread:
	extends RefCounted

	var start_error: int = OK
	var started: bool = false
	var alive: bool = true
	var result


	func _init(
		initial_start_error: int = OK,
		initial_alive: bool = true,
		initial_result = null
	) -> void:
		start_error = initial_start_error
		alive = initial_alive
		result = initial_result


	func start(_callable: Callable, _priority: int) -> int:
		if start_error != OK:
			return start_error

		started = true
		return OK


	func is_started() -> bool:
		return started


	func is_alive() -> bool:
		return started and alive


	func wait_to_finish():
		started = false
		return result


	func finish(raw_result) -> void:
		result = raw_result
		alive = false


class TestPreparationService:
	extends CityPreparationService

	var fake_threads: Array = []
	var thread_start_failure_count: int = 0


	func queue_fake_thread(fake_thread: FakePreparationThread) -> void:
		fake_threads.append(fake_thread)


	func _create_thread():
		if fake_threads.is_empty():
			return null

		return fake_threads.pop_front()


	func _report_thread_start_failure(_start_error: int) -> void:
		thread_start_failure_count += 1


class FakeTerminalService:
	extends RefCounted

	var terminal_result: Dictionary = {}
	var synchronous_payload: Dictionary = {"marker": "synchronous"}


	func poll() -> void:
		pass


	func take_terminal_result(_generation: int) -> Dictionary:
		var result := terminal_result
		terminal_result = {}
		return result


	func is_valid_request(_request: Dictionary) -> bool:
		return true


	func prepare_synchronously(_request: Dictionary) -> Dictionary:
		return synchronous_payload.duplicate(true)


	func shutdown() -> void:
		pass


class FakeTransitionRenderer:
	extends Node

	var transition_values: Array[bool] = []


	func set_city_transition_pending(is_pending: bool) -> void:
		transition_values.append(is_pending)


class TestGameSession:
	extends GameSession

	var ensure_call_count: int = 0
	var activate_call_count: int = 0
	var last_prepared_payload: Dictionary = {}
	var preparation_failure_messages: Array[String] = []


	func _ensure_city_view(prepared_payload: Dictionary) -> bool:
		ensure_call_count += 1
		last_prepared_payload = prepared_payload

		if city_view == null:
			city_view = Node.new()
		return true


	func _activate_view(_target_view: Node) -> bool:
		activate_call_count += 1
		return true


	func _report_city_preparation_failure(message: String) -> void:
		preparation_failure_messages.append(message)


class ExplicitBindingTransactionCityView:
	extends Control

	var configured_context
	var session_active: bool = false


	func configure_initial_city_presentation(
		settlement_context,
		_prepared_payload: Dictionary = {}
	) -> bool:
		configured_context = settlement_context
		return configured_context != null


	func validate_city_presentation_binding(settlement_context) -> bool:
		return configured_context != null and is_same(
			configured_context,
			settlement_context
		)


	func get_bound_settlement_context():
		return configured_context


	func set_session_view_active(is_active: bool) -> void:
		session_active = is_active
		visible = is_active


class FirstEntryTransactionWorldView:
	extends Control

	var select_region_button: Control


	func _init() -> void:
		select_region_button = Control.new()
		select_region_button.visible = true
		add_child(select_region_button)


class FirstEntryTransactionSession:
	extends GameSession

	var reject_first_synchronized_foundation: bool = true
	var synchronization_call_count: int = 0
	var city_view_creation_count: int = 0
	var first_entry_failure_messages: Array[String] = []


	func _synchronize_first_city_entry_foundation() -> bool:
		synchronization_call_count += 1
		var synchronized := (
			super._synchronize_first_city_entry_foundation()
		)

		if synchronized and reject_first_synchronized_foundation:
			reject_first_synchronized_foundation = false
			return false

		return synchronized


	func _create_city_view() -> Node:
		city_view_creation_count += 1
		var test_city_view := ExplicitBindingTransactionCityView.new()
		test_city_view.name = "FirstEntryTransactionCityView"
		return test_city_view


	func _report_first_city_entry_failure(message: String) -> void:
		first_entry_failure_messages.append(message)


class NullCityViewTransactionSession:
	extends GameSession

	var reject_next_city_view: bool = true
	var city_view_creation_count: int = 0
	var synchronization_call_count: int = 0
	var first_entry_failure_messages: Array[String] = []


	func _create_city_view() -> Node:
		city_view_creation_count += 1
		if reject_next_city_view:
			reject_next_city_view = false
			return null

		return ExplicitBindingTransactionCityView.new()


	func _prepare_first_city_entry(
		_prepared_payload: Dictionary = {}
	):
		synchronization_call_count += 1
		return self


	func _select_first_city_detailed_simulation_target() -> bool:
		return true


	func _report_first_city_entry_failure(message: String) -> void:
		first_entry_failure_messages.append(message)


func _ready() -> void:
	_test_thread_start_failure_terminal()
	_test_invalid_worker_result_terminal()
	_test_cancel_retry_and_stale_result()
	_test_cancel_does_not_start_queued_work()
	_test_shutdown_terminalizes_pending_requests()
	_test_game_session_terminal_outcomes()
	_test_game_session_prewarm_lifecycle()
	_test_first_city_entry_transaction()
	await _test_background_city_preparation()
	await _test_persistent_world_city_views()
	await _test_requested_initial_city_entry()
	_test_debug_panels_default_to_minimized()
	WorldData.reset_runtime_session_state()
	GameSession.cancel_next_session_city_entry()

	if failure_count > 0:
		push_error("Game session persistence test failed: " + str(failure_count))
		get_tree().quit(1)
		return

	print("Game session persistence tests passed.")
	get_tree().quit(0)


func _test_thread_start_failure_terminal() -> void:
	var service := TestPreparationService.new()
	service.queue_fake_thread(
		FakePreparationThread.new(ERR_CANT_CREATE)
	)
	var request := _make_preparation_request(
		"thread-start-failure-test"
	)
	var generation: int = service.request_preparation(request)
	var terminal := service.take_terminal_result(generation)
	_expect(generation > 0, "A start failure must retain its generation.")
	_expect(
		str(terminal.get("status", ""))
		== PREPARATION_SERVICE.STATUS_FAILED,
		"Thread.start failure must immediately publish FAILED."
	)
	_expect(
		int(terminal.get("generation", 0)) == generation
		and str(terminal.get("signature", ""))
		== str(request["signature"]),
		"Thread.start failure must preserve exact request identity."
	)
	_expect(
		service.thread_start_failure_count == 1,
		"Thread.start failure must be reported exactly once."
	)
	service.shutdown()


func _test_invalid_worker_result_terminal() -> void:
	var service := TestPreparationService.new()
	service.queue_fake_thread(
		FakePreparationThread.new(OK, false, 42)
	)
	var request := _make_preparation_request(
		"invalid-worker-result-test"
	)
	var generation: int = service.request_preparation(request)
	var terminal := service.take_terminal_result(generation)
	_expect(
		str(terminal.get("status", ""))
		== PREPARATION_SERVICE.STATUS_FAILED,
		"A non-Dictionary worker result must publish FAILED."
	)
	_expect(
		str(terminal.get("reason", ""))
		== "invalid_worker_result_type",
		"Invalid worker output must retain a diagnostic terminal reason."
	)
	service.shutdown()

	var identity_service := TestPreparationService.new()
	identity_service.queue_fake_thread(
		FakePreparationThread.new(
			OK,
			false,
			{
				"valid": true,
				"signature": "wrong-signature",
				"preparation_generation": 999,
			}
		)
	)
	var identity_request := _make_preparation_request(
		"invalid-worker-identity-test"
	)
	var identity_generation: int = (
		identity_service.request_preparation(identity_request)
	)
	var identity_terminal := identity_service.take_terminal_result(
		identity_generation
	)
	_expect(
		str(identity_terminal.get("status", ""))
		== PREPARATION_SERVICE.STATUS_FAILED
		and int(identity_terminal.get("generation", 0))
		== identity_generation
		and str(identity_terminal.get("signature", ""))
		== str(identity_request["signature"]),
		"Worker output cannot replace main-thread request identity."
	)
	identity_service.shutdown()

	var malformed_identity_service := TestPreparationService.new()
	malformed_identity_service.queue_fake_thread(
		FakePreparationThread.new(
			OK,
			false,
			{
				"valid": true,
				"signature": "malformed-worker-identity-test",
				"preparation_generation": {"not": "an integer"},
			}
		)
	)
	var malformed_request := _make_preparation_request(
		"malformed-worker-identity-test"
	)
	var malformed_generation: int = (
		malformed_identity_service.request_preparation(malformed_request)
	)
	var malformed_terminal := (
		malformed_identity_service.take_terminal_result(
			malformed_generation
		)
	)
	_expect(
		str(malformed_terminal.get("status", ""))
		== PREPARATION_SERVICE.STATUS_FAILED
		and str(malformed_terminal.get("reason", ""))
		== "invalid_worker_result_identity",
		"A malformed worker generation must publish FAILED safely."
	)
	malformed_identity_service.shutdown()

	var malformed_payload_service := TestPreparationService.new()
	var malformed_payload_request := _make_preparation_request(
		"malformed-worker-payload-test"
	)
	malformed_payload_service.queue_fake_thread(
		FakePreparationThread.new(
			OK,
			false,
			{
				"valid": true,
				"signature": str(malformed_payload_request["signature"]),
				"preparation_generation": 1,
			}
		)
	)
	var malformed_payload_generation: int = (
		malformed_payload_service.request_preparation(
			malformed_payload_request
		)
	)
	var malformed_payload_terminal := (
		malformed_payload_service.take_terminal_result(
			malformed_payload_generation
		)
	)
	_expect(
		str(malformed_payload_terminal.get("status", ""))
		== PREPARATION_SERVICE.STATUS_FAILED
		and str(malformed_payload_terminal.get("reason", ""))
		== "invalid_worker_success_payload",
		"A success-shaped result without a city payload must publish FAILED."
	)
	malformed_payload_service.shutdown()

	var malformed_atlas_service := TestPreparationService.new()
	var malformed_atlas_request := _make_preparation_request(
		"malformed-worker-atlas-test"
	)
	var malformed_atlas_result := _make_fake_worker_success(
		str(malformed_atlas_request["signature"]),
		1,
		"malformed-atlas"
	)
	var malformed_atlas: Dictionary = malformed_atlas_result["map_atlas"]
	malformed_atlas["visual_version"] = {"not": "an integer"}
	malformed_atlas_service.queue_fake_thread(
		FakePreparationThread.new(OK, false, malformed_atlas_result)
	)
	var malformed_atlas_generation: int = (
		malformed_atlas_service.request_preparation(
			malformed_atlas_request
		)
	)
	var malformed_atlas_terminal := (
		malformed_atlas_service.take_terminal_result(
			malformed_atlas_generation
		)
	)
	_expect(
		str(malformed_atlas_terminal.get("status", ""))
		== PREPARATION_SERVICE.STATUS_FAILED
		and str(malformed_atlas_terminal.get("reason", ""))
		== "invalid_worker_success_payload",
		"Malformed atlas metadata must publish FAILED safely."
	)
	malformed_atlas_service.shutdown()


func _test_cancel_retry_and_stale_result() -> void:
	var service := TestPreparationService.new()
	var old_thread := FakePreparationThread.new()
	var new_thread := FakePreparationThread.new()
	service.queue_fake_thread(old_thread)
	service.queue_fake_thread(new_thread)
	var request := _make_preparation_request(
		"cancel-retry-test"
	)
	var old_generation: int = service.request_preparation(request)
	service.cancel_pending_requests()
	var cancelled := service.take_terminal_result(old_generation)
	_expect(
		str(cancelled.get("status", ""))
		== PREPARATION_SERVICE.STATUS_CANCELLED,
		"Cancellation must immediately publish CANCELLED."
	)

	var new_generation: int = service.request_preparation(request)
	_expect(
		new_generation > old_generation,
		"An immediate same-signature retry must get a fresh generation."
	)
	_expect(
		service.get_request_status(new_generation)
		== PREPARATION_SERVICE.STATUS_RUNNING,
		"A same-signature retry must remain accepted while the old worker finishes."
	)

	old_thread.finish(
		_make_fake_worker_success(
			str(request["signature"]),
			old_generation,
			"stale-old-result"
		)
	)
	service.poll()
	_expect(
		service.get_request_status(old_generation, false)
		== PREPARATION_SERVICE.STATUS_CANCELLED,
		"A stale old worker result cannot overwrite CANCELLED."
	)
	_expect(
		new_thread.started,
		"The fresh generation must start after the cancelled worker exits."
	)

	new_thread.finish(
		_make_fake_worker_success(
			str(request["signature"]),
			new_generation,
			"fresh-result"
		)
	)
	service.poll()
	var succeeded := service.take_terminal_result(new_generation)
	var payload = succeeded.get("payload", {})
	_expect(
		str(succeeded.get("status", ""))
		== PREPARATION_SERVICE.STATUS_SUCCEEDED,
		"The replacement generation must reach SUCCEEDED."
	)
	_expect(
		payload is Dictionary
		and str(payload.get("marker", "")) == "fresh-result",
		"Only the replacement generation may publish its payload."
	)
	service.shutdown()


func _test_shutdown_terminalizes_pending_requests() -> void:
	var service := TestPreparationService.new()
	var active_thread := FakePreparationThread.new()
	var queued_thread := FakePreparationThread.new()
	service.queue_fake_thread(active_thread)
	service.queue_fake_thread(queued_thread)
	var active_generation: int = service.request_preparation(
		_make_preparation_request("shutdown-active-test")
	)
	var queued_generation: int = service.request_preparation(
		_make_preparation_request("shutdown-queued-test")
	)
	active_thread.finish(null)

	service.shutdown()
	var active_terminal := service.take_terminal_result(active_generation)
	var queued_terminal := service.take_terminal_result(queued_generation)
	_expect(
		str(active_terminal.get("status", ""))
		== PREPARATION_SERVICE.STATUS_CANCELLED,
		"Service shutdown must terminalize the active request."
	)
	_expect(
		str(queued_terminal.get("status", ""))
		== PREPARATION_SERVICE.STATUS_CANCELLED,
		"Service shutdown must terminalize the queued request."
	)
	_expect(
		not queued_thread.started,
		"Service shutdown must not start queued preparation while exiting."
	)


func _test_cancel_does_not_start_queued_work() -> void:
	var service := TestPreparationService.new()
	var active_thread := FakePreparationThread.new()
	var queued_thread := FakePreparationThread.new()
	service.queue_fake_thread(active_thread)
	service.queue_fake_thread(queued_thread)
	var active_generation: int = service.request_preparation(
		_make_preparation_request("cancel-finished-active-test")
	)
	var queued_generation: int = service.request_preparation(
		_make_preparation_request("cancel-finished-queued-test")
	)
	active_thread.finish(null)

	service.cancel_pending_requests()
	var active_terminal := service.take_terminal_result(active_generation)
	var queued_terminal := service.take_terminal_result(queued_generation)
	_expect(
		str(active_terminal.get("status", ""))
		== PREPARATION_SERVICE.STATUS_CANCELLED
		and str(queued_terminal.get("status", ""))
		== PREPARATION_SERVICE.STATUS_CANCELLED,
		"Cancellation must terminalize both finished-active and queued work."
	)
	_expect(
		not queued_thread.started,
		"Cancellation must not promote queued preparation while cancelling."
	)
	service.shutdown()


func _test_game_session_terminal_outcomes() -> void:
	_test_game_session_terminal_case(
		PREPARATION_SERVICE.STATUS_SUCCEEDED,
		true,
		{"marker": "prepared"}
	)
	_test_game_session_terminal_case(
		PREPARATION_SERVICE.STATUS_FAILED,
		true,
		{}
	)
	_test_game_session_terminal_case(
		PREPARATION_SERVICE.STATUS_CANCELLED,
		false,
		{}
	)
	_test_game_session_terminal_case(
		PREPARATION_SERVICE.STATUS_SUPERSEDED,
		false,
		{}
	)

	var session := TestGameSession.new()
	var preparation := FakeTerminalService.new()
	var renderer := FakeTransitionRenderer.new()
	session.city_preparation = preparation
	session.world_renderer = renderer
	session.pending_city_switch = true
	session.pending_city_request = {"signature": "new-request"}
	session.pending_city_preparation_generation = 2
	preparation.terminal_result = {
		"generation": 1,
		"signature": "old-request",
		"status": PREPARATION_SERVICE.STATUS_SUCCEEDED,
		"payload": {"marker": "stale"},
	}
	session._process(0.0)
	_expect(
		session.pending_city_switch
		and session.pending_city_preparation_generation == 2
		and not session.pending_city_request.is_empty(),
		"A stale terminal result cannot clear a newer pending switch."
	)
	_expect(
		session.ensure_call_count == 0
		and session.activate_call_count == 0
		and renderer.transition_values.is_empty(),
		"A stale terminal result cannot install or activate a city."
	)
	_free_test_session(session, renderer)


func _test_game_session_prewarm_lifecycle() -> void:
	WorldData.reset_runtime_session_state()
	var service := TestPreparationService.new()
	var first_thread := FakePreparationThread.new()
	var second_thread := FakePreparationThread.new()
	service.queue_fake_thread(first_thread)
	service.queue_fake_thread(second_thread)
	var renderer := FakeTransitionRenderer.new()
	var session := TestGameSession.new()
	session.city_preparation = service
	session.world_renderer = renderer
	var first_request := _make_preparation_request("prewarm-first-test")
	var second_request := _make_preparation_request("prewarm-second-test")

	session.prepare_city_view(first_request)
	var first_generation: int = (
		session.prewarmed_city_preparation_generation
	)
	session.prepare_city_view(second_request)
	var second_generation: int = (
		session.prewarmed_city_preparation_generation
	)
	_expect(
		first_generation > 0 and second_generation > first_generation,
		"A changed prewarm signature must receive a fresh generation."
	)
	_expect(
		service.get_request_status(first_generation, false)
		== PREPARATION_SERVICE.STATUS_SUPERSEDED
		and not service.has_terminal_result(first_generation),
		"A replaced prewarm must release its terminal payload."
	)

	first_thread.finish(
		_make_fake_worker_success(
			str(first_request["signature"]),
			first_generation,
			"stale-prewarm"
		)
	)
	session._process(0.0)
	_expect(
		second_thread.started,
		"The replacement prewarm must start after stale work exits."
	)

	session.show_city_view(second_request)
	_expect(
		session.pending_city_preparation_generation == second_generation
		and renderer.transition_values == [true],
		"Showing a running prewarm must join it and show transition UI."
	)
	second_thread.finish(
		_make_fake_worker_success(
			str(second_request["signature"]),
			second_generation,
			"current-prewarm"
		)
	)
	session._process(0.0)
	_expect(
		not session.pending_city_switch
		and session.ensure_call_count == 1
		and session.activate_call_count == 1
		and str(session.last_prepared_payload.get("marker", ""))
		== "current-prewarm",
		"Only the current prewarm may activate the prepared city."
	)
	_expect(
		renderer.transition_values == [true, false],
		"A running prewarm must clear transition UI after success."
	)

	_free_test_session(session, renderer)


func _test_first_city_entry_transaction() -> void:
	WorldData.reset_runtime_session_state()
	SimulationClock.reset_clock_state()
	_test_null_city_view_does_not_commit_first_entry()
	var world := _make_world(10, 10, 52_101)
	var locked := WorldData.lock_world_save({
		"source_world": world,
		"region_top_left": Vector2i(2, 2),
		"region_center": Vector2i(2, 2),
		"region_size": 1,
		"world_scene_path": "res://scenes/GameSession.tscn",
		"city_scene_path": "res://scenes/CityScreen.tscn",
		"city_name": "Transaction Test City",
		"culture_name": "Transaction Test Culture",
	})
	_expect(locked, "The first-entry transaction fixture must lock its world.")
	if not locked:
		return

	var city_world := _make_world(20, 20, 52_102)
	WorldData.store_city_world_save(city_world, 52_102)
	var keep_size := CityObjectCatalog.get_city_object_size_for_type(
		CityObjectCatalog.CITY_OBJECT_CITY_CENTER
	)
	var keep_top_left := Vector2i(8, 6)
	var keep := CityObjectSystem.register_completed_city_object({
		"object_type": CityObjectCatalog.CITY_OBJECT_CITY_CENTER,
		"top_left": keep_top_left,
		"size_tiles": keep_size,
		"object_owner": "player",
		"city_world": city_world,
	})
	_expect(
		not keep.is_empty(),
		"The first-entry transaction fixture must create one City Keep."
	)
	if keep.is_empty():
		WorldData.reset_runtime_session_state()
		return

	WorldData.found_player_city({
		"city_world_seed": 52_102,
		"city_map_size": Vector2i(city_world.width, city_world.height),
		"foundation_top_left": keep_top_left,
		"foundation_size": keep_size,
	})
	var keep_id := int(keep.get("id", -1))
	var seeded_resources := {
		CityResourceCatalog.RESOURCE_FISH: 7,
		CityResourceCatalog.RESOURCE_LUMBER: 11,
		CityResourceCatalog.RESOURCE_STONE: 13,
	}

	for raw_resource in seeded_resources.keys():
		var resource := str(raw_resource)
		var accepted := (
			CityResourceContainerSystem.add_resource_to_city_object_storage(
				keep_id,
				resource,
				int(seeded_resources[resource])
			)
		)
		_expect(
			accepted == int(seeded_resources[resource]),
			"The first-entry fixture must seed exact Keep resources."
		)

	var object_state_before = CityObjectSystem.get_current_state()
	var citizen_state_before = CityCitizenRegistrySystem.get_current_state()
	var resource_state_before = CityResourceAccountingSystem.get_current_state()
	var objects_before := CityObjectSystem.get_city_object_snapshot()
	var citizens_before: Array = citizen_state_before.citizens.duplicate(true)
	var next_object_id_before: int = int(object_state_before.next_object_id)
	var next_citizen_id_before: int = int(citizen_state_before.next_citizen_id)
	var resource_totals_before := {}

	for raw_resource in seeded_resources.keys():
		var resource := str(raw_resource)
		resource_totals_before[resource] = (
			CityResourceAccountingSystem.get_total_physical_city_resource_amount(resource)
		)
		_expect(
			int(resource_totals_before[resource])
			== int(seeded_resources[resource]),
			"The transaction fixture must expose each seeded physical total."
		)

	_expect(
		objects_before.size() == 1
		and citizens_before.size()
		== CityCitizenRegistrySystem.STARTING_CITY_POPULATION,
		"The transaction fixture must begin with one Keep and eight citizens."
	)

	SimulationClock.start_new_game(4, 15, 37)
	SimulationClock.set_speed_multiplier(3.0)
	SimulationClock.set_simulation_paused(false)
	var clock_minutes_before := SimulationClock.absolute_world_minutes
	var clock_tick_before := SimulationClock.tick_index
	var world_view := FirstEntryTransactionWorldView.new()
	var session := FirstEntryTransactionSession.new()
	session.add_child(world_view)
	session.world_view = world_view
	session.world_renderer = world_view
	session.active_view = world_view

	var first_entry_succeeded := session._ensure_city_view({})
	var first_activation_succeeded := session._activate_view(session.city_view)
	_expect(
		not first_entry_succeeded
		and not first_activation_succeeded
		and session.city_view == null
		and not session.city_view_has_been_entered,
		"A rejected foundation synchronization must not commit city entry."
	)
	_expect(
		session.active_view == world_view
		and world_view.select_region_button.visible
		and session.simulation_speed_controls == null
		and session.city_view_creation_count == 1
		and session.get_node_or_null("FirstEntryTransactionCityView") == null,
		"Failed entry must preserve the world UI and discard its detached city candidate."
	)
	_expect(
		SimulationClock.absolute_world_minutes == clock_minutes_before
		and SimulationClock.tick_index == clock_tick_before
		and is_equal_approx(SimulationClock.speed_multiplier, 3.0)
		and not SimulationClock.simulation_paused,
		"Failed entry must leave the existing clock state byte-for-byte intact."
	)
	_expect(
		session.first_entry_failure_messages.size() == 1,
		"Failed entry must report the transaction rejection exactly once."
	)
	_expect(
		WorldPoliticalState.get_polity_snapshot().size() == 1
		and WorldPoliticalState.get_settlement_snapshot().size() == 1
		and is_same(CityObjectSystem.get_current_state(), object_state_before)
		and is_same(
			CityCitizenRegistrySystem.get_current_state(),
			citizen_state_before
		)
		and is_same(
			CityResourceAccountingSystem.get_current_state(),
			resource_state_before
		),
		"A post-sync rejection must preserve one exact settlement state owner."
	)
	var polity_snapshot_after_rejection := (
		WorldPoliticalState.get_polity_snapshot()
	)
	var settlement_snapshot_after_rejection := (
		WorldPoliticalState.get_settlement_snapshot()
	)
	var player_polity_id_after_rejection := WorldPoliticalState.player_polity_id
	var capital_id_after_rejection := WorldPoliticalState.active_settlement_id
	var capital_state_after_rejection = (
		WorldPoliticalState.get_city_simulation_state(
			capital_id_after_rejection
		)
	)
	var next_polity_id_after_rejection := WorldPoliticalState.next_polity_id
	var next_settlement_id_after_rejection := (
		WorldPoliticalState.next_settlement_id
	)

	var retry_succeeded := session._ensure_city_view({})
	var retry_activation_succeeded := session._activate_view(session.city_view)
	_expect(
		retry_succeeded
		and retry_activation_succeeded
		and session.city_view != null
		and session.city_view_has_been_entered
		and session.active_view == session.city_view,
		"Retry must commit and activate the prepared city exactly once."
	)
	_expect(
		session.synchronization_call_count == 2
		and session.city_view_creation_count == 2
		and session.simulation_speed_controls != null
		and not world_view.select_region_button.visible,
		"Successful retry must perform one first-entry UI commit."
	)
	_expect(
		SimulationClock.simulation_paused
		and is_equal_approx(SimulationClock.speed_multiplier, 1.0)
		and SimulationClock.get_world_day() == 1
		and SimulationClock.get_world_hour() == 6
		and SimulationClock.get_world_minute() == 0
		and SimulationClock.tick_index == 0,
		"Successful retry must commit the normal paused Day 1 06:00 clock."
	)

	var content_preserved: bool = (
		is_same(CityObjectSystem.get_current_state(), object_state_before)
		and is_same(
			CityCitizenRegistrySystem.get_current_state(),
			citizen_state_before
		)
		and is_same(
			CityResourceAccountingSystem.get_current_state(),
			resource_state_before
		)
		and CityObjectSystem.get_city_object_snapshot() == objects_before
		and CityCitizenRegistrySystem.get_current_state().citizens
		== citizens_before
		and CityObjectSystem.get_current_state().next_object_id
		== next_object_id_before
		and CityCitizenRegistrySystem.get_current_state().next_citizen_id
		== next_citizen_id_before
	)

	for raw_resource in seeded_resources.keys():
		var resource := str(raw_resource)
		content_preserved = (
			content_preserved
			and CityResourceAccountingSystem
			.get_total_physical_city_resource_amount(resource)
			== int(resource_totals_before[resource])
		)

	_expect(
		content_preserved
		and WorldPoliticalState.get_polity_snapshot()
		== polity_snapshot_after_rejection
		and WorldPoliticalState.get_settlement_snapshot()
		== settlement_snapshot_after_rejection
		and WorldPoliticalState.player_polity_id
		== player_polity_id_after_rejection
		and WorldPoliticalState.active_settlement_id
		== capital_id_after_rejection
		and WorldPoliticalState.next_polity_id
		== next_polity_id_after_rejection
		and WorldPoliticalState.next_settlement_id
		== next_settlement_id_after_rejection
		and is_same(
			WorldPoliticalState.get_city_simulation_state(
				capital_id_after_rejection
			),
			capital_state_after_rejection
		),
		"Retry must not duplicate the Keep, citizens, resources, or registry."
	)

	var committed_city_view_id := session.city_view.get_instance_id()
	var committed_controls_id := (
		session.simulation_speed_controls.get_instance_id()
	)
	var repeated_entry_succeeded := session._ensure_city_view({})
	var repeated_activation_succeeded := session._activate_view(
		session.city_view
	)
	_expect(
		repeated_entry_succeeded
		and repeated_activation_succeeded
		and session.synchronization_call_count == 2
		and session.city_view_creation_count == 2
		and session.city_view.get_instance_id() == committed_city_view_id
		and session.simulation_speed_controls.get_instance_id()
		== committed_controls_id
		and CityObjectSystem.get_city_object_snapshot() == objects_before
		and CityCitizenRegistrySystem.get_current_state().citizens
		== citizens_before
		and WorldPoliticalState.get_polity_snapshot()
		== polity_snapshot_after_rejection
		and WorldPoliticalState.get_settlement_snapshot()
		== settlement_snapshot_after_rejection
		and WorldPoliticalState.next_polity_id
		== next_polity_id_after_rejection
		and WorldPoliticalState.next_settlement_id
		== next_settlement_id_after_rejection,
		"Repeated entry after commit must be a complete no-op."
	)

	session.free()
	SimulationClock.reset_clock_state()
	WorldData.reset_runtime_session_state()


func _test_null_city_view_does_not_commit_first_entry() -> void:
	var session := NullCityViewTransactionSession.new()
	SimulationClock.start_new_game(3, 14, 29)
	SimulationClock.set_speed_multiplier(2.0)
	SimulationClock.set_simulation_paused(false)
	var minutes_before := SimulationClock.absolute_world_minutes
	var tick_before := SimulationClock.tick_index

	_expect(
		not session._ensure_city_view({})
		and session.city_view == null
		and not session.city_view_has_been_entered
		and session.simulation_speed_controls == null
		and session.city_view_creation_count == 1
		and session.synchronization_call_count == 0
		and session.first_entry_failure_messages.size() == 1
		and SimulationClock.absolute_world_minutes == minutes_before
		and SimulationClock.tick_index == tick_before
		and is_equal_approx(SimulationClock.speed_multiplier, 2.0)
		and not SimulationClock.simulation_paused,
		"A city-view creation failure must leave first entry entirely uncommitted."
	)
	_expect(
		session._ensure_city_view({})
		and session.city_view != null
		and session.city_view_has_been_entered
		and session.simulation_speed_controls != null
		and session.city_view_creation_count == 2
		and session.synchronization_call_count == 1,
		"A city-view creation failure must remain retryable and commit once."
	)
	session.free()
	SimulationClock.reset_clock_state()


func _test_game_session_terminal_case(
	status: String,
	should_activate: bool,
	payload: Dictionary
) -> void:
	var session := TestGameSession.new()
	var preparation := FakeTerminalService.new()
	var renderer := FakeTransitionRenderer.new()
	session.city_preparation = preparation
	session.world_renderer = renderer
	session.pending_city_switch = true
	session.pending_city_request = {"signature": "terminal-test"}
	session.pending_city_preparation_generation = 7
	preparation.terminal_result = {
		"generation": 7,
		"signature": "terminal-test",
		"status": status,
	}

	if status == PREPARATION_SERVICE.STATUS_SUCCEEDED:
		preparation.terminal_result["payload"] = payload

	session._process(0.0)
	_expect(
		not session.pending_city_switch
		and session.pending_city_request.is_empty()
		and session.pending_city_preparation_generation == 0,
		"Every applicable " + status + " outcome must clear pending state."
	)
	_expect(
		renderer.transition_values == [false],
		"Every applicable " + status + " outcome must clear transition UI."
	)
	_expect(
		(session.ensure_call_count == 1) == should_activate
		and (session.activate_call_count == 1) == should_activate,
		status + " must preserve its intended city activation behavior."
	)

	if status == PREPARATION_SERVICE.STATUS_SUCCEEDED:
		_expect(
			session.last_prepared_payload == payload,
			"SUCCEEDED must install the exact prepared payload."
		)
	elif status == PREPARATION_SERVICE.STATUS_FAILED:
		_expect(
			session.last_prepared_payload
			== preparation.synchronous_payload
			and session.preparation_failure_messages.size() == 1,
			"FAILED must install the synchronous fallback payload exactly once."
		)
	else:
		_expect(
			session.preparation_failure_messages.is_empty(),
			status + " must not be reported as a preparation failure."
		)

	_free_test_session(session, renderer)


func _free_test_session(
	session: TestGameSession,
	renderer: FakeTransitionRenderer
) -> void:
	if session.city_view != null:
		session.city_view.free()
		session.city_view = null

	session.world_renderer = null
	renderer.free()
	session.free()


func _test_background_city_preparation() -> void:
	var service = PREPARATION_SERVICE.new()
	var region_tiles := _make_region_tiles(2)
	var request := {
		"signature": "background-preparation-test",
		"region_tiles": region_tiles,
		"region_size": 2,
		"local_tiles_per_world_tile": 2,
		"city_seed": 9917,
	}
	var generation: int = service.request_preparation(request)
	var deadline_msec := Time.get_ticks_msec() + 5000

	while (
		not service.has_terminal_result(generation)
		and Time.get_ticks_msec() < deadline_msec
	):
		await get_tree().process_frame

	var terminal := service.take_terminal_result(generation)
	var payload = terminal.get("payload", {})
	_expect(
		str(terminal.get("status", ""))
		== PREPARATION_SERVICE.STATUS_SUCCEEDED,
		"Normal background preparation must publish SUCCEEDED."
	)
	_expect(not payload.is_empty(), "Background city preparation must complete.")

	if not payload.is_empty():
		var prepared_world = payload.get("city_world")
		var prepared_atlas = payload.get("map_atlas")
		_expect(
			prepared_world is WorldData
			and prepared_world.width == 4
			and prepared_world.height == 4,
			"Background preparation must build the requested city dimensions."
		)
		_expect(
			prepared_atlas is Dictionary
			and prepared_atlas.get("rgba8") is PackedByteArray
			and int(prepared_atlas.get("width", 0)) == 4
			and int(prepared_atlas.get("height", 0)) == 4
			and prepared_atlas.get("modes", []).size()
			== MapVisuals.get_all_view_modes().size(),
			"Background preparation must build one complete atomic map atlas."
		)

	service.shutdown()


func _test_persistent_world_city_views() -> void:
	WorldData.reset_runtime_session_state()
	SimulationClock.reset_clock_state()
	var world := _make_world(8, 8, 4301)
	var locked := WorldData.lock_world_save({
		"source_world": world,
		"region_top_left": Vector2i(2, 2),
		"region_center": Vector2i(2, 2),
		"region_size": 1,
		"world_scene_path": "res://scenes/GameSession.tscn",
		"city_scene_path": "res://scenes/CityScreen.tscn",
		"city_name": "Persistence Test City",
		"culture_name": "Persistence Test Culture",
	})
	_expect(locked, "The persistence fixture must lock its world save.")

	var city_world := _make_world(16, 16, 8123)
	WorldData.store_city_world_save(city_world, 8123)

	# Reproduce a clock that drifted while the founding world remained visible.
	# First city entry must discard that pre-settlement time and begin at 06:00.
	SimulationClock.start_new_game(1, 9, 6)
	SimulationClock.set_speed_multiplier(3.0)
	SimulationClock.set_simulation_paused(false)

	var session = GAME_SESSION_SCENE.instantiate()
	add_child(session)
	await get_tree().process_frame

	var initial_world_view = session.world_view
	var initial_world_id: int = initial_world_view.get_instance_id()
	var world_region_button = session.world_renderer.get(
		"select_region_button"
	)
	_expect(
		session.simulation_speed_controls == null,
		"World view must not show speed controls before first city entry."
	)
	_expect(
		world_region_button is CanvasItem
		and (world_region_button as CanvasItem).visible,
		"Select Region must remain available before first city entry."
	)

	session.show_city_view()
	await get_tree().process_frame

	_expect(session.city_view != null, "City view must be created on first entry.")
	_expect(
		session.active_view == session.city_view,
		"First entry must activate the city view."
	)
	_expect(
		is_instance_valid(initial_world_view)
		and initial_world_view.get_instance_id() == initial_world_id,
		"Entering the city must not destroy or reload the world view."
	)
	_expect(
		session.city_view_has_been_entered,
		"First city activation must unlock the shared playback controls."
	)
	_expect(
		SimulationClock.simulation_paused,
		"First city entry must pause the simulation by default."
	)
	_expect(
		is_equal_approx(SimulationClock.speed_multiplier, 1.0),
		"First city entry must select normal speed beneath the paused state."
	)
	_expect(
		SimulationClock.get_world_day() == 1
		and SimulationClock.get_world_hour() == 6
		and SimulationClock.get_world_minute() == 0
		and SimulationClock.tick_index == 0,
		"First city entry must begin Day 1 at exactly 06:00 with no consumed ticks."
	)
	_expect(
		world_region_button is CanvasItem
		and not (world_region_button as CanvasItem).visible,
		"Entering the city must retire the founding-only Select Region button."
	)

	var speed_controls = session.simulation_speed_controls
	_expect(
		speed_controls != null,
		"First city entry must create the session-wide speed controls."
	)

	var speed_controls_id := 0

	if speed_controls != null:
		speed_controls_id = speed_controls.get_instance_id()
		_expect(
			speed_controls.buttons.size() == 4,
			"Playback controls must contain Pause, 1x, 2x, and 3x."
		)
		_expect(
			speed_controls.speed_one_button.text == "1x"
			and speed_controls.speed_two_button.text == "2x"
			and speed_controls.speed_three_button.text == "3x",
			"Playback speed labels must match the accepted design."
		)
		_expect(
			speed_controls.get_selected_mode_name() == "pause",
			"The pause control must be selected on first city entry."
		)
		speed_controls.select_speed(2.0)

	_expect(
		not SimulationClock.simulation_paused
		and is_equal_approx(SimulationClock.speed_multiplier, 2.0),
		"Selecting 2x must resume the shared clock at double speed."
	)

	var city_renderer = session.city_view
	var first_city_id: int = session.city_view.get_instance_id()
	var all_modes_ready := true

	for mode in MapVisuals.get_all_view_modes():
		all_modes_ready = (
			all_modes_ready
			and city_renderer.city_texture_cache.is_mode_ready(
				city_renderer.city_world,
				mode
			)
		)

	_expect(
		all_modes_ready,
		"City entry must publish all map modes atomically before activation."
	)

	session.show_world_view()
	await get_tree().process_frame
	_expect(
		session.active_view == initial_world_view,
		"Back must reactivate the existing world view."
	)
	_expect(
		session.simulation_speed_controls != null
		and session.simulation_speed_controls.visible,
		"Returning to the world after city entry must retain visible controls."
	)
	_expect(
		session.simulation_speed_controls.get_instance_id()
		== speed_controls_id,
		"World and city views must share one playback-control instance."
	)
	_expect(
		not SimulationClock.simulation_paused
		and is_equal_approx(SimulationClock.speed_multiplier, 2.0),
		"World return must preserve the city-selected clock speed."
	)
	_expect(
		world_region_button is CanvasItem
		and not (world_region_button as CanvasItem).visible,
		"Select Region must stay hidden after returning to the world."
	)

	session.show_city_view()
	await get_tree().process_frame
	_expect(
		session.city_view.get_instance_id() == first_city_id,
		"Repeated city entry must reuse the same city instance."
	)
	_expect(
		initial_world_view.get_instance_id() == initial_world_id,
		"Repeated switching must preserve the same world instance."
	)
	_expect(
		not SimulationClock.simulation_paused
		and is_equal_approx(SimulationClock.speed_multiplier, 2.0),
		"Repeated city entry must not reset the shared playback state."
	)

	if speed_controls != null:
		speed_controls.select_pause()
		_expect(
			SimulationClock.simulation_paused
			and speed_controls.get_selected_mode_name() == "pause",
			"Pause must update both the clock and active-button state."
		)
		speed_controls.select_speed(3.0)
		_expect(
			not SimulationClock.simulation_paused
			and is_equal_approx(SimulationClock.speed_multiplier, 3.0)
			and speed_controls.get_selected_mode_name() == "3x",
			"The final speed button must run the clock at triple speed."
		)

	SimulationClock.set_simulation_paused(false)
	SimulationClock.set_speed_multiplier(1.0)
	session.queue_free()
	await get_tree().process_frame


func _test_requested_initial_city_entry() -> void:
	WorldData.reset_runtime_session_state()
	SimulationClock.reset_clock_state()
	GameSession.cancel_next_session_city_entry()

	var world := _make_world(8, 8, 7711)
	var locked := WorldData.lock_world_save({
		"source_world": world,
		"region_top_left": Vector2i(2, 2),
		"region_center": Vector2i(2, 2),
		"region_size": 1,
		"world_scene_path": "res://scenes/GameSession.tscn",
		"city_scene_path": "res://scenes/CityScreen.tscn",
		"city_name": "Dev City",
		"culture_name": "Dev Culture",
	})
	_expect(locked, "Requested-entry fixture must lock the dev identity.")
	WorldData.store_city_world_save(_make_world(16, 16, 7722), 7722)

	GameSession.request_next_session_city_entry()
	_expect(
		GameSession.has_pending_next_session_city_entry(),
		"Dev launch must record a one-shot initial-city request."
	)

	var session = GAME_SESSION_SCENE.instantiate()
	add_child(session)
	await get_tree().process_frame
	await get_tree().process_frame

	_expect(
		not GameSession.has_pending_next_session_city_entry(),
		"The new GameSession must consume the one-shot city-entry request."
	)
	_expect(
		session.city_view != null
		and session.active_view == session.city_view,
		"A requested session must automatically enter its persistent city view."
	)
	_expect(
		session.simulation_speed_controls != null
		and SimulationClock.simulation_paused
		and SimulationClock.get_world_hour() == 6
		and SimulationClock.get_world_minute() == 0,
		"Requested Dev City entry must receive the normal controls and paused 06:00 clock."
	)
	_expect(
		WorldData.get_official_city_name() == "Dev City"
		and WorldData.get_official_founding_culture_name() == "Dev Culture",
		"Requested Dev City entry must preserve city and culture identity."
	)

	var world_region_button = session.world_renderer.get(
		"select_region_button"
	)
	_expect(
		world_region_button is CanvasItem
		and not (world_region_button as CanvasItem).visible,
		"Requested Dev City entry must retire Select Region."
	)

	if session.city_view != null:
		session.city_view.call("on_back_button_pressed")
		await get_tree().process_frame

	_expect(
		session.active_view == session.world_view,
		"The actual city Back handler must return a requested Dev City to its persistent world."
	)

	session.queue_free()
	await get_tree().process_frame


func _test_debug_panels_default_to_minimized() -> void:
	WorldData.debug_mode_enabled = false
	var host := Node.new()
	add_child(host)
	var first_panel = DEBUG_PANEL_SCRIPT.new()
	var second_panel = DEBUG_PANEL_SCRIPT.new()
	var setup_values := {
		"parent": host,
		"canvas_layer_index": 100,
		"panel_position": Vector2.ZERO,
		"padding": Vector2(12.0, 10.0),
		"minimum_size": Vector2(260.0, 80.0),
		"initial_text": "Debug Test",
		"text_provider": Callable(self, "_get_debug_panel_test_text"),
	}
	first_panel.setup(setup_values)
	second_panel.setup(setup_values)

	first_panel.set_enabled(true)
	second_panel.refresh()
	_expect(
		first_panel.is_minimized and second_panel.is_minimized,
		"Every debug panel must open minimized when tilde enables debug mode."
	)

	first_panel.set_minimized(false)
	second_panel.set_minimized(false)
	first_panel.set_enabled(false)
	first_panel.set_enabled(true)
	second_panel.refresh()
	_expect(
		first_panel.is_minimized and second_panel.is_minimized,
		"A later debug enable must re-minimize active and previously inactive panels."
	)

	first_panel.set_enabled(false)
	host.queue_free()


func _get_debug_panel_test_text() -> String:
	return "Debug Test"


func _make_preparation_request(signature: String) -> Dictionary:
	return {
		"signature": signature,
		"region_tiles": _make_region_tiles(1),
		"region_size": 1,
		"local_tiles_per_world_tile": 1,
		"city_seed": 8811,
	}


func _make_fake_worker_success(
	signature: String,
	generation: int,
	marker: String
) -> Dictionary:
	var prepared_world := _make_world(1, 1, generation)
	return {
		"valid": true,
		"signature": signature,
		"preparation_generation": generation,
		"city_world": prepared_world,
		"city_seed": generation,
		"map_atlas": MapVisuals.build_atomic_mode_atlas_data(
			prepared_world
		),
		"tree_tiles": [],
		"rock_tiles": [],
		"feature_tile_data_version": prepared_world.tile_data_version,
		"city_surface_feature_change_version": (
			prepared_world.city_surface_feature_change_version
		),
		"preparation_duration_usec": 1,
		"marker": marker,
	}


func _make_region_tiles(size: int) -> Array:
	var rows: Array = []

	for _y in range(size):
		var row: Array = []

		for _x in range(size):
			row.append(_make_land_tile())

		rows.append(row)

	return rows


func _make_world(width: int, height: int, seed: int) -> WorldData:
	var world := WorldData.new()
	world.setup(width, height, seed)

	for y in range(height):
		for x in range(width):
			world.tiles[y][x] = _make_land_tile()

	world.mark_tile_data_changed()
	return world


func _make_land_tile() -> Dictionary:
	return {
		"fertility": 55.0,
		"elevation": 0.2,
		"temperature": 0.5,
		"precipitation": 0.5,
		"terrain": WorldData.TERRAIN_LAND,
		"biome": WorldData.BIOME_PLAIN,
		"resource": WorldData.RESOURCE_NONE,
		"is_land": true,
	}


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error("Game session persistence test: " + message)
