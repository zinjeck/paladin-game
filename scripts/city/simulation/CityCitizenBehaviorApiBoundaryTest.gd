extends Node

const TILE_A := Vector2i(2, 2)
const TILE_B := Vector2i(3, 2)

var failure_count: int = 0


func _ready() -> void:
	_test_focused_behavior_gateways_and_state_isolation()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City citizen behavior API boundary test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City citizen behavior API boundary test passed.")
	get_tree().quit(0)


func _test_focused_behavior_gateways_and_state_isolation() -> void:
	var fixture := _make_two_city_fixture()
	if fixture.is_empty():
		return

	var culture_id := int(fixture["culture_id"])
	var city_a_id := int(fixture["city_a_id"])
	var city_b_id := int(fixture["city_b_id"])
	var city_a := _exercise_city_gateways(city_a_id, culture_id, 98_101)
	var city_b := _exercise_city_gateways(city_b_id, culture_id, 98_202)
	if city_a.is_empty() or city_b.is_empty():
		return

	_expect(
		int(city_a["citizen_id"]) == 1
		and int(city_b["citizen_id"]) == 1
		and int(city_a["registry_version"])
		== int(city_b["registry_version"])
		and int(city_a["spatial_version"])
		== int(city_b["spatial_version"])
		and int(city_a["movement_version"])
		== int(city_b["movement_version"])
		and int(city_a["task_version"])
		== int(city_b["task_version"]),
		"Both Cities must independently reuse citizen ID and local versions."
	)
	_expect(
		not is_same(city_a["registry_state"], city_b["registry_state"])
		and not is_same(city_a["spatial_state"], city_b["spatial_state"])
		and not is_same(city_a["movement_state"], city_b["movement_state"])
		and not is_same(city_a["task_state"], city_b["task_state"]),
		"Equal local values must retain four distinct per-City state owners."
	)

	_expect(
		WorldPoliticalState.set_active_settlement(city_a_id)
		and _active_city_matches(city_a),
		"Switching B -> A must restore City A through focused gateways."
	)
	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id)
		and _active_city_matches(city_b),
		"Switching A -> B must restore City B through focused gateways."
	)
	_expect(
		WorldPoliticalState.set_active_settlement(city_a_id)
		and _active_city_matches(city_a),
		"A -> B -> A must restore City A despite equal IDs and versions."
	)


func _exercise_city_gateways(
	city_id: int,
	culture_id: int,
	seed_value: int
) -> Dictionary:
	_expect(
		WorldPoliticalState.set_active_settlement(city_id),
		"The City under test must become active."
	)
	var city_world := _make_world(16, 16, seed_value)
	WorldPoliticalState.set_current_city_world(city_world)
	WorldPoliticalState.set_current_city_seed(seed_value)

	var house := CityObjectSystem.add_city_object({
		"object_type": CityObjectCatalog.CITY_OBJECT_HOUSE,
		"top_left": Vector2i(8, 8),
		"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
			CityObjectCatalog.CITY_OBJECT_HOUSE
		),
		"object_owner": "player",
		"city_world": city_world,
	})
	var house_id := int(house.get("id", -1))
	var citizen := CityCitizenRegistrySystem.add_city_citizen(
		"",
		TILE_A,
		CityCitizens.CITY_CITIZEN_SEX_MALE,
		culture_id
	)
	var citizen_id := int(citizen.get("id", -1))
	var registry_state := CityCitizenRegistrySystem.get_current_state()
	var spatial_state := CityCitizenSpatialSystem.get_current_state()
	var movement_state := CityCitizenMovementRuntimeSystem.get_current_state()
	var task_state := CityCitizenTaskRuntimeSystem.get_current_state()

	_expect(
		house_id > 0
		and citizen_id == 1
		and CityCitizenRegistrySystem.get_city_citizen_index_by_id(citizen_id)
		== 0
		and int(
			CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id).get(
				"id",
				-1
			)
		) == citizen_id
		and CityCitizenSpatialSystem.get_city_citizen_ids_at_tile(TILE_A)
		== [citizen_id],
		"WorldData creation must register through focused lookup and spatial APIs."
	)

	var task_version_before := task_state.citizen_task_version
	_expect(
		CityAssignmentSystem.assign_city_citizen_home(citizen_id, house_id)
		and CityCitizenTaskRuntimeSystem.assign_city_citizen_task(citizen_id, {
			"kind": CityCitizens.CITY_CITIZEN_TASK_KIND_RETURN_HOME,
			"source": CityCitizens.CITY_CITIZEN_TASK_SOURCE_SCHEDULE,
			"priority": 50,
			"target_object_id": house_id,
		})
		and task_state.active_task_ids == [citizen_id]
		and task_state.citizen_task_version == task_version_before + 1
		and str(
			CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(
				citizen_id
			).get("kind", "")
		) == CityCitizens.CITY_CITIZEN_TASK_KIND_RETURN_HOME,
		"Task assignment must update the focused task registry exactly once."
	)
	_expect(
		CityCitizenTaskRuntimeSystem.clear_city_citizen_task(citizen_id)
		and task_state.active_task_ids.is_empty()
		and task_state.active_task_id_lookup.is_empty()
		and task_state.citizen_task_version == task_version_before + 2
		and str(
			CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(
				citizen_id
			).get("kind", "")
		) == CityCitizens.CITY_CITIZEN_TASK_KIND_NONE,
		"Task clearing must retire registry membership and invalidate once."
	)

	var movement_version_before := movement_state.citizen_movement_version
	var spatial_version_before := spatial_state.citizen_spatial_version
	_expect(
		CityCitizenMovementRuntimeSystem.assign_city_citizen_movement_order(
			citizen_id,
			[TILE_A, TILE_B]
		)
		and movement_state.active_mover_ids == [citizen_id]
		and movement_state.citizen_movement_version
		== movement_version_before + 1,
		"Movement assignment must register the mover through its focused API."
	)

	CitizenMovementSystem.run_tick(seed_value, 1)
	_expect(
		CityCitizenSpatialSystem.get_city_citizen_tile_position(citizen_id)
		== TILE_A
		and spatial_state.citizen_spatial_version == spatial_version_before
		and movement_state.citizen_movement_version
		== movement_version_before + 2,
		"A partial movement tick must not publish a false spatial change."
	)

	CitizenMovementSystem.run_tick(seed_value + 1, 1)
	_expect(
		CityCitizenSpatialSystem.get_city_citizen_tile_position(citizen_id)
		== TILE_B
		and CityCitizenSpatialSystem.get_city_citizen_ids_at_tile(TILE_A).is_empty()
		and CityCitizenSpatialSystem.get_city_citizen_ids_at_tile(TILE_B)
		== [citizen_id]
		and spatial_state.citizen_spatial_version == spatial_version_before + 1
		and movement_state.citizen_movement_version
		== movement_version_before + 3
		and movement_state.active_mover_ids.is_empty()
		and movement_state.active_mover_id_lookup.is_empty(),
		"A completed movement tick must commit citizen and spatial state atomically."
	)

	return {
		"citizen_id": citizen_id,
		"registry_state": registry_state,
		"spatial_state": spatial_state,
		"movement_state": movement_state,
		"task_state": task_state,
		"registry_version": registry_state.citizen_version,
		"spatial_version": spatial_state.citizen_spatial_version,
		"movement_version": movement_state.citizen_movement_version,
		"task_version": task_state.citizen_task_version,
	}


