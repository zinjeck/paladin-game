extends Node

const SHARED_CITIZEN_TILE := Vector2i(5, 5)
const CITY_A_TILE := Vector2i(6, 5)
const CITY_B_TILE := Vector2i(5, 6)
const CityStateValidatorScript = preload(
	"res://scripts/city/simulation/CityStateValidator.gd"
)

var failure_count: int = 0


func _ready() -> void:
	_test_equal_version_city_isolation()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City citizen-spatial isolation test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City citizen-spatial isolation test passed.")
	get_tree().quit(0)


func _test_equal_version_city_isolation() -> void:
	WorldData.reset_runtime_session_state()
	var culture := WorldData.create_culture("Citizen Spatial Isolation Culture")
	var culture_id := int(culture.get("id", -1))
	var polity := WorldPoliticalState.create_polity({
		"name": "Citizen Spatial Isolation Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})
	var polity_id := int(polity.get("id", -1))
	var city_a := _create_city("Citizen Spatial City A", polity_id, Vector2i(1, 1))
	var city_b := _create_city("Citizen Spatial City B", polity_id, Vector2i(8, 8))
	if city_a.is_empty() or city_b.is_empty():
		_expect(false, "The fixture must create two Cities.")
		return

	var city_a_id := int(city_a["id"])
	var city_b_id := int(city_b["id"])
	var state_a := _seed_city(city_a_id, culture_id, 96_101, CITY_A_TILE)
	var state_b := _seed_city(city_b_id, culture_id, 96_202, CITY_B_TILE)
	if state_a.is_empty() or state_b.is_empty():
		return

	var spatial_a: CityCitizenSpatialState = state_a["spatial_state"]
	var spatial_b: CityCitizenSpatialState = state_b["spatial_state"]
	spatial_a.citizen_spatial_version = 9
	spatial_b.citizen_spatial_version = 9

	_expect(
		int(state_a["citizen_id"]) == 1
		and int(state_b["citizen_id"]) == 1
		and spatial_a.citizen_spatial_version == spatial_b.citizen_spatial_version
		and not is_same(spatial_a, spatial_b)
		and not is_same(spatial_a.citizen_ids_by_tile, spatial_b.citizen_ids_by_tile),
		"Equal citizen IDs and versions must retain distinct spatial owners."
	)
	_expect(
		spatial_a.citizen_ids_by_tile.get(CITY_A_TILE, []) == [1]
		and spatial_b.citizen_ids_by_tile.get(CITY_B_TILE, []) == [1]
		and spatial_a.citizen_ids_by_tile.get(CITY_B_TILE, []).is_empty()
		and spatial_b.citizen_ids_by_tile.get(CITY_A_TILE, []).is_empty(),
		"Each City must index citizen 1 only at its own local tile."
	)

	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id)
		and _bind_fixture_city(city_a_id)
		and CityCitizenSpatialSystem.get_city_citizen_tile_position(1) == CITY_A_TILE
		and is_same(CityCitizenSpatialSystem.get_current_state(), spatial_a),
		"An explicit City A citizen binding must ignore presentation selection B."
	)
	_expect(
		_bind_fixture_city(city_b_id)
		and CityCitizenSpatialSystem.get_city_citizen_tile_position(1) == CITY_B_TILE
		and is_same(CityCitizenSpatialSystem.get_current_state(), spatial_b),
		"Binding City B must restore its exact equal-ID spatial state."
	)
	_expect(
		_bind_fixture_city(city_a_id)
		and CityCitizenSpatialSystem.get_city_citizen_tile_position(1) == CITY_A_TILE
		and spatial_a.citizen_spatial_version == 9,
		"A -> B -> A must preserve City A's spatial continuation."
	)

	var validation_a := CityStateValidatorScript.validate_for_settlement(
		WorldPoliticalState.get_settlement_context(city_a_id), true, false
	)
	var validation_b := CityStateValidatorScript.validate_for_settlement(
		WorldPoliticalState.get_settlement_context(city_b_id), true, false
	)
	_expect(
		int(validation_a.get("citizen_spatial_state_instance_id", -1))
		== int(spatial_a.get_instance_id())
		and int(validation_b.get("citizen_spatial_state_instance_id", -1))
		== int(spatial_b.get_instance_id())
		and int(validation_a.get("citizen_spatial_state_instance_id", -1))
		!= int(validation_b.get("citizen_spatial_state_instance_id", -1)),
		"Validator caches must distinguish equal-version spatial owners."
	)


func _seed_city(
	city_id: int,
	culture_id: int,
	seed_value: int,
	target_tile: Vector2i
) -> Dictionary:
	_expect(
		WorldPoliticalState.set_active_settlement(city_id)
		and _bind_fixture_city(city_id),
		"The seeded City must select presentation and bind its citizen owner."
	)
	var city_state = WorldPoliticalState.get_city_simulation_state(city_id)
	if not city_state is CitySettlementSimulationState:
		return {}
	var city_world := _make_world(16, 16, seed_value)
	WorldPoliticalState.set_current_city_world(city_world)
	WorldPoliticalState.set_current_city_seed(seed_value)
	var citizen := CityCitizenRegistrySystem.add_city_citizen(
		"",
		SHARED_CITIZEN_TILE,
		CityCitizens.CITY_CITIZEN_SEX_MALE,
		culture_id
	)
	var citizen_id := int(citizen.get("id", -1))
	if citizen_id != 1:
		_expect(false, "Each City must create local citizen 1.")
		return {}
	_expect(
		CityCitizenSpatialSystem.set_city_citizen_tile_position_for_city_state(
			city_state,
			city_world,
			citizen_id,
			target_tile
		),
		"The explicit fixture must move citizen 1 into its City-local spatial slot."
	)
	return {
		"citizen_id": citizen_id,
		"spatial_state": CityCitizenSpatialSystem.get_current_state(),
	}


func _bind_fixture_city(city_id: int) -> bool:
	var city_state = WorldPoliticalState.get_city_simulation_state(city_id)
	if not city_state is CitySettlementSimulationState:
		return false
	CityCitizenUnboundCompatibility.bind_legacy_fixture_state(city_state)
	return true


func _create_city(city_name: String, polity_id: int, region_center: Vector2i) -> Dictionary:
	return WorldPoliticalState.create_settlement({
		"name": city_name,
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": polity_id,
		"world_region_top_left": region_center,
		"world_region_center": region_center,
		"world_region_size": 1,
		"simulation_backend_kind": SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE,
	})


func _make_world(width: int, height: int, seed_value: int) -> WorldData:
	var world := WorldData.new()
	world.setup(width, height, seed_value)
	for y in range(height):
		for x in range(width):
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
	push_error("City citizen-spatial isolation test: " + message)
