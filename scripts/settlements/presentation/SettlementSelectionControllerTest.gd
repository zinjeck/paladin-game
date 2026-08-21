extends Node

const SettlementSelectionControllerScript := preload(
	"res://scripts/settlements/presentation/SettlementSelectionController.gd"
)
const CityCitizenMovementPresentationScript := preload(
	"res://scripts/citizens/rendering/CityCitizenMovementPresentation.gd"
)

var failure_count: int = 0


func _ready() -> void:
	_test_binding_high_water_and_exact_settlement_isolation()
	WorldData.reset_runtime_session_state()
	if failure_count > 0:
		push_error(
			"Settlement selection controller test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return
	print("Settlement selection controller test passed.")
	get_tree().quit(0)


func _test_binding_high_water_and_exact_settlement_isolation() -> void:
	WorldData.reset_runtime_session_state()
	var fixture := _create_two_settlement_fixture()
	_expect(not fixture.is_empty(), "The exact A/B fixture must be created.")
	if fixture.is_empty():
		return

	var context_a: SettlementSimulationContext = fixture["context_a"]
	var context_b: SettlementSimulationContext = fixture["context_b"]
	var state_a: CitySettlementSimulationState = fixture["state_a"]
	var state_b: CitySettlementSimulationState = fixture["state_b"]
	var object_a: Dictionary = fixture["object_a"]
	var object_b: Dictionary = fixture["object_b"]
	var citizen_a: Dictionary = fixture["citizen_a"]
	var binding_a_1 := CityPresentationBinding.new()
	var binding_b_1 := CityPresentationBinding.new()
	var binding_b_2 := CityPresentationBinding.new()
	var binding_a_3 := CityPresentationBinding.new()
	_expect(
		binding_a_1.rebind(context_a, 1)
		and binding_b_1.rebind(context_b, 1)
		and binding_b_2.rebind(context_b, 2)
		and binding_a_3.rebind(context_a, 3),
		"Every explicit generation fixture must be valid."
	)
	if not binding_a_1.is_valid() or not binding_b_2.is_valid():
		return

	var controller = SettlementSelectionControllerScript.new()
	_expect(
		controller.bind_settlement_presentation(binding_a_1, 2),
		"Generation 1 must bind settlement A."
	)
	_expect(
		controller.bind_settlement_presentation(binding_a_1, 2),
		"An equal generation must be idempotent only for the same exact binding."
	)
	_expect(
		not controller.bind_settlement_presentation(binding_b_1, 2),
		"An equal-generation binding for settlement B must be rejected."
	)

	var wrong_movement: CityCitizenMovementPresentation = (
		CityCitizenMovementPresentationScript.new()
	)
	_expect(
		wrong_movement.bind_settlement_presentation(binding_b_1, 2),
		"The wrong-helper fixture must be explicitly bound to settlement B."
	)
	var citizen_a_id := int(citizen_a.get("id", -1))
	var citizen_a_tile: Vector2i = citizen_a.get(
		"city_tile_position",
		Vector2i(-1, -1)
	)
	# A same-local-ID B presenter would move A's marker far away if the
	# selection controller accepted it by shape instead of by exact binding.
	wrong_movement.visual_position_by_citizen_id[citizen_a_id] = Vector2(1, 14)
	var citizen_a_center := Vector2(
		(float(citizen_a_tile.x) + 0.5) * 2.0,
		(float(citizen_a_tile.y) + 0.5) * 2.0
	)
	var citizen_ids_with_wrong_helper := (
		controller.get_selectable_settlement_citizen_ids_at_world_point(
			citizen_a_tile,
			citizen_a_center,
			wrong_movement
		)
	)
	_expect(
		citizen_ids_with_wrong_helper == [citizen_a_id],
		"A correctly typed helper for the wrong binding must be a no-op; "
		+ "selection must fall back to exact A-owned citizen geometry."
	)

	_expect(
		WorldPoliticalState.set_active_settlement(context_b.settlement_id),
		"B may be globally active while the controller remains explicitly A-bound."
	)
	var overlapping_object_id := int(object_a.get("id", -1))
	_expect(
		overlapping_object_id == int(object_b.get("id", -2)),
		"The A/B fixture must overlap object IDs to expose cross-state reads."
	)
	var resolved_a := controller.get_settlement_object_by_id(
		overlapping_object_id
	)
	_expect(
		resolved_a.get("top_left") == object_a.get("top_left")
		and resolved_a.get("top_left") != object_b.get("top_left"),
		"A-bound reads must ignore globally active B despite the overlapping ID."
	)
	controller.update_hovered_settlement_tile(object_a["top_left"])
	controller.set_selected_settlement_object(overlapping_object_id)
	controller.begin_selection_drag(Vector2(2, 2), Vector2(2, 2))

	var object_count_a := CityObjectSystem.get_city_objects_for_city_state(
		state_a
	).size()
	var object_count_b := CityObjectSystem.get_city_objects_for_city_state(
		state_b
	).size()
	_expect(
		controller.bind_settlement_presentation(binding_b_2, 2),
		"A newer generation must rebind to exact settlement B."
	)
	_expect(
		controller.is_interaction_state_clear(),
		"A/B rebind must clear hover, selection, and drag presentation state."
	)
	_expect(
		not controller.bind_settlement_presentation(binding_a_1, 2),
		"Delayed generation 1 must be rejected after generation 2."
	)
	_expect(
		WorldPoliticalState.set_active_settlement(context_a.settlement_id),
		"A may be globally active while the controller remains explicitly B-bound."
	)
	var resolved_b := controller.get_settlement_object_by_id(
		overlapping_object_id
	)
	_expect(
		resolved_b.get("top_left") == object_b.get("top_left")
		and resolved_b.get("top_left") != object_a.get("top_left"),
		"B-bound reads must ignore globally active A despite the overlapping ID."
	)
	var object_b_center := Vector2(object_b["top_left"] * 2) + Vector2.ONE
	var selection_result := controller.select_settlement_entity_at_world_point(
		object_b_center
	)
	_expect(
		str(selection_result.get("current_kind", ""))
		== SettlementSelectionControllerScript.SELECTION_KIND_OBJECT
		and int(selection_result.get("current_id", -1))
		== overlapping_object_id,
		"Point hit-testing must select only the B-bound object."
	)

	controller.reset_presentation()
	_expect(
		not controller.bind_settlement_presentation(binding_b_2, 2),
		"Reset must preserve the generation high-water mark."
	)
	_expect(
		controller.bind_settlement_presentation(binding_a_3, 2)
		and controller.bind_settlement_presentation(binding_a_3, 2),
		"A newer A generation must bind and remain exactly idempotent."
	)
	_expect(
		CityObjectSystem.get_city_objects_for_city_state(state_a).size()
		== object_count_a
		and CityObjectSystem.get_city_objects_for_city_state(state_b).size()
		== object_count_b,
		"Rebind, reset, hover, drag, and selection must never mutate gameplay."
	)


func _create_two_settlement_fixture() -> Dictionary:
	var culture := WorldData.create_culture("Selection Controller Culture")
	var culture_id := int(culture.get("id", -1))
	var polity := WorldPoliticalState.create_polity({
		"name": "Selection Controller Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})
	var polity_id := int(polity.get("id", -1))
	var settlement_a := _create_settlement(
		"Selection A",
		polity_id,
		Vector2i(2, 2)
	)
	var settlement_b := _create_settlement(
		"Selection B",
		polity_id,
		Vector2i(4, 4)
	)
	var settlement_a_id := int(settlement_a.get("id", -1))
	var settlement_b_id := int(settlement_b.get("id", -1))
	var state_a = WorldPoliticalState.get_city_simulation_state(settlement_a_id)
	var state_b = WorldPoliticalState.get_city_simulation_state(settlement_b_id)
	if (
		culture_id <= 0
		or polity_id <= 0
		or not state_a is CitySettlementSimulationState
		or not state_b is CitySettlementSimulationState
	):
		return {}

	var typed_state_a: CitySettlementSimulationState = state_a
	var typed_state_b: CitySettlementSimulationState = state_b
	var object_a := _seed_state(
		typed_state_a,
		settlement_a_id,
		culture_id,
		111_001,
		Vector2i(1, 1)
	)
	var object_b := _seed_state(
		typed_state_b,
		settlement_b_id,
		culture_id,
		111_002,
		Vector2i(9, 9)
	)
	var citizen_a := CityCitizenRegistrySystem.add_city_citizen_for_city_state(
		typed_state_a,
		"",
		Vector2i(14, 2),
		CityCitizens.CITY_CITIZEN_SEX_FEMALE,
		culture_id
	)
	var citizen_b := CityCitizenRegistrySystem.add_city_citizen_for_city_state(
		typed_state_b,
		"",
		Vector2i(2, 14),
		CityCitizens.CITY_CITIZEN_SEX_MALE,
		culture_id
	)
	var context_a = WorldPoliticalState.get_settlement_context(settlement_a_id)
	var context_b = WorldPoliticalState.get_settlement_context(settlement_b_id)
	if object_a.is_empty():
		push_error("Selection fixture could not register object A.")
	if object_b.is_empty():
		push_error("Selection fixture could not register object B.")
	if not context_a is SettlementSimulationContext:
		push_error("Selection fixture could not resolve context A.")
	if not context_b is SettlementSimulationContext:
		push_error("Selection fixture could not resolve context B.")
	if (
		object_a.is_empty()
		or object_b.is_empty()
		or citizen_a.is_empty()
		or citizen_b.is_empty()
		or not context_a is SettlementSimulationContext
		or not context_b is SettlementSimulationContext
	):
		return {}
	return {
		"context_a": context_a,
		"context_b": context_b,
		"state_a": typed_state_a,
		"state_b": typed_state_b,
		"object_a": object_a,
		"object_b": object_b,
		"citizen_a": citizen_a,
		"citizen_b": citizen_b,
	}


func _create_settlement(
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


func _seed_state(
	state: CitySettlementSimulationState,
	settlement_id: int,
	culture_id: int,
	seed_value: int,
	top_left: Vector2i
) -> Dictionary:
	state.city_world = _make_world(seed_value)
	state.city_seed = seed_value
	state.city_runtime_data = {
		"id": settlement_id,
		"name": "Selection Fixture " + str(settlement_id),
		"primary_culture_id": culture_id,
		"founded": false,
		"can_build": false,
	}
	var settlement_object := CityObjectSystem.register_completed_city_object_for_city_state(
		state,
		{
			"object_type": CityObjectCatalog.CITY_OBJECT_CITY_CENTER,
			"top_left": top_left,
			"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
				CityObjectCatalog.CITY_OBJECT_CITY_CENTER
			),
			"object_owner": "player",
		}
	)
	if settlement_object.is_empty():
		return {}
	state.city_runtime_data.merge({
		"city_world_seed": seed_value,
		"city_map_size": Vector2i(16, 16),
		"foundation_top_left": settlement_object.get("top_left", Vector2i(-1, -1)),
		"foundation_size": settlement_object.get("size", Vector2i.ZERO),
		"foundation_object_id": int(settlement_object.get("id", -1)),
		"foundation_object_owner": str(settlement_object.get("owner", "")),
		"founded": true,
		"can_build": true,
	}, true)
	return settlement_object


func _make_world(seed_value: int) -> WorldData:
	var world := WorldData.new()
	world.setup(16, 16, seed_value)
	for y in range(world.height):
		for x in range(world.width):
			world.tiles[y][x] = {
				"fertility": 50.0,
				"elevation": 0.2,
				"temperature": 0.5,
				"precipitation": 0.5,
				"terrain": WorldData.TERRAIN_LAND,
				"biome": WorldData.BIOME_PLAIN,
				"resource": WorldData.RESOURCE_NONE,
				"is_land": true,
			}
	world.mark_tile_data_changed()
	return world


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error("Settlement selection controller test: " + message)
