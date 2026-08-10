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
	var city_a := _create_city(
		"Citizen Spatial City A",
		polity_id,
		Vector2i(1, 1)
	)
	var city_b := _create_city(
		"Citizen Spatial City B",
		polity_id,
		Vector2i(8, 8)
	)
	_expect(
		not city_a.is_empty() and not city_b.is_empty(),
		"The fixture must create two instance-owned Cities."
	)
	if city_a.is_empty() or city_b.is_empty():
		return

	var city_a_id := int(city_a["id"])
	var city_b_id := int(city_b["id"])
	_expect(
		WorldPoliticalState.set_active_settlement(city_a_id),
		"City A must become active."
	)
	WorldData.official_city_world = _make_world(16, 16, 100_101)
	WorldData.official_city_seed = 100_101
	var citizen_a := WorldData.add_city_citizen(
		"",
		SHARED_CITIZEN_TILE,
		WorldData.CITY_CITIZEN_SEX_MALE,
		culture_id
	)
	var registry_a := (
		CityCitizenRegistrySystem.get_current_state()
	)
	var spatial_state_a := (
		CityCitizenSpatialSystem.get_current_state()
	)
	var spatial_index_a: Dictionary = spatial_state_a.citizen_ids_by_tile
	var mover_ids_a: Array[int] = [101]
	var movement_events_a: Array = [{"marker": "A"}]
	var task_ids_a: Array[int] = [101]
	var access_cache_a: Dictionary = {101: {"marker": "A"}}
	CityCitizenMovementRuntimeSystem.get_current_state().active_mover_ids = mover_ids_a
	CityCitizenMovementRuntimeSystem.get_current_state().active_mover_id_lookup = {101: true}
	CityCitizenMovementRuntimeSystem.get_current_state().citizen_movement_visual_events = movement_events_a
	CityCitizenMovementRuntimeSystem.get_current_state().citizen_movement_visual_tick_index = 101
	CityCitizenTaskRuntimeSystem.get_current_state().active_task_ids = task_ids_a
	CityCitizenTaskRuntimeSystem.get_current_state().active_task_id_lookup = {101: true}
	WorldData.city_object_access_tile_cache = access_cache_a
	CityCitizenMovementRuntimeSystem.get_current_state().citizen_movement_version = 11
	CityCitizenTaskRuntimeSystem.get_current_state().citizen_task_version = 13
	CityAssignmentSystem.get_current_state().assignment_version = 15
	CityEmploymentSystem.get_current_state().workplace_version = 17

	_expect(
		int(citizen_a.get("id", -1)) == 1
		and spatial_state_a.citizen_spatial_version == 1
		and spatial_index_a.get(SHARED_CITIZEN_TILE, []) == [1],
		"City A must own local citizen 1 at the shared coordinate."
	)

	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id),
		"City B must become active."
	)
	WorldData.official_city_world = _make_world(16, 16, 100_202)
	WorldData.official_city_seed = 100_202
	var citizen_b := WorldData.add_city_citizen(
		"",
		SHARED_CITIZEN_TILE,
		WorldData.CITY_CITIZEN_SEX_FEMALE,
		culture_id
	)
	var registry_b := (
		CityCitizenRegistrySystem.get_current_state()
	)
	var spatial_state_b := (
		CityCitizenSpatialSystem.get_current_state()
	)
	var spatial_index_b: Dictionary = spatial_state_b.citizen_ids_by_tile
	_expect(
		int(citizen_b.get("id", -1)) == 1
		and spatial_state_b.citizen_spatial_version
		== spatial_state_a.citizen_spatial_version
		and spatial_index_b.get(SHARED_CITIZEN_TILE, []) == [1]
		and not is_same(spatial_state_b, spatial_state_a)
		and not is_same(spatial_index_b, spatial_index_a),
		"City B must independently reuse ID, coordinate, and spatial version."
	)

	_test_renderer_identity_invalidation(
		city_b_id,
		registry_b,
		spatial_state_b
	)
	_test_validator_identity_invalidation(city_b_id, spatial_state_b)

	var mover_ids_b: Array[int] = [202]
	var movement_events_b: Array = [{"marker": "B"}]
	var task_ids_b: Array[int] = [202]
	var access_cache_b: Dictionary = {202: {"marker": "B"}}
	CityCitizenMovementRuntimeSystem.get_current_state().active_mover_ids = mover_ids_b
	CityCitizenMovementRuntimeSystem.get_current_state().active_mover_id_lookup = {202: true}
	CityCitizenMovementRuntimeSystem.get_current_state().citizen_movement_visual_events = movement_events_b
	CityCitizenMovementRuntimeSystem.get_current_state().citizen_movement_visual_tick_index = 202
	CityCitizenTaskRuntimeSystem.get_current_state().active_task_ids = task_ids_b
	CityCitizenTaskRuntimeSystem.get_current_state().active_task_id_lookup = {202: true}
	WorldData.city_object_access_tile_cache = access_cache_b
	CityCitizenMovementRuntimeSystem.get_current_state().citizen_movement_version = 12
	CityCitizenTaskRuntimeSystem.get_current_state().citizen_task_version = 14
	CityAssignmentSystem.get_current_state().assignment_version = 16
	CityEmploymentSystem.get_current_state().workplace_version = 18

	_expect(
		WorldPoliticalState.set_active_settlement(city_a_id)
		and is_same(
			CityCitizenRegistrySystem.get_current_state(),
			registry_a
		)
		and is_same(
			CityCitizenSpatialSystem.get_current_state(),
			spatial_state_a
		)
		and is_same(CityCitizenSpatialSystem.get_current_state().citizen_ids_by_tile, spatial_index_a)
		and CityCitizenSpatialSystem.get_current_state().citizen_spatial_version == 1
		and is_same(CityCitizenMovementRuntimeSystem.get_current_state().active_mover_ids, mover_ids_a)
		and is_same(
			CityCitizenMovementRuntimeSystem.get_current_state().citizen_movement_visual_events,
			movement_events_a
		)
		and is_same(CityCitizenTaskRuntimeSystem.get_current_state().active_task_ids, task_ids_a)
		and is_same(WorldData.city_object_access_tile_cache, access_cache_a)
		and CityCitizenMovementRuntimeSystem.get_current_state().citizen_movement_version == 11
		and CityCitizenTaskRuntimeSystem.get_current_state().citizen_task_version == 13
		and CityAssignmentSystem.get_current_state().assignment_version == 15
		and CityEmploymentSystem.get_current_state().workplace_version == 17,
		"A -> B -> A must restore City A's exact owners and deferred runtime."
	)
	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id)
		and is_same(
			CityCitizenSpatialSystem.get_current_state(),
			spatial_state_b
		)
		and is_same(CityCitizenSpatialSystem.get_current_state().citizen_ids_by_tile, spatial_index_b)
		and CityCitizenSpatialSystem.get_current_state().citizen_spatial_version == 1
		and is_same(CityCitizenMovementRuntimeSystem.get_current_state().active_mover_ids, mover_ids_b)
		and is_same(
			CityCitizenMovementRuntimeSystem.get_current_state().citizen_movement_visual_events,
			movement_events_b
		)
		and is_same(CityCitizenTaskRuntimeSystem.get_current_state().active_task_ids, task_ids_b)
		and is_same(WorldData.city_object_access_tile_cache, access_cache_b)
		and CityCitizenMovementRuntimeSystem.get_current_state().citizen_movement_version == 12
		and CityCitizenTaskRuntimeSystem.get_current_state().citizen_task_version == 14
		and CityAssignmentSystem.get_current_state().assignment_version == 16
		and CityEmploymentSystem.get_current_state().workplace_version == 18,
		"A -> B -> A -> B must leave City B unchanged."
	)

	var city_a_root = WorldPoliticalState.get_city_simulation_state(city_a_id)
	var city_b_root = WorldPoliticalState.get_city_simulation_state(city_b_id)
	_expect(
		city_a_root is CitySettlementSimulationState
		and city_b_root is CitySettlementSimulationState
		and is_same(city_a_root.citizen_spatial_state, spatial_state_a)
		and is_same(city_b_root.citizen_spatial_state, spatial_state_b)
		and not is_same(
			city_a_root.citizen_movement_runtime_state,
			city_b_root.citizen_movement_runtime_state
		)
		and is_same(
			city_a_root.citizen_movement_runtime_state.active_mover_ids,
			mover_ids_a
		)
		and is_same(
			city_b_root.citizen_movement_runtime_state.active_mover_ids,
			mover_ids_b
		)
		and is_same(
			city_a_root.citizen_task_runtime_state.active_task_ids,
			task_ids_a
		)
		and is_same(
			city_b_root.citizen_task_runtime_state.active_task_ids,
			task_ids_b
		)
		and is_same(city_a_root.object_access_tile_cache, access_cache_a)
		and is_same(city_b_root.object_access_tile_cache, access_cache_b),
		"Spatial, movement, and task owners must remain separate from the "
		+ "access-cache root."
	)


