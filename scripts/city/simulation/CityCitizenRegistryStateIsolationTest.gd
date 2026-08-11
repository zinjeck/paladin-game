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
	var city_a := _create_city(
		"Citizen Registry City A",
		polity_id,
		Vector2i(1, 1)
	)
	var city_b := _create_city(
		"Citizen Registry City B",
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
	WorldPoliticalState.set_current_city_world(_make_world(16, 16, 97_101))
	WorldPoliticalState.set_current_city_seed(97_101)
	var citizen_a := WorldData.add_city_citizen(
		"",
		SHARED_CITIZEN_TILE,
		WorldData.CITY_CITIZEN_SEX_MALE,
		culture_id
	)
	var state_a := (
		CityCitizenRegistrySystem.get_current_state()
	)
	var citizens_a: Array = state_a.citizens
	var index_a: Dictionary = state_a.citizen_index_by_id
	var spatial_a: Dictionary = CityCitizenSpatialSystem.get_current_state().citizen_ids_by_tile
	var version_a := state_a.citizen_version
	var next_id_a := state_a.next_citizen_id
	var mover_ids_a: Array[int] = [101]
	var mover_lookup_a: Dictionary = {101: true}
	var movement_events_a: Array = [{"marker": "A"}]
	var task_ids_a: Array[int] = [101]
	var task_lookup_a: Dictionary = {101: true}
	var access_cache_a: Dictionary = {101: {"marker": "A"}}
	CityCitizenMovementRuntimeSystem.get_current_state().active_mover_ids = mover_ids_a
	CityCitizenMovementRuntimeSystem.get_current_state().active_mover_id_lookup = mover_lookup_a
	CityCitizenMovementRuntimeSystem.get_current_state().citizen_movement_visual_events = movement_events_a
	CityCitizenMovementRuntimeSystem.get_current_state().citizen_movement_visual_tick_index = 101
	CityCitizenTaskRuntimeSystem.get_current_state().active_task_ids = task_ids_a
	CityCitizenTaskRuntimeSystem.get_current_state().active_task_id_lookup = task_lookup_a
	CityNavigationSystem.get_current_state().object_access_tile_cache = access_cache_a
	CityCitizenMovementRuntimeSystem.get_current_state().citizen_movement_version = 11
	CityCitizenTaskRuntimeSystem.get_current_state().citizen_task_version = 13
	CityAssignmentSystem.get_current_state().assignment_version = 15
	CityEmploymentSystem.get_current_state().workplace_version = 17

	_expect(
		int(citizen_a.get("id", -1)) == 1
		and version_a == 1
		and next_id_a == 2
		and int(index_a.get(1, -1)) == 0
		and spatial_a.get(SHARED_CITIZEN_TILE, []) == [1],
		"City A must own local citizen 1 at the shared coordinate."
	)
	if citizens_a.is_empty():
		return

	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id),
		"City B must become active."
	)
	WorldPoliticalState.set_current_city_world(_make_world(16, 16, 97_202))
	WorldPoliticalState.set_current_city_seed(97_202)
	var citizen_b := WorldData.add_city_citizen(
		"",
		SHARED_CITIZEN_TILE,
		WorldData.CITY_CITIZEN_SEX_FEMALE,
		culture_id
	)
	var state_b := (
		CityCitizenRegistrySystem.get_current_state()
	)
	var citizens_b: Array = state_b.citizens
	var index_b: Dictionary = state_b.citizen_index_by_id
	var spatial_b: Dictionary = CityCitizenSpatialSystem.get_current_state().citizen_ids_by_tile

	_expect(
		int(citizen_b.get("id", -1)) == 1
		and state_b.citizen_version == version_a
		and state_b.next_citizen_id == next_id_a
		and int(index_b.get(1, -1)) == 0
		and spatial_b.get(SHARED_CITIZEN_TILE, []) == [1],
		"City B must independently reuse citizen ID 1 and the same coordinate."
	)
	if citizens_b.is_empty():
		return
	_expect(
		not is_same(state_b, state_a)
		and not is_same(citizens_b, citizens_a)
		and not is_same(index_b, index_a)
		and not is_same(spatial_b, spatial_a)
		and str(citizens_a[0].get("sex", ""))
		== WorldData.CITY_CITIZEN_SEX_MALE
		and str(citizens_b[0].get("sex", ""))
		== WorldData.CITY_CITIZEN_SEX_FEMALE,
		"Equal local IDs, coordinates, and versions must not alias City state."
	)

	_test_renderer_identity_invalidation(city_b_id, state_b)
	_test_validator_identity_invalidation(city_b_id, state_b)
	var mover_ids_b: Array[int] = [202]
	var mover_lookup_b: Dictionary = {202: true}
	var movement_events_b: Array = [{"marker": "B"}]
	var task_ids_b: Array[int] = [202]
	var task_lookup_b: Dictionary = {202: true}
	var access_cache_b: Dictionary = {202: {"marker": "B"}}
	CityCitizenMovementRuntimeSystem.get_current_state().active_mover_ids = mover_ids_b
	CityCitizenMovementRuntimeSystem.get_current_state().active_mover_id_lookup = mover_lookup_b
	CityCitizenMovementRuntimeSystem.get_current_state().citizen_movement_visual_events = movement_events_b
	CityCitizenMovementRuntimeSystem.get_current_state().citizen_movement_visual_tick_index = 202
	CityCitizenTaskRuntimeSystem.get_current_state().active_task_ids = task_ids_b
	CityCitizenTaskRuntimeSystem.get_current_state().active_task_id_lookup = task_lookup_b
	CityNavigationSystem.get_current_state().object_access_tile_cache = access_cache_b
	CityCitizenMovementRuntimeSystem.get_current_state().citizen_movement_version = 12
	CityCitizenTaskRuntimeSystem.get_current_state().citizen_task_version = 14
	CityAssignmentSystem.get_current_state().assignment_version = 16
	CityEmploymentSystem.get_current_state().workplace_version = 18

	_expect(
		WorldPoliticalState.set_active_settlement(city_a_id)
		and is_same(
			CityCitizenRegistrySystem.get_current_state(),
			state_a
		)
		and is_same(CityCitizenRegistrySystem.get_current_state().citizens, citizens_a)
		and is_same(CityCitizenRegistrySystem.get_current_state().citizen_index_by_id, index_a)
		and is_same(CityCitizenSpatialSystem.get_current_state().citizen_ids_by_tile, spatial_a)
		and is_same(CityCitizenMovementRuntimeSystem.get_current_state().active_mover_ids, mover_ids_a)
		and is_same(CityCitizenMovementRuntimeSystem.get_current_state().active_mover_id_lookup, mover_lookup_a)
		and is_same(
			CityCitizenMovementRuntimeSystem.get_current_state().citizen_movement_visual_events,
			movement_events_a
		)
		and CityCitizenMovementRuntimeSystem.get_current_state().citizen_movement_visual_tick_index == 101
		and is_same(CityCitizenTaskRuntimeSystem.get_current_state().active_task_ids, task_ids_a)
		and is_same(CityCitizenTaskRuntimeSystem.get_current_state().active_task_id_lookup, task_lookup_a)
		and is_same(CityNavigationSystem.get_current_state().object_access_tile_cache, access_cache_a)
		and CityCitizenMovementRuntimeSystem.get_current_state().citizen_movement_version == 11
		and CityCitizenTaskRuntimeSystem.get_current_state().citizen_task_version == 13
		and CityAssignmentSystem.get_current_state().assignment_version == 15
		and CityEmploymentSystem.get_current_state().workplace_version == 17
		and CityCitizenRegistrySystem.get_current_state().next_citizen_id == next_id_a
		and CityCitizenRegistrySystem.get_current_state().citizen_version == version_a
		and str(CityCitizenRegistrySystem.get_current_state().citizens[0].get("sex", ""))
		== WorldData.CITY_CITIZEN_SEX_MALE,
		"A -> B -> A must restore City A's exact registry and spatial workspace."
	)
	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id)
		and is_same(
			CityCitizenRegistrySystem.get_current_state(),
			state_b
		)
		and is_same(CityCitizenRegistrySystem.get_current_state().citizens, citizens_b)
		and is_same(CityCitizenRegistrySystem.get_current_state().citizen_index_by_id, index_b)
		and is_same(CityCitizenSpatialSystem.get_current_state().citizen_ids_by_tile, spatial_b)
		and is_same(CityCitizenMovementRuntimeSystem.get_current_state().active_mover_ids, mover_ids_b)
		and is_same(CityCitizenMovementRuntimeSystem.get_current_state().active_mover_id_lookup, mover_lookup_b)
		and is_same(
			CityCitizenMovementRuntimeSystem.get_current_state().citizen_movement_visual_events,
			movement_events_b
		)
		and CityCitizenMovementRuntimeSystem.get_current_state().citizen_movement_visual_tick_index == 202
		and is_same(CityCitizenTaskRuntimeSystem.get_current_state().active_task_ids, task_ids_b)
		and is_same(CityCitizenTaskRuntimeSystem.get_current_state().active_task_id_lookup, task_lookup_b)
		and is_same(CityNavigationSystem.get_current_state().object_access_tile_cache, access_cache_b)
		and CityCitizenMovementRuntimeSystem.get_current_state().citizen_movement_version == 12
		and CityCitizenTaskRuntimeSystem.get_current_state().citizen_task_version == 14
		and CityAssignmentSystem.get_current_state().assignment_version == 16
		and CityEmploymentSystem.get_current_state().workplace_version == 18
		and CityCitizenRegistrySystem.get_current_state().next_citizen_id == 2
		and CityCitizenRegistrySystem.get_current_state().citizen_version == 1
		and str(CityCitizenRegistrySystem.get_current_state().citizens[0].get("sex", ""))
		== WorldData.CITY_CITIZEN_SEX_FEMALE,
		"A -> B -> A -> B must leave City B's registry unchanged."
	)

	var city_a_root = WorldPoliticalState.get_city_simulation_state(city_a_id)
	var city_b_root = WorldPoliticalState.get_city_simulation_state(city_b_id)
	_expect(
		city_a_root is CitySettlementSimulationState
		and city_b_root is CitySettlementSimulationState
		and is_same(city_a_root.citizen_registry_state, state_a)
		and is_same(city_b_root.citizen_registry_state, state_b)
		and not is_same(
			city_a_root.citizen_spatial_state,
			city_b_root.citizen_spatial_state
		)
		and is_same(
			city_a_root.citizen_spatial_state.citizen_ids_by_tile,
			spatial_a
		)
		and is_same(
			city_b_root.citizen_spatial_state.citizen_ids_by_tile,
			spatial_b
		)
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
		),
		"Registry, spatial, movement, and task owners must remain isolated."
	)


