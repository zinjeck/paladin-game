extends Node
class_name GameSession

# Owns the world and city views for one runtime session. Once created, neither
# view is destroyed during normal world/city navigation, so switching becomes
# a visibility and input handoff instead of a scene reload.

const WORLD_SCENE := preload("res://scenes/WorldScene.tscn")
const CITY_SCENE := preload("res://scenes/CityScreen.tscn")
const CityPreparationServiceScript := preload(
	"res://scripts/session/CityPreparationService.gd"
)
const SimulationSpeedControlsScript := preload(
	"res://scripts/ui/common/SimulationSpeedControls.gd"
)
const CitySettlementRuntimeBootstrapScript := preload(
	"res://scripts/city/simulation/CitySettlementRuntimeBootstrap.gd"
)

# Scene changes cannot pass constructor arguments. This one-shot request lets
# launchers choose the initial persistent view without bypassing GameSession.
# The first GameSession to enter the tree consumes and clears the request.
static var _next_session_starts_in_city: bool = false

var world_view: Node
var world_renderer: Node
var city_view: Node
var active_view: Node
var simulation_speed_controls: CanvasLayer
var city_preparation = CityPreparationServiceScript.new()
var pending_city_request: Dictionary = {}
var pending_city_switch: bool = false
var pending_city_preparation_generation: int = 0
var prewarmed_city_request: Dictionary = {}
var prewarmed_city_preparation_generation: int = 0
var city_view_has_been_entered: bool = false


static func request_next_session_city_entry() -> void:
	_next_session_starts_in_city = true


static func cancel_next_session_city_entry() -> void:
	_next_session_starts_in_city = false


static func has_pending_next_session_city_entry() -> bool:
	return _next_session_starts_in_city


static func _consume_next_session_city_entry() -> bool:
	var should_start_in_city := _next_session_starts_in_city
	_next_session_starts_in_city = false
	return should_start_in_city


func _ready() -> void:
	var should_start_in_city := _consume_next_session_city_entry()

	add_to_group("game_session")
	world_view = WORLD_SCENE.instantiate()
	add_child(world_view)
	world_renderer = world_view.get_node_or_null("WorldRenderer")
	_set_view_active(world_view, true)
	active_view = world_view

	# Defer until the dynamically instantiated WorldRenderer has completed its
	# own ready work and can build the ordinary city-preparation request.
	if should_start_in_city:
		call_deferred("_enter_requested_initial_city_view")


func _process(_delta: float) -> void:
	city_preparation.poll()
	_consume_pending_city_preparation_terminal()


func _exit_tree() -> void:
	city_preparation.shutdown()


func _enter_requested_initial_city_view() -> void:
	if not is_inside_tree():
		return

	show_city_view()


func _get_presented_settlement_id() -> int:
	var presented_context = WorldPoliticalState.get_active_settlement_context()
	if presented_context != null:
		return int(presented_context.settlement_id)
	return WorldPoliticalState.get_player_capital_settlement_id()


func prepare_city_view(request: Dictionary) -> void:
	if (
		city_view != null
		or WorldData.has_player_capital_city_save()
		or pending_city_switch
	):
		return

	if not city_preparation.is_valid_request(request):
		return

	var signature := str(request.get("signature", ""))

	if (
		prewarmed_city_preparation_generation > 0
		and str(prewarmed_city_request.get("signature", ""))
		!= signature
	):
		_abandon_prewarmed_city_preparation()

	var generation: int = city_preparation.request_preparation(request)

	if generation <= 0:
		return

	prewarmed_city_request = request.duplicate(true)
	prewarmed_city_preparation_generation = generation


func cancel_city_preparation() -> void:
	var pending_generation := pending_city_preparation_generation
	var prewarmed_generation := prewarmed_city_preparation_generation
	city_preparation.cancel_pending_requests()

	if pending_generation > 0:
		city_preparation.discard_terminal_result(pending_generation)
	if (
		prewarmed_generation > 0
		and prewarmed_generation != pending_generation
	):
		city_preparation.discard_terminal_result(prewarmed_generation)

	_clear_prewarmed_city_preparation_tracking()
	_clear_pending_city_switch()