func _test_renderer_identity_invalidation(
	city_id: int,
	registry_state: CityCitizenRegistryState,
	original_spatial_state: CityCitizenSpatialState
) -> void:
	var renderer := CityRenderer.new()
	renderer.observed_city_citizen_registry_state = registry_state
	renderer.observed_city_citizen_version = registry_state.citizen_version
	renderer.observed_city_citizen_spatial_state = original_spatial_state
	renderer.observed_city_citizen_spatial_version = (
		original_spatial_state.citizen_spatial_version
	)
	renderer.observed_city_citizen_movement_version = (
		CityCitizenMovementRuntimeSystem.get_current_state().citizen_movement_version
	)
	renderer.observed_city_citizen_movement_runtime_state = (
		CityCitizenMovementRuntimeSystem.get_current_state()
	)
	var replacement_state := _clone_spatial_state(original_spatial_state)
	var city_root = WorldPoliticalState.get_city_simulation_state(city_id)
	city_root.citizen_spatial_state = replacement_state
	var change_flags: Dictionary = {}
	renderer._collect_world_data_change_flags(change_flags)
	_expect(
		bool(change_flags.get("city_citizen_spatial_changed", false))
		and not bool(change_flags.get("city_citizens_changed", false))
		and not bool(change_flags.get("city_citizen_movement_changed", false))
		and is_same(
			renderer.observed_city_citizen_spatial_state,
			replacement_state
		)
		and renderer.observed_city_citizen_spatial_version
		== original_spatial_state.citizen_spatial_version,
		"Renderer refresh must include spatial identity at equal versions."
	)
	city_root.citizen_spatial_state = original_spatial_state
	renderer.free()


