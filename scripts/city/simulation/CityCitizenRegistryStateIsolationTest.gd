extends Node

const SHARED_CITIZEN_TILE := Vector2i(5, 5)
const CityStateValidatorScript = preload(
	"res://scripts/city/simulation/CityStateValidator.gd"
)

var failure_count: int = 0


func _ready() -> void:
	_test_equal_version_city_isolation()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City citizen-registry isolation test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City citizen-registry isolation test passed.")
	get_tree().quit(0)


func _test_equal_version_city_isolation() -> void:
	WorldData.reset_runtime_session_state()
	var culture := WorldData.create_culture("Citizen Registry Isolation Culture")
	var culture_id := int(culture.get("id", -1))
	var polity := WorldPoliticalState.create_polity({
		"name": "Citizen Registry Isolation Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})
	var polity_id := int(polity.get("id", -1))
	var city_a := _create_city("Citizen Registry City A", polity_id, Vector2i(1, 1))
	var city_b := _create_city("Citizen Registry City B", polity_id, Vector2i(8, 8))
	_expect(
		not city_a.is_empty() and not city_b.is_empty(),
		"The fixture must create two instance-owned Cities."
	)
	if city_a.is_empty() or city_b.is_empty():
		return

	var city_a_id := int(city_a["id"])
	var city_b_id := int(city_b["id"])
	var state_a := _seed_city(city_a_id, culture_id, 97_101, CityCitizens.CITY_CITIZEN_SEX_MALE, 101)
	var state_b := _seed_city(city_b_id, culture_id, 97_202, CityCitizens.CITY_CITIZEN_SEX_FEMALE, 202)
	if state_a.is_empty() or state_b.is_empty():
		return

	_expect(
		int(state_a["citizen_id"]) == 1
		and int(state_b["citizen_id"]) == 1
		and int(state_a["registry_version"]) == 1
		and int(state_b["registry_version"]) == 1
		and int(state_a["next_id"]) == 2
		and int(state_b["next_id"]) == 2,
		"Both Cities must independently reuse citizen ID 1 and equal registry versions."
	)
	_expect(
		not is_same(state_a["registry_state"], state_b["registry_state"])
		and not is_same(state_a["citizens"], state_b["citizens"])
		and not is_same(state_a["index"], state_b["index"])
		and not is_same(state_a["spatial"], state_b["spatial"])
		and not is_same(state_a["movement_ids"], state_b["movement_ids"])
		and not is_same(state_a["task_ids"], state_b["task_ids"]),
		"Equal local IDs and versions must retain distinct mutable owners."
	)

	_expect(
		WorldPoliticalState.set_active_settlement(city_a_id)
		and _bind_fixture_city(city_a_id)
		and _matches_seeded_city(state_a),
		"B -> A must restore City A's exact registry and runtime owners."
	)
	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id)
		and _bind_fixture_city(city_b_id)
		and _matches_seeded_city(state_b),
		"A -> B must restore City B's exact registry and runtime owners."
	)
	_expect(
		WorldPoliticalState.set_active_settlement(city_a_id)
		and _bind_fixture_city(city_a_id)
		and _matches_seeded_city(state_a),
		"A -> B -> A must preserve City A despite equal IDs and versions."
	)

	var validation_a := CityStateValidatorScript.validate_for_settlement(
		WorldPoliticalState.get_settlement_context(city_a_id), true, false
	)
	var validation_b := CityStateValidatorScript.validate_for_settlement(
		WorldPoliticalState.get_settlement_context(city_b_id), true, false
	)
	_expect(
		int(validation_a.get("citizen_registry_state_instance_id", -1))
		== int(state_a["registry_state"].get_instance_id())
		and int(validation_b.get("citizen_registry_state_instance_id", -1))
		== int(state_b["registry_state"].get_instance_id())
		and int(validation_a.get("citizen_registry_state_instance_id", -1))
		!= int(validation_b.get("citizen_registry_state_instance_id", -1)),
		"Validation must remain keyed by exact registry owner identity."
	)