func _test_renderer_identity_invalidation(
	city_id: int,
	original_state: CityCitizenRegistryState
) -> void:
	var renderer := CityRenderer.new()
	renderer.observed_city_citizen_registry_state = original_state
	renderer.observed_city_citizen_version = original_state.citizen_version
	renderer.observed_city_citizen_movement_version = (
		CityCitizenMovementRuntimeSystem.get_current_state().citizen_movement_version - 1
	)
	renderer.observed_city_citizen_movement_runtime_state = (
		CityCitizenMovementRuntimeSystem.get_current_state()
	)
	renderer.city_citizen_movement_presentation.movement_snapshot_by_citizen_id = {
		1: {"marker": "old-city"},
	}
	renderer.city_citizen_movement_presentation.visual_position_by_citizen_id = {
		1: Vector2(99.0, 99.0),
	}
	renderer.city_citizen_movement_presentation.transition_by_citizen_id = {
		1: {"marker": "old-city"},
	}
	renderer.city_citizen_movement_presentation.tracked_mover_id_lookup = {
		1: true,
	}
	var replacement_state := _clone_registry_state(original_state)
	var city_root = WorldPoliticalState.get_city_simulation_state(city_id)
	city_root.citizen_registry_state = replacement_state
	var change_flags: Dictionary = {}
	renderer._collect_world_data_change_flags(change_flags)
	_expect(
		bool(change_flags.get("city_citizens_changed", false))
		and bool(change_flags.get("city_citizen_registry_changed", false))
		and bool(change_flags.get("city_citizen_movement_changed", false))
		and is_same(
			renderer.observed_city_citizen_registry_state,
			replacement_state
		)
		and renderer.observed_city_citizen_version
		== original_state.citizen_version,
		"Renderer refresh must include registry identity when versions are equal."
	)
	renderer._synchronize_city_citizen_movement(change_flags)
	_expect(
		renderer
		.city_citizen_movement_presentation
		.movement_snapshot_by_citizen_id.is_empty()
		and renderer
		.city_citizen_movement_presentation
		.visual_position_by_citizen_id.is_empty()
		and renderer
		.city_citizen_movement_presentation
		.transition_by_citizen_id.is_empty()
		and renderer
		.city_citizen_movement_presentation
		.tracked_mover_id_lookup.is_empty()
		and renderer.synchronized_city_citizen_movement_version
		== CityCitizenMovementRuntimeSystem.get_current_state().citizen_movement_version,
		"A registry switch must discard old-City cosmetic movement by local ID."
	)
	city_root.citizen_registry_state = original_state
	renderer.free()