func _test_validator_identity_invalidation(
	city_id: int,
	original_spatial_state: CityCitizenSpatialState
) -> void:
	var first_validation := CityStateValidatorScript.validate(true, false)
	var replacement_state := _clone_spatial_state(original_spatial_state)
	replacement_state.citizen_ids_by_tile.clear()
	var city_root = WorldPoliticalState.get_city_simulation_state(city_id)
	city_root.citizen_spatial_state = replacement_state
	var second_validation := CityStateValidatorScript.validate(false, false)
	_expect(
		int(first_validation.get(
			"citizen_spatial_state_instance_id",
			-1
		)) == int(original_spatial_state.get_instance_id())
		and int(second_validation.get(
			"citizen_spatial_state_instance_id",
			-1
		)) == int(replacement_state.get_instance_id())
		and _contains_error_fragment(
			second_validation.get("errors", []),
			"missing from the spatial index"
		),
		"Validator cache must invalidate and inspect equal-version replacement."
	)
	city_root.citizen_spatial_state = original_spatial_state
	CityStateValidatorScript.validate(true, false)


func _contains_error_fragment(raw_errors, fragment: String) -> bool:
	if not raw_errors is Array:
		return false
	for raw_error in raw_errors:
		if fragment in str(raw_error):
			return true
	return false


func _clone_spatial_state(
	source: CityCitizenSpatialState
) -> CityCitizenSpatialState:
	var clone := CityCitizenSpatialState.new()
	clone.citizen_ids_by_tile = source.citizen_ids_by_tile.duplicate(true)
	clone.citizen_spatial_version = source.citizen_spatial_version
	return clone


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
	push_error("City citizen-spatial isolation test: " + message)