func _active_city_matches(expected: Dictionary) -> bool:
	var citizen_id := int(expected["citizen_id"])
	return (
		is_same(
			CityCitizenRegistrySystem.get_current_state(),
			expected["registry_state"]
		)
		and is_same(
			CityCitizenSpatialSystem.get_current_state(),
			expected["spatial_state"]
		)
		and is_same(
			CityCitizenMovementRuntimeSystem.get_current_state(),
			expected["movement_state"]
		)
		and is_same(
			CityCitizenTaskRuntimeSystem.get_current_state(),
			expected["task_state"]
		)
		and CityCitizenRegistrySystem.get_current_state().citizen_version
		== int(expected["registry_version"])
		and CityCitizenSpatialSystem.get_current_state().citizen_spatial_version
		== int(expected["spatial_version"])
		and (
			CityCitizenMovementRuntimeSystem.get_current_state()
			.citizen_movement_version
		) == int(expected["movement_version"])
		and CityCitizenTaskRuntimeSystem.get_current_state().citizen_task_version
		== int(expected["task_version"])
		and int(
			CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id).get(
				"id",
				-1
			)
		) == citizen_id
		and CityCitizenSpatialSystem.get_city_citizen_tile_position(citizen_id)
		== TILE_B
		and CityCitizenSpatialSystem.get_city_citizen_ids_at_tile(TILE_B)
		== [citizen_id]
		and CityCitizenMovementRuntimeSystem.get_current_state().active_mover_ids
		.is_empty()
		and CityCitizenTaskRuntimeSystem.get_current_state().active_task_ids
		.is_empty()
	)


func _make_two_city_fixture() -> Dictionary:
	WorldData.reset_runtime_session_state()
	var culture := WorldData.create_culture("Citizen API Boundary Culture")
	var culture_id := int(culture.get("id", -1))
	var polity := WorldPoliticalState.create_polity({
		"name": "Citizen API Boundary Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})
	var polity_id := int(polity.get("id", -1))
	var city_a := _create_city("Citizen API City A", polity_id, Vector2i(1, 1))
	var city_b := _create_city("Citizen API City B", polity_id, Vector2i(2, 2))
	if culture_id <= 0 or city_a.is_empty() or city_b.is_empty():
		_expect(false, "The two-City boundary fixture must be created.")
		return {}
	return {
		"culture_id": culture_id,
		"city_a_id": int(city_a["id"]),
		"city_b_id": int(city_b["id"]),
	}


func _create_city(
	city_name: String,
	polity_id: int,
	region_center: Vector2i
) -> Dictionary:
	return WorldPoliticalState.create_settlement({
		"name": city_name,
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": polity_id,
		"world_region_top_left": region_center,
		"world_region_center": region_center,
		"world_region_size": 1,
		"simulation_backend_kind": (
			SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE
		),
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
	push_error("City citizen behavior API boundary test: " + message)