func _seed_city(
	city_id: int,
	culture_id: int,
	seed_value: int,
	sex: String,
	marker: int
) -> Dictionary:
	_expect(
		WorldPoliticalState.set_active_settlement(city_id)
		and _bind_fixture_city(city_id),
		"The seeded City must select presentation and bind its exact citizen owner."
	)
	if WorldPoliticalState.active_settlement_id != city_id:
		return {}
	WorldPoliticalState.set_current_city_world(_make_world(16, 16, seed_value))
	WorldPoliticalState.set_current_city_seed(seed_value)
	var citizen := CityCitizenRegistrySystem.add_city_citizen(
		"", SHARED_CITIZEN_TILE, sex, culture_id
	)
	var citizen_id := int(citizen.get("id", -1))
	if citizen_id != 1:
		_expect(false, "Each City must create its own local citizen 1.")
		return {}

	var registry_state := CityCitizenRegistrySystem.get_current_state()
	var spatial_state := CityCitizenSpatialSystem.get_current_state()
	var movement_state := CityCitizenMovementRuntimeSystem.get_current_state()
	var task_state := CityCitizenTaskRuntimeSystem.get_current_state()
	movement_state.active_mover_ids = [marker]
	movement_state.active_mover_id_lookup = {marker: true}
	movement_state.citizen_movement_visual_events = [{"marker": marker}]
	movement_state.citizen_movement_visual_tick_index = marker
	movement_state.citizen_movement_version = 11
	task_state.active_task_ids = [marker]
	task_state.active_task_id_lookup = {marker: true}
	task_state.citizen_task_version = 13
	CityAssignmentSystem.get_current_state().assignment_version = 15
	CityEmploymentSystem.get_current_state().workplace_version = 17

	return {
		"city_id": city_id,
		"citizen_id": citizen_id,
		"registry_state": registry_state,
		"citizens": registry_state.citizens,
		"index": registry_state.citizen_index_by_id,
		"registry_version": registry_state.citizen_version,
		"next_id": registry_state.next_citizen_id,
		"spatial": spatial_state.citizen_ids_by_tile,
		"movement_state": movement_state,
		"movement_ids": movement_state.active_mover_ids,
		"task_state": task_state,
		"task_ids": task_state.active_task_ids,
		"marker": marker,
		"sex": sex,
	}


func _matches_seeded_city(expected: Dictionary) -> bool:
	var marker := int(expected["marker"])
	var registry_state := CityCitizenRegistrySystem.get_current_state()
	var spatial_state := CityCitizenSpatialSystem.get_current_state()
	var movement_state := CityCitizenMovementRuntimeSystem.get_current_state()
	var task_state := CityCitizenTaskRuntimeSystem.get_current_state()
	return (
		is_same(registry_state, expected["registry_state"])
		and is_same(registry_state.citizens, expected["citizens"])
		and is_same(registry_state.citizen_index_by_id, expected["index"])
		and registry_state.citizen_version == int(expected["registry_version"])
		and registry_state.next_citizen_id == int(expected["next_id"])
		and is_same(spatial_state.citizen_ids_by_tile, expected["spatial"])
		and is_same(movement_state, expected["movement_state"])
		and is_same(movement_state.active_mover_ids, expected["movement_ids"])
		and movement_state.active_mover_id_lookup.get(marker, false)
		and movement_state.citizen_movement_version == 11
		and is_same(task_state, expected["task_state"])
		and is_same(task_state.active_task_ids, expected["task_ids"])
		and task_state.active_task_id_lookup.get(marker, false)
		and task_state.citizen_task_version == 13
		and CityAssignmentSystem.get_current_state().assignment_version == 15
		and CityEmploymentSystem.get_current_state().workplace_version == 17
		and str(registry_state.citizens[0].get("sex", "")) == str(expected["sex"])
		and spatial_state.citizen_ids_by_tile.get(SHARED_CITIZEN_TILE, []) == [1]
	)


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
	push_error("City citizen-registry isolation test: " + message)