func show_city_view(request: Dictionary = {}) -> void:
	if city_view != null:
		var selected_settlement_id := _get_presented_settlement_id()
		if selected_settlement_id > 0:
			show_settlement_city_view(selected_settlement_id)
		return

	if WorldData.has_player_capital_city_save():
		cancel_city_preparation()
		if _ensure_city_view({}):
			_activate_view(city_view)
		return

	if request.is_empty() and world_renderer != null:
		if world_renderer.has_method("build_city_preparation_request"):
			request = world_renderer.call("build_city_preparation_request")

	if not city_preparation.is_valid_request(request):
		push_error("GameSession cannot enter the city without a valid preparation request.")
		return

	var signature := str(request["signature"])
	if (
		prewarmed_city_preparation_generation > 0
		and str(prewarmed_city_request.get("signature", ""))
		!= signature
	):
		_abandon_prewarmed_city_preparation()

	if (
		pending_city_switch
		and pending_city_preparation_generation > 0
		and str(pending_city_request.get("signature", "")) != signature
	):
		var replaced_generation := pending_city_preparation_generation
		city_preparation.supersede_request(replaced_generation)
		city_preparation.discard_terminal_result(replaced_generation)

	var generation: int = city_preparation.request_preparation(request)

	if generation <= 0:
		push_error("GameSession could not start city preparation.")
		return

	pending_city_request = request.duplicate(true)
	pending_city_preparation_generation = generation
	pending_city_switch = true

	if prewarmed_city_preparation_generation > 0:
		if prewarmed_city_preparation_generation == generation:
			_clear_prewarmed_city_preparation_tracking()
		else:
			_abandon_prewarmed_city_preparation()

	_consume_pending_city_preparation_terminal()

	if pending_city_switch:
		_set_world_transition_pending(true)


func show_settlement_city_view(
	settlement_id: int,
	prepared_payload: Dictionary = {}
) -> bool:
	if city_view == null or settlement_id <= 0:
		return false

	var target_context = WorldPoliticalState.get_settlement_context(
		settlement_id
	)
	if (
		target_context == null
		or not target_context.supports_city_simulation()
		or not _install_prepared_city_payload_for_context(
			target_context,
			prepared_payload
		)
	):
		return false

	var lifecycle_owner := _find_view_lifecycle_owner(city_view)
	if (
		lifecycle_owner == null
		or not lifecycle_owner.has_method("can_rebind_city_presentation")
		or not lifecycle_owner.has_method("rebind_city_presentation")
		or not lifecycle_owner.has_method("validate_city_presentation_binding")
		or not bool(lifecycle_owner.call(
			"can_rebind_city_presentation",
			target_context,
			prepared_payload
		))
	):
		return false

	var bootstrap_result := _bootstrap_city_context(target_context)
	if not bool(bootstrap_result.get("success", false)):
		return false

	var previous_settlement_id := _get_presented_settlement_id()
	var previous_detailed_simulation_settlement_id := (
		SimulationCoordinator.get_detailed_simulation_settlement_id()
	)
	var previous_bound_context = _get_renderer_bound_context(lifecycle_owner)
	if previous_bound_context == null:
		previous_bound_context = WorldPoliticalState.get_settlement_context(
			previous_settlement_id
		)
	var city_was_active := active_view == city_view
	var simulation_was_paused := SimulationClock.simulation_paused
	var simulation_speed_before := SimulationClock.speed_multiplier

	cancel_city_preparation()
	_set_world_transition_pending(true)
	SimulationClock.set_simulation_paused(true)
	if city_was_active:
		_set_view_active(city_view, false)

	# The renderer proves it can bind the explicit target before the session
	# changes either presentation selection or detailed-simulation policy.
	var rebound := bool(lifecycle_owner.call(
		"rebind_city_presentation",
		target_context,
		prepared_payload
	))
	if rebound:
		rebound = bool(lifecycle_owner.call(
			"validate_city_presentation_binding",
			target_context
		))
	if rebound:
		rebound = (
			SimulationCoordinator.select_detailed_simulation_settlement(settlement_id)
		)
	if rebound:
		rebound = WorldPoliticalState.set_active_settlement(settlement_id)

	if not rebound:
		if previous_bound_context != null:
			lifecycle_owner.call(
				"rebind_city_presentation",
				previous_bound_context,
				{}
			)
		_restore_detailed_simulation_target(
			previous_detailed_simulation_settlement_id
		)
		if previous_settlement_id > 0:
			WorldPoliticalState.set_active_settlement(
				previous_settlement_id
			)
		if city_was_active:
			_set_view_active(city_view, true)
			active_view = city_view
		_set_world_transition_pending(false)
		SimulationClock.set_speed_multiplier(simulation_speed_before)
		SimulationClock.set_simulation_paused(simulation_was_paused)
		return false

	if city_was_active:
		_set_view_active(city_view, true)
		active_view = city_view
	else:
		_activate_view(city_view)

	_set_world_transition_pending(false)
	SimulationClock.set_speed_multiplier(simulation_speed_before)
	SimulationClock.set_simulation_paused(simulation_was_paused)
	return true


