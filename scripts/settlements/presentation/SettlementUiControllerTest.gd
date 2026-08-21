extends Node

const WORLD_SIZE := Vector2i(20, 20)
const TILE_SIZE := 2
const SEED_A := 439_001
const SEED_B := 439_002
const SettlementPlacementControllerScript := preload(
	"res://scripts/settlements/presentation/SettlementPlacementController.gd"
)
const SettlementSelectionControllerScript := preload(
	"res://scripts/settlements/presentation/SettlementSelectionController.gd"
)
const SettlementCommandControllerScript := preload(
	"res://scripts/settlements/presentation/SettlementCommandController.gd"
)
const SettlementUiControllerScript := preload(
	"res://scripts/settlements/presentation/SettlementUiController.gd"
)

var failure_count: int = 0


class UiActionHarness:
	extends RefCounted

	var ready_modes: Dictionary = {}
	var applied_modes: Array[int] = []
	var back_count: int = 0
	var presentation_changes: Array[Dictionary] = []


	func is_map_mode_ready(mode: int) -> bool:
		return bool(ready_modes.get(mode, false))


	func apply_map_mode(mode: int) -> void:
		applied_modes.append(mode)


	func back() -> void:
		back_count += 1


	func present_ui_change(
		change_kind: String,
		payload: Variant = null
	) -> void:
		presentation_changes.append({
			"kind": change_kind,
			"payload": payload,
		})


