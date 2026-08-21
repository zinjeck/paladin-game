extends Node

const SettlementInfrastructurePresenterScript := preload(
	"res://scripts/settlements/presentation/SettlementInfrastructurePresenter.gd"
)

var failure_count: int = 0


class InfrastructureDrawProbe:
	extends Node2D

	var presenter
	var completed_draw_count: int = 0


	func _draw() -> void:
		presenter.draw_completed_infrastructure(self)
		presenter.draw_ground_piles(self)
		completed_draw_count += 1


func _ready() -> void:
	await _test_exact_binding_high_water_and_presentation_purity()
	WorldData.reset_runtime_session_state()
	if failure_count > 0:
		push_error(
			"Settlement infrastructure presenter test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return
	print("Settlement infrastructure presenter test passed.")
	get_tree().quit(0)


func _test_exact_binding_high_water_and_presentation_purity() -> void:
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
	var binding_a_1 := CityPresentationBinding.new()
	var binding_b_1 := CityPresentationBinding.new()
	var binding_b_2 := CityPresentationBinding.new()
	var binding_a_3 := CityPresentationBinding.new()
	_expect(
		binding_a_1.rebind(context_a, 1)
		and binding_b_1.rebind(context_b, 1)
		and binding_b_2.rebind(context_b, 2)
		and binding_a_3.rebind(context_a, 3),
		"Every explicit presentation binding must be valid."
	)
	if not binding_a_1.is_valid() or not binding_b_2.is_valid():
		return

	var presenter = SettlementInfrastructurePresenterScript.new()
	_expect(
		presenter.can_bind_settlement_presentation(binding_a_1, 2)
		and presenter.highest_accepted_binding_generation == 0,
		"Binding preflight must be pure."
	)
	_expect(
		presenter.bind_settlement_presentation(binding_a_1, 2)
		and presenter.bind_settlement_presentation(binding_a_1, 2),
		"Generation 1 A must bind and remain exactly idempotent."
	)
	_expect(
		not presenter.can_bind_settlement_presentation(binding_b_1, 2)
		and not presenter.bind_settlement_presentation(binding_b_1, 2)
		and presenter.is_bound_to_settlement_presentation(binding_a_1),
		"Equal-generation B must be rejected without replacing A."
	)
	_expect(
		int(object_a.get("id", -1)) == int(object_b.get("id", -2))
		and object_a.get("top_left") != object_b.get("top_left"),
		"A/B must overlap local object IDs but retain distinct geometry."
	)

	var gameplay_before := _capture_gameplay_versions(state_a, state_b)
	_expect(
		WorldPoliticalState.set_active_settlement(context_b.settlement_id),
		"B may be globally active while infrastructure remains A-bound."
	)
	_expect(
		is_same(presenter.presentation_binding.settlement_state, state_a)
		and not is_same(presenter.presentation_binding.settlement_state, state_b),
		"Infrastructure reads must remain owned by exact binding A."
	)
	var probe := InfrastructureDrawProbe.new()
	probe.presenter = presenter
	add_child(probe)
	probe.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(
		probe.completed_draw_count > 0,
		"The exact A-bound infrastructure draw path must execute."
	)

	_expect(
		presenter.bind_settlement_presentation(binding_b_2, 2)
		and presenter.is_bound_to_settlement_presentation(binding_b_2),
		"A newer generation must rebind to exact settlement B."
	)
	_expect(
		not presenter.bind_settlement_presentation(binding_a_1, 2)
		and presenter.is_bound_to_settlement_presentation(binding_b_2),
		"Delayed generation 1 A must not replace generation 2 B."
	)
	_expect(
		WorldPoliticalState.set_active_settlement(context_a.settlement_id),
		"A may be globally active while infrastructure remains B-bound."
	)
	_expect(
		is_same(presenter.presentation_binding.settlement_state, state_b)
		and not is_same(presenter.presentation_binding.settlement_state, state_a),
		"Infrastructure reads must remain owned by exact binding B."
	)
	probe.queue_redraw()
	await get_tree().process_frame

	presenter.reset_presentation()
	_expect(
		presenter.presentation_binding == null
		and presenter.highest_accepted_binding_generation == 2
		and not presenter.bind_settlement_presentation(binding_b_2, 2)
		and presenter.bind_settlement_presentation(binding_a_3, 2),
		"Reset must clear presentation state without lowering its high-water mark."
	)
	probe.queue_redraw()
	await get_tree().process_frame
	_expect(
		_capture_gameplay_versions(state_a, state_b) == gameplay_before,
		"Bind, draw, rebind, and reset must never mutate settlement gameplay."
	)
	probe.queue_free()


func _capture_gameplay_versions(
	state_a: CitySettlementSimulationState,
	state_b: CitySettlementSimulationState
) -> Dictionary:
	return {
		"a_object": CityObjectSystem.get_city_object_version_for_city_state(
			state_a
		),
		"a_ground": state_a.logistics_state.ground_pile_version,
		"a_construction": state_a.construction_state.construction_version,
		"b_object": CityObjectSystem.get_city_object_version_for_city_state(
			state_b
		),
		"b_ground": state_b.logistics_state.ground_pile_version,
		"b_construction": state_b.construction_state.construction_version,
	}


func _create_two_settlement_fixture() -> Dictionary:
	var culture := WorldData.create_culture("Infrastructure Presenter Culture")
	var culture_id := int(culture.get("id", -1))
	var polity := WorldPoliticalState.create_polity({
		"name": "Infrastructure Presenter Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})
	var polity_id := int(polity.get("id", -1))
	var settlement_a := _create_settlement("Infrastructure A", polity_id, 2)
	var settlement_b := _create_settlement("Infrastructure B", polity_id, 4)
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
		421_001,
		Vector2i(1, 1)
	)
	var object_b := _seed_state(
		typed_state_b,
		settlement_b_id,
		421_002,
		Vector2i(9, 9)
	)
	var context_a = WorldPoliticalState.get_settlement_context(settlement_a_id)
	var context_b = WorldPoliticalState.get_settlement_context(settlement_b_id)
	if (
		object_a.is_empty()
		or object_b.is_empty()
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
	}


func _create_settlement(
	settlement_name: String,
	polity_id: int,
	region_coordinate: int
) -> Dictionary:
	var region_position := Vector2i(region_coordinate, region_coordinate)
	return WorldPoliticalState.create_settlement({
		"name": settlement_name,
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": polity_id,
		"world_region_top_left": region_position,
		"world_region_center": region_position,
		"world_region_size": 1,
		"simulation_backend_kind": (
			SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE
		),
	})


func _seed_state(
	state: CitySettlementSimulationState,
	settlement_id: int,
	seed_value: int,
	top_left: Vector2i
) -> Dictionary:
	state.city_world = _make_world(seed_value)
	state.city_seed = seed_value
	state.city_runtime_data = {
		"id": settlement_id,
		"name": "Infrastructure Fixture " + str(settlement_id),
		"founded": false,
		"can_build": false,
	}
	var settlement_object := (
		CityObjectSystem.register_completed_city_object_for_city_state(
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
	)
	if settlement_object.is_empty():
		return {}
	state.city_runtime_data.merge({
		"city_world_seed": seed_value,
		"city_map_size": Vector2i(16, 16),
		"foundation_top_left": settlement_object["top_left"],
		"foundation_size": settlement_object["size"],
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
	push_error("Settlement infrastructure presenter test: " + message)