func show_world_view() -> void:
	cancel_city_preparation()
	_hide_world_region_selection_after_city_entry()
	_activate_view(world_view)


func _consume_pending_city_preparation_terminal() -> void:
	if not pending_city_switch:
		return

	var expected_generation := pending_city_preparation_generation

	if expected_generation <= 0:
		_finish_failed_city_preparation(
			"City preparation lost its request generation."
		)
		return

	var terminal: Dictionary = city_preparation.take_terminal_result(
		expected_generation
	)

	if terminal.is_empty():
		return
	if (
		int(terminal.get("generation", 0)) != expected_generation
		or str(terminal.get("signature", ""))
		!= str(pending_city_request.get("signature", ""))
	):
		# Exact-generation lookup makes this impossible for the real service.
		# If a substitute violates that contract, a stale result still must not
		# clear or activate over the current request.
		return

	var status := str(terminal.get("status", ""))

	if status == CityPreparationServiceScript.STATUS_SUCCEEDED:
		var payload = terminal.get("payload", {})

		if payload is Dictionary and not payload.is_empty():
			_clear_pending_city_switch()
			if _ensure_city_view(payload):
				_activate_view(city_view)
			return

		_finish_failed_city_preparation(
			"Background city preparation returned an empty payload."
		)
		return

	if status == CityPreparationServiceScript.STATUS_FAILED:
		_finish_failed_city_preparation(
			"Background city preparation failed; falling back to "
				+ "synchronous city initialization."
		)
		return

	if (
		status == CityPreparationServiceScript.STATUS_CANCELLED
		or status == CityPreparationServiceScript.STATUS_SUPERSEDED
	):
		_clear_pending_city_switch()
		return

	_finish_failed_city_preparation(
		"Background city preparation returned an unknown terminal state."
	)


func _finish_failed_city_preparation(message: String) -> void:
	var fallback_request := pending_city_request.duplicate(true)
	_clear_pending_city_switch()
	_report_city_preparation_failure(message)

	var fallback_payload: Dictionary = {}
	if city_preparation.is_valid_request(fallback_request):
		fallback_payload = city_preparation.prepare_synchronously(
			fallback_request
		)

	if fallback_payload.is_empty():
		_report_city_preparation_failure(
			"Synchronous city preparation also failed; the world view remains active."
		)
		return

	if _ensure_city_view(fallback_payload):
		_activate_view(city_view)


func _report_city_preparation_failure(message: String) -> void:
	push_error(message)


func _clear_pending_city_switch() -> void:
	pending_city_switch = false
	pending_city_request.clear()
	pending_city_preparation_generation = 0
	_set_world_transition_pending(false)


func _abandon_prewarmed_city_preparation() -> void:
	var generation := prewarmed_city_preparation_generation

	if generation > 0:
		city_preparation.supersede_request(generation)
		city_preparation.discard_terminal_result(generation)

	_clear_prewarmed_city_preparation_tracking()


func _clear_prewarmed_city_preparation_tracking() -> void:
	prewarmed_city_request.clear()
	prewarmed_city_preparation_generation = 0