func _ready() -> void:
	_test_exact_binding_actions_and_layout()
	WorldData.reset_runtime_session_state()
	if failure_count > 0:
		push_error(
			"Settlement UI controller test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return
	print("Settlement UI controller test passed.")
	get_tree().quit(0)


func _test_exact_binding_actions_and_layout() -> void:
	WorldData.reset_runtime_session_state()
	var fixture := _create_fixture()
	_expect(not fixture.is_empty(), "The registered A/B fixture must exist.")
	if fixture.is_empty():
		return

	var context_a: SettlementSimulationContext = fixture["context_a"]
	var context_b: SettlementSimulationContext = fixture["context_b"]
	var state_a: CitySettlementSimulationState = fixture["state_a"]
	var state_b: CitySettlementSimulationState = fixture["state_b"]
	var binding_a := CityPresentationBinding.new()
	var binding_b_equal := CityPresentationBinding.new()
	var binding_b := CityPresentationBinding.new()
	_expect(
		binding_a.rebind(context_a, 1)
		and binding_b_equal.rebind(context_b, 1)
		and binding_b.rebind(context_b, 2),
		"A1, B1, and B2 bindings must be valid."
	)

	var placement = SettlementPlacementControllerScript.new()
	var selection = SettlementSelectionControllerScript.new()
	var command = SettlementCommandControllerScript.new()
	var controller = SettlementUiControllerScript.new()
	_expect(
		placement.bind_settlement_presentation(binding_a, TILE_SIZE)
		and selection.bind_settlement_presentation(binding_a, TILE_SIZE)
		and command.bind_settlement_presentation(binding_a, TILE_SIZE)
		and controller.can_bind_settlement_presentation(binding_a)
		and controller.bind_settlement_presentation(binding_a)
		and controller.bind_settlement_presentation(binding_a),
		"The exact A1 binding must be pure and idempotent."
	)
	_expect(
		not controller.can_bind_settlement_presentation(binding_b_equal)
		and not controller.bind_settlement_presentation(binding_b_equal)
		and controller.is_bound_to_settlement_presentation(binding_a),
		"A different settlement at generation one must be rejected."
	)

	var harness := UiActionHarness.new()
	for mode in MapVisuals.get_all_view_modes():
		harness.ready_modes[mode] = true
	var ui_parent := Control.new()
	add_child(ui_parent)
	var gameplay_before := _capture_gameplay(state_a, state_b)
	_expect(
		controller.setup(
			ui_parent,
			placement,
			selection,
			command,
			{
				"is_map_mode_ready": Callable(
					harness,
					"is_map_mode_ready"
				),
				"apply_map_mode": Callable(harness, "apply_map_mode"),
				"back": Callable(harness, "back"),
				"present_ui_change": Callable(
					harness,
					"present_ui_change"
				),
			}
		)
		and controller.create_overlay_chrome(),
		"Chrome setup must accept only the three narrow controllers and four callbacks."
	)

	var viewport_size := Vector2(800.0, 600.0)
	controller.layout(viewport_size)
	_expect(
		controller.bottom_buttons.size() == 6
		and controller.get_bottom_button_for_slot(1).position
		== Vector2(226.0, 542.0)
		and controller.get_bottom_button_for_slot(6).position
		== Vector2(516.0, 542.0)
		and controller.back_button.position == Vector2(720.0, 538.0)
		and controller.resource_bar.position.y == 0.0
		and is_equal_approx(
			controller.resource_bar.position.x
			+ controller.resource_bar.size.x,
			viewport_size.x
		),
		"Bottom slots, resource bar, and back button must preserve viewport layout."
	)

	controller.get_bottom_button_for_slot(3).pressed.emit()
	_expect(
		controller.has_open_object_menu()
		and not controller.is_build_menu_open()
		and not controller.map_menu_open,
		"An object option must exclusively own the open popup slot."
	)
	controller.get_bottom_button_for_slot(2).pressed.emit()
	_expect(
		controller.is_build_menu_open()
		and not controller.has_open_object_menu()
		and not controller.map_menu_open,
		"The build menu must close object and map menus."
	)
	controller.maps_button.pressed.emit()
	_expect(
		controller.map_menu_open
		and not controller.is_build_menu_open()
		and not controller.has_open_object_menu(),
		"The map menu must close build and object menus."
	)
	controller.get_bottom_button_for_slot(6).pressed.emit()
	_expect(
		command.menu_open
		and controller.command_chop_trees_button.visible
		and not controller.map_menu_open
		and not controller.is_build_menu_open()
		and not controller.has_open_object_menu(),
		"Command chrome must be exclusive while command state remains controller-owned."
	)

	var next_mode := MapVisuals.ViewMode.RESOURCES
	controller.map_mode_buttons[
		MapVisuals.get_all_view_modes().find(next_mode)
	].pressed.emit()
	controller.back_button.pressed.emit()
	_expect(
		controller.view_mode == next_mode
		and harness.applied_modes == [next_mode]
		and harness.back_count == 1,
		"Map and back buttons must invoke their narrow facade callbacks exactly once."
	)
	_expect(
		_capture_gameplay(state_a, state_b) == gameplay_before,
		"Layout and all menu actions must be presentation-pure."
	)

	_expect(
		placement.bind_settlement_presentation(binding_b, TILE_SIZE)
		and selection.bind_settlement_presentation(binding_b, TILE_SIZE)
		and command.bind_settlement_presentation(binding_b, TILE_SIZE)
		and controller.bind_settlement_presentation(binding_b)
		and controller.is_interaction_state_clear()
		and not controller.bind_settlement_presentation(binding_a)
		and controller.is_bound_to_settlement_presentation(binding_b),
		"A1 to B2 must clear chrome and reject stale A1 without gameplay mutation."
	)
	controller.reset_presentation()
	var binding_a_new := CityPresentationBinding.new()
	_expect(
		controller.highest_accepted_binding_generation == 2
		and not controller.bind_settlement_presentation(binding_b)
		and binding_a_new.rebind(context_a, 3)
		and placement.bind_settlement_presentation(binding_a_new, TILE_SIZE)
		and selection.bind_settlement_presentation(binding_a_new, TILE_SIZE)
		and command.bind_settlement_presentation(binding_a_new, TILE_SIZE)
		and controller.bind_settlement_presentation(binding_a_new)
		and controller.is_bound_to_settlement_presentation(binding_a_new)
		and _capture_gameplay(state_a, state_b) == gameplay_before,
		"Reset must preserve the generation high-water and remain presentation-pure."
	)
	ui_parent.queue_free()


func _create_fixture() -> Dictionary:
	var culture := WorldData.create_culture("Settlement UI Culture")
	var culture_id := int(culture.get("id", CultureData.INVALID_CULTURE_ID))
	var polity := WorldPoliticalState.create_polity({
		"name": "Settlement UI Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})
	var polity_id := int(polity.get("id", PolityData.INVALID_POLITY_ID))
	var settlement_a := _create_city("UI A", polity_id, Vector2i(2, 2))
	var settlement_b := _create_city("UI B", polity_id, Vector2i(5, 5))
	var settlement_a_id := int(
		settlement_a.get("id", SettlementData.INVALID_SETTLEMENT_ID)
	)
	var settlement_b_id := int(
		settlement_b.get("id", SettlementData.INVALID_SETTLEMENT_ID)
	)
	if culture_id <= 0 or settlement_a_id <= 0 or settlement_b_id <= 0:
		return {}
	if (
		not WorldPoliticalState.store_city_world_for_settlement(
			settlement_a_id,
			_make_world(SEED_A),
			SEED_A
		)
		or not WorldPoliticalState.store_city_world_for_settlement(
			settlement_b_id,
			_make_world(SEED_B),
			SEED_B
		)
	):
		return {}
	var context_a: SettlementSimulationContext = (
		WorldPoliticalState.get_settlement_context(settlement_a_id)
	)
	var context_b: SettlementSimulationContext = (
		WorldPoliticalState.get_settlement_context(settlement_b_id)
	)
	if context_a == null or context_b == null:
		return {}
	if (
		not _found_context(context_a)
		or not _found_context(context_b)
	):
		return {}
	return {
		"context_a": context_a,
		"context_b": context_b,
		"state_a": context_a.get_detailed_simulation_state(),
		"state_b": context_b.get_detailed_simulation_state(),
	}


func _create_city(
	settlement_name: String,
	polity_id: int,
	region_center: Vector2i
) -> Dictionary:
	return WorldPoliticalState.create_settlement({
		"name": settlement_name,
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": polity_id,
		"world_region_top_left": region_center,
		"world_region_center": region_center,
		"world_region_size": 1,
		"simulation_backend_kind": (
			SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE
		),
	})


func _make_world(seed_value: int) -> WorldData:
	var world := WorldData.new()
	world.setup(WORLD_SIZE.x, WORLD_SIZE.y, seed_value)
	for y in range(world.height):
		for x in range(world.width):
			world.set_tile_terrain(Vector2i(x, y), WorldData.TERRAIN_LAND)
	return world


func _found_context(context: SettlementSimulationContext) -> bool:
	var state: CitySettlementSimulationState = (
		context.get_detailed_simulation_state()
	)
	if state == null:
		return false
	var keep := CityObjectSystem.place_immediate_settlement_object_for_context(
		context,
		{
			"object_type": CityObjectCatalog.CITY_OBJECT_CITY_CENTER,
			"top_left": Vector2i(2, 2),
			"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
				CityObjectCatalog.CITY_OBJECT_CITY_CENTER
			),
			"object_owner": "player",
			"settlement_world": state.city_world,
			"settlement_seed": state.city_seed,
		}
	)
	return not keep.is_empty() and state.is_city_founded()


func _capture_gameplay(
	state_a: CitySettlementSimulationState,
	state_b: CitySettlementSimulationState
) -> Dictionary:
	return {
		"a_objects": state_a.object_state.objects.duplicate(true),
		"a_object_version": state_a.object_state.object_version,
		"a_sites": state_a.construction_state.construction_sites.duplicate(true),
		"a_construction_version": (
			state_a.construction_state.construction_version
		),
		"a_commands": state_a.work_state.player_commands.duplicate(true),
		"a_command_version": state_a.work_state.player_command_version,
		"b_objects": state_b.object_state.objects.duplicate(true),
		"b_object_version": state_b.object_state.object_version,
		"b_sites": state_b.construction_state.construction_sites.duplicate(true),
		"b_construction_version": (
			state_b.construction_state.construction_version
		),
		"b_commands": state_b.work_state.player_commands.duplicate(true),
		"b_command_version": state_b.work_state.player_command_version,
	}


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error("SettlementUiControllerTest: " + message)
