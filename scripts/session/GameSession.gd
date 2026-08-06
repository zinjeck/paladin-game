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

	if not pending_city_switch:
		return

	var signature := str(pending_city_request.get("signature", ""))
	var payload := city_preparation.take_completed_payload(signature)

	if payload.is_empty():
		if city_preparation.take_failure(signature):
			pending_city_switch = false
			_set_world_transition_pending(false)
			push_error(
				"Background city preparation failed; falling back to "
				+ "synchronous city initialization."
			)
			_ensure_city_view({})
			_activate_view(city_view)

		return

	pending_city_switch = false
	_set_world_transition_pending(false)
	_ensure_city_view(payload)
	_activate_view(city_view)


func _exit_tree() -> void:
	city_preparation.shutdown()


func _enter_requested_initial_city_view() -> void:
	if not is_inside_tree():
		return

	show_city_view()


func prepare_city_view(request: Dictionary) -> void:
	if city_view != null or WorldData.has_active_city_save():
		return

	city_preparation.request_preparation(request)


func cancel_city_preparation() -> void:
	pending_city_switch = false
	pending_city_request.clear()
	_set_world_transition_pending(false)
	city_preparation.cancel_pending_requests()


func show_city_view(request: Dictionary = {}) -> void:
	if city_view != null:
		_activate_view(city_view)
		return

	if WorldData.has_active_city_save():
		_ensure_city_view({})
		_activate_view(city_view)
		return

	if request.is_empty() and world_renderer != null:
		if world_renderer.has_method("build_city_preparation_request"):
			request = world_renderer.call("build_city_preparation_request")

	if not city_preparation.is_valid_request(request):
		push_error("GameSession cannot enter the city without a valid preparation request.")
		return

	var signature := str(request["signature"])
	var payload := city_preparation.take_completed_payload(signature)

	if not payload.is_empty():
		_ensure_city_view(payload)
		_activate_view(city_view)
		return

	pending_city_request = request.duplicate(true)
	pending_city_switch = true
	_set_world_transition_pending(true)
	city_preparation.request_preparation(request)


func show_world_view() -> void:
	pending_city_switch = false
	pending_city_request.clear()
	_set_world_transition_pending(false)
	_hide_world_region_selection_after_city_entry()
	_activate_view(world_view)


func _ensure_city_view(prepared_payload: Dictionary) -> void:
	if city_view != null:
		return

	# Establish the authoritative new-city clock before the expensive renderer
	# enters the tree. No hidden initialization frame may consume settlement time.
	_prepare_first_city_entry()
	city_view = CITY_SCENE.instantiate()

	if city_view.has_method("set_session_prepared_city_payload"):
		city_view.call(
			"set_session_prepared_city_payload",
			prepared_payload
		)

	if city_view.has_method("set_session_view_active"):
		city_view.call("set_session_view_active", false)
	else:
		city_view.visible = false
		city_view.process_mode = Node.PROCESS_MODE_DISABLED

	add_child(city_view)
	_set_view_active(city_view, false)


func _activate_view(target_view: Node) -> void:
	if target_view == null:
		return

	if target_view == city_view:
		_prepare_first_city_entry()

	if target_view == active_view:
		return

	_set_view_active(active_view, false)
	_set_view_active(target_view, true)
	active_view = target_view


func _prepare_first_city_entry() -> void:
	if city_view_has_been_entered:
		return

	city_view_has_been_entered = true
	SimulationClock.start_new_game()
	SimulationClock.set_simulation_paused(true)
	_ensure_simulation_speed_controls()
	_hide_world_region_selection_after_city_entry()


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