func _ensure_city_view(prepared_payload: Dictionary) -> bool:
	if city_view != null:
		return city_view_has_been_entered

	var candidate_city_view := _create_city_view()
	if candidate_city_view == null:
		_report_first_city_entry_failure(
			"GameSession could not instantiate the prepared city view."
		)
		return false

	var settlement_context: SettlementSimulationContext = (
		_prepare_first_city_entry(prepared_payload)
	)
	if settlement_context == null:
		candidate_city_view.free()
		return false

	var lifecycle_owner := _find_view_lifecycle_owner(candidate_city_view)
	if (
		lifecycle_owner == null
		or not lifecycle_owner.has_method(
			"configure_initial_city_presentation"
		)
		or not lifecycle_owner.has_method(
			"validate_city_presentation_binding"
		)
		or not bool(lifecycle_owner.call(
			"configure_initial_city_presentation",
			settlement_context,
			prepared_payload
		))
	):
		candidate_city_view.free()
		_report_first_city_entry_failure(
			"GameSession could not configure the city renderer before _ready()."
		)
		return false

	var previous_detailed_simulation_settlement_id := (
		SimulationCoordinator.get_detailed_simulation_settlement_id()
	)
	if not _select_first_city_detailed_simulation_target():
		candidate_city_view.free()
		_report_first_city_entry_failure(
			"GameSession could not select the founding settlement for detailed simulation."
		)
		return false

	city_view = candidate_city_view
	if city_view.has_method("set_session_view_active"):
		city_view.call("set_session_view_active", false)
	else:
		city_view.visible = false
		city_view.process_mode = Node.PROCESS_MODE_DISABLED

	add_child(city_view)
	_set_view_active(city_view, false)
	if not bool(lifecycle_owner.call(
		"validate_city_presentation_binding",
		settlement_context
	)):
		remove_child(city_view)
		city_view.free()
		city_view = null
		_restore_detailed_simulation_target(
			previous_detailed_simulation_settlement_id
		)
		_report_first_city_entry_failure(
			"The configured city renderer failed its post-ready binding validation."
		)
		return false

	_commit_first_city_entry()
	return true


func _create_city_view() -> Node:
	return CITY_SCENE.instantiate()


func _activate_view(target_view: Node) -> bool:
	if target_view == null:
		return false
	if target_view == city_view and not city_view_has_been_entered:
		return false
	if target_view == active_view:
		return true

	_set_view_active(active_view, false)
	_set_view_active(target_view, true)
	active_view = target_view
	return true


func _prepare_first_city_entry(
	prepared_payload: Dictionary = {}
) -> SettlementSimulationContext:
	if city_view_has_been_entered:
		var existing_capital_id := (
			WorldPoliticalState.get_player_capital_settlement_id()
		)
		return WorldPoliticalState.get_settlement_context(
			existing_capital_id
		)

	if not _synchronize_first_city_entry_foundation():
		_report_first_city_entry_failure(
			"GameSession could not establish the founding settlement context."
		)
		return null

	var capital_settlement_id := (
		WorldPoliticalState.get_player_capital_settlement_id()
	)
	var settlement_context = WorldPoliticalState.get_settlement_context(
		capital_settlement_id
	)
	if (
		settlement_context == null
		or not _install_prepared_city_payload_for_context(
			settlement_context,
			prepared_payload
		)
	):
		_report_first_city_entry_failure(
			"GameSession could not install the prepared world into the founding settlement."
		)
		return null

	var bootstrap_result := _bootstrap_city_context(settlement_context)
	if not bool(bootstrap_result.get("success", false)):
		_report_first_city_entry_failure(
			"GameSession could not bootstrap the founding settlement: "
			+ str(bootstrap_result.get("errors", []))
		)
		return null

	return settlement_context


func _select_first_city_detailed_simulation_target() -> bool:
	var capital_settlement_id := (
		WorldPoliticalState.get_player_capital_settlement_id()
	)
	return (
		capital_settlement_id > 0
		and SimulationCoordinator.select_detailed_simulation_settlement(
			capital_settlement_id
		)
	)


func _synchronize_first_city_entry_foundation() -> bool:
	if (
		not WorldPoliticalState.synchronize_foundation_with_world_data()
		or not WorldPoliticalState.validate_registry_integrity()
	):
		return false

	var capital_settlement_id := (
		WorldPoliticalState.get_player_capital_settlement_id()
	)
	var capital_context = WorldPoliticalState.get_settlement_context(
		capital_settlement_id
	)
	return (
		capital_context != null
		and capital_context.supports_city_simulation()
		and capital_context.get_city_simulation_state() != null
	)