func _test_validator_identity_invalidation(
	city_id: int,
	original_state: CityCitizenRegistryState
) -> void:
	var first_validation := CityStateValidatorScript.validate(true, false)
	var replacement_state := _clone_registry_state(original_state)
	var city_root = WorldPoliticalState.get_city_simulation_state(city_id)
	city_root.citizen_registry_state = replacement_state
	var second_validation := CityStateValidatorScript.validate(false, false)
	_expect(
		int(first_validation.get(
			"citizen_registry_state_instance_id",
			-1
		)) == int(original_state.get_instance_id())
		and int(second_validation.get(
			"citizen_registry_state_instance_id",
			-1
		)) == int(replacement_state.get_instance_id())
		and int(first_validation.get(
			"citizen_registry_state_instance_id",
			-1
		)) != int(second_validation.get(
			"citizen_registry_state_instance_id",
			-1
		)),
		"Validator caching must invalidate on an equal-version owner replacement."
	)
	city_root.citizen_registry_state = original_state
	CityStateValidatorScript.validate(true, false)


func _clone_registry_state(
	source: CityCitizenRegistryState
) -> CityCitizenRegistryState:
	var clone := CityCitizenRegistryState.new()
	clone.citizens = source.citizens.duplicate(true)
	clone.citizen_index_by_id = source.citizen_index_by_id.duplicate(true)
	clone.next_citizen_id = source.next_citizen_id
	clone.citizen_version = source.citizen_version
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
	push_error("City citizen-registry isolation test: " + message)