func _install_prepared_city_payload_for_context(
	settlement_context: SettlementSimulationContext,
	prepared_payload: Dictionary
) -> bool:
	if (
		settlement_context == null
		or not WorldPoliticalState.is_registered_settlement_context(
			settlement_context
		)
	):
		return false

	var city_state: CitySettlementSimulationState = (
		settlement_context.get_city_simulation_state()
	)
	if city_state == null:
		return false

	if prepared_payload.is_empty():
		return (
			city_state.city_world is WorldData
			and city_state.city_world.width > 0
			and city_state.city_world.height > 0
			and city_state.city_seed > 0
		)

	var prepared_world = prepared_payload.get("city_world")
	var prepared_seed_value = prepared_payload.get("city_seed")
	if (
		not prepared_world is WorldData
		or not prepared_seed_value is int
		or prepared_world.width <= 0
		or prepared_world.height <= 0
		or int(prepared_seed_value) <= 0
	):
		return false

	var prepared_seed: int = prepared_seed_value
	if prepared_world.seed != 0 and prepared_world.seed != prepared_seed:
		return false
	if (
		city_state.city_world != null
		and not is_same(city_state.city_world, prepared_world)
	):
		return false
	if city_state.city_seed != 0 and city_state.city_seed != prepared_seed:
		return false

	city_state.city_world = prepared_world
	city_state.city_seed = prepared_seed
	return true


func _bootstrap_city_context(
	settlement_context: SettlementSimulationContext
) -> Dictionary:
	return CitySettlementRuntimeBootstrapScript.ensure_ready(
		settlement_context
	)


func _commit_first_city_entry() -> void:
	if city_view_has_been_entered:
		return

	city_view_has_been_entered = true
	SimulationClock.start_new_game()
	SimulationClock.set_simulation_paused(true)
	_ensure_simulation_speed_controls()
	_hide_world_region_selection_after_city_entry()


func _restore_detailed_simulation_target(settlement_id: int) -> void:
	if settlement_id > 0:
		SimulationCoordinator.select_detailed_simulation_settlement(
			settlement_id
		)
	else:
		SimulationCoordinator.clear_detailed_simulation_settlement()


func _get_renderer_bound_context(lifecycle_owner: Node):
	if (
		lifecycle_owner != null
		and lifecycle_owner.has_method("get_bound_settlement_context")
	):
		return lifecycle_owner.call("get_bound_settlement_context")
	return null


func _report_first_city_entry_failure(message: String) -> void:
	push_error(message)


func _hide_world_region_selection_after_city_entry() -> void:
	if not city_view_has_been_entered or world_renderer == null:
		return

	# WorldRenderer owns this founding-only button. Once the persistent city view
	# has been entered, region selection is retired for the remainder of session.
	var region_selection_button = world_renderer.get("select_region_button")

	if region_selection_button is CanvasItem:
		(region_selection_button as CanvasItem).visible = false


func _ensure_simulation_speed_controls() -> void:
	if simulation_speed_controls != null:
		return

	simulation_speed_controls = SimulationSpeedControlsScript.new()
	simulation_speed_controls.name = "SimulationSpeedControls"
	add_child(simulation_speed_controls)


func _set_view_active(view: Node, is_active: bool) -> void:
	if view == null:
		return

	if view is CanvasItem:
		(view as CanvasItem).visible = is_active

	view.process_mode = (
		Node.PROCESS_MODE_INHERIT
		if is_active
		else Node.PROCESS_MODE_DISABLED
	)

	var lifecycle_owner := _find_view_lifecycle_owner(view)

	if lifecycle_owner != null:
		lifecycle_owner.call("set_session_view_active", is_active)


func _find_view_lifecycle_owner(view: Node) -> Node:
	if view.has_method("set_session_view_active"):
		return view

	for child in view.get_children():
		var owner := _find_view_lifecycle_owner(child)

		if owner != null:
			return owner

	return null


func _set_world_transition_pending(is_pending: bool) -> void:
	if world_renderer == null:
		return
	if world_renderer.has_method("set_city_transition_pending"):
		world_renderer.call("set_city_transition_pending", is_pending)
